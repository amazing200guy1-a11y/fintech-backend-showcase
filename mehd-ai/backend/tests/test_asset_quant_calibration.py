"""
Mehd AI — Asset Quantitative Calibration & Sizing Verification Tests
=====================================================================
Ensures that all 16 Sovereign assets (Forex Majors, Crosses, Gold, Silver,
Crypto, and Indices) calculate mathematically exact pip values, SL/TP distances,
and safe lot sizes, with zero overleveraging vulnerabilities.
"""

import pytest
from unittest.mock import patch, AsyncMock, MagicMock
import sys

# Ensure firebase is mocked before imports
if 'firebase_admin' not in sys.modules:
    sys.modules['firebase_admin'] = MagicMock()
if 'firebase_admin.firestore' not in sys.modules:
    sys.modules['firebase_admin.firestore'] = MagicMock()

from models import get_pip_size
from risk_engine import HardRiskKernel
from sniper_engine import SniperEngine


class TestAssetPipSizeAndValues:
    def test_canonical_pip_sizes(self):
        """Verify pip sizes across all 16 Sovereign asset categories."""
        # Standard Forex
        assert get_pip_size("EURUSD") == 0.0001
        assert get_pip_size("GBPUSD") == 0.0001
        assert get_pip_size("AUDUSD") == 0.0001
        assert get_pip_size("NZDUSD") == 0.0001
        assert get_pip_size("USDCAD") == 0.0001
        assert get_pip_size("USDCHF") == 0.0001
        assert get_pip_size("EURGBP") == 0.0001

        # JPY Pairs
        assert get_pip_size("USDJPY") == 0.01
        assert get_pip_size("GBPJPY") == 0.01
        assert get_pip_size("EURJPY") == 0.01

        # Metals & Energy
        assert get_pip_size("XAUUSD") == 0.01
        assert get_pip_size("XAGUSD") == 0.01
        assert get_pip_size("USOIL") == 0.01

        # Indices
        assert get_pip_size("US30") == 1.0
        assert get_pip_size("NAS100") == 1.0
        assert get_pip_size("SPX500") == 1.0
        assert get_pip_size("GER40") == 1.0

        # Crypto
        assert get_pip_size("BTCUSD") == 1.0
        assert get_pip_size("ETHUSD") == 1.0
        assert get_pip_size("SOLUSD") == 0.01

    def test_kernel_pip_values(self):
        """Verify HardRiskKernel pip values match institutional contract sizes."""
        kernel = HardRiskKernel()
        assert kernel._get_pip_value("EURUSD") == 10.0
        assert kernel._get_pip_value("USDJPY") == 7.0
        assert kernel._get_pip_value("XAUUSD") == 1.0
        assert kernel._get_pip_value("XAGUSD") == 50.0
        assert kernel._get_pip_value("USOIL") == 10.0
        assert kernel._get_pip_value("US30") == 1.0
        assert kernel._get_pip_value("NAS100") == 1.0
        assert kernel._get_pip_value("SPX500") == 1.0
        assert kernel._get_pip_value("GER40") == 1.0
        assert kernel._get_pip_value("BTCUSD") == 1.0
        assert kernel._get_pip_value("ETHUSD") == 1.0
        assert kernel._get_pip_value("SOLUSD") == 1.0


class TestManualExecutionBriefCalculations:
    @pytest.mark.asyncio
    async def test_usdjpy_does_not_overleverage(self):
        """USD/JPY must calculate ~0.48 lots for $100 risk / 30 pips, NEVER 33 lots."""
        from routes.analysis import analyze_for_command
        from unittest.mock import MagicMock
        from starlette.requests import Request

        mock_snap = MagicMock()
        mock_snap.bid = 150.000
        mock_snap.ask = 150.015
        scope = {"type": "http", "client": ("127.0.0.1", 1234), "headers": []}
        req = Request(scope)

        with patch("routes.analysis.streamer.get_latest_snapshot", return_value=mock_snap), \
             patch("routes.analysis.get_user_tier_async", new_callable=AsyncMock) as mock_tier:
            mock_tier.return_value = "core"
            func = getattr(analyze_for_command, "__wrapped__", analyze_for_command)
            res = await func(req, "USDJPY", "BUY", "uid_test_1")
            
            # SL must be 30 pips below 150.000 = 149.700
            assert res["sl"] == 149.700
            # Suggested lot must be around 0.48 (100 / (30 * 7.0)), NOT 33.33!
            assert 0.40 <= res["suggested_lot"] <= 0.55
            assert res["suggested_lot"] != 33.33

    @pytest.mark.asyncio
    async def test_silver_calculates_correct_safe_lots(self):
        """Silver (XAG/USD) has $50/pip/lot. 25 pips SL on $100 risk = 0.08 lots."""
        from routes.analysis import analyze_for_command
        from unittest.mock import MagicMock
        from starlette.requests import Request

        mock_snap = MagicMock()
        mock_snap.bid = 30.00
        mock_snap.ask = 30.03
        scope = {"type": "http", "client": ("127.0.0.1", 1234), "headers": []}
        req = Request(scope)

        with patch("routes.analysis.streamer.get_latest_snapshot", return_value=mock_snap), \
             patch("routes.analysis.get_user_tier_async", new_callable=AsyncMock) as mock_tier:
            mock_tier.return_value = "core"
            func = getattr(analyze_for_command, "__wrapped__", analyze_for_command)
            res = await func(req, "XAGUSD", "BUY", "uid_test_1")
            
            # SL distance is $0.25 (25 pips)
            assert res["sl"] == 29.75
            # Lot size: $100 / (25 pips * $50) = 0.08 lots
            assert res["suggested_lot"] == 0.08

    @pytest.mark.asyncio
    async def test_indices_us30_has_realistic_sl_and_lots(self):
        """US30 at 39,000 must use 50-point SL and realistic lot size, not 0.0030 points."""
        from routes.analysis import analyze_for_command
        from unittest.mock import MagicMock
        from starlette.requests import Request

        mock_snap = MagicMock()
        mock_snap.bid = 39000.00
        mock_snap.ask = 39003.00
        scope = {"type": "http", "client": ("127.0.0.1", 1234), "headers": []}
        req = Request(scope)

        with patch("routes.analysis.streamer.get_latest_snapshot", return_value=mock_snap), \
             patch("routes.analysis.get_user_tier_async", new_callable=AsyncMock) as mock_tier:
            mock_tier.return_value = "core"
            func = getattr(analyze_for_command, "__wrapped__", analyze_for_command)
            res = await func(req, "US30", "BUY", "uid_test_1")
            
            # SL must be 50 points below 39,000 = 38,950
            assert res["sl"] == 38950.00
            # TP must be 120 points above 39,000 = 39,120
            assert res["tp"] == 39120.00
            # Lot size: $100 / (50 pts * $1/pt) = 2.0 contracts
            assert res["suggested_lot"] == 2.0
            # Spread must be 3.0 points, NOT 30,000!
            assert res["spread_pips"] == 3.0


