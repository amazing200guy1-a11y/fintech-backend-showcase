"""
Mehd AI — Payment System Tests
=================================
Tests for the Paddle + Paystack dual-gateway payment integration.
Covers: tier config, tier management, signature verification,
legacy aliases, and pricing structure integrity.
"""

import hashlib
import hmac
import json
import pytest
from unittest.mock import patch, MagicMock, AsyncMock
import sys

# Mock firebase before imports
sys.modules['firebase_admin'] = MagicMock()
sys.modules['firebase_admin.firestore'] = MagicMock()

from routes.payments import (
    TIER_CONFIG,
    get_tier_config,
    get_user_tier,
    set_user_tier,
    _verify_paddle_signature,
    _verify_paystack_signature,
    _user_tiers,
    _LEGACY_TIER_ALIASES,
)


# ──────────────────────────────────────────────
#  Tier Configuration Tests
# ──────────────────────────────────────────────

class TestTierConfig:
    def test_all_tiers_exist(self):
        """All 4 tiers must be defined."""
        required = ["expired", "core", "precision", "institutional"]
        for tier in required:
            assert tier in TIER_CONFIG, f"Missing tier: {tier}"

    def test_no_legacy_tiers_in_config(self):
        """Legacy tier names must NOT exist as primary keys in TIER_CONFIG."""
        for legacy in ["scout", "guardian", "operative", "sovereign"]:
            assert legacy not in TIER_CONFIG, f"Legacy tier '{legacy}' should not be a primary key in TIER_CONFIG"

    def test_expired_is_free(self):
        config = TIER_CONFIG["expired"]
        assert config["price_monthly"] == 0

    def test_core_price_and_limits(self):
        config = TIER_CONFIG["core"]
        assert config["price_monthly"] == 79.0
        assert config["auto_execution"] == "assisted"

    def test_precision_price_and_limits(self):
        config = TIER_CONFIG["precision"]
        assert config["price_monthly"] == 149.0
        assert config["auto_execution"] in ("assisted", "full")

    def test_institutional_price_and_limits(self):
        config = TIER_CONFIG["institutional"]
        assert config["price_monthly"] == 299.0
        assert config["auto_execution"] == "full"

    def test_institutional_has_extra_features(self):
        """Institutional must have features that Core doesn't."""
        core = TIER_CONFIG["core"]
        institutional = TIER_CONFIG["institutional"]
        assert core["don_push_alerts"] is False
        assert institutional["don_push_alerts"] is True
        assert core["multi_account_sync"] is False
        assert institutional["multi_account_sync"] is True

    def test_all_tiers_get_full_11_agents(self):
        """CRITICAL: No tier should limit the number of agents.
        Every analysis = full 11 agents. Always."""
        for tier_name, config in TIER_CONFIG.items():
            assert "models_per_analysis" not in config, (
                f"Tier '{tier_name}' has 'models_per_analysis' — "
                f"this violates the core rule: every analysis uses ALL 11 agents"
            )


# ──────────────────────────────────────────────
#  Legacy Tier Alias Tests
# ──────────────────────────────────────────────

class TestLegacyAliases:
    def test_scout_resolves_to_expired(self):
        config = get_tier_config("scout")
        assert config == TIER_CONFIG["expired"]

    def test_guardian_resolves_to_core(self):
        config = get_tier_config("guardian")
        assert config == TIER_CONFIG["core"]

    def test_operative_resolves_to_institutional(self):
        config = get_tier_config("operative")
        assert config == TIER_CONFIG["institutional"]

    def test_unknown_tier_defaults_to_expired(self):
        config = get_tier_config("nonexistent_tier")
        assert config == TIER_CONFIG["expired"]

    def test_alias_map_exists(self):
        assert _LEGACY_TIER_ALIASES["scout"] == "expired"
        assert _LEGACY_TIER_ALIASES["guardian"] == "core"
        assert _LEGACY_TIER_ALIASES["operative"] == "institutional"


# ──────────────────────────────────────────────
#  Tier Management Tests
# ──────────────────────────────────────────────

class TestTierManagement:
    def setup_method(self):
        """Reset user tiers before each test."""
        _user_tiers.clear()

    def test_default_tier_is_observer(self):
        assert get_user_tier("new_user_123") == "observer"

    def test_set_tier(self):
        set_user_tier.__module__  # ensure loaded
        with patch.dict(sys.modules, {"storage": MagicMock()}):
            set_user_tier("user_1", "institutional")
        assert get_user_tier("user_1") == "institutional"

    def test_downgrade_to_observer(self):
        with patch.dict(sys.modules, {"storage": MagicMock()}):
            set_user_tier("user_2", "institutional")
            assert get_user_tier("user_2") == "institutional"
            set_user_tier("user_2", "observer")
            assert get_user_tier("user_2") == "observer"

    def test_get_tier_config_default(self):
        config = get_tier_config("nonexistent_tier")
        assert config == TIER_CONFIG["expired"]


