"""Tests for the /health endpoint."""

from __future__ import annotations

from unittest.mock import AsyncMock

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_health_all_connected(client: AsyncClient) -> None:
    """Both Ollama and Qdrant reachable -> status ok."""
    resp = await client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["ollama"] == "connected"
    assert body["qdrant"] == "connected"
    assert "version" in body


@pytest.mark.asyncio
async def test_health_ollama_down(
    client: AsyncClient,
    mock_ollama: AsyncMock,
) -> None:
    """Ollama unreachable -> status degraded."""
    mock_ollama.health.return_value = False
    resp = await client.get("/health")
    body = resp.json()
    assert body["status"] == "degraded"
    assert body["ollama"] == "disconnected"
    assert body["qdrant"] == "connected"


@pytest.mark.asyncio
async def test_health_qdrant_down(
    client: AsyncClient,
    mock_qdrant: AsyncMock,
) -> None:
    """Qdrant unreachable -> status degraded."""
    mock_qdrant.health.return_value = False
    resp = await client.get("/health")
    body = resp.json()
    assert body["status"] == "degraded"
    assert body["ollama"] == "connected"
    assert body["qdrant"] == "disconnected"


@pytest.mark.asyncio
async def test_health_all_down(
    client: AsyncClient,
    mock_ollama: AsyncMock,
    mock_qdrant: AsyncMock,
) -> None:
    """Both down -> status error."""
    mock_ollama.health.return_value = False
    mock_qdrant.health.return_value = False
    resp = await client.get("/health")
    body = resp.json()
    assert body["status"] == "error"
    assert body["ollama"] == "disconnected"
    assert body["qdrant"] == "disconnected"
