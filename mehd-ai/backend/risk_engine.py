"""
Mehd AI — Hard Risk Kernel
===========================
This is the single most important file in the entire system.

The HardRiskKernel sits OUTSIDE all AI influence. No model,
no Den verdict, no user override can change or bypass
these rules. They are calculated from raw math on the actual
account numbers.

Think of it like the circuit breaker in your house — the
electricity (AI) does the work, but if something goes wrong,
the breaker (this kernel) cuts power instantly. No negotiation.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional
import json
import os
import re
import time

from models import (
    AccountHealth, 
    Direction, 
    RiskDecision, 
    TradeOrder, 
    AIVote,
    AppConstitution,
    ConstitutionRule,
    get_pip_size
)

from constitution_manager import ConstitutionManager
from risk_state_store import RiskStateStore

logger = logging.getLogger("mehd.risk_engine")


class HardRiskKernel:
    """
    The unbreakable safety layer of Mehd AI.

    Every trade request must pass through evaluate() before
    it can be executed. If any rule fails, the trade is dead.

    Rules enforced:
    1. Max risk per trade is user-configured (0.1%–10%), enforced by the kernel
    2. Every order MUST have a stop-loss
    3. 3% daily drawdown → 24-hour account lock
    4. Abnormal spread → volatility warning
    """

    # ── Constants ─────────────────────────────────────
    MAX_RISK_PER_TRADE_PCT: float = 10.0      # Hard ceiling: user can go up to 10% (set by UI slider)
    MAX_DAILY_DRAWDOWN_PCT: float = 3.0       # 3% daily loss → lockout (matches AppConstants.killSwitchPercent)
    # Autopilot is held to a tighter 2/3 of the user's own drawdown limit.
    # If MAX_DAILY_DRAWDOWN_PCT ever changes, this updates automatically.
    MAX_AUTO_DRAWDOWN_PCT: float = MAX_DAILY_DRAWDOWN_PCT * (2 / 3)  # = 2.0% by default
    LOCKOUT_DURATION_HOURS: int = 24           # How long the lock lasts
    SPREAD_VOLATILITY_THRESHOLD: float = 5.0   # Pips — above this is "wide"
    PIP_VALUE_PER_STANDARD_LOT: float = 10.0   # $10 per pip per standard lot (simplified)
    
    # ── IN-MEMORY CACHE FOR GLOBAL CONSTITUTION ──
    _global_constitution_cache = None
    _global_constitution_timestamp = 0
    
    @classmethod
    async def get_global_constitution_cached(cls):
        now = time.time()
        # 60-second TTL to prevent disk I/O bottleneck
        if cls._global_constitution_cache is None or (now - cls._global_constitution_timestamp) > 60:
            cls._global_constitution_cache = await ConstitutionManager.load(user_id=None)
            cls._global_constitution_timestamp = now
        return cls._global_constitution_cache

    def __init__(self) -> None:
        """
        The kernel starts with a clean state, then restores any persisted
        drawdown/lock state from disk. This ensures that a server restart
        cannot reset the daily drawdown counter (safety critical).
        """
        self.account: AccountHealth = AccountHealth(
            balance=10_000.00,
            equity=10_000.00,
            daily_drawdown_pct=0.0,
            is_locked=False,
            lock_reason=None,
            lock_expiry=None,
        )
        self._restore_state()
        logger.info("HardRiskKernel initialised — balance: $%.2f, drawdown: %.2f%%", 
                    self.account.balance, self.account.daily_drawdown_pct)

    def _persist_state(self) -> None:
        """Save safety-critical state to file (sync) and storage backend (async) via RiskStateStore."""
        RiskStateStore.persist_state(self.account)

    async def restore_from_storage(self) -> None:
        """Async restore from storage backend."""
        updated = await RiskStateStore.restore_from_storage(self.account)
        if updated:
            self.account = updated

    def _restore_state(self) -> None:
        """Restore drawdown/lock state on boot (sync fallback)."""
        self.account = RiskStateStore.restore_state(self.account)


    async def sync_broker_equity(self) -> None:
        """
        Dynamically fetches live equity and margin from the configured Broker API.
        If no API key is present, it falls back to the local demo state.
        """
        try:
            from broker_gateway import broker_gateway
            if broker_gateway.is_live:
                summary = await broker_gateway.get_account_summary()
                if summary.get("mode") == "live" and summary.get("balance", 0) > 0:
                    self.account = self.account.model_copy(
                        update={
                            "balance": summary["balance"],
                            "equity": summary.get("equity", summary["balance"]),
                        }
                    )
                    logger.debug(
                        "Synced broker equity: balance=$%.2f, equity=$%.2f",
                        self.account.balance,
                        self.account.equity,
                    )
                # If mode is "error", keep existing values (don't reset to 0)
        except Exception as e:
            # If broker_gateway import fails or API errors, keep offline state
            logger.debug("Broker sync skipped: %s", e)

    # ──────────────────────────────────────────────────
    #  PUBLIC: evaluate() — the only entry point
    # ──────────────────────────────────────────────────

    async def evaluate(self, order: TradeOrder, current_price: float = 0.0, current_spread: float = 0.0, user_id: str | None = None) -> RiskDecision:
        from risk_evaluator import evaluate_order_risk
        return await evaluate_order_risk(self, order, current_price, current_spread, user_id)

    async def evaluate_master_block(self, order: TradeOrder, current_price: float = 0.0, current_spread: float = 0.0) -> RiskDecision:
        from risk_evaluator import evaluate_master_block_risk
        return await evaluate_master_block_risk(self, order, current_price, current_spread)

    def _get_pip_value(self, symbol: str) -> float:
        """Returns approximate USD pip value for 1 standard lot (100,000 units)."""
        sym = symbol.upper()
        if "XAU" in sym: return 1.0
        if "JPY" in sym: return 7.0
        if "GBP" in sym and not "USD" in sym: return 12.0
        return 10.0

    def calculate_user_lot_size(self, cfg: "AutopilotConfig", stop_loss_pips: float, consensus: float, current_spread: float, symbol: str = "") -> float:
        """
        Institutional Capital Scaling Engine.
        Calculates a user's safe lot size based on their simulated equity, enforcing drawdown penalties,
        win streak caps, and max lot ceilings.
        """
        MIN_LOT = 0.01
        
        if getattr(cfg, "compounding_mode", "OFF") == "OFF":
            return MIN_LOT

        equity = getattr(cfg, "simulated_equity", 100.0)

        # 1. Negative Equity Protection
        if equity <= 0:
            cfg.simulated_equity = 100.0
            cfg.compounding_mode = "OFF"
            return MIN_LOT

        # 2. Capital Protection Floor (Disable if equity < 70% of starting)
        if equity < 70.0:  # Assuming 100 was starting
            return MIN_LOT

        # 3. Drawdown Check
        drawdown = getattr(cfg, "current_drawdown_pct", 0.0)
        if drawdown >= 5.0:
            return MIN_LOT
            
        # 4. Base Risk sizing — use the user's configured risk, capped at MAX
        # cfg.risk_per_trade is stored as a percentage (1.0 = 1%)
        user_risk_pct = getattr(cfg, "risk_per_trade", 1.0)
        risk_pct = min(user_risk_pct, self.MAX_RISK_PER_TRADE_PCT) / 100  # convert to decimal for math
        
        # 5. Drawdown Penalty
        if drawdown >= 3.0:
            risk_pct *= 0.5  # Slash risk by 50%
            
        # 6. Loss Streak Protection
        losses = getattr(cfg, "consecutive_losses", 0)
        if losses >= 3:
            return MIN_LOT  # Temporary pause
        elif losses >= 2:
            risk_pct *= 0.7  # Reduce by 30%

        # 8. Controlled Boost (+25%) / ALPHA PREDATOR BOOST (+50%)
        boost = 1.0
        is_predator = getattr(cfg, "predator_mode", False)
        wins = getattr(cfg, "consecutive_wins", 0)
        
        is_spread_safe = current_spread <= self.SPREAD_VOLATILITY_THRESHOLD
        
        if is_predator and wins >= 1 and losses == 0:
            boost = 1.50 # ALPHA PREDATOR: 50% risk boost on win streaks
            logger.info("🔥 ALPHA PREDATOR ACTIVATED: Scaling risk by 1.5x after win streak.")
        elif consensus >= 90.0 and is_spread_safe and losses == 0:
            boost = 1.25
            
        # 9. Math Calculation
        sl_pips = max(stop_loss_pips, 1.0)
        pip_value = self._get_pip_value(symbol)
        raw_lot = (equity * risk_pct * boost) / (sl_pips * pip_value)
        
        # 10. Dynamic Max Cap: min(5.0, equity * safe_ratio)
        safe_ratio = 1.0 / 1000.0  # max 1 lot per $1000 equity
        
        # Predator expands the cap
        cap_limit = 10.0 if is_predator else 5.0
        dynamic_cap = min(cap_limit, equity * safe_ratio)
        
        final_lot = max(MIN_LOT, min(raw_lot, dynamic_cap))
        
        # 7. Win Streak Freeze (Bypassed in Predator Mode)
        if wins >= 3 and not is_predator:
            # Freeze growth by removing boost and capping aggressively
            frozen_lot = (equity * 0.01) / (sl_pips * pip_value)
            final_lot = max(MIN_LOT, min(frozen_lot, dynamic_cap))
            
        return round(final_lot, 2)

    # ──────────────────────────────────────────────────
    #  PUBLIC: check_volatility() — spread check
    # ──────────────────────────────────────────────────

    def check_volatility(self, spread: float) -> bool:
        """
        Returns True if the spread is abnormally wide.

        When True, the frontend should grey out the trade button
        because trading during extreme volatility is dangerous —
        slippage can make stop-losses meaningless.
        """
        is_volatile = spread > self.SPREAD_VOLATILITY_THRESHOLD
        if is_volatile:
            logger.warning(
                "VOLATILITY WARNING: Spread %.2f pips exceeds threshold %.2f pips",
                spread,
                self.SPREAD_VOLATILITY_THRESHOLD,
            )
        return is_volatile

    def check_math_veto(self, math_votes: list[AIVote]) -> tuple[bool, str]:
        """
        Check if any 2 Math models veto the trade based on detecting
        black swans, extreme volatility, slippage >10%, or calculation mismatch.
        """
        vetoes = 0
        reasons = []

        for vote in math_votes:
            text = vote.reasoning.lower()
            if any(kw in text for kw in ["black swan", "volatility", "slippage"]):
                vetoes += 1
                reasons.append(vote.model_name)

        if len(math_votes) >= 2:
            confidences = [v.confidence for v in math_votes]
            max_divergence = max(confidences) - min(confidences)
            if max_divergence > 50.0:  # 50 percentage-point mismatch
                vetoes += 2
                reasons.append("divergence")

        if vetoes >= 2:
            reason = f"Math Layer Veto triggered by {', '.join(set(reasons))}."
            logger.critical("FIREBASE LOG: %s", reason)
            return True, reason

        return False, ""

    # ──────────────────────────────────────────────────
    #  PUBLIC: update_drawdown() — track daily losses
    # ──────────────────────────────────────────────────

    def update_drawdown(self, loss_amount: float) -> None:
        """
        Called after a trade closes at a loss to update the
        running daily drawdown percentage. If it crosses 3%,
        the account gets locked immediately.
        """
        if self.account.balance <= 0:
            self._lock_account(reason="Account balance is zero or negative")
            return

        loss_pct = (loss_amount / self.account.balance) * 100
        new_drawdown = self.account.daily_drawdown_pct + loss_pct

        self.account = self.account.model_copy(
            update={"daily_drawdown_pct": new_drawdown}
        )
        self._persist_state()

        logger.info("Daily drawdown updated: %.2f%%", new_drawdown)

        if new_drawdown >= self.MAX_DAILY_DRAWDOWN_PCT:
            self._lock_account(
                reason=(
                    f"Daily drawdown hit {new_drawdown:.2f}% "
                    f"(limit: {self.MAX_DAILY_DRAWDOWN_PCT}%)"
                )
            )
            # ── TRACK RECORD: Log lockout as proof of protection ──
            try:
                import track_record
                track_record.log_drawdown_lockout(
                    drawdown_pct=new_drawdown,
                    max_pct=self.MAX_DAILY_DRAWDOWN_PCT,
                    lock_duration_hours=self.LOCKOUT_DURATION_HOURS,
                )
            except Exception as e:
                logger.warning("Failed to log drawdown lockout: %s", e)  # Track record should never crash the risk engine

    # ──────────────────────────────────────────────────
    #  PRIVATE helpers
    # ──────────────────────────────────────────────────

    def _verify_olympus_agents(self, order: TradeOrder, current_price: float) -> Optional[str]:
        """
        OLYMPUS mathematical verification before calculating anything else.
        ATLAS checks SL validity.
        TITAN checks TP validity.
        """
        if current_price <= 0:
            return None # Skip if no live price fed (e.g. mock test)

        is_buy = order.direction == Direction.BUY
        
        # ATLAS Verification
        if order.stop_loss is not None:
            if is_buy and order.stop_loss >= current_price:
                return "ATLAS VETO: Stop loss must be below current price for BUY orders."
            if not is_buy and order.stop_loss <= current_price:
                return "ATLAS VETO: Stop loss must be above current price for SELL orders."
                
        # TITAN Verification
        if order.take_profit is not None:
            if is_buy and order.take_profit <= current_price:
                return "TITAN VETO: Take profit must be above current price for BUY orders."
            if not is_buy and order.take_profit >= current_price:
                return "TITAN VETO: Take profit must be below current price for SELL orders."
                
            # Tiger Mode asymmetric payout enforcement — only applies to 'tiger' tier orders
            if order.tier == 'tiger' and order.stop_loss is not None:
                stop_distance = abs(current_price - order.stop_loss)
                target_distance = abs(order.take_profit - current_price)
                if stop_distance > 0 and target_distance < (2.0 * stop_distance):
                    rr_actual = target_distance / stop_distance
                    return (f"TITAN VETO: Risk:Reward is {rr_actual:.2f}:1, below the Tiger Mode minimum of 2:1 "
                            f"(Risk: {stop_distance:.4f}, Reward: {target_distance:.4f}). "
                            "Tiger Mode only hunts asymmetric payouts.")
                
        return None

    def _calculate_safe_lot_size(self, order: TradeOrder, entry_price: float = 0.0) -> float:
        """
        Calculate the maximum lot size that risks at most 1% of balance.

        Formula:
            max_risk_dollars = balance × (max_risk_pct / 100)
            stop_distance_pips = |entry_price - stop_loss| / pip_size
            safe_lots = max_risk_dollars / (stop_distance_pips × pip_value_per_lot)

        This is pure math — the AI has no say in this number.
        """
        # risk_percentage is stored as a percentage value in TradeOrder (1.0 = 1%, max 1.0).
        # Do NOT multiply by 100 — it's already a percentage, not a decimal.
        client_risk_pct = order.risk_percentage or 1.0
        if order.is_auto_execution:
            applied_risk_pct = min(0.5, client_risk_pct)  # Autopilot never exceeds 0.5%
        else:
            applied_risk_pct = min(client_risk_pct, self.MAX_RISK_PER_TRADE_PCT)  # Cap at hard ceiling
        max_risk_dollars = self.account.balance * (applied_risk_pct / 100)

        # For forex, 1 pip = 0.0001 for most pairs (0.01 for JPY, 0.1 for XAU)
        pip_size = get_pip_size(order.symbol)

        # Use the ACTUAL current market price passed from the streamer.
        # If not provided, fall back to a conservative 50-pip estimate.
        if entry_price > 0 and order.stop_loss is not None:
            stop_distance = abs(entry_price - order.stop_loss)
        else:
            stop_distance = 50.0 * pip_size  # Conservative fallback
            logger.warning("No entry price provided — using conservative 50-pip SL distance")

        stop_distance_pips = max(stop_distance / pip_size, 1.0)

        safe_lot_size = max_risk_dollars / (
            stop_distance_pips * self._get_pip_value(order.symbol)
        )

        # Round to 2 decimal places (standard lot precision)
        safe_lot_size = round(safe_lot_size, 2)

        logger.debug(
            "FORGE Risk calc: max_risk=$%.2f, entry=%.5f, sl=%.5f, stop_dist=%.1f pips, safe_lots=%.2f",
            max_risk_dollars,
            entry_price,
            order.stop_loss or 0.0,
            stop_distance_pips,
            safe_lot_size,
        )

        return safe_lot_size

    def _estimate_max_loss(self, lot_size: float, order: TradeOrder, entry_price: float = 0.0) -> float:
        """
        Estimate the maximum possible loss for this trade
        (i.e., if the stop-loss is hit).
        """
        pip_size = get_pip_size(order.symbol)

        if entry_price > 0 and order.stop_loss is not None:
            stop_distance = abs(entry_price - order.stop_loss)
        else:
            stop_distance = 50.0 * pip_size

        stop_distance_pips = max(stop_distance / pip_size, 1.0)

        max_loss = lot_size * stop_distance_pips * self._get_pip_value(order.symbol)
        return max_loss

    def _lock_account(self, reason: str) -> None:
        """Lock the account for LOCKOUT_DURATION_HOURS."""
        expiry = datetime.now(timezone.utc) + timedelta(hours=self.LOCKOUT_DURATION_HOURS)
        self.account = self.account.model_copy(
            update={
                "is_locked": True,
                "lock_reason": reason,
                "lock_expiry": expiry,
            }
        )
        self._persist_state()
        logger.critical(
            "🔒 ACCOUNT LOCKED: %s — Unlocks at %s",
            reason,
            expiry.isoformat(),
        )

    def _unlock_account(self) -> None:
        """Unlock the account after the lockout period expires."""
        self.account = self.account.model_copy(
            update={
                "is_locked": False,
                "lock_reason": None,
                "lock_expiry": None,
                "daily_drawdown_pct": 0.0,
            }
        )
        self._persist_state()
        logger.info("🔓 Account UNLOCKED — daily drawdown reset to 0%%")

    def get_account_health(self) -> AccountHealth:
        """Return the current account health snapshot."""
        # Auto-unlock if expiry has passed
        if (
            self.account.is_locked
            and self.account.lock_expiry
            and datetime.now(timezone.utc) >= self.account.lock_expiry
        ):
            self._unlock_account()
        return self.account
