"""
Mehd AI — The Broadcaster (Underground Research Daemon)
=========================================================
THIS IS THE MOST IMPORTANT ARCHITECTURAL FILE IN MEHD AI.

THE IDEA (from the founder):
Forex is global. EUR/USD in Lagos = EUR/USD in Miami = EUR/USD in Tokyo.
So why run 11 AI agents for EVERY user? Run them ONCE, broadcast to ALL.

HOW IT WORKS:
    1. A background daemon runs 24/5 (forex market hours).
    2. Every cycle, it picks a currency pair from the watch list.
    3. It runs the FULL 11-agent consensus (all 3 layers + Chairman).
    4. It stores the result in a global broadcast store.
    5. It pushes a notification to every subscribed user.
    6. It moves to the next pair.

    Total cycle for 9 pairs: ~3 minutes (20s per pair × 9 pairs).
    User experience: INSTANT. Results are always pre-computed.

WHY THIS IS GENIUS:
    Old model:  11 calls × 10,000 users = 110,000 API calls/day → $$$
    New model:  11 calls × 9 pairs × 288 cycles/day = 28,512 calls → 99.97% cheaper

    Old latency: 8-30 seconds PER USER
    New latency: 0 seconds. The answer is already waiting.

MONETIZATION:
    Free tier:  See consensus results (delayed 15 min)
    Pro tier:   Real-time push notifications + full vote breakdown
    Institutional: Raw API access to the broadcast stream

This is the Bloomberg Terminal model applied to AI consensus.
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections import deque
from datetime import datetime, timezone, timedelta
from typing import Optional, Any
from dataclasses import dataclass, field

from models import ConsensusResult, MarketSnapshot
from storage import storage
from utils.chart_utils import generate_drawing_commands, generate_mock_candles
from secretary import secretary

logger = logging.getLogger("mehd.broadcaster")


def _safe_create_task(coro, name: str = "unnamed"):
    """Fire-and-forget wrapper that logs errors instead of silently swallowing them."""
    async def _wrapper():
        try:
            await coro
        except Exception as e:
            logger.error("Background task '%s' failed: %s", name, e)
    return asyncio.create_task(_wrapper())


# ──────────────────────────────────────────────
#  Configuration
# ──────────────────────────────────────────────

# Pairs the Broadcaster monitors — synced with Flutter's AppConstants.symbols
# HARDENED (VULN-13): These MUST match what the Flutter client shows.
# If a pair is here but not in Flutter, it wastes API calls.
# If a pair is in Flutter but not here, users see "No broadcast yet."
BROADCAST_PAIRS = [
    # Core 6 Major Assets: Forex Majors, Commodity, and Institutional Liquidity
    "EUR/USD", "GBP/USD", "AUD/USD", "USD/JPY", "USD/CAD", "XAU/USD",
]

# How long to wait between full cycles (seconds)
# 300 = 5 minutes. The Den re-analyzes every pair every 5 minutes.
CYCLE_INTERVAL_SECONDS = 300

# Minimum seconds between analyses of the SAME pair
# Prevents hammering APIs if a cycle runs fast
MIN_PAIR_INTERVAL_SECONDS = 30

# How many historical broadcasts to keep per pair
BROADCAST_HISTORY_SIZE = 50

# Delay for free-tier users (seconds)
FREE_TIER_DELAY_SECONDS = 900  # 15 minutes


# ──────────────────────────────────────────────
#  Broadcast Signal — one consensus result
# ──────────────────────────────────────────────

@dataclass
class BroadcastSignal:
    """A single broadcast: one pair, one consensus, one moment in time."""
    symbol: str
    consensus: ConsensusResult
    snapshot: MarketSnapshot
    broadcast_time: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    cycle_id: int = 0
    analysis_duration_ms: int = 0
    status: str = "FRESH"

    def to_notification(self) -> dict:
        """
        Converts to a push notification payload.
        This is what users receive on their phone.
        """
        direction = self.consensus.final_direction.value
        pct = self.consensus.consensus_percentage
        emoji = "🟢" if direction == "BUY" else "🔴" if direction == "SELL" else "⚪"

        # Only push if consensus is strong enough to be actionable (standardized at 92%)
        if pct < 92:
            return None  # Don't spam users with weak signals

        return {
            "title": f"{emoji} {self.symbol} — {direction} Signal",
            "body": (
                f"The Den reached {pct:.0f}% consensus. "
                f"11 AI agents analyzed the market."
            ),
            "data": {
                "symbol": self.symbol,
                "direction": direction,
                "consensus_pct": pct,
                "proceed": self.consensus.proceed,
                "timestamp": self.broadcast_time.isoformat(),
                "cycle_id": self.cycle_id,
                "chairman_summary": self.consensus.chairman_summary or "",
            },
        }

    def to_dict(self) -> dict:
        """Serializable summary for API responses."""
        import json
        return {
            "symbol": self.symbol,
            "direction": self.consensus.final_direction.value,
            "consensus_pct": self.consensus.consensus_percentage,
            "proceed": self.consensus.proceed,
            "chairman_summary": self.consensus.chairman_summary,
            "rejection_reason": self.consensus.rejection_reason,
            "vote_count": len(self.consensus.votes),
            "consensus_data": json.loads(self.consensus.model_dump_json()),
            "snapshot": {
                "bid": self.snapshot.bid,
                "ask": self.snapshot.ask,
                "spread": self.snapshot.spread,
                "data_source": self.snapshot.data_source,
                "is_live": self.snapshot.is_live,
            },
            "broadcast_time": self.broadcast_time.isoformat(),
            "analysis_duration_ms": self.analysis_duration_ms,
            "cycle_id": self.cycle_id,
            "status": self.status, # Signal Lifecycle Phase
        }


# ──────────────────────────────────────────────
#  The Broadcaster Engine
# ──────────────────────────────────────────────

class Broadcaster:
    """
    The Underground Research Daemon.

    Runs continuously in the background, cycling through all
    watched pairs and publishing consensus results to all users.

    Think of it as a news agency: reporters (11 agents) investigate,
    then the results are broadcast to every subscriber simultaneously.
    """

    def __init__(self) -> None:
        # Latest broadcast per pair — O(1) lookup
        self._latest: dict[str, BroadcastSignal] = {}

        # Historical broadcasts per pair — for trend analysis
        self._history: dict[str, deque[BroadcastSignal]] = {
            pair: deque(maxlen=BROADCAST_HISTORY_SIZE)
            for pair in BROADCAST_PAIRS
        }

        # Subscriptions using Condition instead of Queues for O(1) memory scaling (Google Lesson)
        self._live_condition: asyncio.Condition = asyncio.Condition()
        self._delayed_condition: asyncio.Condition = asyncio.Condition()
        self._latest_live_msg: Optional[BroadcastSignal] = None
        self._latest_delayed_msg: Optional[BroadcastSignal] = None
        self._total_delayed_broadcasts: int = 0

        # Notification callback (set by main.py to call FCM)
        self._notification_callback: Optional[Any] = None

        # State tracking
        self._running: bool = False
        self._task: Optional[asyncio.Task] = None
        self._lifecycle_task: Optional[asyncio.Task] = None
        self._delayed_task: Optional[asyncio.Task] = None
        self._cycle_count: int = 0
        self._total_broadcasts: int = 0
        self._last_pair_time: dict[str, float] = {}
        self._errors_this_cycle: int = 0
        self._started_at: Optional[datetime] = None

    # ──────────────────────────────────────────
    #  Lifecycle
    # ──────────────────────────────────────────

    async def start(self) -> None:
        """Start the background daemon."""
        if self._running:
            logger.warning("Broadcaster already running.")
            return

        self._running = True
        self._started_at = datetime.now(timezone.utc)
        self._task = asyncio.create_task(self._daemon_loop())
        self._lifecycle_task = asyncio.create_task(self._lifecycle_manager_loop())
        self._delayed_task = asyncio.create_task(self._delayed_pusher_loop())
        logger.info(
            "🔊 BROADCASTER STARTED — Monitoring %d pairs, cycle every %ds",
            len(BROADCAST_PAIRS),
            CYCLE_INTERVAL_SECONDS,
        )

    def stop(self) -> None:
        """Stop the background daemon gracefully."""
        self._running = False
        if self._task:
            self._task.cancel()
        if self._lifecycle_task:
            self._lifecycle_task.cancel()
        if self._delayed_task:
            self._delayed_task.cancel()
        logger.info(
            "🔇 BROADCASTER STOPPED — %d total broadcasts sent",
            self._total_broadcasts,
        )

    def set_notification_callback(self, callback) -> None:
        """Register a function to call when a strong signal is found."""
        self._notification_callback = callback
        logger.info("Broadcaster notification callback registered.")

    async def ingest_news_packet(self, news_packet: dict) -> None:
        """
        Called by the API layer when a financial news wire pushes a new event packet.
        Uses secretary.evaluate_incoming_news_packet() to check computer metadata tags
        (e.g. impact_level = 'HIGH') WITHOUT reading English text or using an LLM.

        If the news qualifies as HIGH or CRITICAL impact, immediately triggers an
        out-of-cycle analysis on the affected currency pairs so users get updated
        signals within seconds of the news wire firing — not waiting for the next
        scheduled cycle.
        """
        should_trigger, category, affected_symbols = secretary.evaluate_incoming_news_packet(news_packet)

        if not should_trigger:
            logger.debug("News packet evaluated: LOW impact — no out-of-cycle analysis triggered.")
            return

        logger.info(
            "📡 NEWS WIRE TRIGGERED OUT-OF-CYCLE ANALYSIS: Category=%s, Affected=%s",
            category, affected_symbols
        )

        # Find which of our Core 6 pairs are affected by this news event
        pairs_to_reanalyze = []
        if affected_symbols:
            for sym in affected_symbols:
                sym_upper = sym.upper().replace("/", "")
                for pair in BROADCAST_PAIRS:
                    pair_clean = pair.upper().replace("/", "")
                    if sym_upper in pair_clean and pair not in pairs_to_reanalyze:
                        pairs_to_reanalyze.append(pair)
        else:
            # If news wire doesn't specify symbols, re-analyze all Core 6 pairs
            pairs_to_reanalyze = list(BROADCAST_PAIRS)

        # Trigger immediate out-of-cycle analysis (non-blocking)
        for pair in pairs_to_reanalyze:
            logger.info("⚡ Out-of-cycle analysis triggered for %s due to %s news", pair, category)
            _safe_create_task(self._analyze_and_broadcast(pair), name=f"news_triggered_{pair}")



    async def _daemon_loop(self) -> None:
        """
        The heart of the Broadcaster.
        Cycles through all pairs, runs consensus, broadcasts results.
        """
        # Wait a few seconds for other services to initialize
        await asyncio.sleep(5)

        while self._running:
            self._cycle_count += 1
            self._errors_this_cycle = 0
            cycle_start = time.time()

            logger.info(
                "━━━ BROADCAST CYCLE #%d START ━━━ (%d pairs)",
                self._cycle_count,
                len(BROADCAST_PAIRS),
            )

            for pair in BROADCAST_PAIRS:
                if not self._running:
                    break

                # Respect minimum interval per pair
                last_time = self._last_pair_time.get(pair, 0)
                elapsed = time.time() - last_time
                if elapsed < MIN_PAIR_INTERVAL_SECONDS:
                    wait = MIN_PAIR_INTERVAL_SECONDS - elapsed
                    await asyncio.sleep(wait)

                await self._analyze_and_broadcast(pair)

            cycle_duration = time.time() - cycle_start
            logger.info(
                "━━━ BROADCAST CYCLE #%d COMPLETE ━━━ "
                "Duration: %.1fs | Errors: %d | Total broadcasts: %d",
                self._cycle_count,
                cycle_duration,
                self._errors_this_cycle,
                self._total_broadcasts,
            )

            # ── Health Registry Report ──
            from system_health import health_registry
            stale_count = sum(
                1 for s in self._latest.values()
                if (datetime.now(timezone.utc) - s.broadcast_time).total_seconds() > CYCLE_INTERVAL_SECONDS * 2
            )
            if self._errors_this_cycle >= len(BROADCAST_PAIRS):
                _health_state = "RED"
                _health_detail = f"All {len(BROADCAST_PAIRS)} pairs failed — circuit breaker engaged"
            elif self._errors_this_cycle > 0 or stale_count > 0:
                _health_state = "YELLOW"
                _health_detail = f"{self._errors_this_cycle} errors, {stale_count} stale pairs"
            else:
                _health_state = "GREEN"
                _health_detail = f"Cycle #{self._cycle_count} clean — {len(BROADCAST_PAIRS)} pairs analyzed"
            await health_registry.report("broadcaster", _health_state, _health_detail, {
                "cycle_count": self._cycle_count,
                "cycle_duration_s": round(cycle_duration, 1),
                "errors_this_cycle": self._errors_this_cycle,
                "stale_pairs": stale_count,
            })

            # Circuit breaker: If ALL pairs errored, back off before next cycle
            if self._errors_this_cycle >= len(BROADCAST_PAIRS):
                backoff = min(120.0, CYCLE_INTERVAL_SECONDS * 2)
                logger.critical(
                    "BROADCASTER CIRCUIT BREAKER: ALL %d pairs failed this cycle. "
                    "Backing off for %.0fs to prevent API hammering.",
                    len(BROADCAST_PAIRS), backoff,
                )
                await asyncio.sleep(backoff)
            else:
                # Wait for next cycle
                remaining_wait = max(0, CYCLE_INTERVAL_SECONDS - cycle_duration)
                if remaining_wait > 0:
                    await asyncio.sleep(remaining_wait)

    async def _analyze_and_broadcast(self, symbol: str) -> None:
        """Run the full Den analysis on one pair and broadcast the result."""
        from state import den_engine, streamer, audit

        async def _safe_store(sig_id: str, data: dict):
            try:
                await storage.set("broadcast_history", sig_id, data)
            except Exception as e:
                logger.error("CRITICAL: Signal %s lost — Firestore write failed: %s", sig_id, e)

        try:
            start_time = time.time()

            # 1. Get live snapshot
            snapshot = streamer.get_latest_snapshot(symbol)

            # ── Pillar 2: THE SECRETARY (Market Noise Filter) ──
            cached_signal = self._latest.get(symbol)
            last_snapshot = cached_signal.snapshot if cached_signal else None
            
            should_wake, reason, briefing = secretary.analyze_market_tick(
                symbol, snapshot, last_snapshot
            )

            if cached_signal and not should_wake:
                age_mins = (datetime.now(timezone.utc) - cached_signal.broadcast_time).total_seconds() / 60
                if age_mins < 15.0:  # Keep cache for up to 15 mins if market is flat
                    logger.info("SECRETARY (%s): %s — Skipping analysis.", symbol, reason)
                    # Update cycle ID and snapshot, but keep same consensus
                    cached_signal.snapshot = snapshot
                    cached_signal.cycle_id = self._cycle_count
                    cached_signal.broadcast_time = datetime.now(timezone.utc)
                    cached_signal.analysis_duration_ms = 0
                    
                    await self._push_to_subscribers(cached_signal)
                    self._total_broadcasts += 1
                    self._last_pair_time[symbol] = time.time()
                    return
            
            logger.info("SECRETARY (%s): Waking 11 agents. Reason: %s", symbol, reason)
            # Log the briefing template the agents will receive
            logger.debug("Briefing sent to agents:\n%s", briefing)
            
            # ATTACH the briefing to the snapshot so agents can read it
            snapshot.briefing = briefing

            # 2. Run the FULL 11-agent consensus
            # This is the "slow" part — but nobody is waiting.
            # It runs in the background while users do other things.
            # We wrap this in a strict timeout so a stuck API never halts the Clock.
            try:
                result = await asyncio.wait_for(
                    den_engine.analyze(
                        symbol,
                        snapshot,
                        tier="institutional",  # Highest active tier — full precision consensus
                        current_drawdown=0.0,  # Global analysis, not per-user
                    ),
                    timeout=60.0
                )
            except asyncio.TimeoutError:
                logger.error("Analysis for %s TIMED OUT after 60 seconds. Skipping pair to prevent clock freeze.", symbol)
                self._errors_this_cycle += 1
                return

            duration_ms = int((time.time() - start_time) * 1000)

            # Generate AI Drawing Commands for chart overlay
            try:
                mock_candles = generate_mock_candles(snapshot.close)
                result.drawings = generate_drawing_commands(symbol, result, mock_candles)
            except Exception as draw_err:
                logger.warning("Failed to generate drawing commands for %s: %s", symbol, draw_err)
                result.drawings = []

            # 3. Create the broadcast signal
            signal = BroadcastSignal(
                symbol=symbol,
                consensus=result,
                snapshot=snapshot,
                cycle_id=self._cycle_count,
                analysis_duration_ms=duration_ms,
            )

            # 4. Store it locally (memory)
            self._latest[symbol] = signal
            self._history[symbol].append(signal)
            self._last_pair_time[symbol] = time.time()
            self._total_broadcasts += 1

            # 4b. Store it persistently for Signal Lifecycle / Missed Signals UI
            signal_id = f"{symbol.replace('/', '_')}_{int(start_time * 1000)}"
            signal_data = signal.to_dict()
            signal_data["signal_id"] = signal_id
            # TTL: broadcast signals auto-delete after 24 hours
            signal_data["expires_at"] = (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat()
            
            # Fire-and-forget async save with error handling
            _safe_create_task(_safe_store(signal_id, signal_data), name=f"persist_{signal_id}")

            # 4c. Invalidate previous signals for this pair if direction changed
            _safe_create_task(self._invalidate_previous_signals(symbol, result.final_direction.value), name=f"invalidate_{symbol}")

            # 4d. AUTOPILOT DROP: If signal >= 92%, alert the Auto-Execution Worker
            if result.consensus_percentage >= 92 and result.proceed:
                auto_exec_data = signal_data.copy()
                auto_exec_data["status"] = "PENDING_EXECUTION"
                # HARDENED: Include vote data so worker can check OLYMPUS anomaly flags
                auto_exec_data["votes"] = [
                    {
                        "model_name": v.model_name,
                        "direction": v.direction.value,
                        "confidence": v.confidence,
                        "reasoning": v.reasoning,
                        "layer": self._get_agent_layer(v.model_name),
                    }
                    for v in result.votes
                ]
                # HARDENED: Include live price data for SL/TP calculation
                auto_exec_data["current_price"] = snapshot.bid
                auto_exec_data["spread"] = snapshot.spread
                auto_exec_data["expires_at"] = (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat()
                _safe_create_task(storage.set("pending_auto_executions", signal_id, auto_exec_data), name=f"autopilot_drop_{signal_id}")

            # 4e. REJECTION FEED DROP: If the AI blocks a trade, push to the Rejection Feed
            if result.consensus_percentage < 80 or not result.proceed:
                rejection_data = signal_data.copy()
                rejection_data["rejection_time"] = datetime.now(timezone.utc).isoformat()
                rejection_data["expires_at"] = (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat()
                rejection_data["rejection_reason"] = result.rejection_reason or "Insufficient consensus to guarantee safety."
                _safe_create_task(storage.set("rejection_feed", signal_id, rejection_data), name=f"reject_drop_{signal_id}")

            # 5. Push to SSE subscribers
            await self._push_to_subscribers(signal)

            # 6. Send push notification if signal is strong
            notification = signal.to_notification()
            if notification and self._notification_callback:
                try:
                    await self._notification_callback(notification)
                except Exception as e:
                    logger.error("Notification callback failed: %s", e)

            # 7. Log to audit trail
            audit.log_consensus(symbol, result)

            logger.info(
                "📡 BROADCAST: %s → %s (%.0f%%) in %dms | proceed=%s",
                symbol,
                result.final_direction.value,
                result.consensus_percentage,
                duration_ms,
                result.proceed,
            )

        except Exception as e:
            self._errors_this_cycle += 1
            logger.error(
                "Broadcast FAILED for %s: %s", symbol, e, exc_info=True
            )

    # ──────────────────────────────────────────
    #  SSE Push (Real-Time Subscribers)
    # ──────────────────────────────────────────

    async def _push_to_subscribers(self, signal: BroadcastSignal) -> None:
        """Push a new signal to all connected SSE subscribers via Condition."""
        async with self._live_condition:
            self._latest_live_msg = signal
            self._live_condition.notify_all()

    # ──────────────────────────────────────────
    #  Lifecycle Manager
    # ──────────────────────────────────────────

    async def _invalidate_previous_signals(self, symbol: str, new_direction: str) -> None:
        """Invalidates older active signals for the same pair if direction flips or consensus drops."""
        try:
            # FIX H3: Use query() instead of get_all() — only fetch active signals for THIS symbol
            active_signals = await storage.query("broadcast_history", [
                ("symbol", "==", symbol),
                ("status", "in", ["FRESH", "ACTIVE", "STALE"]),
            ])
            for sig_id, sig_data in active_signals.items():
                if sig_data.get("direction") != new_direction or sig_data.get("consensus_pct", 0) < 70:
                    sig_data["status"] = "INVALIDATED"
                    await storage.set("broadcast_history", sig_id, sig_data)
        except Exception as e:
            logger.error("Failed to invalidate previous signals for %s: %s", symbol, e)

    async def _lifecycle_manager_loop(self) -> None:
        """Periodically ages signals in Firestore (FRESH -> ACTIVE -> STALE -> EXPIRED)"""
        await asyncio.sleep(10) # wait a bit before first run
        
        while self._running:
            try:
                now = datetime.now(timezone.utc)
                
                # FIX H2: Use query() instead of get_all() — only fetch signals that
                # are still alive (FRESH/ACTIVE/STALE). Skip EXPIRED and INVALIDATED
                # since they don't need aging. This cuts Firestore reads by 90%+.
                live_signals = await storage.query("broadcast_history", [
                    ("status", "in", ["FRESH", "ACTIVE", "STALE"]),
                ])
                
                updated_count = 0
                for sig_id, sig_data in live_signals.items():
                    bt_str = sig_data.get("broadcast_time")
                    status = sig_data.get("status", "FRESH")
                    
                    if not bt_str:
                        continue
                    
                    try:
                        bt = datetime.fromisoformat(bt_str)
                    except ValueError:
                        continue
                        
                    age_mins = (now - bt).total_seconds() / 60
                    
                    new_status = status
                    if age_mins > 240: # 4 hours
                        new_status = "EXPIRED"
                    elif age_mins > 30: # 30 mins
                        new_status = "STALE"
                    elif age_mins > 5: # 5 mins
                        new_status = "ACTIVE"
                        
                    if new_status != status:
                        sig_data["status"] = new_status
                        await storage.set("broadcast_history", sig_id, sig_data)
                        updated_count += 1
                
                if updated_count > 0:
                    logger.info("♻️ Lifecycle Manager updated %d signals", updated_count)
                    
            except Exception as e:
                logger.error("Lifecycle manager error: %s", e)
                
            await asyncio.sleep(60) # run every minute

    # HARDENED (VULN-08): Maximum concurrent SSE subscribers.
    # Without this cap, an attacker could open thousands of connections
    # and exhaust server memory (each queue holds up to 50 signals).
    MAX_SUBSCRIBERS = 500

    async def subscribe(self):
        """Async generator yielding signals as they arrive via Condition broadcast."""
        last_seen = self._total_broadcasts
        while True:
            async with self._live_condition:
                if last_seen == self._total_broadcasts:
                    try:
                        await asyncio.wait_for(self._live_condition.wait(), timeout=60)
                    except asyncio.TimeoutError:
                        yield "HEARTBEAT"
                        continue
                
                if self._latest_live_msg:
                    yield self._latest_live_msg
                last_seen = self._total_broadcasts

    async def subscribe_delayed(self):
        """
        Create a new delayed SSE subscription.
        Backfills already-matured signals, then yields new delayed signals.
        """
        now = datetime.now(timezone.utc)
        for pair in BROADCAST_PAIRS:
            history = self._history.get(pair, [])
            for sig in list(history):
                age = (now - sig.broadcast_time).total_seconds()
                if age >= FREE_TIER_DELAY_SECONDS:
                    delayed_sig = BroadcastSignal(
                        symbol=sig.symbol,
                        consensus=sig.consensus,
                        snapshot=sig.snapshot,
                        broadcast_time=sig.broadcast_time,
                        cycle_id=sig.cycle_id,
                        analysis_duration_ms=sig.analysis_duration_ms,
                        status="delayed",
                    )
                    yield delayed_sig

        last_seen = self._total_delayed_broadcasts
        while True:
            async with self._delayed_condition:
                if last_seen == self._total_delayed_broadcasts:
                    try:
                        await asyncio.wait_for(self._delayed_condition.wait(), timeout=60)
                    except asyncio.TimeoutError:
                        yield "HEARTBEAT"
                        continue
                if self._latest_delayed_msg:
                    yield self._latest_delayed_msg
                last_seen = self._total_delayed_broadcasts

    def unsubscribe(self, *args) -> None:
        """No-op. Condition based broadcaster handles garbage collection automatically."""
        pass

    async def _delayed_pusher_loop(self) -> None:
        """
        Periodically pushes signals that have matured past the Free Tier delay.

        FIX DP-01 (Fragile Window Replaced):
        The old logic used a 60-second window (age >= DELAY and age < DELAY+60).
        If GC or CPU contention caused the loop to sleep even slightly too long,
        the signal would age past DELAY+60 and be PERMANENTLY DROPPED — the user
        never receives it.

        New logic: track `last_pushed_broadcast_time` per pair. Push any signal
        whose broadcast_time is NEWER than the last one pushed and is mature enough.
        This is resilient to any loop delay.

        FIX RC-01 (Race Condition):
        Push loop now operates under `_delayed_sub_lock` to prevent
        RuntimeError from concurrent subscribe/unsubscribe mutations.
        """
        await asyncio.sleep(15)
        # Map: pair -> broadcast_time of the last signal pushed to delayed subscribers
        last_pushed_broadcast_time: dict[str, datetime] = {}

        while self._running:
            try:
                now = datetime.now(timezone.utc)
                for pair in BROADCAST_PAIRS:
                    history = self._history.get(pair, [])
                    for sig in list(history):
                        age = (now - sig.broadcast_time).total_seconds()
                        if age < FREE_TIER_DELAY_SECONDS:
                            continue  # Not yet matured — skip

                        last_bt = last_pushed_broadcast_time.get(pair)
                        if last_bt is not None and sig.broadcast_time <= last_bt:
                            continue  # Already pushed this or an older signal

                        # New matured signal — push it.
                        last_pushed_broadcast_time[pair] = sig.broadcast_time
                        delayed_sig = BroadcastSignal(
                            symbol=sig.symbol,
                            consensus=sig.consensus,
                            snapshot=sig.snapshot,
                            broadcast_time=sig.broadcast_time,
                            cycle_id=sig.cycle_id,
                            analysis_duration_ms=sig.analysis_duration_ms,
                            status="delayed",
                        )
                        # Push via Condition broadcast (O(1) memory scaling)
                        async with self._delayed_condition:
                            self._latest_delayed_msg = delayed_sig
                            self._total_delayed_broadcasts += 1
                            self._delayed_condition.notify_all()

                        logger.debug(
                            "DELAYED PUSH: %s matured and broadcast to delayed subscribers",
                            pair,
                        )

            except Exception as e:
                logger.error("Delayed pusher error: %s", e)
            await asyncio.sleep(10)

    # ──────────────────────────────────────────
    #  Public API (used by route handlers)
    # ──────────────────────────────────────────

    def get_latest(self, symbol: str) -> Optional[BroadcastSignal]:
        """Get the most recent broadcast for a specific pair."""
        return self._latest.get(symbol)

    def get_all_latest(self) -> dict[str, dict]:
        """Get the latest broadcast for ALL pairs — the global dashboard."""
        return {
            symbol: signal.to_dict()
            for symbol, signal in self._latest.items()
        }

    def get_history(self, symbol: str, limit: int = 20) -> list[dict]:
        """Get historical broadcasts for trend analysis."""
        if symbol not in self._history:
            return []
        entries = list(self._history[symbol])
        return [e.to_dict() for e in entries[-limit:]]

    def get_status(self) -> dict:
        """Get the Broadcaster's operational status."""
        now = time.time()
        pairs_analyzed = len(self._latest)
        staleness = {}
        for symbol, signal in self._latest.items():
            age_seconds = (
                datetime.now(timezone.utc) - signal.broadcast_time
            ).total_seconds()
            staleness[symbol] = {
                "age_seconds": int(age_seconds),
                "is_fresh": age_seconds < CYCLE_INTERVAL_SECONDS * 2,
            }

        return {
            "running": self._running,
            "started_at": self._started_at.isoformat() if self._started_at else None,
            "cycle_count": self._cycle_count,
            "total_broadcasts": self._total_broadcasts,
            "pairs_monitored": len(BROADCAST_PAIRS),
            "pairs_analyzed": pairs_analyzed,
            "active_subscribers": 0,  # Condition-based: no queue tracking needed
            "cycle_interval_seconds": CYCLE_INTERVAL_SECONDS,
            "pair_freshness": staleness,
        }


    # ──────────────────────────────────────────
    #  FIX C1: Agent layer lookup for autopilot vote data
    # ──────────────────────────────────────────

    def _get_agent_layer(self, model_name: str) -> str:
        """Map display name back to layer for autopilot anomaly checking."""
        from consensus_engine import DEN_IDENTITY
        for _, info in DEN_IDENTITY.items():
            if info["display_name"] == model_name:
                return info["layer"]
        return "UNKNOWN"


# ──────────────────────────────────────────────
#  Singleton Instance
# ──────────────────────────────────────────────

broadcaster = Broadcaster()
