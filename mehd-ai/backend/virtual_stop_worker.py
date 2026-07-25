"""
Mehd AI — The Sniper Engine (Virtual Stop Loss Worker)
======================================================
This background worker constantly monitors the live market feed and compares it
against our "secret vault" of Stop Losses and Take Profits. 

Because we do not send the SL/TP to the broker, the broker cannot hunt them.
This script acts as the trigger finger, instantly closing trades if the price hits our secret bounds.
"""

import asyncio
import logging
from datetime import datetime, timezone
from storage import storage
from state import streamer
from broker_gateway import broker_gateway
import broker_scanner

logger = logging.getLogger("mehd.virtual_stop_worker")

class VirtualStopWorker:
    def __init__(self):
        self._running = False
        self._task = None
        # In-memory guard: prevents double-close during Firestore delete propagation window
        self._closing_trades: set = set()
        self._stops_cache: dict = {}
        self._listener = None

    def start(self):
        if not self._running:
            self._running = True
            # Setup real-time listener if in Firestore mode to keep reads at near-zero cost
            if hasattr(storage, "_db"):
                try:
                    col_ref = storage._db.collection("virtual_stops")
                    self._listener = col_ref.on_snapshot(self._on_snapshot_callback)
                    logger.info("🎯 Sniper Engine: Firestore on_snapshot listener established.")
                except Exception as e:
                    logger.error(f"Failed to start Firestore listener: {e}")

            self._task = asyncio.create_task(self._loop())
            logger.info("🎯 Sniper Engine (Virtual Stops) started.")

    def stop(self):
        self._running = False
        if self._task:
            self._task.cancel()
        if self._listener:
            try:
                self._listener.unsubscribe()
                logger.info("🎯 Sniper Engine: Firestore on_snapshot listener unsubscribed.")
            except Exception as e:
                logger.error(f"Failed to unsubscribe Firestore listener: {e}")
            self._listener = None
        logger.info("🎯 Sniper Engine (Virtual Stops) stopped.")

    def _on_snapshot_callback(self, col_snapshot, changes, read_time):
        new_cache = {}
        for doc in col_snapshot:
            new_cache[doc.id] = doc.to_dict()
        self._stops_cache = new_cache
        logger.info(f"🎯 Sniper Engine: stops cache updated with {len(new_cache)} active stops.")

    async def _loop(self):
        await asyncio.sleep(5)  # Boot delay
        while self._running:
            try:
                # We check 5 times a second (200ms latency)
                await self._check_stops()
                await asyncio.sleep(0.2) 
            except Exception as e:
                logger.error(f"Sniper Engine error: {e}")
                await asyncio.sleep(1)

    async def _check_stops(self):
        # Read from local memory cache if Firestore backend is active
        if hasattr(storage, "_db"):
            stops = self._stops_cache
        else:
            stops = await storage.get_all("virtual_stops")

        if not stops:
            return

        for trade_id, data in list(stops.items()):
            symbol = data.get("symbol")
            direction = data.get("direction")
            stop_loss = data.get("stop_loss")
            take_profit = data.get("take_profit")
            account_id = data.get("account_id")

            if not all([symbol, direction, account_id]):
                continue

            snap = streamer.get_latest_snapshot(symbol)
            if snap is None or snap.bid <= 0.0 or snap.ask <= 0.0:
                continue

            # Check logic based on direction
            close_reason = None
            if direction.upper() == "BUY":
                # For a BUY, we close if the BID price drops below SL or jumps above TP
                if stop_loss is not None and snap.bid <= stop_loss:
                    close_reason = f"Hit Virtual Stop Loss @ {snap.bid}"
                elif take_profit is not None and snap.bid >= take_profit:
                    close_reason = f"Hit Virtual Take Profit @ {snap.bid}"
            elif direction.upper() == "SELL":
                # For a SELL, we close if the ASK price jumps above SL or drops below TP
                if stop_loss is not None and snap.ask >= stop_loss:
                    close_reason = f"Hit Virtual Stop Loss @ {snap.ask}"
                elif take_profit is not None and snap.ask <= take_profit:
                    close_reason = f"Hit Virtual Take Profit @ {snap.ask}"

            # If a bound is hit, fire the close trade command!
            if close_reason:
                # Guard: skip if already being closed (prevents double-call in 200ms propagation window)
                if trade_id in self._closing_trades:
                    continue
                self._closing_trades.add(trade_id)
                logger.critical(f"🎯 SNIPER TRIGGER: {close_reason} | Trade ID: {trade_id}")

                # Record trigger time and price for broker performance measurement
                trigger_time  = datetime.now(timezone.utc)
                trigger_price = snap.bid if direction.upper() == "BUY" else snap.ask

                success = await broker_gateway.close_trade(trade_id, account_id)
                if success:
                    fill_time = datetime.now(timezone.utc)
                    # Re-fetch live price immediately after fill as slippage reference
                    post_snap   = streamer.get_latest_snapshot(symbol)
                    fill_price  = (post_snap.bid if direction.upper() == "BUY" else post_snap.ask) if post_snap else trigger_price
                    broker_id   = data.get("broker_id", data.get("broker_name", "oanda"))

                    # Fire-and-forget broker performance log (non-blocking)
                    asyncio.create_task(broker_scanner.log_execution_performance(
                        broker_id     = broker_id,
                        symbol        = symbol,
                        direction     = direction,
                        trigger_price = trigger_price,
                        fill_price    = fill_price,
                        trigger_time  = trigger_time,
                        fill_time     = fill_time,
                    ))

                    # Remove from active monitoring vault
                    await storage.delete("virtual_stops", trade_id)
                    # Optimistically update the cache to prevent race condition before listener fires
                    if trade_id in self._stops_cache:
                        del self._stops_cache[trade_id]
                    self._closing_trades.discard(trade_id)
                else:
                    # Release lock on failure so it retries next cycle
                    self._closing_trades.discard(trade_id)
                    logger.error(f"Failed to close trade {trade_id} via Sniper Engine!")

# Singleton
virtual_stop_worker = VirtualStopWorker()
