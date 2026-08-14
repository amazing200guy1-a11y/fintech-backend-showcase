"""
Mehd AI — Analysis Routes
===========================
Endpoints: /analyze/{symbol}, /stream/{symbol}

These are the "brain" endpoints — they ask the 11 AI agents
what they think about a currency pair and stream live prices.
"""

from __future__ import annotations

import asyncio
import logging
import time

from fastapi import APIRouter, HTTPException, Request, Depends
from slowapi import Limiter
from sse_starlette.sse import EventSourceResponse

from auth import get_current_user, get_real_ip, get_uid_rate_key
from consensus_engine import generate_drawing_commands, generate_mock_candles
from models import ConsensusResult
from state import (
    den_engine, streamer, risk_client, audit,
    analysis_cache, daily_api_spend_usd,
    last_consensus_time, VALID_SYMBOLS,
)
from datetime import datetime, timezone
from routes.payments import get_user_tier_async, get_tier_config
from storage import storage

logger = logging.getLogger("mehd.routes.analysis")
router = APIRouter()
limiter = Limiter(key_func=get_uid_rate_key)


@router.get(
    "/analyze/{symbol}",
    response_model=ConsensusResult,
    summary="Analyze a currency pair with 11 AI agents",
    tags=["Analysis"],
)
@limiter.limit("10/minute")
async def analyze_symbol(
    request: Request, 
    symbol: str, 
    tiger_mode: bool = False,
    uid: str = Depends(get_current_user)
) -> ConsensusResult:
    """
    Fires all 11 AI agents to analyze the given currency pair.
    Returns the consensus result with every model's vote,
    the majority direction, and whether trading should proceed.
    """
    logger.info("=== ANALYZE REQUEST: %s (user: %s, tiger: %s) ===", symbol, uid, tiger_mode)

    # SECURITY: Validate symbol FIRST
    if symbol not in VALID_SYMBOLS:
        raise HTTPException(status_code=400, detail="Invalid symbol")

    # SECURITY: Look up tier from server-side persistent storage
    tier_name = await get_user_tier_async(uid)
    if tiger_mode:
        # SECURITY: Observer (free) users cannot activate Tiger Mode — it would bypass daily limits
        if tier_name == "observer":
            raise HTTPException(
                status_code=403,
                detail="Tiger Mode requires an active subscription. Upgrade to unlock.",
            )
        tier_name = "tiger"
        
    tier_config = get_tier_config(tier_name)
    daily_limit = tier_config["analyses_per_day"]
    
    # FIX (BUG-01): Key MUST include date so the counter resets daily.
    # Without the date, the counter accumulates forever and users get
    # permanently locked out after day 1. Format matches tokens_used.
    from datetime import datetime, timezone
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    analysis_key = f"{uid}_{today}"
    
    # SECURITY (VULN-02): Atomic check-and-increment prevents the "100-Hand Grab"
    # race condition. If 200 requests hit simultaneously, Firestore serializes 
    # the transactions and only `daily_limit` requests will succeed.
    success = await storage.check_and_increment("analysis_counts", analysis_key, "count", daily_limit)
    if not success:
        # FIX (BUG-03): Upgrade path must match the user's CURRENT tier.
        # Observer → Core, Core → Precision, Precision → Institutional
        if tier_name == "precision":
            upgrade_path = "Institutional"
        elif tier_name == "core":
            upgrade_path = "Precision"
        else:
            upgrade_path = "Core Trader"
        raise HTTPException(
            status_code=429,
            detail=f"Daily analysis limit reached ({daily_limit}). Upgrade to {upgrade_path} for more capacity.",
        )

    # Get the real live market snapshot
    live_snapshot = streamer.get_latest_snapshot(symbol)

    # Check cache — same snapshot never analyzed twice
    snap_key = str(live_snapshot.id)
    if snap_key in analysis_cache:
        logger.info("Cache hit for snapshot %s", snap_key)
        return analysis_cache[snap_key]

    try:
        health = await risk_client.get_account_health()
        result = await den_engine.analyze(
            symbol,
            live_snapshot,
            tier=tier_name,
            current_drawdown=health.daily_drawdown_pct,
        )

        # Generate AI Drawing Commands
        mock_candles = generate_mock_candles(live_snapshot.close)
        result.drawings = generate_drawing_commands(symbol, result, mock_candles)

        # Math Layer pre-check
        math_agent_names = ["TITAN", "ATLAS", "FORGE", "THE DON", "SENTINEL"]
        math_votes = [
            v for v in result.votes if v.model_name.upper() in math_agent_names
        ]
        vetoed, veto_reason = await risk_client.check_math_veto(math_votes)
        if vetoed:
            result.proceed = False
            result.rejection_reason = "Math Layer Veto — Market unsafe"

        # Log to audit trail
        audit.log_consensus(symbol, result)

        # Update global counters
        import state
        await storage.increment("global_stats", "daily_spend", "usd", 0.05)
        state.last_consensus_time = time.time()

        # Evict oldest cache entry if too large
        ANALYSIS_CACHE_MAX_SIZE = 200
        if len(analysis_cache) >= ANALYSIS_CACHE_MAX_SIZE:
            oldest_key = next(iter(analysis_cache))
            del analysis_cache[oldest_key]
        analysis_cache[snap_key] = result

        return result

    except Exception as e:
        logger.error("Analysis failed for %s: %s", symbol, e)
        raise HTTPException(
            status_code=500,
            detail="Analysis temporarily unavailable. Please try again.",
        ) from e


