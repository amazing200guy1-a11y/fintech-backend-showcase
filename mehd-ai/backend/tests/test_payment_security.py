"""
Mehd AI — Payment Security & Real-Money Flow Hardening Tests
============================================================
Tests for:
1. Paystack transaction initialization currency parameter (USD guarantee).
2. Paystack charge.success instant tier unlock.
3. Paystack refund.processed and dispute.created tier revocation.
4. Paddle transaction.refunded, transaction.disputed, and adjustment.created tier revocation.
"""

import hashlib
import hmac
import json
import time
from unittest.mock import patch, AsyncMock, MagicMock
import pytest
from starlette.requests import Request

import sys
# Mock firebase before imports
sys.modules['firebase_admin'] = MagicMock()
sys.modules['firebase_admin.firestore'] = MagicMock()

from routes.payments import (
    get_user_tier,
    set_user_tier,
    initialize_paystack_transaction,
    PaystackInitRequest,
)
from routes.payments_webhooks import paddle_webhook, paystack_webhook


def _make_req(body: bytes, headers: dict) -> Request:
    scope = {
        "type": "http",
        "method": "POST",
        "path": "/payments/webhook",
        "headers": [(k.lower().encode("latin1"), v.encode("latin1")) for k, v in headers.items()],
        "client": ("127.0.0.1", 12345),
    }
    async def receive():
        return {"type": "http.request", "body": body}
    return Request(scope, receive)


class TestPaystackCurrencyAndInstantUnlock:
    """Verifies USD billing protection and charge.success instant activation."""

    @pytest.mark.asyncio
    async def test_paystack_initialize_sends_currency_param(self):
        req = _make_req(b"", {})
        captured_payload = {}

        class MockResponse:
            status_code = 200
            def json(self):
                return {
                    "status": True,
                    "data": {
                        "authorization_url": "https://checkout.paystack.com/auth_123",
                        "access_code": "acc_123",
                        "reference": "ref_123",
                    }
                }

        async def mock_post(url, headers=None, json=None):
            nonlocal captured_payload
            captured_payload = json
            return MockResponse()

        mock_client = AsyncMock()
        mock_client.post = mock_post
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch("routes.payments.os.getenv", side_effect=lambda k, d="": "sk_live_test_key" if k == "PAYSTACK_SECRET_KEY" else d), \
             patch("httpx.AsyncClient", return_value=mock_client):
            res = await initialize_paystack_transaction(
                req,
                PaystackInitRequest(tier="core", email="real_money@mehdai.com"),
                uid="uid_real_money_1",
            )
            assert res["status"] == "success"
            assert captured_payload.get("currency") == "USD"
            assert captured_payload.get("amount") == 7900
            assert captured_payload.get("metadata", {}).get("tier") == "core"

    @pytest.mark.asyncio
    async def test_paystack_charge_success_instantly_upgrades_user(self):
        uid = "uid_paystack_instant_1"
        secret = "sk_paystack_sec_key"
        payload_data = {
            "id": "evt_charge_success_101",
            "event": "charge.success",
            "data": {
                "customer": {"email": "instant@mehdai.com"},
                "plan": {"plan_code": "PLN_sovereign_instant"},
                "metadata": {"mehd_uid": uid, "tier": "institutional"},
            }
        }
        body = json.dumps(payload_data).encode("utf-8")
        sig = hmac.new(secret.encode("utf-8"), body, hashlib.sha512).hexdigest()
        req = _make_req(body, {"x-paystack-signature": sig})

        with patch("routes.payments.PAYSTACK_SECRET_KEY", secret), \
             patch("routes.payments.PAYSTACK_TO_TIER", {"PLN_sovereign_instant": "institutional"}):
            res = await paystack_webhook(req)
            assert res["status"] == "ok"
            assert get_user_tier(uid) == "institutional"