# ──────────────────────────────────────────────
#  Paddle Signature Verification Tests
# ──────────────────────────────────────────────

class TestPaddleSignature:
    def _make_sig(self, secret: str, ts: int, body: str) -> str:
        signed = f"{ts}:{body}"
        h = hmac.new(secret.encode(), signed.encode(), hashlib.sha256).hexdigest()
        return f"ts={ts};h1={h}"

    def test_valid_signature_accepted(self):
        secret = "paddle_test_secret_123"
        ts = int(__import__('time').time())
        body = json.dumps({"event_type": "subscription.created"})
        sig = self._make_sig(secret, ts, body)
        with patch("routes.payments.PADDLE_WEBHOOK_SECRET", secret):
            assert _verify_paddle_signature(body.encode(), sig) is True

    def test_invalid_signature_rejected(self):
        secret = "paddle_test_secret_123"
        ts = int(__import__('time').time())
        body = json.dumps({"event_type": "subscription.created"})
        with patch("routes.payments.PADDLE_WEBHOOK_SECRET", secret):
            assert _verify_paddle_signature(body.encode(), "ts={ts};h1=bad_sig") is False

    def test_missing_secret_rejected(self):
        body = b'{"event_type": "subscription.created"}'
        with patch("routes.payments.PADDLE_WEBHOOK_SECRET", ""):
            assert _verify_paddle_signature(body, "ts=1;h1=anything") is False

    def test_old_timestamp_rejected(self):
        """Replay attack guard: events older than 5 minutes are rejected."""
        secret = "paddle_test_secret_123"
        old_ts = int(__import__('time').time()) - 400  # 6+ minutes old
        body = json.dumps({"event_type": "subscription.created"})
        sig = self._make_sig(secret, old_ts, body)
        with patch("routes.payments.PADDLE_WEBHOOK_SECRET", secret):
            assert _verify_paddle_signature(body.encode(), sig) is False


# ──────────────────────────────────────────────
#  Paystack Signature Verification Tests
# ──────────────────────────────────────────────

class TestPaystackSignature:
    def _make_sig(self, secret: str, body: bytes) -> str:
        return hmac.new(secret.encode(), body, hashlib.sha512).hexdigest()

    def test_valid_signature_accepted(self):
        secret = "sk_test_paystack_123"
        body = json.dumps({"event": "subscription.create"}).encode()
        sig = self._make_sig(secret, body)
        with patch("routes.payments.PAYSTACK_SECRET_KEY", secret):
            assert _verify_paystack_signature(body, sig) is True

    def test_invalid_signature_rejected(self):
        secret = "sk_test_paystack_123"
        body = json.dumps({"event": "subscription.create"}).encode()
        with patch("routes.payments.PAYSTACK_SECRET_KEY", secret):
            assert _verify_paystack_signature(body, "bad_signature") is False

    def test_missing_secret_rejected(self):
        body = b'{"event": "subscription.create"}'
        with patch("routes.payments.PAYSTACK_SECRET_KEY", ""):
            assert _verify_paystack_signature(body, "anything") is False

    def test_tampered_body_rejected(self):
        secret = "sk_test_paystack_123"
        original_body = json.dumps({"event": "subscription.create", "tier": "core"}).encode()
        tampered_body = json.dumps({"event": "subscription.create", "tier": "institutional"}).encode()
        sig = self._make_sig(secret, original_body)
        with patch("routes.payments.PAYSTACK_SECRET_KEY", secret):
            assert _verify_paystack_signature(tampered_body, sig) is False


# ──────────────────────────────────────────────
#  Price Integrity Tests
# ──────────────────────────────────────────────

class TestPriceIntegrity:
    def test_tiers_ordered_by_price(self):
        """Higher tiers must cost more (or equal)."""
        prices = [
            TIER_CONFIG["expired"]["price_monthly"],
            TIER_CONFIG["core"]["price_monthly"],
            TIER_CONFIG["precision"]["price_monthly"],
            TIER_CONFIG["institutional"]["price_monthly"],
        ]
        for i in range(len(prices) - 1):
            assert prices[i] <= prices[i + 1], (
                f"Tier price ordering broken: {prices[i]} > {prices[i+1]}"
            )
