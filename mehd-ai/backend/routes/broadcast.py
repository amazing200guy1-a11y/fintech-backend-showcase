"""
Mehd AI — Broadcast Routes
=============================
Endpoints: /broadcast/latest, /broadcast/latest/{symbol},
           /broadcast/history/{symbol}, /broadcast/status,
           /broadcast/stream

These endpoints serve the pre-computed consensus results
from the Broadcaster daemon. Users get INSTANT results
because the 11 agents already ran in the background.

SPEED COMPARISON:
    Old /analyze/{symbol}: 8-30 seconds (per user, per request)
    New /broadcast/latest: <50ms (pre-computed, instant)
"""

from __future__ import annotations
from typing import Literal

import asyncio
from datetime import datetime, timezone
import logging
import time

from fastapi import APIRouter, HTTPException, Depends, Request
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse

from auth import get_current_user
from broadcaster import broadcaster, FREE_TIER_DELAY_SECONDS, BROADCAST_PAIRS
from models import AutopilotConfig
from routes.payments import get_user_tier, get_tier_config, get_user_tier_async
from routes.analysis import limiter
from storage import storage

logger = logging.getLogger("mehd.routes.broadcast")
router = APIRouter(prefix="/broadcast", tags=["Broadcast"])


@router.get(
    "/latest",
    summary="Get latest consensus for ALL pairs (instant)",
)
@limiter.limit("60/minute")
async def get_all_latest(request: Request, uid: str = Depends(get_current_user)):
    """
    Returns the most recent consensus result for every monitored pair.
    This is the global dashboard — what Bloomberg's front page would look like.

    Response time: <50ms (pre-computed by the Broadcaster daemon).
    """
    latest = broadcaster.get_all_latest()

    if not latest:
        return {
            "status": "warming_up",
            "message": (
                "The Den is still analyzing. "
                "First results will appear within 3 minutes."
            ),
            "pairs_pending": 9,
        }

    # HARDENED (VULN-01): get_user_tier returns a STRING (e.g. "observer"),
    # NOT a dict. We must use get_tier_config() to get the config dict,
    # then check the tier name to determine free vs paid.
    tier_name = await get_user_tier_async(uid)
    tier_config = get_tier_config(tier_name)
    is_free = tier_name in ("observer", "scout")  # Legacy 'scout' included for safety

    if is_free:
        # Free users get delayed data — filter out signals newer than 15 min
        from datetime import datetime, timezone, timedelta

        cutoff = datetime.now(timezone.utc) - timedelta(
            seconds=FREE_TIER_DELAY_SECONDS
        )
        delayed = {}
        for symbol, data in latest.items():
            broadcast_time = data.get("broadcast_time", "")
            try:
                bt = datetime.fromisoformat(broadcast_time)
                if bt <= cutoff:
                    delayed[symbol] = data
                else:
                    delayed[symbol] = {
                        "symbol": symbol,
                        "status": "delayed",
                        "available_in_seconds": int(
                            (bt - cutoff).total_seconds()
                        ),
                        "message": "Upgrade to Core Trader for real-time signals.",
                    }
            except (ValueError, TypeError):
                delayed[symbol] = data

        return {"tier": tier_name, "delay_seconds": FREE_TIER_DELAY_SECONDS, "signals": delayed}

    return {"tier": tier_name, "delay_seconds": 0, "signals": latest}


