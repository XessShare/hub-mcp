"""Shared pytest fixtures for the JBOT API test suite."""

from __future__ import annotations

from typing import AsyncIterator
from unittest.mock import AsyncMock

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from jbot_api.main import create_app
from jbot_api.services.ollama_client import OllamaClient
from jbot_api.services.qdrant_client import QdrantClient


@pytest.fixture()
def mock_ollama() -> AsyncMock:
    """Return a mock OllamaClient with sensible defaults."""
    client = AsyncMock(spec=OllamaClient)
    client.health.return_value = True
    client.chat.return_value = {
        "message": {"role": "assistant", "content": "Hello from JBOT!"},
        "prompt_eval_count": 10,
        "eval_count": 5,
    }
    client.embed.return_value = [[0.1] * 4096]
    return client


@pytest.fixture()
def mock_qdrant() -> AsyncMock:
    """Return a mock QdrantClient with sensible defaults."""
    client = AsyncMock(spec=QdrantClient)
    client.health.return_value = True
    client.ensure_collection.return_value = None
    client.search.return_value = []
    return client


@pytest.fixture()
def app(mock_ollama: AsyncMock, mock_qdrant: AsyncMock) -> FastAPI:
    """Create a FastAPI app instance with mocked service clients."""
    application = create_app()
    application.state.ollama = mock_ollama
    application.state.qdrant = mock_qdrant
    return application


@pytest.fixture()
async def client(app: FastAPI) -> AsyncIterator[AsyncClient]:
    """Provide an async HTTP test client bound to the app."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
