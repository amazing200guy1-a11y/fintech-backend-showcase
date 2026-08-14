"""
Mehd AI — Risk Engine Tests
==============================
These tests prove that the HardRiskKernel ACTUALLY works.

If any of these fail, real money is at risk.
Run with: python -m pytest tests/test_risk_engine.py -v
"""

import pytest
from datetime import datetime, timezone
from uuid import uuid4

# Add parent dir to path so we can import backend modules
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from risk_engine import HardRiskKernel, ConstitutionManager
from models import TradeOrder, Direction, RiskDecision, AIVote

# ──────────────────────────────────────────────
#  FIXTURES
# ──────────────────────────────────────────────

@pytest.fixture
def anyio_backend():
    return 'asyncio'


@pytest.fixture
def kernel():
    """Fresh risk kernel with $10,000 balance for each test."""
    from risk_state_store import RiskStateStore
    if os.path.exists(RiskStateStore._STATE_FILE):
        try:
            os.remove(RiskStateStore._STATE_FILE)
        except Exception:
            pass
    k = HardRiskKernel()
    yield k
    if os.path.exists(RiskStateStore._STATE_FILE):
        try:
            os.remove(RiskStateStore._STATE_FILE)
        except Exception:
            pass


@pytest.fixture
def valid_buy_order():
    """Standard valid BUY order: EUR/USD, 0.1 lots, SL 50 pips below."""
    return TradeOrder(
        symbol="EURUSD",
        direction=Direction.BUY,
        lot_size=0.1,
        stop_loss=1.0800,
        take_profit=1.0950,
    )


@pytest.fixture
def valid_sell_order():
    """Standard valid SELL order: EUR/USD, 0.1 lots, SL 50 pips above."""
    return TradeOrder(
        symbol="EURUSD",
        direction=Direction.SELL,
        lot_size=0.1,
        stop_loss=1.0900,
        take_profit=1.0750,
    )


# ──────────────────────────────────────────────
#  TEST 1: The 1% Rule (Non-Negotiable)
# ──────────────────────────────────────────────

class TestOnePercentRule:
    """
    The single most important rule in Mehd AI:
    No trade can risk more than 1% of the account balance.
    """

    @pytest.mark.anyio
    async def test_safe_lot_size_respects_one_percent(self, kernel, valid_buy_order):
        """
        EURUSD, entry=1.0850, SL=1.0800 → 50-pip stop.
        1% of $10,000 = $100 max risk.
        Pip value = $10/pip/lot.
        Safe lots = $100 / (50 × $10) = 0.20 lots exactly.
        """
        decision = await kernel.evaluate(valid_buy_order, current_price=1.0850)
        assert decision.approved is True
        assert decision.calculated_lot_size == 0.20

    @pytest.mark.anyio
    async def test_oversized_lot_gets_capped(self, kernel):
        """If trader requests 5.0 lots but safe is 0.20, it must be capped to 0.20."""
        big_order = TradeOrder(
            symbol="EURUSD",
            direction=Direction.BUY,
            lot_size=5.0,  # Way too much
            stop_loss=1.0800,
            take_profit=1.0950,
        )
        decision = await kernel.evaluate(big_order, current_price=1.0850)
        assert decision.approved is True
        assert decision.calculated_lot_size < 5.0   # Must be capped
        assert decision.calculated_lot_size == 0.20  # Capped to exactly the safe level

    @pytest.mark.anyio
    async def test_tiny_account_still_protected(self, kernel):
        """
        $100 balance, 1% risk = $1 max risk.
        EURUSD, 50-pip SL, $10/pip/lot.
        Safe lots = $1 / (50 × $10) = 0.002 → rounds to 0.0 → rejected (< 0.01 min).
        The engine must NOT let this trade through with a dangerous lot size.
        """
        kernel.account = kernel.account.model_copy(
            update={"balance": 100.0, "equity": 100.0}
        )
        order = TradeOrder(
            symbol="EURUSD",
            direction=Direction.BUY,
            lot_size=0.01,
            stop_loss=1.0800,
        )
        decision = await kernel.evaluate(order, current_price=1.0850)
        # Safe lot = $1 / $500 = 0.002 — below 0.01 minimum → must be rejected
        assert decision.approved is False


