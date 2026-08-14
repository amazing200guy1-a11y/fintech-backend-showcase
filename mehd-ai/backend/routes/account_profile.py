from fastapi import APIRouter, Depends, Request, HTTPException
from security import get_current_user
from storage import storage
from profit_rotator import ProfitRotator
from secret_rotator import SecretRotator
from emergency_lockdown import EmergencyLockdown

router = APIRouter()

from redteam_simulation import RedTeamSimulation
from honeypot_canary import HoneypotCanary

@router.get("/security/status", tags=["Security"])
async def get_security_status(uid: str = Depends(get_current_user)):
    """Returns Day 9-25 security fortress status."""
    status = await SecretRotator.get_rotation_status(uid)
    status["redteam"] = RedTeamSimulation.run_penetration_tests()
    return status

@router.get("/admin/debug/tokens", include_in_schema=False)
async def honeypot_canary_trap(request: Request):
    """Day 19 Honeypot Trap: Auto-bans malicious scanners attempting admin access."""
    client_ip = request.client.host if request.client else "unknown"
    return await HoneypotCanary.trigger_canary_trap(client_ip, "/admin/debug/tokens", dict(request.headers))

@router.post("/security/lockdown", tags=["Security"])
async def trigger_emergency_lockdown(reason: str = "USER_TRIGGERED", uid: str = Depends(get_current_user)):
    """Triggers Day 13 emergency lockdown playbook."""
    return await EmergencyLockdown.trigger_lockdown(uid, reason)

@router.get("/account/profit-rotation", tags=["Account"])
async def get_profit_rotation(target_usd: float = 5000.0, uid: str = Depends(get_current_user)):
    """Returns B-Book Stealth Radar status and recommended broker rotation targets."""
    return await ProfitRotator.get_broker_stealth_status(uid=uid, weekly_target_usd=target_usd)

