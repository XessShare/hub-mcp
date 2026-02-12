"""Test fitnaai health endpoint."""

from fastapi.testclient import TestClient

from fitnaai.server import app


def test_health() -> None:
    """Health endpoint returns ok."""
    client = TestClient(app)
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert "version" in data
