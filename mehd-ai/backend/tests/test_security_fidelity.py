"""
Mehd AI — Mathematical Security Fidelity Test Suite
===================================================
Tests cryptographic non-repudiation, tamper-evidence,
anti-replay timestamp validation, and deterministic threat defense.
"""

import time
import pytest
import hmac
import hashlib

from intent_capsule import (
    sign_vote,
    verify_all_capsules,
    IntentCapsule,
    _compute_signature,
    CAPSULE_MAX_AGE_SECONDS,
)
from security_guard import (
    verify_hmac_signature,
    sanitize_input_string,
    ThreatJail,
)


class TestIntentCapsuleFidelity:
    """Mathematical verification of AI vote non-repudiation and tamper protection."""

    def test_valid_capsule_verifies(self):
        capsule = sign_vote("CAESAR", "BUY", 88.5, "Strong bullish setup.")
        is_ok, reason = capsule.verify()
        assert is_ok is True
        assert reason == "VERIFIED"

    def test_tampered_direction_fails(self):
        """Flipping BUY to SELL breaks the HMAC digest with mathematical certainty."""
        capsule = sign_vote("CAESAR", "BUY", 88.5, "Strong bullish setup.")
        # Attempt to forge a modified capsule with identical signature
        forged = IntentCapsule(
            model_name=capsule.model_name,
            direction="SELL",  # Injected direction
            confidence=capsule.confidence,
            reasoning=capsule.reasoning,
            timestamp=capsule.timestamp,
            signature=capsule.signature,
        )
        is_ok, reason = forged.verify()
        assert is_ok is False
        assert "TAMPERED" in reason

    def test_tampered_confidence_fails(self):
        """Modifying confidence value breaks the signature."""
        capsule = sign_vote("SAGE", "SELL", 75.0, "Risk detected.")
        forged = IntentCapsule(
            model_name=capsule.model_name,
            direction=capsule.direction,
            confidence=99.9,  # Injected confidence
            reasoning=capsule.reasoning,
            timestamp=capsule.timestamp,
            signature=capsule.signature,
        )
        is_ok, reason = forged.verify()
        assert is_ok is False
        assert "TAMPERED" in reason

    def test_stale_capsule_fails(self):
        """Votes older than CAPSULE_MAX_AGE_SECONDS are rejected."""
        old_ts = time.time() - (CAPSULE_MAX_AGE_SECONDS + 10)
        sig = _compute_signature("TITAN", "BUY", 80.0, old_ts)
        stale_capsule = IntentCapsule(
            model_name="TITAN",
            direction="BUY",
            confidence=80.0,
            reasoning="Old vote.",
            timestamp=old_ts,
            signature=sig,
        )
        is_ok, reason = stale_capsule.verify()
        assert is_ok is False
        assert "STALE" in reason

    def test_batch_verify_all_capsules_blocks_on_single_breach(self):
        c1 = sign_vote("CIPHER", "BUY", 85.0, "Reason 1")
        c2 = sign_vote("PHANTOM", "BUY", 90.0, "Reason 2")
        bad_sig = IntentCapsule("ORACLE", "BUY", 80.0, "Reason 3", time.time(), "invalid_signature_hex")

        all_ok, failures = verify_all_capsules([c1, c2, bad_sig])
        assert all_ok is False
        assert len(failures) == 1
        assert "ORACLE" in failures[0]


class TestAntiReplayShieldFidelity:
    """Mathematical verification of HMAC anti-replay request validation."""

    def setup_method(self):
        self.secret = "test_super_secret_key_32_characters_long_min"
        self.payload = b'{"symbol": "EURUSD", "action": "BUY"}'

    def test_valid_request_signature_passes(self):
        now_str = str(time.time())
        msg = f"{now_str}.".encode("utf-8") + self.payload
        sig = hmac.new(self.secret.encode("utf-8"), msg, hashlib.sha256).hexdigest()

        assert verify_hmac_signature(self.payload, sig, now_str, self.secret, max_age_sec=30.0) is True

    def test_expired_timestamp_fails(self):
        """Request from 45 seconds ago fails anti-replay check."""
        expired_ts_str = str(time.time() - 45.0)
        msg = f"{expired_ts_str}.".encode("utf-8") + self.payload
        sig = hmac.new(self.secret.encode("utf-8"), msg, hashlib.sha256).hexdigest()

        assert verify_hmac_signature(self.payload, sig, expired_ts_str, self.secret, max_age_sec=30.0) is False

    def test_altered_payload_fails(self):
        """Altering the payload body with the same signature fails HMAC comparison."""
        now_str = str(time.time())
        msg = f"{now_str}.".encode("utf-8") + self.payload
        sig = hmac.new(self.secret.encode("utf-8"), msg, hashlib.sha256).hexdigest()

        tampered_payload = b'{"symbol": "EURUSD", "action": "SELL"}'
        assert verify_hmac_signature(tampered_payload, sig, now_str, self.secret, max_age_sec=30.0) is False


class TestInputSanitizerFidelity:
    """Mathematical determinism in SQL, XSS, and path traversal stripping."""

    def test_sql_injection_keywords_stripped(self):
        raw = "EURUSD'; DROP TABLE users; --"
        clean = sanitize_input_string(raw)
        assert "DROP" not in clean
        assert "TABLE" in clean
        assert "--" not in clean

    def test_xss_script_tags_stripped(self):
        raw = "<script>alert('pwned')</script>EURUSD"
        clean = sanitize_input_string(raw)
        assert "<script>" not in clean
        assert "</script>" not in clean
        assert "EURUSD" in clean

    def test_path_traversal_stripped(self):
        raw = "../../../etc/passwd"
        clean = sanitize_input_string(raw)
        assert ".." not in clean
        assert "etc/passwd" in clean
