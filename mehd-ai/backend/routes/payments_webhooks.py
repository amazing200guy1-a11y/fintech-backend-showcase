"""
Mehd AI — Payment Webhook Handlers (Paddle v2 + Paystack Dual Gateway)
======================================================================
Production-hardened webhook receiver supporting:
1. Paddle Billing v2 (HMAC-SHA256, 300s freshness window, replay attack defense)
2. Paystack (HMAC-SHA512, constant-time digest verification)
3. Dual-layer idempotency guard (In-memory LRU deque + Persistent Storage)
4. Instant user tier synchronization across all 16 Sovereign assets
"""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import time
from collections import deque
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from auth import get_uid_rate_key
from storage import storage

logger = logging.getLogger("mehd.routes.payments_webhooks")
webhook_router = APIRouter()
limiter = Limiter(key_func=get_uid_rate_key)

# In-memory LRU deque for ultra-fast duplicate event suppression
_processed_event_ids: deque[str] = deque(maxlen=1000)


# ──────────────────────────────────────────────
#  Signature Verification
# ──────────────────────────────────────────────

def _verify_paddle_signature(raw_body: bytes, header: str, secret: str = "") -> bool:
    """
    Verify Paddle v2 HMAC-SHA256 signature.
    Header format: 'ts=1234567;h1=hash'
    Rejects events older than 300 seconds (5 minutes) to defeat replay attacks.
    """
    import routes.payments as p_mod
    if not secret:
        secret = getattr(p_mod, "PADDLE_WEBHOOK_SECRET", "") or os.getenv("PADDLE_WEBHOOK_SECRET", "")
    if not secret or not header:
        return False
    try:
        parts = dict(item.split("=", 1) for item in header.split(";") if "=" in item)
        ts_str = parts.get("ts", "")
        h1 = parts.get("h1", "")
        if not ts_str or not h1:
            return False

        ts_val = int(ts_str)
        now_val = int(time.time())
        if abs(now_val - ts_val) > 300:
            logger.warning("Paddle signature timestamp stale: ts=%d, now=%d", ts_val, now_val)
            return False

        signed_payload = f"{ts_str}:{raw_body.decode('utf-8')}"
        expected = hmac.new(
            secret.encode("utf-8"),
            signed_payload.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, h1)
    except Exception as e:
        logger.warning("Paddle signature verification exception: %s", e)
        return False


def _verify_paystack_signature(raw_body: bytes, header: str, secret: str = "") -> bool:
    """
    Verify Paystack HMAC-SHA512 signature.
    Header contains hexadecimal HMAC-SHA512 hash of raw_body.
    """
    import routes.payments as p_mod
    if not secret:
        secret = getattr(p_mod, "PAYSTACK_SECRET_KEY", "") or os.getenv("PAYSTACK_SECRET_KEY", "")
    if not secret or not header:
        return False
    try:
        expected = hmac.new(
            secret.encode("utf-8"),
            raw_body,
            hashlib.sha512,
        ).hexdigest()
        return hmac.compare_digest(expected.lower(), header.lower())
    except Exception as e:
        logger.warning("Paystack signature verification exception: %s", e)
        return False



# ──────────────────────────────────────────────
#  Idempotency Guards
# ──────────────────────────────────────────────

async def _is_already_processed(event_id: str) -> bool:
    """Check both memory deque and persistent storage for idempotency."""
    if event_id in _processed_event_ids:
        return True
    existing = await storage.get("webhook_events", event_id)
    if existing:
        _processed_event_ids.append(event_id)
        return True
    return False


async def _mark_processed(event_id: str, event_type: str) -> None:
    """Record event in memory deque and persistent storage."""
    _processed_event_ids.append(event_id)
    await storage.set("webhook_events", event_id, {
        "processed_at": datetime.now(timezone.utc).isoformat(),
        "event_type": event_type,
    })


# ──────────────────────────────────────────────
#  Paddle Webhook Endpoint
# ──────────────────────────────────────────────

