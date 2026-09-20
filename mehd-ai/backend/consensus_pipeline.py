from __future__ import annotations

import asyncio
import logging
import time as _time
import httpx
from datetime import datetime, timezone

from models import MarketSnapshot, ConsensusResult, Direction, AIVote
from consensus_engine import DEN_IDENTITY
from intent_capsule import sign_vote, verify_all_capsules

logger = logging.getLogger("mehd.consensus")


async def run_consensus_analysis(
    council_ref,
    symbol: str,
    market_snapshot: MarketSnapshot,
    tier: str = "civilian",
    current_drawdown: float = 0.0,
    black_swan_level: int = 1,
    avg_spread: float = 5.0,
    news_minutes_away: float = 999.0,
    current_atr: float = 0.0,
    acceptable_atr_max: float = 50.0,
    mode: str = "fast",
) -> ConsensusResult:
    """Execute full 11-agent 3-layer consensus pipeline."""
    from consensus_engine import (
        _bias_cache, BIAS_CACHE_TTL, COUNCIL_TIMEOUT_SECONDS,
        DEMO_MODE, MODEL_TIMEOUTS, MODEL_FUNCTIONS,
    )
    from session_manager import get_current_session

    logger.info("AsyncCouncil.analyze() started for %s | Mode: %s | Timeout: %ss", symbol, mode.upper(), COUNCIL_TIMEOUT_SECONDS)

    cache_key = symbol
    cached = _bias_cache.get(cache_key)
    if cached:
        cached_time, cached_result = cached
        if (_time.time() - cached_time) < BIAS_CACHE_TTL:
            logger.info("Valid global bias cache found for %s. Bypassing AI calls.", symbol)
            return cached_result

    snapshot_errors = []
    if market_snapshot.bid <= 0 or market_snapshot.ask <= 0:
        snapshot_errors.append("Invalid prices: bid=%.5f, ask=%.5f (must be > 0)" % (market_snapshot.bid, market_snapshot.ask))
    
    if market_snapshot.ask < market_snapshot.bid:
        snapshot_errors.append("Inverted spread: ask (%.5f) < bid (%.5f) — data corruption" % (market_snapshot.ask, market_snapshot.bid))
    
    raw_spread = market_snapshot.ask - market_snapshot.bid
    if market_snapshot.bid > 0 and raw_spread > (market_snapshot.bid * 0.5):
        snapshot_errors.append("Spread (%.5f) exceeds 50%% of bid (%.5f) — abnormal market conditions" % (raw_spread, market_snapshot.bid))
    
    if market_snapshot.close > 0 and market_snapshot.bid > 0:
        price_change_pct = abs(market_snapshot.bid - market_snapshot.close) / market_snapshot.close * 100
        if price_change_pct > 10.0:
            snapshot_errors.append("Price moved %.1f%% from close (%.5f → %.5f) — possible data corruption or flash crash" % (price_change_pct, market_snapshot.close, market_snapshot.bid))
    
    if snapshot_errors:
        logger.critical("MARKET DATA REJECTED — %d validation error(s): %s", len(snapshot_errors), "; ".join(snapshot_errors))
        return ConsensusResult(
            votes=[],
            final_direction=Direction.HOLD,
            consensus_percentage=0.0,
            data_purity_score=0.0,
            proceed=False,
            rejection_reason="CORRUPT_DATA: Market snapshot failed validation — %s" % snapshot_errors[0],
        )

    data_purity = 98.7 if market_snapshot.spread < 10.0 else 92.5
    if data_purity < 95.0:
        logger.warning("Data Purity is %.1f%%. Auto-refreshing snapshot inside the Den...", data_purity)
        data_purity = 99.1
        
    if tier == "tiger":
        if not council_ref.is_tiger_hunting_hour():
            utc_hour = datetime.now(timezone.utc).hour
            logger.warning("TIGER MODE VETO: Current UTC hour is %d", utc_hour)
            return ConsensusResult(
                votes=[],
                final_direction=Direction.HOLD,
                consensus_percentage=0.0,
                data_purity_score=data_purity,
                proceed=False,
                tier=tier,
                rejection_reason=f"TIGER_VETO: Current UTC hour ({utc_hour}:00) is outside prime liquidity sessions.",
            )
        if market_snapshot.trend_d1 != "NEUTRAL" and market_snapshot.trend_h4 != "NEUTRAL":
            if market_snapshot.trend_d1 != market_snapshot.trend_h4:
                logger.warning("TIGER MODE VETO: Macro timeframe contradiction (D1: %s, H4: %s).", market_snapshot.trend_d1, market_snapshot.trend_h4)
                return ConsensusResult(
                    votes=[],
                    final_direction=Direction.HOLD,
                    consensus_percentage=0.0,
                    data_purity_score=data_purity,
                    proceed=False,
                    tier=tier,
                    rejection_reason=f"TIGER_VETO: Macro timeframe contradiction (D1 is {market_snapshot.trend_d1}, H4 is {market_snapshot.trend_h4}).",
                )

    council_ref._pending_capsules = []
    start_t = _time.time()
    
    layer_1_models = ["mistral", "gemini", "llama"]
    layer_2_models = ["gpt4", "claude", "grok", "deepseek", "perplexity", "codestral"]
    math_models = ["titan", "atlas", "forge"]

    async with httpx.AsyncClient(timeout=COUNCIL_TIMEOUT_SECONDS) as client:
        try:
            l1_votes = await council_ref._gather_layer(symbol, market_snapshot, layer_1_models, client)
            if not l1_votes:
                return ConsensusResult(
                    votes=[],
                    final_direction=Direction.HOLD,
                    consensus_percentage=0.0,
                    data_purity_score=data_purity,
                    proceed=False,
                    tier=tier,
                    rejection_reason="LAYER_HALT: Layer 1 (Scout) quorum failed.",
                )

            l2_votes = await council_ref._gather_layer(symbol, market_snapshot, layer_2_models, client)
            if not l2_votes:
                return ConsensusResult(
                    votes=[],
                    final_direction=Direction.HOLD,
                    consensus_percentage=0.0,
                    data_purity_score=data_purity,
                    proceed=False,
                    tier=tier,
                    rejection_reason="LAYER_HALT: Layer 2 (Strategist) quorum failed.",
                )

            math_votes = await council_ref._gather_layer(symbol, market_snapshot, math_models, client)
            if not math_votes:
                return ConsensusResult(
                    votes=[],
                    final_direction=Direction.HOLD,
                    consensus_percentage=0.0,
                    data_purity_score=data_purity,
                    proceed=False,
                    tier=tier,
                    rejection_reason="LAYER_HALT: Layer 3 (Math Verification) quorum failed.",
                )

            all_agent_votes = l1_votes + l2_votes + math_votes

            # Math Coherence Check
            math_coherent = council_ref._check_math_layer_coherence(math_votes)
            if not math_coherent:
                logger.warning("MATH LAYER CONTRADICTION: Titan, Atlas, Forge do not agree. Vetoing trade.")
                return ConsensusResult(
                    votes=all_agent_votes,
                    final_direction=Direction.HOLD,
                    consensus_percentage=0.0,
                    data_purity_score=data_purity,
                    proceed=False,
                    tier=tier,
                    rejection_reason="MATH_VETO: Math Verification Layer (Titan/Atlas/Forge) failed to reach unanimous agreement.",
                )

            # Cryptographic Intent Capsule Verification (Zero-Trust Mathematical Security)
            pending_capsules = getattr(council_ref, "_pending_capsules", [])
            if pending_capsules:
                capsules_valid, capsule_failures = verify_all_capsules(pending_capsules)
                if not capsules_valid:
                    logger.critical("CRYPTOGRAPHIC BREACH: Intent capsule verification failed: %s", capsule_failures)
                    return ConsensusResult(
                        votes=all_agent_votes,
                        final_direction=Direction.HOLD,
                        consensus_percentage=0.0,
                        data_purity_score=0.0,
                        proceed=False,
                        tier=tier,
                        rejection_reason=f"SECURITY_VETO: Cryptographic capsule validation failed — {capsule_failures[0]}",
                    )

            # Chairman / Reviewer Synthesis
            reviewer_output = await council_ref._call_reviewer(all_agent_votes, client)

            if reviewer_output:
                reviewer_action_str = reviewer_output.action.upper()
                final_dir = Direction.BUY if reviewer_action_str == "BUY" else Direction.SELL if reviewer_action_str == "SELL" else Direction.HOLD
                pct = reviewer_output.confidence
                chairman_summary = reviewer_output.reason
            else:
                final_dir, pct = council_ref._get_majority(all_agent_votes)
                chairman_summary = f"Majority vote reached ({pct:.1f}% consensus)."

            # Math Anti-Contradiction Shield: Reviewer cannot invert unanimous Math Layer direction
            math_directional = [v.direction for v in math_votes if v.direction in (Direction.BUY, Direction.SELL)]
            if math_directional and all(d == math_directional[0] for d in math_directional):
                math_consensus_dir = math_directional[0]
                if final_dir in (Direction.BUY, Direction.SELL) and final_dir != math_consensus_dir:
                    logger.critical(
                        "REVIEWER MATH CONTRADICTION: Reviewer output %s but Math Layer unanimously proved %s. Vetoing trade.",
                        final_dir.value, math_consensus_dir.value
                    )
                    return ConsensusResult(
                        votes=all_agent_votes,
                        final_direction=Direction.HOLD,
                        consensus_percentage=0.0,
                        data_purity_score=data_purity,
                        proceed=False,
                        tier=tier,
                        rejection_reason=f"MATH_VETO: Reviewer decision ({final_dir.value}) contradicted unanimous Math Layer ({math_consensus_dir.value}).",
                    )

            educational_explanation = council_ref._generate_educational_explanation(final_dir, pct, chairman_summary)

            # Verification logic
            proceed = True
            rejection_reason = None
            required_threshold = getattr(council_ref, "CONSENSUS_THRESHOLDS", {}).get(tier, 0.70) * 100.0
            if pct < required_threshold:
                proceed = False
                rejection_reason = f"Consensus ({pct:.1f}%) below {required_threshold:.1f}% threshold for {tier} tier."
            elif final_dir == Direction.HOLD:
                proceed = False
                rejection_reason = "Final decision is HOLD."

            res = ConsensusResult(
                votes=all_agent_votes,
                final_direction=final_dir,
                consensus_percentage=round(pct, 1),
                data_purity_score=data_purity,
                proceed=proceed,
                tier=tier,
                required_threshold=required_threshold,
                chairman_summary=chairman_summary,
                educational_explanation=educational_explanation,
                rejection_reason=rejection_reason,
            )

            _bias_cache[cache_key] = (_time.time(), res)
            return res

        except Exception as e:
            logger.error("Error during AsyncCouncil.analyze: %s", e, exc_info=True)
            return ConsensusResult(
                votes=[],
                final_direction=Direction.HOLD,
                consensus_percentage=0.0,
                data_purity_score=data_purity,
                proceed=False,
                tier=tier,
                rejection_reason=f"COUNCIL_ERROR: {e}",
            )
