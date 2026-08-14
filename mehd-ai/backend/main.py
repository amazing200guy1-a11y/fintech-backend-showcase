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
from routes.websocket_signals import router as ws_router, init_ws_redis_listener
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

@asynccontextmanager
async def lifespan(app: FastAPI):
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

    # Initialize WebSocket signal distributor for Google Cloud Run
    try:
        await init_ws_redis_listener()
    except Exception as e:
        logger.warning("WebSocket Redis listener init failed (non-fatal): %s", e)

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
    
    # Tear down the isolated Risk Microservice if defined
    risk_task_ref = globals().get("_risk_task")
    if risk_task_ref:
        risk_task_ref.cancel()


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
    allow_headers=["Authorization", "Content-Type", "Accept", "X-Signature", "X-Timestamp", "X-Nonce"],
)

# ── FORTRESS SECURITY HEADERS & THREAT JAIL MIDDLEWARE ──
from security_guard import threat_jail, get_real_client_ip

@app.middleware("http")
async def fortress_security_middleware(request: Request, call_next):
    client_ip = get_real_client_ip(request)

    # 1. Threat Jail IP Ban Check
    if threat_jail.is_ip_banned(client_ip):
        logger.warning("🚨 FORTRESS DEFENSE: Blocked request from banned IP %s", client_ip)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied by Fortress Threat Defense System."
        )

    # 2. Process Request
    response = await call_next(request)

    # 3. Inject Military-Grade HTTP Security Headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains; preload"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Content-Security-Policy"] = "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com;"

    return response


# ── Register All Routers ──
app.include_router(analysis_router)
app.include_router(trading_router)
app.include_router(den_router)
app.include_router(account_router)
app.include_router(admin_router)
app.include_router(broadcast_router)
app.include_router(payments_router)
app.include_router(ws_router)
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

    from security_guard import sanitize_input_string
    allowed_types = {"WITHDRAWAL_DELAY", "SPREAD_MANIPULATION", "OTHER"}
    broker_id = sanitize_input_string(body.broker_id.strip().lower(), max_length=50)
    report_type = sanitize_input_string(body.report_type.strip().upper(), max_length=50)
    clean_description = sanitize_input_string(body.description, max_length=500)

    if not broker_id or len(broker_id) > 50:
        raise HTTPException(status_code=400, detail="Invalid broker_id.")
    if report_type not in allowed_types:
        raise HTTPException(status_code=400, detail=f"report_type must be one of: {allowed_types}")
    if not clean_description or len(clean_description) < 10:
        raise HTTPException(status_code=400, detail="Description must be at least 10 characters.")

    now = datetime.now(timezone.utc)
    report_key = f"{broker_id}_{uid[:8]}_{now.strftime('%Y%m%d_%H%M%S')}"
    report_data = {
        "broker_id":   broker_id,
        "user_id":     uid,
        "report_type": report_type,
        "description": clean_description,
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

