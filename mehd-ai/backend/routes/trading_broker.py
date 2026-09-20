"""
Mehd AI — Trading Broker Gateway Satellite Router
=================================================
Endpoints:
  GET  /trades/positions    — Pull live open positions with exact broker PnL
  POST /trades/market-order — Direct execution on connected MT5/Exness broker
  POST /trades/close        — Close or partially close an open trade on broker
"""

import logging
import time
from typing import Optional
from uuid import uuid4

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel

from auth import get_current_user
from log_utils import safe_uid
from storage import storage

logger = logging.getLogger("mehd.routes.trading_broker")
router = APIRouter()


class ClosePositionPayload(BaseModel):
    ticket: Optional[str] = None
    symbol: Optional[str] = None
    volume: Optional[float] = None


class MarketOrderPayload(BaseModel):
    symbol: str
    direction: str = "BUY"
    lot_size: float = 0.01
    stop_loss: Optional[float] = None
    take_profit: Optional[float] = None


@router.get("/trades/positions", summary="Get exact live open positions and account summary from connected broker")
async def get_positions_endpoint(uid: str = Depends(get_current_user)):
    """
    Pulls exact open positions, entry prices, current prices, and floating PnL
    along with exact live balance, equity, and margin directly from MT5 / Exness.
    Zero hallucination. Matches the broker phone app down to the penny.
    """
    from mt5_gateway import mt5_gateway
    if mt5_gateway.is_available():
        positions = mt5_gateway.get_positions()
        account = await mt5_gateway.get_account_summary(credentials={})
        return {
            "positions": positions,
            "count": len(positions),
            "broker": "mt5",
            "account": account,
        }

    return {"positions": [], "count": 0, "broker": "none", "account": None}


@router.get("/trades/account", summary="Get exact live account summary directly from connected broker")
async def get_account_endpoint(uid: str = Depends(get_current_user)):
    """Pulls exact live balance, equity, margin, free margin from MT5."""
    from mt5_gateway import mt5_gateway
    if mt5_gateway.is_available():
        summary = await mt5_gateway.get_account_summary(credentials={})
        return summary
    return {
        "status": "disconnected",
        "broker": "none",
        "balance": 0.0,
        "equity": 0.0,
        "margin": 0.0,
        "margin_free": 0.0,
    }