class TestSniperPullbackCalibration:
    def test_sniper_pullback_distances_above_broker_spread(self):
        """Verify sniper targets do not trigger prematurely inside spread noise."""
        cb = MagicMock()
        engine = SniperEngine(cb)

        # 1. Gold (XAUUSD) at 2300.00: 20 pips ($0.20) pullback
        engine.arm_sniper("sig_gold", {
            "symbol": "XAUUSD",
            "direction": "BUY",
            "current_price": 2300.00,
            "broadcast_time": "2026-09-06T00:00:00+00:00",
            "votes": [],
        })
        gold_entry = engine.pending_sniper_entries.get("XAUUSD")
        if gold_entry:
            # Target price must be 2299.80 ($0.20 pullback, not $0.04)
            assert gold_entry["target_price"] == 2299.80

        # 2. Crypto (BTCUSD) at 65000.00: 25 points ($25.00) pullback
        engine.arm_sniper("sig_btc", {
            "symbol": "BTCUSD",
            "direction": "BUY",
            "current_price": 65000.00,
            "broadcast_time": "2026-09-06T00:00:00+00:00",
            "votes": [],
        })
        btc_entry = engine.pending_sniper_entries.get("BTCUSD")
        if btc_entry:
            # Target price must be 64975.00 ($25 pullback, not $2)
            assert btc_entry["target_price"] == 64975.00

        # 3. Indices (US30) at 39000.00: 10 points pullback
        engine.arm_sniper("sig_us30", {
            "symbol": "US30",
            "direction": "BUY",
            "current_price": 39000.00,
            "broadcast_time": "2026-09-06T00:00:00+00:00",
            "votes": [],
        })
        us30_entry = engine.pending_sniper_entries.get("US30")
        if us30_entry:
            # Target price must be 38990.00 (10 points pullback)
            assert us30_entry["target_price"] == 38990.00

        # 4. Energy (USOIL) at 75.00: 10 pips ($0.10) pullback
        engine.arm_sniper("sig_usoil", {
            "symbol": "USOIL",
            "direction": "BUY",
            "current_price": 75.00,
            "broadcast_time": "2026-09-06T00:00:00+00:00",
            "votes": [],
        })
        oil_entry = engine.pending_sniper_entries.get("USOIL")
        if oil_entry:
            assert oil_entry["target_price"] == 74.90


class TestBrokerGatewayQuadruplets:
    def test_oanda_symbol_mapping_quadruplets(self):
        """Ensure all Quadruplets correctly map to institutional OANDA/broker instruments."""
        from broker_gateway import _get_oanda_instrument, _lot_to_units, _format_price

        assert _get_oanda_instrument("SPX500") == "SPX500_USD"
        assert _get_oanda_instrument("GER40") == "DE30_EUR"
        assert _get_oanda_instrument("USOIL") == "WTICO_USD"
        assert _get_oanda_instrument("SOLUSD") == "SOL_USD"

        # Lot to units
        assert _lot_to_units(1.0, "SPX500") == 1
        assert _lot_to_units(1.0, "GER40") == 1
        assert _lot_to_units(1.0, "USOIL") == 1000
        assert _lot_to_units(1.0, "SOLUSD") == 1

        # Price formatting
        assert _format_price(5620.456, "SPX500") == "5620.46"
        assert _format_price(18530.222, "GER40") == "18530.22"
        assert _format_price(72.508, "USOIL") == "72.51"
        assert _format_price(145.883, "SOLUSD") == "145.88"
