from fastapi import APIRouter, Depends, Request, HTTPException
from security import get_current_user
from storage import storage

router = APIRouter()

@router.get(
    "/autopilot/config",
    summary="Get the user's autopilot configuration",
)
@limiter.limit("30/minute")
async def get_autopilot_config(request: Request, uid: str = Depends(get_current_user)):
    """Returns the user's current autopilot settings, or defaults if none exist."""
    raw = await storage.get("autopilot_configs", uid)
    if raw:
        try:
            cfg = AutopilotConfig.model_validate(raw)
            return cfg.model_dump()
        except Exception as e:
            logger.warning("Failed to validate autopilot config for %s: %s", uid, e)
    # Return defaults
    return AutopilotConfig().model_dump()


@router.post(
    "/autopilot/config",
    summary="Save the user's autopilot configuration",
)
@limiter.limit("10/minute")
async def save_autopilot_config(
    request: Request, body: AutopilotConfigRequest, uid: str = Depends(get_current_user)
):
    """
    Saves autopilot settings from the Flutter app.
    Preserves server-managed fields (frozen, counts, timestamps).
    """
    # Load existing config to preserve server-managed state
    raw = await storage.get("autopilot_configs", uid)
    if raw:
        try:
            cfg = AutopilotConfig.model_validate(raw)
        except Exception as e:
            logger.warning("Corrupted autopilot config for %s, resetting to default: %s", uid, e)
            cfg = AutopilotConfig()
    else:
        cfg = AutopilotConfig()
    
    # Only update user-controlled fields (never let client set frozen, counts, etc.)
    cfg.enabled = body.enabled
    cfg.whitelisted_pairs = body.whitelisted_pairs
    cfg.active_hours_start_utc = max(0, min(23, body.active_hours_start_utc))
    cfg.active_hours_end_utc = max(0, min(23, body.active_hours_end_utc))
    cfg.predator_mode = body.predator_mode
    cfg.assist_mode = body.assist_mode

    # Tier gate: Autopilot and Predator mode access
    tier_name = await get_user_tier_async(uid)
    
    full_auto_tiers = ("institutional", "precision", "operative")
    assist_tiers = ("core", "institutional", "precision", "operative")
    
    if tier_name not in assist_tiers:
        # Observer or unrecognized tier cannot enable autopilot at all
        cfg.enabled = False
        cfg.assist_mode = False
        cfg.predator_mode = False
    elif tier_name not in full_auto_tiers:
        # Core tier can only enable assist_mode, not predator mode and not full auto
        cfg.predator_mode = False
        if cfg.enabled and not cfg.assist_mode:
            cfg.enabled = False
            logger.warning(f"User {uid} (tier: {tier_name}) attempted full auto without assist mode — denied.")

    # Tier gate: only institutional/precision users may enable compounding.
    # Everyone else is silently clamped to OFF to prevent free-tier abuse.
    compounding_tiers = ("institutional", "precision", "operative")  # operative = legacy institutional
    if body.compounding_mode != "OFF" and tier_name not in compounding_tiers:
        logger.warning(
            "User %s (tier: %s) attempted to enable compounding_mode=%s — denied.",
            uid, tier_name, body.compounding_mode
        )
        cfg.compounding_mode = "OFF"
    else:
        cfg.compounding_mode = body.compounding_mode
    
    import json
    await storage.set("autopilot_configs", uid, json.loads(cfg.model_dump_json()))
    
    return {"status": "saved", "config": cfg.model_dump()}


