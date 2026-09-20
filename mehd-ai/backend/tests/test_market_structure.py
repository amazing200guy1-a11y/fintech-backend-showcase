import pytest
from secretary import MarketStructureDetector, Secretary
from models import MarketSnapshot

def test_bullish_fair_value_gap_detection():
    detector = MarketStructureDetector()
    # Candle 0: Previous candle (c2) -> High 1.1510
    detector.record_candle("EURUSD", 1.1500, 1.1510, 1.1495, 1.1508)
    # Candle 1: Middle impulse candle (c1) -> Spikes to 1.1530
    detector.record_candle("EURUSD", 1.1508, 1.1530, 1.1508, 1.1528)
    # Candle 2: Current candle (c0) -> Low 1.1518 (8 pips above 1.1510)
    detector.record_candle("EURUSD", 1.1528, 1.1540, 1.1518, 1.1535)

    fvg, sweep = detector.detect_fvg_and_sweeps("EURUSD", pip_size=0.0001)
    assert "BULLISH FVG" in fvg
    assert "8.0 pips" in fvg
    assert "1.15100" in fvg
    assert "1.15180" in fvg

def test_bearish_fair_value_gap_detection():
    detector = MarketStructureDetector()
    # Candle 0: Previous candle (c2) -> Low 1.1550
    detector.record_candle("EURUSD", 1.1560, 1.1565, 1.1550, 1.1552)
    # Candle 1: Middle impulse down (c1) -> Dumps to 1.1520
    detector.record_candle("EURUSD", 1.1550, 1.1552, 1.1520, 1.1522)
    # Candle 2: Current candle (c0) -> High 1.1540 (10 pips below 1.1550)
    detector.record_candle("EURUSD", 1.1522, 1.1540, 1.1515, 1.1525)

    fvg, sweep = detector.detect_fvg_and_sweeps("EURUSD", pip_size=0.0001)
    assert "BEARISH FVG" in fvg
    assert "10.0 pips" in fvg
    assert "1.15400" in fvg
    assert "1.15500" in fvg

def test_liquidity_sweep_detection():
    detector = MarketStructureDetector()
    # Build 5 candles establishing swing high at 1.1550
    for i in range(5):
        detector.record_candle("EURUSD", 1.1530, 1.1550 if i == 2 else 1.1540, 1.1520, 1.1535)
    
    # Current candle spikes above 1.1550 to 1.1558 (sweeping high by 8 pips), but closes at 1.1545 (back inside)
    detector.record_candle("EURUSD", 1.1535, 1.1558, 1.1530, 1.1545)

    fvg, sweep = detector.detect_fvg_and_sweeps("EURUSD", pip_size=0.0001)
    assert "BEARISH SWEEP" in sweep
    assert "8.0 pips" in sweep
    assert "1.15500" in sweep

def test_secretary_briefing_includes_market_structure():
    sec = Secretary()
    snap = MarketSnapshot(
        symbol="EURUSD",
        bid=1.15370,
        ask=1.15380,
        spread=1.0,
        open=1.15300,
        high=1.15400,
        low=1.15280,
        close=1.15370,
        volume=1000.0,
    )
    should_wake, reason, briefing = sec.analyze_market_tick("EURUSD", snap, None)
    assert "Verified FVG:" in briefing
    assert "Liquidity Sweep:" in briefing
    assert "Current Price:" in briefing
    assert "Math EV (Pre-Calc):" in briefing
    assert "Mathematical Edge:" in briefing

def test_quant_ev_engine_edge_calculation():
    from secretary import QuantEVEngine
    engine = QuantEVEngine()
    snap = MarketSnapshot(
        symbol="EURUSD",
        bid=1.15370,
        ask=1.15380,
        spread=1.0,
        open=1.15300,
        high=1.15600,
        low=1.15100,
        close=1.15370,
        volume=1000.0,
    )
    ev_line, edge = engine.calculate_ev("EURUSD", snap)
    assert "EV=" in ev_line
    assert "RR=2.5:1" in ev_line
    assert "WinRate=61.7%" in ev_line
    assert "POSITIVE EDGE" in edge

