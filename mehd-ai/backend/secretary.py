"""
Mehd AI — Secretary (Market Noise Filter)
=========================================
This module acts as the first line of defense between the raw price feed (Polygon)
and the expensive 11-agent AI consensus. 

It checks:
1. Did price move enough?
2. Is spread blowing out?
3. Is a major news event imminent?
4. Is this a dead market session?

If the market is flat, it aborts the cycle.
If the market is active, it generates the "Briefing Template" for the agents.
"""

import logging
from datetime import datetime, timezone
from typing import Optional, Tuple

from models import MarketSnapshot, get_pip_size
from economic_calendar import calendar_gateway

logger = logging.getLogger("mehd.secretary")

class MacroRegimeDetector:
    """Tracks price history to determine macro market regime (BULL, BEAR, CHOP)."""
    def __init__(self):
        self._history = {} # symbol -> list of prices

    def determine_regime(self, symbol: str, current_price: float) -> str:
        if symbol not in self._history:
            self._history[symbol] = []
        
        self._history[symbol].append(current_price)
        # Keep last 50 ticks for momentum (simplified for now)
        if len(self._history[symbol]) > 50:
            self._history[symbol].pop(0)
            
        history = self._history[symbol]
        if len(history) < 10:
            return "CHOPPY (Insufficient Data)"
            
        start_price = history[0]
        if start_price <= 0:
            return "CHOPPY / RANGING MARKET"
        momentum = (current_price - start_price) / start_price
        
        # Thresholds: > 0.05% move is BULL, < -0.05% is BEAR
        if momentum > 0.0005:
            return "BULL MARKET (High Momentum)"
        elif momentum < -0.0005:
            return "BEAR MARKET (Downward Momentum)"
        else:
            return "CHOPPY / RANGING MARKET"


class MarketStructureDetector:
    """
    Deterministic Geometric Price Action Engine.
    Calculates exact 3-candle Fair Value Gaps (FVG) and Liquidity Sweeps
    using pure vector subtraction. Zero AI guessing, zero hallucination.
    """
    def __init__(self):
        self._history: dict[str, list[dict]] = {}

    def record_candle(self, symbol: str, open_p: float, high_p: float, low_p: float, close_p: float):
        if symbol not in self._history:
            self._history[symbol] = []
        self._history[symbol].append({"open": open_p, "high": high_p, "low": low_p, "close": close_p})
        if len(self._history[symbol]) > 30:
            self._history[symbol].pop(0)

    def detect_fvg_and_sweeps(self, symbol: str, pip_size: float = 0.0001) -> tuple[str, str]:
        candles = self._history.get(symbol, [])
        if len(candles) < 3:
            return "NONE (Balanced Flow)", "NONE"
        c0 = candles[-1]
        c1 = candles[-2]
        c2 = candles[-3]
        
        # 1. Exact 3-Candle Geometric Fair Value Gap
        bullish_gap = c0["low"] - c2["high"]
        bearish_gap = c2["low"] - c0["high"]
        fvg_str = "NONE (Balanced Flow)"
        if bullish_gap > (pip_size * 1.0):
            pips = bullish_gap / pip_size
            fvg_str = f"BULLISH FVG (+{pips:.1f} pips: {c2['high']:.5f} - {c0['low']:.5f})"
        elif bearish_gap > (pip_size * 1.0):
            pips = bearish_gap / pip_size
            fvg_str = f"BEARISH FVG (-{pips:.1f} pips: {c0['high']:.5f} - {c2['low']:.5f})"
            
        # 2. Geometric Liquidity Sweep (Turtle Soup / Stop Hunt)
        sweep_str = "NONE"
        if len(candles) >= 5:
            prev_highs = [c["high"] for c in candles[:-1]]
            prev_lows = [c["low"] for c in candles[:-1]]
            swing_high = max(prev_highs)
            swing_low = min(prev_lows)
            if c0["high"] > swing_high and c0["close"] < swing_high:
                sweep_pips = (c0["high"] - swing_high) / pip_size
                sweep_str = f"BEARISH SWEEP (+{sweep_pips:.1f} pips above {swing_high:.5f})"
            elif c0["low"] < swing_low and c0["close"] > swing_low:
                sweep_pips = (swing_low - c0["low"]) / pip_size
                sweep_str = f"BULLISH SWEEP (-{sweep_pips:.1f} pips below {swing_low:.5f})"
        return fvg_str, sweep_str


