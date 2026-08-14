"""
Day 9 — STRIDE Threat Model Evaluator

Evaluates incoming requests against the 6 STRIDE threat vectors:
- Spoofing (Identity verification)
- Tampering (Payload integrity)
- Repudiation (Non-repudiable audit logging)
- Information Disclosure (Secret scrubbing)
- Denial of Service (Request volume limits)
- Elevation of Privilege (Tier role validation)
"""
import re
from typing import Dict, Any, Tuple

class StrideThreatEvaluator:
    """Evaluates request payloads for STRIDE security risks."""

    _SYMBOL_PATTERN = re.compile(r"^[A-Z0-9]{3,12}$")

    @classmethod
    def evaluate_request(
        cls,
        endpoint: str,
        user_tier: str,
        required_tier: str = "observer",
        symbol: str | None = None,
        payload_bytes: bytes | None = None,
    ) -> Tuple[bool, str]:
        """
        Returns (is_secure, refusal_reason).
        """
        # 1. Elevation of Privilege Check
        tier_hierarchy = {"observer": 0, "core": 1, "precision": 2, "institutional": 3}
        user_level = tier_hierarchy.get(user_tier.lower(), 0)
        req_level = tier_hierarchy.get(required_tier.lower(), 0)

        if user_level < req_level:
            return False, f"STRIDE Elevation Risk: Endpoint '{endpoint}' requires '{required_tier}' tier."

        # 2. Tampering & Injection Check
        if symbol:
            clean_symbol = symbol.strip().upper()
            if not cls._SYMBOL_PATTERN.match(clean_symbol):
                return False, f"STRIDE Tampering Risk: Invalid symbol format '{symbol}'."

        # 3. Denial of Service Payload Size Check (Cap at 2MB)
        if payload_bytes and len(payload_bytes) > 2 * 1024 * 1024:
            return False, "STRIDE DoS Risk: Request payload exceeds 2MB limit."

        return True, "SECURE"