@router.get(
    "/latest/{symbol}",
    summary="Get latest consensus for ONE pair (instant)",
)
@limiter.limit("60/minute")
async def get_latest_for_symbol(
    request: Request, symbol: str, uid: str = Depends(get_current_user)
):
    """
    Returns the most recent broadcast for a specific pair.
    Includes full vote breakdown, chairman summary, and snapshot data.
    Enforces daily reveal tokens based on subscription tier.
    """
    tier_name = await get_user_tier_async(uid)
    config = get_tier_config(tier_name)
    daily_limit = config.get("analyses_per_day", 999)
    weekly_limit = config.get("analyses_per_week", 999)

    # If daily limit is 0 but weekly limit > 0, this is the Observer tier (1 per week)
    if daily_limit == 0 and weekly_limit > 0:
        # Enforce weekly token limit
        year, week, _ = datetime.now(timezone.utc).isocalendar()
        token_key = f"{uid}_{year}_W{week}"
        
        revealed_symbols = await storage.get("reveals", token_key) or {}
        if symbol not in revealed_symbols:
            success = await storage.check_and_increment("tokens_used", token_key, "count", weekly_limit)
            if not success:
                raise HTTPException(
                    status_code=403,
                    detail=f"Weekly token limit reached ({weekly_limit}/{weekly_limit}). Upgrade to Core Trader for daily access.",
                )
            else:
                logger.info("User %s spent 1 weekly token to reveal %s. Tier: %s", uid, symbol, tier_name)
            
            revealed_symbols[symbol] = True
            await storage.set("reveals", token_key, revealed_symbols)

    # Else if daily limit is between 1 and 998, this is Core/Precision tier (X per day)
    elif 0 < daily_limit < 999:
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        token_key = f"{uid}_{today}"
        
        revealed_symbols = await storage.get("reveals", token_key) or {}
        if symbol not in revealed_symbols:
            success = await storage.check_and_increment("tokens_used", token_key, "count", daily_limit)
            if not success:
                raise HTTPException(
                    status_code=403,
                    detail=f"Daily token limit reached ({daily_limit}/{daily_limit}). Upgrade to Institutional for unlimited reveals.",
                )
            
            revealed_symbols[symbol] = True
            await storage.set("reveals", token_key, revealed_symbols)
            logger.info("User %s spent 1 daily token to reveal %s. Tier: %s", uid, symbol, tier_name)

    signal = broadcaster.get_latest(symbol)

    if signal is None:
        raise HTTPException(
            status_code=404,
            detail=f"No broadcast yet for {symbol}. The Den updates every 5 minutes.",
        )

    return signal.to_dict()


@router.get(
    "/history/{symbol}",
    summary="Get historical broadcasts for trend analysis",
)
@limiter.limit("60/minute")
async def get_broadcast_history(
    request: Request, symbol: str, limit: int = 20, uid: str = Depends(get_current_user)
):
    """
    Returns the last N broadcasts for a pair.
    Useful for seeing how consensus has shifted over time.
    """
    safe_limit = min(max(limit, 1), 50)
    history = broadcaster.get_history(symbol, safe_limit)

    if not history:
        return {
            "symbol": symbol,
            "history": [],
            "message": "No broadcast history yet for this pair.",
        }

    return {"symbol": symbol, "count": len(history), "history": history}


@router.get(
    "/stream",
    summary="Live SSE stream of all broadcast signals",
)
@limiter.limit("10/minute")
async def stream_broadcasts(request: Request, uid: str = Depends(get_current_user)):
    """
    Real-time Server-Sent Events stream.
    Every time the Broadcaster publishes a new signal for ANY pair,
    it's pushed to this stream.

    LOCKED to paid tiers. Observer must use tokens.

    HARDENED: 30-minute max connection lifetime + 60s heartbeat.
    Without this, a client could hold a connection open forever,
    eating server memory. After 30 min, the client must reconnect.
    """
    tier_name = await get_user_tier_async(uid)
    config = get_tier_config(tier_name)
    
    is_free = tier_name in ("observer", "scout")  # Legacy 'scout' included for safety
    
    if is_free:
        generator = broadcaster.subscribe_delayed()
        logger.info(f"User {uid} (Observer) connected to delayed broadcast stream.")
    else:
        generator = broadcaster.subscribe()
        logger.info(f"User {uid} ({tier_name}) connected to live broadcast stream.")

    # Max connection duration: 30 minutes (prevents resource exhaustion)
    MAX_CONNECTION_SECONDS = 30 * 60

    async def event_generator():
        connection_start = time.monotonic()
        try:
            async for signal in generator:
                elapsed = time.monotonic() - connection_start
                if elapsed >= MAX_CONNECTION_SECONDS:
                    # Send a close event so the client knows to reconnect
                    yield {"event": "connection_expiry", "data": {"reason": "max_lifetime_reached", "reconnect": True}}
                    logger.info("SSE: Connection for user %s expired after %.0fs (max: %ds)", uid, elapsed, MAX_CONNECTION_SECONDS)
                    break

                if signal == "HEARTBEAT":
                    yield {"event": "heartbeat", "data": {"ts": time.time()}}
                elif isinstance(signal, dict):
                    yield {"data": signal}
                else:
                    yield {"data": signal.to_dict()}
        except asyncio.CancelledError:
            pass
        finally:
            broadcaster.unsubscribe(generator)
            logger.debug("SSE: Connection closed for user %s (%.0fs)", uid, time.monotonic() - connection_start)

    return EventSourceResponse(event_generator())


