"""
Mehd AI — Economic Calendar Gateway (HARDENED)
================================================
This module tracks high-impact macroeconomic events (NFP, CPI, FOMC, ECB).

DESIGN:
  The calendar has TWO layers of protection:

  1. HARDCODED SCHEDULE (always active, no API key needed):
     NFP, FOMC, CPI, and ECB dates follow publicly known patterns.
     NFP = first Friday of every month at 13:30 UTC.
     FOMC = 8 scheduled dates per year at 19:00 UTC.
     CPI = ~12th of every month at 13:30 UTC.
     ECB = ~6 scheduled dates per year at 13:15 UTC.
     
     These events cause the most violent moves in forex. Blocking
     trades around them is the single highest-value safety feature
     in the system. It costs NOTHING to implement and prevents
     the #1 cause of retail account blowups.

  2. LIVE API (optional — Financial Modeling Prep):
     When ECONOMIC_API_KEY is set, the gateway fetches ALL high-impact
     events from the API and caches them for 4 hours. This catches
     irregular events (emergency rate decisions, speeches, etc.)
     that the hardcoded schedule misses.

  The two layers are ADDITIVE — the hardcoded schedule is never disabled,
  even when the live API is active. Belt AND suspenders.
"""

import os
import logging
import time
from datetime import datetime, timezone, timedelta
from typing import Optional
from calendar import monthcalendar, FRIDAY

logger = logging.getLogger("mehd.economic_calendar")


# ──────────────────────────────────────────────
#  Hardcoded Tier-1 Event Schedule
# ──────────────────────────────────────────────

def _get_first_friday(year: int, month: int) -> int:
    """Returns the day-of-month for the first Friday of the given month."""
    cal = monthcalendar(year, month)
    for week in cal:
        if week[FRIDAY] != 0:
            return week[FRIDAY]
    return 1  # Fallback (should never happen)


def _build_nfp_dates(year: int) -> list[datetime]:
    """NFP (Non-Farm Payrolls): First Friday of every month at 13:30 UTC."""
    dates = []
    for month in range(1, 13):
        day = _get_first_friday(year, month)
        dates.append(datetime(year, month, day, 13, 30, tzinfo=timezone.utc))
    return dates


def _build_cpi_dates(year: int) -> list[datetime]:
    """US CPI: Typically released around the 10th-14th of each month at 13:30 UTC.
    We use the 12th as the best approximation. The live API corrects this."""
    dates = []
    for month in range(1, 13):
        day = min(12, 28)  # 12th of each month
        dates.append(datetime(year, month, day, 13, 30, tzinfo=timezone.utc))
    return dates


# FOMC meeting dates are publicly announced a year in advance.
# These are the announcement times (when the rate decision is released).
# Source: https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm
FOMC_2025 = [
    datetime(2025, 1, 29, 19, 0, tzinfo=timezone.utc),
    datetime(2025, 3, 19, 18, 0, tzinfo=timezone.utc),
    datetime(2025, 5, 7, 18, 0, tzinfo=timezone.utc),
    datetime(2025, 6, 18, 18, 0, tzinfo=timezone.utc),
    datetime(2025, 7, 30, 18, 0, tzinfo=timezone.utc),
    datetime(2025, 9, 17, 18, 0, tzinfo=timezone.utc),
    datetime(2025, 10, 29, 18, 0, tzinfo=timezone.utc),
    datetime(2025, 12, 17, 19, 0, tzinfo=timezone.utc),
]

FOMC_2026 = [
    datetime(2026, 1, 28, 19, 0, tzinfo=timezone.utc),
    datetime(2026, 3, 18, 18, 0, tzinfo=timezone.utc),
    datetime(2026, 5, 6, 18, 0, tzinfo=timezone.utc),
    datetime(2026, 6, 17, 18, 0, tzinfo=timezone.utc),
    datetime(2026, 7, 29, 18, 0, tzinfo=timezone.utc),
    datetime(2026, 9, 16, 18, 0, tzinfo=timezone.utc),
    datetime(2026, 10, 28, 18, 0, tzinfo=timezone.utc),
    datetime(2026, 12, 16, 19, 0, tzinfo=timezone.utc),
]

