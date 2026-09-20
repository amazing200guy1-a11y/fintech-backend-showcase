"""
Mehd AI — Authentication Dependencies
=======================================
Shared auth logic used by all route files.
"""

from __future__ import annotations

import base64
import json
import logging
import time
from fastapi import Depends, Header, HTTPException, Request

logger = logging.getLogger("mehd.auth")

# Secure UID masking for logs
from log_utils import safe_uid, safe_email

def get_real_ip(request: Request) -> str:
    """Extracts the real client IP, bypassing proxy headers correctly.

    SECURITY: We use the RIGHTMOST IP in X-Forwarded-For.
    Each proxy APPENDS the upstream address, so:
      - Legitimate: X-Forwarded-For: CLIENT_IP  (Railway adds it)
      - Spoofed:    X-Forwarded-For: FAKE_IP, CLIENT_IP  (attacker prepends FAKE_IP; Railway still appends the real one)
    Taking the last value means an attacker's injected IPs are ignored.
    X-Real-IP (set by nginx/Cloudflare as a single authoritative value) is
    preferred when available as it cannot be spoofed by the client at all.
    """
    # Prefer X-Real-IP — single authoritative value from a trusted proxy
    real_ip = request.headers.get("x-real-ip", "").strip()
    if real_ip:
        return real_ip

    # Fall back to rightmost X-Forwarded-For entry (our platform's ingress adds it last)
    forwarded_for = request.headers.get("x-forwarded-for", "")
    if forwarded_for:
        ips = [ip.strip() for ip in forwarded_for.split(",")]
        return ips[-1]  # rightmost = added by trusted platform proxy

    return request.client.host if request.client else "127.0.0.1"


def get_uid_rate_key(request: Request) -> str:
    """Extract user identity for rate limiting on authenticated endpoints.

    Decodes the JWT payload (base64 only — no cryptographic verification)
    to extract the UID. This is safe because:
      - Authentication is STILL enforced by Firebase in get_current_user().
      - This function is ONLY used as a rate-limit bucket identifier.
      - Even if an attacker forges a JWT with a fake UID, they just get
        their own isolated rate-limit bucket (which is the correct behavior).

    Falls back to IP-based keying for unauthenticated requests.
    """
    auth_header = request.headers.get("authorization", "")
    if auth_header.lower().startswith("bearer "):
        try:
            token = auth_header[7:]
            # JWT structure: header.payload.signature — we only need the payload
            payload_b64 = token.split(".")[1]
            # Add padding for base64 decoding
            payload_b64 += "=" * (4 - len(payload_b64) % 4)
            payload = json.loads(base64.urlsafe_b64decode(payload_b64))
            uid = payload.get("user_id") or payload.get("sub", "")
            if uid:
                return f"uid:{uid}"
            # UID field missing from a structurally valid JWT — log and fall back
            logger.warning(
                "RATE_KEY_FALLBACK: JWT parsed but no user_id/sub claim found. "
                "Falling back to IP-based limiting. This may indicate a token forge attempt."
            )
        except Exception as e:
            # FIX: Log the fallback so silent IP-bypass attempts are visible in logs.
            logger.warning(
                "RATE_KEY_FALLBACK: JWT parsing failed (%s). Falling back to IP-based limiting. "
                "Repeated occurrences may indicate a bypass attempt.", e
            )
    return get_real_ip(request)


from cachetools import LRUCache

_lock_cache = LRUCache(maxsize=10000)
LOCK_CACHE_TTL = 5  # seconds (reduced from 30s to minimize post-ban attack window)

# Revocation result TTL cache — prevents Firebase Admin SDK cost-attack via
# hammering 10,000 revoked tokens (each call = one Firebase API round-trip).
# Cache: uid → {"revoked": bool, "checked_at": float}
_revocation_cache = LRUCache(maxsize=10000)
REVOCATION_CACHE_TTL = 60  # seconds: re-check Firebase at most once per minute per UID

