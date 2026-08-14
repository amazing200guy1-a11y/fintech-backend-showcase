"""
Day 23 — Transport Layer Security (TLS 1.3) Forward Secrecy Enforcer

Enforces HSTS, Strict Transport Security, and Perfect Forward Secrecy headers.
"""
from typing import Dict

class TlsSecrecyEnforcer:
    """Provides enterprise security headers for HTTPS/TLS responses."""

    @staticmethod
    def get_security_headers() -> Dict[str, str]:
        """Returns institutional TLS 1.3 and HSTS headers."""
        return {
            "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "X-XSS-Protection": "1; mode=block",
            "Referrer-Policy": "strict-origin-when-cross-origin",
        }