# ECB Rate Decisions (approximate — always at 13:15 UTC)
ECB_2025 = [
    datetime(2025, 1, 30, 13, 15, tzinfo=timezone.utc),
    datetime(2025, 3, 6, 13, 15, tzinfo=timezone.utc),
    datetime(2025, 4, 17, 12, 15, tzinfo=timezone.utc),
    datetime(2025, 6, 5, 12, 15, tzinfo=timezone.utc),
    datetime(2025, 7, 24, 12, 15, tzinfo=timezone.utc),
    datetime(2025, 9, 11, 12, 15, tzinfo=timezone.utc),
    datetime(2025, 10, 30, 13, 15, tzinfo=timezone.utc),
    datetime(2025, 12, 18, 13, 15, tzinfo=timezone.utc),
]

ECB_2026 = [
    datetime(2026, 1, 22, 13, 15, tzinfo=timezone.utc),
    datetime(2026, 3, 5, 13, 15, tzinfo=timezone.utc),
    datetime(2026, 4, 16, 12, 15, tzinfo=timezone.utc),
    datetime(2026, 6, 4, 12, 15, tzinfo=timezone.utc),
    datetime(2026, 7, 16, 12, 15, tzinfo=timezone.utc),
    datetime(2026, 9, 10, 12, 15, tzinfo=timezone.utc),
    datetime(2026, 10, 29, 13, 15, tzinfo=timezone.utc),
    datetime(2026, 12, 17, 13, 15, tzinfo=timezone.utc),
]


# Which currencies are affected by which events
_CURRENCY_EVENT_MAP = {
    "USD": "nfp,fomc,cpi",     # NFP, FOMC, CPI all affect USD pairs
    "EUR": "ecb",              # ECB affects EUR pairs
    "GBP": "boe",              # BOE affects GBP pairs
    "JPY": "boj",              # BOJ affects JPY pairs
    "AUD": "rba,cpi",          # RBA affects AUD pairs
    "NZD": "rbnz,cpi",         # RBNZ affects NZD pairs
    "CAD": "boc,cpi",          # BOC affects CAD pairs
    "CHF": "snb,cpi",          # SNB affects CHF pairs
    "XAU": "nfp,fomc,cpi",    # Gold moves violently on USD news
    "XAG": "nfp,fomc,cpi",    # Silver moves violently on USD news
    "BTC": "fomc",             # Crypto reacts to FOMC
    "ETH": "fomc",
    "NAS": "fomc,cpi",         # NASDAQ reacts to FOMC and CPI
    "US3": "fomc,cpi",         # US30 (Dow) reacts to FOMC and CPI
}


def _get_affected_currencies(symbol: str) -> list[str]:
    """Extract which currencies from the symbol are sensitive to news."""
    symbol_upper = symbol.upper().replace("/", "")
    affected = []
    for currency in _CURRENCY_EVENT_MAP:
        if currency in symbol_upper:
            affected.append(currency)
    return affected


def _get_hardcoded_events(year: int) -> list[tuple[datetime, str]]:
    """Build all hardcoded events for a given year."""
    events = []
    
    # NFP
    for dt in _build_nfp_dates(year):
        events.append((dt, "NFP"))
    
    # CPI
    for dt in _build_cpi_dates(year):
        events.append((dt, "CPI"))
    
    # FOMC
    fomc_dates = FOMC_2025 if year == 2025 else FOMC_2026 if year == 2026 else []
    for dt in fomc_dates:
        events.append((dt, "FOMC"))
    
    # ECB
    ecb_dates = ECB_2025 if year == 2025 else ECB_2026 if year == 2026 else []
    for dt in ecb_dates:
        events.append((dt, "ECB"))
    
    return events


# ──────────────────────────────────────────────
#  Gateway Class
# ──────────────────────────────────────────────

# ──────────────────────────────────────────────
#  Defensive Normalization Mappings (Multi-API Polyfill)
# ──────────────────────────────────────────────