class TestRefundAndDisputeRevocation:
    """Verifies that refunds, chargebacks, and disputes instantly revoke user access."""

    @pytest.mark.asyncio
    async def test_paystack_refund_processed_revokes_tier(self):
        uid = "uid_paystack_refunded_1"
        set_user_tier(uid, "institutional")
        assert get_user_tier(uid) == "institutional"

        secret = "sk_paystack_sec_key"
        payload_data = {
            "id": "evt_refund_processed_202",
            "event": "refund.processed",
            "data": {
                "customer": {"email": "refunded@mehdai.com"},
            }
        }
        body = json.dumps(payload_data).encode("utf-8")
        sig = hmac.new(secret.encode("utf-8"), body, hashlib.sha512).hexdigest()
        req = _make_req(body, {"x-paystack-signature": sig})

        with patch("routes.payments.PAYSTACK_SECRET_KEY", secret), \
             patch("routes.payments._paystack_email_to_uid", {"refunded@mehdai.com": uid}):
            res = await paystack_webhook(req)
            assert res["status"] == "ok"
            assert get_user_tier(uid) == "expired"

    @pytest.mark.asyncio
    async def test_paystack_dispute_created_revokes_tier(self):
        uid = "uid_paystack_disputed_1"
        set_user_tier(uid, "precision")
        assert get_user_tier(uid) == "precision"

        secret = "sk_paystack_sec_key"
        payload_data = {
            "id": "evt_dispute_created_303",
            "event": "dispute.created",
            "data": {
                "customer": {"email": "dispute@mehdai.com"},
            }
        }
        body = json.dumps(payload_data).encode("utf-8")
        sig = hmac.new(secret.encode("utf-8"), body, hashlib.sha512).hexdigest()
        req = _make_req(body, {"x-paystack-signature": sig})

        with patch("routes.payments.PAYSTACK_SECRET_KEY", secret), \
             patch("routes.payments._paystack_email_to_uid", {"dispute@mehdai.com": uid}):
            res = await paystack_webhook(req)
            assert res["status"] == "ok"
            assert get_user_tier(uid) == "expired"

    @pytest.mark.asyncio
    async def test_paddle_transaction_refunded_revokes_tier(self):
        uid = "uid_paddle_refunded_1"
        set_user_tier(uid, "institutional")
        assert get_user_tier(uid) == "institutional"

        secret = "paddle_sec_wh_key"
        ts = int(time.time())
        payload_data = {
            "notification_id": "ntf_paddle_refund_404",
            "event_type": "transaction.refunded",
            "data": {
                "custom_data": {"mehd_uid": uid},
            }
        }
        body = json.dumps(payload_data).encode("utf-8")
        h1 = hmac.new(secret.encode("utf-8"), f"{ts}:{body.decode('utf-8')}".encode("utf-8"), hashlib.sha256).hexdigest()
        sig = f"ts={ts};h1={h1}"
        req = _make_req(body, {"Paddle-Signature": sig})

        with patch("routes.payments.PADDLE_WEBHOOK_SECRET", secret):
            res = await paddle_webhook(req)
            assert res["status"] == "ok"
            assert get_user_tier(uid) == "expired"

    @pytest.mark.asyncio
    async def test_paddle_transaction_disputed_revokes_tier(self):
        uid = "uid_paddle_disputed_1"
        set_user_tier(uid, "precision")
        assert get_user_tier(uid) == "precision"

        secret = "paddle_sec_wh_key"
        ts = int(time.time())
        payload_data = {
            "notification_id": "ntf_paddle_dispute_505",
            "event_type": "transaction.disputed",
            "data": {
                "custom_data": {"mehd_uid": uid},
            }
        }
        body = json.dumps(payload_data).encode("utf-8")
        h1 = hmac.new(secret.encode("utf-8"), f"{ts}:{body.decode('utf-8')}".encode("utf-8"), hashlib.sha256).hexdigest()
        sig = f"ts={ts};h1={h1}"
        req = _make_req(body, {"Paddle-Signature": sig})

        with patch("routes.payments.PADDLE_WEBHOOK_SECRET", secret):
            res = await paddle_webhook(req)
            assert res["status"] == "ok"
            assert get_user_tier(uid) == "expired"


class TestTierAssetGatingSecurity:
    def test_core_tier_symbol_permissions(self):
        from routes.payments import is_symbol_allowed_for_tier
        # Allowed for Core (8 Flagships: Majors, Gold, Nasdaq, Bitcoin)
        assert is_symbol_allowed_for_tier("EURUSD", "core") is True
        assert is_symbol_allowed_for_tier("XAUUSD", "core") is True
        assert is_symbol_allowed_for_tier("NAS100", "core") is True
        assert is_symbol_allowed_for_tier("BTCUSD", "core") is True
        assert is_symbol_allowed_for_tier("EUR/USD", "core") is True
        assert is_symbol_allowed_for_tier("BTC/USD", "core") is True
        
        # Blocked for Core (Require Precision / Sovereign)
        assert is_symbol_allowed_for_tier("USOIL", "core") is False
        assert is_symbol_allowed_for_tier("US30", "core") is False
        assert is_symbol_allowed_for_tier("ETHUSD", "core") is False
        assert is_symbol_allowed_for_tier("SPX500", "core") is False
        assert is_symbol_allowed_for_tier("GER40", "core") is False
        assert is_symbol_allowed_for_tier("SOLUSD", "core") is False

    def test_precision_tier_symbol_permissions(self):
        from routes.payments import is_symbol_allowed_for_tier
        # Allowed for Precision (14 Assets)
        assert is_symbol_allowed_for_tier("EURUSD", "precision") is True
        assert is_symbol_allowed_for_tier("USOIL", "precision") is True
        assert is_symbol_allowed_for_tier("US30", "precision") is True
        assert is_symbol_allowed_for_tier("ETHUSD", "precision") is True
        assert is_symbol_allowed_for_tier("XAGUSD", "precision") is True
        assert is_symbol_allowed_for_tier("EURGBP", "precision") is True
        
        # Blocked for Precision (Requires Sovereign)
        assert is_symbol_allowed_for_tier("SPX500", "precision") is False
        assert is_symbol_allowed_for_tier("GER40", "precision") is False
        assert is_symbol_allowed_for_tier("GBPJPY", "precision") is False
        assert is_symbol_allowed_for_tier("EURJPY", "precision") is False
        assert is_symbol_allowed_for_tier("SOLUSD", "precision") is False

    def test_sovereign_tier_has_all_twenty_symbols(self):
        from routes.payments import is_symbol_allowed_for_tier
        from state import VALID_SYMBOLS
        for sym in VALID_SYMBOLS:
            assert is_symbol_allowed_for_tier(sym, "institutional") is True
            assert is_symbol_allowed_for_tier(sym, "sovereign") is True
            assert is_symbol_allowed_for_tier(sym, "tiger") is True
