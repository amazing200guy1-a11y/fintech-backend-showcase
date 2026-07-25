"""
Mehd AI — FastAPI Application (Clean Architecture)
====================================================
This file does ONE thing: wire the application together.

It creates the FastAPI app, attaches middleware, and includes
the route files. ALL endpoint logic lives in the routes/ folder.

Before (v1): 1,287 lines — trading, AI routing, marketplace,
  GDPR, health checks, security headers... all in one file.

After (v2): ~140 lines — just the wiring.

How the pieces connect:
    Flutter App  →  main.py (FastAPI)
                      ├── routes/analysis.py  →  /analyze, /stream
                      ├── routes/trading.py   →  /execute
                      ├── routes/den.py       →  /den/*, /drawings/*
                      ├── routes/account.py   →  /account_health, /constitution
                      └── routes/admin.py     →  /health, /audit-trail, /backtest
"""

from __future__ import annotations

# CRITICAL: Load .env before ANY module reads os.getenv()
# Without this, all keys (CAPSULE_SIGNING_SECRET, RISK_INTERNAL_TOKEN, etc.) are empty
# and the server crashes with RuntimeError on startup.
from dotenv import load_dotenv
load_dotenv()

# ── Sentry Crash Monitoring ──────────────────────────────
# When the server crashes at 3am, you know in 60 seconds.
# Empty DSN = no-op (safe). Paste a real DSN to activate.
import os
import sentry_sdk
_sentry_dsn = os.getenv("SENTRY_DSN", "")
if _sentry_dsn:
    sentry_sdk.init(
        dsn=_sentry_dsn,
        traces_sample_rate=0.1,  # 10% of requests traced (performance)
        profiles_sample_rate=0.1,
    )
# ─────────────────────────────────────────────────────────

import asyncio
import logging
import time
from collections import defaultdict
from contextlib import asynccontextmanager
from logging.handlers import RotatingFileHandler

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from auth import get_current_user

from black_swan_monitor import monitor_instance as black_swan
from broadcaster import broadcaster
from auto_execution_worker import auto_execution_worker
from cleanup_worker import cleanup_worker
from weekly_scan_worker import weekly_scan_worker
from truth_engine_worker import truth_engine_worker
from personalization_worker import personalization_worker
from virtual_stop_worker import virtual_stop_worker
from state import (
    audit, den_engine, streamer, risk_client,
    DEMO_MODE, start_time,
)

# Import all route modules
from routes.analysis import router as analysis_router, limiter as analysis_limiter
from routes.trading import router as trading_router
from routes.den import router as den_router
from routes.account import router as account_router
from routes.admin import router as admin_router
from routes.broadcast import router as broadcast_router
from routes.payments import router as payments_router
from auth import auth_router

# ──────────────────────────────────────────────
#  Logging & Audit Log Setup
# ──────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s │ %(name)-22s │ %(levelname)-8s │ %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("mehd.main")

# Layer 1: Establish Audit Logging directory and Rotating Audit Handler
os.makedirs("logs", exist_ok=True)
audit_logger = logging.getLogger("mehd.audit")
audit_logger.setLevel(logging.INFO)
audit_logger.propagate = False  # Keep audit logs segregated from standard stdout

_audit_handler = RotatingFileHandler("logs/audit.log", maxBytes=10*1024*1024, backupCount=5, encoding="utf-8")
_audit_handler.setFormatter(logging.Formatter(
    fmt="%(asctime)s │ %(levelname)-8s │ %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
))
audit_logger.addHandler(_audit_handler)


# ──────────────────────────────────────────────
#  Startup / Shutdown Lifecycle
# ──────────────────────────────────────────────

_risk_task: asyncio.Task | None = None
_risk_process = None

