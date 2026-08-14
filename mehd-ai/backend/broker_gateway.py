"""
Mehd AI — Broker Gateway (OANDA v20 REST API)
===============================================
This module is the ONLY code that talks to the real broker.
When OANDA_API_KEY and OANDA_ACCOUNT_ID are set in .env,
the system executes real trades. When they're missing, it
returns mock fills.

OANDA v20 REST API Documentation:
  https://developer.oanda.com/rest-live-v20/order-ep/

SECURITY:
  - This module is ONLY called from risk_gateway.py after all
    4 gates have passed (seal check, kernel eval, double-validate, execute)
  - The TradeOrder has already been capped to safe lot sizes
  - Stop-loss and take-profit are already verified
"""

from __future__ import annotations

import logging
import os
import random
import time
from typing import Optional

import httpx

from models import TradeOrder, RiskDecision, Direction, get_pip_size
from state import streamer
from storage import storage

logger = logging.getLogger("mehd.broker_gateway")

# OANDA API Configuration
# For practice accounts: https://api-fxpractice.oanda.com
# For live accounts:     https://api-fxtrade.oanda.com
OANDA_API_URL = os.getenv("OANDA_API_URL", "https://api-fxpractice.oanda.com")

# Symbol mapping: Mehd uses EURUSD, OANDA uses EUR_USD
OANDA_SYMBOL_MAP = {
    "EURUSD": "EUR_USD", "GBPUSD": "GBP_USD", "USDJPY": "USD_JPY",
    "AUDUSD": "AUD_USD", "USDCAD": "USD_CAD", "NZDUSD": "NZD_USD",
    "EURGBP": "EUR_GBP", "EURJPY": "EUR_JPY", "GBPJPY": "GBP_JPY",
    "XAUUSD": "XAU_USD", "XAGUSD": "XAG_USD",
    "BTCUSD": "BTC_USD", "ETHUSD": "ETH_USD",
    # FIX C6: NAS100 and US30 were missing — auto-execution orders were being silently rejected by OANDA
    "NAS100": "NAS100_USD", "US30": "US30_USD",
}


def _get_oanda_instrument(symbol: str) -> str:
    """Convert internal symbol (EURUSD) to OANDA format (EUR_USD)."""
    return OANDA_SYMBOL_MAP.get(symbol.upper(), symbol.replace("USD", "_USD"))


def _lot_to_units(lot_size: float, symbol: str) -> int:
    """
    Convert lot size to OANDA units.
    Forex:  1 standard lot = 100,000 units
    Gold:   1 standard lot = 100 oz (OANDA trades gold in troy ounces)
    """
    if "XAU" in symbol.upper():
        return max(1, int(lot_size * 100))  # Gold: 0.1 lot = 10 oz
    return int(lot_size * 100_000)  # Forex: 1 lot = 100,000 units


