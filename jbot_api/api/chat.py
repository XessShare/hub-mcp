"""OpenAI-compatible ``/v1/chat/completions`` endpoint.

Proxies requests to a local Ollama instance, translating between
the OpenAI wire format and Ollama's native API.
"""

from __future__ import annotations

import json
import logging
import time
import uuid

import httpx
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

from jbot_api.core.deps import OllamaClientDep
from jbot_api.models.schemas import (
    ChatCompletionChunk,
    ChatCompletionRequest,
    ChatCompletionResponse,
    Choice,
    ChoiceMessage,
    DeltaMessage,
    StreamChoice,
    Usage,
)

logger = logging.getLogger(__name__)
router = APIRouter(tags=["Chat"])


@router.post(
    "/v1/chat/completions",
    response_model=ChatCompletionResponse,
    responses={502: {"description": "Ollama backend unavailable"}},
)
async def chat_completions(
    payload: ChatCompletionRequest,
    ollama: OllamaClientDep,
) -> ChatCompletionResponse | StreamingResponse:
    """Create a chat completion (OpenAI-compatible).

    Forwards the conversation to Ollama and returns the response in
    the standard OpenAI chat-completion format.  Supports both
    synchronous and streaming modes.

    Example:
        ```bash
        curl -X POST http://localhost:8000/v1/chat/completions \\
          -H "Content-Type: application/json" \\
          -d '{
            "model": "llama3.1:8b",
            "messages": [{"role": "user", "content": "What is 2+2?"}],
            "temperature": 0.3
          }'
        ```
    """
    messages = [{"role": m.role.value, "content": m.content} for m in payload.messages]
    stop_seqs = (
        payload.stop if isinstance(payload.stop, list) else [payload.stop] if payload.stop else None
    )

    if payload.stream:
        return _stream_response(ollama, messages, payload, stop_seqs)

    return await _sync_response(ollama, messages, payload, stop_seqs)


async def _sync_response(
    ollama: OllamaClientDep,
    messages: list[dict[str, str]],
    payload: ChatCompletionRequest,
    stop: list[str] | None,
) -> ChatCompletionResponse:
    """Handle a non-streaming chat completion."""
    try:
        result = await ollama.chat(
            messages,
            model=payload.model,
            temperature=payload.temperature,
            top_p=payload.top_p,
            max_tokens=payload.max_tokens,
            stop=stop,
            presence_penalty=payload.presence_penalty,
            frequency_penalty=payload.frequency_penalty,
        )
    except httpx.HTTPStatusError as exc:
        logger.error("Ollama HTTP error: status=%s", exc.response.status_code)
        raise HTTPException(status_code=502, detail="Ollama backend unavailable") from exc
    except httpx.HTTPError as exc:
        logger.error("Ollama connection error: %s", exc)
        raise HTTPException(status_code=502, detail="Ollama backend unreachable") from exc

    content = result.get("message", {}).get("content", "")
    eval_count = result.get("eval_count", 0)
    prompt_eval_count = result.get("prompt_eval_count", 0)

    return ChatCompletionResponse(
        model=payload.model,
        choices=[
            Choice(
                index=0,
                message=ChoiceMessage(content=content),
                finish_reason="stop",
            ),
        ],
        usage=Usage(
            prompt_tokens=prompt_eval_count,
            completion_tokens=eval_count,
            total_tokens=prompt_eval_count + eval_count,
        ),
    )


def _stream_response(
    ollama: OllamaClientDep,
    messages: list[dict[str, str]],
    payload: ChatCompletionRequest,
    stop: list[str] | None,
) -> StreamingResponse:
    """Return an SSE streaming response for chat completions."""
    completion_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"

    async def event_generator() -> ...:
        try:
            first = True
            async for chunk in ollama.chat_stream(
                messages,
                model=payload.model,
                temperature=payload.temperature,
                top_p=payload.top_p,
                max_tokens=payload.max_tokens,
                stop=stop,
            ):
                token = chunk.get("message", {}).get("content", "")
                done = chunk.get("done", False)

                delta = DeltaMessage(
                    role="assistant" if first else None,
                    content=token,
                )
                first = False

                stream_chunk = ChatCompletionChunk(
                    id=completion_id,
                    created=int(time.time()),
                    model=payload.model,
                    choices=[
                        StreamChoice(
                            index=0,
                            delta=delta,
                            finish_reason="stop" if done else None,
                        ),
                    ],
                )
                yield f"data: {stream_chunk.model_dump_json()}\n\n"

            yield "data: [DONE]\n\n"
        except httpx.HTTPError as exc:
            logger.error("Ollama stream error: %s", exc)
            error_payload = json.dumps({"error": "Ollama backend error"})
            yield f"data: {error_payload}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
