import hmac
import hashlib
import json
import logging
from fastapi import APIRouter, Request, HTTPException
from storage import storage

logger = logging.getLogger("payments_paddle")
router = APIRouter()

def _verify_paddle_signature(payload: bytes, signature_header: str) -> bool:
    """
    Paddle v2 webhook signature verification.
    Header format: ts=<timestamp>;h1=<hmac_sha256_hex>
    Signed string: '<timestamp>:<raw_body>'
    """
    if not PADDLE_WEBHOOK_SECRET:
        logger.critical("PADDLE_WEBHOOK_SECRET is not set — bouncing webhook")
        return False
    try:
        parts = dict(item.split("=", 1) for item in signature_header.split(";"))
        ts = parts.get("ts", "")
        h1 = parts.get("h1", "")
        if not ts or not h1:
            return False
        # Replay attack guard: reject events older than 5 minutes
        if abs(time.time() - int(ts)) > 300:
            logger.warning("PADDLE WEBHOOK: Replay attack detected — timestamp %s", ts)
            return False
        signed_payload = f"{ts}:{payload.decode('utf-8')}"
        expected = hmac.new(
            PADDLE_WEBHOOK_SECRET.encode("utf-8"),
            signed_payload.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, h1)
    except Exception as e:
        logger.error("Paddle signature verification error: %s", e)
        return False


def _verify_paystack_signature(payload: bytes, signature_header: str) -> bool:
    """
    Paystack webhook signature verification.
    Header: x-paystack-signature = HMAC-SHA512(raw_body, secret_key)
    """
    if not PAYSTACK_SECRET_KEY:
        logger.critical("PAYSTACK_SECRET_KEY is not set — bouncing webhook")
        return False
    try:
        expected = hmac.new(
            PAYSTACK_SECRET_KEY.encode("utf-8"),
            payload,
            hashlib.sha512,
        ).hexdigest()
        return hmac.compare_digest(expected, signature_header)
    except Exception as e:
        logger.error("Paystack signature verification error: %s", e)
        return False


# ──────────────────────────────────────────────
#  Idempotency Guard
# ──────────────────────────────────────────────

async def _is_already_processed(event_id: str) -> bool:
    """Returns True if the event has already been processed."""
    if event_id in _processed_event_ids:
        return True
    from storage import storage
    if await storage.get("webhook_events", event_id):
        _processed_event_ids.append(event_id)
        return True
    return False


async def _mark_processed(event_id: str, event_type: str) -> None:
    _processed_event_ids.append(event_id)
    from storage import storage
    await storage.set("webhook_events", event_id, {
        "processed_at": datetime.now(timezone.utc).isoformat(),
        "event_type": event_type,
    })


# ──────────────────────────────────────────────
#  Paddle Webhook Handler
# ──────────────────────────────────────────────

@router.post("/paddle-webhook", summary="Paddle webhook handler", include_in_schema=False)
@limiter.limit("100/minute")
async def paddle_webhook(request: Request):
    """
    Handles Paddle v2 subscription events:
    - subscription.created  → new subscription, grant tier
    - subscription.updated  → plan/status change (grant or revoke)
    - subscription.canceled → cancel, downgrade to observer
    - transaction.completed → (optional) one-time purchase confirmation
    """
    payload = await request.body()
    sig_header = request.headers.get("Paddle-Signature", "")

    if not _verify_paddle_signature(payload, sig_header):
        logger.critical("PADDLE WEBHOOK: Invalid signature — possible tampering")
        raise HTTPException(status_code=400, detail="Invalid webhook signature")

    import json
    try:
        event = json.loads(payload)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON payload")

    event_id   = event.get("notification_id", "")
    event_type = event.get("event_type", "")
    data       = event.get("data", {})

    logger.info("PADDLE WEBHOOK: %s (id: %s)", event_type, event_id)

    if event_id and await _is_already_processed(event_id):
        return {"status": "already_processed"}

    if event_id:
        await _mark_processed(event_id, event_type)

    # ── Extract UID from custom_data (we embed uid when creating checkout) ──
    custom_data = data.get("custom_data") or {}
    uid = custom_data.get("mehd_uid", "")

    if not uid:
        logger.warning("PADDLE WEBHOOK: No mehd_uid in custom_data for event %s", event_type)
        return {"status": "no_uid"}

    # ── Extract portal/billing management URLs from subscription data ──
    management_urls = data.get("management_urls") or {}
    portal_urls = {
        "update_payment_method": management_urls.get("update_payment_method", PRICING_URL),
        "cancel": management_urls.get("cancel", PRICING_URL),
    }

    if event_type in ("subscription.created", "subscription.updated"):
        status = data.get("status", "")
        if status in ("active", "trialing", "past_due"):
            # Find tier from price ID
            items = data.get("items") or []
            for item in items:
                price_id = (item.get("price") or {}).get("id", "")
                tier = PADDLE_TO_TIER.get(price_id)
                if tier:
                    set_user_tier(uid, tier, portal_urls)
                    logger.info("PADDLE: User %s → %s (status: %s)", uid, tier, status)
                    break
        elif status in ("canceled", "paused"):
            await _downgrade_user(uid, "paddle subscription paused/canceled")

    elif event_type == "subscription.canceled":
        await _downgrade_user(uid, "paddle subscription canceled")

    return {"status": "ok"}


# ──────────────────────────────────────────────
#  Paystack Webhook Handler
# ──────────────────────────────────────────────