@router.post("/trades/market-order", summary="Execute direct market order on connected broker")
async def market_order_endpoint(
    payload: MarketOrderPayload,
    uid: str = Depends(get_current_user),
):
    """
    Direct market order execution from Cockpit / Strike Desk / Positions deck.
    Enforces the Two-Tier Institutional Shield:
      Tier 1: Strategic SL kept in MEHD AI memory vault (hidden from broker).
      Tier 2: Catastrophic Hard Stop placed on Exness 3x away (prevent wipeout).
    """
    from models import TradeOrder, RiskDecision, Direction
    from secrets_manager import encryption

    sym = payload.symbol.replace("/", "").upper()
    direction = Direction.BUY if payload.direction.upper() == "BUY" else Direction.SELL
    lot = max(0.01, min(float(payload.lot_size), 10.0))
    logger.info("Direct market order received from %s: %s %s %.2f lots", safe_uid(uid), direction.value, sym, lot)

    # 1. Fetch user broker vault credentials if stored
    user_vault = await storage.get("broker_vaults", uid)
    broker_creds = None
    if user_vault:
        try:
            broker_creds = {
                "api_key": encryption.decrypt(user_vault.get("encrypted_api_key", "")),
                "api_secret": encryption.decrypt(user_vault.get("encrypted_api_secret", "")),
                "account_id": user_vault.get("exchange_id", ""),
                "exchange_id": user_vault.get("exchange_id", ""),
                "server": user_vault.get("server", ""),
            }
        except Exception as e:
            logger.warning("Failed to decrypt user vault: %s", e)

    # 2. Direct MT5 execution if available
    from mt5_gateway import mt5_gateway
    if mt5_gateway.is_available():
        try:
            sl_val = payload.stop_loss if (payload.stop_loss and payload.stop_loss > 0) else None
            tp_val = payload.take_profit if (payload.take_profit and payload.take_profit > 0) else None

            order = TradeOrder(
                symbol=sym if len(sym) >= 6 else f"{sym}USD",
                direction=direction,
                lot_size=lot,
                stop_loss=sl_val,
                take_profit=tp_val,
            )
            decision = RiskDecision(
                id=uuid4(),
                approved=True,
                calculated_lot_size=lot,
                stop_loss=sl_val,
                take_profit=tp_val,
                use_virtual_stops=True,
            )

            res = await mt5_gateway.execute_order(order, decision, credentials=broker_creds or {})
            if res.get("status") == "filled":
                ticket = str(res.get("trade_id", ""))
                fill_price = float(res.get("fill_price", 0.0))
                logger.critical("🎯 DIRECT BROKER FILL: %s %s %.2f lots on MT5 (Ticket #%s @ %.5f)", direction.value, sym, lot, ticket, fill_price)
                return {
                    "status": "filled",
                    "broker": "mt5",
                    "ticket": ticket,
                    "fill_price": fill_price,
                    "lot_size": float(res.get("lot_size", lot)),
                    "symbol": res.get("symbol", sym),
                    "direction": direction.value,
                    "virtual_stop_loss": True,
                }
            elif res.get("status") == "rejected":
                logger.warning("MT5 order rejected: %s", res.get("reason"))
                return {
                    "status": "error",
                    "broker": "mt5",
                    "reason": res.get("reason", "Broker rejected order"),
                }
        except Exception as e:
            logger.error("Direct MT5 execution error: %s", e)

    # 3. Paper mode fallback if MT5 not active
    sim_ticket = f"SIM_{int(time.time()*1000)}"
    return {
        "status": "filled",
        "broker": "paper",
        "ticket": sim_ticket,
        "fill_price": 0.0,
        "lot_size": lot,
        "symbol": sym,
        "direction": direction.value,
    }


@router.post("/trades/close", summary="Close or partially close an open trade position on broker")
@router.post("/close-position", include_in_schema=False)
async def close_position_endpoint(
    payload: ClosePositionPayload,
    uid: str = Depends(get_current_user),
):
    """
    Closes or partially closes an open position on the broker (MT5, Exness, etc.)
    and clears/updates virtual stops.
    """
    from broker_gateway import broker_gateway
    logger.info("Close request from %s for ticket=%s, symbol=%s, volume=%s", safe_uid(uid), payload.ticket, payload.symbol, payload.volume)

    # 1. Close by specific ticket (full or partial)
    if payload.ticket:
        from mt5_gateway import mt5_gateway
        if mt5_gateway.is_available():
            closed = await mt5_gateway.close_trade(str(payload.ticket), volume=payload.volume)
            if closed:
                if payload.volume is None:
                    await storage.delete("virtual_stops", str(payload.ticket))
                return {"status": "success", "ticket": payload.ticket, "closed": True}
        success = await broker_gateway.close_trade(str(payload.ticket), account_id="")
        if success:
            await storage.delete("virtual_stops", str(payload.ticket))
            return {"status": "success", "ticket": payload.ticket, "closed": True}
        raise HTTPException(status_code=400, detail=f"Failed to close position #{payload.ticket} on broker.")

    # 2. Close by symbol or close all
    try:
        import MetaTrader5 as mt5
        from mt5_gateway import mt5_gateway
        if mt5.initialize():
            positions = mt5.positions_get()
            closed_count = 0
            if positions:
                clean_sym = payload.symbol.replace("/", "").upper() if payload.symbol else None
                for p in positions:
                    if clean_sym is None or clean_sym in p.symbol.upper():
                        if await mt5_gateway.close_trade(p.ticket, volume=payload.volume):
                            closed_count += 1
                            if payload.volume is None:
                                await storage.delete("virtual_stops", str(p.ticket))
            return {"status": "success", "closed_count": closed_count}
    except Exception as e:
        logger.error("Error closing positions via MT5: %s", e)

    return {"status": "success", "closed_count": 0}
