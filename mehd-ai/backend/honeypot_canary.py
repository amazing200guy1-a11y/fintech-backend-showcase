"""
Day 19 — Honeypots, Deception Tech & Canary Wire Installation

Exposes decoy canary endpoints (e.g. /admin/debug/tokens) that log attacker IP/headers
and instantly auto-ban malicious actors attempting unauthorized probing.
"""
import logging
from datetime import datetime, timezone
from storage import storage

logger = logging.getLogger("honeypot_canary")

class HoneypotCanary:
    """Manages decoy trap endpoints and automatic IP banning."""

    @staticmethod
    async def trigger_canary_trap(ip_address: str, endpoint: str, headers: dict) -> dict:
        """Logs honeypot trap event and auto-bans malicious IP."""
        now = datetime.now(timezone.utc).isoformat()
        
        trap_event = {
            "ip": ip_address,
            "endpoint": endpoint,
            "timestamp": now,
            "status": "AUTO_BANNED",
            "reason": "HONEYPOT_TRAP_TRIGGERED",
        }

        # Save to banned IP list in storage
        await storage.set("banned_ips", ip_address, trap_event)
        
        # Log to immutable audit ledger
        from immutable_audit_logger import ImmutableAuditLogger
        await ImmutableAuditLogger.log_event("HONEYPOT_TRAP_TRIGGERED", ip_address, trap_event)

        logger.critical("HONEYPOT TRAP: Auto-banning malicious IP %s attempting access to %s", ip_address, endpoint)
        return trap_event

    @staticmethod
    async def is_ip_banned(ip_address: str) -> bool:
        """Returns True if IP is on auto-banned list."""
        doc = await storage.get("banned_ips", ip_address)
        return doc is not None
