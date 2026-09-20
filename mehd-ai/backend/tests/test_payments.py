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
    check_broker_trial_eligibility,
    bind_broker_trial_account,
    _get_trial_info,
    activate_trial,
    FREE_TRIAL_DAYS,
    FREE_TRIAL_TIER,
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

    def test_default_tier_is_expired(self):
        # Mehd AI has NO free tier. A brand new unknown user is "expired"
        # until they start their 3-day Institutional free trial via Paddle/Paystack.
        assert get_user_tier("new_user_123") == "expired"

    def test_set_tier(self):
        set_user_tier.__module__  # ensure loaded
        with patch.dict(sys.modules, {"storage": MagicMock()}):
            set_user_tier("user_1", "institutional")
        assert get_user_tier("user_1") == "institutional"

    def test_downgrade_to_expired(self):
        # "observer" is a legacy alias for "expired" — no free tier exists.
        with patch.dict(sys.modules, {"storage": MagicMock()}):
            set_user_tier("user_2", "institutional")
            assert get_user_tier("user_2") == "institutional"
            set_user_tier("user_2", "observer")   # legacy alias input
            assert get_user_tier("user_2") == "expired"  # resolves to expired

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


# ──────────────────────────────────────────────
#  Broker Trial Fingerprinting Tests
# ──────────────────────────────────────────────

class TestBrokerTrialFingerprint:
    @pytest.mark.asyncio
    async def test_fresh_broker_account_is_eligible(self):
        with patch("storage.storage.get", new_callable=AsyncMock) as mock_get:
            mock_get.return_value = None
            eligible = await check_broker_trial_eligibility("MT5-998877", "uid_user_1")
            assert eligible is True

    @pytest.mark.asyncio
    async def test_same_user_is_eligible(self):
        with patch("storage.storage.get", new_callable=AsyncMock) as mock_get:
            mock_get.return_value = {"uid": "uid_user_1", "activated_at": "2026-08-30T10:00:00"}
            eligible = await check_broker_trial_eligibility("998877", "uid_user_1")
            assert eligible is True

    @pytest.mark.asyncio
    async def test_recycled_broker_on_different_user_is_blocked(self):
        with patch("storage.storage.get", new_callable=AsyncMock) as mock_get:
            mock_get.return_value = {"uid": "uid_user_1", "activated_at": "2026-08-30T10:00:00"}
            eligible = await check_broker_trial_eligibility("998877", "uid_burner_attacker_2")
            assert eligible is False

    @pytest.mark.asyncio
    async def test_bind_broker_burns_account_in_storage(self):
        with patch("storage.storage.set", new_callable=AsyncMock) as mock_set:
            await bind_broker_trial_account("MT5-123456", "uid_user_1")
            mock_set.assert_called_once()
            args = mock_set.call_args[0]
            assert args[0] == "broker_trials"
            assert args[1] == "mt5123456"
            assert args[2]["uid"] == "uid_user_1"


# ──────────────────────────────────────────────
#  Active Market Days Free Trial Tests
# ──────────────────────────────────────────────

