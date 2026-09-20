"""
Mehd AI — Secrets Manager (Production-Grade Secret Handling)
==============================================================
WHY THIS EXISTS:
Before this file, ALL secrets lived in a flat .env file. That works
for development, but for a financial app handling real money:
  - One `git add -f .env` and EVERY key is burned
  - No audit trail of who accessed which secret
  - No automatic rotation
  - No encryption at rest (plain text on disk)

This module provides a SecretManager that:
  1. Tries GCP Secret Manager first (if configured)
  2. Falls back to environment variables (.env)
  3. Logs every secret access for audit trail
  4. Validates that critical secrets are not defaults/placeholders

HOW TO USE:
    from secrets_manager import secrets

    # Get a secret (tries GCP first, falls back to env)
    key = secrets.get("PADDLE_WEBHOOK_SECRET")

    # Check if a secret exists and is not a placeholder
    if secrets.is_valid("CAPSULE_SIGNING_SECRET"):
        ...

ENABLING GCP SECRET MANAGER:
    1. pip install google-cloud-secret-manager
    2. Set GCP_PROJECT_ID in .env (or use Application Default Credentials)
    3. Create secrets in GCP console: Secret Manager → Create Secret
    4. Name them exactly like your env vars (e.g., CAPSULE_SIGNING_SECRET)
    5. That's it — this module auto-detects and uses them.
"""

from __future__ import annotations

import logging
import os
from functools import lru_cache
from typing import Optional

logger = logging.getLogger("mehd.secrets_manager")

# Patterns that indicate a secret is a placeholder/default
_PLACEHOLDER_PATTERNS = [
    "CHANGE-IN-PROD",      # Catches CAPSULE_SIGNING_SECRET=CHANGE-IN-PROD-...
    "ROTATED",             # Catches ...-ROTATED suffix used in default .env
    "generate_",
    "your-key-here",
    "replace-me",
    "TODO",
    "xxx",
    "default",
]


class SecretManager:
    """
    Production-grade secret retrieval with GCP Secret Manager fallback.

    Priority order:
      1. GCP Secret Manager (if google-cloud-secret-manager is installed + GCP_PROJECT_ID is set)
      2. Environment variables (from .env or system env)
      3. Default value (if provided)

    Every access is logged at DEBUG level for audit trail.
    """

    def __init__(self) -> None:
        self._gcp_client = None
        self._gcp_project = os.getenv("GCP_PROJECT_ID", "")
        self._gcp_available = False
        self._cache: dict[str, str] = {}  # In-memory cache to avoid repeated GCP calls

        # Try to initialize GCP Secret Manager
        if self._gcp_project:
            try:
                from google.cloud import secretmanager
                self._gcp_client = secretmanager.SecretManagerServiceClient()
                self._gcp_available = True
                logger.info("Secrets: GCP Secret Manager ACTIVE (project: %s)", self._gcp_project)
            except ImportError:
                logger.info(
                    "Secrets: google-cloud-secret-manager not installed. "
                    "Using .env fallback. Install with: pip install google-cloud-secret-manager"
                )
            except Exception as e:
                logger.warning("Secrets: GCP Secret Manager init failed (%s). Using .env fallback.", e)
        else:
            logger.info("Secrets: GCP_PROJECT_ID not set. Using .env variables (set GCP_PROJECT_ID to enable vault).")

    def get(self, name: str, default: str = "") -> str:
        """
        Retrieve a secret by name.

        Checks GCP Secret Manager first, then falls back to env vars.
        Results are cached in memory so GCP is only called once per secret.
        """
        # L1: In-memory cache
        if name in self._cache:
            return self._cache[name]

        # L2: GCP Secret Manager
        if self._gcp_available:
            try:
                value = self._get_from_gcp(name)
                if value is not None:
                    self._cache[name] = value
                    logger.debug("Secret '%s' loaded from GCP Secret Manager", name)
                    return value
            except Exception as e:
                logger.debug("Secret '%s' not in GCP (%s), falling back to env", name, e)

        # L3: Environment variable
        value = os.getenv(name, default)
        self._cache[name] = value
        logger.debug("Secret '%s' loaded from environment variable", name)
        return value

    def is_valid(self, name: str) -> bool:
        """
        Check if a secret exists, is non-empty, and is NOT a placeholder.
        Use this at startup to validate critical secrets.
        """
        value = self.get(name)
        if not value:
            return False
        value_lower = value.lower()
        return not any(p.lower() in value_lower for p in _PLACEHOLDER_PATTERNS)

    def require(self, name: str) -> str:
        """
        Get a secret or raise RuntimeError if it's missing/placeholder.
        Use this for secrets that MUST exist (app won't start without them).
        """
        if not self.is_valid(name):
            value = self.get(name)
            if not value:
                raise RuntimeError(
                    f"FATAL: Required secret '{name}' is missing. "
                    f"Set it in .env or GCP Secret Manager."
                )
            else:
                raise RuntimeError(
                    f"FATAL: Required secret '{name}' appears to be a placeholder/default value. "
                    f"Replace it with a real production secret."
                )
        return self.get(name)

    def audit_status(self) -> dict:
        """
        Returns a summary of secret health for startup logging.
        Does NOT reveal actual secret values — only status.
        """
        critical_secrets = [
            "CAPSULE_SIGNING_SECRET",
            "PADDLE_WEBHOOK_SECRET",
            "PAYSTACK_SECRET_KEY",
        ]
        status = {}
        for name in critical_secrets:
            value = self.get(name)
            if not value:
                status[name] = "MISSING"
            elif not self.is_valid(name):
                status[name] = "PLACEHOLDER"
            else:
                status[name] = "ACTIVE"
        return {
            "backend": "gcp_secret_manager" if self._gcp_available else "env_file",
            "secrets": status,
        }

    def _get_from_gcp(self, name: str) -> Optional[str]:
        """Fetch a secret from GCP Secret Manager."""
        if not self._gcp_client or not self._gcp_project:
            return None

        try:
            resource_name = f"projects/{self._gcp_project}/secrets/{name}/versions/latest"
            response = self._gcp_client.access_secret_version(request={"name": resource_name})
            return response.payload.data.decode("utf-8")
        except Exception:
            return None

    def clear_cache(self) -> None:
        """Clear the in-memory cache. Useful for secret rotation."""
        self._cache.clear()
        logger.info("Secrets: In-memory cache cleared (secrets will be re-fetched)")


