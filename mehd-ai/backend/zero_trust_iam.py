"""
Day 16 — Zero-Trust Network & Service IAM Configuration

Validates service account permissions according to the principle of least privilege.
Guarantees broker keys and database roles cannot execute administrative overrides.
"""
from typing import Dict, Any

class ZeroTrustIAM:
    """Enforces least-privilege service account roles."""

    _ROLE_PERMISSIONS: Dict[str, list[str]] = {
        "trader": ["read_market", "execute_user_trade", "view_own_history"],
        "broker_gateway": ["execute_broker_order", "read_spread"],
        "admin": ["read_audit_logs", "trigger_emergency_lockdown"],
    }

    @classmethod
    def validate_action(cls, role: str, action: str) -> bool:
        """Returns True if the service role is granted permission for the action."""
        allowed = cls._ROLE_PERMISSIONS.get(role.lower(), [])
        return action in allowed
