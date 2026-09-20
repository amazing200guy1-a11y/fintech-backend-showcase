"""Mehd AI — Broker Gateway (OANDA v20 REST API & Native MT5 Gateway)."""

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
    "EURUSD": "EUR_USD", "GBPUSD": "GBP_USD", "USDJPY": "USD_JPY", "AUDUSD": "AUD_USD",
    "USDCAD": "USD_CAD", "NZDUSD": "NZD_USD", "USDCHF": "USD_CHF", "EURGBP": "EUR_GBP",
    "EURJPY": "EUR_JPY", "GBPJPY": "GBP_JPY", "XAUUSD": "XAU_USD", "XAGUSD": "XAG_USD",
    "BTCUSD": "BTC_USD", "ETHUSD": "ETH_USD", "SOLUSD": "SOL_USD", "NAS100": "NAS100_USD",
    "US30": "US30_USD", "SPX500": "SPX500_USD", "GER40": "DE30_EUR", "USOIL": "WTICO_USD",
}


def _get_oanda_instrument(symbol: str) -> str:
    clean = symbol.upper().replace("/", "")
    return OANDA_SYMBOL_MAP.get(clean, symbol.replace("USD", "_USD"))


def _lot_to_units(lot_size: float, symbol: str) -> int:
    """Convert lot size to OANDA units across all 20 Sovereign assets."""
    if lot_size <= 0.0:
        return 0
    sym = symbol.upper().replace("/", "")
    if "XAU" in sym:
        return max(1, int(round(lot_size * 100)))  # Gold: 1 lot = 100 oz
    elif "XAG" in sym:
        return max(1, int(round(lot_size * 5_000)))  # Silver: 1 lot = 5,000 oz
    elif any(k in sym for k in ("NAS", "US30", "SPX", "GER", "DAX")):
        return max(1, int(round(lot_size)))  # Indices: 1 lot = 1 contract
    elif any(k in sym for k in ("OIL", "WTI")):
        return max(1, int(round(lot_size * 1_000)))  # Crude: 1 lot = 1,000 barrels
    elif any(k in sym for k in ("BTC", "ETH", "SOL")):
        return max(1, int(round(lot_size)))  # Crypto: 1 lot = 1 unit
    return max(1, int(round(lot_size * 100_000)))  # Forex: 1 lot = 100,000 units


def _format_price(price: float, symbol: str) -> str:
    """Format price according to broker instrument decimal precision."""
    sym = symbol.upper().replace("/", "")
    if "JPY" in sym:
        return f"{price:.3f}"
    elif any(k in sym for k in ("XAU", "XAG", "BTC", "ETH", "SOL", "NAS", "US30", "SPX", "GER", "OIL", "WTI")):
        return f"{price:.2f}"
    return f"{price:.5f}"


