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

from models import MarketSnapshot
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
        momentum = (current_price - start_price) / start_price
        
        # Thresholds: > 0.05% move is BULL, < -0.05% is BEAR
        if momentum > 0.0005:
            return "BULL MARKET (High Momentum)"
        elif momentum < -0.0005:
            return "BEAR MARKET (Downward Momentum)"
        else:
            return "CHOPPY / RANGING MARKET"

class Secretary:
    def __init__(self):
        # Default minimum pip movement required to wake agents if no news
        self.min_pip_movement = 5.0
        self.regime_detector = MacroRegimeDetector()
        
    def _get_pip_size(self, symbol: str) -> float:
        """Returns the decimal value of 1 pip for the given symbol."""
        # JPY pairs: pip at second decimal place
        if "JPY" in symbol:
            return 0.01
        # Gold/Silver: pip = 0.01
        elif "XAU" in symbol or "XAG" in symbol:
            return 0.01
        # Crypto: 1 pip = 1 price unit
        elif "BTC" in symbol or "ETH" in symbol:
            return 1.0
        # Indices: 1 pip = 1 index point
        elif "NAS" in symbol or "US30" in symbol or "SPX" in symbol:
            return 1.0
        # Standard forex pairs: pip at fourth decimal place
        else:
            return 0.0001

    def _get_blackswan_pip_threshold(self, symbol: str) -> float:
        """Returns the spike pip threshold that qualifies as a Black Swan for this symbol.
        Different assets have very different normal ranges of movement."""
        if "BTC" in symbol:
            return 500.0   # BTC: 500-point move in 60s is extreme
        elif "ETH" in symbol:
            return 150.0   # ETH: 150-point move in 60s is extreme
        elif "NAS" in symbol or "SPX" in symbol:
            return 100.0   # Nasdaq/S&P: 100-point move in 60s is extreme
        elif "US30" in symbol:
            return 200.0   # Dow Jones: 200-point move in 60s is extreme
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
        
        # Simple session mapping (UTC)
        if 8 <= hour < 12:
            return "London Open"
        elif 12 <= hour < 16:
            return "New York Open / London Overlap"
        elif 16 <= hour < 21:
            return "New York Afternoon"
        elif 21 <= hour < 24 or 0 <= hour < 8:
            return "Asian/Sydney Session"
        return "Unknown Session"

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
        
        # Detect Macro Regime
        regime = self.regime_detector.determine_regime(symbol, current_snapshot.bid)
        
        briefing = self._generate_briefing(
            symbol=symbol,
            snapshot=current_snapshot,
            pip_movement=pip_movement,
            news_context=news_context,
            session=self._determine_session(),
            volatility=volatility_level,
            minutes_elapsed=minutes_elapsed,
            regime=regime
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
        regime: str = "UNKNOWN"
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
