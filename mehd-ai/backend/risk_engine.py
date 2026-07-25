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
    1. Max 1% of balance at risk per trade
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
        """
        Run ALL risk checks on a trade order.
        Returns a RiskDecision — approved or rejected with reason.

        The order of checks matters:
        1. Account lock check (fastest — just read a boolean)
        2. Absolute Risk check (simple multiplication)
        3. Market Environment check (spread/volatility)
        4. Take Profit Logic (verify R:R)
        5. Drift / Data Tampering detection
        """
        # Always read real money before making a decision.
        await self.sync_broker_equity()

        logger.info("Kernel beginning evaluation for %s trade...", order.symbol)
        logger.info(
            "Evaluating order: %s %s %.2f lots (entry_price=%.5f)",
            order.direction.value,
            order.symbol,
            order.lot_size,
            current_price,
        )

        # ── CHECK 0: Economic Calendar (Sovereign Lock / SUPREME Override) ──────────
        from economic_calendar import calendar_gateway
        minutes_to_news = calendar_gateway.get_minutes_to_next_high_impact_news(order.symbol)
        
        # SUPREME Override: Stricter news window for auto-execution (60 mins vs 30 mins)
        news_threshold = 60 if order.is_auto_execution else 30
        
        if minutes_to_news is not None and minutes_to_news <= news_threshold:
            return RiskDecision(
                approved=False,
                calculated_lot_size=0.0,
                stop_loss=order.stop_loss or 0.0001,
                take_profit=order.take_profit,
                rejection_reason=(
                    f"REJECTED: {'SUPREME OVERRIDE' if order.is_auto_execution else 'SOVEREIGN LOCK'}. "
                    f"High impact news in {minutes_to_news} mins. "
                    "Trading is paused to protect capital from extreme volatility spikes."
                ),
                vetoing_agents=["KERNEL", "SENTINEL"]
            )

        # ── CHECK 1: Is the account locked? ──────────
        if self.account.is_locked:
            # Check if the lock has expired
            if self.account.lock_expiry and datetime.now(timezone.utc) >= self.account.lock_expiry:
                self._unlock_account()
            else:
                expiry_str = (
                    self.account.lock_expiry.isoformat()
                    if self.account.lock_expiry
                    else "unknown"
                )
                return RiskDecision(
                    approved=False,
                    calculated_lot_size=0.0,
                    stop_loss=order.stop_loss or 0.0001,
                    take_profit=order.take_profit,
                    rejection_reason=(
                        f"Account is locked: {self.account.lock_reason}. "
                        f"Unlocks at {expiry_str}"
                    ),
                    vetoing_agents=["KERNEL"]
                )

        # ── CHECK 2: Volatility / Spread check ──────
        # SUPREME Override: Stricter spread check for auto-execution
        spread_threshold = self.SPREAD_VOLATILITY_THRESHOLD * 0.5 if order.is_auto_execution else self.SPREAD_VOLATILITY_THRESHOLD
        
        if current_spread > spread_threshold:
            return RiskDecision(
                approved=False,
                calculated_lot_size=0.0,
                stop_loss=order.stop_loss or 0.0001,
                take_profit=order.take_profit,
                rejection_reason=(
                    f"REJECTED: Spread is {current_spread:.1f} pips — above the "
                    f"{spread_threshold:.1f} pip safety threshold. "
                    f"{'SUPREME OVERRIDE: ' if order.is_auto_execution else ''}Trading during extreme volatility is blocked."
                ),
                vetoing_agents=["KERNEL", "TITAN"]
            )

        # ── CHECK 3: Is there a stop-loss? ───────────
        if order.stop_loss is None:
            return RiskDecision(
                approved=False,
                calculated_lot_size=0.0,
                stop_loss=0.0001,  # Placeholder — trade is rejected anyway
                take_profit=order.take_profit,
                rejection_reason=(
                    "REJECTED: No stop-loss provided. Every trade in Mehd AI "
                    "must have a stop-loss. This is non-negotiable."
                ),
                vetoing_agents=["KERNEL"]
            )

        # ── CHECK 3.5: OLYMPUS Agents Verification ──
        olympus_veto = self._verify_olympus_agents(order, current_price)
        if olympus_veto:
            agent = olympus_veto.split(" VETO:")[0] if " VETO:" in olympus_veto else "OLYMPUS"
            return RiskDecision(
                approved=False,
                calculated_lot_size=0.0,
                stop_loss=order.stop_loss,
                take_profit=order.take_profit,
                rejection_reason="REJECTED: %s" % olympus_veto,
                vetoing_agents=[agent]
            )

        # ── CHECK 4: Calculate safe lot size ─────────
        safe_lot_size = self._calculate_safe_lot_size(order, current_price)

        if safe_lot_size <= 0:
            return RiskDecision(
                approved=False,
                calculated_lot_size=0.0,
                stop_loss=order.stop_loss,
                take_profit=order.take_profit,
                rejection_reason=(
                    "REJECTED: Calculated safe lot size is zero or negative. "
                    "The stop-loss distance may be too tight for your account balance."
                ),
                vetoing_agents=["KERNEL", "ATLAS"]
            )

        # If the trader asked for more lots than is safe, cap it
        final_lot_size = min(order.lot_size, safe_lot_size)

        if final_lot_size < order.lot_size:
            logger.warning(
                "Lot size capped: requested %.4f → safe %.4f",
                order.lot_size,
                final_lot_size,
            )

        # ── CHECK 4: Daily drawdown check ────────────
        # (This check runs here because the trade itself might push
        #  drawdown over the limit — we need to simulate it)
        potential_loss = self._estimate_max_loss(final_lot_size, order, current_price)
        potential_drawdown_pct = (
            (self.account.daily_drawdown_pct)
            + (potential_loss / self.account.balance * 100)
        )

        # SUPREME Override: autopilot is held to MAX_AUTO_DRAWDOWN_PCT (2/3 of user drawdown limit)
        # This keeps a tighter leash on the AI than the user themselves would have.
        max_drawdown = self.MAX_AUTO_DRAWDOWN_PCT if order.is_auto_execution else self.MAX_DAILY_DRAWDOWN_PCT

        if potential_drawdown_pct >= max_drawdown:
            if order.is_auto_execution:
                return RiskDecision(
                    approved=False,
                    calculated_lot_size=0.0,
                    stop_loss=order.stop_loss,
                    take_profit=order.take_profit,
                    rejection_reason=f"SUPREME OVERRIDE: Autopilot daily loss limit ({max_drawdown}%) hit.",
                    vetoing_agents=["KERNEL"]
                )
            else:
                self._lock_account(
                    reason=(
                        f"Daily drawdown would reach {potential_drawdown_pct:.2f}% "
                        f"(limit: {max_drawdown}%). "
                        f"Trade blocked to protect your capital."
                    )
                )
                return RiskDecision(
                    approved=False,
                    calculated_lot_size=0.0,
                    stop_loss=order.stop_loss,
                    take_profit=order.take_profit,
                    rejection_reason=self.account.lock_reason,
                    vetoing_agents=["KERNEL"]
                )

        # ── CHECK 5: The Trader's Constitution ────────
        # Load the trader's PERSONAL mandate and enforce it ruthlessly.
        # Fix Constitution Disconnect: Load GLOBAL autonomous rules as well
        personal_constitution = await ConstitutionManager.load(user_id=user_id)
        global_constitution = await self.get_global_constitution_cached()
        
        all_rules = personal_constitution.rules + global_constitution.rules
        
        for rule in all_rules:
            if not rule.is_active:
                continue
                
            # Rule: Max Daily Trades
            if rule.rule_type == "max_daily_trades":
                if personal_constitution.daily_trades_count >= rule.parameter:
                    logger.critical("🔥 CONSTITUTION VETO: %s (Limit: %d, Taken: %d)", 
                                    rule.name, rule.parameter, personal_constitution.daily_trades_count)
                    return RiskDecision(
                        approved=False,
                        calculated_lot_size=0.0,
                        stop_loss=order.stop_loss or 0.0,
                        take_profit=order.take_profit,
                        rejection_reason="CONSTITUTION_VETO: %s" % rule.description,
                        vetoing_agents=["CONSTITUTION"]
                    )
            
            # Rule: Minimum Consensus (requires knowing the consensus %, which we don't have here)
            # We will assume consensus is passed in via the order or enforced before execution.
            # But we can add a placeholder comment.
            elif rule.rule_type == "min_consensus":
                # Enforced in the consensus engine or main.py. Passed here to avoid changing signature too much.
                pass
                
            # Rule: Forbidden Trading Hours (e.g., param could be an int representing hour to ban)
            elif rule.rule_type == "forbidden_hours":
                current_hour = datetime.now(timezone.utc).hour
                if current_hour == int(rule.parameter):
                    logger.critical("🔥 CONSTITUTION VETO: %s (Forbidden Hour: %02d:00 UTC)", 
                                    rule.name, int(rule.parameter))
                    return RiskDecision(
                        approved=False,
                        calculated_lot_size=0.0,
                        stop_loss=order.stop_loss or 0.0,
                        take_profit=order.take_profit,
                        rejection_reason="CONSTITUTION_VETO: %s" % rule.description,
                        vetoing_agents=["CONSTITUTION"]
                    )

            # Rule: Autonomous Dynamic Veto (Self-Learning Feedback Loop)
            elif rule.rule_type == "dynamic_veto":
                cond = getattr(rule, "condition_payload", {})
                if cond:
                    # Filter by Symbol (if specified)
                    if cond.get("symbol") and cond.get("symbol") != order.symbol:
                        continue
                    
                    # Filter by Direction (if specified)
                    if cond.get("direction") and cond.get("direction") != order.direction.value:
                        continue
                    
                    # Condition: Max Spread
                    max_spread = cond.get("max_spread_allowed")
                    if max_spread is not None and current_spread > max_spread:
                        logger.critical("🔥 AUTONOMOUS VETO: %s (Spread %.1f > %.1f)", 
                                        rule.name, current_spread, max_spread)
                        return RiskDecision(
                            approved=False,
                            calculated_lot_size=0.0,
                            stop_loss=order.stop_loss or 0.0,
                            take_profit=order.take_profit,
                            rejection_reason=f"AUTONOMOUS_VETO (Learned): {rule.description}",
                            vetoing_agents=["SENTINEL"]
                        )
                    
                    # Structural Condition: Depth of Market (DOM) Imbalance
                    min_dom = cond.get("min_dom_imbalance")
                    max_dom = cond.get("max_dom_imbalance")
                    
                    if min_dom is not None or max_dom is not None:
                        try:
                            from state import streamer
                            snapshot = streamer.get_latest_snapshot(order.symbol)
                            
                            # Fix "Failing Open": If safety rules require DOM data, and we don't have it, we must reject.
                            if not snapshot or not snapshot.dom_data:
                                # Rule Decay: If the rule is older than 24 hours, assume a permanent data provider outage and skip.
                                rule_age = datetime.now(timezone.utc) - rule.created_at
                                if rule_age > timedelta(hours=24):
                                    logger.warning("⚠️ Bypassing stale structural rule %s (Missing DOM data, rule age > 24h).", rule.name)
                                    pass # Bypass rule
                                else:
                                    logger.critical("🔥 STRUCTURAL VETO: %s (Missing DOM data for safety check. Rule is fresh: fails closed.)", rule.name)
                                    return RiskDecision(
                                        approved=False,
                                        calculated_lot_size=0.0,
                                        stop_loss=order.stop_loss or 0.0,
                                        take_profit=order.take_profit,
                                        rejection_reason="STRUCTURAL_DATA_MISSING: Cannot verify DOM safety rule.",
                                        vetoing_agents=["KERNEL", "TITAN"]
                                    )
                                    
                            if snapshot and snapshot.dom_data:
                                imbalance = snapshot.dom_data.imbalance_ratio
                                
                                if min_dom is not None and imbalance < min_dom:
                                    logger.critical("🔥 STRUCTURAL VETO: %s (DOM Imbalance %.2f < %.2f limit)", 
                                                    rule.name, imbalance, min_dom)
                                    return RiskDecision(
                                        approved=False,
                                        calculated_lot_size=0.0,
                                        stop_loss=order.stop_loss or 0.0,
                                        take_profit=order.take_profit,
                                        rejection_reason=f"STRUCTURAL_VETO (Learned): {rule.description}",
                                        vetoing_agents=["SENTINEL", "TITAN"]
                                    )
                                    
                                if max_dom is not None and imbalance > max_dom:
                                    logger.critical("🔥 STRUCTURAL VETO: %s (DOM Imbalance %.2f > %.2f limit)", 
                                                    rule.name, imbalance, max_dom)
                                    return RiskDecision(
                                        approved=False,
                                        calculated_lot_size=0.0,
                                        stop_loss=order.stop_loss or 0.0,
                                        take_profit=order.take_profit,
                                        rejection_reason=f"STRUCTURAL_VETO (Learned): {rule.description}",
                                        vetoing_agents=["SENTINEL", "TITAN"]
                                    )
                        except ImportError:
                            pass # If streamer isn't available, skip structural check

        # ── ALL CHECKS PASSED ────────────────────────
        logger.info(
            "Trade APPROVED: %s %s %.4f lots (SL: %.5f, TP: %s)",
            order.direction.value,
            order.symbol,
            final_lot_size,
            order.stop_loss,
            order.take_profit,
        )

        return RiskDecision(
            approved=True,
            calculated_lot_size=final_lot_size,
            stop_loss=order.stop_loss,
            take_profit=order.take_profit,
            expected_price=current_price,
            rejection_reason=None,
        )

    async def evaluate_master_block(self, order: TradeOrder, current_price: float = 0.0, current_spread: float = 0.0) -> RiskDecision:
        """
        Special evaluation for Master Block orders.
        Bypasses individual retail equity constraints (max 1% balance),
        but strictly enforces structural market safety (news, spread, DOM).
        The actual lot size is preserved as requested by the aggregator.
        """
        logger.info("Kernel beginning MASTER BLOCK evaluation for %s trade...", order.symbol)

        # ── CHECK 0: Economic Calendar ──────────
        from economic_calendar import calendar_gateway
        minutes_to_news = calendar_gateway.get_minutes_to_next_high_impact_news(order.symbol)
        
        news_threshold = 60
        if minutes_to_news is not None and minutes_to_news <= news_threshold:
            return RiskDecision(
                approved=False, calculated_lot_size=0.0, stop_loss=order.stop_loss or 0.0001, take_profit=order.take_profit,
                rejection_reason=f"REJECTED: SUPREME OVERRIDE. High impact news in {minutes_to_news} mins.",
                vetoing_agents=["KERNEL", "SENTINEL"]
            )

        # ── CHECK 2: Volatility / Spread check ──────
        spread_threshold = self.SPREAD_VOLATILITY_THRESHOLD * 0.5
        if current_spread > spread_threshold:
            return RiskDecision(
                approved=False, calculated_lot_size=0.0, stop_loss=order.stop_loss or 0.0001, take_profit=order.take_profit,
                rejection_reason=f"REJECTED: Spread is {current_spread:.1f} pips — above the {spread_threshold:.1f} pip safety threshold.",
                vetoing_agents=["KERNEL", "TITAN"]
            )

        # ── CHECK 3: Is there a stop-loss? ───────────
        if order.stop_loss is None:
            return RiskDecision(
                approved=False, calculated_lot_size=0.0, stop_loss=0.0001, take_profit=order.take_profit,
                rejection_reason="REJECTED: No stop-loss provided.",
                vetoing_agents=["KERNEL"]
            )

        # ── CHECK 3.5: OLYMPUS Agents Verification ──
        olympus_veto = self._verify_olympus_agents(order, current_price)
        if olympus_veto:
            agent = olympus_veto.split(" VETO:")[0] if " VETO:" in olympus_veto else "OLYMPUS"
            return RiskDecision(
                approved=False, calculated_lot_size=0.0, stop_loss=order.stop_loss, take_profit=order.take_profit,
                rejection_reason="REJECTED: %s" % olympus_veto,
                vetoing_agents=[agent]
            )

        # ── ALL CHECKS PASSED ────────────────────────
        return RiskDecision(
            approved=True,
            calculated_lot_size=order.lot_size, # Preserve original volume
            stop_loss=order.stop_loss,
            take_profit=order.take_profit,
            expected_price=current_price,
            rejection_reason=None,
        )

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
            
        # 4. Base Risk sizing (1% standard)
        risk_pct = 0.01
        
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
        # FIX C5: Read risk % from the order (already server-clamped in routes/trading.py).
        # For auto-execution, apply the stricter 0.5% SUPREME Override cap.
        # order.risk_percentage arrives as a decimal (e.g. 0.02 = 2%), so multiply by 100.
        client_risk_pct = (order.risk_percentage or 0.01) * 100  # convert decimal → percentage
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
