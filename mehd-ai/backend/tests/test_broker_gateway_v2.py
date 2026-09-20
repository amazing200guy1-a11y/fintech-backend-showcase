"""
Mehd AI — Broker Gateway Tests
=================================
Tests for the OANDA broker integration layer.
Covers: paper mode, symbol mapping, lot conversion, account summary.
"""

import pytest
from unittest.mock import patch, MagicMock

from models import TradeOrder, RiskDecision, Direction
from broker_gateway import (
    BrokerGateway,
    _get_oanda_instrument,
    _lot_to_units,
)


# ──────────────────────────────────────────────
#  Symbol Mapping Tests
# ──────────────────────────────────────────────

class TestSymbolMapping:
    def test_eurusd(self):
        assert _get_oanda_instrument("EURUSD") == "EUR_USD"

    def test_gbpusd(self):
        assert _get_oanda_instrument("GBPUSD") == "GBP_USD"

    def test_usdjpy(self):
        assert _get_oanda_instrument("USDJPY") == "USD_JPY"

    def test_xauusd(self):
        assert _get_oanda_instrument("XAUUSD") == "XAU_USD"

    def test_case_insensitive(self):
        assert _get_oanda_instrument("eurusd") == "EUR_USD"

    def test_unknown_symbol_fallback(self):
        """Unknown symbols should still get a reasonable conversion."""
        result = _get_oanda_instrument("NZDUSD")
        assert result == "NZD_USD"


# ──────────────────────────────────────────────
#  Lot to Units Conversion
# ──────────────────────────────────────────────

class TestLotToUnits:
    def test_one_standard_lot(self):
        """1 lot = 100,000 units for forex."""
        assert _lot_to_units(1.0, "EURUSD") == 100_000

    def test_micro_lot(self):
        """0.01 lot = 1,000 units."""
        assert _lot_to_units(0.01, "EURUSD") == 1_000

    def test_mini_lot(self):
        """0.10 lot = 10,000 units."""
        assert _lot_to_units(0.10, "EURUSD") == 10_000

    def test_gold_lot(self):
        """Gold: 1 lot = 100 unit (ounce)."""
        assert _lot_to_units(1.0, "XAUUSD") == 100

    def test_fractional_lot(self):
        """0.69 lots = 69,000 units."""
        assert _lot_to_units(0.69, "GBPUSD") == 69_000

    def test_silver_lot(self):
        """Silver: 1 lot = 5,000 oz, 0.01 lot = 50 oz."""
        assert _lot_to_units(1.0, "XAGUSD") == 5_000
        assert _lot_to_units(0.01, "XAG/USD") == 50

    def test_index_lot(self):
        """Indices: 1 lot = 1 contract."""
        assert _lot_to_units(1.0, "NAS100") == 1
        assert _lot_to_units(2.0, "US30") == 2

    def test_crypto_lot(self):
        """Crypto: 1 lot = 1 unit."""
        assert _lot_to_units(1.0, "BTCUSD") == 1
        assert _lot_to_units(1.0, "ETH/USD") == 1

    def test_usdchf_instrument_mapping(self):
        """USDCHF must map to USD_CHF (not _USDCHF)."""
        from broker_gateway import _get_oanda_instrument
        assert _get_oanda_instrument("USDCHF") == "USD_CHF"
        assert _get_oanda_instrument("USD/CHF") == "USD_CHF"

    def test_micro_lot_minimum_guard(self):
        """Even microscopic lot sizes must return at least 1 unit."""
        assert _lot_to_units(0.00001, "EURUSD") >= 1
        assert _lot_to_units(0.001, "XAUUSD") >= 1


# ──────────────────────────────────────────────
#  Price Precision Formatting Tests
# ──────────────────────────────────────────────

class TestPriceFormatting:
    def test_forex_precision(self):
        from broker_gateway import _format_price
        assert _format_price(1.085023, "EURUSD") == "1.08502"
        assert _format_price(1.2700, "GBPUSD") == "1.27000"

    def test_jpy_precision(self):
        from broker_gateway import _format_price
        assert _format_price(154.2567, "USDJPY") == "154.257"
        assert _format_price(162.1, "GBPJPY") == "162.100"

    def test_metals_precision(self):
        from broker_gateway import _format_price
        assert _format_price(2350.5678, "XAUUSD") == "2350.57"
        assert _format_price(30.456, "XAGUSD") == "30.46"

    def test_crypto_and_indices_precision(self):
        from broker_gateway import _format_price
        assert _format_price(65432.123, "BTCUSD") == "65432.12"
        assert _format_price(3456.789, "ETHUSD") == "3456.79"
        assert _format_price(18500.255, "NAS100") == "18500.26"


# ──────────────────────────────────────────────
#  Headers & Credentials Security Tests
# ──────────────────────────────────────────────

class TestHeadersSecurity:
    def test_headers_without_credentials_uses_env(self):
        from broker_gateway import BrokerGateway
        with patch.dict("os.environ", {"OANDA_API_KEY": "env-test-key-123", "OANDA_ACCOUNT_ID": "acct-123"}):
            gw = BrokerGateway()
            headers = gw._headers(None)
            assert headers["Authorization"] == "Bearer env-test-key-123"

    def test_headers_with_explicit_credentials(self):
        from broker_gateway import BrokerGateway
        with patch.dict("os.environ", {"OANDA_API_KEY": "env-key", "OANDA_ACCOUNT_ID": "acct-123"}):
            gw = BrokerGateway()
            headers = gw._headers({"api_key": "user-custom-key-999"})
            assert headers["Authorization"] == "Bearer user-custom-key-999"


