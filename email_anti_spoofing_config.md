# ✉️ Domain Anti-Spoofing & Anti-Phishing DNS Configuration Guide

This guide details the exact cryptographic DNS records required to **completely eradicate fake emails claiming to originate from `@mehdai.com`**.

When configured, global mail providers (Gmail, Microsoft Outlook, Apple Mail, Yahoo) will automatically **REJECT and DROP** any email sent by unauthorized servers or scammers attempting to spoof your brand.

---

## 1. SPF (Sender Policy Framework) Record

- **Record Type**: `TXT`
- **Host / Name**: `@` (or `mehdai.com`)
- **Value**:
  ```text
  v=spf1 include:_spf.google.com include:sendgrid.net ip4:YOUR_SERVER_IP ~all
  ```
- **What it does**: Informs global mail servers of the exact authorized IPs/mail gateways permitted to send emails on your behalf. Any email sent from a scammer's server fails SPF validation.

---

## 2. DKIM (DomainKeys Identified Mail) Record

- **Record Type**: `TXT`
- **Host / Name**: `s1._domainkey` (or selector provided by mail provider)
- **Value**:
  ```text
  v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC3...
  ```
- **What it does**: Attaches a cryptographic signature to every legitimate email sent by your backend. Mail providers check the public key in your DNS to verify the email's integrity.

---

## 3. DMARC (Domain-based Message Authentication, Reporting & Conformance) Record

- **Record Type**: `TXT`
- **Host / Name**: `_dmarc`
- **Value**:
  ```text
  v=DMARC1; p=reject; rua=mailto:dmarc-reports@mehdai.com; ruf=mailto:security@mehdai.com; pct=100; sp=reject;
  ```
- **What it does**: 
  - `p=reject`: Instructs Gmail/Outlook to **REJECT and DELETE** any email failing SPF/DKIM authentication.
  - `rua=mailto:...`: Sends daily automated forensic reports on any fake email spoofing attempts.

---

## 4. In-App User Anti-Phishing Security Phrase

- **Client Implementation**: Integrated via `AntiPhishingService` in `lib/services/anti_phishing_service.dart`.
- **How It Protects Users**: Every email sent from MEHD AI includes the user's custom secret phrase (e.g. `"GOLDEN FALCON 2026"`). Scammers cannot guess the phrase, allowing users to verify authentic emails instantly.