async def _run_risk_microservice():
    global _risk_process
    consecutive_errors = 0
    try:
        while True:
            logger.info("Starting Risk Microservice on 127.0.0.1:8001...")
            import sys
            import subprocess
            import os
            
            minimal_env = {
                "RISK_INTERNAL_TOKEN": os.environ.get("RISK_INTERNAL_TOKEN", ""),
                "PATH": os.environ.get("PATH", ""),
                "PYTHONPATH": os.environ.get("PYTHONPATH", ""),
                # Windows-critical: Python stdlib (ssl, socket, tempfile) requires these
                "SYSTEMROOT": os.environ.get("SYSTEMROOT", ""),
                "VIRTUAL_ENV": os.environ.get("VIRTUAL_ENV", ""),
                "USERPROFILE": os.environ.get("USERPROFILE", ""),
            }
            
            _risk_process = subprocess.Popen(
                [sys.executable, "-m", "uvicorn", "risk_microservice:app", "--host", "127.0.0.1", "--port", "8001"],
                env=minimal_env
            )
            boot_time = time.time()

            # Report healthy once booted
            from system_health import health_registry
            await health_registry.report("risk_microservice", "GREEN", "Running on 127.0.0.1:8001")

            # Wait for process to exit using asyncio thread to avoid blocking main thread
            await asyncio.to_thread(_risk_process.wait)
            
            uptime = time.time() - boot_time
            if uptime > 30.0:
                # Ran for >30s before crashing — treat as transient, reset backoff
                consecutive_errors = 1
            else:
                consecutive_errors += 1
            sleep_time = min(60.0, 2.0 * (1.5 ** consecutive_errors))
            logger.critical(f"Risk Microservice CRASHED after {uptime:.0f}s. Restarting in {sleep_time:.1f} seconds...")

            # Report crash to health registry
            _h_state = "RED" if consecutive_errors >= 3 else "YELLOW"
            await health_registry.report("risk_microservice", _h_state,
                f"Crashed after {uptime:.0f}s — restarting in {sleep_time:.0f}s", {
                    "consecutive_crashes": consecutive_errors,
                    "last_uptime_s": round(uptime, 1),
                })

            await asyncio.sleep(sleep_time)
    except asyncio.CancelledError:
        if _risk_process:
            _risk_process.terminate()
        logger.info("Risk Microservice shutdown.")

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup checks and graceful shutdown."""
    
    # Generate an internal secure token for the Risk Microservice if not already defined
    if not os.environ.get("RISK_INTERNAL_TOKEN"):
        import secrets
        os.environ["RISK_INTERNAL_TOKEN"] = secrets.token_hex(32)

    # Start the Risk Guard Auto-Restarting Daemon (only if running locally)
    # If RISK_MICROSERVICE_URL points to a remote/different container (like http://risk:8001),
    # we don't start the subprocess because a dedicated service is running.
    microservice_url = os.environ.get("RISK_MICROSERVICE_URL", "http://127.0.0.1:8001")
    if "127.0.0.1" in microservice_url or "localhost" in microservice_url:
        global _risk_task
        _risk_task = asyncio.create_task(_run_risk_microservice())
        await asyncio.sleep(2)  # Give the microservice time to boot
    else:
        logger.info(f"Using external/containerized Risk Microservice at {microservice_url}")

    # ── STARTUP ──────────────────────────────
    logger.info("=" * 60)
    logger.info("  MEHD AI — Starting up")
    logger.info("=" * 60)

    import state
    await state.load_daily_spend_from_db()
    logger.info(f"✓ Daily API spend loaded: ${state.daily_api_spend_usd:.2f} / ${state.DAILY_API_BUDGET_USD:.2f}")

    # Self-check 1: Risk engine via Client
    try:
        health = await risk_client.get_account_health()
        logger.info("✓ Risk engine microservice loaded — balance: $%.2f", health.balance)
    except Exception as e:
        logger.critical("✗ Risk engine FAILED to load: %s", e)
        raise RuntimeError(f"Risk engine startup check failed: {e}") from e

    # FIX M3: Restore risk kernel state from storage backend (multi-replica aware)
    try:
        from risk_engine import HardRiskKernel
        kernel = HardRiskKernel()
        await kernel.restore_from_storage()
        logger.info("✓ Risk kernel state synced from storage backend")
    except Exception as e:
        logger.debug("Risk kernel storage restore skipped (non-fatal): %s", e)

    # Self-check 2: Audit trail
    try:
        logger.info("✓ Audit trail initialised — session: %s", audit.session_id)
    except Exception as e:
        logger.error("✗ Audit trail issue (non-fatal): %s", e)

    # Self-check 3: Den models
    try:
        model_status = await den_engine.health_check()
        responding = sum(1 for s in model_status.values() if s == "responding")
        logger.info("✓ The Den: %d/%d models responding", responding, len(model_status))
    except Exception as e:
        logger.error("✗ Den health check issue (non-fatal): %s", e)

    # Start data streamer
    try:
        await streamer.start()
        logger.info("✓ Market Data Streamer started")
    except Exception as e:
        logger.error("✗ Streamer startup issue (non-fatal): %s", e)

    # Start background loops (if not running in decoupled worker mode)
    if os.environ.get("DECOUPLED_WORKER_MODE", "").lower() == "true":
        logger.info("ℹ️ Running in DECOUPLED_WORKER_MODE — Background worker daemons bypassed on API server.")
    else:
        # Start Black Swan Monitor
        asyncio.create_task(black_swan.run_daemon())

        # Start the Broadcaster — the Underground Research Daemon
        # This runs 11 agents continuously in the background for all pairs,
        # so every user gets instant results instead of waiting 20 seconds.
        await broadcaster.start()
        
        # Start the Autopilot Execution Worker
        auto_execution_worker.start()

        # Start the Cleanup Worker to handle TTLs
        cleanup_worker.start()

        # Start the Weekly Scan Worker
        weekly_scan_worker.start()

        # Start the Truth Engine Worker (Scoreboard stats)
        truth_engine_worker.start()

        # Start the Personalization Worker (Chairman's Voice)
        personalization_worker.start()

        # Start the Sniper Engine (Virtual Stops)
        virtual_stop_worker.start()

        # Wire push notifications — "The Don Decided" FCM alerts for >= 92% conviction signals
        from push_notification_service import push_service
        async def _on_strong_signal(notification: dict):
            """Called by Broadcaster when a signal exceeds 92% conviction.
            Sends directly to individual registered device tokens (not topic broadcast)
            to prevent double-notifications for users subscribed to both channels.
            """
            await push_service.send_don_decided_alert(notification)
        broadcaster.set_notification_callback(_on_strong_signal)

        logger.info("✓ Broadcaster daemon started — Underground research active")

    # Rebuild payment tier caches from storage on startup
    # HARDENED: Without this, a restart drops all paying users to 'observer'.
    # Rebuilds from Firestore for both Paddle and Paystack subscribers.
    from routes.payments import rebuild_tier_caches
    await rebuild_tier_caches()
    logger.info("✓ Tier caches rebuilt — Paddle & Paystack subscribers restored")

    # ── SECURITY ENVIRONMENT AUDIT ──────────────
    # Uses the SecretManager which checks GCP Secret Manager first,
    # then falls back to .env. This is the migration path to a vault.
    from secrets_manager import secrets
    _security_warnings = []

    # DEMO_MODE logic is safely handled by state.py (does not bypass auth)

    # Critical secrets — app refuses to start without these
    try:
        capsule_secret = secrets.require("CAPSULE_SIGNING_SECRET")
    except RuntimeError as e:
        logger.critical(str(e))
        raise
    if len(capsule_secret) < 32 and not DEMO_MODE:
        logger.critical("FATAL: CAPSULE_SIGNING_SECRET is too weak. Must be at least 32 characters in production.")
        raise RuntimeError("Weak CAPSULE_SIGNING_SECRET")

    # SECURITY: ENCRYPTION_MASTER_KEY is required to encrypt broker API keys at rest.
    # Without it, keys are stored as plaintext in Firestore. This is ONLY allowed in
    # development. In production (ENVIRONMENT=production), the app MUST have this key.
    _env = os.getenv("ENVIRONMENT", "development").lower().strip()
    encryption_key = secrets.get("ENCRYPTION_MASTER_KEY")
    if not encryption_key:
        if _env == "production" or not DEMO_MODE:
            logger.critical(
                "FATAL: ENCRYPTION_MASTER_KEY is not set in production. "
                "Broker API keys will be stored in PLAIN TEXT. "
                "Set ENCRYPTION_MASTER_KEY in .env or GCP Secret Manager."
            )
            raise RuntimeError("ENCRYPTION_MASTER_KEY required in production.")
        else:
            _security_warnings.append(
                "ENCRYPTION_MASTER_KEY is not set — broker API keys stored in PLAIN TEXT. "
                "Acceptable in development only. Set before going live."
            )
    elif len(encryption_key) < 32 and (_env == "production" or not DEMO_MODE):
        logger.critical("FATAL: ENCRYPTION_MASTER_KEY is too weak. Must be at least 32 characters in production.")
        raise RuntimeError("Weak ENCRYPTION_MASTER_KEY")

    critical_keys = ["GROQ_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY"]
    missing = [k for k in critical_keys if not secrets.get(k)]
    if missing:
        _security_warnings.append("Missing API keys: %s — agents will use fallback mode." % ", ".join(missing))

    # Log the secrets backend status (GCP vault vs .env)
    secret_audit = secrets.audit_status()
    logger.info("Secrets Backend: %s", secret_audit["backend"])

    if _security_warnings:
        logger.warning("=" * 60)
        logger.warning("  SECURITY AUDIT — %d WARNING(S)", len(_security_warnings))
        logger.warning("=" * 60)
        for i, w in enumerate(_security_warnings, 1):
            logger.warning("  [%d] %s", i, w)
        logger.warning("=" * 60)
    else:
        logger.info("✓ Security environment audit passed")

    # ── TRACK RECORD: Log boot event ──────────
    try:
        import track_record
        vault_loaded = os.path.exists(os.path.join(os.path.dirname(__file__), ".prompt_vault.py"))
        broker_mode = "paper" if DEMO_MODE else "live"
        track_record.log_system_boot(
            broker_mode=broker_mode,
            vault_loaded=vault_loaded,
            provider=os.getenv("DATA_PROVIDER", "twelvedata"),
        )
        stats = track_record.get_stats()
        logger.info("Track Record: %d trades, %.1f%% win rate, $%.2f saved by risk blocks",
                    stats["total_trades"], stats["win_rate"], stats["total_money_saved"])
    except Exception as e:
        logger.warning("Track record boot failed (non-fatal): %s", e)

    logger.info("=" * 60)
    logger.info("  MEHD AI — Ready to protect traders")
    logger.info("=" * 60)

    yield  # ← App running

    # ── SHUTDOWN ─────────────────────────────
    logger.info("MEHD AI — Shutting down gracefully")
    auto_execution_worker.stop()
    cleanup_worker.stop()
    weekly_scan_worker.stop()
    truth_engine_worker.stop()
    personalization_worker.stop()
    virtual_stop_worker.stop()
    broadcaster.stop()
    await streamer.stop()
    black_swan.stop_daemon()
    
    # Tear down the isolated Risk Microservice
    if _risk_task:
        _risk_task.cancel()


# ──────────────────────────────────────────────
#  FastAPI App
# ──────────────────────────────────────────────

app = FastAPI(
    title="Mehd AI — Forex Trading Assistant",
    description=(
        "Multi-model AI consensus engine with unbreakable risk rules. "
        "Protects traders from losing money through 11-agent voting, "
        "hard-coded safety limits, and permanent audit logging."
    ),
    version="0.2.0",
    lifespan=lifespan,
)

# Rate limiter state
app.state.limiter = analysis_limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── CORS ──
# SECURITY FIX: Dev origins are ONLY included when DEMO_MODE=true.
# In production, localhost origins are stripped to prevent attackers
# from exploiting localhost CORS to make authenticated API requests.
_DEV_ORIGINS = [
    "http://localhost:8080", "http://localhost:3000",
    "http://127.0.0.1:8080", "http://127.0.0.1:3000",
    "http://localhost:8005", "http://127.0.0.1:8005",
]
# Production origins from environment (comma-separated)
# Example: CORS_ORIGINS=https://mehdai.com,https://app.mehdai.com
_prod_origins_str = os.getenv("CORS_ORIGINS", "")
_PROD_ORIGINS = [o.strip() for o in _prod_origins_str.split(",") if o.strip()] if _prod_origins_str else []

if DEMO_MODE:
    _ALLOWED_ORIGINS = _DEV_ORIGINS + _PROD_ORIGINS
    logger.info("CORS: Dev mode — localhost origins ENABLED")
else:
    _ALLOWED_ORIGINS = _PROD_ORIGINS
    logger.info("CORS: Production mode — localhost origins STRIPPED (security hardened)")

if _PROD_ORIGINS:
    logger.info("CORS: Production origins loaded — %s", _PROD_ORIGINS)
elif not DEMO_MODE:
    logger.critical("CORS: No production origins set and DEMO_MODE=false! Set CORS_ORIGINS env var.")

app.add_middleware(
    CORSMiddleware,
    allow_origins=_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)


# ── Symbol Injection Guard ──
# SECURITY: Validates any `symbol` query parameter against VALID_SYMBOLS before
# the request reaches any route handler. Prevents injection of arbitrary strings
# into Groq/OANDA API calls, and blocks path traversal / oversized symbol attacks.
import re as _re
_SYMBOL_RE = _re.compile(r'^[A-Z0-9]{3,12}$')

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
            _banned_ips[client_ip] = now + 900  # 15 minutes
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
        async def receive():
            return {"type": "http.request", "body": body}
        request._receive = receive

    return await call_next(request)


# ── Register All Routers ──
app.include_router(analysis_router)
app.include_router(trading_router)
app.include_router(den_router)
app.include_router(account_router)
app.include_router(admin_router)
app.include_router(broadcast_router)
app.include_router(payments_router)
app.include_router(auth_router)

# ── Track Record Stats Endpoint ──
@app.get("/track-record")
@analysis_limiter.limit("30/minute")
async def get_track_record(request: Request, uid: str = Depends(get_current_user)):
    """Returns the cumulative track record stats — win rate, saves, etc."""
    import track_record
    return track_record.get_stats()


# ── Broker Health Endpoint ──
@app.get("/broker/health")
@analysis_limiter.limit("60/minute")
async def get_broker_health(request: Request, uid: str = Depends(get_current_user)):
    """
    Returns broker health scores from the community incident database.
    In DEMO_MODE, returns realistic mock data so the Flutter client always has data.
    In live mode, returns the daily-aggregated system_metrics/broker_health document.
    """
    import os
    from broker_scanner import get_demo_health
    demo_mode = os.getenv("DEMO_MODE", "true").lower() == "true"
    if demo_mode:
        return get_demo_health()
    live_data = await storage.get("system_metrics", "broker_health")
    if live_data:
        return live_data
    # Fallback to demo if live data not yet generated (first day of deployment)
    return get_demo_health()


# ── Broker Dispute / Report Endpoint ──
class BrokerReportRequest(BaseModel):
    broker_id: str
    report_type: str   # "WITHDRAWAL_DELAY" | "SPREAD_MANIPULATION" | "OTHER"
    description: str


@app.post("/broker/report")
@analysis_limiter.limit("5/minute")
async def submit_broker_report(
    request: Request,
    body: BrokerReportRequest,
    uid: str = Depends(get_current_user),
):
    """
    Allows an authenticated user to submit a community dispute report against a broker.
    Covers Pillar 3 (Withdrawal Honesty) and Pillar 4 (Spread Stability).

    Each report is written as one Firestore document — event-driven, near-zero billing.
    The daily broker health aggregation reads these and factors them into the score.
    """
    from datetime import datetime, timezone

    # Input validation
    allowed_types = {"WITHDRAWAL_DELAY", "SPREAD_MANIPULATION", "OTHER"}
    broker_id = body.broker_id.strip().lower()
    report_type = body.report_type.strip().upper()

    if not broker_id or len(broker_id) > 50:
        raise HTTPException(status_code=400, detail="Invalid broker_id.")
    if report_type not in allowed_types:
        raise HTTPException(status_code=400, detail=f"report_type must be one of: {allowed_types}")
    if not body.description or len(body.description.strip()) < 10:
        raise HTTPException(status_code=400, detail="Description must be at least 10 characters.")
    if len(body.description) > 500:
        raise HTTPException(status_code=400, detail="Description must be under 500 characters.")

    now = datetime.now(timezone.utc)
    report_key = f"{broker_id}_{uid[:8]}_{now.strftime('%Y%m%d_%H%M%S')}"
    report_data = {
        "broker_id":   broker_id,
        "user_id":     uid,
        "report_type": report_type,
        "description": body.description.strip(),
        "timestamp":   now.isoformat(),
        "status":      "PENDING",   # Future: REVIEWED | CONFIRMED | REJECTED
    }

    try:
        await storage.set("broker_reports", report_key, report_data)
        logger.info("📋 Broker dispute report received | %s | %s | user=%s", broker_id.upper(), report_type, uid[:8])
        return {"status": "submitted", "message": "Thank you. Your report has been received and will be reviewed by the community."}
    except Exception as e:
        logger.error("Failed to save broker report: %s", e)
        raise HTTPException(status_code=500, detail="Failed to submit report. Please try again.")


# ── FCM Registration Endpoint ──
class FcmTokenRequest(BaseModel):
    token: str
    platform: str  # "android" | "ios" | "web"


@app.post("/user/fcm")
async def update_fcm_token(
    body: FcmTokenRequest,
    uid: str = Depends(get_current_user),
):
    """
    Registers or updates the authenticated user's FCM push notification token.
    Stores the token in the Firestore 'user_fcm_tokens' collection.
    """
    from datetime import datetime, timezone

    token = body.token.strip()
    platform = body.platform.strip().lower()

    if not token:
        raise HTTPException(status_code=400, detail="token is required")
    if platform not in {"android", "ios", "web"}:
        raise HTTPException(status_code=400, detail="platform must be one of: android, ios, web")

    try:
        await storage.set("user_fcm_tokens", uid, {
            "token": token,
            "platform": platform,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        })
        logger.info("🔔 Registered FCM token for user: %s (platform: %s)", uid[:8], platform)
        return {"status": "success", "message": "FCM token updated."}
    except Exception as e:
        logger.error("Failed to update FCM token for user %s: %s", uid, e)
        raise HTTPException(status_code=500, detail="Failed to update FCM token.")