@router.get(
    "/stream/{symbol}",
    summary="Live Server-Sent Events price stream",
    tags=["Streaming"],
)
@limiter.limit("10/minute")
async def stream_prices(
    request: Request, symbol: str, uid: str = Depends(get_current_user)
):
    """
    Pushes live prices to the frontend every 500ms via SSE.
    HARDENED: Gated to Core Trader+ tier with a 30-minute max connection lifetime
    to prevent resource exhaustion from free-tier users opening unlimited connections.
    """
    import time
    tier_name = await get_user_tier_async(uid)
    if tier_name in ("observer", "scout"):
        raise HTTPException(
            status_code=403,
            detail="Live price streaming requires Core Trader tier or above.",
        )

    MAX_CONNECTION_SECONDS = 30 * 60  # 30 minutes

    async def event_generator():
        connection_start = time.monotonic()
        try:
            async for snapshot in streamer.subscribe(symbol):
                elapsed = time.monotonic() - connection_start
                if elapsed >= MAX_CONNECTION_SECONDS:
                    yield {"event": "connection_expiry", "data": '{"reason":"max_lifetime_reached","reconnect":true}'}
                    break
                yield {"data": snapshot.model_dump_json()}
        except asyncio.CancelledError:
            pass

    return EventSourceResponse(event_generator())


@router.get(
    "/weekly-scan",
    summary="Get the user's weekly AI scan",
    tags=["Analysis"],
)
@limiter.limit("5/minute")
async def get_weekly_scan(request: Request, uid: str = Depends(get_current_user)):
    """
    Returns the user's latest weekly scan generated by the background worker.
    Rate-limited to 5/minute per user to prevent Firestore hammering.
    Only Observer Mode users need this endpoint — paid users have real-time data.
    """
    scan = await storage.get("weekly_scans", uid)
    if scan:
        # Surface scan freshness so the frontend can display "Generated X days ago".
        return {
            **scan,
            "generated_at": scan.get("timestamp"),
        }
    return {
        "message": "Weekly scan not yet generated. The Den is analyzing markets.",
        "results": [],
        "generated_at": None,
    }


@router.get(
    "/alpha-signals",
    summary="Get Perfect Trades (Alpha Signals)",
    tags=["Analysis"],
)
async def get_alpha_signals(uid: str = Depends(get_current_user)):
    """
    Returns 'Perfect Trades' where the Den reached very high consensus (>90%).
    Pulls from REAL broadcaster data — no fabricated signals.
    """
    from broadcaster import broadcaster

    all_latest = broadcaster.get_all_latest()
    alpha_signals = []

    for symbol, data in all_latest.items():
        consensus_pct = data.get("consensus_pct", 0)
        direction = data.get("direction", "HOLD")
        proceed = data.get("proceed", False)

        # Only surface signals with genuinely high consensus and approval
        if consensus_pct >= 90 and proceed and direction != "HOLD":
            alpha_signals.append({
                "id": f"ALPHA_{int(time.time())}_{symbol.replace('/', '')}",
                "symbol": symbol,
                "direction": direction,
                "consensus_percentage": consensus_pct,
                "chairman_summary": data.get("chairman_summary", ""),
                "vote_count": data.get("vote_count", 0),
                "status": data.get("status", "FRESH"),
                "broadcast_time": data.get("broadcast_time", ""),
            })

    if not alpha_signals:
        return {
            "signals": [],
            "message": "No alpha signals right now. The Den broadcasts high-confidence setups when 90%+ of agents agree.",
        }

    return {"signals": alpha_signals}


@router.get(
    "/position-health",
    summary="Get real-time health scores for all open positions",
    tags=["Analysis"],
)
@limiter.limit("20/minute")
async def get_position_health(
    request: Request, uid: str = Depends(get_current_user)
) -> dict:
    """
    Returns the current AI-calculated health scores for all of 
    the user's open auto-execution positions.
    """
    # 1. Get all open positions for this user
    # We query the health collection directly using the composite key pattern.
    all_health = await storage.get_all("position_health")
    
    user_health = {}
    for key, data in all_health.items():
        if key.startswith(f"{uid}_"):
            symbol = key.split("_")[1]
            user_health[symbol] = data
            
    return user_health


