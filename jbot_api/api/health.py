"""Health-check endpoint.

Reports the overall service status and connectivity to backend
dependencies (Ollama, Qdrant).
"""

from __future__ import annotations

import logging

from fastapi import APIRouter

from jbot_api.core.config import get_settings
from jbot_api.core.deps import OllamaClientDep, QdrantClientDep
from jbot_api.models.schemas import HealthStatus

logger = logging.getLogger(__name__)
router = APIRouter(tags=["Health"])


@router.get(
    "/health",
    response_model=HealthStatus,
    responses={200: {"description": "Service health status"}},
)
async def health_check(
    ollama: OllamaClientDep,
    qdrant: QdrantClientDep,
) -> HealthStatus:
    """Return the health status of the API and its dependencies.

    Checks connectivity to Ollama and Qdrant. Returns ``"ok"`` when
    both are reachable, ``"degraded"`` when one is down, and
    ``"error"`` when both are unreachable.

    Example:
        ```bash
        curl http://localhost:8000/health
        ```
    """
    settings = get_settings()
    ollama_ok = await ollama.health()
    qdrant_ok = await qdrant.health()

    if ollama_ok and qdrant_ok:
        status = "ok"
    elif ollama_ok or qdrant_ok:
        status = "degraded"
    else:
        status = "error"

    return HealthStatus(
        status=status,
        version=settings.app_version,
        ollama="connected" if ollama_ok else "disconnected",
        qdrant="connected" if qdrant_ok else "disconnected",
    )