# Tracking Failed Logins for MFA Fatigue Defense (Sniper DoS fix)
# L1 cache — flushed to persistent storage on every write
_failed_logins = LRUCache(maxsize=10000)

async def record_failed_login(email: str) -> None:
    """Records a failed login attempt and locks the account if 3 failures occur within 10 minutes.
    
    SECURITY HARDENED: 
    1. Counters are persisted to storage so they survive server restarts.
    2. Wrapped in a distributed lock to prevent TOCTOU race conditions.
    """
    from datetime import datetime, timedelta, timezone
    from storage import storage
    
    lock_key = f"failed_login_{email}"
    acquired = await storage.acquire_lock(lock_key, ttl_seconds=10)
    if not acquired:
        # If another instance is updating this email right now, let it.
        # We can either retry or just return. Returning is safer for DoS prevention.
        _masked_email = email[:2] + "***@***" + email.split("@")[-1][-3:] if "@" in email else "***"
        logger.warning("Could not acquire lock for %s - concurrent login failure being processed.", _masked_email)
        return

    try:
        now = datetime.now(timezone.utc)
        
        # Load from persistent storage if not in L1 cache
        if email not in _failed_logins:
            persisted = await storage.get("failed_logins", email)
            if persisted and persisted.get("first_failure"):
                first_failure = datetime.fromisoformat(persisted["first_failure"])
                if first_failure.tzinfo is None:
                    first_failure = first_failure.replace(tzinfo=timezone.utc)
                if (now - first_failure) < timedelta(minutes=10):
                    _failed_logins[email] = {"count": persisted.get("count", 0), "first_failure": first_failure}
        
        if email not in _failed_logins:
            _failed_logins[email] = {"count": 1, "first_failure": now}
        else:
            # Reset counter if the first failure was more than 10 minutes ago
            if (now - _failed_logins[email]["first_failure"]) > timedelta(minutes=10):
                 _failed_logins[email] = {"count": 1, "first_failure": now}
            else:
                 _failed_logins[email]["count"] += 1
        
        # Persist to storage (survives restarts)
        await storage.set("failed_logins", email, {
            "count": _failed_logins[email]["count"],
            "first_failure": _failed_logins[email]["first_failure"].isoformat(),
        })
                 
        if _failed_logins[email]["count"] >= 3:
            try:
                from firebase_admin import auth as fb_auth, firestore
                user_record = fb_auth.get_user_by_email(email)
                uid = user_record.uid
                
                unlock_time = now + timedelta(minutes=30)
                
                # 1. Update Firestore
                db = firestore.client()
                db.collection("users").document(uid).update({
                    "is_locked": True,
                    "lock_reason": "MFA_FATIGUE_ATTACK_DETECTED",
                    "locked_until": unlock_time.isoformat()
                })
                
                # 2. Update High-Speed Storage (Phantom Lock)
                await storage.set("auth_locks", uid, {"locked_until": unlock_time.isoformat()})
                
                # 3. Clear both local + persistent trackers
                del _failed_logins[email]
                await storage.delete("failed_logins", email)
                logger.critical("UBER TRAP TRIGGERED (Internal): Account %s locked for 30 mins due to 3 failed MFA/login attempts.", safe_uid(uid))
            except Exception as e:
                 logger.error("Error during internal lockdown trigger for %s: %s", email, e)
    finally:
        await storage.release_lock(lock_key)


