from __future__ import annotations

import asyncio
import logging
import time
import uuid
import json
import random
from datetime import datetime, timezone

from models import Direction, AutopilotConfig, MasterTradeReceipt, LedgerDistributionTask, TradeOrder
from risk_engine import HardRiskKernel
from storage import storage
from hardened_kill_switch import hardened_kill_switch
from models import get_pip_size

logger = logging.getLogger("mehd.auto_execution")


async def run_master_worker(worker_ref) -> None:
    """Master execution engine processing queued AI signals into broker trade orders."""
    while worker_ref._running:
        task_data = None
        try:
            task_data = await worker_ref._execution_queue.get()
            symbol = task_data["symbol"]
            signal_data = task_data["signal_data"]
            triggered_price = task_data["triggered_price"]

            queued_at = task_data.get("queued_at", time.time())
            signal_age = time.time() - queued_at
            MAX_SIGNAL_QUEUE_AGE = 60.0
            if signal_age > MAX_SIGNAL_QUEUE_AGE:
                logger.warning(
                    "STALE SIGNAL EVICTED: %s signal was %.1fs old in queue (max %.0fs). "
                    "Skipping to protect users from stale price execution.",
                    symbol, signal_age, MAX_SIGNAL_QUEUE_AGE
                )
                worker_ref._execution_queue.task_done()
                continue

            await asyncio.sleep(random.uniform(0.08, 0.30))

            system_pause = await storage.get("system_state", "pause_flag")
            if system_pause:
                continue

            direction_str = signal_data.get("direction", "BUY").upper()
            direction = Direction.BUY if direction_str == "BUY" else Direction.SELL

            try:
                from state import streamer
                snapshot = streamer.get_latest_snapshot(symbol)
                live_price = snapshot.ask if direction == Direction.BUY else snapshot.bid
            except Exception as e:
                logger.warning(f"Master worker price fetch failed for {symbol}: {e}")
                live_price = triggered_price
            
            analysis_price = signal_data.get("current_price", 0.0)
            if not worker_ref._check_killswitch(analysis_price, live_price, symbol):
                logger.warning(f"Master Exec: Stale Price Killswitch triggered on {symbol}. Aborted.")
                continue

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
                worker_ref._execution_queue.task_done()
                continue

            consensus = signal_data.get("consensus", 0.0)
            if consensus < 70.0:
                logger.warning(f"Consensus {consensus}% < 70%. Trade rejected by Minimum Quality Gate.")
                worker_ref._execution_queue.task_done()
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

            eligible_users = []
            user_lots = {}
            total_volume_lots = 0.0
            
            got_lock = await storage.acquire_lock(f"master_exec_{symbol}", ttl_seconds=30)
            if not got_lock:
                logger.warning(f"Master Exec: Could not acquire symbol lock for {symbol}. Order already processing. Skipping.")
                worker_ref._execution_queue.task_done()
                continue

            async for chunk in storage.stream_collection("autopilot_configs", chunk_size=500):
                for user_id, raw_cfg in chunk.items():
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
                        
                        risk_eval = master_kernel.evaluate_trade(
                            account_balance=cfg.account_balance,
                            risk_per_trade_pct=cfg.risk_per_trade,
                            stop_loss_pips=stop_loss_pips,
                            symbol=symbol,
                            current_spread_pips=current_spread,
                            daily_loss_accumulated=cfg.daily_loss_usd,
                        )

                        if not risk_eval["allowed"]:
                            await worker_ref._log_rejection(
                                user_id, symbol, direction_str, risk_eval["reason"], consensus, signal_data.get("cycle_id", 0)
                            )
                            if "Killswitch" in risk_eval["reason"]:
                                await worker_ref._send_critical_alert(user_id, symbol)
                            continue

                        user_lot = risk_eval["lot_size"]
                        cfg.active_allocations[symbol] = user_lot
                        await worker_ref._save_config(user_id, cfg)
                        
                        eligible_users.append(user_id)
                        user_lots[user_id] = user_lot
                        total_volume_lots += user_lot

                    except Exception as e:
                        logger.warning(f"Error evaluating user {user_id} for {symbol}: {e}")

            if not eligible_users or total_volume_lots <= 0.0:
                logger.info(f"Master Exec: 0 eligible users for {symbol}. Skipping master order.")
                continue

            total_volume_lots = round(total_volume_lots, 2)
            if total_volume_lots < 0.01:
                total_volume_lots = 0.01

            master_order = TradeOrder(
                symbol=symbol,
                direction=direction,
                volume=total_volume_lots,
                stop_loss=suggested_sl,
                take_profit=suggested_tp,
                order_type="MARKET",
                user_id="MASTER_MAM",
            )

            logger.info(
                f"🚀 MASTER EXECUTION: Aggregated {len(eligible_users)} users -> "
                f"Executing {total_volume_lots:.2f} lots {direction_str} on {symbol} via Broker Gateway..."
            )

            result = await worker_ref._broker_execute(master_order, signal_data)
            
            if result.get("success"):
                fill_price = result.get("fill_price", live_price)
                broker_order_id = result.get("order_id", f"MAM_{uuid.uuid4().hex[:8]}")
                broker_filled_volume = result.get("filled_volume", total_volume_lots)
                
                fill_ratio = 1.0
                if total_volume_lots > 0 and broker_filled_volume < total_volume_lots:
                    fill_ratio = broker_filled_volume / total_volume_lots
                    logger.warning(
                        f"⚠️ PARTIAL FILL: Broker filled {broker_filled_volume:.2f} / {total_volume_lots:.2f} lots "
                        f"({fill_ratio*100:.1f}%) for {symbol}. Scaling user allocations."
                    )
                
                master_receipt = MasterTradeReceipt(
                    master_order_id=broker_order_id,
                    symbol=symbol,
                    direction=direction_str,
                    fill_price=fill_price,
                    total_volume_lots=broker_filled_volume,
                    requested_volume_lots=total_volume_lots,
                    fill_ratio=fill_ratio,
                    eligible_user_count=len(eligible_users),
                    allocated_user_lots=user_lots,
                )
                
                await storage.set(
                    "master_receipts",
                    master_receipt.master_order_id,
                    json.loads(master_receipt.model_dump_json())
                )

                ledger_task = LedgerDistributionTask(
                    task_id=master_receipt.master_order_id,
                    symbol=symbol,
                    direction=direction_str,
                    fill_price=fill_price,
                    fill_ratio=fill_ratio,
                    total_users=len(eligible_users),
                )
                
                await storage.set(
                    "ledger_tasks",
                    ledger_task.task_id,
                    json.loads(ledger_task.model_dump_json())
                )

                logger.info(
                    f"✅ MASTER ORDER FILLED at {fill_price} (Order ID: {broker_order_id}). "
                    f"Created Ledger Task for async distribution."
                )

            else:
                reason = result.get("reason", "Broker execution failed")
                logger.error(f"❌ MASTER EXECUTION FAILED on {symbol}: {reason}")
                for u_id in eligible_users:
                    await worker_ref._log_rejection(
                        u_id, symbol, direction_str, f"Master Order Rejected by Broker: {reason}", consensus, signal_data.get("cycle_id", 0)
                    )

        except Exception as e:
            logger.error(f"Master worker error: {e}")
        finally:
            if task_data is not None:
                try:
                    await storage.release_lock(f"master_exec_{task_data['symbol']}")
                except Exception as e:
                    logger.debug(f"Lock release cleanup for {task_data['symbol']}: {e}")
                worker_ref._execution_queue.task_done()
