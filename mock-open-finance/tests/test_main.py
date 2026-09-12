import time

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_get_config_default():
    resp = client.get("/config")
    assert resp.status_code == 200
    body = resp.json()
    assert "min_ms" in body and "max_ms" in body


def test_set_latency_updates_config():
    resp = client.put("/config/latency", json={"min_ms": 10, "max_ms": 20})
    assert resp.status_code == 200
    assert resp.json()["config"] == {"min_ms": 10, "max_ms": 20}

    resp = client.get("/config")
    assert resp.json() == {"min_ms": 10, "max_ms": 20}


def test_profile_is_deterministic_and_respects_latency():
    client.put("/config/latency", json={"min_ms": 5, "max_ms": 15})

    start = time.monotonic()
    r1 = client.post("/open-finance/profile/abc123")
    elapsed_ms = (time.monotonic() - start) * 1000
    assert r1.status_code == 200
    assert elapsed_ms >= 5

    r2 = client.post("/open-finance/profile/abc123")
    body1, body2 = r1.json(), r2.json()
    for key in ("income", "risk_score", "age", "debt_ratio"):
        assert body1[key] == body2[key]


def test_enrich_returns_expected_shape():
    client.put("/config/latency", json={"min_ms": 0, "max_ms": 5})
    resp = client.post(
        "/open-finance/enrich/client-1", params={"consentimiento_id": "cons-1"}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["client_id"] == "client-1"
    assert body["consentimiento_id"] == "cons-1"
    assert 300 <= body["credit_score"] <= 900
    assert len(body["products"]) >= 1
