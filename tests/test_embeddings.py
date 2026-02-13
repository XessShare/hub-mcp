"""Tests for the /v1/embeddings endpoint."""

from __future__ import annotations

from unittest.mock import AsyncMock

import httpx
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_embeddings_single_string(client: AsyncClient) -> None:
    """Happy path: single string input returns one embedding."""
    resp = await client.post(
        "/v1/embeddings",
        json={"model": "nomic-embed-text", "input": "hello world"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["object"] == "list"
    assert body["model"] == "nomic-embed-text"
    assert len(body["data"]) == 1
    assert body["data"][0]["object"] == "embedding"
    assert body["data"][0]["index"] == 0
    assert isinstance(body["data"][0]["embedding"], list)
    assert body["usage"]["prompt_tokens"] > 0


@pytest.mark.asyncio
async def test_embeddings_list_input(
    client: AsyncClient,
    mock_ollama: AsyncMock,
) -> None:
    """Input as a list of strings produces multiple embeddings."""
    mock_ollama.embed.return_value = [[0.1] * 4096, [0.2] * 4096]
    resp = await client.post(
        "/v1/embeddings",
        json={"model": "nomic-embed-text", "input": ["hello", "world"]},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["data"]) == 2
    assert body["data"][0]["index"] == 0
    assert body["data"][1]["index"] == 1


@pytest.mark.asyncio
async def test_embeddings_ollama_error(
    client: AsyncClient,
    mock_ollama: AsyncMock,
) -> None:
    """Ollama HTTP error -> 502."""
    mock_response = httpx.Response(status_code=500, request=httpx.Request("POST", "/api/embed"))
    mock_ollama.embed.side_effect = httpx.HTTPStatusError(
        "Internal Server Error",
        request=mock_response.request,
        response=mock_response,
    )
    resp = await client.post(
        "/v1/embeddings",
        json={"model": "test", "input": "hello"},
    )
    assert resp.status_code == 502


@pytest.mark.asyncio
async def test_embeddings_connection_error(
    client: AsyncClient,
    mock_ollama: AsyncMock,
) -> None:
    """Ollama unreachable -> 502."""
    mock_ollama.embed.side_effect = httpx.ConnectError("Connection refused")
    resp = await client.post(
        "/v1/embeddings",
        json={"model": "test", "input": "hello"},
    )
    assert resp.status_code == 502
    assert "unreachable" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_embeddings_missing_model(client: AsyncClient) -> None:
    """Missing model field returns 422."""
    resp = await client.post(
        "/v1/embeddings",
        json={"input": "hello"},
    )
    assert resp.status_code == 422
