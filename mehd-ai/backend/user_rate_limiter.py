"""
Day 12 — Per-User UID + Per-IP Adaptive Rate Limiter

Enforces strict rate limits by both IP address and User UID to prevent API scraping.
"""
import time
from typing import Dict, Tuple

_user_token_buckets: Dict[str, Tuple[float, int]] = {}

class UserRateLimiter:
    """Token-bucket rate limiter per UID/IP."""

    @classmethod
    def check_rate_limit(cls, identifier: str, max_requests: int = 60, window_seconds: int = 60) -> Tuple[bool, int]:
        """
        Returns (is_allowed, remaining_requests).
        """
        now = time.time()
        last_reset, current_count = _user_token_buckets.get(identifier, (now, 0))

        if now - last_reset >= window_seconds:
            last_reset = now
            current_count = 0

        if current_count >= max_requests:
            return False, 0

        _user_token_buckets[identifier] = (last_reset, current_count + 1)
        remaining = max_requests - (current_count + 1)
        return True, remaining