@webhook_router.post("/paddle-webhook", summary="Paddle v2 webhook handler", include_in_schema=False)
@limiter.limit("100/minute")
async def paddle_webhook(request: Request):
    """
    Handles Paddle v2 subscription events:
    - subscription.created  → new subscription, grant tier
    - subscription.updated  → plan/status change (grant or revoke)
    - subscription.canceled → cancel, downgrade to observer
    """
    import routes.payments as p_mod

    payload = await request.body()
    sig_header = request.headers.get("Paddle-Signature", "")

    if not _verify_paddle_signature(payload, sig_header):
        logger.critical("PADDLE WEBHOOK: Invalid signature — possible tampering or replay")
        raise HTTPException(status_code=400, detail="Invalid webhook signature")

    try:
        event = json.loads(payload)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON payload")

    event_id = event.get("notification_id", "")
    event_type = event.get("event_type", "")
    data = event.get("data", {})

    logger.info("PADDLE WEBHOOK: %s (id: %s)", event_type, event_id)

    if event_id and await _is_already_processed(event_id):
        logger.info("PADDLE WEBHOOK: Duplicate event %s ignored", event_id)
        return {"status": "already_processed"}

    if event_id:
        await _mark_processed(event_id, event_type)

    custom_data = data.get("custom_data") or {}
    uid = custom_data.get("mehd_uid", "")

    if not uid:
        customer_email = data.get("customer", {}).get("email") if isinstance(data.get("customer"), dict) else None
        if customer_email:
            uid = await p_mod._uid_from_email(customer_email)

    if not uid:
        logger.warning("PADDLE WEBHOOK: No mehd_uid found in event %s", event_type)
        return {"status": "no_uid"}

    management_urls = data.get("management_urls") or {}
    portal_urls = {
        "update_payment_method": management_urls.get("update_payment_method", p_mod.PRICING_URL),
        "cancel": management_urls.get("cancel", p_mod.PRICING_URL),
    }

    if event_type in ("subscription.created", "subscription.updated"):
        sub_status = data.get("status", "")
        if sub_status in ("active", "trialing", "past_due"):
            items = data.get("items") or []
            target_tier = None
            for item in items:
                price_id = (item.get("price") or {}).get("id", "")
                target_tier = p_mod.PADDLE_TO_TIER.get(price_id)
                if target_tier:
                    break

            if not target_tier:
                target_tier = custom_data.get("tier")

            if target_tier:
                p_mod.set_user_tier(uid, target_tier, portal_urls)
                logger.info("PADDLE: User %s upgraded to %s (status: %s)", uid, target_tier, sub_status)
            else:
                logger.warning("PADDLE: Unknown price ID in items for user %s", uid)
        elif sub_status in ("canceled", "paused"):
            await p_mod._downgrade_user(uid, f"paddle subscription {sub_status}")

    elif event_type in ("subscription.canceled", "transaction.refunded", "transaction.disputed", "adjustment.created"):
        await p_mod._downgrade_user(uid, f"paddle {event_type}")

    return {"status": "ok"}


# ──────────────────────────────────────────────
#  Paystack Webhook Endpoint
# ──────────────────────────────────────────────

@webhook_router.post("/paystack-webhook", summary="Paystack webhook handler", include_in_schema=False)
@limiter.limit("100/minute")
async def paystack_webhook(request: Request):
    """
    Handles Paystack subscription events:
    - subscription.create   → new subscription, grant tier
    - subscription.disable  → cancellation, downgrade to observer
    - invoice.payment_failed → warn, grace period
    """
    import routes.payments as p_mod

    payload = await request.body()
    sig_header = request.headers.get("x-paystack-signature", "")

    if not _verify_paystack_signature(payload, sig_header):
        logger.critical("PAYSTACK WEBHOOK: Invalid signature — possible tampering")
        raise HTTPException(status_code=400, detail="Invalid webhook signature")

    try:
        event = json.loads(payload)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON payload")

    event_id = str(event.get("id") or int(time.time() * 1000))
    event_type = event.get("event", "")
    data = event.get("data", {})

    logger.info("PAYSTACK WEBHOOK: %s (id: %s)", event_type, event_id)

    if event_id and await _is_already_processed(event_id):
        logger.info("PAYSTACK WEBHOOK: Duplicate event %s ignored", event_id)
        return {"status": "already_processed"}

    if event_id:
        await _mark_processed(event_id, event_type)

    customer = data.get("customer") or {}
    email = customer.get("email", "")

    if event_type in ("subscription.create", "charge.success"):
        plan = data.get("plan") or {}
        plan_code = plan.get("plan_code", "") if isinstance(plan, dict) else str(plan)

        tier = p_mod.PAYSTACK_TO_TIER.get(plan_code)
        metadata = data.get("metadata") or {}
        if not tier and isinstance(metadata, dict):
            tier = metadata.get("tier")

        if not tier:
            logger.warning("PAYSTACK: Unknown plan_code %s / metadata — cannot map to tier", plan_code)
            return {"status": "unknown_plan"}

        uid = metadata.get("mehd_uid") if isinstance(metadata, dict) else None
        if not uid and email:
            uid = await p_mod._uid_from_email(email)

        if not uid:
            logger.warning("PAYSTACK: No user found for email %s", email)
            return {"status": "user_not_found"}

        if email:
            p_mod._paystack_email_to_uid[email] = uid

        portal_urls = {
            "update_payment_method": p_mod.PRICING_URL,
            "cancel": p_mod.PRICING_URL,
        }
        p_mod.set_user_tier(uid, tier, portal_urls)
        logger.info("PAYSTACK: User %s (%s) upgraded to %s via %s", uid, email, tier, event_type)

    elif event_type in ("subscription.disable", "refund.processed", "dispute.created", "charge.dispute.create"):
        uid = p_mod._paystack_email_to_uid.get(email) or await p_mod._uid_from_email(email)
        if uid:
            await p_mod._downgrade_user(uid, f"paystack {event_type}")

    elif event_type == "invoice.payment_failed":
        uid = p_mod._paystack_email_to_uid.get(email) or await p_mod._uid_from_email(email)
        if uid:
            logger.warning("PAYSTACK PAYMENT FAILED: User %s (%s) — awaiting retry", uid, email)

    return {"status": "ok"}
