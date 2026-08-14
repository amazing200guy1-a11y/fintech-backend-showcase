"""
Mehd AI — Storage Abstraction Layer
======================================
WHY THIS EXISTS:
Before this file, all critical data was stored in Python dicts.
Server restart = total data loss. That's fine for demos but
FATAL for production.

This file provides a StorageBackend interface with two implementations:
  1. MemoryStorage — Python dicts (current, fast, volatile)
  2. FirestoreStorage — Google Firestore (persistent, production)

HOW TO USE:
  from storage import storage
  
  # Save data
  await storage.set("drawings", "user123_EURUSD", {"lines": [...]})
  
  # Read data
  data = await storage.get("drawings", "user123_EURUSD")
  
  # Delete data
  await storage.delete("drawings", "user123_EURUSD")
  
  # List all keys in a collection
  keys = await storage.list_keys("drawings")

SWITCHING BACKENDS:
  Set STORAGE_BACKEND=firestore in .env to use Firestore.
  Default is "memory" (in-memory Python dicts).

ADDING REDIS LATER:
  Just create a RedisStorage class that implements StorageBackend,
  and add "redis" as an option in _create_backend().
"""

from __future__ import annotations

import asyncio
import json
import logging
import operator
import os
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger("mehd.storage")


# ──────────────────────────────────────────────
#  Abstract Interface
# ──────────────────────────────────────────────

class StorageBackend(ABC):
    """
    Interface that all storage backends must implement.
    Collections are like "tables" — e.g. "drawings", "briefs", "counts".
    Keys are unique identifiers within a collection.
    Values are JSON-serializable Python dicts.
    """

    @abstractmethod
    async def get(self, collection: str, key: str) -> Optional[dict]:
        """Get a single document by key. Returns None if not found."""
        ...

    @abstractmethod
    async def set(self, collection: str, key: str, value: dict) -> None:
        """Set a single document. Overwrites if exists."""
        ...

    @abstractmethod
    async def delete(self, collection: str, key: str) -> bool:
        """Delete a single document. Returns True if deleted, False if not found."""
        ...

    @abstractmethod
    async def list_keys(self, collection: str) -> list[str]:
        """List all keys in a collection."""
        ...

    @abstractmethod
    async def get_all(self, collection: str) -> dict[str, dict]:
        """Get all documents in a collection. Returns {key: value} dict."""
        ...

    @abstractmethod
    async def stream_collection(self, collection: str, chunk_size: int = 5000):
        """Yields chunks of documents from a collection to prevent OOM on large datasets."""
        yield {}

    @abstractmethod
    async def increment(self, collection: str, key: str, field: str, amount: int = 1) -> int:
        """Atomically increment a numeric field. Returns the new value."""
        ...

    @abstractmethod
    async def count(self, collection: str) -> int:
        """Count documents in a collection."""
        ...

    @abstractmethod
    async def check_and_increment(self, collection: str, key: str, field: str, limit: int) -> bool:
        """
        Atomically checks if a field is < limit, and if so, increments it.
        Returns True if successful, False if the limit was reached.
        This prevents TOCTOU (Time of Check to Time of Use) race conditions.
        """
        ...

    @abstractmethod
    async def query(self, collection: str, filters: list[tuple[str, str, Any]]) -> dict[str, dict]:
        """
        Query documents matching ALL filters. Returns {key: value} dict.
        
        Each filter is a tuple of (field_path, operator, value).
        Supported operators: '==', '!=', '<', '<=', '>', '>=', 'in', 'not-in'
        
        Example:
            await storage.query('broadcast_history', [
                ('status', 'in', ['FRESH', 'ACTIVE', 'STALE']),
                ('symbol', '==', 'EUR/USD'),
            ])
        """
        ...

    @abstractmethod
    async def acquire_lock(self, key: str, ttl_seconds: int = 30) -> bool:
        """Acquire a distributed lock. Returns True if acquired, False if already locked."""
        ...

    @abstractmethod
    async def release_lock(self, key: str) -> None:
        """Release a distributed lock."""
        ...

    @abstractmethod
    async def batch_update(self, collection: str, updates: dict[str, dict]) -> None:
        """
        Write or update multiple documents in a single bulk operation.
        Updates is a dict mapping keys to their document content.
        """
        ...


# ──────────────────────────────────────────────
#  Backend 1: In-Memory (Default, Fast, Volatile)
# ──────────────────────────────────────────────

