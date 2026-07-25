"""
Mehd AI — Push Notification Service
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

THE RETENTION ENGINE: When the Broadcaster detects a high-conviction
signal (>= 92% consensus — "The Don Decided"), fire a push notification
to all subscribed users via the FCM topic broadcast_alerts.

Free users see a teaser: "The Den detected a signal on XAU/USD."
Paid users see direction + confidence: "XAU/USD: BUY at 95% consensus."

This pulls users back into the app when they're not looking.
The most valuable notification in fintech.

Rate limit: max 1 notification per symbol per hour to prevent spam.
"""

import logging
import time
from datetime import datetime, timezone, timedelta
from storage import storage

logger = logging.getLogger("mehd.notifications")

# Track last notification time per symbol (prevent spam)
# In production with multiple workers, move this to Redis.
NOTIFICATION_COOLDOWN_SECONDS = 3600  # 1 hour per symbol

# Minimum consensus to trigger a notification
MIN_CONVICTION_PERCENT = 92.0


def _get_firebase_messaging():
    """Lazy import Firebase Admin messaging. Returns None if not configured."""
    try:
        import firebase_admin
        from firebase_admin import messaging

        # Ensure Firebase app is initialized
        if not firebase_admin._apps:
            logger.debug("Firebase Admin not initialized — notifications disabled.")
            return None

        return messaging
    except ImportError:
        logger.debug("firebase_admin not installed — notifications disabled.")
        return None
    except Exception as e:
        logger.debug("Firebase messaging unavailable: %s", e)
        return None


async def send_high_conviction_alert(
    symbol: str,
    direction: str,
    confidence: float,
    vote_count: int = 0,
) -> bool:
    """
    Send a push notification when a high-conviction signal is detected.

    Args:
        symbol: The trading pair (e.g., "XAU/USD")
        direction: BUY, SELL, or HOLD
        confidence: Consensus percentage (0-100)
        vote_count: Number of agents that voted

    Returns:
        True if notification was sent, False if skipped/failed.
    """
    # Skip if below conviction threshold
    if confidence < MIN_CONVICTION_PERCENT:
        return False

    # Skip if direction is HOLD — no signal
    if direction == "HOLD":
        return False

    # Rate limit: 1 notification per symbol per hour
    now = time.time()
    last_time_doc = await storage.get("notification_cooldowns", symbol)
    last_time = last_time_doc.get("last_time", 0) if last_time_doc else 0
    
    if (now - last_time) < NOTIFICATION_COOLDOWN_SECONDS:
        remaining = int(NOTIFICATION_COOLDOWN_SECONDS - (now - last_time))
        logger.debug(
            "NOTIFY: Skipping %s — cooldown active (%ds remaining)",
            symbol, remaining,
        )
        return False

    messaging = _get_firebase_messaging()
    if messaging is None:
        logger.debug("NOTIFY: Firebase messaging not available — skipping.")
        return False

    try:
        # Build the notification message
        # Topic: 'broadcast_alerts' — all users who opted in to trade signals
        emoji = "🟢" if direction == "BUY" else "🔴"
        
        # Two versions: teaser (free) and full (paid)
        # We send to a topic — ALL subscribers get the teaser.
        # The Flutter client decides whether to show teaser or full
        # based on the user's local tier.
        message = messaging.Message(
            topic="broadcast_alerts",
            notification=messaging.Notification(
                title=f"{emoji} The Den detected a signal on {symbol}",
                body=f"Open to see the full 11-agent consensus breakdown.",
            ),
            data={
                "symbol": symbol,
                "direction": direction,
                "confidence": str(round(confidence, 1)),
                "vote_count": str(vote_count),
                "type": "high_conviction_signal",
            },
            # Android-specific: high priority, custom sound
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="mehd_signals",
                    priority="high",
                    default_sound=True,
                    click_action="FLUTTER_NOTIFICATION_CLICK",
                ),
            ),
            # iOS-specific: badge, sound
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        badge=1,
                        sound="default",
                        category="SIGNAL_ALERT",
                    ),
                ),
            ),
        )

        # Send the notification
        response = messaging.send(message)
        await storage.set("notification_cooldowns", symbol, {
            "last_time": now,
            "expires_at": (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat(),
        })

        logger.info(
            "🔔 NOTIFY SENT: %s %s at %.1f%% confidence (msg: %s)",
            symbol, direction, confidence, response,
        )
        return True

    except Exception as e:
        logger.error("NOTIFY FAILED for %s: %s", symbol, e)
        return False


async def send_personalized_ticker_alert(user_id: str, symbol: str, personalized_message: str) -> bool:
    """
    Sends a personalized push notification directly to a specific user.
    """
    messaging = _get_firebase_messaging()
    if messaging is None:
        logger.debug("NOTIFY: Firebase messaging not available — skipping personalized alert.")
        return False

    try:
        # Push directly to this user's topic
        message = messaging.Message(
            topic=f"user_{user_id}",
            notification=messaging.Notification(
                title=f"MEHD Executive Brief — {symbol}",
                body=personalized_message,
            ),
            data={
                "type": "PERSONAL_TICKER_ALERT",
                "symbol": symbol,
                "message": personalized_message,
                "user_id": user_id,
            },
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(badge=1, sound="default"),
                )
            ),
        )
        response = messaging.send(message)
        logger.info(f"🔔 PERSONAL PUSH sent to {user_id} for {symbol}: {response}")
        return True
    except Exception as e:
        logger.error(f"Failed to send personal alert to {user_id}: {e}")
        return False


async def send_critical_autopilot_alert(user_id: str, symbol: str) -> bool:
    """
    Sends a real targeted FCM push notification when auto-execution is frozen.
    """
    messaging = _get_firebase_messaging()
    if messaging is None:
        logger.debug("NOTIFY: Firebase messaging not available for critical alert — skipping.")
        return False

    try:
        message = messaging.Message(
            topic=f"autopilot_{user_id}",
            notification=messaging.Notification(
                title="⚠️ AUTO-EXECUTION FROZEN",
                body=f"Broker timeout on {symbol}. Manual review required. Autopilot halted until you unfreeze.",
            ),
            data={
                "type": "AUTOPILOT_FREEZE",
                "symbol": symbol,
                "user_id": user_id,
                "action": "MANUAL_REVIEW_REQUIRED",
            },
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="critical_alert.aiff", badge=1),
                )
            ),
        )
        response = messaging.send(message)
        logger.info(f"🔔 CRITICAL PUSH sent to user {user_id}: {response}")
        return True
    except Exception as e:
        logger.error(f"Failed to send critical alert to {user_id}: {e}")
        return False

