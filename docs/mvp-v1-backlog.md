# JBOT MVP v1 — Issue Backlog

> Create these as GitHub Issues. Priority: P0 = must ship, P1 = should ship, P2 = nice to have.

## P0 — Core API

### 1. [MVP] FastAPI project scaffold + health endpoint
**Labels:** `mvp-v1`, `backend`
**Acceptance:**
- FastAPI app starts on port 8000
- `GET /health` returns JSON with service status for Ollama, Qdrant, Postgres, Redis
- Docker image builds and runs in compose stack

### 2. [MVP] Chat completions endpoint (OpenAI-compatible)
**Labels:** `mvp-v1`, `backend`, `llm`
**Acceptance:**
- `POST /v1/chat/completions` proxies to Ollama
- Supports `stream: true` (SSE) and `stream: false`
- Request/response matches OpenAI format
- Returns token usage counts

### 3. [MVP] Embeddings endpoint
**Labels:** `mvp-v1`, `backend`, `llm`
**Acceptance:**
- `POST /v1/embeddings` generates vectors via Ollama (`nomic-embed-text`)
- OpenAI-compatible response format
- Returns usage info

### 4. [MVP] API key authentication middleware
**Labels:** `mvp-v1`, `backend`, `security`
**Acceptance:**
- All `/v1/*` endpoints require `Authorization: Bearer <key>`
- Keys stored as bcrypt hash in PostgreSQL
- Invalid/missing key returns 401
- `/health` accessible without auth

### 5. [MVP] Audit logging
**Labels:** `mvp-v1`, `backend`, `compliance`
**Acceptance:**
- Every API request logged to PostgreSQL: timestamp, user_id, endpoint, model, token_count, latency_ms
- Logs queryable via admin endpoint or direct SQL

---

## P0 — Document Pipeline (RAG)

### 6. [MVP] Document upload + chunking
**Labels:** `mvp-v1`, `backend`, `rag`
**Acceptance:**
- `POST /v1/documents/upload` accepts PDF, DOCX, TXT, MD (max 50MB)
- Text extracted and split into 512-token chunks (50-token overlap)
- Chunks embedded and upserted to Qdrant
- Returns document ID, chunk count, status

### 7. [MVP] RAG retrieval in chat completions
**Labels:** `mvp-v1`, `backend`, `rag`
**Acceptance:**
- When user message sent to `/v1/chat/completions`, top-k relevant chunks retrieved from Qdrant
- Chunks injected into system prompt as context
- Works with any uploaded document collection

### 8. [MVP] Document list + delete endpoints
**Labels:** `mvp-v1`, `backend`, `rag`
**Acceptance:**
- `GET /v1/documents` returns paginated list of indexed documents
- `DELETE /v1/documents/{id}` removes document metadata from Postgres and vectors from Qdrant

---

## P1 — Web UI

### 9. [MVP] Minimal chat web UI
**Labels:** `mvp-v1`, `frontend`
**Acceptance:**
- Login page (API key entry)
- Chat interface with streaming response display
- Upload button for documents
- Role dropdown (Analyst, Researcher, Assistant)
- Works in modern browsers (Chrome, Firefox, Safari)

---

## P1 — Configuration

### 10. [MVP] Role presets (system prompts)
**Labels:** `mvp-v1`, `backend`
**Acceptance:**
- Three built-in roles: Analyst, Researcher, Assistant
- Each role has a system prompt stored in config/DB
- Selectable via `X-JBOT-Role` header or UI dropdown

### 11. [MVP] Rate limiting
**Labels:** `mvp-v1`, `backend`, `security`
**Acceptance:**
- Redis-based rate limiting per API key
- Default: 60 req/min, 100k tokens/min
- Returns 429 with `X-RateLimit-*` headers when exceeded

---

## P2 — Operations

### 12. [MVP] Deployment documentation
**Labels:** `mvp-v1`, `docs`
**Acceptance:**
- README with hardware requirements, quickstart (`docker compose up -d`)
- Configuration guide (`.env`, role presets, network)
- Troubleshooting section (GPU not detected, MTU issues, Qdrant OOM)

### 13. [MVP] Automated backup for Qdrant + Postgres
**Labels:** `mvp-v1`, `ops`
**Acceptance:**
- Cron job triggers Qdrant snapshot + `pg_dump` daily
- Backups stored in `/opt/jbot/backups/` with 7-day retention
- Restore procedure documented and tested once

---

## Security Issues (create separately)

### 14. [SEC] Verify socket proxy permissions
### 15. [SEC] Confirm no internal hostnames in public DNS
### 16. [SEC] Change all default passwords
### 17. [SEC] Enable Fail2ban on Proxmox host
### 18. [SEC] Audit LXC device passthrough (minimal devices only)
