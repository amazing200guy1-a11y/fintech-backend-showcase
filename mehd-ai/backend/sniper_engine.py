"""
Mehd AI — Sniper Execution Engine
===================================
Handles high-precision entry arming, pullback tracking, 1-pip bounce verification,
and runaway/breakout protection.
"""

import asyncio
import logging
import random
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, Callable, Optional

from storage import storage
from models import get_pip_size

logger = logging.getLogger("mehd.sniper_engine")

MAX_SIGNAL_AGE_SECONDS = 300  # 5 minutes


def is_market_open(symbol: str = "") -> bool:
    """Check if market for the given symbol is open.
    Crypto pairs (BTC/USD, etc.) trade 24/7/365.
    Forex & metals close on weekends (Friday 22:00 UTC → Sunday 22:00 UTC)."""
    sym_upper = symbol.upper()
    if "BTC" in sym_upper or "ETH" in sym_upper or "SOL" in sym_upper or "CRYPTO" in sym_upper:
        return True  # Crypto is 24/7

    now = datetime.now(timezone.utc)
    weekday = now.weekday()  # 0=Mon, 6=Sun
    hour = now.hour
    if weekday == 4 and hour >= 22:
        return False
    if weekday == 5:
        return False
    if weekday == 6 and hour < 22:
        return False
    return True


