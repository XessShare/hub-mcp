"""JBOT API — FastAPI application entry point.

Creates the ASGI application with lifespan management for service
clients (Ollama, Qdrant) and registers all route modules.

Run with::

    uvicorn jbot_api.main:app --reload
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from jbot_api.api import chat, embeddings, health
from jbot_api.core.config import get_settings
from jbot_api.services.ollama_client import OllamaClient
from jbot_api.services.qdrant_client import QdrantClient

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Manage startup / shutdown of shared service clients."""
    settings = get_settings()

    # --- Startup ---
    logging.basicConfig(
        level=logging.DEBUG if settings.debug else logging.INFO,
        format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
    )
    logger.info("Starting %s v%s", settings.app_name, settings.app_version)

    ollama = OllamaClient(settings)
    qdrant = QdrantClient(settings)

    app.state.ollama = ollama
    app.state.qdrant = qdrant

    # Best-effort collection bootstrap
    try:
        await qdrant.ensure_collection()
    except Exception:
        logger.warning("Could not ensure Qdrant collection on startup (will retry on demand)")

    yield

    # --- Shutdown ---
    logger.info("Shutting down service clients")
    await ollama.close()
    await qdrant.close()


def create_app() -> FastAPI:
    """Application factory — builds and returns the configured FastAPI instance."""
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description=(
            "OpenAI-compatible autonomous agent platform for trading and "
            "business automation.  Backed by Ollama (local LLMs) and Qdrant "
            "(vector memory)."
        ),
        lifespan=lifespan,
    )

    # --- CORS ---
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # --- Routers ---
    app.include_router(health.router)
    app.include_router(chat.router)
    app.include_router(embeddings.router)

    return app


app = create_app()
