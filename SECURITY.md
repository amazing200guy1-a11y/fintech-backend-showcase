# Security Policy

## Supported Versions
| Version | Supported |
|---|---|
| Latest `main` | Yes |

## Reporting a Vulnerability
If you discover a security vulnerability, please do NOT open a public issue.

Email: available via GitHub profile contact.

We will respond within 48 hours and patch critical issues within 7 days.

## Security Design Principles
- All API endpoints require Firebase JWT authentication
- HMAC-SHA256 anti-replay shield (30-second nonce window)
- Automated IP ban engine (ThreatJail) on repeated failed auth attempts
- MFA enforced for Sovereign-tier execution routes
- No secrets, keys, or credentials in any repository
- FlutterSecureStorage (Keystore/Keychain) for client-side sensitive data

## Dependency Policy
- All dependencies must be pinned to exact versions in production
- Dependabot alerts reviewed weekly
- No direct `import *` patterns in security-critical modules