# ──────────────────────────────────────────────
#  TEST 2: Stop-Loss is MANDATORY
# ──────────────────────────────────────────────

class TestStopLossRequired:
    """No stop-loss = no trade. Period. This is non-negotiable."""

    @pytest.mark.anyio
    async def test_no_stop_loss_rejected(self, kernel):
        """A trade without a stop-loss must ALWAYS be rejected."""
        no_sl_order = TradeOrder(
            symbol="EURUSD",
            direction=Direction.BUY,
            lot_size=0.1,
            stop_loss=None,
        )
        decision = await kernel.evaluate(no_sl_order, current_price=1.0850)
        assert decision.approved is False
        assert "stop-loss" in decision.rejection_reason.lower()


# ──────────────────────────────────────────────
#  TEST 3: Account Lockout (3% Daily Drawdown)
# ──────────────────────────────────────────────

class TestAccountLockout:
    """If daily losses exceed 3%, the account locks for 24 hours."""

    def test_drawdown_triggers_lockout(self, kernel):
        """Simulating 3.5% daily loss should lock the account."""
        kernel.update_drawdown(350.0)  # $350 = 3.5% of $10,000
        health = kernel.get_account_health()
        assert health.is_locked is True
        assert health.lock_reason is not None

    @pytest.mark.anyio
    async def test_locked_account_rejects_all_trades(self, kernel, valid_buy_order):
        """Once locked, every trade attempt must be rejected."""
        kernel.update_drawdown(350.0)
        decision = await kernel.evaluate(valid_buy_order, current_price=1.0850)
        assert decision.approved is False
        assert "locked" in decision.rejection_reason.lower()

    def test_incremental_drawdown_tracked(self, kernel):
        """Multiple small losses should accumulate correctly."""
        kernel.update_drawdown(100.0)  # 1%
        assert not kernel.account.is_locked
        kernel.update_drawdown(100.0)  # 2% total
        assert not kernel.account.is_locked
        kernel.update_drawdown(150.0)  # 3.5% total → LOCK
        assert kernel.account.is_locked


# ──────────────────────────────────────────────
#  TEST 4: Volatility Protection
# ──────────────────────────────────────────────

class TestVolatilityProtection:
    """Wide spreads = dangerous market. Block trades."""

    @pytest.mark.anyio
    async def test_wide_spread_rejected(self, kernel, valid_buy_order):
        """Spread above 5 pips should block the trade."""
        decision = await kernel.evaluate(
            valid_buy_order, current_price=1.0850, current_spread=8.0
        )
        assert decision.approved is False
        assert "spread" in decision.rejection_reason.lower()

    @pytest.mark.anyio
    async def test_normal_spread_approved(self, kernel, valid_buy_order):
        """Normal spread (1.5 pips) should allow the trade."""
        decision = await kernel.evaluate(
            valid_buy_order, current_price=1.0850, current_spread=1.5
        )
        assert decision.approved is True


# ──────────────────────────────────────────────
#  TEST 5: OLYMPUS Agent Verification
# ──────────────────────────────────────────────

class TestOlympusVerification:
    """ATLAS and TITAN verify SL/TP placement logic."""

    @pytest.mark.anyio
    async def test_buy_sl_above_price_rejected(self, kernel):
        """BUY + SL above current price = wrong. ATLAS should veto."""
        bad_order = TradeOrder(
            symbol="EURUSD",
            direction=Direction.BUY,
            lot_size=0.1,
            stop_loss=1.0900,  # ABOVE current price — wrong for BUY
        )
        decision = await kernel.evaluate(bad_order, current_price=1.0850)
        assert decision.approved is False
        assert "ATLAS" in decision.rejection_reason

    @pytest.mark.anyio
    async def test_sell_sl_below_price_rejected(self, kernel):
        """SELL + SL below current price = wrong. ATLAS should veto."""
        bad_order = TradeOrder(
            symbol="EURUSD",
            direction=Direction.SELL,
            lot_size=0.1,
            stop_loss=1.0800,  # BELOW current price — wrong for SELL
        )
        decision = await kernel.evaluate(bad_order, current_price=1.0850)
        assert decision.approved is False
        assert "ATLAS" in decision.rejection_reason

    @pytest.mark.anyio
    async def test_buy_tp_below_price_rejected(self, kernel):
        """BUY + TP below current price = wrong. TITAN should veto."""
        bad_order = TradeOrder(
            symbol="EURUSD",
            direction=Direction.BUY,
            lot_size=0.1,
            stop_loss=1.0800,
            take_profit=1.0800,  # BELOW current price — wrong for BUY
        )
        decision = await kernel.evaluate(bad_order, current_price=1.0850)
        assert decision.approved is False
        assert len(decision.rejection_reason) > 0