@router.get(
    "/analyze/command/{symbol}",
    summary="Fast swarm scan for slash command — returns entry, SL, TP, lot size",
    tags=["Analysis"],
)
@limiter.limit("20/minute")
async def analyze_for_command(
    request: Request,
    symbol: str,
    direction: str = "BUY",
    uid: str = Depends(get_current_user),
) -> dict:
    """
    Triggered by /long and /short slash commands.
    Returns a structured execution brief: entry, SL, TP, lot, and tier-gated flags.

    Tier gates:
    - core ($79):          entry + SL + TP. Manual EXECUTE confirm required. Sandbox.
    - precision ($149):    Full levels + auto_execute=True. Live broker.
    - institutional ($299): Full levels + auto_execute + don_alert + partial TP. Live.
    """
    if symbol not in VALID_SYMBOLS:
        raise HTTPException(status_code=400, detail=f"Invalid symbol: {symbol}")

    direction = direction.upper()
    if direction not in ("BUY", "SELL"):
        raise HTTPException(status_code=400, detail="direction must be BUY or SELL")

    tier_name = await get_user_tier_async(uid)
    from routes.payments import _LEGACY_TIER_ALIASES
    tier_name = _LEGACY_TIER_ALIASES.get(tier_name, tier_name)

    live_snapshot = streamer.get_latest_snapshot(symbol)
    entry = live_snapshot.bid if direction == "BUY" else live_snapshot.ask
    spread = live_snapshot.ask - live_snapshot.bid

    is_jpy    = "JPY" in symbol
    is_gold   = "XAU" in symbol
    is_crypto = symbol in ("BTC/USD", "ETH/USD")

    if is_crypto:
        sl_distance = entry * 0.005   # 0.5%
        tp_distance = entry * 0.012   # 1.2%
    elif is_gold:
        sl_distance = 5.00            # $5 SL
        tp_distance = 12.00           # $12 TP  (1:2.4 RR)
    elif is_jpy:
        sl_distance = 0.30            # 30 pips
        tp_distance = 0.72            # 72 pips (1:2.4 RR)
    else:
        sl_distance = 0.0030          # 30 pips
        tp_distance = 0.0072          # 72 pips (1:2.4 RR)

    if direction == "BUY":
        sl = round(entry - sl_distance, 5)
        tp = round(entry + tp_distance, 5)
    else:
        sl = round(entry + sl_distance, 5)
        tp = round(entry - tp_distance, 5)

    # 1% risk on $10k default equity — real equity from broker in production
    risk_amount = 10_000.0 * 0.01
    sl_pips = sl_distance * (100 if is_jpy else 10_000) if not is_gold and not is_crypto else sl_distance
    pip_value = 1.0 if is_gold else (0.1 if is_jpy else 10.0)
    raw_lot = risk_amount / (sl_pips * pip_value) if sl_pips > 0 else 0.01
    suggested_lot = round(max(0.01, min(raw_lot, 100.0)), 2)

    result = {
        "symbol":        symbol,
        "direction":     direction,
        "entry":         round(entry, 5),
        "sl":            sl,
        "tp":            tp,
        "suggested_lot": suggested_lot,
        "spread_pips":   round(spread * (100 if is_jpy else 10_000), 1),
        "risk_reward":   "1:2.4",
        "tier":          tier_name,
    }

    if tier_name == "institutional":
        result["auto_execute"]       = True
        result["don_alert"]          = True
        result["execution_mode"]     = "live"
        result["automation_mode"]    = "fully-automated"
        result["breakeven_trigger"]  = round(
            (entry + sl_distance * 0.5) if direction == "BUY" else (entry - sl_distance * 0.5), 5
        )
        result["partial_tp"] = round(
            (entry + tp_distance * 0.5) if direction == "BUY" else (entry - tp_distance * 0.5), 5
        )
    elif tier_name == "precision":
        result["auto_execute"]       = True
        result["don_alert"]          = False
        result["execution_mode"]     = "live"
        result["automation_mode"]    = "semi-automated"
        result["breakeven_trigger"]  = round(
            (entry + sl_distance * 0.5) if direction == "BUY" else (entry - sl_distance * 0.5), 5
        )
        result["partial_tp"] = round(
            (entry + tp_distance * 0.5) if direction == "BUY" else (entry - tp_distance * 0.5), 5
        )
    else:
        result["auto_execute"]   = False
        result["don_alert"]      = False
        result["execution_mode"] = "sandbox"
        result["automation_mode"] = "manual"


    logger.info(
        "CMD_BRIEF: %s %s | tier=%s | entry=%.5f SL=%.5f TP=%.5f lot=%.2f | uid=%s",
        direction, symbol, tier_name, entry, sl, tp, suggested_lot, uid[:8]
    )
    return result
