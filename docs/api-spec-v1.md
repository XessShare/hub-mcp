# JBOT MVP v1 — API Specification

## Base URL

```
https://jbot.internal.local:8081/v1
```

## Authentication

All endpoints require `Authorization: Bearer <api-key>` header.
API keys are stored hashed in PostgreSQL.

---

## Endpoints

### POST /v1/chat/completions

OpenAI-compatible chat completion. Proxies to local Ollama instance.

**Request:**
```json
{
  "model": "llama3.1:8b",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Summarize our Q3 report."}
  ],
  "stream": true,
  "temperature": 0.7,
  "max_tokens": 2048
}
```

**Response (streaming):** Server-Sent Events, OpenAI format.

**Response (non-streaming):**
```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1700000000,
  "model": "llama3.1:8b",
  "choices": [
    {
      "index": 0,
      "message": {"role": "assistant", "content": "..."},
      "finish_reason": "stop"
    }
  ],
  "usage": {"prompt_tokens": 42, "completion_tokens": 128, "total_tokens": 170}
}
```

**Role Presets:** Pass preset name in system message or via `X-JBOT-Role` header.
Available presets: `analyst`, `researcher`, `assistant`.

---

### POST /v1/embeddings

Generate vector embeddings for text. Uses Ollama embedding model.

**Request:**
```json
{
  "model": "nomic-embed-text",
  "input": "European regulatory compliance framework"
}
```

**Response:**
```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "index": 0,
      "embedding": [0.0023, -0.0091, ...]
    }
  ],
  "model": "nomic-embed-text",
  "usage": {"prompt_tokens": 5, "total_tokens": 5}
}
```

---

### POST /v1/documents/upload

Upload a document for RAG ingestion. Chunks, embeds, and stores in Qdrant.

**Request:** `multipart/form-data`
- `file`: PDF, DOCX, TXT, or MD file (max 50MB)
- `collection` (optional): Target Qdrant collection (default: `default`)
- `metadata` (optional): JSON string with custom metadata

**Response:**
```json
{
  "id": "doc_abc123",
  "filename": "q3-report.pdf",
  "collection": "default",
  "chunks": 47,
  "status": "indexed",
  "created_at": "2026-02-13T10:00:00Z"
}
```

---

### GET /v1/documents

List all indexed documents.

**Query Parameters:**
- `collection` (optional): Filter by collection
- `limit` (optional): Max results (default 50)
- `offset` (optional): Pagination offset

**Response:**
```json
{
  "documents": [
    {
      "id": "doc_abc123",
      "filename": "q3-report.pdf",
      "collection": "default",
      "chunks": 47,
      "created_at": "2026-02-13T10:00:00Z"
    }
  ],
  "total": 1
}
```

---

### DELETE /v1/documents/{id}

Remove a document and its vectors from the store.

**Response:**
```json
{
  "id": "doc_abc123",
  "status": "deleted"
}
```

---

### GET /health

Service health check. No authentication required.

**Response:**
```json
{
  "status": "ok",
  "version": "0.1.0",
  "services": {
    "ollama": "healthy",
    "qdrant": "healthy",
    "postgres": "healthy",
    "redis": "healthy"
  },
  "gpu": {
    "available": true,
    "device": "AMD Radeon RX 6800 XT",
    "vram_used_mb": 4096,
    "vram_total_mb": 16384
  }
}
```

---

## Error Format

All errors follow a consistent structure:

```json
{
  "error": {
    "type": "invalid_request",
    "message": "File size exceeds 50MB limit.",
    "code": 400
  }
}
```

## Rate Limits

| Tier     | Requests/min | Tokens/min |
|----------|-------------|------------|
| Default  | 60          | 100,000    |
| Admin    | 300         | 500,000    |

Rate limit headers included in every response:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`
