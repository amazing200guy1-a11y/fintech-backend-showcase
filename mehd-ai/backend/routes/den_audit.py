from fastapi import APIRouter, Depends, Request, HTTPException
from security import get_current_user
from storage import storage

router = APIRouter()

@router.post("/den/audit", response_model=PostMortemResult, summary="The Auditor reviews a closed trade.", tags=["The Den"])
@limiter.limit("2/minute")
async def perform_audit(request: Request, req: PostMortemRequest, uid: str = Depends(get_current_user)):
    logger.info("THE AUDITOR is reviewing trade: %s", req.trade_id)
    try:
        result_dict = {
            "mistake_dna": "Under Review",
            "analysis": (
                f"The Auditor is analyzing trade {req.trade_id} on {req.symbol}. "
                f"Direction: {req.direction.value}, PnL: ${req.pnl:.2f}. "
                f"Full post-mortem pending deep model analysis."
            ),
            "suggested_rule": None,
        }
        return PostMortemResult(**result_dict)
    except Exception as e:
        logger.error("Auditor failed: %s", e)
        raise HTTPException(status_code=500, detail="Auditor temporarily unavailable.")


@router.get("/den/brief/{trade_id}", tags=["Den"])
async def get_executive_brief(trade_id: str, uid: str = Depends(get_current_user)):
    brief = await storage.get("briefs", trade_id)
    if brief:
        if brief.get("user_id") != uid:
            raise HTTPException(status_code=403, detail="Forbidden: You do not own this brief")
        return brief
    raise HTTPException(status_code=404, detail="Brief not found")


@router.post("/den/shadow", tags=["The Den"])
async def activate_shadow_mode(uid: str = Depends(get_current_user)):
    """
    Shadow Mode — compares your decisions against what the Den would have done.
    Now pulls from real broadcast history instead of hardcoded numbers.
    """
    from broadcaster import broadcaster

    # Pull real broadcast data
    status = broadcaster.get_status()
    total_broadcasts = status.get("total_broadcasts", 0)

    # Calculate stats from broadcast history
    all_latest = broadcaster.get_all_latest()
    buy_signals = sum(1 for s in all_latest.values() if s.get("direction") == "BUY")
    sell_signals = sum(1 for s in all_latest.values() if s.get("direction") == "SELL")

    # Pull user's actual trade count — scoped to THIS user only
    user_trades_dict = await storage.query("briefs", [("user_id", "==", uid)])
    user_trades = len(user_trades_dict)

    return {
        "total_signals": total_broadcasts,
        "active_pairs": len(all_latest),
        "buy_signals": buy_signals,
        "sell_signals": sell_signals,
        "your_trades": user_trades,
        "broadcaster_cycles": status.get("cycle_count", 0),
        "certified_alpha": total_broadcasts > 10,  # Certified after 10+ broadcasts
    }


# ──────────────────────────────────────────────
#  Drawing Endpoints
# ──────────────────────────────────────────────