class SniperEngine:
    """
    Precision execution tracker for high-conviction signals.
    Arms entry targets, waits for pullbacks and 1-pip bounce confirmations,
    and forwards execution tasks to the master execution queue.
    """
    def __init__(self, queue_execution_cb: Callable):
        self.pending_sniper_entries: Dict[str, Dict[str, Any]] = {}
        self._queue_master_execution = queue_execution_cb

    def arm_sniper(self, sig_id: str, signal_data: dict):
        symbol = signal_data.get("symbol")
        direction_str = signal_data.get("direction")
        
        if not symbol or direction_str not in ["BUY", "SELL"]:
            return
        
        # MARKET HOURS GATE: Do not arm sniper during market closure (Crypto is 24/7)
        if not is_market_open(symbol):
            logger.info(f"MARKET CLOSED: Sniper not armed for {symbol}. Forex markets are closed.")
            return

        # ECONOMIC NEWS BLACKOUT GATE
        try:
            from economic_calendar import calendar_gateway
            mins_to_news = calendar_gateway.get_minutes_to_next_high_impact_news(symbol)
            if mins_to_news is not None:
                if 0 <= mins_to_news <= 60:
                    logger.warning(f"BLOCKED: News blackout active for {symbol}. High-impact news is in {mins_to_news} minutes. Skipping sniper.")
                    return
                elif mins_to_news < 0:
                    logger.warning(f"BLOCKED: Post-news volatility window active for {symbol}. Event was {-mins_to_news} minutes ago. Skipping sniper.")
                    return
        except Exception as e:
            logger.error(f"Error checking news blackout for {symbol}: {e}")
            
        current_price = signal_data.get("current_price", 0.0)
        if current_price <= 0.0:
            return

        # STRUCTURAL MARKET CONFIRMATION GATE
        try:
            from state import streamer
            snapshot = streamer.get_latest_snapshot(symbol)
            if snapshot and snapshot.open > 0:
                if direction_str == "BUY" and current_price < snapshot.open:
                    logger.warning(f"BLOCKED: Structural Filter failed for {symbol}. {direction_str} attempted below Daily Open ({current_price} < {snapshot.open}).")
                    return
                if direction_str == "SELL" and current_price > snapshot.open:
                    logger.warning(f"BLOCKED: Structural Filter failed for {symbol}. {direction_str} attempted above Daily Open ({current_price} > {snapshot.open}).")
                    return
        except Exception as e:
            logger.debug(f"Structural confirmation skipped for {symbol}: {e}")

        # SIGNAL FRESHNESS GATE
        broadcast_time_str = signal_data.get("broadcast_time")
        if broadcast_time_str:
            try:
                broadcast_time = datetime.fromisoformat(broadcast_time_str)
                age_seconds = (datetime.now(timezone.utc) - broadcast_time).total_seconds()
                if age_seconds > MAX_SIGNAL_AGE_SECONDS:
                    logger.warning(f"DISCARDED: Signal {sig_id} for {symbol} is {age_seconds:.0f}s old. Stale — not arming sniper.")
                    return
            except (ValueError, TypeError):
                logger.warning(f"Signal {sig_id} has unparseable broadcast_time — discarding for safety.")
                return
        else:
            logger.warning(f"Signal {sig_id} has no broadcast_time — discarding for safety.")
            return

        # OLYMPUS ANOMALY FLAG CHECK
        math_anomaly_keywords = ["black swan", "anomal", "volatility spike", "flash crash", "slippage"]
        vote_data = signal_data.get("votes", [])
        olympus_anomaly_count = 0
        for vote in vote_data:
            layer = vote.get("layer", "").upper()
            reasoning = vote.get("reasoning", "").lower()
            if layer == "OLYMPUS" and any(kw in reasoning for kw in math_anomaly_keywords):
                olympus_anomaly_count += 1
        if olympus_anomaly_count >= 2:
            logger.warning(f"BLOCKED: {olympus_anomaly_count}/3 OLYMPUS agents flagged anomalies for {symbol}. Signal discarded.")
            return

        # Prevent duplicate entries on same symbol
        if symbol in self.pending_sniper_entries:
            return
            
        pip_size = get_pip_size(symbol)

        is_gold = "XAU" in symbol.upper()
        pullback_pips = 4.0 if is_gold else 2.0
        runaway_pips = 10.0 if is_gold else 5.0
        timeout_seconds = 90 if is_gold else 180
        
        pullback_dist = pullback_pips * pip_size
        runaway_dist = runaway_pips * pip_size
        
        if direction_str == "BUY":
            target_price = round(current_price - pullback_dist, 5)
            cancel_price = round(current_price + runaway_dist, 5)
        else:
            target_price = round(current_price + pullback_dist, 5)
            cancel_price = round(current_price - runaway_dist, 5)

        entry = {
            "sig_id": sig_id,
            "signal_data": signal_data,
            "analysis_price": current_price,
            "target_price": target_price,
            "cancel_price": cancel_price,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "expires_at": (datetime.now(timezone.utc) + timedelta(hours=48)).isoformat(),
            "direction": direction_str,
            "timeout_seconds": timeout_seconds,
            "state": "ARMED"
        }
        self.pending_sniper_entries[symbol] = entry
        
        try:
            loop = asyncio.get_running_loop()
            loop.create_task(storage.set("sniper_targets", symbol, entry))
        except RuntimeError as e:
            logger.warning("No running loop found when arming sniper target for %s: %s", symbol, e)
        
        logger.info(f"🎯 SNIPER ARMED for {symbol}. Dir: {direction_str}, Analyzed: {current_price}, Pullback Target: {target_price}, Cancel at: {cancel_price}")

    async def run_sniper_loop(self, is_running_cb: Callable[[], bool]):
        await asyncio.sleep(5)
        
        # Restore persisted sniper targets
        try:
            persisted = await storage.get_all("sniper_targets")
            if persisted:
                for symbol, entry in persisted.items():
                    if symbol not in self.pending_sniper_entries:
                        entry["timestamp"] = datetime.fromisoformat(entry["timestamp"])
                        self.pending_sniper_entries[symbol] = entry
                        logger.info(f"🎯 Restored persisted sniper target for {symbol}.")
        except Exception as e:
            logger.warning(f"Failed to restore sniper targets: {e}")
        
        consecutive_errors = 0
        while is_running_cb():
            try:
                now = datetime.now(timezone.utc)
                symbols_to_remove = []
                
                system_pause = await storage.get("system_state", "pause_flag")
                if system_pause:
                    for sym in list(self.pending_sniper_entries.keys()):
                        await storage.delete("sniper_targets", sym)
                    self.pending_sniper_entries.clear()
                    await asyncio.sleep(1)
                    continue

                for symbol, data in list(self.pending_sniper_entries.items()):
                    ts = data["timestamp"] if isinstance(data["timestamp"], datetime) else datetime.fromisoformat(data["timestamp"])
                    timeout_val = data.get("timeout_seconds", 120)
                    if (now - ts).total_seconds() > timeout_val:
                        logger.warning(f"Sniper timeout for {symbol}. Cancelled (TIMEOUT_NO_ENTRY).")
                        symbols_to_remove.append(symbol)
                        continue

                    try:
                        from state import streamer
                        snapshot = streamer.get_latest_snapshot(symbol)
                        if not snapshot: continue
                        
                        if data["direction"] == "BUY":
                            live_price = snapshot.ask
                        else:
                            live_price = snapshot.bid
                    except Exception as e:
                        logger.debug(f"Sniper price fetch failed for {symbol}: {e}")
                        continue

                    analysis_price = data.get("analysis_price", 0.0)
                    if analysis_price > 0 and (live_price < analysis_price * 0.5 or live_price > analysis_price * 2.0):
                        logger.warning(f"BAD TICK REJECTED for {symbol}: live={live_price}, analysis={analysis_price}")
                        continue

                    current_state = data.get("state", "ARMED")

                    if current_state == "ARMED":
                        is_runaway = False
                        if data["direction"] == "BUY" and live_price >= data["cancel_price"]: is_runaway = True
                        if data["direction"] == "SELL" and live_price <= data["cancel_price"]: is_runaway = True
                        
                        if is_runaway:
                            spread = snapshot.spread
                            if spread <= 3.0:
                                logger.info(f"🚀 BREAKOUT MODE TRIGGERED for {symbol} at {live_price:.5f}! (Runaway without pullback)")
                                data["state"] = "EXECUTED_BREAKOUT"
                                data["signal_data"]["breakout_factor"] = 0.5
                                await self._queue_master_execution(symbol, data["signal_data"], live_price)
                            else:
                                logger.warning(f"Sniper runaway for {symbol}. Cancelled (High Spread: {spread}).")
                                data["state"] = "MISSED_ENTRY"
                            symbols_to_remove.append(symbol)
                            continue

                        hit_pullback = False
                        if data["direction"] == "BUY" and live_price <= data["target_price"]: hit_pullback = True
                        if data["direction"] == "SELL" and live_price >= data["target_price"]: hit_pullback = True

                        if hit_pullback:
                            logger.info(f"🎯 SNIPER HIT PULLBACK for {symbol} at {live_price:.5f}. Waiting for bounce...")
                            data["state"] = "WAITING_PULLBACK"
                            pip_size = get_pip_size(symbol)
                            if data["direction"] == "BUY":
                                data["bounce_target"] = round(live_price + (1.0 * pip_size), 5)
                            else:
                                data["bounce_target"] = round(live_price - (1.0 * pip_size), 5)
                            continue

                    elif current_state == "WAITING_PULLBACK":
                        is_triggered = False
                        if data["direction"] == "BUY" and live_price >= data.get("bounce_target", live_price): is_triggered = True
                        if data["direction"] == "SELL" and live_price <= data.get("bounce_target", live_price): is_triggered = True

                        if is_triggered:
                            delay_ms = random.uniform(10, 50)
                            logger.info(f"🎯 SNIPER TRIGGERED (BOUNCE CONFIRMED) for {symbol} at {live_price:.5f}! Anti-crowding delay: {delay_ms:.0f}ms")
                            await asyncio.sleep(delay_ms / 1000.0)
                            
                            data["state"] = "EXECUTED"
                            await self._queue_master_execution(symbol, data["signal_data"], live_price)
                            symbols_to_remove.append(symbol)

                for sym in symbols_to_remove:
                    self.pending_sniper_entries.pop(sym, None)
                    await storage.delete("sniper_targets", sym)
                
                consecutive_errors = 0
                sleep_time = 0.1 if self.pending_sniper_entries else 0.5

            except Exception as e:
                consecutive_errors += 1
                logger.error(f"Sniper loop error: {e}")
                sleep_time = min(60.0, 0.5 * (2 ** consecutive_errors))
                logger.info(f"Sniper loop backing off for {sleep_time}s due to consecutive errors.")
            
            await asyncio.sleep(sleep_time)