# ──────────────────────────────────────────────
#  Paper Mode Tests
# ──────────────────────────────────────────────

class TestPaperMode:
    def setup_method(self):
        """Create a gateway with no API keys (paper mode)."""
        with patch.dict("os.environ", {"OANDA_API_KEY": "", "OANDA_ACCOUNT_ID": ""}):
            self.gw = BrokerGateway()

    def test_is_paper_mode(self):
        assert not self.gw._is_live

    def test_paper_execution_returns_simulated(self):
        order = TradeOrder(
            symbol="EURUSD",
            direction=Direction.BUY,
            lot_size=0.01,
            stop_loss=1.08000,
            take_profit=1.09000,
        )
        decision = RiskDecision(
            approved=True,
            calculated_lot_size=0.01,
            stop_loss=1.08000,
            take_profit=1.09000,
        )
        import asyncio
        result = asyncio.run(self.gw.execute_order(order, decision))
        assert result["mode"] == "paper"
        assert result["status"] == "simulated"
        assert result["broker"] == "mock"

    def test_paper_account_summary(self):
        import asyncio
        summary = asyncio.run(self.gw.get_account_summary())
        assert summary["mode"] == "paper"
        assert summary["balance"] == 10_000.0
        assert summary["equity"] == 10_000.0


class TestLatencyArbitrageBoundsAndRateLimiter:
    def test_rate_limiter_is_loop_aware(self):
        import asyncio
        gw = BrokerGateway()
        sem1 = gw._rate_limiter
        assert isinstance(sem1, asyncio.Semaphore)
        # Re-access returns same semaphore on same loop
        assert gw._rate_limiter is sem1

    @pytest.mark.asyncio
    async def test_live_price_bounds_are_asset_calibrated(self):
        """Verify that priceBound gives realistic spread room for each asset class."""
        from unittest.mock import AsyncMock
        gw = BrokerGateway()
        gw._is_live = True

        captured_payloads = []

        async def mock_post(url, headers=None, json=None):
            captured_payloads.append(json)
            mock_resp = MagicMock()
            mock_resp.status_code = 201
            mock_resp.json.return_value = {
                "orderFillTransaction": {
                    "id": "1001",
                    "price": json["order"].get("priceBound", "1.0850"),
                    "units": json["order"]["units"],
                }
            }
            return mock_resp

        # 1. Gold (XAUUSD): expected price 2300.00 -> bound with 50 pips ($0.50)
        gw._circuit_breaker_open_until = 0.0
        gold_order = TradeOrder(symbol="XAUUSD", direction=Direction.BUY, lot_size=0.1)
        gold_decision = RiskDecision(approved=True, calculated_lot_size=0.1, stop_loss=2290.0, expected_price=2300.00)

        with patch("os.getenv", side_effect=lambda k, d="": "key" if "API_KEY" in k else ("101" if "ACCOUNT" in k else d)), \
             patch("httpx.AsyncClient.post", side_effect=mock_post):
            res = await gw.execute_order(gold_order, gold_decision)
            assert res["status"] == "filled"
            # Gold priceBound BUY: 2300.00 + (50 * 0.01) = 2300.50
            assert captured_payloads[-1]["order"]["priceBound"] == "2300.50"

        # 2. Crypto (BTCUSD): expected price 65000.00 -> bound with 50 pts ($50.00)
        gw._circuit_breaker_open_until = 0.0
        btc_order = TradeOrder(symbol="BTCUSD", direction=Direction.SELL, lot_size=0.05)
        btc_decision = RiskDecision(approved=True, calculated_lot_size=0.05, stop_loss=66000.0, expected_price=65000.00)

        with patch("os.getenv", side_effect=lambda k, d="": "key" if "API_KEY" in k else ("101" if "ACCOUNT" in k else d)), \
             patch("httpx.AsyncClient.post", side_effect=mock_post):
            res = await gw.execute_order(btc_order, btc_decision)
            assert res["status"] == "filled"
            # BTC priceBound SELL: 65000.00 - (50 * 1.0) = 64950.00
            assert captured_payloads[-1]["order"]["priceBound"] == "64950.00"

        # 3. Indices (US30): expected price 39000.00 -> bound with 15 pts
        gw._circuit_breaker_open_until = 0.0
        us30_order = TradeOrder(symbol="US30USD", direction=Direction.BUY, lot_size=1.0)
        us30_decision = RiskDecision(approved=True, calculated_lot_size=1.0, stop_loss=38950.0, expected_price=39000.00)

        with patch("os.getenv", side_effect=lambda k, d="": "key" if "API_KEY" in k else ("101" if "ACCOUNT" in k else d)), \
             patch("httpx.AsyncClient.post", side_effect=mock_post):
            res = await gw.execute_order(us30_order, us30_decision)
            assert res["status"] == "filled"
            # US30 priceBound BUY: 39000.00 + (15 * 1.0) = 39015.00
            assert captured_payloads[-1]["order"]["priceBound"] == "39015.00"
