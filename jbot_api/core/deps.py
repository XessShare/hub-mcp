"""FastAPI dependency injection helpers.

Provides typed ``Annotated`` aliases so route handlers can declare
service dependencies concisely::

    @router.post("/v1/chat/completions")
    async def chat(payload: ChatRequest, ollama: OllamaClientDep):
        ...
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Request

from jbot_api.services.ollama_client import OllamaClient
from jbot_api.services.qdrant_client import QdrantClient


def _get_ollama(request: Request) -> OllamaClient:
    """Retrieve the OllamaClient from application state."""
    return request.app.state.ollama


def _get_qdrant(request: Request) -> QdrantClient:
    """Retrieve the QdrantClient from application state."""
    return request.app.state.qdrant


OllamaClientDep = Annotated[OllamaClient, Depends(_get_ollama)]
QdrantClientDep = Annotated[QdrantClient, Depends(_get_qdrant)]
