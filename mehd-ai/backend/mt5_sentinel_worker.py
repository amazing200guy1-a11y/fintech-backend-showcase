"""
Mehd AI - MT5 Sentinel Worker (Backend Autonomous Profit Engine)
=================================================================
Monitors live Exness MT5 positions every second and fires the 4-stage
autonomous profit-protection triggers on real broker positions:

  Stage 1 - Auto-BE Shield   (1.0R) : Move SL to entry + spread offset
  Stage 2 - Auto-Bank 50%    (1.5R) : Partial close 50% of lots on Exness
  Stage 3 - Titan Lock        (3.0R) : Bank 50% remainder, lock SL to +1.0R
  Stage 4 - Sovereign Apex   (5.0R) : Bank 50% remainder, lock SL to +3.0R

Server-side mirror of sentinel_guard_service.dart.
Flutter skips MT5 positions (broker == 'mt5'). This worker handles them.
"""

from __future__ import annotations

import asyncio
import logging
import math
from typing import Dict, Any

from state import streamer
from mt5_gateway import mt5_gateway

logger = logging.getLogger("mehd.mt5_sentinel")

R_BE        = 1.0
R_BANK      = 1.5
R_TITAN     = 3.0
R_SOVEREIGN = 5.0

SPREAD_OFFSETS: Dict[str, float] = {
    "XAUUSD": 0.30, "XAGUSD": 0.05,
    "BTCUSD": 15.0, "ETHUSD": 2.0,
    "NAS100": 1.5,  "US30":   2.0,
    "USDJPY": 0.03, "EURJPY": 0.03, "GBPJPY": 0.04,
}
DEFAULT_SPREAD_OFFSET = 0.00030

DEFAULT_SL_DISTANCES: Dict[str, float] = {
    "XAUUSD": 3.00, "XAGUSD": 0.20,
    "BTCUSD": 300.0, "ETHUSD": 20.0,
    "NAS100": 20.0, "US30": 50.0,
    "USDJPY": 0.30, "EURJPY": 0.30, "GBPJPY": 0.40,
}
DEFAULT_SL_DISTANCE = 0.00300


def _spread_offset(symbol: str) -> float:
    clean = symbol.upper().replace("/", "").replace("m", "").replace("M", "")
    for key, val in SPREAD_OFFSETS.items():
        if key in clean:
            return val
    return DEFAULT_SPREAD_OFFSET


def _default_sl_distance(symbol: str) -> float:
    clean = symbol.upper().replace("/", "").replace("m", "").replace("M", "")
    for key, val in DEFAULT_SL_DISTANCES.items():
        if key in clean:
            return val
    return DEFAULT_SL_DISTANCE


def _floor_lot(lots: float, step: float = 0.01) -> float:
    return math.floor(round(lots / step, 8)) * step


