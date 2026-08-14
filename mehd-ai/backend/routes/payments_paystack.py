import hmac
import hashlib
import json
import logging
from fastapi import APIRouter, Request, HTTPException
from storage import storage

logger = logging.getLogger("payments_paystack")
router = APIRouter()

@router.post("/paystack-webhook", summary="Paystack webhook handler", include_in_schema=False)
@limiter.limit("100/minute")
async def paystack_webhook(request: Request):
    """
    Handles Paystack subscription events:
    - subscription.create   → new subscription, grant tier
    - subscription.disable  → cancellation, downgrade to observer
    - invoice.payment_failed → warn, do not punish immediately
    """
    payload = await request.body()
    sig_header = request.headers.get("x-paystack-signature", "")

    if not _verify_paystack_signature(payload, sig_header):
        logger.critical("PAYSTACK WEBHOOK: Invalid signature — possible tampering")
        raise HTTPException(status_code=400, detail="Invalid webhook signature")

    import json
    try:
        event = json.loads(payload)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON payload")

    event_id   = event.get("id", str(int(time.time() * 1000)))  # Paystack uses numeric IDs
    event_type = event.get("event", "")
    data       = event.get("data", {})

    logger.info("PAYSTACK WEBHOOK: %s (id: %s)", event_type, event_id)

    if str(event_id) and await _is_already_processed(str(event_id)):
        return {"status": "already_processed"}

    if event_id:
        await _mark_processed(str(event_id), event_type)

    if event_type == "subscription.create":
        # Paystack embeds customer email and plan code
        customer = data.get("customer") or {}
        email    = customer.get("email", "")
        plan     = data.get("plan") or {}
        plan_code = plan.get("plan_code", "")

        tier = PAYSTACK_TO_TIER.get(plan_code)
        if not tier:
            logger.warning("PAYSTACK: Unknown plan_code %s — cannot map to tier", plan_code)
            return {"status": "unknown_plan"}

        # Resolve UID from email via Firebase
        uid = await _uid_from_email(email)
        if not uid:
            logger.warning("PAYSTACK: No Firebase user found for email %s", email)
            return {"status": "user_not_found"}

        # Cache the email → uid mapping
        _paystack_email_to_uid[email] = uid

        # Paystack does not provide self-service portal URLs.
        # We direct users to the website billing section.
        portal_urls = {
            "update_payment_method": PRICING_URL,
            "cancel": PRICING_URL,
        }
        set_user_tier(uid, tier, portal_urls)
        logger.info("PAYSTACK: User %s (%s) → %s", uid, email, tier)

    elif event_type == "subscription.disable":
        customer  = data.get("customer") or {}
        email     = customer.get("email", "")
        uid = _paystack_email_to_uid.get(email) or await _uid_from_email(email)
        if uid:
            await _downgrade_user(uid, "paystack subscription disabled")

    elif event_type == "invoice.payment_failed":
        customer = data.get("customer") or {}
        email    = customer.get("email", "")
        uid = _paystack_email_to_uid.get(email) or await _uid_from_email(email)
        if uid:
            logger.warning("PAYSTACK PAYMENT FAILED: User %s (%s) — Paystack will retry", uid, email)

    return {"status": "ok"}


# ──────────────────────────────────────────────
#  Helper: Downgrade User
# ──────────────────────────────────────────────

