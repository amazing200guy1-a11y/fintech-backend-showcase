"""
Mehd AI — Consensus Engine (Live API Version)
==============================================
Phase 2: Real AI APIs.

The 11 AI agents are now hitting actual endpoints across 5 providers
(Anthropic, OpenAI, Google, xAI, Perplexity, DeepSeek, Groq, Mistral).

If a key is missing or an API times out, the model is skipped gracefully.
The Den proceeds as long as there are enough votes to meet the
70%+ threshold.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time as _time
import re as _re
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

import httpx
from models import AIVote, ConsensusResult, Direction, MarketSnapshot, FinalReviewerOutput
from intent_capsule import sign_vote, verify_all_capsules, IntentCapsule
from anomaly_detector import anomaly_detector

# Import modular helper configurations and providers
from consensus.helpers import (
    SENTIMENT_LAYER,
    STRATEGY_LAYER,
    MATH_LAYER,
    SUPREME,
    ALL_MODELS,
    agents,
    COUNCIL_TIMEOUT_SECONDS,
    MODEL_TIMEOUTS,
    DEN_IDENTITY,
    _get_vault_role,
    _build_system_prompt,
    _build_user_message,
    _parse_llm_json,
    _sanitize_confidence,
    _sanitize_reasoning,
)
from consensus.providers import MODEL_FUNCTIONS

# Import modular chart/drawing helpers
from utils.chart_utils import (
    generate_drawing_commands,
    generate_mock_candles,
    validate_user_level,
)

logger = logging.getLogger("mehd.consensus_engine")

# Risk constants — must stay in sync with HardRiskKernel.MAX_DAILY_DRAWDOWN_PCT (3.0%)
# Autopilot Sovereign Lock fires at 2/3 of the user kill-switch to give an early warning margin.
AUTOPILOT_DRAWDOWN_LIMIT: float = 2.0   # = 3.0 * (2/3) — tighter than the manual 3% kill-switch

# ──────────────────────────────────────────────
#  Demo Mode Toggle
# ──────────────────────────────────────────────
DEMO_MODE = os.getenv('DEMO_MODE', 'true').lower() in ('true', '1', 'yes')

from consensus_cache import (
    _sentiment_cache,
    SENTIMENT_CACHE_TTL,
    SENTIMENT_CACHE_MAX_SIZE,
    _bias_cache,
    BIAS_CACHE_TTL,
    BIAS_CACHE_MAX_SIZE,
    call_sentinel as _call_sentinel,
)
from auditor_agent import auditor_agent

# ──────────────────────────────────────────────
#  AsyncCouncil
# ──────────────────────────────────────────────

class AsyncCouncil:
    """
    Fires all 11 AI agents simultaneously, collects their votes,
    and determines consensus using real API calls.
    """

    CONSENSUS_THRESHOLDS = {
        "observer": 0.70,
        "core": 0.70,
        "precision": 0.80,
        "institutional": 0.95,
        "civilian": 0.70,
        "operative": 0.80,
        "sovereign": 0.95,
        "tiger": 0.85,
    }
    MATH_CONFIDENCE_DIVERGENCE_LIMIT: float = 0.5

    def is_tiger_hunting_hour(self) -> bool:
        """
        Tiger Mode only hunts during peak market liquidity windows.
        London Session:  07:00 UTC - 10:00 UTC
        NY Session:      12:00 UTC - 16:00 UTC  (includes London/NY overlap)
        Outside these two windows the market is low-volume and full of fakeouts.
        """
        hour = datetime.now(timezone.utc).hour
        return (7 <= hour < 10) or (12 <= hour < 16)

    async def analyze(
        self,
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
        from consensus_pipeline import run_consensus_analysis
        return await run_consensus_analysis(
            self, symbol, market_snapshot, tier, current_drawdown,
            black_swan_level, avg_spread, news_minutes_away, current_atr,
            acceptable_atr_max, mode
        )

    def _get_majority(self, current_votes: list[AIVote]) -> tuple[Direction, float]:
        if not current_votes: 
            return Direction.HOLD, 0.0
        counts = {Direction.BUY: 0, Direction.SELL: 0, Direction.HOLD: 0}
        for v in current_votes: 
            counts[v.direction] += 1
        maj_dir = max(counts, key=counts.get)
        pct = (counts[maj_dir] / len(current_votes)) * 100.0
        return maj_dir, pct

    # ──────────────────────────────────────────────
    #  The Auditor — Post-Mortem Agent
    # ──────────────────────────────────────────────
    
    async def perform_audit(
        self, 
        trade_id: str,
        symbol: str, 
        direction: Direction, 
        entry_price: float, 
        exit_price: float, 
        pnl: float,
        user_notes: Optional[str] = None
    ) -> dict:
        """Delegates post-mortem audit to AuditorAgent."""
        return await auditor_agent.perform_audit(
            trade_id=trade_id,
            symbol=symbol,
            direction=direction,
            entry_price=entry_price,
            exit_price=exit_price,
            pnl=pnl,
            user_notes=user_notes,
        )

    async def _gather_layer(self, symbol: str, snapshot: MarketSnapshot, layer_models: list[str], client: httpx.AsyncClient) -> list[AIVote]:
        from consensus_layer_runner import gather_layer_votes
        return await gather_layer_votes(self, symbol, snapshot, layer_models, client)

    async def _call_reviewer(self, votes: list[AIVote], client: httpx.AsyncClient) -> Optional[FinalReviewerOutput]:
        from consensus_layer_runner import call_reviewer_engine
        return await call_reviewer_engine(votes, client)

    MATH_LAYER_DISPLAY = ["TITAN", "ATLAS", "FORGE"]

    def _check_math_layer_coherence(self, votes: list[AIVote]) -> bool:
        """Protect against divergent quants."""
        math_votes = [v for v in votes if v.model_name in self.MATH_LAYER_DISPLAY]
        if len(math_votes) < 2:
            return False

        confidences = [v.confidence / 100.0 for v in math_votes]
        max_divergence = max(confidences) - min(confidences)

        if max_divergence > self.MATH_CONFIDENCE_DIVERGENCE_LIMIT:
            logger.warning(
                "MATH LAYER DIVERGENCE: gap=%.2f (limit: %.2f) — Models: %s",
                max_divergence, self.MATH_CONFIDENCE_DIVERGENCE_LIMIT,
                ", ".join(f"{v.model_name}={v.confidence:.1f}%" for v in math_votes)
            )
            return True

        return False

    async def health_check(self) -> dict:
        status: dict[str, str] = {}
        key_map = {
            "grok": "GROQ_API_KEY",
            "perplexity": "PERPLEXITY_API_KEY",
            "gemini": "GEMINI_API_KEY",
            "claude": "ANTHROPIC_API_KEY",
            "gpt-4": "OPENAI_API_KEY",
            "llama": "GROQ_API_KEY",
            "deepseek": "DEEPSEEK_API_KEY",
            "openai-o3": "OPENAI_API_KEY",
            "codestral": "MISTRAL_API_KEY",
        }
        
        for name, env_var in key_map.items():
            if os.getenv(env_var):
                status[name] = "ready (key loaded)"
            else:
                status[name] = "missing key"
                
        return status

    def _generate_educational_explanation(self, direction: Direction, confidence: float, summary: str | None) -> str:
        """Translates technical AI consensus into a Grade-4 English explanation."""
        from models import Direction
        if direction == Direction.HOLD:
            return "The market is currently messy and undecided. It's like a tug-of-war where nobody is winning, so the AI is waiting for a clear move before suggesting a trade."
        
        dir_word = "up" if direction == Direction.BUY else "down"
        strength = "strong" if confidence >= 85 else "moderate"
        
        explanation = f"The AI agents see a {strength} chance that the price will move {dir_word}. "
        
        if summary and "momentum" in summary.lower():
            explanation += "They noticed the price has a lot of energy moving in this direction right now. "
        elif summary and "support" in summary.lower():
            explanation += "They found a 'floor' on the chart where the price usually bounces back up. "
        else:
            explanation += "They analyzed the current price action and global bank sessions to find this high-probability path."

        return explanation
