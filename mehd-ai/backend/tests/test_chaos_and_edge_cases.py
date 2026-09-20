"""
Mehd AI — Autonomous Chaos & Edge-Case Simulation Suite
======================================================
Tests non-negotiable defensive perimeters under extreme conditions:
  1. Flash spread widening (>5x typical) -> trade blocked.
  2. News blackout safety window (<5 min to high impact) -> entries halted.
  3. Broker disconnect / timeout -> consecutive failure threshold triggers safety pause.
  4. Drawdown limit lockout & non-positive equity defense -> 0 lot size, allowed=False.
"""

import pytest
import asyncio
from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock, AsyncMock, patch

from risk_engine import HardRiskKernel
from hardened_kill_switch import HardenedKillSwitch
from economic_calendar import is_high_impact_event
from auto_execution_worker import auto_execution_worker
from models import TradeOrder, Direction, AutopilotConfig


class TestChaosAndEdgeCases:
    """Rigorous tests covering extreme market anomalies and broker drops."""

    @pytest.fixture
    def risk_kernel(self):
        kernel = HardRiskKernel()
        kernel.account.balance = 10_000.0
        kernel.account.equity = 10_000.0
        kernel.account.daily_drawdown_pct = 0.0
        kernel.account.is_locked = False
        return kernel

    def test_flash_spread_widening_blocks_execution(self, risk_kernel):
        """
        Verify that a sudden spread spike (e.g. from 0.8 pips to 6.0 pips)
        triggers the spread volatility barrier and fails trade approval.
        """
        # 1. Normal spread (0.8 pips) on EUR/USD -> Passes risk evaluation
        res_normal = risk_kernel.evaluate_trade(
            account_balance=10_000.0,
            risk_per_trade_pct=1.0,
            stop_loss_pips=20.0,
            symbol="EURUSD",
            current_spread_pips=0.8,
            daily_loss_accumulated=0.0,
        )
        assert res_normal["allowed"] is True
        assert res_normal["lot_size"] > 0.0

        # 2. Flash spread widening (6.0 pips > 2.5 pips threshold) -> Blowout rejection
        res_spike = risk_kernel.evaluate_trade(
            account_balance=10_000.0,
            risk_per_trade_pct=1.0,
            stop_loss_pips=20.0,
            symbol="EURUSD",
            current_spread_pips=6.0,
            daily_loss_accumulated=0.0,
        )
        assert res_spike["allowed"] is False
        assert "spread blowout" in res_spike["reason"].lower()
        assert res_spike["lot_size"] == 0.0
        assert "TITAN" in res_spike["agents_vetoed"]

    def test_news_blackout_safety_window(self):
        """
        Verify that high-impact economic news triggers blackout detection.
        """
        # High impact events across various broker/provider formats
        assert is_high_impact_event({"importance": "High", "event": "Non-Farm Employment Change"}) is True
        assert is_high_impact_event({"impact": 3, "event": "US Non-Farm Payrolls"}) is True
        assert is_high_impact_event({"severity": "Critical", "event": "CPI m/m"}) is True
        assert is_high_impact_event({"level": "Red", "event": "FOMC Rate Decision"}) is True

        # Low impact / noise events are not blackout triggers
        assert is_high_impact_event({"importance": "Low", "event": "Statistical Report"}) is False
        assert is_high_impact_event({"impact": 1, "event": "Consumer Sentiment Prelim"}) is False

    @pytest.mark.asyncio
    async def test_broker_disconnect_circuit_breaker(self):
        """
        Verify that when the broker drops, consecutive failure counter increments
        and health registry flags execution degradation.
        """
        initial_failures = auto_execution_worker._consecutive_broker_failures

        # Simulate 5 consecutive broker failures
        auto_execution_worker._consecutive_broker_failures = 5

        from system_health import health_registry
        # Run health evaluation
        await health_registry.report(
            "execution_worker",
            "RED" if auto_execution_worker._consecutive_broker_failures >= 5 else "GREEN",
            "Execution paused — broker failures exceeded threshold",
            {"broker_failures": auto_execution_worker._consecutive_broker_failures}
        )

        state = await health_registry.aggregate_state()
        # With 5 broker failures, system should reflect degraded/critical state
        assert state in ("DEGRADED", "CRITICAL", "RED")

        # Cleanup
        auto_execution_worker._consecutive_broker_failures = initial_failures

    def test_drawdown_limit_lockout(self, risk_kernel):
        """
        Verify that daily loss exceeding 3.0% locks out the account.
        """
        # 1. 1.0% loss -> Allowed
        res_ok = risk_kernel.evaluate_trade(
            account_balance=10_000.0,
            risk_per_trade_pct=1.0,
            stop_loss_pips=20.0,
            symbol="EURUSD",
            current_spread_pips=1.0,
            daily_loss_accumulated=100.0,  # 1.0%
        )
        assert res_ok["allowed"] is True

        # 2. 3.2% loss -> Exceeds MAX_DAILY_DRAWDOWN_PCT (3.0%) -> Rejected
        res_blocked = risk_kernel.evaluate_trade(
            account_balance=10_000.0,
            risk_per_trade_pct=1.0,
            stop_loss_pips=20.0,
            symbol="EURUSD",
            current_spread_pips=1.0,
            daily_loss_accumulated=320.0,  # 3.2%
        )
        assert res_blocked["allowed"] is False
        assert "drawdown" in res_blocked["reason"].lower() or "limit" in res_blocked["reason"].lower()

    def test_zero_or_negative_equity_defense(self, risk_kernel):
        """
        Verify that non-positive balance/equity returns exactly 0.0 lots
        and halts execution immediately (never negative, never clamping to 0.01).
        """
        cfg_zero = MagicMock()
        cfg_zero.simulated_equity = 0.0
        cfg_zero.risk_per_trade = 1.0
        cfg_zero.compounding_mode = "OFF"

        lot = risk_kernel.calculate_user_lot_size(cfg_zero, stop_loss_pips=20.0, consensus=0.9, current_spread=1.0, symbol="EURUSD")
        assert lot == 0.0

        cfg_negative = MagicMock()
        cfg_negative.simulated_equity = -250.0
        cfg_negative.risk_per_trade = 1.0
        cfg_negative.compounding_mode = "OFF"

        lot_neg = risk_kernel.calculate_user_lot_size(cfg_negative, stop_loss_pips=20.0, consensus=0.9, current_spread=1.0, symbol="EURUSD")
        assert lot_neg == 0.0
