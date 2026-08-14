"""
Mehd AI — WebSocket Dual-Task Signal Manager Tests
====================================================
Tests the Dual-Task ConnectionManager, non-blocking broadcast,
and queue backpressure eviction policy.
"""

import pytest
import asyncio
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from routes.websocket_signals import ConnectionManager


class MockWebSocket:
    """Mock WebSocket for unit testing."""
    def __init__(self):
        self.accepted = False
        self.closed = False
        self.sent_messages = []

    async def accept(self):
        self.accepted = True

    async def send_json(self, data):
        self.sent_messages.append(data)

    async def close(self):
        self.closed = True


@pytest.fixture
def anyio_backend():
    return 'asyncio'


@pytest.mark.asyncio
async def test_connection_manager_connect_disconnect():
    """Verify that clients can connect and disconnect cleanly."""
    manager = ConnectionManager(queue_maxsize=10)
    ws = MockWebSocket()

    q = await manager.connect(ws)
    assert ws.accepted is True
    assert manager.client_count == 1
    assert q.maxsize == 10

    await manager.disconnect(ws)
    assert manager.client_count == 0


@pytest.mark.asyncio
async def test_connection_manager_broadcast_non_blocking():
    """Verify non-blocking put_nowait delivery to all connected clients."""
    manager = ConnectionManager(queue_maxsize=10)
    ws1 = MockWebSocket()
    ws2 = MockWebSocket()

    q1 = await manager.connect(ws1)
    q2 = await manager.connect(ws2)

    signal = {"symbol": "EUR/USD", "direction": "BUY", "consensus": 95.0}
    delivered = manager.broadcast_signal(signal)

    assert delivered == 2
    assert q1.qsize() == 1
    assert q2.qsize() == 1

    msg1 = q1.get_nowait()
    assert msg1["symbol"] == "EUR/USD"
    assert msg1["consensus"] == 95.0

    await manager.disconnect(ws1)
    await manager.disconnect(ws2)


@pytest.mark.asyncio
async def test_connection_manager_backpressure_drop_oldest():
    """
    Verify backpressure strategy:
    When queue is full (maxsize=3 for test), the oldest frame is dropped
    and the newest 99% signal is inserted without blocking.
    """
    manager = ConnectionManager(queue_maxsize=3)
    ws = MockWebSocket()
    q = await manager.connect(ws)

    # Fill queue with 3 older signals
    manager.broadcast_signal({"id": 1, "data": "old_1"})
    manager.broadcast_signal({"id": 2, "data": "old_2"})
    manager.broadcast_signal({"id": 3, "data": "old_3"})
    assert q.full()

    # Broadcast 4th (fresh) signal — should drop id=1 and accept id=4
    delivered = manager.broadcast_signal({"id": 4, "data": "fresh_4"})
    assert delivered == 1
    assert q.qsize() == 3

    # Verify order: id=2, id=3, id=4 (id=1 was safely evicted)
    first = q.get_nowait()
    assert first["id"] == 2
    second = q.get_nowait()
    assert second["id"] == 3
    third = q.get_nowait()
    assert third["id"] == 4

    await manager.disconnect(ws)
