"""
Mehd AI — AES-256 User Credentials Crypto Vault
=================================================
Provides AES-256 Fernet envelope encryption and decryption for user broker API keys.
User keys are encrypted at rest BEFORE being written to Firestore or database,
and only decrypted in-memory during active order execution inside broker_gateway.py.
"""

import os
import base64
import logging
from typing import Optional, Dict
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

logger = logging.getLogger("mehd.crypto_vault")

# Salt for key derivation (Default fallback; production pulls from GCP/Env)
_DEFAULT_SALT = b"mehd_ai_sovereign_vault_salt_2026"

def _get_master_key() -> bytes:
    """Retrieve master secret or generate a deterministic Fernet key."""
    master_secret = os.getenv("CAPSULE_SIGNING_SECRET", "mehd-ai-production-vault-secret-key-change-in-prod")
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=_DEFAULT_SALT,
        iterations=100_000,
    )
    return base64.urlsafe_b64encode(kdf.derive(master_secret.encode()))

class CryptoVault:
    """AES-256 Encryption Vault for User Broker API Keys."""
    
    def __init__(self):
        self._fernet = Fernet(_get_master_key())

    def encrypt_secret(self, raw_secret: str) -> str:
        """Encrypts a plain text API key into an AES-256 Fernet token."""
        if not raw_secret:
            return ""
        try:
            encrypted_bytes = self._fernet.encrypt(raw_secret.encode("utf-8"))
            return encrypted_bytes.decode("utf-8")
        except Exception as e:
            logger.error("CryptoVault encryption failed: %s", e)
            raise RuntimeError("Failed to encrypt secret key.")

    def decrypt_secret(self, encrypted_secret: str) -> str:
        """Decrypts an AES-256 Fernet token back to raw API key."""
        if not encrypted_secret:
            return ""
        try:
            decrypted_bytes = self._fernet.decrypt(encrypted_secret.encode("utf-8"))
            return decrypted_bytes.decode("utf-8")
        except Exception as e:
            logger.error("CryptoVault decryption failed: %s", e)
            return ""

    def encrypt_credentials(self, credentials: Dict[str, str]) -> Dict[str, str]:
        """Encrypts dictionary containing api_key and account_id."""
        encrypted = {}
        for k, v in credentials.items():
            if k in ("api_key", "secret_key", "password", "token"):
                encrypted[k] = self.encrypt_secret(v)
            else:
                encrypted[k] = v
        return encrypted

    def decrypt_credentials(self, credentials: Dict[str, str]) -> Dict[str, str]:
        """Decrypts dictionary containing encrypted api_key."""
        decrypted = {}
        for k, v in credentials.items():
            if k in ("api_key", "secret_key", "password", "token"):
                decrypted[k] = self.decrypt_secret(v)
            else:
                decrypted[k] = v
        return decrypted

# Singleton Vault Instance
vault = CryptoVault()
