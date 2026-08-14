import asyncio
import logging
import time
from fastapi import Request, HTTPException
from fastapi.responses import JSONResponse

logger = logging.getLogger("app_middleware")

@app.middleware("http")
async def validate_symbol_param(request: Request, call_next):
    from state import VALID_SYMBOLS
    raw_symbol = request.query_params.get("symbol")
    if raw_symbol is not None:
        clean = raw_symbol.upper().replace("/", "").strip()
        if not _SYMBOL_RE.match(clean):
            return __import__('fastapi').responses.JSONResponse(
                status_code=400,
                content={"detail": f"Invalid symbol format: '{raw_symbol}'"}
            )
        if clean not in VALID_SYMBOLS:
            return __import__('fastapi').responses.JSONResponse(
                status_code=400,
                content={"detail": f"Unsupported symbol: '{clean}'. See /analysis/symbols for valid options."}
            )
    return await call_next(request)


# ── Security Headers Middleware ──
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains; preload"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'self'; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src 'self' https://fonts.gstatic.com; "
        "img-src 'self' data:; "
        "connect-src 'self' http://localhost:* http://127.0.0.1:* https://*.firebaseio.com https://*.googleapis.com; "
        "frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
    )
    return response


# ── Suspicious Request Fingerprinting Middleware ──
# asyncio.Lock must be created lazily (after the event loop starts) so we
# initialise it on first use rather than at module import time.
_ip_requests: defaultdict = defaultdict(list)
_banned_ips: dict = {}   # IP -> ban_expires_timestamp
_ip_lock: asyncio.Lock | None = None

def _get_ip_lock() -> asyncio.Lock:
    global _ip_lock
    if _ip_lock is None:
        _ip_lock = asyncio.Lock()
    return _ip_lock

@app.middleware("http")
async def bot_fingerprint_middleware(request: Request, call_next):
    from auth import get_real_ip
    client_ip = get_real_ip(request)
    
    # Exclude localhost/internal health check loop from bans
    if client_ip in ("127.0.0.1", "localhost", "::1"):
        return await call_next(request)
        
    now = time.time()
    
    async with _get_ip_lock():
        # Check storage-persisted bans first (survive server restarts)
        try:
            persisted_ban = await storage.get("ip_bans", client_ip)
            if persisted_ban:
                ban_expires = float(persisted_ban.get("expires", 0))
                if ban_expires > now:
                    retry_after = int(ban_expires - now)
                    return __import__('fastapi').responses.JSONResponse(
                        status_code=429,
                        content={"detail": "Too many requests. Temporary ban in effect."},
                        headers={"Retry-After": str(retry_after)}
                    )
                else:
                    await storage.delete("ip_bans", client_ip)
        except Exception:
            pass  # Non-fatal — fall through to in-memory check

        ban_expires = _banned_ips.get(client_ip, 0)
        if ban_expires > now:
            retry_after = int(ban_expires - now)
            return __import__('fastapi').responses.JSONResponse(
                status_code=429,
                content={"detail": "Too many requests. Temporary ban in effect."},
                headers={"Retry-After": str(retry_after)}
            )
        elif ban_expires > 0:
            del _banned_ips[client_ip]
            _ip_requests[client_ip] = []

        _ip_requests[client_ip].append(now)
        _ip_requests[client_ip] = [t for t in _ip_requests[client_ip] if now - t <= 60]
        
        if len(_ip_requests[client_ip]) > 50:
            ban_until = now + 900  # 15 minutes
            _banned_ips[client_ip] = ban_until
            # Persist ban to storage so it survives server restarts
            try:
                await storage.set("ip_bans", client_ip, {"expires": ban_until})
            except Exception:
                pass  # Non-fatal — in-memory ban still active
            logger.warning("SUSPICIOUS_BOT_DETECTED: IP %s sent %d requests in 60s. Banned for 15m.", client_ip, len(_ip_requests[client_ip]))
            return __import__('fastapi').responses.JSONResponse(
                status_code=429,
                content={"detail": "Suspicious request velocity detected. IP banned for 15 minutes."},
                headers={"Retry-After": "900"}
            )
            
    return await call_next(request)


# ── Audit Logging Middleware ──
@app.middleware("http")
async def audit_log_middleware(request: Request, call_next):
    from auth import get_real_ip, get_uid_rate_key
    
    client_ip = get_real_ip(request)
    user_agent = request.headers.get("user-agent", "unknown")
    
    user_key = get_uid_rate_key(request)
    user_id = user_key.replace("uid:", "") if user_key.startswith("uid:") else "guest"
    
    start_time_ms = time.time()
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    except Exception as e:
        status_code = 500
        raise e
    finally:
        duration_ms = int((time.time() - start_time_ms) * 1000)
        path = request.url.path
        level = "HIGH_PRIORITY" if any(x in path for x in ["/auth", "/trading", "/payments", "/admin"]) else "INFO"
        
        audit_msg = (
            f"ip={client_ip} │ user_id={user_id} │ "
            f"method={request.method} │ path={path} │ status={status_code} │ "
            f"duration={duration_ms}ms │ ua={user_agent}"
        )
        
        if level == "HIGH_PRIORITY":
            audit_logger.warning(audit_msg)
        else:
            audit_logger.info(audit_msg)


# ── Request Body Size Limit ──
@app.middleware("http")
async def limit_request_body(request: Request, call_next):
    """
    HARDENED (VULN-09): Enforces body size limit by checking BOTH the
    Content-Length header AND the actual body bytes. The header alone
    is spoofable — an attacker can claim a small body but send a large one.

    CRITICAL FIX: After reading the body for size validation, we re-inject
    it via request._receive so downstream handlers (like Stripe webhook
    signature verification) can read it again. Without this, the body
    stream is consumed and downstream gets empty bytes.
    """
    MAX_BODY_SIZE = 1_048_576  # 1 MB

    # Quick reject via header (fast path)
    if request.headers.get("content-length"):
        try:
            content_length = int(request.headers["content-length"])
            if content_length > MAX_BODY_SIZE:
                raise HTTPException(status_code=413, detail="Request body too large")
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid Content-Length header")

    # For endpoints that consume the body, we also enforce at the byte level.
    # This catches chunked transfer encoding and spoofed Content-Length headers.
    # Note: For streaming endpoints (SSE), the body is typically empty so this is safe.
    if request.method in ("POST", "PUT", "PATCH"):
        body = await request.body()
        if len(body) > MAX_BODY_SIZE:
            raise HTTPException(status_code=413, detail="Request body too large")

        # Re-inject the body so downstream handlers can read it again.
        # Without this, request.body() returns empty bytes on second call.
