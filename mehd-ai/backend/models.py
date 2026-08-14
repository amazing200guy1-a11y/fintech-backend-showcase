"""
Mehd AI — Data Models (Pydantic v2)
====================================
Every piece of data that flows through Mehd AI has a strict shape.
No field can be missing, no value can be the wrong type, no number
can exceed its allowed range. In a financial system, a single
mistyped field can mean real money lost. These models prevent that.
"""

from __future__ import annotations

import time
from datetime import datetime, timezone
from enum import Enum
from typing import Optional, Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, field_validator
from market_models import *


# ──────────────────────────────────────────────
#  Enums — the ONLY directions the system can express
# ──────────────────────────────────────────────

class Direction(str, Enum):
    """
    A trade can only ever go in one of three directions.
    By making this an enum, it is impossible for any part
    of the system to invent a fourth option like 'MAYBE'.
    """
    BUY = "BUY"
    SELL = "SELL"
    HOLD = "HOLD"

class SignalPhase(str, Enum):
    """
    The lifecycle of a broadcast signal.
    FRESH: 0-5 mins. Highly actionable.
    ACTIVE: 5-30 mins. Actionable, but price may have moved.
    STALE: 30m-4h. Warning, do not trade without new analysis.
    EXPIRED: >4h. Dead signal.
    INVALIDATED: Replaced by a contrary signal.
    """
    FRESH = "FRESH"
    ACTIVE = "ACTIVE"
    STALE = "STALE"
    EXPIRED = "EXPIRED"
    INVALIDATED = "INVALIDATED"



# ──────────────────────────────────────────────
#  Unified Pip Size — SINGLE SOURCE OF TRUTH
# ──────────────────────────────────────────────

def get_pip_size(symbol: str) -> float:
    """
    Returns the pip size for a given trading instrument.
    
    This is the ONE AND ONLY place pip_size should be defined.
    All other files MUST import this function instead of
    calculating pip_size inline.
    
    Rules:
      XAU (Gold)  → 0.01  (Standard 2nd decimal place)
      JPY pairs   → 0.01  (1 pip = ¥0.01 price movement)
      All others  → 0.0001 (1 pip = $0.0001 price movement)
    """
    sym = symbol.upper().replace("/", "")
    if "XAU" in sym:
        return 0.01
    if "JPY" in sym:
        return 0.01
    return 0.0001


# ──────────────────────────────────────────────
#  DepthOfMarket — Institutional Level 2 Data
# ──────────────────────────────────────────────

class DepthOfMarket(BaseModel):
    """
    Level 2 Institutional Order Book data.
    This is the "Empty Room" ready to receive real bank volume data.
    """
    bids: list[tuple[float, float]] = Field(default_factory=list, description="List of (price, volume) tuples")
    asks: list[tuple[float, float]] = Field(default_factory=list, description="List of (price, volume) tuples")
    imbalance_ratio: float = Field(default=0.0, description="Positive = Buy pressure, Negative = Sell pressure")


# ──────────────────────────────────────────────
#  MarketSnapshot — what the market looks like RIGHT NOW
# ──────────────────────────────────────────────

