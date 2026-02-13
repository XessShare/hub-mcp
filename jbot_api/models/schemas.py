"""OpenAI-compatible Pydantic v2 request / response schemas.

These models mirror the OpenAI API specification so that any client
built for OpenAI can talk to JBOT without modification.
"""

from __future__ import annotations

import time
import uuid
from enum import Enum
from typing import Any, Literal

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------


class Role(str, Enum):
    """Valid message roles."""

    system = "system"
    user = "user"
    assistant = "assistant"


class ChatMessage(BaseModel):
    """A single message within a conversation."""

    role: Role
    content: str


# ---------------------------------------------------------------------------
# /v1/chat/completions – Request
# ---------------------------------------------------------------------------


class ChatCompletionRequest(BaseModel):
    """OpenAI-compatible chat completion request.

    Example:
        ```json
        {
          "model": "llama3.1:8b",
          "messages": [{"role": "user", "content": "Hello!"}],
          "temperature": 0.7,
          "stream": false
        }
        ```
    """

    model: str = Field(description="Model identifier (maps to an Ollama model tag).")
    messages: list[ChatMessage] = Field(min_length=1, description="Conversation history.")
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)
    top_p: float = Field(default=1.0, ge=0.0, le=1.0)
    max_tokens: int | None = Field(default=None, ge=1)
    stream: bool = False
    stop: list[str] | str | None = None
    presence_penalty: float = Field(default=0.0, ge=-2.0, le=2.0)
    frequency_penalty: float = Field(default=0.0, ge=-2.0, le=2.0)


# ---------------------------------------------------------------------------
# /v1/chat/completions – Response
# ---------------------------------------------------------------------------


class ChoiceMessage(BaseModel):
    """The assistant message returned in a choice."""

    role: Literal["assistant"] = "assistant"
    content: str


class Choice(BaseModel):
    """A single completion choice."""

    index: int = 0
    message: ChoiceMessage
    finish_reason: Literal["stop", "length"] = "stop"


class Usage(BaseModel):
    """Token usage statistics."""

    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0


class ChatCompletionResponse(BaseModel):
    """OpenAI-compatible chat completion response.

    Example:
        ```json
        {
          "id": "chatcmpl-abc123",
          "object": "chat.completion",
          "created": 1700000000,
          "model": "llama3.1:8b",
          "choices": [{"index": 0, "message": {"role": "assistant", "content": "Hi!"}, "finish_reason": "stop"}],
          "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
        }
        ```
    """

    id: str = Field(default_factory=lambda: f"chatcmpl-{uuid.uuid4().hex[:12]}")
    object: Literal["chat.completion"] = "chat.completion"
    created: int = Field(default_factory=lambda: int(time.time()))
    model: str
    choices: list[Choice]
    usage: Usage = Field(default_factory=Usage)


# ---------------------------------------------------------------------------
# /v1/chat/completions – Streaming
# ---------------------------------------------------------------------------


class DeltaMessage(BaseModel):
    """Incremental message delta for streaming."""

    role: Literal["assistant"] | None = None
    content: str | None = None


class StreamChoice(BaseModel):
    """A single streaming chunk choice."""

    index: int = 0
    delta: DeltaMessage
    finish_reason: Literal["stop", "length"] | None = None


class ChatCompletionChunk(BaseModel):
    """OpenAI-compatible streaming chunk."""

    id: str = Field(default_factory=lambda: f"chatcmpl-{uuid.uuid4().hex[:12]}")
    object: Literal["chat.completion.chunk"] = "chat.completion.chunk"
    created: int = Field(default_factory=lambda: int(time.time()))
    model: str
    choices: list[StreamChoice]


# ---------------------------------------------------------------------------
# /v1/embeddings
# ---------------------------------------------------------------------------


class EmbeddingRequest(BaseModel):
    """OpenAI-compatible embedding request.

    Example:
        ```json
        {
          "model": "nomic-embed-text",
          "input": "The quick brown fox jumps over the lazy dog"
        }
        ```
    """

    model: str = Field(description="Embedding model identifier.")
    input: str | list[str] = Field(description="Text(s) to embed.")
    encoding_format: Literal["float", "base64"] = "float"


class EmbeddingData(BaseModel):
    """A single embedding vector."""

    object: Literal["embedding"] = "embedding"
    index: int = 0
    embedding: list[float]


class EmbeddingResponse(BaseModel):
    """OpenAI-compatible embedding response."""

    object: Literal["list"] = "list"
    model: str
    data: list[EmbeddingData]
    usage: Usage = Field(default_factory=Usage)


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------


class HealthStatus(BaseModel):
    """Service health check response."""

    status: Literal["ok", "degraded", "error"]
    version: str
    ollama: Literal["connected", "disconnected"]
    qdrant: Literal["connected", "disconnected"]
    details: dict[str, Any] = Field(default_factory=dict)


# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------


class ErrorDetail(BaseModel):
    """Structured error payload returned in HTTP error responses."""

    detail: str
    request_id: str = Field(default_factory=lambda: uuid.uuid4().hex[:16])
