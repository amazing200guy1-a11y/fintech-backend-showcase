"""
Mehd AI - Free Trial and Broker Trial Service
Tracks active trading days (Mon-Fri) and binds broker accounts for 1-time Institutional trial.
"""
from __future__ import annotations

import logging
import re as _re
from datetime import datetime, timezone

logger = logging.getLogger("mehd.services.trial")

FREE_TRIAL_DAYS = 3
FREE_TRIAL_TIER = "institutional"


def _get_datetime():
    import sys
    if "routes.payments" in sys.modules:
        pm = sys.modules["routes.payments"]
        if hasattr(pm, "datetime"):
            return pm.datetime
    return datetime


async def _get_trial_info(uid: str) -> dict | None:
    """Get trial status for a user.
    Tracks active trading days (Mon-Fri). Weekends (Sat/Sun) and market holidays
    are paused and do NOT consume active trial days.
    """
    try:
        from storage import storage
        trial_data = await storage.get("user_trials", uid)
        if not trial_data or "activated_at" not in trial_data:
            return None

        dt_cls = _get_datetime()
        now = dt_cls.now(timezone.utc)
        today_str = now.strftime("%Y-%m-%d")
        is_weekend = now.weekday() >= 5

        active_dates_used = list(trial_data.get("active_dates_used", []))

        if not is_weekend:
            if today_str not in active_dates_used and len(active_dates_used) < FREE_TRIAL_DAYS:
                active_dates_used.append(today_str)
                trial_data["active_dates_used"] = active_dates_used
                trial_data["last_active_date"] = today_str
                await storage.set("user_trials", uid, trial_data)

        days_used = len(active_dates_used)
        days_remaining = max(0, FREE_TRIAL_DAYS - days_used)
        is_active = (days_remaining > 0) or (today_str in active_dates_used and not is_weekend)

        return {
            "activated_at": trial_data["activated_at"],
            "days_remaining": days_remaining,
            "days_used": days_used,
            "is_active": is_active,
            "is_weekend_paused": is_weekend,
            "trial_tier": FREE_TRIAL_TIER,
            "active_dates_used": active_dates_used,
        }
    except Exception as e:
        logger.warning("Trial lookup failed for %s: %s", uid, e)
        return None


async def activate_trial(uid: str, normalized_phone: str, ip_key: str) -> dict:
    """Activate the 3 Active Market Days free trial for a new user (idempotent)."""
    from storage import storage
    existing = await _get_trial_info(uid)
    if existing:
        return existing
    dt_cls = _get_datetime()
    now = dt_cls.now(timezone.utc)
    today_str = now.strftime("%Y-%m-%d")
    is_weekend = now.weekday() >= 5
    active_dates = [today_str] if not is_weekend else []

    trial_data = {
        "activated_at": now.isoformat(),
        "trial_tier": FREE_TRIAL_TIER,
        "trial_days": FREE_TRIAL_DAYS,
        "active_dates_used": active_dates,
        "last_active_date": today_str if not is_weekend else None,
    }
    await storage.set("user_trials", uid, trial_data)
    await storage.set("phone_trials", normalized_phone, {"uid": uid, "activated_at": now.isoformat()})
    logger.info("ACTIVE MARKET TRIAL ACTIVATED: User %s -> %d active trading days of %s access", uid, FREE_TRIAL_DAYS, FREE_TRIAL_TIER)
    return {
        "activated_at": now.isoformat(),
        "days_remaining": FREE_TRIAL_DAYS - len(active_dates),
        "days_used": len(active_dates),
        "is_active": True,
        "is_weekend_paused": is_weekend,
        "trial_tier": FREE_TRIAL_TIER,
        "active_dates_used": active_dates,
    }


async def check_broker_trial_eligibility(broker_account_id: str, uid: str) -> bool:
    if not broker_account_id:
        return True
    from storage import storage
    normalized = _re.sub(r"[^a-zA-Z0-9]", "", str(broker_account_id)).lower()
    if not normalized:
        return True
    existing = await storage.get("broker_trials", normalized)
    if existing and existing.get("uid") != uid:
        logger.warning("TRIAL EXPLOIT ATTEMPT: Broker account %s claimed by UID %s, rejected for UID %s", normalized, existing.get("uid"), uid)
        return False
    return True


async def bind_broker_trial_account(broker_account_id: str, uid: str) -> None:
    if not broker_account_id:
        return
    from storage import storage
    now = datetime.now(timezone.utc)
    normalized = _re.sub(r"[^a-zA-Z0-9]", "", str(broker_account_id)).lower()
    if normalized:
        await storage.set("broker_trials", normalized, {"uid": uid, "activated_at": now.isoformat()})
        logger.info("BROKER TRIAL BOUND: Account %s burned to UID %s", normalized, uid)
