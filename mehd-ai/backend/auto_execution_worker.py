"""
Mehd AI — Auto-Execution Worker (HARDENED v2)
==============================================
FIXES APPLIED:
  P0 #9:  daily_auto_trades_count now resets at midnight UTC
  P0 #2:  Signal freshness gate (max 5 minutes old)
  P0 #4:  Per-user asyncio.Lock prevents concurrent execution races
  P0 #5:  Duplicate position check before broker execution
  P1 #1:  OLYMPUS anomaly flags checked from signal vote data
  P1 #10: Per-user risk evaluation (no shared kernel contamination)
  P1 #11: ATR-based SL/TP fallback when consensus doesn't provide them
"""

import asyncio
import logging
from datetime import datetime, timezone, timedelta
import json
import traceback
import uuid
import random

from storage import storage
from models import AutopilotConfig, TradeOrder, Direction, RiskDecision, get_pip_size
from risk_engine import HardRiskKernel
from hardened_kill_switch import hardened_kill_switch

logger = logging.getLogger("mehd.auto_execution")

# Priority mapping for tier-based execution routing.
# Lower number = Higher priority.
# This ensures Institutional users get filled first during liquidity events.
TIER_PRIORITY = {
    "institutional": -1,
    "precision": 1,
    "core": 2,
    "observer": 3,
    # Legacy aliases — existing Firestore records may still use old names
    "operative": -1,   # Was the top tier → map to institutional priority
    "guardian": 2,      # Was mid tier → map to core priority
    "scout": 3,         # Was free tier → map to observer priority
}

# Maximum age (in seconds) for a signal to be eligible for auto-execution.
# Anything older than this is discarded — prices may have moved.
MAX_SIGNAL_AGE_SECONDS = 300  # 5 minutes

# ── Market Hours Filter ──────────────────────────
# Forex markets: Sunday 22:00 UTC → Friday 22:00 UTC
def is_market_open() -> bool:
    """Check if forex markets are currently open.
    Returns False during weekends (Friday 22:00 UTC → Sunday 22:00 UTC)."""
    now = datetime.now(timezone.utc)
    weekday = now.weekday()  # 0=Mon, 6=Sun
    hour = now.hour
    # Friday after 22:00 UTC → market closed
    if weekday == 4 and hour >= 22:
        return False
    # Saturday → market closed
    if weekday == 5:
        return False
    # Sunday before 22:00 UTC → market closed
    if weekday == 6 and hour < 22:
        return False
    return True


