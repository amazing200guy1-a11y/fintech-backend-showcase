"""
Mehd AI — MetaTrader 5 (MT5) Native Gateway
============================================
Provides direct, low-level IPC communication with MetaTrader 5.
Supports Exness, FTMO, IC Markets, XM, Pepperstone, and all MT5 retail brokers.

Zero Middlemen. Zero Cloud API Fees ($0 Cost).
Enforces MEHD AI's Virtual Stop Loss to protect against B-Book broker hunting.
"""

from __future__ import annotations

import logging
import math
from datetime import datetime, timezone
from typing import Optional

from models import TradeOrder, RiskDecision, Direction
from storage import storage

logger = logging.getLogger("mehd.mt5_gateway")

# Try to import MetaTrader5, handle gracefully if not installed
try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    mt5 = None
    MT5_AVAILABLE = False


class MT5Gateway:
    """Manages direct execution and live account queries via MetaTrader 5."""

    def __init__(self):
        self._last_connected_server: Optional[str] = None
        self._last_connected_login: Optional[int] = None

    def is_available(self) -> bool:
        """Returns True if the MetaTrader5 Python package is installed."""
        return MT5_AVAILABLE

    def _ensure_connected(self, credentials: dict | None = None) -> tuple[bool, str]:
        """
        Authenticates with the MT5 terminal using the provided credentials,
        or connects to the currently active desktop session if already authorized.
        Returns (success: bool, error_message: str).
        """
        if not MT5_AVAILABLE or mt5 is None:
            return False, "MetaTrader5 Python library is not available on this platform."

        # Initialize MT5 IPC connection
        if not mt5.initialize():
            err = mt5.last_error()
            logger.warning("MT5 initialize failed: %s", err)
            return False, f"MT5 terminal not detected: {err[1] if len(err) > 1 else err}"

        current_acc = mt5.account_info()

        # If no credentials provided, check if desktop MT5 is already logged in
        if not credentials:
            try:
                already_connected = current_acc is not None and int(current_acc.login) > 0
            except (TypeError, ValueError):
                already_connected = False
            if already_connected:
                self._last_connected_login = current_acc.login
                self._last_connected_server = current_acc.server
                return True, ""
            return False, "No active MT5 account logged in."

        login_raw = credentials.get("login") or credentials.get("api_key")
        password = credentials.get("password") or credentials.get("api_secret")
        server = credentials.get("server") or credentials.get("exchange_id", "")

        # If already logged into this account on desktop, accept immediately
        if current_acc is not None and login_raw:
            try:
                target_login = int(str(login_raw).strip())
                if current_acc.login == target_login:
                    self._last_connected_login = current_acc.login
                    self._last_connected_server = current_acc.server
                    return True, ""
            except ValueError:
                pass

        if not login_raw or not password or not server:
            if current_acc is not None and current_acc.login > 0:
                return True, ""
            return False, "Missing MT5 credentials (server, login, or password required)."

        try:
            login = int(str(login_raw).strip())
        except ValueError:
            return False, f"Invalid MT5 account number format: {login_raw}"

        # If already logged in to this exact account, skip re-login
        if self._last_connected_login == login and self._last_connected_server == str(server).strip():
            acc = mt5.account_info()
            if acc is not None and acc.login == login:
                return True, ""

        # Perform terminal login
        authorized = mt5.login(
            login=login,
            password=str(password).strip(),
            server=str(server).strip(),
        )

        if not authorized:
            err = mt5.last_error()
            logger.error("MT5 login failed for #%d on %s: %s", login, server, err)
            return False, f"MT5 login rejected: {err[1] if len(err) > 1 else err}"

        self._last_connected_login = login
        self._last_connected_server = str(server).strip()
        logger.info("MT5 authorized successfully: Account #%d on %s", login, server)
        return True, ""

    async def get_account_summary(self, credentials: dict) -> dict:
        """
        Pulls exact live balance, equity, and margin from the MT5 broker.
        """
        ok, err_msg = self._ensure_connected(credentials)
        if not ok:
            return {
                "balance": 0.0,
                "equity": 0.0,
                "mode": "error",
                "status": "disconnected",
                "error": err_msg,
            }

        acc = mt5.account_info()
        if acc is None:
            return {
                "balance": 0.0,
                "equity": 0.0,
                "mode": "error",
                "status": "error",
                "error": "Could not read account info from MT5 terminal.",
            }

        is_demo = acc.trade_mode == mt5.ACCOUNT_TRADE_MODE_DEMO

        return {
            "balance": float(acc.balance),
            "equity": float(acc.equity),
            "margin": float(acc.margin),
            "margin_free": float(acc.margin_free),
            "margin_level": float(acc.margin_level) if float(acc.margin) > 0 else 0.0,
            "profit": float(acc.profit),
            "leverage": float(getattr(acc, "leverage", 100)),
            "currency": acc.currency,
            "server": acc.server,
            "login": acc.login,
            "company": acc.company,
            "mode": "demo" if is_demo else "live",
            "status": "connected",
            "broker": "mt5",
        }

    def _resolve_symbol(self, raw_symbol: str) -> Optional[str]:
        """Resolves broker-specific symbol suffixes (e.g. EURUSDm, EURUSD.raw, EURUSD_i)."""
        raw = raw_symbol.replace("/", "").replace("_", "").strip()
        
        # 1. Check exact raw symbol
        if mt5.symbol_info(raw) is not None:
            return raw

        base = raw.upper()
        if mt5.symbol_info(base) is not None:
            return base

        # Strip existing suffix if present (e.g. BTCUSDM -> BTCUSD)
        clean_base = base
        for s in ["M", ".RAW", "_I", ".C", ".PRO"]:
            if clean_base.endswith(s) and len(clean_base) > len(s) + 3:
                clean_base = clean_base[:-len(s)]
                break

        # Common broker suffix variations
        for suffix in ["m", ".raw", "_i", ".c", ".pro", "c", "i", ""]:
            candidate = f"{clean_base}{suffix}"
            if mt5.symbol_info(candidate) is not None:
                return candidate

        return None

    async def execute_order(self, order: TradeOrder, decision: RiskDecision, credentials: dict) -> dict:
        """
        Executes a market order on MT5 with Virtual Stop Loss protection.
        """
        if not getattr(decision, "approved", False) or getattr(decision, "calculated_lot_size", 0.0) <= 0.0:
            return {
                "mode": "error",
                "status": "rejected",
                "broker": "mt5",
                "reason": f"Risk decision rejected: {getattr(decision, 'rejection_reason', None) or 'Calculated lot size is zero'}",
            }

        ok, err_msg = self._ensure_connected(credentials)
        if not ok:
            return {
                "mode": "error",
                "status": "rejected",
                "broker": "mt5",
                "reason": err_msg,
            }

        target_sym = self._resolve_symbol(order.symbol)
        if not target_sym:
            return {
                "mode": "error",
                "status": "rejected",
                "broker": "mt5",
                "reason": f"Symbol '{order.symbol}' was not found on this broker.",
            }

        # Make sure symbol is selected in Market Watch
        mt5.symbol_select(target_sym, True)
        tick = mt5.symbol_info_tick(target_sym)
        sym_info = mt5.symbol_info(target_sym)

        if not tick or not sym_info:
            return {
                "mode": "error",
                "status": "rejected",
                "broker": "mt5",
                "reason": f"No market tick stream available for {target_sym}.",
            }

        is_buy = order.direction == Direction.BUY
        order_type = mt5.ORDER_TYPE_BUY if is_buy else mt5.ORDER_TYPE_SELL
        exec_price = tick.ask if is_buy else tick.bid

        # Lot size normalization
        min_vol = sym_info.volume_min or 0.01
        max_vol = sym_info.volume_max or 100.0
        step_vol = sym_info.volume_step or 0.01

        calc_lots = decision.calculated_lot_size
        if calc_lots < min_vol:
            return {
                "mode": "error",
                "status": "rejected",
                "broker": "mt5",
                "reason": f"Calculated lot size ({calc_lots:.4f}) is below broker minimum contract ({min_vol}).",
            }
        volume = min(calc_lots, max_vol)
        volume = round(math.floor(volume / step_vol) * step_vol, 2)

        # Check filling mode supported by broker (bitmask: 1=FOK, 2=IOC)
        filling = mt5.ORDER_FILLING_IOC
        if sym_info.filling_mode & 2:
            filling = mt5.ORDER_FILLING_IOC
        elif sym_info.filling_mode & 1:
            filling = mt5.ORDER_FILLING_FOK
        else:
            filling = mt5.ORDER_FILLING_RETURN

        # Build trade request (TWO-TIER INSTITUTIONAL SHIELD)
        request = {
            "action": mt5.TRADE_ACTION_DEAL, "symbol": target_sym, "volume": float(volume),
            "type": order_type, "price": float(exec_price), "deviation": 20, "magic": 202609,
            "comment": "MEHD 2-TIER STEALTH" if decision.use_virtual_stops else "MEHD HARD STOP",
            "type_time": mt5.ORDER_TIME_GTC, "type_filling": filling,
        }

        if decision.use_virtual_stops:
            # Place Disaster Hard Stop on broker tight enough (1.5x distance) to prevent account blowouts
            # while keeping strategic SL invisible in MEHD memory vault to avoid stop-hunting
            if decision.stop_loss and float(decision.stop_loss) > 0:
                sl_val = float(decision.stop_loss)
                sl_dist = abs(float(exec_price) - sl_val)
                # 1.5x normal SL distance: outside stop-hunt wick sweeps, but tight enough for zero catastrophic wipeouts
                disaster_dist = sl_dist * 1.5
                disaster_sl = (float(exec_price) - disaster_dist) if is_buy else (float(exec_price) + disaster_dist)
                digits = sym_info.digits if sym_info and sym_info.digits else 2
                request["sl"] = float(round(disaster_sl, digits))
            if decision.take_profit and float(decision.take_profit) > 0:
                digits = sym_info.digits if sym_info and sym_info.digits else 2
                request["tp"] = float(round(float(decision.take_profit), digits))
        else:
            if decision.stop_loss and float(decision.stop_loss) > 0:
                request["sl"] = float(decision.stop_loss)
            if decision.take_profit and float(decision.take_profit) > 0:
                request["tp"] = float(decision.take_profit)

        result = mt5.order_send(request)
        if result is None:
            err = mt5.last_error()
            return {
                "mode": "error",
                "status": "rejected",
                "broker": "mt5",
                "reason": f"MT5 order_send call returned None: {err}",
            }

        if result.retcode != mt5.TRADE_RETCODE_DONE:
            return {
                "mode": "error",
                "status": "rejected",
                "broker": "mt5",
                "reason": f"MT5 broker rejected order (Code {result.retcode}): {result.comment}",
            }

        ticket = result.order or result.deal
        logger.critical("🎯 MT5 FILL: #%s %s %.2f lots @ %.5f", ticket, target_sym, volume, result.price)

        # Register in Virtual Stop Loss Vault
        if decision.use_virtual_stops and ticket:
            await storage.set("virtual_stops", str(ticket), {
                "symbol": order.symbol,
                "direction": order.direction.value,
                "entry_price": float(result.price),
                "stop_loss": float(decision.stop_loss) if decision.stop_loss is not None else None,
                "take_profit": float(decision.take_profit) if decision.take_profit is not None else None,
                "volume": float(volume),
                "broker": "mt5",
                "ticket": str(ticket),
                "account_id": str(ticket),
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })

        acc = mt5.account_info()
        is_demo = acc.trade_mode == mt5.ACCOUNT_TRADE_MODE_DEMO if acc else True

        contract_size = float(sym_info.trade_contract_size) if sym_info and getattr(sym_info, "trade_contract_size", None) else 100000.0
        return {
            "mode": "demo" if is_demo else "live",
            "status": "filled",
            "broker": "mt5",
            "trade_id": str(ticket),
            "fill_price": float(result.price),
            "lot_size": float(volume),
            "units": float(volume) * contract_size,
            "symbol": target_sym,
            "virtual_stop_loss": decision.use_virtual_stops,
        }

    def get_positions(self) -> list[dict]:
        """Pulls exact open positions and live floating profit/loss directly from MetaTrader 5."""
        if not MT5_AVAILABLE or mt5 is None:
            return []

        ok, _ = self._ensure_connected()
        if not ok:
            return []

        positions = mt5.positions_get()
        if not positions:
            return []

        result = []
        for p in positions:
            is_buy = p.type == mt5.ORDER_TYPE_BUY
            sym = p.symbol
            clean_sym = sym
            for s in ["m", ".raw", "_i", ".c", ".pro", "M", ".RAW", "_I", ".C", ".PRO"]:
                if clean_sym.endswith(s) and len(clean_sym) > len(s) + 2:
                    clean_sym = clean_sym[:-len(s)]
                    break

            display_sym = f"{clean_sym[:3]}/{clean_sym[3:]}" if len(clean_sym) == 6 and not clean_sym.endswith(("100", "500")) else clean_sym

            result.append({
                "id": str(p.ticket), "ticket": p.ticket, "symbol": display_sym, "raw_symbol": p.symbol,
                "type": "BUY" if is_buy else "SELL", "direction": "BUY" if is_buy else "SELL",
                "entry": float(p.price_open), "current": float(p.price_current),
                "sl": float(p.sl) if p.sl else None, "tp": float(p.tp) if p.tp else None,
                "lotSize": float(p.volume), "initialLot": float(p.volume),
                "swap": float(p.swap), "pnl": float(p.profit), "profit": float(p.profit),
                "broker": "mt5", "comment": p.comment, "magic": p.magic, "time": p.time,
            })
        return result

    async def close_trade(self, ticket: int | str, volume: Optional[float] = None) -> bool:
        """Closes or partially closes an open MT5 position by ticket."""
        if not MT5_AVAILABLE or mt5 is None:
            return False

        ok, _ = self._ensure_connected()
        if not ok:
            return False

        try:
            ticket_num = int(str(ticket).strip())
        except ValueError:
            return False

        positions = mt5.positions_get(ticket=ticket_num)
        if not positions:
            logger.warning("MT5 position #%d already closed or not found", ticket_num)
            return True  # Already closed

        pos = positions[0]
        is_buy = pos.type == mt5.ORDER_TYPE_BUY
        opposite_type = mt5.ORDER_TYPE_SELL if is_buy else mt5.ORDER_TYPE_BUY

        tick = mt5.symbol_info_tick(pos.symbol)
        sym_info = mt5.symbol_info(pos.symbol)
        if not tick:
            return False

        close_price = tick.bid if is_buy else tick.ask

        # Determine volume to close (supports partial close for 'Bank 50%')
        step = sym_info.volume_step if sym_info and sym_info.volume_step else 0.01
        min_vol = sym_info.volume_min if sym_info and sym_info.volume_min else 0.01
        max_vol = sym_info.volume_max if sym_info and sym_info.volume_max else 100.0

        if volume is not None and volume > 0:
            target_vol = round(round(float(volume) / step) * step, 2)
            target_vol = max(min_vol, min(target_vol, pos.volume))
            close_vol = target_vol
        else:
            close_vol = pos.volume

        filling = mt5.ORDER_FILLING_IOC
        if sym_info:
            if sym_info.filling_mode & 2:
                filling = mt5.ORDER_FILLING_IOC
            elif sym_info.filling_mode & 1:
                filling = mt5.ORDER_FILLING_FOK
            else:
                filling = mt5.ORDER_FILLING_RETURN

        is_partial = close_vol < pos.volume
        request = {
            "action": mt5.TRADE_ACTION_DEAL, "position": pos.ticket, "symbol": pos.symbol,
            "volume": float(close_vol), "type": opposite_type, "price": float(close_price),
            "deviation": 25, "magic": 202609,
            "comment": "MEHD 50% PROFIT BANK" if is_partial else "MEHD AI CLOSE",
            "type_time": mt5.ORDER_TIME_GTC, "type_filling": filling,
        }

        result = mt5.order_send(request)
        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            logger.critical("🎯 MT5 POSITION #%d CLOSED (%.2f lots of %.2f lots)", ticket_num, close_vol, pos.volume)
            return True
        else:
            err = result.comment if result else mt5.last_error()
            logger.error("Failed to close MT5 position #%d: %s", ticket_num, err)
            return False

    async def modify_sl(self, ticket: int | str, new_sl: float, new_tp: float | None = None) -> bool:
        """Moves the stop-loss (and optionally take-profit) of an open MT5 position."""
        if not MT5_AVAILABLE or mt5 is None:
            return False

        ok, _ = self._ensure_connected()
        if not ok:
            return False

        try:
            ticket_num = int(str(ticket).strip())
        except ValueError:
            return False

        positions = mt5.positions_get(ticket=ticket_num)
        if not positions:
            logger.warning("MT5 modify_sl: position #%d not found", ticket_num)
            return False

        pos = positions[0]
        sym_info = mt5.symbol_info(pos.symbol)
        digits = sym_info.digits if sym_info else 5

        request = {
            "action": mt5.TRADE_ACTION_SLTP, "position": ticket_num, "symbol": pos.symbol,
            "sl": round(new_sl, digits), "tp": round(new_tp, digits) if new_tp is not None else pos.tp,
            "magic": 202609, "comment": "MEHD SENTINEL SL MOVE",
        }

        result = mt5.order_send(request)
        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            logger.critical("⚡ MT5 SL MOVED: #%d → SL=%.5f", ticket_num, new_sl)
            return True
        else:
            err = result.comment if result else mt5.last_error()
            logger.error("Failed to modify SL on MT5 #%d: %s", ticket_num, err)
            return False

mt5_gateway = MT5Gateway()

