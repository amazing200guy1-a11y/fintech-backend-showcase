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
        """Logs honeypot trap event and auto-bans malicious IP.

        The ban is registered in BOTH storage (persisted) AND ThreatJail
        so fortress_security_middleware blocks the IP immediately on all
        subsequent requests without needing a separate banned_ips lookup.
        """
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
        
        # Register in ThreatJail so fortress_security_middleware enforces the ban
        # immediately on all routes — max out violations to trigger instant ban.
        from security_guard import threat_jail
        for _ in range(threat_jail._max_violations):
            threat_jail.record_violation(ip_address, "HONEYPOT_TRAP_TRIGGERED")
        
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
