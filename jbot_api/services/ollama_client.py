"""Async HTTP client for the Ollama REST API.

Wraps Ollama's ``/api/chat`` and ``/api/embed`` endpoints behind a
clean async interface that the rest of JBOT consumes via dependency
injection.
"""

from __future__ import annotations

import logging
from typing import Any, AsyncIterator

import httpx

from jbot_api.core.config import Settings

logger = logging.getLogger(__name__)


class OllamaClient:
    """Thin async wrapper around Ollama's local HTTP API.

    Args:
        settings: Application settings providing base URL and timeout.
    """

    def __init__(self, settings: Settings) -> None:
        self._base_url = settings.ollama_base_url.rstrip("/")
        self._default_model = settings.ollama_default_model
        self._client = httpx.AsyncClient(
            base_url=self._base_url,
            timeout=httpx.Timeout(settings.ollama_timeout, connect=10.0),
        )

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    async def close(self) -> None:
        """Close the underlying HTTP connection pool."""
        await self._client.aclose()

    async def health(self) -> bool:
        """Return ``True`` if Ollama is reachable."""
        try:
            resp = await self._client.get("/")
            return resp.status_code == 200
        except httpx.HTTPError:
            return False

    # ------------------------------------------------------------------
    # Chat completions
    # ------------------------------------------------------------------

    async def chat(
        self,
        messages: list[dict[str, str]],
        model: str | None = None,
        *,
        temperature: float = 0.7,
        top_p: float = 1.0,
        max_tokens: int | None = None,
        stop: list[str] | None = None,
        presence_penalty: float = 0.0,
        frequency_penalty: float = 0.0,
    ) -> dict[str, Any]:
        """Send a chat request to Ollama and return the full response.

        Args:
            messages: Conversation messages in ``[{"role": ..., "content": ...}]`` format.
            model: Ollama model tag; falls back to the configured default.
            temperature: Sampling temperature.
            top_p: Nucleus sampling parameter.
            max_tokens: Maximum tokens to generate.
            stop: Stop sequences.
            presence_penalty: Presence penalty (mapped to Ollama's repeat_penalty).
            frequency_penalty: Frequency penalty (mapped to Ollama's repeat_penalty).

        Returns:
            Raw JSON response from Ollama ``/api/chat``.

        Raises:
            httpx.HTTPStatusError: On non-2xx responses.

        Example:
            >>> resp = await client.chat([{"role": "user", "content": "Hi"}])
            >>> print(resp["message"]["content"])
        """
        body: dict[str, Any] = {
            "model": model or self._default_model,
            "messages": messages,
            "stream": False,
            "options": {
                "temperature": temperature,
                "top_p": top_p,
            },
        }
        if max_tokens is not None:
            body["options"]["num_predict"] = max_tokens
        if stop:
            body["options"]["stop"] = stop
        # Map OpenAI penalties → Ollama repeat_penalty (additive blend)
        combined_penalty = 1.0 + abs(presence_penalty) + abs(frequency_penalty)
        if combined_penalty > 1.0:
            body["options"]["repeat_penalty"] = combined_penalty

        resp = await self._client.post("/api/chat", json=body)
        resp.raise_for_status()
        return resp.json()

    async def chat_stream(
        self,
        messages: list[dict[str, str]],
        model: str | None = None,
        *,
        temperature: float = 0.7,
        top_p: float = 1.0,
        max_tokens: int | None = None,
        stop: list[str] | None = None,
    ) -> AsyncIterator[dict[str, Any]]:
        """Stream chat tokens from Ollama.

        Yields:
            Parsed JSON objects for each streamed chunk.

        Example:
            >>> async for chunk in client.chat_stream([{"role": "user", "content": "Hi"}]):
            ...     print(chunk["message"]["content"], end="")
        """
        body: dict[str, Any] = {
            "model": model or self._default_model,
            "messages": messages,
            "stream": True,
            "options": {"temperature": temperature, "top_p": top_p},
        }
        if max_tokens is not None:
            body["options"]["num_predict"] = max_tokens
        if stop:
            body["options"]["stop"] = stop

        async with self._client.stream("POST", "/api/chat", json=body) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.strip():
                    continue
                import json

                yield json.loads(line)

    # ------------------------------------------------------------------
    # Embeddings
    # ------------------------------------------------------------------

    async def embed(
        self,
        texts: list[str],
        model: str | None = None,
    ) -> list[list[float]]:
        """Generate embeddings for a batch of texts.

        Args:
            texts: Input texts to embed.
            model: Embedding model tag; defaults to configured default.

        Returns:
            List of float vectors, one per input text.

        Raises:
            httpx.HTTPStatusError: On non-2xx responses.

        Example:
            >>> vectors = await client.embed(["hello world"])
            >>> len(vectors[0])  # embedding dimension
            4096
        """
        resolved_model = model or self._default_model
        embeddings: list[list[float]] = []
        for text in texts:
            resp = await self._client.post(
                "/api/embed",
                json={"model": resolved_model, "input": text},
            )
            resp.raise_for_status()
            data = resp.json()
            embeddings.extend(data.get("embeddings", []))
        return embeddings
