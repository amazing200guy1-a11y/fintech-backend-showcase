import logging
from datetime import datetime, timezone
from typing import Optional
import json
from models import AppConstitution, ConstitutionRule
from storage import storage

logger = logging.getLogger("mehd.risk_engine")

class ConstitutionManager:
    """
    Manages loading, validating, and updating the Trader's Constitution.
    
    FIX #4: Now supports per-user constitutions. Each user gets their own
    trade counter, rules, and daily reset — no more cross-user contamination.
    
    - load(user_id="abc") → loads user-specific constitution
    - load()             → loads global fallback (backward compat)
    """

    @classmethod
    def _default_constitution(cls) -> AppConstitution:
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        return AppConstitution(
            last_reset_date=today,
            daily_trades_count=0,
            rules=[
                ConstitutionRule(
                    name="Overtrading Protection",
                    description="Maximum 3 trades per day to prevent revenge trading.",
                    rule_type="max_daily_trades",
                    parameter=3.0,
                ),
                ConstitutionRule(
                    name="High Conviction Only",
                    description="Only trade when consensus is 80% or higher.",
                    rule_type="min_consensus",
                    parameter=80.0,
                )
            ]
        )

    @classmethod
    async def load(cls, user_id: Optional[str] = None) -> AppConstitution:
        key = user_id if user_id else "global"
        try:
            data = await storage.get("constitutions", key)
            if data:
                return AppConstitution.model_validate(data)
            
            # If not found, create and save default
            default_const = cls._default_constitution()
            await cls.save(default_const, user_id=user_id)
            return default_const
        except Exception as e:
            logger.critical("Error loading constitution for %s (FAIL CLOSED): %s", key, e)
            return AppConstitution(
                rules=[
                    ConstitutionRule(
                        name="Constitution Corrupted",
                        description="Security mechanism failed to read safety rules. System fail-closed.",
                        rule_type="max_daily_trades",
                        parameter=0.0,
                    )
                ]
            )

    @classmethod
    async def save(cls, constitution: AppConstitution, user_id: Optional[str] = None) -> None:
        key = user_id if user_id else "global"
        try:
            # Convert to dict to save in Firestore via storage
            data = json.loads(constitution.model_dump_json())
            await storage.set("constitutions", key, data)
        except Exception as e:
            logger.error("Error saving constitution for %s: %s", key, e)
            
    @classmethod
    async def increment_daily_trades(cls, user_id: Optional[str] = None) -> None:
        from storage import storage
        key = user_id if user_id else "global"
        lock_key = f"constitution_lock_{key}"
        # Acquire a distributed lock to make read-modify-write atomic.
        # Without this, concurrent manual + autopilot executions both read
        # count=N, both increment to N+1, and both save — bypassing the daily cap.
        got_lock = await storage.acquire_lock(lock_key, ttl_seconds=10)
        if not got_lock:
            logger.warning("Constitution lock contention for user %s — skipping duplicate increment", key)
            return
        try:
            const = await cls.load(user_id=user_id)
            today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            if const.last_reset_date != today:
                const.daily_trades_count = 0
                const.last_reset_date = today

            const.daily_trades_count += 1
            await cls.save(const, user_id=user_id)
        finally:
            await storage.release_lock(lock_key)
