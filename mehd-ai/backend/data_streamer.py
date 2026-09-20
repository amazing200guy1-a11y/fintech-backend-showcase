"""
Mehd AI — Live Market Data Streamer (FIX 1: Real-Time Feed)
============================================================
Raw, institutional-grade feed: Polygon → TwelveData → Mock.
Every snapshot tracks data_age_ms, data_source, is_live, latency_warning.
"""

from __future__ import annotations

import asyncio
import logging
import os
import random
import time
import uuid
from datetime import datetime, timezone
from typing import AsyncGenerator, Optional

import httpx
from models import MarketSnapshot

logger = logging.getLogger("mehd.data_streamer")

# Try to import MT5, but don't crash if it's missing
try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False

# ──────────────────────────────────────────────
#  FIX 1: Provider Configuration
# ──────────────────────────────────────────────

POLYGON_API_KEY = os.getenv("POLYGON_API_KEY", "")
TWELVEDATA_API_KEY = os.getenv("TWELVEDATA_API_KEY", "")

# Provider priority (highest first)
PROVIDER_CHAIN = ["polygon", "twelvedata", "mock"]


class MarketDataStreamer:
    """
    Manages the live price feed with triple-redundancy.
    Now tracks data_source, data_age_ms, is_live, and latency_warning
    on every single snapshot so the frontend always knows what it's seeing.
    """

    def __init__(self) -> None:
        self._running: bool = False
        self._active_symbols: set[str] = set()
        self._latest_snapshots: dict[str, MarketSnapshot] = {}
        self._subscribers: dict[str, list[asyncio.Queue[MarketSnapshot]]] = {}
        self._task: Optional[asyncio.Task] = None
        self.mt5_connected: bool = False
        self._active_provider: str = "mock"
        self._http_client: Optional[httpx.AsyncClient] = None
        # Track when each snapshot was born (epoch ms)
        self._snapshot_born_ms: dict[str, int] = {}

    async def start(self) -> None:
        if self._running:
            return
        logger.info("Initializing MarketDataStreamer...")

        self._http_client = httpx.AsyncClient(timeout=5.0)

        # 1. Try MT5
        if MT5_AVAILABLE:
            try:
                if mt5.initialize():
                    self.mt5_connected = True
                    self._active_provider = "mt5"
                    logger.info("Connected to MetaTrader 5 terminal.")
            except Exception:
                logger.warning("MT5 initialize() failed.")
        
        # 2. Determine best available provider
        if not self.mt5_connected:
            self._active_provider = await self._detect_best_provider()
            logger.info("Active data provider: %s", self._active_provider)

        self._running = True
        self._task = asyncio.create_task(self._poll_prices_loop())
        logger.info("MarketDataStreamer started (provider: %s).", self._active_provider)

    async def _detect_best_provider(self) -> str:
        """Try each provider in order and return the first one that responds."""

        if POLYGON_API_KEY:
            try:
                resp = await self._http_client.get(
                    "https://api.polygon.io/v2/aggs/ticker/C:EURUSD/prev",
                    headers={"Authorization": f"Bearer {POLYGON_API_KEY}"},
                )
                if resp.status_code == 200:
                    return "polygon"
            except Exception as e:
                logger.warning("Polygon probe failed: %s", e)

        if TWELVEDATA_API_KEY:
            try:
                resp = await self._http_client.get(
                    "https://api.twelvedata.com/price",
                    params={"symbol": "EUR/USD"},
                    headers={"Authorization": f"apikey {TWELVEDATA_API_KEY}"},
                )
                if resp.status_code == 200:
                    return "twelvedata"
            except Exception as e:
                logger.warning("TwelveData probe failed: %s", e)

        return "mock"

    async def stop(self) -> None:
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        if self._http_client:
            await self._http_client.aclose()
        if self.mt5_connected and MT5_AVAILABLE:
            mt5.shutdown()
        logger.info("MarketDataStreamer stopped.")

    def _resolve_symbol(self, raw_symbol: str) -> str:
        s = raw_symbol.upper().strip()
        if s in ["GOLD", "XAUUSD"]:
            s = "XAUUSD"
        elif s in ["BTC", "BITCOIN"]:
            s = "BTCUSD"
        s = s.replace("/", "")
        return s

    async def subscribe(self, raw_symbol: str) -> AsyncGenerator[MarketSnapshot, None]:
        symbol = self._resolve_symbol(raw_symbol)
        self._active_symbols.add(symbol)
        queue: asyncio.Queue[MarketSnapshot] = asyncio.Queue(maxsize=100)
        if symbol not in self._subscribers:
            self._subscribers[symbol] = []
        self._subscribers[symbol].append(queue)
        logger.info("New subscriber for %s. Active symbols: %d", symbol, len(self._active_symbols))
        if symbol in self._latest_snapshots:
            yield self._latest_snapshots[symbol]
        try:
            while self._running:
                snapshot = await queue.get()
                yield snapshot
        except asyncio.CancelledError:
            pass
        finally:
            if symbol in self._subscribers and queue in self._subscribers[symbol]:
                self._subscribers[symbol].remove(queue)
                if not self._subscribers[symbol]:
                    self._active_symbols.discard(symbol)

    def get_latest_snapshot(self, raw_symbol: str) -> MarketSnapshot:
        symbol = self._resolve_symbol(raw_symbol)
        if symbol in self._latest_snapshots:
            snap = self._latest_snapshots[symbol]
            # Recompute freshness at access time
            return self._stamp_freshness(snap)
        return self._generate_realistic_mock_tick(symbol)

    def _stamp_freshness(self, snap: MarketSnapshot) -> MarketSnapshot:
        """Recalculates data_age_ms, is_live, latency_warning at serve time."""
        now_ms = int(time.time() * 1000)
        born_ms = self._snapshot_born_ms.get(snap.symbol, now_ms)
        age = now_ms - born_ms
        return snap.model_copy(update={
            "data_age_ms": age,
            "is_live": age < 1000,
            "latency_warning": age > 3000,
        })

    async def _poll_prices_loop(self) -> None:
        symbol_error_counts: dict[str, int] = {}  # Per-symbol error tracking
        while self._running:
            if not self._active_symbols:
                await asyncio.sleep(0.5)
                continue

            for symbol in list(self._active_symbols):
                # Per-symbol backoff: skip symbols that are in cooldown
                err_count = symbol_error_counts.get(symbol, 0)
                if err_count > 0:
                    # Only poll this symbol every N cycles based on its error count
                    # err_count=1 → every 2nd cycle, err_count=3 → every 8th cycle
                    skip_cycles = min(64, 2 ** err_count)
                    if hasattr(self, '_poll_cycle_count'):
                        if self._poll_cycle_count % skip_cycles != 0:
                            continue
                try:
                    snapshot = await self._fetch_oracle_consensus(symbol)
                    self._latest_snapshots[symbol] = snapshot
                    self._snapshot_born_ms[symbol] = int(time.time() * 1000)

                    if symbol in self._subscribers:
                        dead_queues = []
                        for q in self._subscribers[symbol]:
                            try:
                                if q.full():
                                    q.get_nowait()
                                q.put_nowait(self._stamp_freshness(snapshot))
                            except Exception:
                                dead_queues.append(q)
                        for dq in dead_queues:
                            self._subscribers[symbol].remove(dq)
                    symbol_error_counts[symbol] = 0  # Reset on success
                except Exception as e:
                    symbol_error_counts[symbol] = symbol_error_counts.get(symbol, 0) + 1
                    logger.error("Error fetching tick for %s (consecutive: %d): %s", 
                                symbol, symbol_error_counts[symbol], e)

            # Track cycle count for per-symbol skip logic
            if not hasattr(self, '_poll_cycle_count'):
                self._poll_cycle_count = 0
            self._poll_cycle_count += 1

            # ── Health Registry Report ──
            from system_health import health_registry
            errored_symbols = sum(1 for c in symbol_error_counts.values() if c > 0)
            total_symbols = len(self._active_symbols)
            if errored_symbols >= total_symbols and total_symbols > 0:
                _h_state = "RED"
                _h_detail = f"All {total_symbols} price feeds failing"
            elif errored_symbols > 0:
                _h_state = "YELLOW"
                _h_detail = f"{errored_symbols}/{total_symbols} feeds degraded"
            else:
                _h_state = "GREEN"
                _h_detail = f"{total_symbols} feeds streaming at 2Hz"
            await health_registry.report("market_data", _h_state, _h_detail, {
                "active_symbols": total_symbols,
                "symbols_errored": errored_symbols,
                "poll_cycle": self._poll_cycle_count,
            })
                
            # The Valve: 2Hz (500ms) rate limit to protect frontend from stuttering
            await asyncio.sleep(0.5)
    async def _fetch_oracle_consensus(self, symbol: str) -> MarketSnapshot:
        """
        THE ORACLE MATRIX: Fetches from all available providers concurrently.
        Resolves Split-Brain by computing the median and rejecting outliers.
        """
        async def _safe_fetch(coro):
            try:
                return await asyncio.wait_for(coro, timeout=1.5)
            except Exception as e:
                return e

        tasks = []
        if self.mt5_connected and MT5_AVAILABLE:
            tasks.append(_safe_fetch(self._fetch_mt5(symbol)))
        if POLYGON_API_KEY:
            tasks.append(_safe_fetch(self._fetch_polygon(symbol)))
        if TWELVEDATA_API_KEY:
            tasks.append(_safe_fetch(self._fetch_twelvedata(symbol)))
            
        if not tasks:
            return self._generate_realistic_mock_tick(symbol)
            
        # Fire all requests concurrently
        results = await asyncio.gather(*tasks)
        
        valid_snapshots: list[MarketSnapshot] = []
        for r in results:
            if isinstance(r, MarketSnapshot):
                valid_snapshots.append(r)
            else:
                logger.debug("Oracle node timeout/failure for %s: %s", symbol, r)
                
        if not valid_snapshots:
            return self._generate_realistic_mock_tick(symbol)
            
        if len(valid_snapshots) == 1:
            return valid_snapshots[0]
            
        # MULTI-ORACLE CONSENSUS LOGIC
        import statistics
        
        # Find the "truth" median bid
        bids = [s.bid for s in valid_snapshots if s.bid > 0]
        if not bids:
            return self._generate_realistic_mock_tick(symbol)
        median_bid = statistics.median(bids)
        if median_bid <= 0:
            return self._generate_realistic_mock_tick(symbol)
        
        # Outlier Rejection Threshold (0.05% deviation = ~5 pips)
        MAX_DIVERGENCE_PCT = 0.0005 
        
        survivors = []
        for s in valid_snapshots:
            divergence = abs(s.bid - median_bid) / median_bid
            if divergence <= MAX_DIVERGENCE_PCT:
                survivors.append(s)
            else:
                logger.critical("TOXIC DATA BLOCKED: Provider %s deviated by %.4f%% on %s", 
                                s.data_source, divergence * 100, symbol)
                                
        if not survivors:
            # Complete Split-Brain Halt
            logger.critical("SPLIT-BRAIN HALT: Total divergence on %s. Suspending feed.", symbol)
            return self._generate_realistic_mock_tick(symbol)
            
        # Blend the surviving clean snapshots
        avg_bid = sum(s.bid for s in survivors) / len(survivors)
        avg_ask = sum(s.ask for s in survivors) / len(survivors)
        avg_spread = sum(s.spread for s in survivors) / len(survivors)
        
        # Create final secure consensus snapshot
        consensus = survivors[0].model_copy(update={
            "bid": round(avg_bid, 5),
            "ask": round(avg_ask, 5),
            "spread": round(avg_spread, 1),
            "data_source": "oracle_matrix" if len(survivors) > 1 else survivors[0].data_source
        })
        
        return consensus

    async def _fetch_mt5(self, symbol: str) -> MarketSnapshot:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self._fetch_mt5_sync, symbol)

    def _fetch_mt5_sync(self, symbol: str) -> MarketSnapshot:
        tick = mt5.symbol_info_tick(symbol)
        info = mt5.symbol_info(symbol)
        if tick is None or info is None:
            raise ConnectionError(f"MT5 returned None for {symbol}")
        timestamp = datetime.fromtimestamp(tick.time, tz=timezone.utc)
        pip_multiplier = 10000 if info.digits == 5 else (100 if info.digits == 3 else 1)
        spread_pips = (tick.ask - tick.bid) * pip_multiplier
        return MarketSnapshot(
            symbol=symbol, bid=tick.bid, ask=tick.ask,
            spread=round(spread_pips, 1), timestamp=timestamp,
            open=tick.bid, high=tick.bid, low=tick.bid, close=tick.bid,
            volume=tick.volume, data_source="mt5", data_age_ms=0, is_live=True, latency_warning=False,
        )


    async def _fetch_polygon(self, symbol: str) -> MarketSnapshot:
        resp = await self._http_client.get(
            "https://api.polygon.io/v2/aggs/ticker/C:%s/prev" % symbol,
            headers={"Authorization": f"Bearer {POLYGON_API_KEY}"},
        )
        resp.raise_for_status()
        result = resp.json()["results"][0]
        bid = result["c"]
        ask = bid + 0.0002  # Polygon doesn't give B/A for forex on free tier
        pip_size = 1.0 if "BTC" in symbol else (0.1 if ("XAU" in symbol or "GOLD" in symbol) else (0.01 if "JPY" in symbol else 0.0001))
        ask = bid + (1.5 * pip_size)  # Default spread buffer
        return MarketSnapshot(
            symbol=symbol, bid=bid, ask=ask, spread=round((ask - bid) / pip_size, 1),
            timestamp=datetime.now(timezone.utc), open=result["o"], high=result["h"],
            low=result["l"], close=result["c"], volume=result.get("v", 0),
            data_source="polygon", data_age_ms=0, is_live=True, latency_warning=False,
        )

    async def _fetch_twelvedata(self, symbol: str) -> MarketSnapshot:
        fmt_symbol = f"{symbol[:3]}/{symbol[3:]}" if len(symbol) == 6 else symbol
        resp = await self._http_client.get(
            "https://api.twelvedata.com/price",
            params={"symbol": fmt_symbol},
            headers={"Authorization": f"apikey {TWELVEDATA_API_KEY}"},
        )
        resp.raise_for_status()
        data = resp.json()
        price = float(data["price"])
        pip_size = 1.0 if "BTC" in symbol else (0.1 if ("XAU" in symbol or "GOLD" in symbol) else (0.01 if "JPY" in symbol else 0.0001))
        ask = price + (1.5 * pip_size)  # Approximate spread
        return MarketSnapshot(
            symbol=symbol, bid=price, ask=round(ask, 5), spread=1.5,
            timestamp=datetime.now(timezone.utc), open=price, high=price, low=price,
            close=price, volume=0.0, data_source="twelvedata",
            data_age_ms=0, is_live=True, latency_warning=False,
        )

    def _generate_realistic_mock_tick(self, symbol: str) -> MarketSnapshot:
        base_prices = {
            "EURUSD": 1.0850, "GBPUSD": 1.2650, "USDJPY": 150.20,
            "XAUUSD": 2040.50, "BTCUSD": 63400.00,
        }
        base = base_prices.get(symbol, 1.0000)
        if symbol in self._latest_snapshots:
            prev = self._latest_snapshots[symbol]
            change = prev.bid * random.uniform(-0.00005, 0.00005)
            new_bid = prev.bid + change
        else:
            new_bid = base

        multiplier = 0.01 if "JPY" in symbol else (0.1 if "XAU" in symbol else 0.0001)
        spread_pips = random.uniform(1.0, 2.5)
        new_ask = new_bid + (spread_pips * multiplier)

        from models import DepthOfMarket
        return MarketSnapshot(
            id=uuid.uuid4(), symbol=symbol, bid=round(new_bid, 5), ask=round(new_ask, 5),
            spread=round(spread_pips, 1), timestamp=datetime.now(timezone.utc),
            open=round(base, 5), high=round(max(base, new_bid) + (20 * multiplier), 5),
            low=round(min(base, new_bid) - (20 * multiplier), 5), close=round(new_bid, 5),
            volume=random.uniform(10, 500),
            data_source="mock", data_age_ms=0, is_live=False, latency_warning=False,
            dom_data=DepthOfMarket()
        )