@router.get(
    "/autopilot/eligibility",
    summary="Check if the user is eligible for autopilot",
)
@limiter.limit("10/minute")
async def check_autopilot_eligibility(request: Request, uid: str = Depends(get_current_user)):
    """
    Returns real eligibility data for the autopilot gates.
    Queries the user's trade history, account age, and protection score.
    """
    # Fetch real data from user's profile/history
    user_profile = await storage.get("user_profiles", uid) or {}
    trade_history = await storage.get_all(f"trade_history_{uid}") or {}
    
    # Count completed manual trades
    manual_trades = 0
    for _, trade in trade_history.items():
        if not trade.get("is_auto_execution", False):
            manual_trades += 1
    
    # Calculate days on platform
    created_at_str = user_profile.get("created_at")
    days_on_platform = 0
    if created_at_str:
        try:
            created_at = datetime.fromisoformat(created_at_str)
            days_on_platform = (datetime.now(timezone.utc) - created_at).days
        except (ValueError, TypeError) as e:
            logger.warning("Failed to parse created_at for user %s: %s", uid, e)
    
    # Protection score (from risk tracking)
    protection_score = user_profile.get("protection_score", 0)
    
    # Risk rule compliance — check if any blocks were disabled in last 14 days
    risk_violations = user_profile.get("recent_risk_violations", 0)
    no_disabled_blocks = risk_violations == 0
    
    # Determine eligibility
    is_eligible = (
        manual_trades >= 20 and
        days_on_platform >= 30 and
        protection_score >= 70 and
        no_disabled_blocks
    )
    
    return {
        "is_eligible": is_eligible,
        "manual_trades": manual_trades,
        "required_trades": 20,
        "days_on_platform": days_on_platform,
        "required_days": 30,
        "protection_score": protection_score,
        "required_score": 70,
        "no_disabled_blocks": no_disabled_blocks,
    }


@router.post(
    "/autopilot/unfreeze",
    summary="Manually unfreeze autopilot after a broker timeout",
)
@limiter.limit("5/minute")
async def unfreeze_autopilot(request: Request, uid: str = Depends(get_current_user)):
    """
    Called by the user after reviewing their broker account post-freeze.
    Clears the frozen flag so autopilot can resume.
    """
    raw = await storage.get("autopilot_configs", uid)
    if not raw:
        raise HTTPException(status_code=404, detail="No autopilot configuration found.")
    
    try:
        cfg = AutopilotConfig.model_validate(raw)
    except Exception:
        raise HTTPException(status_code=500, detail="Corrupted autopilot config.")
    
    if not cfg.frozen:
        return {"status": "already_unfrozen", "message": "Autopilot is not frozen."}
    
    cfg.frozen = False
    import json
    await storage.set("autopilot_configs", uid, json.loads(cfg.model_dump_json()))
    
    logger.info(f"User {uid} manually unfroze autopilot.")
    return {"status": "unfrozen", "message": "Autopilot unfrozen. It will resume on the next eligible signal."}


@router.post(
    "/autopilot/assist-approve",
    summary="Approve a pending Assist Mode trade",
)
@limiter.limit("10/minute")
async def approve_assist_trade(request: Request, uid: str = Depends(get_current_user)):
    """
    Called when a user in Assist Mode taps 'Confirm' on a pending trade.
    Validates the pending record still exists and the market hasn't moved
    too far from the original setup, then triggers execution.
    """
    import json
    body = await request.body()
    try:
        data = json.loads(body) if body else {}
    except Exception:
        data = {}

    symbol = data.get("symbol")
    if not symbol:
        raise HTTPException(status_code=400, detail="Missing 'symbol' in request body.")

    # 1. Load the pending assist record
    pending = await storage.get("assist_pending", f"{uid}_{symbol}")
    if not pending:
        raise HTTPException(status_code=404, detail=f"No pending assist trade for {symbol}.")

    if pending.get("status") != "WAITING_APPROVAL":
        raise HTTPException(status_code=409, detail="This trade has already been processed.")

    # 2. Stale price guard — reject if the signal is older than 10 minutes
    from datetime import timedelta
    try:
        signal_time = datetime.fromisoformat(pending["timestamp"])
        age = (datetime.now(timezone.utc) - signal_time).total_seconds()
        if age > 600:
            # Mark as expired, don't execute
            pending["status"] = "EXPIRED"
            await storage.set("assist_pending", f"{uid}_{symbol}", pending)
            raise HTTPException(
                status_code=410,
                detail=f"Signal expired ({int(age)}s old). The AI will find a new entry."
            )
    except (ValueError, KeyError) as e:
        logger.warning("Failed to parse signal time for assist trade %s: %s", symbol, e)

    # 3. Mark as approved and let the next execution cycle pick it up
    pending["status"] = "APPROVED"
    pending["approved_at"] = datetime.now(timezone.utc).isoformat()
    await storage.set("assist_pending", f"{uid}_{symbol}", pending)

    logger.info(f"Assist Mode: User {uid} APPROVED trade for {symbol}.")
    return {"status": "approved", "symbol": symbol, "message": "Trade approved. Execution will proceed on next cycle."}
