# JBOT — 90-Day Roadmap

## Phase 1: Self-Hosted Claude Clone (Weeks 1–4)

> Goal: Ship MVP v1 — a working self-hosted AI assistant with RAG.

### Week 1–2: Core API
- [ ] FastAPI project scaffold with `/v1/chat/completions` proxy to Ollama
- [ ] OpenAI-compatible request/response format (streaming + non-streaming)
- [ ] `/v1/embeddings` endpoint using `nomic-embed-text`
- [ ] `/health` endpoint with service dependency checks
- [ ] API key auth middleware (Bearer token, hashed storage in Postgres)
- [ ] Audit logging to PostgreSQL (every request)

### Week 2–3: Document Pipeline
- [ ] `/v1/documents/upload` — PDF/DOCX parsing (PyMuPDF or unstructured)
- [ ] Text chunking (512 token chunks, 50 token overlap)
- [ ] Embedding generation + Qdrant upsert
- [ ] RAG retrieval in `/v1/chat/completions` (auto-inject context)
- [ ] `/v1/documents` list + `/v1/documents/{id}` delete

### Week 3–4: Web UI + Polish
- [ ] Minimal web UI: Login, Chat, Upload, Role selector
- [ ] Role presets (Analyst, Researcher, Assistant system prompts)
- [ ] Rate limiting (Redis-based, per API key)
- [ ] Error handling and input validation
- [ ] Deployment documentation (README with quickstart)

### Milestone: Internal demo with real document Q&A

---

## Phase 2: Tenant System + Templates (Weeks 5–8)

> Goal: Multi-customer readiness. Brand as "fitnaai" tenant layer.

- [ ] Tenant isolation (schema-per-tenant or row-level in Postgres)
- [ ] Tenant-scoped Qdrant collections
- [ ] Admin panel: create tenant, manage API keys, view usage
- [ ] Prompt templates / flow templates (pre-built for common tasks)
- [ ] Usage metering (tokens per tenant per day)
- [ ] Webhook support (notify on document indexed, completion done)

### Milestone: Two separate customers running on same instance, isolated

---

## Phase 3: Voice + Advanced Interface (Weeks 9–12)

> Goal: Brand as "xessshare" — voice-first sovereign AI.

- [ ] Voice input (Whisper.cpp or faster-whisper, local)
- [ ] Voice output (TTS, local — Piper or Coqui)
- [ ] Conversation memory (multi-turn with Redis-backed context)
- [ ] Model management UI (pull/delete Ollama models)
- [ ] Performance dashboard (Grafana: GPU metrics, latency, throughput)
- [ ] Automated backup verification (restore test in CI)

### Milestone: End-to-end voice conversation with document knowledge

---

## Decision Log

| Date       | Decision                                    | Rationale                              |
|------------|---------------------------------------------|----------------------------------------|
| 2026-02-13 | MVP v1 = self-hosted Claude clone           | Lowest complexity, stack already built  |
| 2026-02-13 | Self-hosted only (no managed cloud in v1)   | Focus on product, not ops              |
| 2026-02-13 | OpenAI-compatible API format                | Drop-in replacement for existing tools |
| 2026-02-13 | Defer multi-agent, trading, flow builder    | Avoid feature creep, ship fast         |
