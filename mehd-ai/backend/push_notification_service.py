"""
Mehd AI — FCM Push Notification Service
=========================================

Sends Firebase Cloud Messaging push notifications to individual users
when "The Don Decided" — i.e., the 11-agent consensus reaches >= 92%.

DESIGN:
  - Uses firebase_admin SDK to send via FCM HTTP v1 API.
  - Only fires when consensus >= 92% AND proceed == True.
  - Fetches all active FCM tokens from Firestore `user_fcm_tokens` collection.
  - Sends per-token (not topic) for maximum control and delivery reliability.
  - Fire-and-forget: notification failures NEVER block signal broadcasting.

FIRESTORE SCHEMA:
  user_fcm_tokens/{user_id}
    token: str              — FCM device registration token
    platform: str           — "android" | "ios" | "web"
    updated_at: str         — ISO timestamp of last token refresh

CONVICTION THRESHOLD:
  The Don does not bother users for weak signals.
  Only >= 92% consensus earns a push notification.
  This is "The Don Decided" — the highest conviction available.
"""

import logging
from typing import Optional

logger = logging.getLogger("mehd.push_notification")

# ──────────────────────────────────────────────
#  Conviction Threshold
# ──────────────────────────────────────────────

# The Don Decided: Only send push when consensus >= this threshold.
# This is intentionally high — we do NOT spam users.
THE_DON_THRESHOLD = 92.0


# ──────────────────────────────────────────────
#  FCM Service
# ──────────────────────────────────────────────

