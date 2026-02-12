"""fitnaai API server."""

import uvicorn
from fastapi import FastAPI

from fitnaai import __version__
from fitnaai.config import settings

app = FastAPI(
    title=settings.app_name,
    version=__version__,
    docs_url="/docs",
)


@app.get("/health")
async def health() -> dict[str, str]:
    """Health check endpoint."""
    return {"status": "ok", "version": __version__}


def run() -> None:
    """Run the API server (entry point for `fitnaai-server`)."""
    uvicorn.run(
        "fitnaai.server:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )


if __name__ == "__main__":
    run()