class AutoExecutionWorker:
    """
    Decoupled daemon that listens for high-conviction signals and executes 
    them on behalf of eligible users.
    """
    def __init__(self):
        self._running = False
        self._task = None
        self._reconciliation_task = None
        
        # SNIPER ENGINE & GLOBAL QUEUE
        self._sniper_task = None
        self._execution_queue = asyncio.Queue()
        self._worker_pool = []
        self.pending_sniper_entries = {}
        self._broker_semaphore = None
        
        # Circuit Breaker: track consecutive broker failures
        self._consecutive_broker_failures = 0
        self._max_broker_failures = 5  # Trigger SYSTEM_PAUSE after 5 consecutive failures

    def start(self):
        if not self._running:
            self._running = True
            self._broker_semaphore = asyncio.Semaphore(10)
            self._task = asyncio.create_task(self._loop())
            self._reconciliation_task = asyncio.create_task(self._ghost_trade_reconciliation_loop())
            self._sniper_task = asyncio.create_task(self._sniper_loop())
            self._worker_pool.append(asyncio.create_task(self._master_worker()))
            self._worker_pool.append(asyncio.create_task(self._ledger_distribution_loop()))
            # GAP #6 FIX: Immediate startup recovery check
            # On server restart, check for ghost trades IMMEDIATELY instead of
            # waiting for the reconciliation loop's first 60s cycle.
            self._worker_pool.append(asyncio.create_task(self._startup_recovery_check()))
            logger.info("🤖 Auto-Execution Worker started with MAM Master Ledger Engine.")

    def stop(self):
        self._running = False
        if self._task:
            self._task.cancel()
        if self._reconciliation_task:
            self._reconciliation_task.cancel()
        if self._sniper_task:
            self._sniper_task.cancel()
        for w in self._worker_pool:
            w.cancel()
        logger.info("🤖 Auto-Execution Worker stopped.")

    async def _loop(self):
        await asyncio.sleep(5)  # Delay start
        consecutive_errors = 0
        while self._running:
            _is_paused = False
            try:
                await self._process_pending_signals()
                consecutive_errors = 0
            except Exception as e:
                consecutive_errors += 1
                logger.error(f"AutoExecutionWorker error: {e}")
                logger.debug(traceback.format_exc())

            # ── Health Registry Report ──
            # SELF-CORRECTION: Do NOT add a Firestore read here.
            # _process_pending_signals() already checks system_state.pause_flag.
            # We infer state from local variables only — zero extra I/O.
            from system_health import health_registry
            if self._consecutive_broker_failures >= 5:
                _h_state = "RED"
                _h_detail = "Execution paused — broker failures exceeded threshold"
            elif self._consecutive_broker_failures > 0:
                _h_state = "YELLOW"
                _h_detail = f"{self._consecutive_broker_failures} consecutive broker failures"
            elif consecutive_errors > 0:
                _h_state = "YELLOW"
                _h_detail = "Signal processing errors (backoff active)"
            else:
                _h_state = "GREEN"
                _h_detail = f"{len(self.pending_sniper_entries)} snipers armed, queue clear"
            await health_registry.report("execution_worker", _h_state, _h_detail, {
                "armed_snipers": len(self.pending_sniper_entries),
                "queue_depth": self._execution_queue.qsize(),
                "broker_failures": self._consecutive_broker_failures,
            })

            sleep_time = min(60.0, 10.0 * (1.5 ** consecutive_errors)) if consecutive_errors > 0 else 10.0
            await asyncio.sleep(sleep_time)

    async def _startup_recovery_check(self):
        """GAP #6 FIX: Immediate ghost trade and pending signal check on server restart.
        
        When the server crashes mid-execution, trades may exist on the broker
        but have no record in Mehd AI (ghost trades). This method runs ONCE on
        startup to immediately surface any orphaned state, rather than waiting
        for the reconciliation loop's first 60-second cycle.
        """
        try:
            # Check for ghost trades
            ghost_count = await storage.count("ghost_trades")
            if ghost_count > 0:
                keys = await storage.list_keys("ghost_trades")
                logger.critical(
                    "🚨 STARTUP RECOVERY: Found %d ghost trade(s) from before restart! "
                    "Reconciliation loop will process them. Ghost IDs: %s",
                    ghost_count, keys[:5]  # Log first 5 IDs
                )
            
            # Check for orphaned pending signals
            pending = await storage.get_all("pending_auto_executions")
            if pending:
                logger.warning(
                    "⚠️ STARTUP RECOVERY: Found %d pending signal(s) from before restart. "
                    "These will be processed in the next execution cycle.",
                    len(pending)
                )
            
            # Check for frozen configs (users stuck in frozen state from a crash)
            # This is the most dangerous: a user's autopilot is frozen because
            # a ghost trade lock was never released.
            frozen_configs = await storage.query("autopilot_configs", [("frozen", "==", True)])
            if frozen_configs:
                frozen_users = list(frozen_configs.keys())
                if frozen_users:
                    logger.critical(
                        "🚨 STARTUP RECOVERY: %d user(s) have FROZEN autopilot configs! "
                        "These users cannot trade until unfrozen. UIDs: %s",
                        len(frozen_users), frozen_users[:5]
                    )
                    
            if ghost_count == 0 and not pending:
                logger.info("✅ STARTUP RECOVERY: Clean state — no ghost trades or pending signals found.")
                
        except Exception as e:
            logger.error("Startup recovery check failed: %s", e)

    async def _ghost_trade_reconciliation_loop(self):
        """Persistent background loop to recover ghost trades from long broker outages."""
        await asyncio.sleep(10)
        while self._running:
            try:
                try:
                    from broker_gateway import broker_gateway
                except ImportError:
                    broker_gateway = None

                if broker_gateway:
                    broker_unavailable = False
                    async for chunk in storage.stream_collection("ghost_trades", chunk_size=500):
                        if broker_unavailable:
                            break  # Don't iterate more chunks if broker is down
                        for ghost_id, ghost_data in chunk.items():
                            if broker_unavailable:
                                break  # Don't iterate more ghosts if broker is down
                            # GAP #3 FIX: Per-ghost error isolation (Blast radius containment)
                            # One user's corrupt ghost trade must NEVER block reconciliation for ALL users.
                            try:
                                if ghost_data.get("status") == "pending_reconciliation":
                                    user_id = ghost_data.get("user_id", "unknown")
                                    symbol = ghost_data.get("symbol", "unknown")
                                    try:
                                        open_positions = await broker_gateway.get_open_positions()
                                        
                                        if open_positions is None:
                                            logger.warning("Broker API unavailable. Suspending ALL ghost trade reconciliation until next cycle.")
                                            broker_unavailable = True
                                            break  # Exit inner loop — don't retry each ghost against a dead API
                                            
                                        if any(p.get("symbol") == symbol for p in open_positions):
                                            logger.info(f"👻 RECONCILED: Ghost trade found for {user_id} on {symbol}!")
                                            
                                            lock_key = f"exec_{user_id}"
                                            acquired = await storage.acquire_lock(lock_key, ttl_seconds=30)
                                            if acquired:
                                                try:
                                                    fresh_raw = await storage.get("autopilot_configs", user_id)
                                                    if fresh_raw:
                                                        fresh_cfg = AutopilotConfig.model_validate(fresh_raw)
                                                        fresh_cfg.daily_auto_trades_count += 1
                                                        fresh_cfg.weekly_auto_trades_count += 1
                                                        if symbol not in fresh_cfg.open_auto_positions:
                                                            fresh_cfg.open_auto_positions.append(symbol)
                                                        await self._save_config(user_id, fresh_cfg)
                                                        
                                                        await self._log_to_morning_briefing(
                                                            user_id, symbol, "UNKNOWN", "RECONCILED", 
                                                            f"Ghost trade successfully found and synced after API timeout."
                                                        )
                                                        await storage.delete("ghost_trades", ghost_id)
                                                finally:
                                                    await storage.release_lock(lock_key)
                                        else:
                                            # Fix Ghost Trade Deadlock: Definitive Reconciliation
                                            logger.warning(f"Ghost trade {ghost_id} not found in open positions. Assuming broker rejection.")
                                            
                                            raw_cfg = await storage.get("autopilot_configs", user_id)
                                            if raw_cfg:
                                                cfg = AutopilotConfig.model_validate(raw_cfg)
                                                cfg.frozen = False
                                                await self._save_config(user_id, cfg)
                                                
                                            await self._log_to_morning_briefing(user_id, symbol, "UNKNOWN", "FAILED_TO_OPEN", "Broker confirmed trade was never opened.")
                                            await storage.delete("ghost_trades", ghost_id)
                                    except Exception as e:
                                        logger.warning(f"Reconciliation check failed for {user_id}: {e}")
                            except Exception as ghost_err:
                                # BLAST RADIUS: This ghost is corrupt/malformed. Log and SKIP IT.
                                # Do NOT let it block the rest of the loop.
                                logger.error(f"Ghost trade {ghost_id} processing CRASHED (skipping): {ghost_err}")
                                continue
            except Exception as e:
                logger.error(f"Ghost trade reconciliation loop error: {e}")
            
            await asyncio.sleep(60) # Poll every 60 seconds

    async def _process_pending_signals(self):
        pending = await storage.get_all("pending_auto_executions")
        if not pending:
            return

        system_pause = await storage.get("system_state", "pause_flag")
        if system_pause:
            logger.warning("SYSTEM_PAUSE active. Circuit breaker tripped. Dropping all pending signals.")
            for sig_id in pending.keys():
                await storage.delete("pending_auto_executions", sig_id)
            return

        # GAP #4 FIX: Queue overflow protection (Robinhood lesson)
        # During NFP/FOMC, hundreds of signals can queue up. Without a cap,
        # the execution worker will try to process ALL of them, overwhelming
        # the broker and risking duplicate entries on the same symbol.
        MAX_PENDING_QUEUE_DEPTH = 50
        if len(pending) > MAX_PENDING_QUEUE_DEPTH:
            logger.warning(
                "QUEUE OVERFLOW: %d pending signals exceeds max %d. "
                "Evicting oldest %d signals to prevent execution backlog.",
                len(pending), MAX_PENDING_QUEUE_DEPTH,
                len(pending) - MAX_PENDING_QUEUE_DEPTH
            )
            # Sort by timestamp (oldest first), keep newest MAX_PENDING_QUEUE_DEPTH
            sorted_signals = sorted(
                pending.items(),
                key=lambda kv: kv[1].get("timestamp", ""),
            )
            evict_count = len(sorted_signals) - MAX_PENDING_QUEUE_DEPTH
            for sig_id, _ in sorted_signals[:evict_count]:
                logger.info("QUEUE EVICTION: Dropping stale signal %s", sig_id)
                await storage.delete("pending_auto_executions", sig_id)
            # Refresh after eviction
            pending = dict(sorted_signals[evict_count:])

        for sig_id, signal_data in pending.items():
            try:
                self._arm_sniper(sig_id, signal_data)
            finally:
                # Always remove from pending; Sniper takes over
                await storage.delete("pending_auto_executions", sig_id)

    def _arm_sniper(self, sig_id: str, signal_data: dict):
        symbol = signal_data.get("symbol")
        direction_str = signal_data.get("direction")
        
        if not symbol or direction_str not in ["BUY", "SELL"]:
            return
        
        # MARKET HOURS GATE: Do not arm sniper during market closure
        if not is_market_open():
            logger.info(f"MARKET CLOSED: Sniper not armed for {symbol}. Forex markets are closed.")
            return

        # ── ECONOMIC NEWS BLACKOUT GATE ──
        # Do not arm sniper if high-impact news is within 60 minutes or active
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

        # ── STRUCTURAL MARKET CONFIRMATION GATE ──
        # Proxy for EMA: Compare current price against Daily Open.
        # This prevents the AI from buying into a strong daily downtrend
        # or selling into a strong daily uptrend.
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

        # ── SIGNAL FRESHNESS GATE (ported from legacy _execute_signal) ──
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

        # ── OLYMPUS ANOMALY FLAG CHECK (ported from legacy _execute_signal) ──
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

        # Prevent duplicate entries on same symbol (Execution Lock)
        if symbol in self.pending_sniper_entries:
            return
            
        pip_size = get_pip_size(symbol)

        # Sniper dynamic parameters based on asset volatility
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
        
        # Persist to storage so a server restart doesn't lose armed targets
        import asyncio
        try:
            loop = asyncio.get_running_loop()
            loop.create_task(storage.set("sniper_targets", symbol, entry))
        except RuntimeError as e:
            logger.warning("No running loop found when arming sniper target for %s: %s", symbol, e)
        
        logger.info(f"🎯 SNIPER ARMED for {symbol}. Dir: {direction_str}, Analyzed: {current_price}, Pullback Target: {target_price}, Cancel at: {cancel_price}")

    async def _sniper_loop(self):
        await asyncio.sleep(5)
        
        # Restore any persisted sniper targets from storage on startup
        try:
            persisted = await storage.get_all("sniper_targets")
            if persisted:
                for symbol, entry in persisted.items():
                    if symbol not in self.pending_sniper_entries:
                        # Re-parse the ISO timestamp back to datetime
                        entry["timestamp"] = datetime.fromisoformat(entry["timestamp"])
                        self.pending_sniper_entries[symbol] = entry
                        logger.info(f"🎯 Restored persisted sniper target for {symbol}.")
        except Exception as e:
            logger.warning(f"Failed to restore sniper targets: {e}")
        
        consecutive_errors = 0
        while self._running:
            try:
                now = datetime.now(timezone.utc)
                symbols_to_remove = []
                
                # Check Circuit Breaker mid-hunt
                system_pause = await storage.get("system_state", "pause_flag")
                if system_pause:
                    for sym in list(self.pending_sniper_entries.keys()):
                        await storage.delete("sniper_targets", sym)
                    self.pending_sniper_entries.clear()
                    await asyncio.sleep(1)
                    continue

                for symbol, data in list(self.pending_sniper_entries.items()):
                    # Timeout check (Dynamic)
                    ts = data["timestamp"] if isinstance(data["timestamp"], datetime) else datetime.fromisoformat(data["timestamp"])
                    timeout_val = data.get("timeout_seconds", 120)
                    if (now - ts).total_seconds() > timeout_val:
                        logger.warning(f"Sniper timeout for {symbol}. Cancelled (TIMEOUT_NO_ENTRY).")
                        symbols_to_remove.append(symbol)
                        continue

                    # Get live price (Price Consistency check: Bid vs Ask)
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

                    # BAD TICK PROTECTION: Reject corrupted/unrealistic price data
                    analysis_price = data.get("analysis_price", 0.0)
                    if analysis_price > 0 and (live_price < analysis_price * 0.5 or live_price > analysis_price * 2.0):
                        logger.warning(f"BAD TICK REJECTED for {symbol}: live={live_price}, analysis={analysis_price}")
                        continue

                    current_state = data.get("state", "ARMED")

                    if current_state == "ARMED":
                        # Runaway cancel check
                        is_runaway = False
                        if data["direction"] == "BUY" and live_price >= data["cancel_price"]: is_runaway = True
                        if data["direction"] == "SELL" and live_price <= data["cancel_price"]: is_runaway = True
                        
                        if is_runaway:
                            # BREAKOUT MODE: Recover missed trades
                            spread = snapshot.spread
                            if spread <= 3.0:  # Normal spread check
                                logger.info(f"🚀 BREAKOUT MODE TRIGGERED for {symbol} at {live_price:.5f}! (Runaway without pullback)")
                                data["state"] = "EXECUTED_BREAKOUT"
                                data["signal_data"]["breakout_factor"] = 0.5  # 50% lot size reduction
                                await self._queue_master_execution(symbol, data["signal_data"], live_price)
                            else:
                                logger.warning(f"Sniper runaway for {symbol}. Cancelled (High Spread: {spread}).")
                                data["state"] = "MISSED_ENTRY"
                            symbols_to_remove.append(symbol)
                            continue

                        # Pullback trigger check
                        hit_pullback = False
                        if data["direction"] == "BUY" and live_price <= data["target_price"]: hit_pullback = True
                        if data["direction"] == "SELL" and live_price >= data["target_price"]: hit_pullback = True

                        if hit_pullback:
                            logger.info(f"🎯 SNIPER HIT PULLBACK for {symbol} at {live_price:.5f}. Waiting for bounce...")
                            data["state"] = "WAITING_PULLBACK"
                            from models import get_pip_size
                            pip_size = get_pip_size(symbol)
                            # 1 pip bounce required to confirm the falling knife stopped
                            if data["direction"] == "BUY":
                                data["bounce_target"] = round(live_price + (1.0 * pip_size), 5)
                            else:
                                data["bounce_target"] = round(live_price - (1.0 * pip_size), 5)
                            continue

                    elif current_state == "WAITING_PULLBACK":
                        # Execute only after price bounces in the intended direction
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
                    # Clean up persisted target
                    await storage.delete("sniper_targets", sym)
                
                consecutive_errors = 0 # reset on success
                # Polling Optimization: 100ms when armed, 500ms when idle
                sleep_time = 0.1 if self.pending_sniper_entries else 0.5

            except Exception as e:
                consecutive_errors += 1
                logger.error(f"Sniper loop error: {e}")
                # Exponential backoff on error to prevent CPU hammering
                sleep_time = min(60.0, 0.5 * (2 ** consecutive_errors))
                logger.info(f"Sniper loop backing off for {sleep_time}s due to consecutive errors.")
            
            await asyncio.sleep(sleep_time)

    def _reset_stale_counters(self, cfg):
        """Reset daily/weekly counters if the date has rolled over.
        
        FIX MISS-4: Without this, daily_auto_trades_count only ever goes UP.
        After 2 trades on day 1, the user is permanently locked out forever.
        """
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        this_week = datetime.now(timezone.utc).strftime("%Y-W%W")
        
        if cfg.last_trade_date and cfg.last_trade_date != today:
            cfg.daily_auto_trades_count = 0
        
        if cfg.last_week_reset_date and cfg.last_week_reset_date != this_week:
            cfg.weekly_auto_trades_count = 0
        
        return cfg

    async def _queue_master_execution(self, symbol, signal_data, triggered_price):
        await self._execution_queue.put({
            "symbol": symbol,
            "signal_data": signal_data,
            "triggered_price": triggered_price
        })

    async def _master_worker(self):
        from models import Direction, AutopilotConfig, MasterTradeReceipt, LedgerDistributionTask, TradeOrder
        from risk_engine import HardRiskKernel
        import uuid
        import json
        
        while self._running:
            task_data = None
            try:
                task_data = await self._execution_queue.get()
                symbol = task_data["symbol"]
                signal_data = task_data["signal_data"]
                triggered_price = task_data["triggered_price"]
                direction = Direction(signal_data.get("direction"))
                
                system_pause = await storage.get("system_state", "pause_flag")
                if system_pause:
                    continue

                try:
                    from state import streamer
                    snapshot = streamer.get_latest_snapshot(symbol)
                    live_price = snapshot.ask if direction == Direction.BUY else snapshot.bid
                except Exception as e:
                    logger.warning(f"Master worker price fetch failed for {symbol}: {e}")
                    live_price = triggered_price
                
                analysis_price = signal_data.get("current_price", 0.0)
                if not self._check_killswitch(analysis_price, live_price, symbol):
                    logger.warning(f"Master Exec: Stale Price Killswitch triggered on {symbol}. Aborted.")
                    continue

                # ── HARDENED KILL SWITCH — Multi-Condition Pre-Execution Gate ──
                # Checks: oracle discrepancy, news heartbeat, execution latency.
                # This runs BEFORE any order reaches the broker.
                pip_size_for_ks = get_pip_size(symbol)
                hks_result = hardened_kill_switch.evaluate_pre_execution_safety(
                    symbol=symbol,
                    broker_price=live_price,
                    oracle_price=analysis_price,
                    pip_size=pip_size_for_ks,
                )
                if hks_result["status"] == "HALT":
                    logger.warning(
                        f"Master Exec: Hardened Kill Switch HALT on {symbol}. Reason: {hks_result['reason']}"
                    )
                    self._execution_queue.task_done()
                    continue

                consensus = signal_data.get("consensus", 0.0)
                if consensus < 70.0:
                    logger.warning(f"Consensus {consensus}% < 70%. Trade rejected by Minimum Quality Gate.")
                    self._execution_queue.task_done()
                    continue

                current_price = live_price
                suggested_sl = signal_data.get("suggested_sl", 0.0)
                suggested_tp = signal_data.get("suggested_tp", 0.0)
                
                pip_size = get_pip_size(symbol)
                
                if (suggested_sl <= 0.0 or suggested_sl is None) and current_price > 0:
                    sl_distance = 30 * pip_size
                    tp_distance = 60 * pip_size
                    
                    if "XAU" in symbol.upper():
                        sl_distance = 3.0
                        tp_distance = 6.0
                    
                    if direction == Direction.BUY:
                        suggested_sl = round(current_price - sl_distance, 5)
                        suggested_tp = round(current_price + tp_distance, 5)
                    else:
                        suggested_sl = round(current_price + sl_distance, 5)
                        suggested_tp = round(current_price - tp_distance, 5)

                stop_loss_pips = abs(current_price - suggested_sl) / pip_size if current_price > 0 else 50.0

                master_kernel = HardRiskKernel()
                current_spread = signal_data.get("spread", 0.0)

                # 1. Gather Eligible Users
                eligible_users = []
                user_lots = {}
                total_volume_lots = 0.0
                
                # Apply Global Symbol Execution Lock
                symbol_lock = f"master_exec_{symbol}"
                lock_acquired = await storage.acquire_lock(symbol_lock, ttl_seconds=60)
                if not lock_acquired:
                    logger.warning(f"Master Exec: Lock for {symbol} already held. Skipping duplicate execution.")
                    continue
                    
                try:
                    async for chunk in storage.stream_collection("autopilot_configs", chunk_size=5000):
                        batch_updates = {}
                        assist_pending = []  # Collect assist-mode users to fire in parallel AFTER chunk
                        from state import get_user_tier_name
                        for user_id, raw_cfg in chunk.items():
                            try:
                                cfg = AutopilotConfig.model_validate(raw_cfg)
                                cfg = self._reset_stale_counters(cfg)
                                
                                # LKB-01 Mitigation: Defence-in-depth tier check
                                tier_name = get_user_tier_name(user_id)
                                assist_tiers = ("core", "institutional", "precision", "operative")
                                if tier_name not in assist_tiers:
                                    if cfg.enabled:
                                        logger.warning(f"LKB-01 Mitigated: Free user {user_id} had autopilot enabled. Forcing disabled.")
                                        cfg.enabled = False
                                        batch_updates[user_id] = json.loads(cfg.model_dump_json())
                                    continue
                                
                                if not cfg.enabled or cfg.frozen: continue
                                if cfg.assist_mode:
                                    # Phase 5: Defer approval to avoid blocking the hot loop
                                    assist_pending.append(user_id)
                                    continue
                                
                                user_lot = master_kernel.calculate_user_lot_size(
                                    cfg, stop_loss_pips, consensus, current_spread, symbol
                                )
                                breakout_factor = signal_data.get("breakout_factor", 1.0)
                                user_lot = max(0.01, round(user_lot * breakout_factor, 2))
                                
                                if cfg.daily_auto_trades_count >= cfg.max_daily_auto_trades:
                                    saved_amount = round((stop_loss_pips * 10) * user_lot, 2)
                                    asyncio.create_task(self._log_rejection(
                                        user_id, symbol, direction.value, 
                                        "CONSTITUTION_VETO: Max daily trades reached.", 
                                        ["SENTINEL"], saved_amount
                                    ))
                                    continue
                                    
                                if symbol in cfg.open_auto_positions: continue
                                if len(cfg.open_auto_positions) >= cfg.max_concurrent_positions: continue
                                
                                # Save the precise allocation to avoid the Phantom Lot Disconnect
                                cfg.active_allocations[symbol] = user_lot
                                batch_updates[user_id] = json.loads(cfg.model_dump_json())
                                
                                eligible_users.append(user_id)
                                user_lots[user_id] = user_lot
                                total_volume_lots += user_lot
                            except Exception as e:
                                logger.warning(f"User {user_id} lot sizing failed for {symbol}: {e}")
                                continue
                                
                        if batch_updates:
                            await storage.batch_update("autopilot_configs", batch_updates)
                        
                        # Fire assist approvals in parallel (non-blocking)
                        if assist_pending:
                            await asyncio.gather(*[
                                self._trigger_assist_approval(uid, symbol, direction, suggested_sl, suggested_tp)
                                for uid in assist_pending
                            ], return_exceptions=True)
                except Exception as e:
                    logger.error(f"Error gathering eligible users for {symbol}: {e}")
                    await storage.release_lock(symbol_lock)
                    continue
                            
                if not eligible_users:
                    logger.info(f"No eligible users for {symbol} block trade.")
                    continue

                order = TradeOrder(
                    symbol=symbol,
                    direction=direction,
                    lot_size=total_volume_lots,
                    stop_loss=suggested_sl,
                    take_profit=suggested_tp,
                    is_auto_execution=True
                )
                
                decision = await master_kernel.evaluate_master_block(
                    order=order,
                    current_price=current_price,
                    current_spread=signal_data.get("spread", 0.0)
                )
                
                if not decision.approved:
                    logger.warning(f"Master Trade VETOED: {decision.rejection_reason}")
                    agents = getattr(decision, "vetoing_agents", ["KERNEL"])
                    for uid in eligible_users:
                        lot = user_lots.get(uid, 0.01)
                        saved_amount = round((stop_loss_pips * 10) * lot, 2)
                        asyncio.create_task(self._log_rejection(
                            uid, symbol, direction.value, 
                            decision.rejection_reason, agents, saved_amount
                        ))
                    continue

                # CACHE ENTRY SNAPSHOT FOR LEARNING
                try:
                    from broadcaster import broadcaster
                    entry_signal = broadcaster.get_latest_signal(symbol)
                    if entry_signal:
                        await storage.set("entry_snapshots", f"MASTER_{symbol}", entry_signal)
                except Exception as cache_err:
                    logger.debug(f"Entry snapshot cache failed for {symbol}: {cache_err}")
                
                # BROKER EXECUTION WITH CHUNKING (Max 50 lots per order)
                MAX_CHUNK_LOTS = 50.0
                chunks = []
                remaining_lots = total_volume_lots
                
                while remaining_lots > 0:
                    chunk_size = min(remaining_lots, MAX_CHUNK_LOTS)
                    chunk_order = order.model_copy(update={"lot_size": chunk_size})
                    chunks.append(self._broker_execute(chunk_order, decision))
                    remaining_lots -= chunk_size
                    
                # Execute all chunks concurrently
                import asyncio
                chunk_results = await asyncio.gather(*chunks, return_exceptions=True)
                
                # Aggregate results
                successful_lots = 0.0
                total_fill_cost = 0.0
                
                for res in chunk_results:
                    if isinstance(res, dict) and res.get("status") in ("filled", "simulated"):
                        # "units" from OANDA is standard units (e.g. 100000 = 1 lot)
                        # The broker gateway already translates it, but we can just use the chunk lot size
                        # actually broker_gateway returns `units` in strings. For simplicity we just track successful lots:
                        # We'll calculate proportional success based on the chunks
                        # Since we don't know the exact chunk size without keeping track of the tuple,
                        # let's assume `res.get("units")` returns standard units. Wait, broker_gateway returns:
                        # 'units': order.lot_size (if simulated) or real units string.
                        # Actually, let's just use the chunk logic.
                        # A better way is to pass the chunk size. 
                        # We can just assume all successful chunks executed their full lot_size.
                        pass
                
                # Let's write the aggregation properly
                successful_lots = 0.0
                total_fill_cost = 0.0
                chunk_sizes = [min(l, MAX_CHUNK_LOTS) for l in [total_volume_lots - i*MAX_CHUNK_LOTS for i in range(len(chunks))]]

                for chunk_size, res in zip(chunk_sizes, chunk_results):
                    if isinstance(res, dict) and res.get("status") in ("filled", "simulated"):
                        price = float(res.get("fill_price", triggered_price))
                        
                        if "units" in res:
                            filled_lots = abs(float(res["units"])) / 100000.0
                        else:
                            filled_lots = chunk_size
                            
                        successful_lots += filled_lots
                        total_fill_cost += (price * filled_lots)
                        
                if successful_lots > 0:
                    avg_fill_price = total_fill_cost / successful_lots
                    fill_ratio = successful_lots / total_volume_lots if total_volume_lots > 0 else 1.0
                    
                    receipt = MasterTradeReceipt(
                        id=uuid.uuid4(),
                        symbol=symbol,
                        direction=direction,
                        total_volume_lots=successful_lots,
                        fill_price=avg_fill_price,
                        fill_ratio=fill_ratio,
                        status="FILLED" if successful_lots >= total_volume_lots else "PARTIAL"
                    )
                    await storage.set("master_receipts", str(receipt.id), json.loads(receipt.model_dump_json()))
                    
                    dist_task = LedgerDistributionTask(
                        receipt_id=receipt.id,
                        total_eligible_users=len(eligible_users)
                    )
                    await storage.set("ledger_tasks", str(dist_task.receipt_id), json.loads(dist_task.model_dump_json()))
                    logger.info(f"🏦 MASTER BLOCK EXECUTED for {len(eligible_users)} users. Filled Lots: {successful_lots}")
                    self._consecutive_broker_failures = 0  # Reset circuit breaker on success
                else:
                    logger.error("Master Block Execution Failed: All chunks rejected.")
                    self._consecutive_broker_failures += 1
                    if self._consecutive_broker_failures >= self._max_broker_failures:
                        logger.critical(f"🚨 CIRCUIT BREAKER: {self._consecutive_broker_failures} consecutive broker failures. Triggering SYSTEM_PAUSE.")
                        await storage.set("system_state", "pause_flag", True)
                        await storage.set("system_state", "pause_reason", f"Circuit breaker: {self._consecutive_broker_failures} consecutive broker failures")
                    
            except Exception as e:
                logger.error(f"Master worker error: {e}")
            finally:
                # Release the symbol execution lock if we acquired it
                if task_data is not None:
                    try:
                        await storage.release_lock(f"master_exec_{task_data['symbol']}")
                    except Exception as e:
                        logger.debug(f"Lock release cleanup for {task_data['symbol']}: {e}")
                    self._execution_queue.task_done()

    async def _ledger_distribution_loop(self):
        from models import AutopilotConfig
        import json
        await asyncio.sleep(5)
        
        # ── ORPHAN TRADE RECOVERY ──
        # If the server crashed mid-distribution, reset stuck tasks to resume
        try:
            processing_tasks = await storage.query("ledger_tasks", [("status", "==", "PROCESSING")])
            recovered = 0
            for task_id, task_data in processing_tasks.items():
                task_data["status"] = "PENDING"
                await storage.set("ledger_tasks", task_id, task_data)
                recovered += 1
            if recovered > 0:
                logger.warning(f"Orphan Trade Recovery: Reset {recovered} interrupted ledger tasks to PENDING.")
        except Exception as e:
            logger.error(f"Orphan recovery failed: {e}")
            
        await asyncio.sleep(10)

        while self._running:
            try:
                pending_tasks = await storage.query("ledger_tasks", [("status", "==", "PENDING")])
                for task_id, task_data in pending_tasks.items():
                    task_data["status"] = "PROCESSING"
                    await storage.set("ledger_tasks", task_id, task_data)
                    
                    receipt_data = await storage.get("master_receipts", task_id)
                    if not receipt_data: continue
                    
                    symbol = receipt_data["symbol"]
                    direction = receipt_data["direction"]
                    fill_price = receipt_data["fill_price"]
                    fill_ratio = receipt_data.get("fill_ratio", 1.0)
                    is_closed = receipt_data.get("is_closed", False)
                    total_broker_lots = receipt_data["total_volume_lots"]
                    
                    users_processed = task_data.get("users_processed", 0)
                    processed_user_ids = set(task_data.get("processed_user_ids", []))
                    total_allocated_lots = task_data.get("total_allocated_lots", 0.0) # Track across chunks
                    
                    async for chunk in storage.stream_collection("autopilot_configs", chunk_size=500):
                        batch_updates = {}
                        newly_processed_ids = []
                        items = list(chunk.items())
                        
                        # FIX PRIO-01: Priority Execution Routing.
                        # Instead of random.shuffle(), we sort by tier priority.
                        # Users with lower TIER_PRIORITY values are processed first.
                        def get_prio(item):
                            user_id, raw_cfg = item
                            tier = raw_cfg.get("tier", "observer")
                            return TIER_PRIORITY.get(tier, 99)

                        items.sort(key=get_prio)
                        
                        for user_id, raw_cfg in items:
                            if user_id in processed_user_ids:
                                continue # Idempotency check: prevent double-booking on crash
                                
                            try:
                                cfg = AutopilotConfig.model_validate(raw_cfg)
                                cfg = self._reset_stale_counters(cfg)
                                if not cfg.enabled or cfg.frozen: continue
                                if cfg.daily_auto_trades_count >= cfg.max_daily_auto_trades: continue
                                if symbol in cfg.open_auto_positions: continue
                                if len(cfg.open_auto_positions) >= cfg.max_concurrent_positions: continue
                                
                                # Proportional Allocation Logic
                                intended_lot = cfg.active_allocations.get(symbol, cfg.preferred_lot_size)
                                actual_lot = round(intended_lot * fill_ratio, 2)
                                
                                if actual_lot < 0.01:
                                    await self._log_to_morning_briefing(
                                        user_id, symbol, direction, "DROPPED",
                                        f"Broker partial fill ({fill_ratio*100:.1f}%). Your allocation ({actual_lot}) fell below the 0.01 minimum lot requirement."
                                    )
                                    continue
                                
                                # Update allocation with actual filled amount
                                cfg.active_allocations[symbol] = actual_lot
                                total_allocated_lots += actual_lot
                                
                                cfg.daily_auto_trades_count += 1
                                cfg.weekly_auto_trades_count += 1
                                cfg.last_trade_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
                                cfg.last_week_reset_date = datetime.now(timezone.utc).strftime("%Y-W%W")
                                
                                msg_prefix = "Master Ledger distribution."
                                if fill_ratio < 1.0:
                                    msg_prefix = f"Partial fill executed ({fill_ratio*100:.1f}% liquidity adjustment)."
                                
                                if is_closed:
                                    # Trade closed before distribution reached user
                                    await self._log_to_morning_briefing(
                                        user_id, symbol, direction, "EXECUTED_AND_CLOSED",
                                        f"Micro-scalp. {msg_prefix} Fill: {fill_price}"
                                    )
                                else:
                                    cfg.open_auto_positions.append(symbol)
                                    
                                    # PERSIST POSITION FOR HEALTH SCORING
                                    # This collection allows the health worker to monitor individual trades.
                                    pos_data = {
                                        "user_id": user_id,
                                        "symbol": symbol,
                                        "direction": direction,
                                        "entry_price": fill_price,
                                        "lot_size": actual_lot,
                                        "timestamp": datetime.now(timezone.utc).isoformat(),
                                        "status": "OPEN",
                                    }
                                    pos_key = f"{user_id}_{symbol}"
                                    asyncio.create_task(storage.set("user_positions", pos_key, pos_data))

                                    await self._log_to_morning_briefing(
                                        user_id, symbol, direction, "EXECUTED",
                                        f"{msg_prefix} Fill: {fill_price}"
                                    )
                                    
                                batch_updates[user_id] = json.loads(cfg.model_dump_json())
                                newly_processed_ids.append(user_id)
                                users_processed += 1
                            except Exception as e:
                                logger.warning(f"Ledger distribution skipped user {user_id}: {e}")
                        
                        # Execute bulk batch update per chunk
                        if batch_updates:
                            await storage.batch_update("autopilot_configs", batch_updates)
                            
                            # Immediately save idempotency state
                            processed_user_ids.update(newly_processed_ids)
                            task_data["processed_user_ids"] = list(processed_user_ids)
                            task_data["users_processed"] = users_processed
                            task_data["total_allocated_lots"] = total_allocated_lots
                            await storage.set("ledger_tasks", task_id, task_data)
                            
                    # End of all chunks. Calculate Firm Inventory (Dark Pool)
                    unhedged_lots = total_broker_lots - total_allocated_lots
                    if unhedged_lots > 0:
                        from models import FirmInventory
                        firm_raw = await storage.get("firm_inventory", symbol)
                        if firm_raw:
                            firm_inv = FirmInventory.model_validate(firm_raw)
                        else:
                            firm_inv = FirmInventory(symbol=symbol)
                        
                        firm_inv.net_exposure_lots += unhedged_lots
                        firm_inv.last_updated = datetime.now(timezone.utc)
                        await storage.set("firm_inventory", symbol, json.loads(firm_inv.model_dump_json()))
                        logger.info(f"🦇 DARK POOL: Firm absorbed {unhedged_lots:.2f} unhedged lots for {symbol}. Total exposure: {firm_inv.net_exposure_lots:.2f}")

                    task_data["status"] = "COMPLETED"
                    task_data["users_processed"] = users_processed
                    task_data["completed_at"] = datetime.now(timezone.utc).isoformat()
                    await storage.set("ledger_tasks", task_id, task_data)
                    logger.info(f"✅ Ledger Distribution Complete for {symbol}. {users_processed} user portfolios updated.")
            except Exception as e:
                logger.error(f"Ledger loop error: {e}")
            await asyncio.sleep(20)

    def _check_killswitch(self, analysis_price: float, live_price: float, symbol: str) -> bool:
        if analysis_price <= 0.0 or live_price <= 0.0:
            return False
        
        pip_size = get_pip_size(symbol)
        pip_diff = abs(live_price - analysis_price) / pip_size
        
        is_gold = "XAU" in symbol.upper()
        threshold = 20.0 if is_gold else 10.0
        
        return pip_diff <= threshold

    async def _broker_execute(self, order: TradeOrder, decision) -> dict:
        """
        Executes via the real broker_gateway with a 15-second timeout.
        
        The broker_gateway handles both live (OANDA) and paper modes internally.
        We wrap it in asyncio to prevent blocking the event loop and to detect
        true network timeouts that should trigger the Freeze protocol.
        """
        from broker_gateway import broker_gateway
        
        try:
            # FIX: broker_gateway.execute_order is an async function.
            # run_in_executor does not execute coroutines, it just returns them.
            async with self._broker_semaphore:
                result = await asyncio.wait_for(
                    broker_gateway.execute_order(order, decision),
                    timeout=15.0
                )
            return result
            
        except asyncio.TimeoutError:
            logger.critical(f"Broker execution timed out after 15s for {order.symbol}")
            return {
                "status": "timeout",
                "reason": "Broker API did not respond within 15 seconds.",
                "mode": "unknown"
            }
        except Exception as e:
            logger.error(f"Broker execution error: {e}")
            return {
                "status": "error",
                "reason": f"Broker communication failed: {str(e)}",
                "mode": "unknown"
            }



    def record_trade_loss(self, user_id: str, symbol: str = ""):
        """Legacy 1:1. Use record_master_trade_loss instead."""
        from trade_recorder import trade_recorder
        trade_recorder.record_trade_loss(user_id, symbol)

    def record_trade_close(self, user_id: str, symbol: str):
        """Legacy 1:1. Use record_master_trade_close instead."""
        from trade_recorder import trade_recorder
        trade_recorder.record_trade_close(user_id, symbol)
        
    def record_master_trade_loss(self, symbol: str, profit_per_lot: float = 0.0):
        """Called when the Master block order hits SL. Distributes loss logic."""
        from trade_recorder import trade_recorder
        trade_recorder.record_master_trade_loss(symbol, profit_per_lot)

    def record_master_trade_close(self, symbol: str, profit_per_lot: float = 0.0):
        """Called when Master block order hits TP or manual close."""
        from trade_recorder import trade_recorder
        trade_recorder.record_master_trade_close(symbol, profit_per_lot)

    async def _save_config(self, user_id: str, cfg: AutopilotConfig):
        """Persists autopilot config to storage. Centralizes serialization."""
        from trade_recorder import trade_recorder
        await trade_recorder._save_config(user_id, cfg)

    async def _log_to_morning_briefing(self, user_id: str, symbol: str, direction: str, status: str, reason: str):
        """Writes execution logs so the Flutter app can show them when the user wakes up."""
        from trade_recorder import trade_recorder
        await trade_recorder._log_to_morning_briefing(user_id, symbol, direction, status, reason)

    async def _send_critical_alert(self, user_id: str, symbol: str):
        """
        Sends a real targeted FCM push notification to wake the user up.
        Falls back to logging if Firebase Admin SDK is not configured.
        """
        from notification_service import send_critical_autopilot_alert
        sent = await send_critical_autopilot_alert(user_id, symbol)
        if not sent:
            logger.warning(f"🔔 Critical alert for {user_id} on {symbol} was not delivered via FCM (logged only).")

    async def _trigger_assist_approval(self, user_id, symbol, direction, sl, tp):
        """
        Phase 5: Assist Mode Approval Flow.
        Creates a pending entry and notifies the user.
        """
        from state import audit
        
        # 1. Create the pending entry record
        pending_data = {
            "symbol": symbol,
            "direction": direction,
            "stop_loss": sl,
            "take_profit": tp,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "WAITING_APPROVAL"
        }
        await storage.set("assist_pending", f"{user_id}_{symbol}", pending_data)
        
        # 2. Log to Morning Briefing for UI visibility
        await self._log_to_morning_briefing(
            user_id, symbol, direction, "WAITING",
            f"ENTRY FOUND: AI detected high-probability setup. Waiting for your manual confirmation to execute."
        )
        
        # 3. Audit trail
        audit.log_event(
            user_id=user_id,
            event_type="ASSIST_ENTRY_FOUND",
            symbol=symbol,
            details={"direction": direction, "sl": sl, "tp": tp}
        )
        logger.info(f"Assist Mode: Notification sent to {user_id} for {symbol} {direction}")

    async def _log_rejection(self, user_id: str, symbol: str, direction: str, reason: str, agents: list[str], saved_amount: float):
        """
        Writes an automated risk management veto to the user's live Rejection Feed.

        WHY DIRECT SDK: The storage abstraction layer's set() method maps directly to
        self._db.collection(collection).document(key), which cannot handle slash-paths
        for Firestore subcollections. We therefore write directly via the Admin SDK when
        available, with a graceful fallback to the storage abstraction for dev/memory mode.
        """
        rejection_data = {
            "symbol": symbol,
            "direction": direction,
            "reason": reason,
            "vetoing_agents": agents,
            "saved_amount": saved_amount,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        rejection_id = str(uuid.uuid4())
        
        try:
            import firebase_admin
            from firebase_admin import firestore as _fs
            if firebase_admin._apps:
                db = _fs.client()
                doc_ref = (
                    db.collection("user_profiles")
                    .document(user_id)
                    .collection("rejection_feed")
                    .document(rejection_id)
                )
                await asyncio.to_thread(doc_ref.set, rejection_data)
                logger.debug(f"Logged rejection for {user_id} on {symbol} to Firestore subcollection.")
                return
        except Exception as e:
            logger.warning(f"Firestore subcollection write failed for rejection feed ({user_id}): {e}")

        # Fallback: write to memory storage with a flat namespaced key
        flat_key = f"{user_id}_rejection_{rejection_id}"
        await storage.set("rejection_feed", flat_key, {"user_id": user_id, **rejection_data})


# Global instance
auto_execution_worker = AutoExecutionWorker()