async def _check_phantom_lock(uid: str) -> None:
    """
    Checks the Phantom Lock status using a fast in-memory TTL cache.
    Prevents overwhelming the database on every API call.
    """
    from storage import storage
    from datetime import datetime, timezone

    now_ts = time.time()
    cached = _lock_cache.get(uid)
    
    if cached and (now_ts - cached["checked_at"] < LOCK_CACHE_TTL):
        locked_until = cached["locked_until"]
    else:
        lock_data = await storage.get("auth_locks", uid)
        locked_until = None
        if lock_data and lock_data.get("locked_until"):
            locked_until = datetime.fromisoformat(lock_data.get("locked_until"))
            if locked_until.tzinfo is None:
                locked_until = locked_until.replace(tzinfo=timezone.utc)
            
        _lock_cache[uid] = {"locked_until": locked_until, "checked_at": now_ts}
        
        # Cleanup expired DB locks
        if lock_data and locked_until and datetime.now(timezone.utc) >= locked_until:
            await storage.delete("auth_locks", uid)
            _lock_cache[uid]["locked_until"] = None
            locked_until = None

    if locked_until and datetime.now(timezone.utc) < locked_until:
        logger.critical("PHANTOM LOCK BLOCKED: Compromised or locked JWT attempted access for UID: %s", safe_uid(uid))
        raise HTTPException(
            status_code=403, 
            detail="Account is temporarily locked due to security protocols. All API access revoked."
        )


async def get_current_user(authorization: str = Header(None)) -> str:
    """
    Extracts and verifies the user ID from the Authorization header.
    In DEMO_MODE, returns a sovereign demo user ID if no credentials are provided.
    """
    from state import DEMO_MODE
    if not authorization:
        if DEMO_MODE:
            return "demo_sovereign_trader"
        raise HTTPException(status_code=401, detail="Not authenticated")

    try:
        from firebase_admin import auth as fb_auth

        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not token:
            if DEMO_MODE:
                return "demo_sovereign_trader"
            raise HTTPException(status_code=401, detail="Invalid authorization format")

        # SECURITY: Check revocation result cache first to avoid a Firebase Admin
        # SDK call on every request. Cache TTL = 60s. An attacker with 10k revoked
        # tokens cannot use check_revoked as a Firebase API cost-attack vector.
        # We still verify the JWT signature fully on every request.
        # WAR PREP: Wrapped in to_thread to prevent blocking the async event loop during mass logins.
        import asyncio
        decoded = await asyncio.to_thread(fb_auth.verify_id_token, token, check_revoked=False)  # sig-only first
        uid = decoded["uid"]

        now_ts = time.time()
        cached_rev = _revocation_cache.get(uid)
        if cached_rev is None or (now_ts - cached_rev["checked_at"]) > REVOCATION_CACHE_TTL:
            # Full revocation check — hits Firebase SDK (Network call)
            await asyncio.to_thread(fb_auth.verify_id_token, token, check_revoked=True)
            _revocation_cache[uid] = {"checked_at": now_ts}

        # SECURITY (VULN-05): The Phantom Lock Defense
        await _check_phantom_lock(uid)

        return uid
    except HTTPException:
        raise
    except Exception:
        if DEMO_MODE:
            return "demo_sovereign_trader"
        raise HTTPException(status_code=401, detail="Invalid token")

async def get_current_user_mfa(authorization: str = Header(None)) -> str:
    """
    Extracts user ID and STRICTLY ENFORCES Multi-Factor Authentication.
    If the JWT token lacks the 'sign_in_second_factor' claim, access is denied.
    In DEMO_MODE, returns a sovereign demo user ID.
    """
    from state import DEMO_MODE
    if not authorization:
        if DEMO_MODE:
            return "demo_sovereign_trader"
        raise HTTPException(status_code=401, detail="Not authenticated")

    try:
        from firebase_admin import auth as fb_auth

        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not token:
            if DEMO_MODE:
                return "demo_sovereign_trader"
            raise HTTPException(status_code=401, detail="Invalid authorization format")
        
        import asyncio
        decoded = await asyncio.to_thread(fb_auth.verify_id_token, token, check_revoked=True)
        
        # VERIFY MFA CLAIM
        firebase_claims = decoded.get("firebase", {})
        sign_in_second_factor = firebase_claims.get("sign_in_second_factor")
        
        if not sign_in_second_factor:
            if DEMO_MODE:
                return "demo_sovereign_trader"
            logger.warning(f"MFA Bypass Attempt Blocked for UID: {safe_uid(decoded.get('uid', ''))}")
            raise HTTPException(
                status_code=403, 
                detail="MFA Required. Please verify your identity with an Authenticator App."
            )
            
        uid = decoded["uid"]
        
        # SECURITY (VULN-05): The Phantom Lock Defense (MFA Route)
        await _check_phantom_lock(uid)
                    
        return uid
    except HTTPException:
        raise
    except Exception as e:
        if DEMO_MODE:
            return "demo_sovereign_trader"
        logger.error(f"MFA Token Verification Failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid token")

