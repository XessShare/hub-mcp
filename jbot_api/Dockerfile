# --- JBOT API multi-stage Dockerfile ---
# Build: docker build -t jbot-api -f jbot_api/Dockerfile .
# Run:   docker run -p 8000:8000 jbot-api

# ---- Stage 1: builder ----
FROM python:3.11-slim AS builder

WORKDIR /build

COPY jbot_api/pyproject.toml ./
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir .

COPY jbot_api/ ./jbot_api/
RUN pip install --no-cache-dir .

# ---- Stage 2: runtime ----
FROM python:3.11-slim

# Create non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup -s /usr/sbin/nologin appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin/uvicorn /usr/local/bin/uvicorn

# Copy application code
COPY jbot_api/ ./jbot_api/

# Set ownership
RUN chown -R appuser:appgroup /app

USER appuser

# Defaults — override at runtime via env vars
ENV OLLAMA_BASE_URL=http://host.docker.internal:11434 \
    QDRANT_URL=http://host.docker.internal:6333 \
    HOST=0.0.0.0 \
    PORT=8000

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

ENTRYPOINT ["uvicorn", "jbot_api.main:app", "--host", "0.0.0.0", "--port", "8000"]
