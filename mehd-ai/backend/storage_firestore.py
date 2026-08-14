import os
import asyncio
import logging
from typing import Any, Optional
from storage import StorageBackend, MemoryStorage

logger = logging.getLogger("storage_firestore")

class FirestoreStorage(StorageBackend):
    """
    Stores everything in Google Cloud Firestore.
    Persistent, scalable, production-ready.

    Requires FIREBASE_CREDENTIALS_PATH or Application Default Credentials.
    """

    def __init__(self) -> None:
        try:
            import firebase_admin
            from firebase_admin import firestore as _fs

            # Initialize Firebase if not already done
            if not firebase_admin._apps:
                cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
                if cred_path and Path(cred_path).exists():
                    cred = firebase_admin.credentials.Certificate(cred_path)
                    firebase_admin.initialize_app(cred)
                else:
                    firebase_admin.initialize_app()

            self._db = _fs.client()
            self._fallback = None
            logger.info("Storage: FirestoreStorage initialized (persistent — production mode)")
        except Exception as e:
            env = os.getenv("ENVIRONMENT", "development").lower().strip()
            if env == "production" and os.getenv("FIREBASE_CREDENTIALS_PATH"):
                logger.critical("FATAL: FirestoreStorage failed to initialize in production: %s", e)
                raise RuntimeError(f"FirestoreStorage failed to initialize: {e}")
            else:
                logger.warning("FirestoreStorage: GCP credentials not found locally (%s). Delegating to local MemoryStorage.", e)
                self._db = None
                self._fallback = MemoryStorage()

    async def get(self, collection: str, key: str) -> Optional[dict]:
        if self._db is None and self._fallback is not None:
            return await self._fallback.get(collection, key)
        try:
            doc = await asyncio.wait_for(
                asyncio.to_thread(lambda: self._db.collection(collection).document(key).get()),
                timeout=15.0
            )
            return doc.to_dict() if doc.exists else None
        except Exception as e:
            logger.error("Firestore get failed: %s", e)
            return None

    async def set(self, collection: str, key: str, value: dict) -> None:
        if self._db is None and self._fallback is not None:
            return await self._fallback.set(collection, key, value)
        try:
            await asyncio.wait_for(
                asyncio.to_thread(lambda: self._db.collection(collection).document(key).set(value)),
                timeout=15.0
            )
        except Exception as e:
            logger.error("Firestore set failed: %s", e)

    async def delete(self, collection: str, key: str) -> bool:
        if self._db is None and self._fallback is not None:
            return await self._fallback.delete(collection, key)
        try:
            await asyncio.wait_for(
                asyncio.to_thread(lambda: self._db.collection(collection).document(key).delete()),
                timeout=15.0
            )
            return True
        except Exception as e:
            logger.error("Firestore delete failed: %s", e)
            return False

    async def list_keys(self, collection: str) -> list[str]:
        if self._db is None and self._fallback is not None:
            return await self._fallback.list_keys(collection)
        try:
            docs = await asyncio.wait_for(
                asyncio.to_thread(lambda: list(self._db.collection(collection).select([]).stream())),
                timeout=30.0
            )
            return [doc.id for doc in docs]
        except Exception as e:
            logger.error("Firestore list_keys failed: %s", e)
            return []

    async def get_all(self, collection: str) -> dict[str, dict]:
        if self._db is None and self._fallback is not None:
            return await self._fallback.get_all(collection)
        try:
            docs = await asyncio.wait_for(
                asyncio.to_thread(lambda: list(self._db.collection(collection).stream())),
                timeout=30.0
            )
            return {doc.id: doc.to_dict() for doc in docs}
        except Exception as e:
            logger.error("Firestore get_all failed: %s", e)
            return {}

    async def stream_collection(self, collection: str, chunk_size: int = 5000):
        if self._db is None and self._fallback is not None:
            async for chunk in self._fallback.stream_collection(collection, chunk_size):
                yield chunk
            return
        try:
            ref = self._db.collection(collection)
            def _get_chunk(last_doc=None):
                query = ref.order_by("__name__").limit(chunk_size)
                if last_doc:
                    query = query.start_after(last_doc)
                return list(query.stream())

            last_doc = None
            while True:
                chunk = await asyncio.wait_for(
                    asyncio.to_thread(_get_chunk, last_doc),
                    timeout=30.0
                )
                if not chunk:
                    break
                yield {doc.id: doc.to_dict() for doc in chunk}
                last_doc = chunk[-1]
        except Exception as e:
            logger.error("Firestore stream_collection failed: %s", e)

    async def increment(self, collection: str, key: str, field: str, amount: int = 1) -> int:
        if self._db is None and self._fallback is not None:
            return await self._fallback.increment(collection, key, field, amount)
        try:
            from google.cloud.firestore_v1 import Increment
            ref = self._db.collection(collection).document(key)
            def _do_increment():
                ref.set({field: Increment(amount)}, merge=True)
                doc = ref.get()
                return doc.to_dict().get(field, 0) if doc.exists else 0
            return await asyncio.wait_for(asyncio.to_thread(_do_increment), timeout=15.0)
        except Exception as e:
            logger.error("Firestore increment failed: %s", e)
            return 0

    async def count(self, collection: str) -> int:
        if self._db is None and self._fallback is not None:
            return await self._fallback.count(collection)
        try:
            docs = await asyncio.wait_for(
                asyncio.to_thread(lambda: list(self._db.collection(collection).select([]).stream())),
                timeout=30.0
            )
            return len(docs)
        except Exception as e:
            logger.error("Firestore count failed: %s", e)
            return 0

    async def check_and_increment(self, collection: str, key: str, field: str, limit: int) -> bool:
        if self._db is None and self._fallback is not None:
            return await self._fallback.check_and_increment(collection, key, field, limit)
        try:
            from google.cloud import firestore
            ref = self._db.collection(collection).document(key)
            
            @firestore.transactional
            def _tx_check_and_increment(transaction, doc_ref):
                snapshot = doc_ref.get(transaction=transaction)
                current = snapshot.to_dict().get(field, 0) if snapshot.exists else 0
                if current >= limit:
                    return False
                transaction.set(doc_ref, {field: current + 1}, merge=True)
                return True
                
            transaction = self._db.transaction()
            return await asyncio.wait_for(
                asyncio.to_thread(_tx_check_and_increment, transaction, ref),
                timeout=15.0
            )
        except Exception as e:
            logger.error("Firestore check_and_increment failed: %s", e)
            return False

    async def query(self, collection: str, filters: list[tuple[str, str, Any]]) -> dict[str, dict]:
        if self._db is None and self._fallback is not None:
            return await self._fallback.query(collection, filters)
        try:
            def _do_query():
                ref = self._db.collection(collection)
                for field_path, op, value in filters:
                    ref = ref.where(field_path, op, value)
                return list(ref.stream())
            
            docs = await asyncio.wait_for(asyncio.to_thread(_do_query), timeout=30.0)
            return {doc.id: doc.to_dict() for doc in docs}
        except Exception as e:
            logger.error("Firestore query failed: %s", e)
            return {}

    async def acquire_lock(self, key: str, ttl_seconds: int = 30) -> bool:
        if self._db is None and self._fallback is not None:
            return await self._fallback.acquire_lock(key, ttl_seconds)
        try:
            from google.cloud import firestore
            from datetime import datetime, timezone, timedelta
            ref = self._db.collection("system_locks").document(key)
            
            @firestore.transactional
            def _tx_acquire_lock(transaction, doc_ref):
                snapshot = doc_ref.get(transaction=transaction)
                now = datetime.now(timezone.utc)
                
                if snapshot.exists:
                    expires_at_str = snapshot.to_dict().get("expires_at")
                    if expires_at_str:
                        expires_at = datetime.fromisoformat(expires_at_str)
                        if expires_at > now:
                            return False # Lock is currently held
                            
                # Acquire lock
                expires_new = now + timedelta(seconds=ttl_seconds)
                transaction.set(doc_ref, {"expires_at": expires_new.isoformat()})
                return True
                
            transaction = self._db.transaction()
            return await asyncio.to_thread(_tx_acquire_lock, transaction, ref)
        except Exception as e:
            logger.error("Firestore acquire_lock failed: %s", e)
            return False

    async def release_lock(self, key: str) -> None:
        if self._db is None and self._fallback is not None:
            return await self._fallback.release_lock(key)
        try:
            await asyncio.to_thread(
                lambda: self._db.collection("system_locks").document(key).delete()
            )
        except Exception as e:
            logger.error("Firestore release_lock failed: %s", e)

    async def batch_update(self, collection: str, updates: dict[str, dict]) -> None:
        if self._db is None and self._fallback is not None:
            return await self._fallback.batch_update(collection, updates)
        try:
            items = list(updates.items())
            chunk_size = 500
            
            def _do_batches():
                for i in range(0, len(items), chunk_size):
                    batch = self._db.batch()
                    chunk = items[i:i + chunk_size]
                    for key, value in chunk:
                        ref = self._db.collection(collection).document(key)
                        batch.set(ref, value)
                    batch.commit()
            
            await asyncio.to_thread(_do_batches)
            logger.info("Firestore batch_update committed %d documents to %s", len(items), collection)
        except Exception as e:
            logger.error("Firestore batch_update failed: %s", e)


# ──────────────────────────────────────────────
#  Factory — creates the right backend
# ──────────────────────────────────────────────