class PushNotificationService:
    """
    Firebase Cloud Messaging service for "The Don Decided" alerts.
    
    Wired into the Broadcaster via set_notification_callback().
    Called only when a signal reaches >= 92% consensus.
    """

    def __init__(self):
        self._firebase_app = None
        self._messaging = None
        self._initialized = False
        self._init_firebase()

    def _init_firebase(self) -> None:
        """Initialize firebase_admin SDK. Safe no-op if not configured."""
        try:
            import firebase_admin
            from firebase_admin import credentials, messaging

            # Only initialize if not already done (singleton pattern)
            if not firebase_admin._apps:
                # firebase_admin looks for GOOGLE_APPLICATION_CREDENTIALS env var
                # or uses Application Default Credentials on GCP.
                cred = credentials.ApplicationDefault()
                self._firebase_app = firebase_admin.initialize_app(cred)
                logger.info("PushNotificationService: Firebase Admin SDK initialized.")
            else:
                self._firebase_app = firebase_admin.get_app()
                logger.info("PushNotificationService: Using existing Firebase Admin app.")

            self._messaging = messaging
            self._initialized = True

        except ImportError:
            logger.warning(
                "PushNotificationService: firebase_admin not installed. "
                "Run: pip install firebase-admin. Push notifications disabled."
            )
        except Exception as e:
            logger.warning(
                "PushNotificationService: Firebase Admin init failed (%s). "
                "Ensure GOOGLE_APPLICATION_CREDENTIALS is set or running on GCP. "
                "Push notifications disabled.", e
            )

    @property
    def is_ready(self) -> bool:
        return self._initialized and self._messaging is not None

    async def send_don_decided_alert(self, notification_payload: dict) -> None:
        """
        Entry point called by the Broadcaster's notification callback.
        
        Args:
            notification_payload: dict from BroadcastSignal.to_notification()
              {
                "title": "🟢 XAU/USD — BUY Signal",
                "body": "The Den reached 95% consensus. 11 AI agents analyzed the market.",
                "data": {
                  "symbol": "XAU/USD",
                  "direction": "BUY",
                  "consensus_pct": 95.0,
                  "proceed": True,
                  ...
                }
              }
        """
        if not notification_payload:
            return

        data = notification_payload.get("data", {})

        # THE DON THRESHOLD: Only send if conviction is high enough
        consensus_pct = float(data.get("consensus_pct", 0))
        if consensus_pct < THE_DON_THRESHOLD:
            logger.debug(
                "PushNotification: Skipping — consensus %.0f%% below The Don Threshold (%.0f%%).",
                consensus_pct, THE_DON_THRESHOLD
            )
            return

        # PROCEED GATE: Only push if the Den says the signal is actionable
        # If 10 agents say BUY but the HardRiskKernel vetoes it, proceed=False.
        # In that case we don't buzz the user's phone — the trade is not cleared.
        proceed = str(data.get("proceed", "False")).lower() in ("true", "1", "yes")
        if not proceed:
            logger.debug(
                "PushNotification: Skipping — consensus %.0f%% but proceed=False (signal vetoed).",
                consensus_pct
            )
            return

        if not self.is_ready:
            logger.debug("PushNotification: Service not ready. Skipping.")
            return

        logger.info(
            "🔔 THE DON DECIDED: Sending push notification — %s %.0f%% consensus.",
            notification_payload.get("data", {}).get("symbol", "?"),
            consensus_pct,
        )

        # Fetch all active FCM tokens from Firestore
        try:
            from storage import storage
            token_docs = await storage.get_all("user_fcm_tokens")
        except Exception as e:
            logger.error("PushNotification: Failed to fetch FCM tokens: %s", e)
            return

        if not token_docs:
            logger.debug("PushNotification: No FCM tokens registered. No users to notify.")
            return

        tokens = [
            doc.get("token")
            for doc in token_docs.values()
            if doc.get("token")
        ]

        if not tokens:
            return

        # Build FCM message payload
        title = notification_payload.get("title", "Mehd AI Alert")
        body = notification_payload.get("body", "The Den has spoken.")
        data = {str(k): str(v) for k, v in notification_payload.get("data", {}).items()}
        # Always add a type so Flutter can route it
        data["notification_type"] = "THE_DON_DECIDED"

        # Send in batches of 500 (FCM API limit per call)
        success_count = 0
        fail_count = 0
        BATCH_SIZE = 500

        for i in range(0, len(tokens), BATCH_SIZE):
            batch = tokens[i:i + BATCH_SIZE]
            try:
                message = self._messaging.MulticastMessage(
                    tokens=batch,
                    notification=self._messaging.Notification(
                        title=title,
                        body=body,
                    ),
                    data=data,
                    android=self._messaging.AndroidConfig(
                        priority="high",
                        notification=self._messaging.AndroidNotification(
                            channel_id="don_decided",
                            sound="default",
                        ),
                    ),
                    apns=self._messaging.APNSConfig(
                        payload=self._messaging.APNSPayload(
                            aps=self._messaging.Aps(
                                sound="default",
                                badge=1,
                            )
                        )
                    ),
                )
                response = self._messaging.send_each_for_multicast(message)
                success_count += response.success_count
                fail_count += response.failure_count

                # Clean up invalid tokens (device unregistered, app uninstalled, etc.)
                if response.failure_count > 0:
                    await self._clean_invalid_tokens(batch, response.responses, token_docs)

            except Exception as e:
                logger.error("PushNotification: Batch send failed: %s", e)
                fail_count += len(batch)

        logger.info(
            "🔔 THE DON DECIDED: Push sent — %d success, %d failed (of %d total tokens).",
            success_count, fail_count, len(tokens)
        )

    async def _clean_invalid_tokens(
        self,
        batch_tokens: list,
        responses: list,
        token_docs: dict,
    ) -> None:
        """Remove stale/invalid FCM tokens from Firestore."""
        try:
            from storage import storage
            # Build a reverse map: token → user_id
            token_to_uid = {
                doc.get("token"): uid
                for uid, doc in token_docs.items()
                if doc.get("token")
            }

            for token, response in zip(batch_tokens, responses):
                if not response.success:
                    error_code = getattr(getattr(response, "exception", None), "code", "")
                    # These error codes mean the token is permanently dead
                    if error_code in ("registration-token-not-registered", "invalid-argument"):
                        uid = token_to_uid.get(token)
                        if uid:
                            try:
                                await storage.delete("user_fcm_tokens", uid)
                                logger.info("Cleaned invalid FCM token for user %s", uid)
                            except Exception as e:
                                logger.warning("Failed to clean token for %s: %s", uid, e)
        except Exception as e:
            logger.warning("Token cleanup failed: %s", e)


# Singleton
push_service = PushNotificationService()