# ──────────────────────────────────────────────
#  Data Encryption (At-Rest Protection)
# ──────────────────────────────────────────────

class DataEncryption:
    """
    Encrypts and decrypts sensitive user data at rest (e.g., Broker API keys in Firestore).
    Uses a master key stored in GCP Secret Manager (or .env).
    
    SECURITY FIX (C3): No more hardcoded fallback key. If no key is set:
      - Production: Refuses to start (RuntimeError)
      - Development: Falls back to plaintext with a loud warning
    """
    def __init__(self, master_key: str):
        import base64
        import hashlib
        
        environment = os.getenv("ENVIRONMENT", "development").lower().strip()
        self._master_key = master_key
        self._legacy_fernet = None
        
        if not master_key:
            if environment == "production":
                raise RuntimeError(
                    "FATAL: ENCRYPTION_MASTER_KEY is not set. "
                    "Refusing to start in production without encryption. "
                    "Set ENCRYPTION_MASTER_KEY in .env or GCP Secret Manager."
                )
            logger.warning(
                "⚠️  ENCRYPTION DISABLED: No ENCRYPTION_MASTER_KEY set. "
                "Broker API keys will be stored in PLAIN TEXT. "
                "This is acceptable for development only."
            )
            self._fernet = None
            return
        
        try:
            from cryptography.fernet import Fernet
            # Hash to exactly 32 bytes and encode as url-safe base64 for Fernet fallback
            key_bytes = hashlib.sha256(master_key.encode("utf-8")).digest()
            self._legacy_fernet = Fernet(base64.urlsafe_b64encode(key_bytes))
            # Set self._fernet to a dummy truthy value so encrypt/decrypt logic knows we have a master key
            self._fernet = True
        except ImportError:
            logger.warning("cryptography not installed. Encryption is disabled (PLAIN TEXT MODE). Install with: pip install cryptography")
            self._fernet = None

    def encrypt(self, plain_text: str) -> str:
        if not plain_text:
            return ""
        if not self._fernet:
            return plain_text # Plain text fallback if cryptography missing
            
        import base64
        import os
        from cryptography.fernet import Fernet
        from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
        from cryptography.hazmat.primitives import hashes
        
        # Generate a random 16-byte salt
        salt = os.urandom(16)
        
        # Derive key via PBKDF2 with 600,000 iterations
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=salt,
            iterations=600000,
        )
        derived_key = base64.urlsafe_b64encode(kdf.derive(self._master_key.encode("utf-8")))
        
        # Encrypt
        f = Fernet(derived_key)
        ciphertext = f.encrypt(plain_text.encode("utf-8"))
        
        # Format: v2:salt_b64:ciphertext_b64
        salt_b64 = base64.b64encode(salt).decode("utf-8")
        ciphertext_b64 = base64.b64encode(ciphertext).decode("utf-8")
        return f"v2:{salt_b64}:{ciphertext_b64}"

    def decrypt(self, encrypted_text: str) -> str:
        if not encrypted_text:
            return ""
        if not self._fernet:
            return encrypted_text
            
        import base64
        from cryptography.fernet import Fernet
        from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
        from cryptography.hazmat.primitives import hashes

        # Check for v2 format (PBKDF2)
        if encrypted_text.startswith("v2:"):
            try:
                parts = encrypted_text.split(":")
                if len(parts) != 3:
                    raise ValueError("Malformed v2 encrypted text")
                
                salt = base64.b64decode(parts[1])
                ciphertext = base64.b64decode(parts[2])
                
                kdf = PBKDF2HMAC(
                    algorithm=hashes.SHA256(),
                    length=32,
                    salt=salt,
                    iterations=600000,
                )
                derived_key = base64.urlsafe_b64encode(kdf.derive(self._master_key.encode("utf-8")))
                f = Fernet(derived_key)
                return f.decrypt(ciphertext).decode("utf-8")
            except Exception as e:
                logger.error("Failed to decrypt v2 format: %s", e)
                return ""
        
        # Legacy fallback
        try:
            if self._legacy_fernet:
                return self._legacy_fernet.decrypt(encrypted_text.encode("utf-8")).decode("utf-8")
        except Exception as e:
            logger.error("Failed to decrypt legacy format (wrong master key or corrupted data): %s", e)
        return ""

# ──────────────────────────────────────────────
#  Singleton — import this everywhere
# ──────────────────────────────────────────────

secrets = SecretManager()
encryption = DataEncryption(master_key=secrets.get("ENCRYPTION_MASTER_KEY", ""))
