import asyncio
import logging
from datetime import datetime, timezone, timedelta

from storage import storage
import broker_scanner

logger = logging.getLogger("mehd.cleanup_worker")

class CleanupWorker:
    """
    Background daemon that periodically scrubs expired data from the storage engine.
    This prevents memory leaks (if using MemoryStorage) and database bloat (if using Firestore)
    for collections that do not have native TTLs enabled.
    """
    def __init__(self):
        self._running = False
        self._task = None

    def start(self):
        if not self._running:
            self._running = True
            self._task = asyncio.create_task(self._loop())
            logger.info("🧹 Cleanup Worker started.")

    def stop(self):
        self._running = False
        if self._task:
            self._task.cancel()
            logger.info("🧹 Cleanup Worker stopped.")

    async def _loop(self):
        await asyncio.sleep(60)  # Wait a minute before first run
        while self._running:
            try:
                await self._cleanup_morning_briefings()
                await self._cleanup_pending_signals()
                await self._cleanup_expired_broadcasts()
                await self._reset_daily_budget_if_needed()
                await self._aggregate_broker_health_if_due()
            except asyncio.CancelledError:
                break  # Graceful shutdown — don't log as error
            except Exception as e:
                logger.error(f"CleanupWorker error: {e}")
            
            # Run every hour
            try:
                await asyncio.sleep(3600)
            except asyncio.CancelledError:
                break

    async def _reset_daily_budget_if_needed(self):
        """Resets the daily AI spend limit to $0.00 at UTC midnight."""
        import state
        from storage import storage
        data = await storage.get("system_config", "budget")
        if data:
            last_updated = data.get("last_updated")
            if last_updated:
                try:
                    last_dt = datetime.fromisoformat(last_updated)
                    if last_dt.date() < datetime.now(timezone.utc).date():
                        await state.reset_daily_spend()
                        logger.info("🧹 Midnight reached. Daily API budget reset to $0.00.")
                except ValueError:
                    pass

    async def _aggregate_broker_health_if_due(self):
        """Runs the broker health aggregation once per day (at the first hourly cycle after midnight)."""
        last_run = await storage.get("system_config", "broker_health_last_run")
        today    = datetime.now(timezone.utc).date().isoformat()
        if last_run and last_run.get("date") == today:
            return  # Already ran today
        await broker_scanner.aggregate_broker_health()
        await storage.set("system_config", "broker_health_last_run", {"date": today})
        logger.info("📊 Broker health aggregation completed for %s.", today)

    async def _cleanup_morning_briefings(self):
        """Deletes morning briefing logs that have passed their expires_at TTL."""
        briefings = await storage.get_all("morning_briefing_logs")
        if not briefings:
            return

        now = datetime.now(timezone.utc)
        deleted_count = 0
        
        for key, data in briefings.items():
            expires_at_str = data.get("expires_at")
            if expires_at_str:
                try:
                    expires_at = datetime.fromisoformat(expires_at_str)
                    if now > expires_at:
                        await storage.delete("morning_briefing_logs", key)
                        deleted_count += 1
                except ValueError as e:
                    logger.warning("Failed to parse expires_at for %s: %s", key, e)
                    
        if deleted_count > 0:
            logger.info(f"🧹 Cleaned up {deleted_count} expired morning briefings.")

    async def _cleanup_pending_signals(self):
        """Deletes pending signals that are older than 1 hour (extreme safety catch-all)."""
        pending = await storage.get_all("pending_auto_executions")
        if not pending:
            return

        now = datetime.now(timezone.utc)
        deleted_count = 0
        
        for key, data in pending.items():
            broadcast_time_str = data.get("broadcast_time")
            if broadcast_time_str:
                try:
                    broadcast_time = datetime.fromisoformat(broadcast_time_str)
                    age_hours = (now - broadcast_time).total_seconds() / 3600
                    if age_hours > 1.0:
                        await storage.delete("pending_auto_executions", key)
                        deleted_count += 1
                except ValueError as e:
                    logger.warning("Failed to parse broadcast_time for pending signal %s: %s", key, e)
                    
        if deleted_count > 0:
            logger.info(f"🧹 Cleaned up {deleted_count} hopelessly stale pending signals.")

    async def _cleanup_expired_broadcasts(self):
        """Deletes broadcast_history signals that have been EXPIRED for more than 24 hours.
        This prevents unbounded Firestore growth (~3,700 docs/day)."""
        broadcasts = await storage.get_all("broadcast_history")
        if not broadcasts:
            return

        now = datetime.now(timezone.utc)
        cutoff = now - timedelta(hours=24)
        deleted_count = 0

        for key, data in broadcasts.items():
            status = data.get("status", "")
            if status not in ("EXPIRED", "INVALIDATED"):
                continue

            broadcast_time_str = data.get("broadcast_time")
            if broadcast_time_str:
                try:
                    broadcast_time = datetime.fromisoformat(broadcast_time_str)
                    if broadcast_time < cutoff:
                        await storage.delete("broadcast_history", key)
                        deleted_count += 1
                except ValueError:
                    # Unparseable timestamp — delete it to prevent permanent orphan
                    await storage.delete("broadcast_history", key)
                    deleted_count += 1

        if deleted_count > 0:
            logger.info(f"🧹 Cleaned up {deleted_count} expired/invalidated broadcast signals.")

cleanup_worker = CleanupWorker()