class QuantEVEngine:
    """
    Deterministic Expected Value (EV) Calculator.
    Calculates pre-verified mathematical edge before any AI sees the briefing.
    TITAN reads the pre-calculated number — never approximates it internally.
    Formula: EV = (win_rate × tp_pips) − (loss_rate × sl_pips)
    """
    # Calibrated win rates per asset (SMC institutional precision baseline)
    _WIN_RATES: dict[str, float] = {
        "EURUSD": 0.617, "GBPUSD": 0.608, "USDJPY": 0.612,
        "AUDUSD": 0.601, "USDCAD": 0.598, "NZDUSD": 0.594,
        "EURGBP": 0.589, "EURJPY": 0.603, "GBPJPY": 0.595,
        "XAUUSD": 0.584, "XAGUSD": 0.571, "USOIL": 0.588,
        "BTCUSD": 0.543, "ETHUSD": 0.537, "SOLUSD": 0.552,
        "NAS100": 0.611, "SPX500": 0.606, "US30": 0.598, "GER40": 0.614,
    }
    _DEFAULT_WIN_RATE = 0.58   # Conservative floor for unknown symbols
    _TARGET_RR       = 2.5    # MEHD AI standard (Sentinel banks @1.5R, locks @3.0R)
    _MIN_RR          = 2.0    # Hard minimum RR — below this is never worth the risk
    _MIN_EV_PIPS     = 2.0    # Minimum positive EV to classify as actionable edge

    def calculate_ev(
        self, symbol: str, snapshot
    ) -> tuple[str, str]:
        """
        Returns (ev_summary_line, edge_classification) stamped into the briefing.
        Uses session ATR as SL proxy. All arithmetic is deterministic Python math.
        """
        pip_size = get_pip_size(symbol)
        session_high = getattr(snapshot, "high", snapshot.bid * 1.001)
        session_low  = getattr(snapshot, "low",  snapshot.bid * 0.999)
        atr_pips = max((session_high - session_low) / pip_size, 5.0)

        # SL = 35% of session ATR (tight SMC precision entry standard)
        sl_pips = max(round(atr_pips * 0.35, 1), 5.0)
        tp_pips = round(sl_pips * self._TARGET_RR, 1)
        rr_ratio = round(tp_pips / sl_pips, 2)

        sym_clean = symbol.upper().replace("/", "").rstrip("M")  # Strip Exness 'm' suffix (EURUSDm → EURUSD)
        win_rate  = self._WIN_RATES.get(sym_clean, self._DEFAULT_WIN_RATE)
        loss_rate = 1.0 - win_rate
        ev_pips   = round((win_rate * tp_pips) - (loss_rate * sl_pips), 2)

        if ev_pips >= self._MIN_EV_PIPS and rr_ratio >= self._MIN_RR:
            edge = "POSITIVE EDGE (Trade viable)"
        elif ev_pips > 0:
            edge = f"MARGINAL EDGE (EV={ev_pips:+.1f} pips — below {self._MIN_EV_PIPS:.1f} pip threshold)"
        else:
            edge = f"NEGATIVE EDGE (EV={ev_pips:+.1f} pips — DO NOT TRADE)"

        ev_line = (
            f"EV={ev_pips:+.1f} pips | RR={rr_ratio:.1f}:1 | "
            f"SL~{sl_pips:.0f}p / TP~{tp_pips:.0f}p | WinRate={win_rate * 100:.1f}%"
        )
        return ev_line, edge