@router.delete("/account/delete", tags=["Account"])
async def delete_account(uid: str = Depends(get_current_user)):
    """
    GDPR Article 17: Right to Erasure.
    Actually deletes all user data from every storage collection.
    Also queues a Firestore deletion if credentials are available.
    """
    if uid == "demo_user":
        return {"status": "Demo accounts cannot be deleted."}

    try:
        from storage import storage

        deleted_items = []

        # 1. Delete all user drawings
        drawing_keys = await storage.list_keys("drawings")
        for key in drawing_keys:
            if key.startswith(uid):
                await storage.delete("drawings", key)
                deleted_items.append(f"drawings:{key}")

        # 2. Delete analysis counts
        if await storage.delete("analysis_counts", uid):
            deleted_items.append("analysis_counts")

        # 3. Delete journey data
        if await storage.delete("journey", uid):
            deleted_items.append("journey")

        # 4. Delete subscription & trial data
        if await storage.delete("user_tiers", uid):
            deleted_items.append("user_tiers")
        if await storage.delete("user_trials", uid):
            deleted_items.append("user_trials")

        # 5. Delete security locks
        if await storage.delete("auth_locks", uid):
            deleted_items.append("auth_locks")

        # 6. Delete daily token/reveal/backtest data (keyed with uid prefix)
        for collection in ["tokens_used", "reveals", "backtest_counts"]:
            coll_keys = await storage.list_keys(collection)
            for key in coll_keys:
                if key.startswith(uid):
                    await storage.delete(collection, key)
                    deleted_items.append(f"{collection}:{key}")

        # 7. Delete all executive briefs belonging to this user
        # Now possible because user_id was added to the ExecutiveBrief model (IDOR fix)
        brief_keys = await storage.list_keys("briefs")
        for key in brief_keys:
            brief = await storage.get("briefs", key)
            if brief and brief.get("user_id") == uid:
                await storage.delete("briefs", key)
                deleted_items.append(f"briefs:{key}")

        # 5. Log the deletion
        deletion_record = {
            "userId": uid,
            "requested_at": datetime.now(timezone.utc).isoformat(),
            "status": "COMPLETED",
            "items_deleted": deleted_items,
            "data_categories": [
                "user_profile",
                "drawings",
                "analysis_counts",
                "journey_data",
                "trade_logs",
                "consensus_logs",
                "account_events",
                "settings",
            ],
        }

        # 8. Delete legal acceptances
        if await storage.delete("legal_acceptances", uid):
            deleted_items.append("legal_acceptances")

        # 9. Delete per-user risk states
        if await storage.delete("user_risk_states", uid):
            deleted_items.append("user_risk_states")

        # 10. Delete new V1 collections (position health, watchlists, assist mode, weekly scans)
        for v1_collection in ["watchlists", "weekly_scans", "autopilot_configs"]:
            if await storage.delete(v1_collection, uid):
                deleted_items.append(v1_collection)

        # 11. Delete composite-keyed collections (user_positions, position_health, assist_pending)
        # These use keys like "{uid}_{symbol}", so we must scan for the prefix.
        for composite_collection in ["user_positions", "position_health", "assist_pending"]:
            try:
                comp_keys = await storage.list_keys(composite_collection)
                for key in comp_keys:
                    if key.startswith(uid):
                        await storage.delete(composite_collection, key)
                        deleted_items.append(f"{composite_collection}:{key}")
            except Exception as e:
                logger.warning("GDPR: Could not purge %s for %s: %s", composite_collection, uid, e)

        # Write deletion record to Firestore AND purge userId-keyed collections
        try:
            from firebase_admin import firestore as _fs

            db = _fs.client()

            # GDPR FIX: Actually delete trade_logs, consensus_logs, and account_events.
            # These are keyed by logId/eventId (not userId), so we must QUERY by userId field.
            # The admin SDK bypasses Firestore security rules, so `allow write: if false` doesn't block us.
            _gdpr_collections = ["trade_logs", "consensus_logs", "account_events"]
            for coll_name in _gdpr_collections:
                try:
                    docs = db.collection(coll_name).where("userId", "==", uid).stream()
                    batch = db.batch()
                    batch_count = 0
                    for doc in docs:
                        batch.delete(doc.reference)
                        batch_count += 1
                        # Firestore batches are limited to 500 operations
                        if batch_count >= 500:
                            batch.commit()
                            batch = db.batch()
                            batch_count = 0
                    if batch_count > 0:
                        batch.commit()
                    deleted_items.append(f"{coll_name} (queried by userId)")
                    logger.info("GDPR: Deleted %s docs from %s for user %s", batch_count, coll_name, uid)
                except Exception as coll_err:
                    logger.warning("GDPR: Could not purge %s for %s: %s", coll_name, uid, coll_err)

            # Delete user settings subcollection
            try:
                settings_docs = db.collection("users").document(uid).collection("settings").stream()
                for doc in settings_docs:
                    doc.reference.delete()
                    deleted_items.append(f"settings/{doc.id}")
            except Exception as settings_err:
                logger.warning("GDPR: Could not purge settings for %s: %s", uid, settings_err)

            db.collection("deletion_requests").document(uid).set(deletion_record)
            # Delete the actual user document
            db.collection("users").document(uid).delete()
            logger.info("GDPR: User data purged from Firestore for %s", uid)
        except Exception as e:
            logger.warning(
                "GDPR: Could not write to Firestore (%s). Logged locally.", e
            )

        logger.info(
            "GDPR: Deleted %d items for user %s", len(deleted_items), uid
        )

        return {
            "status": "deletion_completed",
            "message": (
                "Your data has been permanently deleted. "
                f"{len(deleted_items)} data items were purged."
            ),
            "items_deleted": len(deleted_items),
            "request_id": uid,
        }
    except Exception as e:
        logger.error("GDPR deletion request failed for %s: %s", uid, e)
        raise HTTPException(
            status_code=500,
            detail="Deletion request failed. Please contact support.",
        )


# ──────────────────────────────────────────────
#  Smart Watchlists (Phase 4)
# ──────────────────────────────────────────────

@router.get(
    "/watchlist",
    response_model=Watchlist,
    summary="Get user's smart watchlist",
    tags=["Account"],
)
async def get_watchlist(uid: str = Depends(get_current_user)):
    """Returns the user's curated symbol watchlist."""
    from storage import storage
    data = await storage.get("watchlists", uid)
    if not data:
        return Watchlist(user_id=uid, symbols=[])
    return Watchlist.model_validate(data)


@router.post(
    "/watchlist",
    response_model=Watchlist,
    summary="Update user's smart watchlist",
    tags=["Account"],
)
@limiter.limit("5/minute")
async def update_watchlist(
    request: Request, watchlist: Watchlist, uid: str = Depends(get_current_user)
):
    """Updates the user's symbol watchlist."""
    from storage import storage
    from state import VALID_SYMBOLS
    
    # SECURITY: Validate every symbol against the server-side allowlist
    validated_symbols = [s for s in watchlist.symbols if s in VALID_SYMBOLS]
    
    # Cap at 20 symbols to prevent storage abuse
    if len(validated_symbols) > 20:
        raise HTTPException(status_code=400, detail="Watchlist cannot exceed 20 symbols.")
    
    # Force user_id to match current session
    watchlist.user_id = uid
    watchlist.symbols = validated_symbols
    watchlist.last_updated = datetime.now(timezone.utc)
    
    await storage.set("watchlists", uid, watchlist.model_dump())
    return watchlist
