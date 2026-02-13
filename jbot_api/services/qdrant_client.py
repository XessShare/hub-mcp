"""Async client for the Qdrant vector database.

Provides semantic memory storage and retrieval for JBOT agents via
Qdrant's REST API over httpx.
"""

from __future__ import annotations

import logging
import uuid
from typing import Any

import httpx

from jbot_api.core.config import Settings

logger = logging.getLogger(__name__)


class QdrantClient:
    """Thin async wrapper around Qdrant's HTTP API.

    Args:
        settings: Application settings providing URL, API key, and collection defaults.
    """

    def __init__(self, settings: Settings) -> None:
        self._base_url = settings.qdrant_url.rstrip("/")
        self._collection = settings.qdrant_collection
        self._vector_size = settings.qdrant_vector_size
        headers: dict[str, str] = {"Content-Type": "application/json"}
        if settings.qdrant_api_key:
            headers["api-key"] = settings.qdrant_api_key
        self._client = httpx.AsyncClient(
            base_url=self._base_url,
            headers=headers,
            timeout=httpx.Timeout(30.0, connect=10.0),
        )

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    async def close(self) -> None:
        """Close the underlying HTTP connection pool."""
        await self._client.aclose()

    async def health(self) -> bool:
        """Return ``True`` if Qdrant is reachable and healthy."""
        try:
            resp = await self._client.get("/healthz")
            return resp.status_code == 200
        except httpx.HTTPError:
            return False

    # ------------------------------------------------------------------
    # Collection management
    # ------------------------------------------------------------------

    async def ensure_collection(self, collection: str | None = None) -> None:
        """Create the default collection if it does not already exist.

        Args:
            collection: Collection name override; uses configured default if ``None``.

        Example:
            >>> await qdrant.ensure_collection()
        """
        name = collection or self._collection
        check = await self._client.get(f"/collections/{name}")
        if check.status_code == 200:
            logger.info("Qdrant collection '%s' already exists", name)
            return

        body = {
            "vectors": {
                "size": self._vector_size,
                "distance": "Cosine",
            },
        }
        resp = await self._client.put(f"/collections/{name}", json=body)
        resp.raise_for_status()
        logger.info("Created Qdrant collection '%s'", name)

    # ------------------------------------------------------------------
    # CRUD
    # ------------------------------------------------------------------

    async def upsert(
        self,
        vectors: list[list[float]],
        payloads: list[dict[str, Any]],
        ids: list[str] | None = None,
        collection: str | None = None,
    ) -> dict[str, Any]:
        """Upsert vectors with metadata payloads into a collection.

        Args:
            vectors: List of embedding vectors.
            payloads: List of JSON-serialisable metadata dicts (same length as *vectors*).
            ids: Optional point IDs; auto-generated UUIDs if omitted.
            collection: Collection name override.

        Returns:
            Qdrant operation response.

        Raises:
            httpx.HTTPStatusError: On non-2xx responses.

        Example:
            >>> await qdrant.upsert(
            ...     vectors=[[0.1, 0.2, ...]],
            ...     payloads=[{"text": "hello", "source": "user"}],
            ... )
        """
        name = collection or self._collection
        resolved_ids = ids or [uuid.uuid4().hex for _ in vectors]
        points = [
            {"id": pid, "vector": vec, "payload": pl}
            for pid, vec, pl in zip(resolved_ids, vectors, payloads)
        ]
        resp = await self._client.put(
            f"/collections/{name}/points",
            json={"points": points},
        )
        resp.raise_for_status()
        return resp.json()

    async def search(
        self,
        vector: list[float],
        limit: int = 5,
        score_threshold: float | None = None,
        collection: str | None = None,
    ) -> list[dict[str, Any]]:
        """Search for the nearest neighbours of a query vector.

        Args:
            vector: Query embedding vector.
            limit: Maximum number of results.
            score_threshold: Minimum similarity score filter.
            collection: Collection name override.

        Returns:
            List of result dicts containing ``id``, ``score``, and ``payload``.

        Example:
            >>> results = await qdrant.search(query_vector, limit=3)
            >>> for r in results:
            ...     print(r["payload"]["text"], r["score"])
        """
        name = collection or self._collection
        body: dict[str, Any] = {
            "vector": vector,
            "limit": limit,
            "with_payload": True,
        }
        if score_threshold is not None:
            body["score_threshold"] = score_threshold
        resp = await self._client.post(
            f"/collections/{name}/points/search",
            json=body,
        )
        resp.raise_for_status()
        return resp.json().get("result", [])

    async def delete(
        self,
        ids: list[str],
        collection: str | None = None,
    ) -> dict[str, Any]:
        """Delete points by their IDs.

        Args:
            ids: Point IDs to remove.
            collection: Collection name override.

        Returns:
            Qdrant operation response.

        Example:
            >>> await qdrant.delete(["abc123", "def456"])
        """
        name = collection or self._collection
        resp = await self._client.post(
            f"/collections/{name}/points/delete",
            json={"points": ids},
        )
        resp.raise_for_status()
        return resp.json()
