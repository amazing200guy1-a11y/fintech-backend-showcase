from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from storage import storage
from broadcast_signal import BroadcastSignal, BROADCAST_PAIRS, FREE_TIER_DELAY_SECONDS

logger = logging.getLogger("mehd.broadcaster")


async def run_lifecycle_manager_loop(broadcaster_ref) -> None:
    """Periodically ages signals in Firestore (FRESH -> ACTIVE -> STALE -> EXPIRED)"""
    await asyncio.sleep(10)
    
    while broadcaster_ref._running:
        try:
            now = datetime.now(timezone.utc)
            live_signals = await storage.query("broadcast_history", [
                ("status", "in", ["FRESH", "ACTIVE", "STALE"]),
            ])
            
            updated_count = 0
            for sig_id, sig_data in live_signals.items():
                bt_str = sig_data.get("broadcast_time")
                status = sig_data.get("status", "FRESH")
                if not bt_str:
                    continue
                try:
                    bt = datetime.fromisoformat(bt_str)
                except ValueError:
                    continue
                    
                age_mins = (now - bt).total_seconds() / 60
                new_status = status
                if age_mins > 240:
                    new_status = "EXPIRED"
                elif age_mins > 30:
                    new_status = "STALE"
                elif age_mins > 5:
                    new_status = "ACTIVE"
                    
                if new_status != status:
                    sig_data["status"] = new_status
                    await storage.set("broadcast_history", sig_id, sig_data)
                    updated_count += 1
            
            if updated_count > 0:
                logger.info("♻️ Lifecycle Manager updated %d signals", updated_count)
                
        except Exception as e:
            logger.error("Lifecycle manager error: %s", e)
            
        await asyncio.sleep(60)


async def run_delayed_pusher_loop(broadcaster_ref) -> None:
    """Periodically pushes signals that have matured past the Free Tier delay."""
    await asyncio.sleep(15)
    last_pushed_broadcast_time: dict[str, datetime] = {}

    while broadcaster_ref._running:
        try:
            now = datetime.now(timezone.utc)
            for pair in BROADCAST_PAIRS:
                history = broadcaster_ref._history.get(pair, [])
                for sig in list(history):
                    age = (now - sig.broadcast_time).total_seconds()
                    if age < FREE_TIER_DELAY_SECONDS:
                        continue

                    last_bt = last_pushed_broadcast_time.get(pair)
                    if last_bt is not None and sig.broadcast_time <= last_bt:
                        continue

                    last_pushed_broadcast_time[pair] = sig.broadcast_time
                    delayed_sig = BroadcastSignal(
                        symbol=sig.symbol,
                        consensus=sig.consensus,
                        snapshot=sig.snapshot,
                        broadcast_time=sig.broadcast_time,
                        cycle_id=sig.cycle_id,
                        analysis_duration_ms=sig.analysis_duration_ms,
                        status="delayed",
                    )
                    async with broadcaster_ref._delayed_condition:
                        broadcaster_ref._latest_delayed_msg = delayed_sig
                        broadcaster_ref._total_delayed_broadcasts += 1
                        broadcaster_ref._delayed_condition.notify_all()

                    logger.debug(
                        "DELAYED PUSH: %s matured and broadcast to delayed subscribers",
                        pair,
                    )

        except Exception as e:
            logger.error("Delayed pusher error: %s", e)
        await asyncio.sleep(10)