async def get_sovereign_user(uid: str = Depends(get_current_user_mfa)) -> str:
    """
    STRICT ROLE-BASED ACCESS CONTROL (RBAC) - Defeats the Twitter 'God Mode' Hack.
    Even if a user has a valid password and MFA, they cannot access Admin routes
    unless their database profile explicitly grants them SOVEREIGN status.
    """
    try:
        from firebase_admin import firestore
        import asyncio
        db = firestore.client()
        user_doc = await asyncio.to_thread(db.collection("users").document(uid).get)
        
        if not user_doc.exists:
            logger.critical(f"RBAC Block: Ghost user {safe_uid(uid)} tried to access Sovereign route.")
            raise HTTPException(status_code=403, detail="Sovereign Access Denied.")
            
        user_data = user_doc.to_dict()
        if user_data.get("role") != "SOVEREIGN" and user_data.get("admin") is not True:
            logger.critical(f"RBAC Block: Standard user {safe_uid(uid)} tried to access Sovereign route.")
            raise HTTPException(status_code=403, detail="Sovereign Access Denied.")
            
        return uid
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"RBAC Verification Failed: {e}")
        raise HTTPException(status_code=500, detail="Authorization service unavailable.")


# ──────────────────────────────────────────────
#  Secure Failed Login Recording
#  REPLACES the old /security/trigger-lockdown (removed for DoS vulnerability)
#  This is safe because:
#    1. It only RECORDS a failure, it does NOT lock directly
#    2. The server decides when to lock (3 failures in 10 min)
#    3. Rate-limited to 5/minute to prevent abuse
#    4. Email must exist in Firebase Auth (validated server-side)
# ──────────────────────────────────────────────

from fastapi import APIRouter
from pydantic import BaseModel, Field
from slowapi import Limiter

_auth_limiter = Limiter(key_func=get_real_ip)
auth_router = APIRouter(prefix="/auth", tags=["Auth Security"])


class FailedLoginRequest(BaseModel):
    email: str = Field(..., description="Email of the account that failed login/MFA")


@auth_router.post("/record-failed-login", summary="Record a failed login/MFA attempt")
@_auth_limiter.limit("5/minute")
async def record_failed_login_endpoint(request: Request, req: FailedLoginRequest):
    """
    Restored to allow mobile client to report Firebase auth failures.
    HARDENED: Now strictly enforces Firebase App Check. No fallbacks.
    """
    app_check_token = request.headers.get("X-Firebase-AppCheck")
    if not app_check_token:
        logger.warning(f"App Check missing for {req.email}. Rejecting.")
        raise HTTPException(status_code=403, detail="Unauthorized client. Missing App Check token.")
        
    try:
        from firebase_admin import app_check
        import asyncio
        # Verify the App Check token (Network call)
        await asyncio.to_thread(app_check.verify_token, app_check_token)
    except Exception as e:
        logger.error(f"App Check verification failed for {req.email}: {e}")
        raise HTTPException(status_code=403, detail="Unauthorized client. Invalid App Check token.")

    email = req.email.strip().lower()
    if not email or "@" not in email:
        raise HTTPException(status_code=400, detail="Invalid email.")

    try:
        from firebase_admin import auth as fb_auth
        # Network call to check if email exists
        await asyncio.to_thread(fb_auth.get_user_by_email, email)
    except Exception:
        return {"status": "recorded"}

    await record_failed_login(email)
    return {"status": "recorded"}

