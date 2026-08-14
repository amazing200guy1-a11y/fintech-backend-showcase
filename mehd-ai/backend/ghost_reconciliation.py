import asyncio
import logging
from typing import Dict, Any

from storage import storage
from models import AutopilotConfig

logger = logging.getLogger("mehd.ghost_reconciliation")

class GhostReconciliationEngine:
    async def startup_recovery_check(self):
        """Immediate ghost trade and pending signal check on server restart."""
        try:
            ghost_count = await storage.count("ghost_trades")
            if ghost_count > 0:
                keys = await storage.list_keys("ghost_trades")
                logger.critical(
                    "🚨 STARTUP RECOVERY: Found %d ghost trade(s) from before restart! "
                    "Reconciliation loop will process them. Ghost IDs: %s",
                    ghost_count, keys[:5]
                )
            
            pending = await storage.get_all("pending_auto_executions")
            if pending:
                logger.warning(
                    "⚠️ STARTUP RECOVERY: Found %d pending signal(s) from before restart. "
                    "These will be processed in the next execution cycle.",
                    len(pending)
                )
            
            frozen_configs = await storage.query("autopilot_configs", [("frozen", "==", True)])
            if frozen_configs:
                frozen_users = list(frozen_configs.keys())
                if frozen_users:
                    logger.critical(
                        "🚨 STARTUP RECOVERY: %d user(s) have FROZEN autopilot configs! UIDs: %s",
                        len(frozen_users), frozen_users[:5]
                    )
                    
            if ghost_count == 0 and not pending:
                logger.info("✅ STARTUP RECOVERY: Clean state — no ghost trades or pending signals found.")
                
        except Exception as e:
            logger.error("Startup recovery check failed: %s", e)

    async def run_reconciliation_loop(self, is_running_func):
        """Persistent background loop to recover ghost trades from long broker outages."""
        await asyncio.sleep(10)
        while is_running_func():
            try:
                try:
                    from broker_gateway import broker_gateway
                except ImportError:
                    broker_gateway = None

                if broker_gateway:
                    broker_unavailable = False
                    async for chunk in storage.stream_collection("ghost_trades", chunk_size=500):
                        if broker_unavailable:
                            break
                        for ghost_id, ghost_data in chunk.items():
                            if broker_unavailable:
                                break
                            try:
                                if ghost_data.get("status") == "pending_reconciliation":
                                    user_id = ghost_data.get("user_id", "unknown")
                                    symbol = ghost_data.get("symbol", "unknown")
                                    open_positions = await broker_gateway.get_open_positions()
                                    
                                    if open_positions is None:
                                        logger.warning("Broker API unavailable. Suspending ghost trade reconciliation.")
                                        broker_unavailable = True
                                        break
                                        
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
                                                    from trade_recorder import trade_recorder
                                                    await trade_recorder._save_config(user_id, fresh_cfg)
                                            finally:
                                                await storage.release_lock(lock_key)
                                                await storage.delete("ghost_trades", ghost_id)
                            except Exception as ghost_err:
                                logger.error(f"Error reconciling individual ghost trade {ghost_id}: {ghost_err}")
                await asyncio.sleep(60.0)
            except Exception as e:
                logger.error(f"Ghost trade reconciliation loop error: {e}")
                await asyncio.sleep(30.0)

ghost_reconciler = GhostReconciliationEngine()