class MarketSnapshot(BaseModel):
    """
    A frozen picture of a currency pair at one moment in time.
    The frontend sends this to the backend so every AI model
    is analyzing the exact same data — no stale prices.
    """
    id: UUID = Field(
        default_factory=uuid4,
        description="Unique ID for this specific snapshot instance",
    )
    symbol: str = Field(
        ...,
        min_length=6,
        max_length=10,
        description="Currency pair, e.g. 'EURUSD' or 'EUR/USD'",
        examples=["EURUSD"],
    )
    bid: float = Field(..., gt=0, description="Current bid price")
    ask: float = Field(..., gt=0, description="Current ask price")
    spread: float = Field(..., ge=0, description="Ask minus bid, in pips")
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="When this snapshot was captured (UTC)",
    )
    timestamp_ns: int = Field(
        default_factory=time.time_ns,
        description="Nanosecond exact precision for atomic consensus",
    )
    order_book_walls: Optional[str] = Field(
        default="Buyer wall at -20 pips, Seller wall at +30 pips",
        description="Aggregated deep volume liquidity nodes",
    )
    open: float = Field(..., gt=0, description="Period open price")
    high: float = Field(..., gt=0, description="Period high price")
    low: float = Field(..., gt=0, description="Period low price")
    close: float = Field(..., gt=0, description="Period close price")
    volume: float = Field(..., ge=0, description="Trade volume in the period")
    dom_data: Optional[DepthOfMarket] = Field(
        default=None,
        description="Level 2 Institutional Order Book / Depth of Market",
    )

    # ── FIX 1: Data Freshness Fields ──
    data_age_ms: int = Field(
        default=0,
        ge=0,
        description="How old this data is in milliseconds at time of serving",
    )
    data_source: str = Field(
        default="mock",
        description="Which provider delivered this tick (oanda/polygon/twelvedata/mock)",
    )
    is_live: bool = Field(
        default=False,
        description="True only if data_age_ms < 1000",
    )
    briefing: str = Field(
        default="",
        description="The Secretary's market briefing template",
    )
    latency_warning: bool = Field(
        default=False,
        description="True if data_age_ms > 3000 — trader should be cautious",
    )

    # ── Macro Trend Fields (For Tiger Mode Alignment) ──
    trend_d1: Optional[str] = Field(
        default="NEUTRAL",
        description="Daily macro trend direction (BULLISH/BEARISH/NEUTRAL)"
    )
    trend_h4: Optional[str] = Field(
        default="NEUTRAL",
        description="4-Hour macro trend direction (BULLISH/BEARISH/NEUTRAL)"
    )
    trend_h1: Optional[str] = Field(
        default="NEUTRAL",
        description="1-Hour trend direction (BULLISH/BEARISH/NEUTRAL)"
    )

    @field_validator("ask")
    @classmethod
    def ask_must_be_gte_bid(cls, v: float, info) -> float:
        bid = info.data.get("bid")
        if bid is not None and v < bid:
            raise ValueError("Ask price cannot be lower than bid price")
        return v

    @field_validator("high")
    @classmethod
    def high_must_be_gte_low(cls, v: float, info) -> float:
        low = info.data.get("low")
        if low is not None and v < low:
            raise ValueError("High price cannot be lower than low price")
        return v


# ──────────────────────────────────────────────
#  AIVote — one model's opinion
# ──────────────────────────────────────────────

class AIVote(BaseModel):
    """
    Each of the 11 AI agents returns exactly this shape.
    - model_name identifies WHO voted
    - direction is BUY, SELL, or HOLD — nothing else
    - confidence is 0-100 — how sure the model is
    - reasoning is plain English so the trader can read WHY
    """
    model_name: str = Field(
        ...,
        min_length=1,
        description="Name of the AI model, e.g. 'grok', 'claude'",
    )
    snapshot_id: UUID = Field(
        ...,
        description="The exact MarketSnapshot ID this model analyzed",
    )
    direction: Direction = Field(
        ...,
        description="The model's recommended trade direction",
    )
    confidence: float = Field(
        ...,
        ge=0,
        le=100,
        description="Confidence score from 0 (no idea) to 100 (certain)",
    )
    reasoning: str = Field(
        ...,
        min_length=1,
        description="Plain English explanation of why this direction was chosen",
    )


# ──────────────────────────────────────────────
#  FinalReviewerOutput — Strict JSON Template for Layer 4
# ──────────────────────────────────────────────

class FinalReviewerOutput(BaseModel):
    """
    Unbreakable Python mold for the 2 Reviewer AI models.
    If they hallucinate a field or give a bad value, validation fails.
    """
    action: Direction = Field(description="Strictly BUY, SELL, or HOLD")
    confidence: float = Field(ge=0.0, le=100.0, description="0 to 100 confidence score")
    reason: str = Field(description="Strictly a 1-sentence reason for the user")


# ──────────────────────────────────────────────
#  ConsensusResult — the council's combined verdict
# ──────────────────────────────────────────────

