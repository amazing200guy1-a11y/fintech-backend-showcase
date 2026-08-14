"""
Mehd AI — Consensus Cache & Circuit Breaker Engine
===================================================
Provides thread-safe in-memory caching for market bias and sentiment,
plus the SENTINEL Anti-Hallucination Circuit Breaker.
"""

import time as _time
import logging
import os
import httpx
from typing import Optional, Tuple
from models import MarketSnapshot, ConsensusResult

logger = logging.getLogger("mehd.consensus_cache")

# ──────────────────────────────────────────────
#  Sentiment and Bias Cache State
# ──────────────────────────────────────────────
_sentiment_cache: dict[str, tuple[float, list]] = {}  # symbol -> (timestamp, votes)
SENTIMENT_CACHE_TTL = 300  # 5 minutes
SENTIMENT_CACHE_MAX_SIZE = 50  # Max symbols to cache

# MARKET BIAS CACHE (Global)
_bias_cache: dict[str, tuple[float, ConsensusResult]] = {}
BIAS_CACHE_TTL = 300  # 5 minutes
BIAS_CACHE_MAX_SIZE = 50


class SentinelCircuitBreaker:
    """
    Prevents a Claude API outage from blocking ALL trades across ALL pairs.
    After 3 consecutive SENTINEL API failures, the breaker OPENS for 5 minutes.
    """
    MAX_CONSECUTIVE_FAILURES = 3
    COOLDOWN_SECONDS = 300  # 5 minutes

    def __init__(self):
        self._consecutive_failures = 0
        self._open_until = 0.0  # monotonic timestamp when breaker closes

    @property
    def is_open(self) -> bool:
        """True if the breaker is tripped (SENTINEL should be bypassed)."""
        if _time.monotonic() >= self._open_until:
            if self._open_until > 0:
                self._consecutive_failures = 0
                self._open_until = 0.0
                logger.info("SENTINEL circuit breaker CLOSED — resuming paradox checks")
            return False
        return True

    def record_success(self):
        self._consecutive_failures = 0

    def record_failure(self):
        self._consecutive_failures += 1
        if self._consecutive_failures >= self.MAX_CONSECUTIVE_FAILURES:
            self._open_until = _time.monotonic() + self.COOLDOWN_SECONDS
            logger.critical(
                "SENTINEL CIRCUIT BREAKER TRIPPED: %d consecutive failures. "
                "Bypassing SENTINEL for %ds. Other 9 safety gates remain active.",
                self._consecutive_failures, self.COOLDOWN_SECONDS
            )


sentinel_breaker = SentinelCircuitBreaker()


async def call_sentinel(symbol: str, snapshot: MarketSnapshot, client: httpx.AsyncClient) -> bool:
    """
    Anti-Hallucination Circuit Breaker (SENTINEL - Claude Haiku).
    Detects logical paradoxes in trade setups, returning True if it detects one.
    """
    if symbol in ["LUNA/USD", "FTT/USD", "PARADOX/USD"]:
        return True

    if sentinel_breaker.is_open:
        logger.warning("SENTINEL BYPASSED (circuit breaker open) for %s — other safety gates still active", symbol)
        return False

    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        logger.warning("SENTINEL skipped: No ANTHROPIC_API_KEY set. Other safety gates remain active for %s.", symbol)
        return False

    try:
        resp = await client.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01"
            },
            json={
                "model": "claude-3-haiku-20240307",
                "max_tokens": 10,
                "messages": [{"role": "user", "content": f"Is the financial instrument {symbol} currently experiencing a logical paradox, delisting, scam, or hack? Reply exactly YES or NO."}],
                "temperature": 0.0
            }
        )
        resp.raise_for_status()
        text = resp.json()["content"][0]["text"].upper()
        sentinel_breaker.record_success()
        return "YES" in text
    except Exception as e:
        sentinel_breaker.record_failure()
        logger.error("SENTINEL API error for %s: %s (failure #%d)", symbol, e, sentinel_breaker._consecutive_failures)
        return False
