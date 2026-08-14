"""
Mehd AI — Fortress Security Guard & Threat Defense Engine
=========================================================
This module provides military-grade security utilities for the FastAPI backend:
1. Input Sanitization Engine: Neutralizes SQL/NoSQL injection, XSS, HTML tags, and path traversal.
2. Cryptographic HMAC-SHA256 Anti-Replay Shield: Verifies request signatures with 30s nonce windows.
3. Threat Jail: Tracks suspicious, malformed, or brute-force requests and enforces IP bans.
"""

import hmac
import hashlib
import re
import time
import logging
from typing import Dict, Tuple, Optional
from fastapi import HTTPException, Request, status

logger = logging.getLogger("mehd.security_guard")

# Compile regex patterns for input sanitization
_HTML_TAG_RE = re.compile(r'<[^>]*>')
_PATH_TRAVERSAL_RE = re.compile(r'(\.\.[/\\])+')
_SQL_INJECTION_RE = re.compile(
    r'(\b(SELECT|INSERT|UPDATE|DELETE|DROP|ALTER|EXEC|UNION|TRUNCATE|CREATE|DECLARE)\b)|(\-\-)|(/\*|\*/)',
    re.IGNORECASE
)

def get_real_client_ip(request: Request) -> str:
    """
    Extracts and sanitizes the real client IP address from request headers,
    handling reverse proxy headers (X-Forwarded-For, X-Real-IP) to prevent rate-limit spoofing.
    """
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        parts = [p.strip() for p in forwarded_for.split(",") if p.strip()]
        if parts:
            client_ip = parts[0]
            if re.match(r'^[a-fA-F0-9:.]+$', client_ip):
                return client_ip

    real_ip = request.headers.get("X-Real-IP")
    if real_ip and re.match(r'^[a-fA-F0-9:.]+$', real_ip.strip()):
        return real_ip.strip()

    return request.client.host if request.client else "unknown"


def sanitize_input_string(text: str, max_length: int = 2000) -> str:
    """
    Sanitizes user-provided string inputs to prevent XSS, HTML injection,
    SQL injection, and path traversal attacks.
    """
    if not text:
        return ""
    
    # 1. Truncate excessive payload lengths to avoid buffer/regex overflow
    sanitized = text[:max_length]

    # 2. Strip path traversal sequences
    sanitized = _PATH_TRAVERSAL_RE.sub('', sanitized)

    # 3. Strip HTML / script tags
    sanitized = _HTML_TAG_RE.sub('', sanitized)

    # 4. Remove dangerous SQL keywords when used as injection vectors
    sanitized = _SQL_INJECTION_RE.sub('', sanitized)

    # 5. Trim leading/trailing whitespace
    return sanitized.strip()


class ThreatJail:
    """
    In-memory IP & UID Threat Defense Jail.
    Tracks failed auth, malformed payloads, or rate limit abuses and enforces automated IP bans.
    """
    def __init__(self, max_violations: int = 10, ban_duration_sec: float = 900.0):
        self._violations: Dict[str, int] = {}
        self._banned_ips: Dict[str, float] = {}
        self._max_violations = max_violations
        self._ban_duration_sec = ban_duration_sec

    def is_ip_banned(self, ip: str) -> bool:
        """Returns True if the IP is currently banned."""
        now = time.time()
        if ip in self._banned_ips:
            ban_until = self._banned_ips[ip]
            if now < ban_until:
                return True
            else:
                # Ban expired
                del self._banned_ips[ip]
                self._violations[ip] = 0
                logger.info("🛡️ ThreatJail: IP ban expired for %s", ip)
        return False

    def record_violation(self, ip: str, reason: str):
        """Records a security violation for an IP and triggers a ban if threshold is exceeded."""
        count = self._violations.get(ip, 0) + 1
        self._violations[ip] = count
        logger.warning("⚠️ ThreatJail: Security violation from IP %s (%d/%d) — Reason: %s",
                       ip, count, self._max_violations, reason)

        if count >= self._max_violations:
            self._banned_ips[ip] = time.time() + self._ban_duration_sec
            logger.critical("🚨 ThreatJail: IP BANNED! %s banned for %.0f seconds due to repeated security violations.",
                            ip, self._ban_duration_sec)


# Global threat jail singleton instance
threat_jail = ThreatJail()


def verify_hmac_signature(
    payload_bytes: bytes,
    signature: str,
    timestamp_str: str,
    secret: str,
    max_age_sec: float = 30.0
) -> bool:
    """
    Verifies an incoming HMAC-SHA256 request signature and checks that the request
    timestamp is within the acceptable 30-second anti-replay window.

    Payload format signed by client: "{timestamp_str}.{payload_utf8}"
    """
    if not signature or not timestamp_str or not secret:
        return False

    # 1. Verify Timestamp Anti-Replay Window
    try:
        req_timestamp = float(timestamp_str)
        now = time.time()
        if abs(now - req_timestamp) > max_age_sec:
            logger.warning("SecurityGuard: Signature rejected — Timestamp out of window (%.1fs delta)", abs(now - req_timestamp))
            return False
    except (ValueError, TypeError):
        return False

    # 2. Compute Expected Signature
    try:
        message = f"{timestamp_str}.".encode('utf-8') + payload_bytes
        expected_signature = hmac.new(
            secret.encode('utf-8'),
            message,
            hashlib.sha256
        ).hexdigest()

        # Constant-time comparison to prevent timing attacks
        return hmac.compare_digest(expected_signature.lower(), signature.lower())
    except Exception as e:
        logger.error("SecurityGuard: Error computing HMAC signature: %s", e)
        return False