COUNTRY_TO_CURRENCY_POLYFILL = {
    # United States / USD
    "US": "USD", "USA": "USD", "U.S.": "USD", "U.S.A.": "USD",
    "UNITED STATES": "USD", "UNITED STATES OF AMERICA": "USD", "AMERICA": "USD",
    
    # Eurozone / EUR
    "EU": "EUR", "EUR": "EUR", "EURO": "EUR", "EUROZONE": "EUR", "EURO AREA": "EUR",
    "DE": "EUR", "GERMANY": "EUR", "FR": "EUR", "FRANCE": "EUR", "IT": "EUR", "ITALY": "EUR", "ES": "EUR", "SPAIN": "EUR",
    
    # United Kingdom / GBP
    "GB": "GBP", "UK": "GBP", "U.K.": "GBP", "BRITAIN": "GBP", "GREAT BRITAIN": "GBP", "UNITED KINGDOM": "GBP", "ENGLAND": "GBP",
    
    # Japan / JPY
    "JP": "JPY", "JPN": "JPY", "JAPAN": "JPY",
    
    # Australia / AUD
    "AU": "AUD", "AUS": "AUD", "AUSTRALIA": "AUD",
    
    # Canada / CAD
    "CA": "CAD", "CAN": "CAD", "CANADA": "CAD",
    
    # Switzerland / CHF
    "CH": "CHF", "CHE": "CHF", "SWITZERLAND": "CHF", "SWISS": "CHF",
    
    # New Zealand / NZD
    "NZ": "NZD", "NZL": "NZD", "NEW ZEALAND": "NZD",
    
    # China / CNH (Global Risk Sentiment)
    "CN": "CNH", "CHN": "CNH", "CHINA": "CNH",
}


def is_high_impact_event(event: dict) -> bool:
    """
    Defensively determines if an event is High Impact (Red Folder).
    Handles integers (3), strings ('High', 'Critical', 'Red'), and multi-provider keys.
    """
    raw_val = (
        event.get("importance") or
        event.get("impact") or
        event.get("severity") or
        event.get("priority") or
        event.get("level") or
        ""
    )
    norm = str(raw_val).strip().lower()
    return norm in ("3", "high", "red", "critical", "tier1", "tier-1", "severe", "holiday")


def normalize_event_currency(event: dict) -> str:
    """
    Extracts and normalizes currency from any provider's JSON packet.
    360-Degree Triple-Layer Resolution:
      1. Direct currency ticker (e.g. 'USD', 'EUR')
      2. Country code / name polyfill (46 global variants)
      3. Headline / Central Bank Entity scanner (e.g. 'Fed', 'Powell', 'ECB', 'Lagarde', 'BoJ')
    """
    # 1. Direct currency tag if provided
    direct_curr = str(event.get("currency") or event.get("Currency") or "").strip().upper()
    if direct_curr and len(direct_curr) == 3:
        return direct_curr

    # 2. Country name / code lookup
    country = str(event.get("country") or event.get("Country") or "").strip().upper()
    if country in COUNTRY_TO_CURRENCY_POLYFILL:
        return COUNTRY_TO_CURRENCY_POLYFILL[country]

    # 3. 360° Safety Net: Scan Event Name / Headline for Central Bank & Macro Entities
    text_content = f"{event.get('event', '')} {event.get('headline', '')} {event.get('title', '')}".upper()
    if any(k in text_content for k in ("FED", "FOMC", "POWELL", "NFP", "PAYROLL", "CPI", "PCE", "TREASURY", "US ")):
        return "USD"
    if any(k in text_content for k in ("ECB", "LAGARDE", "EUROZONE", "BUND", "GERMAN")):
        return "EUR"
    if any(k in text_content for k in ("BOE", "BANK OF ENGLAND", "BAILEY", "GILT", "BRITISH")):
        return "GBP"
    if any(k in text_content for k in ("BOJ", "BANK OF JAPAN", "UEDA", "YEN", "JGB")):
        return "JPY"
    if any(k in text_content for k in ("RBA", "RESERVE BANK OF AUSTRALIA", "BULLOCK", "AUSSIE")):
        return "AUD"
    if any(k in text_content for k in ("BOC", "BANK OF CANADA", "MACKLEM", "LOONIE")):
        return "CAD"
    if any(k in text_content for k in ("SNB", "SWISS NATIONAL BANK", "JORDAN")):
        return "CHF"
        
    return direct_curr


