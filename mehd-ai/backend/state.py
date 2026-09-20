"""
Mehd AI — Shared Application State
====================================
This is the SINGLE SOURCE OF TRUTH for all shared objects.

WHY THIS EXISTS:
Before this file, all global state (risk_kernel, den_engine, audit, etc.)
lived inside main.py. That meant every new route file had to import from
main.py, creating circular import nightmares and making it impossible to
test individual components.

Now, every shared object lives here. Route files import from state.py,
and main.py just wires everything together.

RULE: If it needs to be shared across multiple route files, it goes here.
"""

from __future__ import annotations

import os
import time
import logging
from datetime import datetime, timezone

from audit_trail import AuditLogger
from consensus_engine import AsyncCouncil
from data_streamer import MarketDataStreamer
from risk_client import risk_client
from models import ExecutiveBrief

logger = logging.getLogger("mehd.state")

# ──────────────────────────────────────────────
#  Core Engine Instances (created once at import)
# ──────────────────────────────────────────────

# Microservice completely handles risk. We just expose the client.
# risk_kernel and risk_gateway are deprecated in the shared state, replaced by risk_client
den_engine = AsyncCouncil()
audit = AuditLogger()
streamer = MarketDataStreamer()

# Track when the server started (for the /health endpoint)
start_time: float = time.time()

# ──────────────────────────────────────────────
#  Configuration (from environment)
# ──────────────────────────────────────────────

DEMO_MODE: bool = os.getenv("DEMO_MODE", "true").lower() == "true"

if DEMO_MODE:
    logger.warning("DEMO_MODE=true — all AI analysis uses simulated data. UI will indicate SIMULATED.")
else:
    logger.info("DEMO_MODE=false — live API mode active. All platform intelligence is real.")
DAILY_API_BUDGET_USD: float = float(os.getenv("DAILY_API_BUDGET_USD", "50"))
ALERT_THRESHOLD_USD: float = float(os.getenv("ALERT_THRESHOLD_USD", "40"))
AUTO_CACHE_THRESHOLD_USD: float = float(os.getenv("AUTO_CACHE_THRESHOLD_USD", "45"))

# ──────────────────────────────────────────────
#  Tier System (server-side — NEVER trust the client)
#  Source of truth: routes/payments.py TIER_CONFIG
#  Every analysis = full 11 agents. Tiers control
#  quantity and features, NEVER quality.
# ──────────────────────────────────────────────

def get_user_tier(uid: str) -> dict:
    """Look up the user's actual tier config. Default to observer (free)."""
    try:
        from routes.payments import get_user_tier as _get_tier_name, get_tier_config
        tier_name = _get_tier_name(uid)
        return get_tier_config(tier_name)
    except ImportError:
        # Fallback if payments module not loaded yet
        return {"analyses_per_day": 1, "full_risk_engine": False}


def get_user_tier_name(uid: str) -> str:
    """Get just the tier name string for a user."""
    try:
        from routes.payments import get_user_tier as _get_tier_name
        return _get_tier_name(uid)
    except ImportError:
        return "observer"


# ──────────────────────────────────────────────
#  In-Memory Storage (API Costs / Non-critical state)
#  Note: User rate limits are securely persisted via storage.py
# ──────────────────────────────────────────────

analysis_counts: dict[str, int] = {}          # user_id -> count today
daily_api_spend_usd: float = 0.0
analysis_cache: dict[str, dict] = {}          # snapshot_id -> result
last_consensus_time: float = 0.0
manual_drawings: dict[str, list[dict]] = {}   # uid_symbol -> drawings
mock_firebase_briefs: dict[str, ExecutiveBrief] = {}

# ──────────────────────────────────────────────
#  Valid Symbols (single source of truth)
# ──────────────────────────────────────────────

VALID_SYMBOLS = [
    # No-slash format — matches what Flutter sends after symbol.replaceAll('/', '')
    "EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDJPY", "USDCAD", "USDCHF",
    "EURGBP", "GBPJPY", "EURJPY",
    "XAUUSD", "XAGUSD", "USOIL",
    "NAS100", "US30", "SPX500", "GER40",
    "BTCUSD", "ETHUSD", "SOLUSD",
    # Slashed format compatibility
    "EUR/USD", "GBP/USD", "AUD/USD", "NZD/USD", "USD/JPY", "USD/CAD", "USD/CHF",
    "EUR/GBP", "GBP/JPY", "EUR/JPY",
    "XAU/USD", "XAG/USD", "USOIL",
    "NAS100", "US30", "SPX500", "GER40",
    "BTC/USD", "ETH/USD", "SOL/USD",
]

# ──────────────────────────────────────────────
#  Budget Helpers (Cost Protection System)
# ──────────────────────────────────────────────

async def increment_api_spend(cost: float) -> None:
    """Increment daily API spend and persist to Firestore."""
    global daily_api_spend_usd
    daily_api_spend_usd += cost
    try:
        from storage import storage
        await storage.set("system_config", "budget", {
            "daily_api_spend_usd": daily_api_spend_usd,
            "last_updated": datetime.now(timezone.utc).isoformat()
        })
    except Exception as e:
        logger.error(f"[STATE] Failed to sync budget to Firestore: {e}")

async def reset_daily_spend() -> None:
    """Reset the daily spend (called by cleanup_worker)."""
    global daily_api_spend_usd
    daily_api_spend_usd = 0.0
    try:
        from storage import storage
        await storage.set("system_config", "budget", {
            "daily_api_spend_usd": 0.0,
            "last_updated": datetime.now(timezone.utc).isoformat()
        })
    except Exception as e:
        logger.error(f"[STATE] Failed to reset budget in Firestore: {e}")

async def load_daily_spend_from_db() -> None:
    """Load the current spend from Firestore on startup."""
    global daily_api_spend_usd
    try:
        from storage import storage
        data = await storage.get("system_config", "budget")
        if data:
            last_updated = data.get("last_updated")
            if last_updated:
                last_dt = datetime.fromisoformat(last_updated)
                if last_dt.date() == datetime.now(timezone.utc).date():
                    daily_api_spend_usd = data.get("daily_api_spend_usd", 0.0)
                else:
                    daily_api_spend_usd = 0.0
    except Exception as e:
        logger.warning(f"[STATE] Failed to load budget from Firestore: {e}")
