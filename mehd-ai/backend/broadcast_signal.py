from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional, Any
from dataclasses import dataclass, field

from models import ConsensusResult, MarketSnapshot

logger = logging.getLogger("mehd.broadcaster")


def _safe_create_task(coro, name: str = "unnamed"):
    """Fire-and-forget wrapper that logs errors instead of silently swallowing them."""
    async def _wrapper():
        try:
            await coro
        except Exception as e:
            logger.error("Background task '%s' failed: %s", name, e)
    return asyncio.create_task(_wrapper())


# Pairs the Broadcaster monitors — synced with Flutter's AppConstants.symbols
BROADCAST_PAIRS = [
    "EUR/USD", "GBP/USD", "AUD/USD", "USD/JPY", "USD/CAD", "XAU/USD",
    "USD/CHF", "NZD/USD", "EUR/GBP", "EUR/JPY", "GBP/JPY",
    "USD/ZAR", "XAG/USD", "BTC/USD", "NAS100",
]

CYCLE_INTERVAL_SECONDS = 300
MIN_PAIR_INTERVAL_SECONDS = 30
BROADCAST_HISTORY_SIZE = 50
FREE_TIER_DELAY_SECONDS = 900  # 15 minutes


@dataclass
class BroadcastSignal:
    """A single broadcast: one pair, one consensus, one moment in time."""
    symbol: str
    consensus: ConsensusResult
    snapshot: MarketSnapshot
    broadcast_time: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    cycle_id: int = 0
    analysis_duration_ms: int = 0
    status: str = "FRESH"

    def to_notification(self) -> dict:
        """Converts to a push notification payload."""
        direction = self.consensus.final_direction.value
        pct = self.consensus.consensus_percentage
        emoji = "🟢" if direction == "BUY" else "🔴" if direction == "SELL" else "⚪"

        if pct < 92:
            return None  # Don't spam users with weak signals

        return {
            "title": f"{emoji} {self.symbol} — {direction} Signal",
            "body": (
                f"The Den reached {pct:.0f}% consensus. "
                f"11 AI agents analyzed the market."
            ),
            "data": {
                "symbol": self.symbol,
                "direction": direction,
                "consensus_pct": pct,
                "proceed": self.consensus.proceed,
                "timestamp": self.broadcast_time.isoformat(),
                "cycle_id": self.cycle_id,
                "chairman_summary": self.consensus.chairman_summary or "",
            },
        }

    def to_dict(self) -> dict:
        """Serializable summary for API responses."""
        import json
        return {
            "symbol": self.symbol,
            "direction": self.consensus.final_direction.value,
            "consensus_pct": self.consensus.consensus_percentage,
            "proceed": self.consensus.proceed,
            "chairman_summary": self.consensus.chairman_summary,
            "rejection_reason": self.consensus.rejection_reason,
            "vote_count": len(self.consensus.votes),
            "consensus_data": json.loads(self.consensus.model_dump_json()),
            "snapshot": {
                "bid": self.snapshot.bid,
                "ask": self.snapshot.ask,
                "spread": self.snapshot.spread,
                "data_source": self.snapshot.data_source,
                "is_live": self.snapshot.is_live,
            },
            "broadcast_time": self.broadcast_time.isoformat(),
            "analysis_duration_ms": self.analysis_duration_ms,
            "status": self.status,
        }