class EconomicCalendarGateway:
    """
    Two-layer news protection:
      Layer 1: Hardcoded NFP/FOMC/CPI/ECB schedule (always active)
      Layer 2: Live API from Financial Modeling Prep / TradingEconomics (when API key is set)
    """
    
    def __init__(self):
        self.api_key = (
            os.getenv("ECONOMIC_API_KEY", "").strip()
            or os.getenv("FMP_API_KEY", "").strip()
            or os.getenv("FINNHUB_API_KEY", "").strip()
        )
        self.base_url = "https://financialmodelingprep.com/api/v3/economic_calendar"
        self._is_live = bool(self.api_key)
        
        # Cache for live API results (refreshed every 4 hours)
        self._live_cache: list[dict] = []
        self._cache_timestamp: float = 0
        self._CACHE_TTL = 4 * 60 * 60  # 4 hours
        
        if self._is_live:
            logger.info("EconomicCalendar: LIVE mode — connected to Global Macro Feed + hardcoded schedule.")
        else:
            logger.info(
                "EconomicCalendar: HARDCODED mode — using known NFP/FOMC/CPI/ECB schedule. "
                "Set ECONOMIC_API_KEY / FINNHUB_API_KEY for full live coverage of all events."
            )

    @property
    def is_live(self) -> bool:
        return bool(
            os.getenv("ECONOMIC_API_KEY", "").strip()
            or os.getenv("FMP_API_KEY", "").strip()
            or os.getenv("FINNHUB_API_KEY", "").strip()
        )

    def get_minutes_to_next_high_impact_news(self, symbol: str) -> Optional[int]:
        """
        Calculates the minutes remaining until a Tier-1 news event
        that impacts the given symbol.
        
        Returns:
            int: Minutes away (can be negative if event is happening NOW).
            None: If no high-impact news is scheduled within the next 24 hours.
        """
        now = datetime.now(timezone.utc)
        affected_currencies = _get_affected_currencies(symbol)
        
        if not affected_currencies:
            return None
        
        closest_minutes: Optional[int] = None
        
        # ── LAYER 1: Hardcoded schedule (always active) ──
        hardcoded_events = _get_hardcoded_events(now.year)
        # Also check next year if we're in December
        if now.month == 12:
            hardcoded_events += _get_hardcoded_events(now.year + 1)
        
        for event_time, event_name in hardcoded_events:
            # Check if this event affects the symbol
            event_affects_symbol = False
            for currency in affected_currencies:
                event_types = _CURRENCY_EVENT_MAP.get(currency, "")
                if event_name.lower() in event_types.lower():
                    event_affects_symbol = True
                    break
            
            if not event_affects_symbol:
                continue
            
            # Calculate minutes away
            delta = (event_time - now).total_seconds() / 60
            
            # Only care about events within the next 24 hours
            # and up to 30 minutes AFTER (volatility persists after release)
            if -30 <= delta <= 1440:
                if closest_minutes is None or delta < closest_minutes:
                    closest_minutes = int(delta)
                    logger.debug(
                        "Hardcoded event: %s in %.0f minutes (symbol: %s)",
                        event_name, delta, symbol
                    )
        
        # ── LAYER 2: Live API (if configured) ──
        if self.is_live:
            live_minutes = self._check_live_api(symbol, affected_currencies, now)
            if live_minutes is not None:
                if closest_minutes is None or live_minutes < closest_minutes:
                    closest_minutes = live_minutes
        
        return closest_minutes

    def _check_live_api(self, symbol: str, affected_currencies: list[str], now: datetime) -> Optional[int]:
        """Fetch high-impact events from live API and find the nearest one."""
        # Refresh cache if stale
        if (time.time() - self._cache_timestamp) > self._CACHE_TTL:
            self._refresh_live_cache(now)
        
        closest: Optional[int] = None
        
        for event in self._live_cache:
            # 1. Defensive Impact Check (Handles 3, 'High', 'Red', 'Critical')
            if not is_high_impact_event(event):
                continue
            
            # 2. Defensive Currency & Country Normalization
            event_currency = normalize_event_currency(event)
            
            if event_currency not in [c for c in affected_currencies]:
                # Also check XAU/BTC/NAS sensitivity to USD
                if event_currency == "USD" and any(c in ("XAU", "BTC", "ETH", "NAS", "US3") for c in affected_currencies):
                    pass  # USD events affect gold/crypto/indices
                else:
                    continue
            
            # Parse event time
            try:
                event_dt_str = event.get("date", "")
                event_dt = datetime.fromisoformat(event_dt_str)
                if event_dt.tzinfo is None:
                    event_dt = event_dt.replace(tzinfo=timezone.utc)
                
                delta = (event_dt - now).total_seconds() / 60
                if -30 <= delta <= 1440:
                    if closest is None or delta < closest:
                        closest = int(delta)
                        logger.debug(
                            "Live API event: %s (%s) in %.0f minutes",
                            event.get("event", "Unknown"), event.get("country", "Global"), delta
                        )
            except (ValueError, TypeError):
                continue
        
        return closest

    def _refresh_live_cache(self, now: datetime) -> None:
        """Fetch today's events from Financial Modeling Prep or Finnhub."""
        try:
            import httpx
            today = now.strftime("%Y-%m-%d")
            tomorrow = (now + timedelta(days=1)).strftime("%Y-%m-%d")

            finnhub_key = os.getenv("FINNHUB_API_KEY", "").strip()
            fmp_key = (os.getenv("FMP_API_KEY", "").strip() or os.getenv("ECONOMIC_API_KEY", "").strip())

            events = []
            # 1. Try Finnhub if key is configured
            if finnhub_key:
                try:
                    url = f"https://finnhub.io/api/v1/calendar/economic?from={today}&to={tomorrow}&token={finnhub_key}"
                    resp = httpx.get(url, timeout=10.0)
                    if resp.status_code == 200:
                        data = resp.json()
                        raw_list = data.get("economicCalendar", []) if isinstance(data, dict) else []
                        # Normalize Finnhub format to standard event schema
                        for item in raw_list:
                            events.append({
                                "event": item.get("event") or item.get("title", ""),
                                "date": item.get("time") or item.get("date", ""),
                                "country": item.get("country", ""),
                                "currency": item.get("currency", ""),
                                "impact": item.get("impact", "High"),
                                "actual": item.get("actual"),
                                "estimate": item.get("estimate"),
                                "previous": item.get("previous"),
                            })
                except Exception as fe:
                    logger.debug("Finnhub economic calendar fetch failed: %s", fe)

            # 2. Try FMP if Finnhub produced no events and FMP key exists
            if not events and fmp_key:
                try:
                    url = f"https://financialmodelingprep.com/api/v3/economic_calendar?from={today}&to={tomorrow}&apikey={fmp_key}"
                    resp = httpx.get(url, timeout=10.0)
                    if resp.status_code == 200:
                        data = resp.json()
                        events = data if isinstance(data, list) else []
                except Exception as fme:
                    logger.debug("FMP economic calendar fetch failed: %s", fme)

            if events:
                self._live_cache = events
                self._cache_timestamp = time.time()
                logger.info("EconomicCalendar: Refreshed live cache — %d live events loaded.", len(self._live_cache))
            else:
                self._cache_timestamp = time.time()
                logger.debug("EconomicCalendar: Live check completed, fallback schedule active.")

        except Exception as e:
            logger.warning("EconomicCalendar: Live API fetch failed (%s). Hardcoded schedule still active.", e)
            self._cache_timestamp = time.time()


# Singleton
calendar_gateway = EconomicCalendarGateway()
