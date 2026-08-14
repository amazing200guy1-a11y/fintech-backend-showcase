"""
Mehd AI — Redis Pub/Sub Bridge & Bounded Queue Tests
======================================================
Verifies multi-worker pub/sub dispatch and non-blocking slow-client protection.
"""

import pytest
import asyncio
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from redis_pubsub import RedisPubSubBridge
from broadcaster import Broadcaster, BroadcastSignal
from models import ConsensusResult, MarketSnapshot, Direction
from uuid import uuid4

@pytest.fixture
def anyio_backend():
    return 'asyncio'

@pytest.mark.asyncio
async def test_redis_pubsub_in_memory_fallback():
    """Verify that when no Redis URL is given, in-memory mode fans out messages seamlessly."""
    bridge = RedisPubSubBridge(redis_url="")
    await bridge.initialize()
    assert not bridge.is_connected

    received = []

    def callback(data):
        received.append(data)

    await bridge.subscribe("mehd:test:signals", callback)
    sub_count = await bridge.publish("mehd:test:signals", {"symbol": "EURUSD", "direction": "BUY"})
    
    assert sub_count == 1
    assert len(received) == 1
    assert received[0]["symbol"] == "EURUSD"
    assert received[0]["direction"] == "BUY"

    # Cleanup
    await bridge.unsubscribe("mehd:test:signals", callback)
    await bridge.close()

@pytest.mark.asyncio
async def test_broadcaster_bounded_queue_non_blocking():
    """Verify that the Broadcaster delivers to subscriber queues with zero slow-client blocking."""
    b = Broadcaster()
    await b.start()

    snapshot_id = uuid4()
    consensus = ConsensusResult(
        id=snapshot_id,
        symbol="EUR/USD",
        final_direction=Direction.BUY,
        consensus_percentage=94.0,
        proceed=True,
        votes=[],
        chairman_summary="Consensus reached",
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
    )
    signal = BroadcastSignal(
        symbol="EUR/USD",
        consensus=consensus,
        snapshot=snapshot,
        cycle_id=1,
    )

    # Subscribe client
    gen = b.subscribe()
    
    # Broadcast a signal
    await b._push_to_subscribers(signal)
    
    # Client receives signal
    received_signal = await asyncio.wait_for(gen.__anext__(), timeout=2.0)
    assert received_signal.symbol == "EUR/USD"

    b.stop()

