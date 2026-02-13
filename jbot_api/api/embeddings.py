"""OpenAI-compatible ``/v1/embeddings`` endpoint.

Proxies embedding requests to Ollama and returns vectors in the
standard OpenAI format.
"""

from __future__ import annotations

import logging

import httpx
from fastapi import APIRouter, HTTPException

from jbot_api.core.deps import OllamaClientDep
from jbot_api.models.schemas import (
    EmbeddingData,
    EmbeddingRequest,
    EmbeddingResponse,
    Usage,
)

logger = logging.getLogger(__name__)
router = APIRouter(tags=["Embeddings"])


@router.post(
    "/v1/embeddings",
    response_model=EmbeddingResponse,
    responses={502: {"description": "Ollama backend unavailable"}},
)
async def create_embeddings(
    payload: EmbeddingRequest,
    ollama: OllamaClientDep,
) -> EmbeddingResponse:
    """Create embeddings for the given input text(s) (OpenAI-compatible).

    Accepts a single string or a list of strings and returns dense
    float vectors via Ollama's ``/api/embed`` endpoint.

    Example:
        ```bash
        curl -X POST http://localhost:8000/v1/embeddings \\
          -H "Content-Type: application/json" \\
          -d '{
            "model": "nomic-embed-text",
            "input": "The quick brown fox"
          }'
        ```
    """
    texts = [payload.input] if isinstance(payload.input, str) else payload.input

    try:
        vectors = await ollama.embed(texts, model=payload.model)
    except httpx.HTTPStatusError as exc:
        logger.error("Ollama embedding HTTP error: status=%s", exc.response.status_code)
        raise HTTPException(status_code=502, detail="Ollama backend unavailable") from exc
    except httpx.HTTPError as exc:
        logger.error("Ollama embedding connection error: %s", exc)
        raise HTTPException(status_code=502, detail="Ollama backend unreachable") from exc

    data = [
        EmbeddingData(index=i, embedding=vec)
        for i, vec in enumerate(vectors)
    ]
    total_tokens = sum(len(t.split()) for t in texts)

    return EmbeddingResponse(
        model=payload.model,
        data=data,
        usage=Usage(
            prompt_tokens=total_tokens,
            completion_tokens=0,
            total_tokens=total_tokens,
        ),
    )