@router.get(
    "/status",
    summary="Broadcaster operational status",
)
@limiter.limit("60/minute")
async def get_broadcaster_status(request: Request, uid: str = Depends(get_current_user)):
    """
    Returns the Broadcaster daemon's health status:
    how many cycles completed, how fresh each pair's data is, etc.
    """
    return broadcaster.get_status()


@router.get(
    "/missed",
    summary="Get missed signals for the Morning Briefing",
)
@limiter.limit("30/minute")
async def get_missed_signals(
    request: Request, since: str, uid: str = Depends(get_current_user)
):
    """
    Returns the count and top example of strong signals broadcast since the given timestamp,
    plus real auto-execution stats from the morning_briefing_logs collection.
    Used for the Morning Briefing / Missed Signals card.
    """
    try:
        since_time = datetime.fromisoformat(since.replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid since timestamp format")

    # PERFORMANCE FIX: Use in-memory broadcaster data instead of loading
    # the entire broadcast_history collection from Firestore.
    # The broadcaster already holds recent signals in RAM — no need to
    # load 78,000+ documents from persistent storage per request.
    missed_count = 0
    strongest_signal = None
    max_pct = 0

    for pair_symbol in broadcaster.BROADCAST_PAIRS:
        history = broadcaster.get_history(pair_symbol, limit=50)
        for sig in history:
            bt_str = sig.get("broadcast_time")
            if not bt_str:
                continue
            try:
                bt = datetime.fromisoformat(bt_str)
            except ValueError:
                continue

            if bt > since_time and sig.get("consensus_pct", 0) >= 70:
                if sig.get("status") != "INVALIDATED":
                    missed_count += 1
                    if sig["consensus_pct"] > max_pct:
                        max_pct = sig["consensus_pct"]
                        strongest_signal = sig

    example_text = ""
    if strongest_signal:
        sym = strongest_signal.get("symbol", "")
        dir_ = strongest_signal.get("direction", "")
        pct = strongest_signal.get("consensus_pct", 0)
        bt_str = strongest_signal.get("broadcast_time", "")
        try:
            bt_local = datetime.fromisoformat(bt_str).strftime("%I:%M %p")
        except (ValueError, TypeError):
            bt_local = bt_str
        example_text = f"{dir_} {sym} {pct}% consensus at {bt_local}."

    # ── Query auto-execution logs (filtered, not full table scan) ──
    auto_executed_count = 0
    vetoed_count = 0
    frozen_count = 0
    try:
        all_logs = await storage.query("morning_briefing_logs", [("user_id", "==", uid)])
        for log_key, log_entry in all_logs.items():
            # Only count logs belonging to this user and after 'since'
            log_ts_str = log_entry.get("timestamp", "")
            try:
                log_ts = datetime.fromisoformat(log_ts_str)
            except (ValueError, TypeError):
                continue
            if log_ts <= since_time:
                continue
            
            status = log_entry.get("status", "")
            if status == "EXECUTED":
                auto_executed_count += 1
            elif status == "VETOED":
                vetoed_count += 1
            elif status == "FROZEN":
                frozen_count += 1
    except Exception as e:
        logger.warning("Failed to query morning briefing logs: %s", e)

    return {
        "missed_count": missed_count,
        "auto_executed_count": auto_executed_count,
        "vetoed_count": vetoed_count,
        "frozen_count": frozen_count,
        "example_missed": example_text
    }


# ──────────────────────────────────────────────
#  AUTOPILOT CONFIG ENDPOINTS
# ──────────────────────────────────────────────

class AutopilotConfigRequest(BaseModel):
    """Request body for saving autopilot settings from the Flutter app."""
    enabled: bool = False
    whitelisted_pairs: list[str] = []
    active_hours_start_utc: int = 0
    active_hours_end_utc: int = 23
    predator_mode: bool = False
    assist_mode: bool = False
    compounding_mode: Literal["OFF", "DYNAMIC SCALING", "INSTITUTIONAL COMPOUNDING"] = "OFF"


