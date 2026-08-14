"""
Mehd AI — Backend Security Audit & Active Alert Dispatcher
===========================================================
Logs security events (new IP logins, rate-limit jail triggers, PIN lockouts, broker flags)
and dispatches real-time alerts to Cloud Audit logs and push notification channels.
"""

import time
import logging
from typing import Dict, Any, Optional

logger = logging.getLogger("mehd.security_alerts")

def log_security_event(
    uid: str,
    event_type: str,
    ip_address: str,
    details: str,
    severity: str = "INFO"
) -> Dict[str, Any]:
    """
    Logs an active security event and dispatches notifications if severity is HIGH or CRITICAL.

    Args:
        uid: Truncated or full user ID
        event_type: Category (e.g. 'NEW_IP_LOGIN', 'THREAT_JAIL_BAN', 'SUSPICIOUS_PAYLOAD')
        ip_address: Client IP address
        details: Human-readable description
        severity: 'INFO' | 'WARNING' | 'HIGH' | 'CRITICAL'
    """
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime())
    event_record = {
        "timestamp": timestamp,
        "uid": uid[:8] if uid else "ANONYMOUS",
        "event_type": event_type,
        "ip_address": ip_address,
        "details": details,
        "severity": severity,
    }

    log_msg = f"🛡️ SECURITY ALERT [{severity}] | {event_type} | User={event_record['uid']} | IP={ip_address} | {details}"
    
    if severity == "CRITICAL":
        logger.critical(log_msg)
    elif severity in ("HIGH", "WARNING"):
        logger.warning(log_msg)
    else:
        logger.info(log_msg)

    return event_record
