"""Tests for JWT authentication utilities."""

from __future__ import annotations

import pytest

from jbot_api.core.security import create_access_token, decode_access_token


def test_create_and_decode_token() -> None:
    """Round-trip: create a token and decode it back."""
    token = create_access_token("user-42", {"role": "admin"})
    claims = decode_access_token(token)
    assert claims["sub"] == "user-42"
    assert claims["role"] == "admin"
    assert "exp" in claims
    assert "iat" in claims


def test_decode_invalid_token() -> None:
    """Invalid token raises 401."""
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as exc_info:
        decode_access_token("not.a.valid.token")
    assert exc_info.value.status_code == 401


def test_create_token_with_extra_claims() -> None:
    """Extra claims are preserved in the token."""
    token = create_access_token("bot-1", {"agent": "analyst", "tier": "premium"})
    claims = decode_access_token(token)
    assert claims["agent"] == "analyst"
    assert claims["tier"] == "premium"
