"""
Mehd AI — MAM / Master Ledger Models & Dark Pool Schemas
=========================================================
Models for FirmInventory (Dark Pool), MasterTradeReceipt, 
LedgerDistributionTask, and Watchlist.
"""

from datetime import datetime, timezone
from typing import Optional
from enum import Enum
from uuid import UUID, uuid4
from pydantic import BaseModel, Field


class Direction(str, Enum):
    """Trade direction (duplicated here to avoid circular import with models.py)."""
    BUY = "BUY"
    SELL = "SELL"

class FirmInventory(BaseModel):
    """
    The Dark Pool internal ledger.
    Tracks 'leftover' fractional lots that the firm absorbs due to 
    rounding errors and dropped minimum-lot allocations.
    """
    symbol: str
    net_exposure_lots: float = Field(default=0.0, description="Total unhedged lots held by the firm.")
    last_updated: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

class MasterTradeReceipt(BaseModel):
    """
    The receipt of a single block order placed by the AI on the broker.
    This replaces millions of individual broker API calls.
    """
    id: UUID = Field(default_factory=uuid4)
    master_order_id: str = Field(default="", description="Broker trade ID or unique receipt ID")
    symbol: str
    direction: Direction | str
    total_volume_lots: float
    requested_volume_lots: float = Field(default=0.0, description="Requested lots before broker fill/partial fill")
    fill_price: float
    fill_ratio: float = Field(default=1.0, description="successful_lots / requested_lots. Used for proportional distribution on partial fills.")
    eligible_user_count: int = Field(default=0, description="Number of users who qualified for this block order")
    allocated_user_lots: dict[str, float] = Field(default_factory=dict, description="Pre-computed lot allocation per user")
    profit_per_lot: float = Field(default=0.0, description="P&L in dollars per 1 standard lot. Used for ledger distribution.")
    status: str = Field(default="FILLED", description="FILLED, PARTIAL, or FAILED")
    is_closed: bool = Field(default=False, description="True if the position was closed before distribution completed")
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

class LedgerDistributionTask(BaseModel):
    """
    Tracks the background job of distributing a MasterTradeReceipt
    to all eligible users without crashing the event loop.
    """
    task_id: str = Field(default="", description="Matches master_receipt master_order_id")
    receipt_id: Optional[UUID] = None
    symbol: str = ""
    direction: str = ""
    fill_price: float = 0.0
    fill_ratio: float = 1.0
    status: str = Field(default="PENDING", description="PENDING, PROCESSING, COMPLETED")
    total_users: int = 0
    total_eligible_users: int = 0
    users_processed: int = 0
    total_allocated_lots: float = 0.0
    processed_user_ids: list[str] = Field(default_factory=list, description="Idempotency array to prevent double-booking on crash recovery")
    started_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    completed_at: Optional[datetime] = None

class Watchlist(BaseModel):
    """
    A collection of symbols that the user is actively monitoring.
    Used for Phase 4: Smart Watchlists.
    """
    user_id: str
    symbols: list[str] = Field(default_factory=list)
    last_updated: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
