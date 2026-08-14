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
from sniper_engine import SniperEngine

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
# Forex & Metals: Sunday 22:00 UTC → Friday 22:00 UTC (24/5)
# Crypto pairs (BTC/USD, etc.): 24/7/365 Non-stop
def is_market_open(symbol: str = "") -> bool:
    """Check if the market for the given symbol is currently open.
    Crypto pairs trade 24/7/365.
    Forex & metals close on weekends (Friday 22:00 UTC → Sunday 22:00 UTC)."""
    sym_upper = symbol.upper()
    if "BTC" in sym_upper or "ETH" in sym_upper or "SOL" in sym_upper or "CRYPTO" in sym_upper:
        return True  # Crypto markets never sleep

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
        self._sniper_engine = SniperEngine(self._queue_master_execution)
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
        from ghost_reconciliation import ghost_reconciler
        await ghost_reconciler.startup_recovery_check()

    async def _ghost_trade_reconciliation_loop(self):
        from ghost_reconciliation import ghost_reconciler
        await ghost_reconciler.run_reconciliation_loop(lambda: self._running)

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

    @property
    def pending_sniper_entries(self):
        return self._sniper_engine.pending_sniper_entries

    def _arm_sniper(self, sig_id: str, signal_data: dict):
        self._sniper_engine.arm_sniper(sig_id, signal_data)

    async def _sniper_loop(self):
        await self._sniper_engine.run_sniper_loop(lambda: self._running)

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
            "triggered_price": triggered_price,
            "queued_at": time.time(),  # SIGNAL AGE GUARD: reject if stale in queue
        })

    async def _master_worker(self):
        from master_execution_engine import run_master_worker
        await run_master_worker(self)


    async def _ledger_distribution_loop(self):
        from mam_ledger_distribution import run_ledger_distribution_loop
        await run_ledger_distribution_loop(self)

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