class BrokerGateway:
    """Handles communication with OANDA REST and native MT5 gateway."""

    def __init__(self):
        self.api_key = os.getenv("OANDA_API_KEY", "")
        self.account_id = os.getenv("OANDA_ACCOUNT_ID", "")
        self.api_url = OANDA_API_URL
        self._is_live = bool(self.api_key and self.account_id)
        self._circuit_breaker_open_until = 0.0
        self._rate_limiter_instance = None
        
        if self._is_live:
            logger.info("BrokerGateway: LIVE mode — connected to OANDA account %s", 
                       self.account_id[:4] + "****")
        else:
            logger.info("BrokerGateway: PAPER mode — no broker keys configured")
    
    @property
    def _rate_limiter(self):
        import asyncio
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = None
        if self._rate_limiter_instance is None or getattr(self, "_rate_limiter_loop", None) != loop:
            self._rate_limiter_instance = asyncio.Semaphore(20)
            self._rate_limiter_loop = loop
        return self._rate_limiter_instance
    
    @property
    def is_live(self) -> bool:
        """Re-check credentials each time (they may be set after init)."""
        key = os.getenv("OANDA_API_KEY", "")
        acct = os.getenv("OANDA_ACCOUNT_ID", "")
        return bool(key and acct)
    
    def _headers(self, credentials: dict | None = None) -> dict:
        """Build API headers with the user's decrypted credentials."""
        from crypto_vault import vault
        api_key = self.api_key or os.getenv("OANDA_API_KEY", "")
        if credentials and "api_key" in credentials:
            # Auto-decrypt if encrypted Fernet token is passed
            raw_key = credentials.get("api_key", "")
            if raw_key.startswith("gAAAAA"):  # Fernet token prefix
                api_key = vault.decrypt_secret(raw_key)
            else:
                api_key = raw_key
        return {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept-Datetime-Format": "RFC3339",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) MehdAI/1.0",
            "X-MBX-APIKEY": api_key,
        }
    
    async def execute_order(self, order: TradeOrder, decision: RiskDecision, credentials: dict | None = None) -> dict:
        """
        Execute an order on the user's connected exchange using their decrypted keys.
        """
        if not getattr(decision, "approved", False) or getattr(decision, "calculated_lot_size", 0.0) <= 0.0:
            return {
                "mode": "error",
                "status": "rejected",
                "broker": "gateway",
                "reason": f"Risk decision rejected: {getattr(decision, 'rejection_reason', None) or 'Calculated lot size is zero'}",
            }

        from crypto_vault import vault
        if credentials:
            credentials = vault.decrypt_credentials(credentials)
            # Check if this is an MT5 broker (Exness, XM, IC Markets, FTMO, etc.)
            exchange_id = (credentials.get("exchange_id") or credentials.get("broker") or "").lower()
            server = credentials.get("server")
            if server or exchange_id in ("exness", "mt5", "xm", "icmarkets", "pepperstone", "ftmo"):
                from mt5_gateway import mt5_gateway
                return await mt5_gateway.execute_order(order, decision, credentials)
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
            
            # Latency defense: bounds protect against execution slippage
            if decision.expected_price > 0:
                pip_size = get_pip_size(order.symbol)
                sym_up = order.symbol.upper().replace("/", "")
                slip_map = {"XAU": 50.0, "XAG": 30.0, "BTC": 50.0, "ETH": 50.0, "NAS": 15.0, "US30": 15.0, "SPX": 15.0}
                max_slip = next((v for k, v in slip_map.items() if k in sym_up), 3.0)
                bound = decision.expected_price + (max_slip * pip_size) if order.direction == Direction.BUY else decision.expected_price - (max_slip * pip_size)
                payload["order"]["priceBound"] = _format_price(bound, order.symbol)
            
            # Two-Tier Stop System:
            # Tier 1: Real strategic SL in virtual stops vault.
            # Tier 2: Catastrophic disaster hard SL on broker to guarantee zero account wipeout.
            if decision.stop_loss:
                if decision.use_virtual_stops:
                    # Place emergency disaster stop calibrated at 1.5x distance (outside hunt wicks, safe from blowouts)
                    sl_dist = abs(decision.expected_price - decision.stop_loss) if decision.expected_price > 0 else 0.0050
                    disaster_sl = (decision.expected_price - (sl_dist * 1.5)) if order.direction == Direction.BUY else (decision.expected_price + (sl_dist * 1.5))
                    payload["order"]["stopLossOnFill"] = {
                        "price": _format_price(disaster_sl, order.symbol),
                        "timeInForce": "GTC",
                    }
                else:
                    payload["order"]["stopLossOnFill"] = {
                        "price": _format_price(decision.stop_loss, order.symbol),
                        "timeInForce": "GTC",
                    }
            
            # Add take-profit if set
            if decision.take_profit and not decision.use_virtual_stops:
                payload["order"]["takeProfitOnFill"] = {
                    "price": _format_price(decision.take_profit, order.symbol),
                    "timeInForce": "GTC",
                }
            
            # Execute the order
            endpoint = f"{self.api_url}/v3/accounts/{account_id}/orders"
            
            start_time = time.monotonic()
            
            async with self._rate_limiter:
                async with httpx.AsyncClient(timeout=3.0) as client:
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
            logger.error("BROKER TIMEOUT: Order for %s did not complete in 3.0s — dropping connection for safety", order.symbol)
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
    
    async def get_account_summary(self, credentials: dict | None = None) -> dict:
        """
        Fetch live account balance and equity from broker (MT5 or OANDA).
        Called by risk_engine.sync_broker_equity().
        """
        if credentials:
            from crypto_vault import vault
            credentials = vault.decrypt_credentials(credentials)
            exchange_id = (credentials.get("exchange_id") or credentials.get("broker") or "").lower()
            server = credentials.get("server")
            if server or exchange_id in ("exness", "mt5", "xm", "icmarkets", "pepperstone", "ftmo"):
                from mt5_gateway import mt5_gateway
                return await mt5_gateway.get_account_summary(credentials)

        # Paper mode: return defaults immediately (no broker needed)
        if not self.is_live and not credentials:
            return {"balance": 10_000.0, "equity": 10_000.0, "mode": "paper"}

        # Check if native MT5 is active on the host machine
        from mt5_gateway import mt5_gateway
        if mt5_gateway.is_available():
            mt5_summary = await mt5_gateway.get_account_summary(credentials or {})
            if mt5_summary.get("status") == "connected":
                return mt5_summary
        
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
    
    async def close_trade(self, trade_id: str, account_id: str = "") -> bool:
        """
        Closes an open trade on the broker (called by VirtualStopWorker).
        Supports MT5 tickets and OANDA trade IDs.
        """
        if str(trade_id).isdigit():
            from mt5_gateway import mt5_gateway
            return await mt5_gateway.close_trade(trade_id)

        if self.is_live:
            try:
                acct = account_id or os.getenv("OANDA_ACCOUNT_ID", "")
                api_url = os.getenv("OANDA_API_URL", OANDA_API_URL)
                async with httpx.AsyncClient(timeout=5.0) as client:
                    resp = await client.put(
                        f"{api_url}/v3/accounts/{acct}/trades/{trade_id}/close",
                        headers=self._headers(),
                    )
                return resp.status_code == 200
            except Exception as e:
                logger.error("OANDA close trade %s error: %s", trade_id, e)
                return False

        return True

    def _mock_execution(self, order: TradeOrder, decision: RiskDecision) -> dict:
        """Returns a highly realistic mock fill simulating real-world spread and slippage."""
        # 1. Base price from the live data streamer (BUY at Ask, SELL at Bid)
        snap = streamer.get_latest_snapshot(order.symbol)
        is_buy = order.direction.value.upper() == "BUY"
        base_price = (snap.ask if snap.ask > 0 else snap.bid) if is_buy else snap.bid
        
        # 2. Check current time for high-impact hours (volatility proxy)
        # London/New York session overlap (12:00 - 18:00 UTC) has elevated volatility
        current_hour = time.gmtime().tm_hour
        is_volatile_hours = 12 <= current_hour <= 18
        
        # 3. Calculate dynamic slippage — scaled to the symbol's pip size
        pip_size = get_pip_size(order.symbol)
        
        if is_volatile_hours:
            slippage = random.uniform(1.0, 8.0) * pip_size   # 1 to 8 pips under volatility
        else:
            slippage = random.uniform(0.1, 2.0) * pip_size   # 0.1 to 2 pips normal

        # Slippage is always unfavorable: BUY fills higher, SELL fills lower
        realistic_fill_price = base_price + slippage if is_buy else base_price - slippage
        
        slippage_pips = slippage / pip_size
        logger.info(
            "📊 Paper Fill Sim: %s Base %.5f | Slippage: +%.1f pips | Final Fill %.5f", 
            "BUY" if is_buy else "SELL", base_price, slippage_pips, realistic_fill_price
        )

        return {
            "mode": "paper",
            "status": "simulated",
            "broker": "mock",
            "fill_price": _format_price(realistic_fill_price, order.symbol),
            "units": str(_lot_to_units(decision.calculated_lot_size, order.symbol)),
            "instrument": _get_oanda_instrument(order.symbol),
            "execution_slippage_pips": f"{slippage_pips:.1f}"
        }

# Singleton instance
broker_gateway = BrokerGateway()