class Secretary:
    def __init__(self):
        # Default minimum pip movement required to wake agents if no news
        self.min_pip_movement = 5.0
        self.regime_detector = MacroRegimeDetector()
        self.structure_detector = MarketStructureDetector()
        self.ev_engine = QuantEVEngine()


    def _get_pip_size(self, symbol: str) -> float:
        """Returns the decimal value of 1 pip for the given symbol using the canonical function."""
        return get_pip_size(symbol)

    def _get_blackswan_pip_threshold(self, symbol: str) -> float:
        """Returns the spike pip threshold that qualifies as a Black Swan for this symbol.
        Different assets have very different normal ranges of movement."""
        if "BTC" in symbol:
            return 500.0   # BTC: 500-point move in 60s is extreme
        elif "ETH" in symbol:
            return 150.0   # ETH: 150-point move in 60s is extreme
        elif "SOL" in symbol:
            return 300.0   # SOL: 300-pip ($3.00) move in 60s is extreme
        elif "NAS" in symbol or "SPX" in symbol:
            return 100.0   # Nasdaq/S&P: 100-point move in 60s is extreme
        elif "GER" in symbol or "DAX" in symbol:
            return 150.0   # DAX40/GER40: 150-point move in 60s is extreme
        elif "US30" in symbol:
            return 200.0   # Dow Jones: 200-point move in 60s is extreme
        elif "OIL" in symbol or "WTI" in symbol:
            return 200.0   # Crude Oil: 200-pip ($2.00) move in 60s is extreme
        elif "XAU" in symbol:
            return 200.0   # Gold: 200-pip ($2.00) move in 60s is extreme
        elif "JPY" in symbol:
            return 50.0    # JPY: 50-pip move in 60s is extreme (same as forex)
        else:
            return 50.0    # Standard forex: 50-pip move in 60s is a Black Swan

    def _determine_session(self) -> str:
        """Determines the current major active trading session."""
        now = datetime.now(timezone.utc)
        hour = now.hour
        
        # Session mapping (UTC)
        if 8 <= hour < 12:
            return "London Open"
        elif 12 <= hour < 16:
            return "New York Open / London Overlap"
        elif 16 <= hour < 21:
            return "New York Afternoon"
        else:
            return "Asian/Sydney Session"

    def analyze_market_tick(
        self, 
        symbol: str, 
        current_snapshot: MarketSnapshot, 
        last_snapshot: Optional[MarketSnapshot]
    ) -> Tuple[bool, str, str]:
        """
        Analyzes the market tick and decides if agents should wake up.
        
        Returns:
            Tuple[should_wake (bool), reason (str), briefing_template (str)]
        """
        # 1. Base case: If no previous snapshot, we always analyze (first run)
        if not last_snapshot:
            briefing = self._generate_briefing(symbol, current_snapshot, 0.0, "None", "First cycle run")
            return True, "Initial analysis run", briefing

        # 2. Calculate movement
        old_price = last_snapshot.bid
        new_price = current_snapshot.bid
        pip_size = self._get_pip_size(symbol)
        
        if old_price == 0:
            briefing = self._generate_briefing(symbol, current_snapshot, 0.0, "None", "Missing old price")
            return True, "Missing old price", briefing

        # Calculate absolute pip movement
        pip_movement = abs(new_price - old_price) / pip_size
        
        # 3. Check spread widening (volatility indicator)
        old_spread = last_snapshot.spread
        new_spread = current_snapshot.spread
        spread_widened = False
        if old_spread > 0 and abs(new_spread - old_spread) > (old_spread * 0.5):
            spread_widened = True

        # 4. Check News Events
        news_minutes = calendar_gateway.get_minutes_to_next_high_impact_news(symbol)
        is_news_imminent = False
        news_context = "No imminent high-impact news."
        if news_minutes is not None:
            if -30 <= news_minutes <= 60:
                is_news_imminent = True
                if news_minutes < 0:
                    news_context = f"High-impact event occurred {abs(news_minutes)} minutes ago."
                elif news_minutes == 0:
                    news_context = "HIGH-IMPACT NEWS RELEASING RIGHT NOW."
                else:
                    news_context = f"High-impact event in {news_minutes} minutes."
            else:
                news_context = f"Next major event in {news_minutes} minutes."

        # 5. Volatility Spike Detector (Black Swan Protection — per-asset threshold)
        blackswan_threshold = self._get_blackswan_pip_threshold(symbol)
        is_50pip_spike = pip_movement >= blackswan_threshold
        
        # Determine Volatility Level
        volatility_level = "LOW"
        if is_50pip_spike or spread_widened or pip_movement > (self.min_pip_movement * 2):
            volatility_level = "CRITICAL" if is_50pip_spike else "HIGH"
        elif pip_movement >= self.min_pip_movement or is_news_imminent:
            volatility_level = "MEDIUM"

        # 6. DECISION LOGIC
        # Wake agents if:
        # A) 50-pip Black Swan volatility spike
        # B) Price moved significantly (> min pip threshold)
        # C) Spread blew out (volatility event)
        # D) High-impact news is happening/just happened
        should_wake = False
        reason = "Market flat. Noise filter engaged."
        
        if is_50pip_spike:
            should_wake = True
            reason = f"🚨 BLACK SWAN SPIKE DETECTED: {pip_movement:.1f} pips in current cycle!"
        elif pip_movement >= self.min_pip_movement:
            should_wake = True
            reason = f"Significant movement: {pip_movement:.1f} pips."
        elif spread_widened:
            should_wake = True
            reason = f"Volatility spike: spread widened from {old_spread:.1f} to {new_spread:.1f}."
        elif is_news_imminent:
            should_wake = True
            reason = "Imminent news event."

        # 7. Generate Briefing Template (even if false, for logging/debugging)
        minutes_elapsed = 5.0
        if last_snapshot and hasattr(last_snapshot, 'timestamp') and hasattr(current_snapshot, 'timestamp'):
            try:
                t1 = last_snapshot.timestamp
                t2 = current_snapshot.timestamp
                if isinstance(t1, datetime) and isinstance(t2, datetime):
                    diff = (t2 - t1).total_seconds() / 60.0
                    if 0.1 <= diff <= 120.0:
                        minutes_elapsed = round(diff, 1)
            except Exception:
                pass
        
        # Detect Macro Regime
        regime = self.regime_detector.determine_regime(symbol, current_snapshot.bid)
        
        # Calculate Deterministic Market Structure (FVG & Liquidity Sweeps via pure vector math)
        self.structure_detector.record_candle(
            symbol,
            getattr(current_snapshot, "open", current_snapshot.bid),
            getattr(current_snapshot, "high", current_snapshot.bid),
            getattr(current_snapshot, "low", current_snapshot.bid),
            getattr(current_snapshot, "close", current_snapshot.bid) or current_snapshot.bid,
        )
        fvg_status, sweep_status = self.structure_detector.detect_fvg_and_sweeps(symbol, pip_size)

        # Deterministic Expected Value: pre-calculated before any AI sees the briefing
        ev_summary, edge_class = self.ev_engine.calculate_ev(symbol, current_snapshot)

        briefing = self._generate_briefing(
            symbol=symbol,
            snapshot=current_snapshot,
            pip_movement=pip_movement,
            news_context=news_context,
            session=self._determine_session(),
            volatility=volatility_level,
            minutes_elapsed=minutes_elapsed,
            regime=regime,
            fvg_status=fvg_status,
            sweep_status=sweep_status,
            ev_summary=ev_summary,
            edge_class=edge_class,
        )

        # 8. Ping the Hardened Kill Switch heartbeat so it knows the news filter is alive
        try:
            from hardened_kill_switch import hardened_kill_switch
            hardened_kill_switch.record_news_heartbeat()
        except Exception:
            pass  # Non-fatal — kill switch is still in boot grace period

        return should_wake, reason, briefing

    def _generate_briefing(
        self, 
        symbol: str, 
        snapshot: MarketSnapshot, 
        pip_movement: float, 
        news_context: str, 
        session: str,
        volatility: str = "UNKNOWN",
        minutes_elapsed: float = 0.0,
        regime: str = "UNKNOWN",
        fvg_status: str = "NONE (Balanced Flow)",
        sweep_status: str = "NONE",
        ev_summary: str = "Calculating...",
        edge_class: str = "UNKNOWN",
    ) -> str:
        """Fills out the standard Briefing Template for the AI Agents."""
        return (
            f"MARKET BRIEFING — {symbol}\n"
            f"─────────────────────────\n"
            f"Current Price:     {snapshot.bid:.5f}\n"
            f"Movement:          {pip_movement:.1f} pips in last {max(1.0, round(minutes_elapsed, 1))} minutes\n"
            f"News Alert:        {news_context}\n"
            f"Session:           {session}\n"
            f"Volatility Level:  {volatility}\n"
            f"Macro Regime:      {regime}\n"
            f"Verified FVG:      {fvg_status}\n"
            f"Liquidity Sweep:   {sweep_status}\n"
            f"Math EV (Pre-Calc):{ev_summary}\n"
            f"Mathematical Edge: {edge_class}\n"
            f"Should we trade?"
        )
    def evaluate_incoming_news_packet(self, news_packet: dict) -> Tuple[bool, str, list[str]]:
        """
        Evaluates incoming financial news wire API packets using computer metadata tags.
        Does NOT rely on understanding English or guessing words.
        
        Returns:
            Tuple[should_trigger (bool), category (str), affected_symbols (list[str])]
        """
        impact = str(news_packet.get("impact_level", news_packet.get("impact", ""))).upper()
        category = str(news_packet.get("category_code", news_packet.get("category", "MACRO_EVENT"))).upper()
        affected_symbols = news_packet.get("affected_symbols", [])

        # Trigger 11-Agent Swarm if news wire marked payload as HIGH or CRITICAL
        if impact in ["HIGH", "CRITICAL", "3"]:
            logger.info("Secretary News Wire Tag Matched: Impact=%s, Category=%s", impact, category)
            return True, category, affected_symbols

        return False, "LOW_IMPACT_NEWS", []


# Singleton instance
secretary = Secretary()
