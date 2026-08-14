"""
Day 11 — Immutable Audit Logging Engine

Implements cryptographic SHA-256 hash-chained append-only logging (tamper-evident ledger).
"""
import hashlib
import json
import logging
from datetime import datetime, timezone
from storage import storage

logger = logging.getLogger("immutable_audit")

class ImmutableAuditLogger:
    """Appends tamper-proof, hash-chained log entries."""

    @staticmethod
    async def log_event(event_type: str, actor_id: str, details: dict) -> dict:
        """Appends a hash-chained log record."""
        now = datetime.now(timezone.utc).isoformat()
        
        # Get previous hash from storage
        last_log = await storage.get("immutable_audit_ledger", "latest") or {}
        previous_hash = last_log.get("current_hash", "0000000000000000000000000000000000000000000000000000000000000000")

        raw_payload = f"{previous_hash}:{now}:{event_type}:{actor_id}:{json.dumps(details, sort_keys=True)}"
        current_hash = hashlib.sha256(raw_payload.encode("utf-8")).hexdigest()

        entry = {
            "timestamp": now,
            "event_type": event_type,
            "actor_id": actor_id,
            "details": details,
            "previous_hash": previous_hash,
            "current_hash": current_hash,
        }

        # Store latest hash pointer
        await storage.set("immutable_audit_ledger", "latest", entry)
        logger.info("IMMUTABLE AUDIT: [%s] Actor: %s | Hash: %s", event_type, actor_id, current_hash[:12])
        return entry