class ConsensusResult(BaseModel):
    """
    After all 11 agents vote, this object holds:
    - every individual vote
    - the final direction the majority chose
    - the percentage that agreed
    - whether the system will allow the trade to proceed
    """
    votes: list[AIVote] = Field(
        ...,
        description="All individual AI model votes",
    )
    final_direction: Direction = Field(
        ...,
        description="The direction chosen by the majority of models",
    )
    consensus_percentage: float = Field(
        ...,
        ge=0,
        le=100,
        description="Percentage of models that agreed on the final direction",
    )
    data_purity_score: float = Field(
        ...,
        ge=0,
        le=100,
        description="Confidence in the exactness of the market data given to the Den",
    )
    proceed: bool = Field(
        ...,
        description="True if consensus is strong enough to allow trading",
    )
    is_simulated: bool = Field(
        default=False,
        description="True if this consensus used any simulated/mock data",
    )
    tier: str = Field(
        default="civilian",
        description="The locked tier validation (observer, core, precision, institutional)",
    )
    required_threshold: float = Field(
        default=0.70,
        description="The matched threshold locked to this tier",
    )
    chairman_summary: Optional[str] = Field(
        default=None,
        description="Two sentence executive summary from the Chairman agent",
    )
    rejection_reason: Optional[str] = Field(
        default=None,
        description="If proceed is False, explains why (e.g. CALCULATION_MISMATCH)",
    )
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="When the consensus was calculated (UTC)",
    )
    drawings: list[dict] = Field(
        default_factory=list,
        description="AI-generated drawing commands for the TradingView chart bridge",
    )
    panic_protocol_active: bool = Field(
        default=False,
        description="True if a systemic market failure or black swan was detected — emergency capital protection mode",
    )
    market_session: str = Field(
        default="Unknown",
        description="The global market session at the time of analysis (e.g. London, NY, Overlap)",
    )
    educational_explanation: str = Field(
        default="",
        description="A simple, Grade-4 English explanation of the chart analysis and drawings.",
    )


# ──────────────────────────────────────────────
#  TradeOrder — what the trader wants to do
# ──────────────────────────────────────────────

class TradeOrder(BaseModel):
    """
    A request to open a trade. The risk engine will
    inspect every field before allowing execution.
    """
    symbol: str = Field(
        ...,
        min_length=6,
        max_length=10,
        description="Currency pair to trade",
        examples=["EURUSD"],
    )
    direction: Direction = Field(
        ...,
        description="BUY or SELL (HOLD would not make sense here)",
    )
    lot_size: float = Field(
        ...,
        gt=0,
        le=100.0,
        description="Position size in lots (0.01 = micro, 1.0 = standard)",
    )
    stop_loss: Optional[float] = Field(
        default=None,
        gt=0,
        description="Stop-loss price — the risk engine REQUIRES this",
    )
    take_profit: Optional[float] = Field(
        default=None,
        gt=0,
        description="Take-profit price — optional but recommended",
    )
    risk_percentage: float = Field(
        default=1.0,
        gt=0,
        le=10.0,
        description="Max percentage of account balance to risk per trade (0.1–10%). Stored as a percentage: 1.0 = 1%, 10.0 = 10%.",
    )
    is_auto_execution: bool = Field(
        default=False,
        description="True if this order was generated by the Autopilot engine.",
    )
    tier: str = Field(
        default="civilian",
        description="The consensus tier this order was generated under. 'tiger' activates strict R:R enforcement.",
    )

class InternalTradeOrder(TradeOrder):
    """
    A TradeOrder that has been enriched with verified AI consensus scores
    by the backend. Passed securely to the Risk Microservice.
    """
    math_layer_votes: Optional[list[AIVote]] = Field(
        default=None,
        description="Votes from the underlying Math Layer, for kernel override",
    )
    votes: Optional[list[AIVote]] = Field(
        default=None,
        description="All individual AI model votes for generating the brief",
    )

# ──────────────────────────────────────────────
#  ExecutiveBrief — The Audit Trail
# ──────────────────────────────────────────────