class MT5SentinelWorker:
    """Background daemon firing autonomous profit triggers on live Exness positions."""

    def __init__(self):
        self._running = False
        self._task: asyncio.Task | None = None
        self._position_state: Dict[str, Dict[str, Any]] = {}

    def start(self):
        if not self._running:
            self._running = True
            self._task = asyncio.create_task(self._loop())
            logger.info("Shield MT5 Sentinel Worker started - monitoring live Exness positions every 1s.")

    def stop(self):
        self._running = False
        if self._task:
            self._task.cancel()
        logger.info("Shield MT5 Sentinel Worker stopped.")

    async def _loop(self):
        await asyncio.sleep(3)
        while self._running:
            try:
                await self._evaluate_positions()
            except Exception as e:
                logger.error("MT5 Sentinel error: %s", e, exc_info=True)
            await asyncio.sleep(1)

    async def _evaluate_positions(self):
        positions = mt5_gateway.get_positions()
        if not positions:
            self._position_state.clear()
            return

        open_tickets = {str(p["ticket"]) for p in positions}
        closed = [t for t in self._position_state if t not in open_tickets]
        for t in closed:
            del self._position_state[t]

        for pos in positions:
            await self._evaluate_one(pos)

    async def _evaluate_one(self, pos: Dict[str, Any]):
        ticket    = str(pos["ticket"])
        symbol    = pos.get("raw_symbol") or pos.get("symbol", "EURUSD")
        direction = pos.get("type", "BUY").upper()
        entry     = float(pos.get("entry", 0.0))
        lot       = float(pos.get("lotSize", 0.01))
        broker_sl = float(pos.get("sl") or 0.0)

        if entry <= 0:
            return

        snap = streamer.get_latest_snapshot(symbol)
        if snap is None or snap.bid <= 0 or snap.ask <= 0:
            return

        current = snap.bid if direction == "BUY" else snap.ask

        if ticket not in self._position_state:
            sl_dist = abs(entry - broker_sl) if broker_sl > 0 else _default_sl_distance(symbol)
            self._position_state[ticket] = {
                "be_armed":     False,
                "banked_stage": 0,
                "sl_dist":      sl_dist,
            }

        state        = self._position_state[ticket]
        sl_dist      = state["sl_dist"]
        be_armed     = state["be_armed"]
        banked_stage = state["banked_stage"]

        if sl_dist <= 0:
            return

        price_diff = (current - entry) if direction == "BUY" else (entry - current)
        r_multiple = price_diff / sl_dist

        # Stage 1: Auto-BE Shield (1.0R)
        if r_multiple >= R_BE and not be_armed:
            offset = _spread_offset(symbol)
            new_sl = (entry + offset) if direction == "BUY" else (entry - offset)
            ok = await mt5_gateway.modify_sl(ticket, new_sl)
            if ok:
                state["be_armed"] = True
                logger.critical(
                    "AUTO-BE #%s %s R=%.2f SL->breakeven %.5f",
                    ticket, symbol, r_multiple, new_sl
                )

        # Stage 2: Auto-Bank 50% (1.5R)
        elif r_multiple >= R_BANK and banked_stage == 0:
            if lot >= 0.02:
                close_lots = _floor_lot(lot * 0.5)
                if close_lots >= 0.01:
                    ok = await mt5_gateway.close_trade(ticket, volume=close_lots)
                    if ok:
                        state["banked_stage"] = 1
                        logger.critical(
                            "BANK 50%% #%s %s R=%.2f closed %.2f lots",
                            ticket, symbol, r_multiple, close_lots
                        )
            else:
                locked_sl = (entry + sl_dist * 0.5) if direction == "BUY" else (entry - sl_dist * 0.5)
                ok = await mt5_gateway.modify_sl(ticket, locked_sl)
                if ok:
                    state["banked_stage"] = 1
                    logger.critical(
                        "MICRO-LOT #%s %s R=%.2f SL->+0.5R %.5f (cannot split 0.01)",
                        ticket, symbol, r_multiple, locked_sl
                    )

        # Stage 3: Titan Lock (3.0R)
        elif r_multiple >= R_TITAN and banked_stage == 1:
            if lot >= 0.02:
                close_lots = _floor_lot(lot * 0.5)
                if close_lots >= 0.01:
                    await mt5_gateway.close_trade(ticket, volume=close_lots)
            profit_sl = (entry + sl_dist * 1.0) if direction == "BUY" else (entry - sl_dist * 1.0)
            ok = await mt5_gateway.modify_sl(ticket, profit_sl)
            if ok:
                state["banked_stage"] = 2
                logger.critical(
                    "TITAN LOCK #%s %s R=%.2f SL->+1.0R %.5f",
                    ticket, symbol, r_multiple, profit_sl
                )

        # Stage 4: Sovereign Apex (5.0R)
        elif r_multiple >= R_SOVEREIGN and banked_stage == 2:
            if lot >= 0.02:
                close_lots = _floor_lot(lot * 0.5)
                if close_lots >= 0.01:
                    await mt5_gateway.close_trade(ticket, volume=close_lots)
            apex_sl = (entry + sl_dist * 3.0) if direction == "BUY" else (entry - sl_dist * 3.0)
            ok = await mt5_gateway.modify_sl(ticket, apex_sl)
            if ok:
                state["banked_stage"] = 3
                logger.critical(
                    "SOVEREIGN APEX #%s %s R=%.2f SL->+3.0R %.5f runner FREE",
                    ticket, symbol, r_multiple, apex_sl
                )


mt5_sentinel_worker = MT5SentinelWorker()
