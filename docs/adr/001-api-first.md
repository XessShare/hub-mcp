# ADR-001: fitnaai is API-First

**Status:** Accepted
**Date:** 2026-02-12
**Decision makers:** Projektleitung

## Context

fitnaai needs a clear product direction before further development. Three paths were evaluated:

1. **API-First AI Service** — REST API, self-hosted inference, white-label capable
2. **Internal Automation Brain** — Ollama-backed, infrastructure control, no public focus
3. **Bot + API Hybrid** — Telegram/Discord front-end with API backend

## Decision

**fitnaai = API-First Core.**

No bot integrations in Phase 1. No Telegram. No Discord.

## Rationale

- Bots bind the product to third-party platforms
- A REST API is scalable, testable, and monetizable
- Bot adapters can be added later as thin clients consuming the API
- API-first aligns with Docker-first deployment on the existing GPU infrastructure

## Consequences

- `[project.optional-dependencies].bot` removed from `pyproject.toml`
- All development effort focuses on FastAPI endpoints + Ollama integration
- Telegram/Discord adapters are a future Phase (post-v1.0) and will live in a separate package or `adapters/` module
- CLI (`fitnaai` command) remains as a developer/operator tool, not a user-facing product

## Alternatives Rejected

- **Bot-first**: Platform lock-in, harder to monetize, harder to test
- **Library-only**: No deployment story, no standalone value
