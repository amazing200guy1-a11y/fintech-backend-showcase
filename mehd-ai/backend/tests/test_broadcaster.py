"""
Mehd AI — Broadcaster Tests
==============================
Proves the broadcast system works correctly.
Run with: python -m pytest tests/test_broadcaster.py -v
"""

import pytest
import asyncio
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from broadcaster import Broadcaster, BroadcastSignal, BROADCAST_PAIRS
from models import ConsensusResult, MarketSnapshot, Direction, AIVote
from uuid import uuid4
from datetime import datetime, timezone


# ──────────────────────────────────────────────
#  FIXTURES
# ──────────────────────────────────────────────

@pytest.fixture
def anyio_backend():
    return 'asyncio'


@pytest.fixture
def broadcaster_instance():
    return Broadcaster()


@pytest.fixture
def mock_signal():
    """Create a realistic broadcast signal for testing."""
    snapshot_id = uuid4()
    votes = [
        AIVote(
            model_name="PHANTOM",
            snapshot_id=snapshot_id,
            direction=Direction.BUY,
            confidence=85.0,
            reasoning="Bullish sentiment detected.",
        ),
        AIVote(
            model_name="TITAN",
            snapshot_id=snapshot_id,
            direction=Direction.BUY,
            confidence=78.0,
            reasoning="Math confirms momentum.",
        ),
    ]

    consensus = ConsensusResult(
        id=snapshot_id,
        symbol="EUR/USD",
        final_direction=Direction.BUY,
        consensus_percentage=93.0,  # Above the 92% notification threshold
        proceed=True,
        votes=votes,
        chairman_summary="The Den confirms bullish momentum.",
        data_purity_score=100.0,
    )

    snapshot = MarketSnapshot(
        id=snapshot_id,
        symbol="EUR/USD",
        bid=1.0850,
        ask=1.0852,
        open=1.0830,
        high=1.0880,
        low=1.0820,
        close=1.0850,
        spread=0.2,
        volume=0,
        data_source="test",
        is_live=False,
    )

    return BroadcastSignal(
        symbol="EUR/USD",
        consensus=consensus,
        snapshot=snapshot,
        cycle_id=1,
        analysis_duration_ms=5000,
    )


# ──────────────────────────────────────────────
#  TEST 1: Broadcast Store
# ──────────────────────────────────────────────

class TestBroadcastStore:
    """The broadcast store must correctly track latest signals per pair."""

    def test_empty_on_start(self, broadcaster_instance):
        """No signals before daemon starts."""
        assert broadcaster_instance.get_all_latest() == {}

    def test_get_latest_returns_signal(self, broadcaster_instance, mock_signal):
        """After storing a signal, it should be retrievable."""
        broadcaster_instance._latest["EUR/USD"] = mock_signal
        latest = broadcaster_instance.get_latest("EUR/USD")
        assert latest is not None
        assert latest.symbol == "EUR/USD"
        assert latest.consensus.final_direction == Direction.BUY

    def test_get_latest_unknown_pair(self, broadcaster_instance):
        """Unknown pair should return None, not crash."""
        result = broadcaster_instance.get_latest("FAKE/PAIR")
        assert result is None

    def test_get_all_latest_returns_all(self, broadcaster_instance, mock_signal):
        """Should return dicts for all stored pairs."""
        broadcaster_instance._latest["EUR/USD"] = mock_signal
        all_latest = broadcaster_instance.get_all_latest()
        assert "EUR/USD" in all_latest
        assert all_latest["EUR/USD"]["direction"] == "BUY"


# ──────────────────────────────────────────────
#  TEST 2: Notification Generation
# ──────────────────────────────────────────────

class TestNotifications:
    """Push notifications must only fire for strong signals."""

    def test_strong_signal_generates_notification(self, mock_signal):
        """93% consensus should generate a notification (threshold is 92%)."""
        notif = mock_signal.to_notification()
        assert notif is not None
        assert "EUR/USD" in notif["title"]
        assert "BUY" in notif["title"]
        assert "93%" in notif["body"]

    def test_weak_signal_suppressed(self, mock_signal):
        """Below 70% consensus should NOT generate a notification."""
        mock_signal.consensus.consensus_percentage = 55.0
        notif = mock_signal.to_notification()
        assert notif is None  # Don't spam users

    def test_notification_data_complete(self, mock_signal):
        """Notification data payload must have all required fields."""
        notif = mock_signal.to_notification()
        assert "data" in notif
        assert "symbol" in notif["data"]
        assert "direction" in notif["data"]
        assert "consensus_pct" in notif["data"]
        assert "timestamp" in notif["data"]


# ──────────────────────────────────────────────
#  TEST 3: History Tracking
# ──────────────────────────────────────────────

class TestHistory:
    """Broadcast history must be bounded and ordered."""

    def test_history_empty_on_start(self, broadcaster_instance):
        """No history before any broadcasts."""
        history = broadcaster_instance.get_history("EUR/USD")
        assert history == []

    def test_history_appends(self, broadcaster_instance, mock_signal):
        """Each broadcast should append to history."""
        broadcaster_instance._history["EUR/USD"].append(mock_signal)
        history = broadcaster_instance.get_history("EUR/USD")
        assert len(history) == 1

    def test_history_limit_respected(self, broadcaster_instance, mock_signal):
        """Requesting limited history should return at most that many."""
        for i in range(10):
            broadcaster_instance._history["EUR/USD"].append(mock_signal)
        history = broadcaster_instance.get_history("EUR/USD", limit=3)
        assert len(history) == 3


# ──────────────────────────────────────────────
#  TEST 4: Configuration
# ──────────────────────────────────────────────

class TestConfiguration:
    """Broadcast configuration sanity checks."""

    def test_fifteen_pairs_monitored(self):
        """Must monitor all 15 institutional pairs."""
        assert len(BROADCAST_PAIRS) == 15
        assert "EUR/USD" in BROADCAST_PAIRS
        assert "XAU/USD" in BROADCAST_PAIRS

    def test_status_structure(self, broadcaster_instance):
        """Status must return all required fields."""
        status = broadcaster_instance.get_status()
        assert "running" in status
        assert "cycle_count" in status
        assert "total_broadcasts" in status
        assert "pairs_monitored" in status
        assert status["pairs_monitored"] == 15


# ──────────────────────────────────────────────
#  TEST 5: Subscriber Management
# ──────────────────────────────────────────────

class TestSubscribers:
    """SSE subscriber management."""

    @pytest.mark.anyio
    async def test_subscribe_returns_generator(self, broadcaster_instance):
        """subscribe() should be an async generator."""
        import types
        gen = broadcaster_instance.subscribe()
        assert isinstance(gen, types.AsyncGeneratorType)

    @pytest.mark.anyio
    async def test_subscribe_delayed_returns_generator(self, broadcaster_instance):
        """subscribe_delayed() should be an async generator."""
        import types
        gen = broadcaster_instance.subscribe_delayed()
        assert isinstance(gen, types.AsyncGeneratorType)
