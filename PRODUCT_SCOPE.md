# JBOT MVP v1 — Product Scope

## Vision

Self-hosted Claude-alternative for European SMEs.
Full data sovereignty, GDPR-compliant, runs on customer hardware.

## Target Persona

**Primary:** Head of Compliance / IT-Leiter at EU SME (50–500 employees)
- Needs AI capabilities but cannot send data to US cloud providers
- Budget for on-prem hardware or EU-hosted VPS
- Wants "ChatGPT-like" interface without vendor lock-in

**Secondary:** Fintech Founder / CTO at early-stage startup
- Needs sovereign AI for regulated industry (BaFin, FCA)
- Wants API-first integration into existing tools

## Core Problem (MVP v1)

> "We need AI assistance internally, but compliance forbids sending data to OpenAI/Anthropic cloud."

## Features (MVP v1)

### Must Have
- **Chat API** — OpenAI-compatible endpoint (`/v1/chat/completions`)
- **Embeddings API** — Vector generation (`/v1/embeddings`)
- **Document Upload** — PDF/DOCX ingestion into Qdrant vector store (`/v1/documents/upload`)
- **Role Presets** — Analyst, Researcher, Assistant (system prompt templates)
- **Audit Logging** — Every request logged with timestamp, user, model, token count
- **Health Endpoint** — Service status for monitoring (`/health`)
- **Self-Host Installer** — Single `docker compose up -d` deployment

### Should Have
- **Web UI** — Login, Chat, Upload, Role Dropdown (minimal)
- **API Key Auth** — Bearer token authentication for API access
- **Rate Limiting** — Per-user request throttling

### Won't Have (v1)
- Multi-agent orchestration
- Trading execution or financial data feeds
- Complex workflow / flow builder
- Voice interface
- Multi-tenant SaaS
- Low-code builder
- Managed cloud hosting

## Technical Stack

| Component       | Technology              | Purpose                    |
|-----------------|-------------------------|----------------------------|
| LLM Runtime     | Ollama (ROCm)           | Local model inference      |
| Vector DB       | Qdrant                  | Document search/RAG        |
| Primary DB      | PostgreSQL 16           | Users, audit logs, config  |
| Cache           | Redis 7                 | Session, rate limiting     |
| Reverse Proxy   | Traefik v3              | TLS, routing, middleware   |
| API Framework   | FastAPI (Python)        | Core business logic        |
| GPU             | AMD RX 6800 XT (ROCm)  | Inference acceleration     |
| Host            | Proxmox VE 9 / LXC     | Virtualization             |

## API Surface (v1)

```
POST /v1/chat/completions     — OpenAI-compatible chat
POST /v1/embeddings           — Generate vector embeddings
POST /v1/documents/upload     — Ingest document into vector store
GET  /v1/documents            — List uploaded documents
DELETE /v1/documents/{id}     — Remove document from store
GET  /health                  — Service health status
```

## Success Criteria

1. User can chat with local LLM through web UI in < 2s first-token latency
2. User can upload a PDF and ask questions about its content (RAG)
3. All data stays on-premises — zero external API calls for inference
4. Audit log captures every interaction with full traceability
5. Deployment from zero to running in < 30 minutes on prepared hardware

## Deployment Model (v1)

**Self-hosted only.**
Customer runs `docker compose up -d` on their own infrastructure.
We provide documentation, compose files, and config templates.

Managed EU Cloud offering is deferred to v2.

## Compliance Stance

- GDPR: No data leaves customer infrastructure
- No telemetry, no phone-home, no analytics
- Qdrant telemetry disabled in production config
- Audit logs stored locally in PostgreSQL
