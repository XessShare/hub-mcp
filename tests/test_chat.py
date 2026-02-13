"""Tests for the /v1/chat/completions endpoint."""

from __future__ import annotations

from unittest.mock import AsyncMock

import httpx
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_chat_completions_success(client: AsyncClient) -> None:
    """Happy path: valid request returns OpenAI-compatible response."""
    resp = await client.post(
        "/v1/chat/completions",
        json={
            "model": "llama3.1:8b",
            "messages": [{"role": "user", "content": "Hello!"}],
            "temperature": 0.5,
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["object"] == "chat.completion"
    assert body["model"] == "llama3.1:8b"
    assert len(body["choices"]) == 1
    assert body["choices"][0]["message"]["role"] == "assistant"
    assert body["choices"][0]["message"]["content"] == "Hello from JBOT!"
    assert body["choices"][0]["finish_reason"] == "stop"
    assert body["usage"]["prompt_tokens"] == 10
    assert body["usage"]["completion_tokens"] == 5
    assert body["usage"]["total_tokens"] == 15
    assert body["id"].startswith("chatcmpl-")


@pytest.mark.asyncio
async def test_chat_completions_empty_messages(client: AsyncClient) -> None:
    """Empty messages list returns 422 validation error."""
    resp = await client.post(
        "/v1/chat/completions",
        json={"model": "test", "messages": []},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_chat_completions_invalid_role(client: AsyncClient) -> None:
    """Invalid role returns 422 validation error."""
    resp = await client.post(
        "/v1/chat/completions",
        json={
            "model": "test",
            "messages": [{"role": "invalid", "content": "hi"}],
        },
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_chat_completions_ollama_http_error(
    client: AsyncClient,
    mock_ollama: AsyncMock,
) -> None:
    """Ollama returns non-2xx -> 502 gateway error."""
    mock_response = httpx.Response(status_code=500, request=httpx.Request("POST", "/api/chat"))
    mock_ollama.chat.side_effect = httpx.HTTPStatusError(
        "Internal Server Error",
        request=mock_response.request,
        response=mock_response,
    )
    resp = await client.post(
        "/v1/chat/completions",
        json={
            "model": "test",
            "messages": [{"role": "user", "content": "hi"}],
        },
    )
    assert resp.status_code == 502
    assert "unavailable" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_chat_completions_ollama_connection_error(
    client: AsyncClient,
    mock_ollama: AsyncMock,
) -> None:
    """Ollama unreachable -> 502 gateway error."""
    mock_ollama.chat.side_effect = httpx.ConnectError("Connection refused")
    resp = await client.post(
        "/v1/chat/completions",
        json={
            "model": "test",
            "messages": [{"role": "user", "content": "hi"}],
        },
    )
    assert resp.status_code == 502
    assert "unreachable" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_chat_completions_temperature_bounds(client: AsyncClient) -> None:
    """Temperature outside [0, 2] returns validation error."""
    resp = await client.post(
        "/v1/chat/completions",
        json={
            "model": "test",
            "messages": [{"role": "user", "content": "hi"}],
            "temperature": 3.0,
        },
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_chat_completions_with_stop_string(
    client: AsyncClient,
    mock_ollama: AsyncMock,
) -> None:
    """Stop as a single string is accepted."""
    resp = await client.post(
        "/v1/chat/completions",
        json={
            "model": "test",
            "messages": [{"role": "user", "content": "hi"}],
            "stop": "\n",
        },
    )
    assert resp.status_code == 200
    # Verify the stop list was forwarded to Ollama
    call_kwargs = mock_ollama.chat.call_args
    assert call_kwargs.kwargs.get("stop") == ["\n"]


@pytest.mark.asyncio
async def test_chat_completions_defaults(
    client: AsyncClient,
    mock_ollama: AsyncMock,
) -> None:
    """Verify default parameter values are forwarded correctly."""
    await client.post(
        "/v1/chat/completions",
        json={
            "model": "test",
            "messages": [{"role": "user", "content": "hi"}],
        },
    )
    call_kwargs = mock_ollama.chat.call_args
    assert call_kwargs.kwargs["temperature"] == 0.7
    assert call_kwargs.kwargs["top_p"] == 1.0
    assert call_kwargs.kwargs["max_tokens"] is None
