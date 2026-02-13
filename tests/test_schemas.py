"""Tests for Pydantic schema validation."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from jbot_api.models.schemas import (
    ChatCompletionRequest,
    ChatCompletionResponse,
    ChatMessage,
    EmbeddingRequest,
    HealthStatus,
    Role,
)


def test_chat_request_valid() -> None:
    """Valid chat request parses without error."""
    req = ChatCompletionRequest(
        model="llama3.1:8b",
        messages=[ChatMessage(role=Role.user, content="hi")],
    )
    assert req.model == "llama3.1:8b"
    assert req.temperature == 0.7
    assert req.stream is False


def test_chat_request_temperature_bounds() -> None:
    """Temperature > 2 fails validation."""
    with pytest.raises(ValidationError):
        ChatCompletionRequest(
            model="test",
            messages=[ChatMessage(role=Role.user, content="hi")],
            temperature=5.0,
        )


def test_chat_request_empty_messages() -> None:
    """Empty messages list fails validation."""
    with pytest.raises(ValidationError):
        ChatCompletionRequest(model="test", messages=[])


def test_chat_response_auto_fields() -> None:
    """Response auto-generates id, created, object."""
    from jbot_api.models.schemas import Choice, ChoiceMessage

    resp = ChatCompletionResponse(
        model="test",
        choices=[Choice(message=ChoiceMessage(content="hi"))],
    )
    assert resp.id.startswith("chatcmpl-")
    assert resp.object == "chat.completion"
    assert resp.created > 0


def test_embedding_request_single_string() -> None:
    """Embedding request accepts a single string."""
    req = EmbeddingRequest(model="test", input="hello")
    assert req.input == "hello"


def test_embedding_request_list_input() -> None:
    """Embedding request accepts a list of strings."""
    req = EmbeddingRequest(model="test", input=["a", "b"])
    assert req.input == ["a", "b"]


def test_health_status_values() -> None:
    """HealthStatus accepts valid literal values."""
    hs = HealthStatus(
        status="degraded",
        version="0.1.0",
        ollama="connected",
        qdrant="disconnected",
    )
    assert hs.status == "degraded"
