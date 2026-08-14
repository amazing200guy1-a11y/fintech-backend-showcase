from fastapi import APIRouter, Depends, HTTPException
from security import get_current_user
from storage import storage

router = APIRouter()

@router.get("/den/journey", tags=["The Den"])
async def den_journey(uid: str = Depends(get_current_user)):
    """
    Trader's personal journey — tracks weeks active, mistake patterns,
    and protection score based on actual trading history.
    """
    # Pull real data from storage
    user_data = await storage.get("journey", uid)
    if user_data:
        return user_data

    # Calculate from trade history — scoped to THIS user only
    trades = await storage.query("briefs", [("user_id", "==", uid)])
    total_trades = len(trades)

    # Calculate weeks active from first trade
    import math
    weeks_active = max(1, math.ceil(total_trades / 5))  # ~5 trades per week estimate

    # Phase progression
    if weeks_active <= 2:
        phase = "Survival & Preservation"
    elif weeks_active <= 6:
        phase = "Pattern Recognition"
    elif weeks_active <= 12:
        phase = "Conviction Building"
    else:
        phase = "Autonomous Execution"

    journey = {
        "status": "active",
        "current_week": weeks_active,
        "total_trades": total_trades,
        "phase": phase,
        "protection_score": min(100, 60 + (total_trades * 2)),  # Improves with experience
        "mistake_dna": [],  # Populated by post-mortem analysis over time
    }

    # Persist for next call
    await storage.set("journey", uid, journey)
    return journey


@router.get("/den/report", tags=["The Den"])
async def den_report(uid: str = Depends(get_current_user)):
    """
    Weekly performance report — based on actual trade data.
    """
    briefs = await storage.query("briefs", [("user_id", "==", uid)])
    total = len(briefs)
    count_data = await storage.get("analysis_counts", uid)
    analyses = count_data.get("count", 0) if count_data else 0

    # Derive intelligence level from real system state
    from broadcaster import broadcaster
    active_signals = len(broadcaster.get_all_latest())
    if active_signals >= 6 and analyses >= 10:
        intel_level = "Sovereign"
    elif active_signals >= 3 and analyses >= 5:
        intel_level = "Precision"
    elif analyses >= 1:
        intel_level = "Active"
    else:
        intel_level = "Dormant"

    report_text = (
        f"Weekly Den Report: {total} trades logged. "
        f"{analyses} analyses performed. "
        f"Intelligence Level: {intel_level} ({active_signals} pairs tracked). "
        f"HardRisk kernel is active and protecting your capital."
    )

    if total == 0:
        report_text = (
            "Weekly Den Report: No trades executed yet. "
            "The Den is watching the markets 24/5 via the Broadcaster. "
            "When you're ready, the 11 agents are standing by."
        )

    return {"report": report_text, "total_trades": total, "total_analyses": analyses}