class TestActiveMarketDaysTrial:
    @pytest.mark.asyncio
    async def test_weekend_activation_pauses_trial(self):
        """If user activates on Saturday, 0 active days are deducted and trial is active with is_weekend_paused=True."""
        from datetime import datetime, timezone
        # 2026-08-29 is Saturday
        saturday = datetime(2026, 8, 29, 14, 0, 0, tzinfo=timezone.utc)
        with patch("routes.payments.datetime") as mock_dt, \
             patch("storage.storage.get", new_callable=AsyncMock) as mock_get, \
             patch("storage.storage.set", new_callable=AsyncMock) as mock_set:
            mock_dt.now.return_value = saturday
            mock_dt.fromisoformat.side_effect = datetime.fromisoformat
            mock_get.return_value = None

            res = await activate_trial("uid_weekend_1", "+1234567890", "127_0_0_1")
            assert res["is_active"] is True
            assert res["is_weekend_paused"] is True
            assert res["days_remaining"] == 3
            assert res["days_used"] == 0

    @pytest.mark.asyncio
    async def test_weekday_activation_consumes_one_day(self):
        """If user activates on Tuesday, 1 active day is deducted and 2 remain."""
        from datetime import datetime, timezone
        # 2026-09-01 is Tuesday
        tuesday = datetime(2026, 9, 1, 10, 0, 0, tzinfo=timezone.utc)
        with patch("routes.payments.datetime") as mock_dt, \
             patch("storage.storage.get", new_callable=AsyncMock) as mock_get, \
             patch("storage.storage.set", new_callable=AsyncMock) as mock_set:
            mock_dt.now.return_value = tuesday
            mock_dt.fromisoformat.side_effect = datetime.fromisoformat
            mock_get.return_value = None

            res = await activate_trial("uid_tuesday_1", "+1234567890", "127_0_0_1")
            assert res["is_active"] is True
            assert res["is_weekend_paused"] is False
            assert res["days_remaining"] == 2
            assert res["days_used"] == 1
            assert "2026-09-01" in res["active_dates_used"]

    @pytest.mark.asyncio
    async def test_three_consecutive_market_days_then_expires(self):
        """User on day 3 uses their 3rd day, on day 4 trial expires."""
        from datetime import datetime, timezone
        mock_data = {
            "activated_at": "2026-09-01T10:00:00+00:00",
            "active_dates_used": ["2026-09-01", "2026-09-02", "2026-09-03"],
            "last_active_date": "2026-09-03",
        }
        # Thursday 2026-09-04 (4th day, not in active_dates_used)
        thursday = datetime(2026, 9, 4, 10, 0, 0, tzinfo=timezone.utc)
        with patch("routes.payments.datetime") as mock_dt, \
             patch("storage.storage.get", new_callable=AsyncMock) as mock_get:
            mock_dt.now.return_value = thursday
            mock_dt.fromisoformat.side_effect = datetime.fromisoformat
            mock_get.return_value = mock_data

            info = await _get_trial_info("uid_veteran_1")
            assert info["days_remaining"] == 0
            assert info["days_used"] == 3
            assert info["is_active"] is False


# ──────────────────────────────────────────────
#  Webhook and Checkout Integration Tests
# ──────────────────────────────────────────────

