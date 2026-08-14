from fastapi import APIRouter, Depends, HTTPException
from security import get_current_user
from storage import storage

router = APIRouter()

@router.get("/drawings/{symbol}", tags=["Drawings"])
async def get_drawings(symbol: str, uid: str = Depends(get_current_user)):
    user_key = f"{uid}_{symbol}"
    data = await storage.get("drawings", user_key)
    return {"drawings": data.get("items", []) if data else []}


# NOTE: /drawings/validate MUST be registered BEFORE /drawings/{symbol} (POST).
# FastAPI matches routes in registration order. If the dynamic route /{symbol}
# comes first, a POST to /drawings/validate is caught with symbol="validate"
# instead of reaching this handler.
@router.post("/drawings/validate", tags=["Drawings"])
async def validate_drawing(req: DrawingValidationRequest, uid: str = Depends(get_current_user)):
    from state import VALID_SYMBOLS
    clean_symbol = req.symbol.replace("/", "").upper()
    if clean_symbol not in VALID_SYMBOLS:
        raise HTTPException(status_code=400, detail="Invalid symbol")
    live_snapshot = streamer.get_latest_snapshot(clean_symbol)
    mock_candles = generate_mock_candles(live_snapshot.close)
    result = validate_user_level(req.price, mock_candles)
    return result


@router.post("/drawings/{symbol}", tags=["Drawings"])
async def save_drawings(symbol: str, data: DrawingData, uid: str = Depends(get_current_user)):
    # SECURITY (APT-03): Cap payload size to prevent Firestore bloat attacks.
    # An attacker could upload multi-megabyte JSON payloads to inflate cloud bills.
    # FIX: Use len(bytes) not sys.getsizeof() — getsizeof measures Python object
    # memory (includes interpreter overhead), NOT the serialized payload size.
    import json as _json
    payload_bytes = len(_json.dumps(data.drawings).encode("utf-8"))
    MAX_DRAWING_BYTES = 50_000  # 50 KB hard cap on serialized JSON
    if payload_bytes > MAX_DRAWING_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"Drawing payload too large ({payload_bytes} bytes). Maximum is {MAX_DRAWING_BYTES} bytes."
        )
    user_key = f"{uid}_{symbol}"
    await storage.set("drawings", user_key, {"items": data.drawings})
    logger.info("Saved %d drawings for %s (user: %s)", len(data.drawings), symbol, uid)
    return {"status": "ok", "count": len(data.drawings)}




# ──────────────────────────────────────────────
#  Self-Correction Layer (Post-Mortem)
# ──────────────────────────────────────────────

@router.post("/den/post-mortem", tags=["Self-Correction"])
@limiter.limit("2/minute")
async def trigger_post_mortem(request: Request, req: PostMortemLossRequest, uid: str = Depends(get_current_user)):
    new_rule = await post_mortem.analyze_loss(
        symbol=req.symbol,
        direction=req.direction,
        snapshot_dump=req.snapshot_dump,
        original_consensus=req.original_consensus,
    )
    return {"status": "Constitution amended", "new_rule": new_rule}
