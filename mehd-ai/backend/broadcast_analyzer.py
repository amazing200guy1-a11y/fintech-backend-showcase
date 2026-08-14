from __future__ import annotations

import asyncio
import logging
import time
from datetime import datetime, timezone

from storage import storage
from utils.chart_utils import generate_drawing_commands, generate_mock_candles
from secretary import secretary
from broadcast_signal import BroadcastSignal

logger = logging.getLogger("mehd.broadcaster")


async def run_analyze_and_broadcast(broadcaster_ref, symbol: str) -> None:
    """Run the full Den analysis on one pair and broadcast the result."""
    from state import den_engine, streamer, audit

    async def _safe_store(sig_id: str, data: dict):
        try:
            await storage.set("broadcast_history", sig_id, data)
        except Exception as e:
            logger.error("CRITICAL: Signal %s lost — Firestore write failed: %s", sig_id, e)

    try:
        start_time = time.time()
        snapshot = streamer.get_latest_snapshot(symbol)

        cached_signal = broadcaster_ref._latest.get(symbol)
        last_snapshot = cached_signal.snapshot if cached_signal else None

        should_wake, reason, briefing = secretary.analyze_market_tick(
            symbol, snapshot, last_snapshot
        )

        if cached_signal and not should_wake:
            age_mins = (datetime.now(timezone.utc) - cached_signal.broadcast_time).total_seconds() / 60
            if age_mins < 15.0:
                logger.info("SECRETARY (%s): %s — Skipping analysis.", symbol, reason)
                cached_signal.snapshot = snapshot
                cached_signal.cycle_id = broadcaster_ref._cycle_count
                cached_signal.broadcast_time = datetime.now(timezone.utc)
                cached_signal.analysis_duration_ms = 0

                await broadcaster_ref._push_to_subscribers(cached_signal)
                broadcaster_ref._total_broadcasts += 1
                broadcaster_ref._last_pair_time[symbol] = time.time()
                return

        logger.info("SECRETARY (%s): Waking 11 agents. Reason: %s", symbol, reason)
        logger.debug("Briefing sent to agents:\n%s", briefing)
        snapshot.briefing = briefing

        try:
            result = await asyncio.wait_for(
                den_engine.analyze(
                    symbol,
                    snapshot,
                    tier="institutional",
                    current_drawdown=0.0,
                ),
                timeout=60.0
            )
        except asyncio.TimeoutError:
            logger.error("Analysis for %s TIMED OUT after 60 seconds.", symbol)
            broadcaster_ref._errors_this_cycle += 1
            return

        duration_ms = int((time.time() - start_time) * 1000)

        try:
            mock_candles = generate_mock_candles(snapshot.close)
            result.drawings = generate_drawing_commands(symbol, result, mock_candles)
        except Exception as draw_err:
            logger.warning("Failed to generate drawing commands for %s: %s", symbol, draw_err)
            result.drawings = []

        signal = BroadcastSignal(
            symbol=symbol,
            consensus=result,
            snapshot=snapshot,
            cycle_id=broadcaster_ref._cycle_count,
            analysis_duration_ms=duration_ms,
        )

        await broadcaster_ref._invalidate_previous_signals(symbol, result.final_direction.value)

        broadcaster_ref._latest[symbol] = signal
        history = broadcaster_ref._history.setdefault(symbol, [])
        history.append(signal)

        sig_dict = signal.to_dict()
        signal_doc_id = f"{symbol.replace('/', '_')}_{int(signal.broadcast_time.timestamp())}"
        await _safe_store(signal_doc_id, sig_dict)

        await storage.set("broadcast_store", symbol.replace("/", "_"), sig_dict)

        await broadcaster_ref._push_to_subscribers(signal)
        broadcaster_ref._total_broadcasts += 1
        broadcaster_ref._last_pair_time[symbol] = time.time()

        audit.log(
            event_type="BROADCAST_COMPLETED",
            user_id="SYSTEM",
            details={
                "symbol": symbol,
                "direction": result.final_direction.value,
                "consensus_pct": result.consensus_percentage,
                "proceed": result.proceed,
                "duration_ms": duration_ms,
                "cycle_id": broadcaster_ref._cycle_count,
            },
        )

        logger.info(
            "BROADCAST [%s #%d]: %s %s (%.1f%% consensus, proceed=%s, %dms)",
            symbol,
            broadcaster_ref._cycle_count,
            result.final_direction.value,
            "PROCEED" if result.proceed else "BLOCKED",
            result.consensus_percentage,
            result.proceed,
            duration_ms,
        )

    except Exception as e:
        logger.error("Failed to analyze/broadcast %s: %s", symbol, e, exc_info=True)
        broadcaster_ref._errors_this_cycle += 1