class MemoryStorage(StorageBackend):
    """
    Stores everything in Python dicts.
    Fast, zero-config, but all data is LOST on server restart.

    For development and demos only.
    """

    def __init__(self) -> None:
        self._store: dict[str, dict[str, dict]] = {}
        self._locks: dict[str, dict] = {}
        logger.info("Storage: MemoryStorage initialized (volatile — data lost on restart)")

    def _ensure_collection(self, collection: str) -> dict[str, dict]:
        if collection not in self._store:
            self._store[collection] = {}
        return self._store[collection]

    async def get(self, collection: str, key: str) -> Optional[dict]:
        col = self._ensure_collection(collection)
        return col.get(key)

    async def set(self, collection: str, key: str, value: dict) -> None:
        col = self._ensure_collection(collection)
        col[key] = value

    async def delete(self, collection: str, key: str) -> bool:
        col = self._ensure_collection(collection)
        if key in col:
            del col[key]
            return True
        return False

    async def list_keys(self, collection: str) -> list[str]:
        col = self._ensure_collection(collection)
        return list(col.keys())

    async def get_all(self, collection: str) -> dict[str, dict]:
        return dict(self._ensure_collection(collection))

    async def stream_collection(self, collection: str, chunk_size: int = 5000):
        col = self._ensure_collection(collection)
        items = list(col.items())
        for i in range(0, len(items), chunk_size):
            yield dict(items[i:i + chunk_size])

    async def increment(self, collection: str, key: str, field: str, amount: int = 1) -> int:
        col = self._ensure_collection(collection)
        if key not in col:
            col[key] = {}
        doc = col[key]
        current = doc.get(field, 0)
        doc[field] = current + amount
        return doc[field]

    async def count(self, collection: str) -> int:
        return len(self._ensure_collection(collection))

    async def check_and_increment(self, collection: str, key: str, field: str, limit: int) -> bool:
        # NOTE: This is only atomic in single-threaded asyncio because no 'await'
        # appears between the read and write. If you introduce threading (e.g.,
        # asyncio.to_thread or a thread pool executor), this guarantee breaks and
        # you must use a proper lock or switch to FirestoreStorage with transactions.
        col = self._ensure_collection(collection)
        if key not in col:
            col[key] = {}
        doc = col[key]
        current = doc.get(field, 0)
        if current >= limit:
            return False
        doc[field] = current + 1
        return True

    async def query(self, collection: str, filters: list[tuple[str, str, Any]]) -> dict[str, dict]:
        """Filter documents in-memory using Python operators."""
        col = self._ensure_collection(collection)
        
        _OPS = {
            '==': operator.eq, '!=': operator.ne,
            '<': operator.lt, '<=': operator.le,
            '>': operator.gt, '>=': operator.ge,
        }
        
        def _matches(doc: dict) -> bool:
            for field_path, op, value in filters:
                doc_value = doc.get(field_path)
                if op == 'in':
                    if doc_value not in value:
                        return False
                elif op == 'not-in':
                    if doc_value in value:
                        return False
                else:
                    op_fn = _OPS.get(op)
                    if op_fn is None:
                        return False
                    try:
                        if not op_fn(doc_value, value):
                            return False
                    except TypeError:
                        return False
            return True
        
        return {key: doc for key, doc in col.items() if _matches(doc)}

    async def acquire_lock(self, key: str, ttl_seconds: int = 30) -> bool:
        from datetime import datetime, timezone, timedelta
        now = datetime.now(timezone.utc)
        
        # Check if lock exists and is still valid
        if key in self._locks:
            expires_at = self._locks[key].get("expires_at")
            if expires_at and expires_at > now:
                return False  # Lock is active and held
                
        # Lock is either free or expired, acquire it with TTL
        self._locks[key] = {
            "expires_at": now + timedelta(seconds=ttl_seconds)
        }
        return True

    async def release_lock(self, key: str) -> None:
        self._locks.pop(key, None)

    async def batch_update(self, collection: str, updates: dict[str, dict]) -> None:
        col = self._ensure_collection(collection)
        for k, v in updates.items():
            col[k] = v


# ──────────────────────────────────────────────
#  Backend 2: Firestore (Persistent, Production)
# ──────────────────────────────────────────────

def _create_backend() -> StorageBackend:
    """
    Create the storage backend based on STORAGE_BACKEND env var.
    Default: "memory" (in-memory Python dicts).
    Set to "firestore" for production persistence.
    """
    environment = os.getenv("ENVIRONMENT", "development").lower().strip()
    backend_type = os.getenv("STORAGE_BACKEND", "memory").lower().strip()

    if backend_type == "firestore":
        try:
            from storage_firestore import FirestoreStorage
            return FirestoreStorage()
        except Exception as e:
            if environment == "production":
                logger.critical("FATAL: FirestoreStorage failed in PRODUCTION: %s", e)
                raise
            else:
                logger.warning("FirestoreStorage unavailable locally (%s) — falling back to MemoryStorage for local dev", e)
                return MemoryStorage()

    if environment == "production":
        logger.critical("FATAL: Refusing to start in PRODUCTION without STORAGE_BACKEND=firestore.")
        raise RuntimeError(
            "FATAL: Refusing to start in PRODUCTION without STORAGE_BACKEND=firestore. "
            "MemoryStorage is volatile and will result in catastrophic data loss."
        )

    if backend_type == "memory":
        return MemoryStorage()
    else:
        logger.warning("Unknown STORAGE_BACKEND '%s' — defaulting to memory", backend_type)
        return MemoryStorage()


# ──────────────────────────────────────────────
#  Singleton — import this everywhere
# ──────────────────────────────────────────────

storage = _create_backend()
