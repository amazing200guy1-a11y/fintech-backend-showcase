from __future__ import annotations

import asyncio
import logging
import json
from datetime import datetime, timezone

from storage import storage
from models import AutopilotConfig, FirmInventory

logger = logging.getLogger("mehd.auto_execution")

TIER_PRIORITY = {
    "vip": 1,
    "commander": 2,
    "sovereign": 3,
    "pro": 4,
    "observer": 5,
}


async def run_ledger_distribution_loop(worker_ref) -> None:
    """Background loop that streams user configs and applies MAM trade allocations."""
    await asyncio.sleep(5)
    
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

    while worker_ref._running:
        try:
            pending_tasks = await storage.query("ledger_tasks", [("status", "==", "PENDING")])
            for task_id, task_data in pending_tasks.items():
                task_data["status"] = "PROCESSING"
                await storage.set("ledger_tasks", task_id, task_data)
                
                receipt_data = await storage.get("master_receipts", task_id)
                if not receipt_data:
                    continue
                
                symbol = receipt_data["symbol"]
                direction = receipt_data["direction"]
                fill_price = receipt_data["fill_price"]
                fill_ratio = receipt_data.get("fill_ratio", 1.0)
                is_closed = receipt_data.get("is_closed", False)
                total_broker_lots = receipt_data["total_volume_lots"]
                
                users_processed = task_data.get("users_processed", 0)
                processed_user_ids = set(task_data.get("processed_user_ids", []))
                total_allocated_lots = task_data.get("total_allocated_lots", 0.0)
                
                async for chunk in storage.stream_collection("autopilot_configs", chunk_size=500):
                    batch_updates = {}
                    newly_processed_ids = []
                    items = list(chunk.items())
                    
                    def get_prio(item):
                        user_id, raw_cfg = item
                        tier = raw_cfg.get("tier", "observer")
                        return TIER_PRIORITY.get(tier, 99)

                    items.sort(key=get_prio)
                    
                    for user_id, raw_cfg in items:
                        if user_id in processed_user_ids:
                            continue
                            
                        try:
                            cfg = AutopilotConfig.model_validate(raw_cfg)
                            cfg = worker_ref._reset_stale_counters(cfg)
                            if not cfg.enabled or cfg.frozen:
                                continue
                            if cfg.daily_auto_trades_count >= cfg.max_daily_auto_trades:
                                continue
                            if symbol in cfg.open_auto_positions:
                                continue
                            if len(cfg.open_auto_positions) >= cfg.max_concurrent_positions:
                                continue
                            
                            intended_lot = cfg.active_allocations.get(symbol, cfg.preferred_lot_size)
                            actual_lot = round(intended_lot * fill_ratio, 2)
                            
                            if actual_lot < 0.01:
                                await worker_ref._log_to_morning_briefing(
                                    user_id, symbol, direction, "DROPPED",
                                    f"Broker partial fill ({fill_ratio*100:.1f}%). Your allocation ({actual_lot}) fell below the 0.01 minimum lot requirement."
                                )
                                continue
                            
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
                                await worker_ref._log_to_morning_briefing(
                                    user_id, symbol, direction, "EXECUTED_AND_CLOSED",
                                    f"Micro-scalp. {msg_prefix} Fill: {fill_price}"
                                )
                            else:
                                cfg.open_auto_positions.append(symbol)
                                
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

                                await worker_ref._log_to_morning_briefing(
                                    user_id, symbol, direction, "EXECUTED",
                                    f"{msg_prefix} Fill: {fill_price}"
                                )
                                
                            batch_updates[user_id] = json.loads(cfg.model_dump_json())
                            newly_processed_ids.append(user_id)
                            users_processed += 1
                        except Exception as e:
                            logger.warning(f"Ledger distribution skipped user {user_id}: {e}")
                    
                    if batch_updates:
                        await storage.batch_update("autopilot_configs", batch_updates)
                        
                        processed_user_ids.update(newly_processed_ids)
                        task_data["processed_user_ids"] = list(processed_user_ids)
                        task_data["users_processed"] = users_processed
                        task_data["total_allocated_lots"] = total_allocated_lots
                        await storage.set("ledger_tasks", task_id, task_data)
                        
                unhedged_lots = total_broker_lots - total_allocated_lots
                if unhedged_lots > 0:
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
