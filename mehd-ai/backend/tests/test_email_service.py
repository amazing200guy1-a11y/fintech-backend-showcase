"""
Test Suite: Anti-Phishing Email Service & Sovereign Seal Fidelity
=================================================================
Verifies that all outgoing email templates include the user's secret
War Room Codename, escape malicious inputs, and warn against phishing.
"""

import pytest
from email_service import email_service


class TestAntiPhishingSealFidelity:
    """Ensures Anti-Phishing Codename Seal is consistently rendered."""

    def test_armed_codename_renders_in_html_and_text(self):
        codename = "Golden Falcon 2026"
        res = email_service.wrap_template(
            codename=codename,
            title="Test Alert",
            content_html="<p>Test content</p>",
            content_text="Test content",
        )

        assert res["has_codename"] is True
        assert "CODENAME: [Golden Falcon 2026]" in res["html"]
        assert "CODENAME: [Golden Falcon 2026]" in res["text"]
        assert "SOVEREIGN ANTI-PHISHING SEAL" in res["html"]

    def test_missing_codename_warns_unarmed(self):
        res = email_service.wrap_template(
            codename=None,
            title="Test Alert",
            content_html="<p>Test</p>",
            content_text="Test",
        )

        assert res["has_codename"] is False
        assert "NOT SET" in res["html"]

    def test_xss_injection_in_codename_is_escaped(self):
        malicious_codename = "<script>alert('pwned')</script>"
        res = email_service.wrap_template(
            codename=malicious_codename,
            title="Test Alert",
            content_html="<p>Test</p>",
            content_text="Test",
        )

        assert "<script>" not in res["html"]
        assert "&lt;script&gt;alert(&#x27;pwned&#x27;)&lt;/script&gt;" in res["html"]

    def test_security_alert_payload_generation(self):
        codename = "AlphaPredator_99"
        alert = email_service.build_security_alert(
            codename=codename,
            event="New IP Login from 192.168.1.1",
            ip_address="192.168.1.1",
        )

        assert alert["has_codename"] is True
        assert "AlphaPredator_99" in alert["html"]
        assert "192.168.1.1" in alert["html"]
        assert "Security Alert" in alert["text"]