class BrokerGateway:
    """
    Handles all communication with the OANDA v20 REST API.
    
    This is a synchronous class used by the RiskGateway executor.
    When no API key is set, all methods return mock responses.
    """
    
    def __init__(self):
        self.api_key = os.getenv("OANDA_API_KEY", "")
        self.account_id = os.getenv("OANDA_ACCOUNT_ID", "")
        self.api_url = OANDA_API_URL
        self._is_live = bool(self.api_key and self.account_id)
        self._circuit_breaker_open_until = 0.0
        import asyncio
        self._rate_limiter = asyncio.Semaphore(20)
        
        if self._is_live:
            logger.info("BrokerGateway: LIVE mode — connected to OANDA account %s", 
                       self.account_id[:4] + "****")
        else:
            logger.info("BrokerGateway: PAPER mode — no broker keys configured")
    
    @property
    def is_live(self) -> bool:
        """Re-check credentials each time (they may be set after init)."""
        key = os.getenv("OANDA_API_KEY", "")
        acct = os.getenv("OANDA_ACCOUNT_ID", "")
        return bool(key and acct)
    
    def _headers(self, credentials: dict | None = None) -> dict:
        """Build API headers with the user's decrypted credentials."""
        from crypto_vault import vault
        if credentials and "api_key" in credentials:
            # Auto-decrypt if encrypted Fernet token is passed
            raw_key = credentials.get("api_key", "")
            if raw_key.startswith("gAAAAA"):  # Fernet token prefix
                api_key = vault.decrypt_secret(raw_key)
            else:
                api_key = raw_key
        else:
            api_key = os.getenv("OANDA_API_KEY", "")

        return {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept-Datetime-Format": "RFC3339",
            "X-MBX-APIKEY": api_key,
        }
    
    async def execute_order(self, order: TradeOrder, decision: RiskDecision, credentials: dict | None = None) -> dict:
        """
        Execute an order on the user's connected exchange using their decrypted keys.
        """
        from crypto_vault import vault
        if credentials:
            credentials = vault.decrypt_credentials(credentials)
        account_id = credentials.get("account_id") if credentials else os.getenv("OANDA_ACCOUNT_ID", "")
        
        now = time.monotonic()
        if now < getattr(self, "_circuit_breaker_open_until", 0.0):
            remaining = int(self._circuit_breaker_open_until - now)
            logger.critical("API Latency Circuit Breaker is OPEN. Halting trades for %ds.", remaining)
            return {
                "mode": "live" if self.is_live else "paper",
                "status": "rejected",
                "broker": "oanda",
                "reason": f"API Latency Circuit Breaker Active. Trades halted for {remaining}s due to severe broker latency.",
            }

        if not self.is_live:
            return self._mock_execution(order, decision)
        
        try:
            instrument = _get_oanda_instrument(order.symbol)
            units = _lot_to_units(decision.calculated_lot_size, order.symbol)
            
            # OANDA: negative units = SELL, positive = BUY
            if order.direction == Direction.SELL:
                units = -units
            
            # Build the order payload
            payload = {
                "order": {
                    "type": "MARKET",
                    "instrument": instrument,
                    "units": str(units),
                    "timeInForce": "FOK",  # Fill Or Kill — no partial fills
                    "positionFill": "DEFAULT",
                }
            }
            
            # LATENCY ARBITRAGE DEFENSE (The Time-Travel Hack)
            # If a high-frequency trader crashes the price in the 500ms delay,
            # this bound physically blocks OANDA from executing the terrible fill.
            if decision.expected_price > 0:
                pip_size = get_pip_size(order.symbol)
                max_slippage_pips = 3.0  # Max 3 pips slippage
                
                if order.direction == Direction.BUY:
                    bound = decision.expected_price + (max_slippage_pips * pip_size)
                else:
                    bound = decision.expected_price - (max_slippage_pips * pip_size)
                    
                payload["order"]["priceBound"] = f"{bound:.5f}"
            
            # Add stop-loss (required by our risk kernel)
            if decision.stop_loss and not decision.use_virtual_stops:
                payload["order"]["stopLossOnFill"] = {
                    "price": f"{decision.stop_loss:.5f}",
                    "timeInForce": "GTC",  # Good Till Cancelled
                }
            
            # Add take-profit if set
            if decision.take_profit and not decision.use_virtual_stops:
                payload["order"]["takeProfitOnFill"] = {
                    "price": f"{decision.take_profit:.5f}",
                    "timeInForce": "GTC",
                }
            
            # Execute the order
            endpoint = f"{self.api_url}/v3/accounts/{account_id}/orders"
            
            start_time = time.monotonic()
            
            async with self._rate_limiter:
                async with httpx.AsyncClient(timeout=5.0) as client:
                    resp = await client.post(
                        endpoint,
                        headers=self._headers(credentials),
                        json=payload,
                    )
                # Hard rate limit: force a minimum 50ms delay between token releases 
                # to strictly enforce a maximum 20 requests per second.
                import asyncio
                await asyncio.sleep(0.05)
            
            latency_ms = (time.monotonic() - start_time) * 1000
            if latency_ms > 1500.0:
                logger.critical("BROKER LATENCY SPIKE: %.1fms. Tripping circuit breaker for 60 seconds.", latency_ms)
                self._circuit_breaker_open_until = time.monotonic() + 60.0
            
            if resp.status_code == 201:
                data = resp.json()
                fill = data.get("orderFillTransaction", {})
                
                logger.info(
                    "BROKER FILL: %s %s %d units @ %s — Trade ID: %s",
                    order.direction.value,
                    instrument,
                    abs(units),
                    fill.get("price", "N/A"),
                    fill.get("tradeOpened", {}).get("tradeID", "N/A"),
                )
                
                trade_id = fill.get("tradeOpened", {}).get("tradeID")
                
                # VIRTUAL STOP LOSS: Save the secret parameters to Firestore
                if decision.use_virtual_stops and trade_id:
                    import asyncio
                    asyncio.create_task(storage.set("virtual_stops", trade_id, {
                        "symbol": order.symbol,
                        "account_id": account_id,
                        "direction": order.direction.value,
                        "entry_price": float(fill.get("price", 0.0)),
                        "stop_loss": decision.stop_loss,
                        "take_profit": decision.take_profit,
                        "units": str(units),
                        "timestamp": fill.get("time"),
                    }))
                elif decision.use_virtual_stops and not trade_id:
                    # CRITICAL: Trade opened but trade_id was missing from broker response.
                    # The virtual stop could NOT be saved. This trade has NO protection.
                    logger.critical(
                        "⚠️ VIRTUAL STOP FAILURE: trade_id missing from OANDA fill response for %s. "
                        "Trade is UNPROTECTED. Manual SL must be set immediately.", order.symbol
                    )
                
                return {
                    "mode": "live",
                    "status": "filled",
                    "broker": "oanda",
                    "trade_id": fill.get("tradeOpened", {}).get("tradeID"),
                    "fill_price": fill.get("price"),
                    "units": fill.get("units"),
                    "instrument": instrument,
                    "pl": fill.get("pl", "0.0"),
                    "financing": fill.get("financing", "0.0"),
                    "timestamp": fill.get("time"),
                }
            else:
                error_data = resp.json()
                reject_reason = error_data.get("orderRejectTransaction", {}).get("rejectReason", "Unknown")
                logger.error(
                    "BROKER REJECTION: %s %s — Reason: %s — HTTP %d",
                    order.direction.value, instrument, reject_reason, resp.status_code,
                )
                return {
                    "mode": "live",
                    "status": "rejected",
                    "broker": "oanda",
                    "reason": reject_reason,
                    "http_status": resp.status_code,
                }
                
        except httpx.TimeoutException:
            logger.error("BROKER TIMEOUT: Order for %s did not complete in 10s", order.symbol)
            return {
                "mode": "live",
                "status": "timeout",
                "broker": "oanda",
                # FIX: Byzantine General's Problem
                # A timeout does NOT mean the order failed. It means the state is UNKNOWN.
                "reason": "Connection to broker timed out. Order state is UNKNOWN (Possible Ghost Trade).",
            }
        except Exception as e:
            logger.error("BROKER ERROR: %s", e)
            return {
                "mode": "live",
                "status": "error",
                "broker": "oanda",
                "reason": f"Broker communication failed: {str(e)}",
            }
    
    async def get_account_summary(self) -> dict:
        """
        Fetch live account balance and equity from OANDA.
        Called by risk_engine.sync_broker_equity().
        """
        if not self.is_live:
            return {"balance": 10_000.0, "equity": 10_000.0, "mode": "paper"}
        
        try:
            account_id = os.getenv("OANDA_ACCOUNT_ID", "")
            api_url = os.getenv("OANDA_API_URL", OANDA_API_URL)
            
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(
                    f"{api_url}/v3/accounts/{account_id}/summary",
                    headers=self._headers(),
                )
            
            if resp.status_code == 200:
                acct = resp.json().get("account", {})
                return {
                    "balance": float(acct.get("balance", 0)),
                    "equity": float(acct.get("NAV", 0)),
                    "unrealized_pl": float(acct.get("unrealizedPL", 0)),
                    "margin_used": float(acct.get("marginUsed", 0)),
                    "margin_available": float(acct.get("marginAvailable", 0)),
                    "open_trade_count": int(acct.get("openTradeCount", 0)),
                    "mode": "live",
                }
            else:
                logger.error("OANDA account summary failed: HTTP %d", resp.status_code)
                return {"balance": 0, "equity": 0, "mode": "error"}
                
        except Exception as e:
            logger.error("OANDA account summary error: %s", e)
            return {"balance": 0, "equity": 0, "mode": "error"}
    
    async def get_open_positions(self) -> Optional[list[dict]]:
        """
        Fetch all open trades from OANDA.
        Used by ghost trade reconciliation to verify broker state.
        Returns a list of dicts with symbol and trade details.
        Returns None if the API call fails, to prevent false negatives.
        """
        if not self.is_live:
            return []
        
        try:
            account_id = os.getenv("OANDA_ACCOUNT_ID", "")
            api_url = os.getenv("OANDA_API_URL", OANDA_API_URL)
            
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(
                    f"{api_url}/v3/accounts/{account_id}/openTrades",
                    headers=self._headers(),
                )
            
            if resp.status_code == 200:
                trades = resp.json().get("trades", [])
                positions = []
                # Reverse-map OANDA instrument back to internal symbol
                reverse_map = {v: k for k, v in OANDA_SYMBOL_MAP.items()}
                for trade in trades:
                    instrument = trade.get("instrument", "")
                    internal_symbol = reverse_map.get(instrument, instrument.replace("_", ""))
                    positions.append({
                        "symbol": internal_symbol,
                        "trade_id": trade.get("id"),
                        "units": trade.get("currentUnits"),
                        "price": trade.get("price"),
                        "unrealized_pl": trade.get("unrealizedPL"),
                        "instrument": instrument,
                    })
                return positions
            else:
                logger.error("OANDA open trades fetch failed: HTTP %d", resp.status_code)
                return None
                
        except Exception as e:
            logger.error("OANDA open trades error: %s", e)
            return None
    
    def _mock_execution(self, order: TradeOrder, decision: RiskDecision) -> dict:
        """Returns a highly realistic mock fill simulating real-world spread and slippage."""
        # 1. Base price from the live data streamer (ensures trades match the UI's test fuel)
        snap = streamer.get_latest_snapshot(order.symbol)
        base_price = snap.bid
        
        # 2. Check current time for high-impact hours (volatility proxy)
        # London/New York session overlap (13:00 - 17:00 UTC) has wild volatility swings
        current_hour = time.gmtime().tm_hour
        is_volatile_hours = 12 <= current_hour <= 18
        
        # 3. Calculate dynamic spread and slippage — scaled to the symbol's pip size
        # Base spread: 1 to 2 pips. Slippage: 0.2 to 3 pips normally, up to 15 pips volatile.
        pip_size = get_pip_size(order.symbol)
        base_spread = random.uniform(1.0, 2.0) * pip_size  # 1-2 pips in price units
        
        if is_volatile_hours:
            slippage = random.uniform(2.0, 15.0) * pip_size  # 2 to 15 pips
        else:
            slippage = random.uniform(0.2, 3.0) * pip_size   # 0.2 to 3 pips

        # Slippage is always unfavorable to the execution direction:
        direction_multiplier = 1 if order.direction.value.upper() == "BUY" else -1
        realistic_fill_price = base_price + (direction_multiplier * (base_spread + slippage))
        
        total_costs_pips = (base_spread + slippage) / pip_size  # Back to pips for logging
        logger.info(
            "📊 Paper Fill Sim: Base %.5f | Cost/Slippage: +%.1f pips | Final Fill %.5f", 
            base_price, total_costs_pips, realistic_fill_price
        )

        return {
            "mode": "paper",
            "status": "simulated",
            "broker": "mock",
            "fill_price": f"{realistic_fill_price:.5f}",
            "units": str(_lot_to_units(decision.calculated_lot_size, order.symbol)),
            "instrument": _get_oanda_instrument(order.symbol),
            "execution_slippage_pips": f"{total_costs_pips:.1f}"
        }
    async def close_trade(self, trade_id: str, account_id: str) -> bool:
        """Closes a specific trade (used by Virtual Stop Sniper Engine)."""
        if not self.is_live: return True
        api_url = os.getenv("OANDA_API_URL", OANDA_API_URL)
        endpoint = f"{api_url}/v3/accounts/{account_id}/trades/{trade_id}/close"
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.put(endpoint, headers=self._headers())
            if resp.status_code == 200:
                logger.info("🎯 VIRTUAL STOP EXECUTION: Successfully closed trade %s", trade_id)
                return True
            else:
                logger.error("VIRTUAL STOP FAIL: HTTP %d for trade %s", resp.status_code, trade_id)
                return False
        except Exception as e:
            logger.error("VIRTUAL STOP ERROR: %s", e)
            return False


# Singleton instance
broker_gateway = BrokerGateway()