class TestPaymentWebhooksAndCheckout:
    @staticmethod
    def _make_req(body: bytes, headers: dict):
        from starlette.requests import Request
        scope = {
            "type": "http",
            "method": "POST",
            "path": "/payments/webhook",
            "headers": [(k.lower().encode(), v.encode()) for k, v in headers.items()],
            "client": ("127.0.0.1", 12345),
        }
        async def receive():
            return {"type": "http.request", "body": body}
        return Request(scope, receive)

    @pytest.mark.asyncio
    async def test_paddle_webhook_upgrades_tier(self):
        from routes.payments import get_user_tier
        from routes.payments_webhooks import paddle_webhook
        import time

        uid = "usr_paddle_upgrade_1"
        secret = "paddle_secret_wh_123"
        ts = int(time.time())
        payload_data = {
            "notification_id": "ntf_001",
            "event_type": "subscription.created",
            "data": {
                "status": "active",
                "custom_data": {"mehd_uid": uid, "tier": "precision"},
                "items": [{"price": {"id": "pri_precision_test"}}],
            }
        }
        body = json.dumps(payload_data).encode("utf-8")
        h1 = hmac.new(secret.encode("utf-8"), f"{ts}:{body.decode('utf-8')}".encode("utf-8"), hashlib.sha256).hexdigest()
        sig = f"ts={ts};h1={h1}"
        req = self._make_req(body, {"Paddle-Signature": sig})

        with patch("routes.payments.PADDLE_WEBHOOK_SECRET", secret), \
             patch("routes.payments.PADDLE_TO_TIER", {"pri_precision_test": "precision"}):
            res = await paddle_webhook(req)
            assert res["status"] == "ok"
            assert get_user_tier(uid) == "precision"

    @pytest.mark.asyncio
    async def test_paystack_webhook_upgrades_tier(self):
        from routes.payments import get_user_tier
        from routes.payments_webhooks import paystack_webhook

        uid = "usr_paystack_upgrade_1"
        secret = "sk_paystack_wh_123"
        payload_data = {
            "id": 999123,
            "event": "subscription.create",
            "data": {
                "customer": {"email": "trader@mehdai.com"},
                "plan": {"plan_code": "PLN_institutional_test"},
                "metadata": {"mehd_uid": uid, "tier": "institutional"},
            }
        }
        body = json.dumps(payload_data).encode("utf-8")
        sig = hmac.new(secret.encode("utf-8"), body, hashlib.sha512).hexdigest()
        req = self._make_req(body, {"x-paystack-signature": sig})

        with patch("routes.payments.PAYSTACK_SECRET_KEY", secret), \
             patch("routes.payments.PAYSTACK_TO_TIER", {"PLN_institutional_test": "institutional"}):
            res = await paystack_webhook(req)
            assert res["status"] == "ok"
            assert get_user_tier(uid) == "institutional"

    @pytest.mark.asyncio
    async def test_paddle_duplicate_webhook_deduplication(self):
        from routes.payments_webhooks import paddle_webhook
        import time

        secret = "paddle_secret_dedup"
        ts = int(time.time())
        payload_data = {
            "notification_id": "ntf_duplicate_99",
            "event_type": "subscription.created",
            "data": {
                "status": "active",
                "custom_data": {"mehd_uid": "uid_dup_1"},
                "items": [],
            }
        }
        body = json.dumps(payload_data).encode("utf-8")
        h1 = hmac.new(secret.encode("utf-8"), f"{ts}:{body.decode('utf-8')}".encode("utf-8"), hashlib.sha256).hexdigest()
        sig = f"ts={ts};h1={h1}"

        with patch("routes.payments.PADDLE_WEBHOOK_SECRET", secret):
            req1 = self._make_req(body, {"Paddle-Signature": sig})
            res1 = await paddle_webhook(req1)
            assert res1["status"] in ("ok", "already_processed")
            req2 = self._make_req(body, {"Paddle-Signature": sig})
            res2 = await paddle_webhook(req2)
            assert res2["status"] == "already_processed"

    @pytest.mark.asyncio
    async def test_paddle_invalid_signature_raises_400(self):
        from routes.payments_webhooks import paddle_webhook
        from fastapi import HTTPException

        req = self._make_req(b'{"event_type":"subscription.created"}', {"Paddle-Signature": "ts=123;h1=tampered_signature"})

        with pytest.raises(HTTPException) as exc:
            await paddle_webhook(req)
        assert exc.value.status_code == 400

    @pytest.mark.asyncio
    async def test_paddle_and_paystack_checkout_endpoints(self):
        from routes.payments import (
            get_paddle_checkout_params, PaddleCheckoutRequest,
            initialize_paystack_transaction, PaystackInitRequest,
        )
        req = self._make_req(b"", {})
        pad_res = await get_paddle_checkout_params(req, PaddleCheckoutRequest(tier="core"), uid="uid_chk_1")
        assert pad_res["tier"] == "core"
        assert pad_res["custom_data"]["mehd_uid"] == "uid_chk_1"

        pay_res = await initialize_paystack_transaction(
            req, PaystackInitRequest(tier="precision", email="chk@mehdai.com"), uid="uid_chk_1"
        )
        assert pay_res["status"] == "success"
        assert "authorization_url" in pay_res

    @pytest.mark.asyncio
    async def test_subscription_status_expired_user_gets_pricing_url(self):
        from routes.payments import get_subscription_status, PRICING_URL
        req = self._make_req(b"", {})
        status = await get_subscription_status(req, uid="expired_user_999")
        assert status.tier == "expired"
        assert status.portal_url == PRICING_URL





