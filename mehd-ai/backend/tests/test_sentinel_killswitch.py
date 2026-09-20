"""
Mehd AI — Sentinel Kill-Switch and Economic News Blackout Tests
===============================================================
Tests the ultimate defensive perimeters:
  1. Manual Panic Button trigger and reset.
  2. News Heartbeat timeout with boot grace period.
  3. Latency spike circuit breaker.
  4. Symbol-aware broker anti-manipulation discrepancy gate.
  5. Economic Calendar hardcoded schedule and news blackout detection.
"""

import time
import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import patch

from hardened_kill_switch import HardenedKillSwitch, _get_max_discrepancy_pips
from economic_calendar import (
    EconomicCalendarGateway,
    _get_affected_currencies,
    _get_first_friday,
    normalize_event_currency,
    is_high_impact_event,
)


class TestHardenedKillSwitch:
    def test_panic_button_lifecycle(self):
        ks = HardenedKillSwitch()
        res = ks.evaluate_pre_execution_safety("EURUSD", 1.0850, 1.0850, 0.0001)
        assert res["status"] == "OK"

        # Trigger Panic
        halt_res = ks.trigger_panic_button("SENTINEL_ADMIN")
        assert halt_res["status"] == "HALTED"

        eval_halt = ks.evaluate_pre_execution_safety("EURUSD", 1.0850, 1.0850, 0.0001)
        assert eval_halt["status"] == "HALT"
        assert "MANUAL_PANIC_BUTTON_ACTIVE" in eval_halt["reason"]

        # Reset Panic
        ks.reset_panic_button()
        res_after = ks.evaluate_pre_execution_safety("EURUSD", 1.0850, 1.0850, 0.0001)
        assert res_after["status"] == "OK"

    def test_execution_latency_spike(self):
        ks = HardenedKillSwitch()
        # Below 100ms latency is safe
        res_ok = ks.evaluate_pre_execution_safety("EURUSD", 1.0850, 1.0850, 0.0001, execution_latency_ms=45.0)
        assert res_ok["status"] == "OK"

        # Over 100ms triggers HALT
        res_halt = ks.evaluate_pre_execution_safety("EURUSD", 1.0850, 1.0850, 0.0001, execution_latency_ms=125.0)
        assert res_halt["status"] == "HALT"
        assert "LATENCY_SPIKE" in res_halt["reason"]

    def test_symbol_aware_discrepancy_thresholds(self):
        assert _get_max_discrepancy_pips("EURUSD") == 5.0
        assert _get_max_discrepancy_pips("GBPUSD") == 5.0
        assert _get_max_discrepancy_pips("XAUUSD") == 25.0
        assert _get_max_discrepancy_pips("XAGUSD") == 25.0
        assert _get_max_discrepancy_pips("BTCUSD") == 50.0
        assert _get_max_discrepancy_pips("NAS100") == 15.0

    def test_forex_manipulation_discrepancy_halt(self):
        ks = HardenedKillSwitch()
        # 6 pips difference on EURUSD (limit is 5.0)
        res = ks.evaluate_pre_execution_safety("EURUSD", 1.0856, 1.0850, 0.0001)
        assert res["status"] == "HALT"
        assert "BROKER_MANIPULATION_DETECTED" in res["reason"]

    def test_gold_discrepancy_allowance(self):
        ks = HardenedKillSwitch()
        # 10 cents ($0.10) difference on XAUUSD is 10 pips (pip_size=0.01)
        # Gold limit is 25.0 pips, so 10 pips must PASS
        res = ks.evaluate_pre_execution_safety("XAUUSD", 2350.10, 2350.00, 0.01)
        assert res["status"] == "OK"

        # 30 cents ($0.30) difference is 30 pips -> exceeds 25.0 pips -> HALT
        res_halt = ks.evaluate_pre_execution_safety("XAUUSD", 2350.30, 2350.00, 0.01)
        assert res_halt["status"] == "HALT"

    def test_news_heartbeat_timeout(self):
        ks = HardenedKillSwitch()
        # Simulate boot 600 seconds ago and heartbeat 40 seconds ago (timeout is 30s)
        ks._boot_time = time.time() - 600.0
        ks._last_news_heartbeat = time.time() - 40.0
        res = ks.evaluate_pre_execution_safety("EURUSD", 1.0850, 1.0850, 0.0001)
        assert res["status"] == "HALT"
        assert "NEWS_FILTER_HEARTBEAT_TIMEOUT" in res["reason"]

        # Record heartbeat
        ks.record_news_heartbeat()
        res_ok = ks.evaluate_pre_execution_safety("EURUSD", 1.0850, 1.0850, 0.0001)
        assert res_ok["status"] == "OK"


class TestEconomicCalendar:
    def test_affected_currencies_extraction(self):
        assert "USD" in _get_affected_currencies("EURUSD")
        assert "EUR" in _get_affected_currencies("EURUSD")
        assert "XAU" in _get_affected_currencies("XAUUSD")
        assert "BTC" in _get_affected_currencies("BTCUSD")
        assert "NAS" in _get_affected_currencies("NAS100")

    def test_first_friday_algorithm(self):
        # Jan 2026: Jan 1 is Thursday, Jan 2 is first Friday
        assert _get_first_friday(2026, 1) == 2
        # Feb 2026: Feb 1 is Sunday, Feb 6 is first Friday
        assert _get_first_friday(2026, 2) == 6

    def test_currency_normalization_polyfill(self):
        assert normalize_event_currency({"country": "United States"}) == "USD"
        assert normalize_event_currency({"country": "Germany"}) == "EUR"
        assert normalize_event_currency({"headline": "Fed Interest Rate Decision"}) == "USD"
        assert normalize_event_currency({"headline": "ECB Press Conference"}) == "EUR"

    def test_high_impact_event_classification(self):
        assert is_high_impact_event({"impact": "High"}) is True
        assert is_high_impact_event({"importance": "Critical"}) is True
        assert is_high_impact_event({"severity": "3"}) is True
        assert is_high_impact_event({"impact": "Low"}) is False
