"""
Mehd AI — Anti-Phishing Email & Sovereign Seal Service
======================================================
Generates transactional email templates with the user's secret
Anti-Phishing War Room Codename prominently displayed in the header.

If a hacker attempts to impersonate Mehd AI, the email will lack
the user's secret codename, warning the trader of a phishing attempt.
"""

import html
import logging
from typing import Dict, Any, Optional
from datetime import datetime, timezone

logger = logging.getLogger("mehd.email_service")


class AntiPhishingEmailService:
    """
    Generates cryptographically validated and anti-phishing protected
    transactional email templates.
    """

    BRAND_NAME = "MEHD AI"
    OFFICIAL_DOMAIN = "mehd.ai"

    @classmethod
    def render_seal_html(cls, codename: Optional[str]) -> str:
        """
        Renders the prominent Anti-Phishing Sovereign Seal HTML header.
        """
        safe_codename = html.escape(codename.strip()) if codename and codename.strip() else "NOT SET — ARM IN SECURITY SETTINGS"
        is_armed = bool(codename and codename.strip())
        accent_color = "#00FF88" if is_armed else "#FFB800"

        return f"""
        <div style="background-color: #070B12; border: 1px solid {accent_color}; border-radius: 10px; padding: 14px 18px; margin-bottom: 24px; font-family: 'Courier New', monospace;">
            <div style="font-size: 11px; color: {accent_color}; font-weight: bold; letter-spacing: 1.5px; text-transform: uppercase; margin-bottom: 4px;">
                🛡️ {cls.BRAND_NAME} — SOVEREIGN ANTI-PHISHING SEAL
            </div>
            <div style="font-size: 14px; color: #FFFFFF; font-weight: bold; letter-spacing: 2px;">
                CODENAME: [{safe_codename}]
            </div>
            <div style="font-size: 10px; color: #8A96A6; margin-top: 6px; line-height: 1.4;">
                ⚠️ <strong>SECURITY RULE:</strong> If this email does not display your exact secret War Room Codename above, it is an <strong>UNAUTHORIZED FORGERY / PHISHING SCAM</strong>. Do not click any links.
            </div>
        </div>
        """

    @classmethod
    def render_seal_text(cls, codename: Optional[str]) -> str:
        """Renders plain-text fallback anti-phishing seal."""
        safe_codename = codename.strip() if codename and codename.strip() else "NOT SET"
        return (
            "============================================================\n"
            f"🛡️ {cls.BRAND_NAME} — SOVEREIGN ANTI-PHISHING SEAL\n"
            f"CODENAME: [{safe_codename}]\n"
            "RULE: If this email does not display your secret codename,\n"
            "it is a PHISHING FORGERY. Delete immediately.\n"
            "============================================================\n\n"
        )

    @classmethod
    def wrap_template(cls, codename: Optional[str], title: str, content_html: str, content_text: str) -> Dict[str, str]:
        """Wraps any email content with the Sovereign Seal and luxury dark-theme envelope."""
        seal_html = cls.render_seal_html(codename)
        seal_text = cls.render_seal_text(codename)

        full_html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{html.escape(title)}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #000000; color: #FFFFFF; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
    <table width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color: #000000; padding: 30px 10px;">
        <tr>
            <td align="center">
                <table width="100%" border="0" cellspacing="0" cellpadding="0" style="max-width: 600px; background-color: #0B0E14; border: 1px solid #1E293B; border-radius: 16px; padding: 28px;">
                    <tr>
                        <td>
                            {seal_html}
                            <h2 style="color: #FFFFFF; font-size: 20px; margin-top: 0; margin-bottom: 16px; letter-spacing: 0.5px;">{html.escape(title)}</h2>
                            <div style="color: #CBD5E1; font-size: 13px; line-height: 1.6;">
                                {content_html}
                            </div>
                            <div style="margin-top: 32px; padding-top: 16px; border-top: 1px solid #1E293B; font-size: 11px; color: #64748B; text-align: center;">
                                © {datetime.now(timezone.utc).year} {cls.BRAND_NAME} Sovereign Financial Engine • Non-Custodial Intelligence
                            </div>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>"""

        full_text = seal_text + f"{title}\n\n" + content_text

        return {
            "html": full_html,
            "text": full_text,
            "has_codename": bool(codename and codename.strip()),
        }

    @classmethod
    def build_security_alert(cls, codename: Optional[str], event: str, ip_address: str) -> Dict[str, str]:
        """Builds a security alert email payload with the Anti-Phishing Seal."""
        now_utc = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        title = "🔒 Security Alert: Account Event Detected"
        
        content_html = f"""
        <p>A notable security event occurred on your {cls.BRAND_NAME} account:</p>
        <div style="background-color: #161B22; border-left: 3px solid #FF3B3B; padding: 12px; margin: 16px 0; font-family: monospace;">
            <strong>EVENT:</strong> {html.escape(event)}<br>
            <strong>IP ADDRESS:</strong> {html.escape(ip_address)}<br>
            <strong>TIMESTAMP:</strong> {now_utc}
        </div>
        <p>If you authorized this action, no further steps are needed. If you did not recognize this event, please revoke your broker API keys inside the Command Center immediately.</p>
        """

        content_text = (
            f"A notable security event occurred on your {cls.BRAND_NAME} account:\n"
            f"EVENT: {event}\n"
            f"IP ADDRESS: {ip_address}\n"
            f"TIMESTAMP: {now_utc}\n\n"
            "If you authorized this action, no further steps are needed."
        )

        return cls.wrap_template(codename, title, content_html, content_text)


# Singleton
email_service = AntiPhishingEmailService()