# ──────────────────────────────────────────────
#  TEST 6: Math Veto (Divergent Quant Models)
# ──────────────────────────────────────────────

class TestMathVeto:
    """If math models wildly disagree, block the trade."""

    def test_high_divergence_triggers_veto(self, kernel):
        """50+ percentage-point divergence between math models = veto."""
        snapshot_id = uuid4()
        votes = [
            AIVote(
                model_name="TITAN",
                snapshot_id=snapshot_id,
                direction=Direction.BUY,
                confidence=95.0,
                reasoning="Strong buy signal based on momentum.",
            ),
            AIVote(
                model_name="ATLAS",
                snapshot_id=snapshot_id,
                direction=Direction.SELL,
                confidence=30.0,
                reasoning="Weak. Possible black swan volatility detected.",
            ),
        ]
        vetoed, reason = kernel.check_math_veto(votes)
        assert vetoed is True
        assert "divergence" in reason.lower()

    def test_aligned_models_no_veto(self, kernel):
        """Models within 20 points of each other = no veto."""
        snapshot_id = uuid4()
        votes = [
            AIVote(
                model_name="TITAN",
                snapshot_id=snapshot_id,
                direction=Direction.BUY,
                confidence=85.0,
                reasoning="Buy.",
            ),
            AIVote(
                model_name="ATLAS",
                snapshot_id=snapshot_id,
                direction=Direction.BUY,
                confidence=78.0,
                reasoning="Buy.",
            ),
        ]
        vetoed, _ = kernel.check_math_veto(votes)
        assert vetoed is False


# ──────────────────────────────────────────────
#  TEST 7: JPY Pair Handling
# ──────────────────────────────────────────────

class TestJPYPairs:
    """JPY pairs use 0.01 pip size instead of 0.0001."""

    @pytest.mark.anyio
    async def test_jpy_lot_size_calculated_correctly(self, kernel):
        """USD/JPY with 50-pip SL should calculate safe lots correctly."""
        order = TradeOrder(
            symbol="USDJPY",
            direction=Direction.BUY,
            lot_size=0.5,
            stop_loss=149.70,  # ~50 pips below 150.20
        )
        decision = await kernel.evaluate(order, current_price=150.20)
        assert decision.approved is True
        assert decision.calculated_lot_size > 0
        # USD/JPY pip value = $7/pip/lot, 50 pip SL
        # Safe lots = $100 / (50 × $7) = $100 / $350 ≈ 0.29 → rounds to 0.29
        assert decision.calculated_lot_size <= 0.29
        assert decision.calculated_lot_size >= 0.28  # Within rounding tolerance


# ──────────────────────────────────────────────
#  TEST 8: Edge Cases
# ──────────────────────────────────────────────

class TestEdgeCases:
    """Things that shouldn't crash the system."""

    def test_zero_balance_locks_account(self, kernel):
        """$0 balance should lock immediately."""
        kernel.account = kernel.account.model_copy(
            update={"balance": 0.0, "equity": 0.0}
        )
        kernel.update_drawdown(1.0)
        assert kernel.account.is_locked

    @pytest.mark.anyio
    async def test_valid_order_returns_all_fields(self, kernel, valid_buy_order):
        """Approved decision must have all required fields populated."""
        decision = await kernel.evaluate(valid_buy_order, current_price=1.0850)
        assert decision.approved is True
        assert decision.calculated_lot_size > 0
        assert decision.stop_loss > 0
        assert decision.rejection_reason is None
        assert decision.id is not None
        assert decision.timestamp is not None
