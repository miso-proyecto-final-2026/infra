import httpx
import pytest
import respx
from asgi_lifespan import LifespanManager
from httpx import ASGITransport

from app.main import app


@pytest.fixture
async def client():
    async with LifespanManager(app, startup_timeout=None, shutdown_timeout=None):
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport, base_url="http://test"
        ) as ac:
            yield ac


@pytest.mark.asyncio
async def test_health(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


@pytest.mark.asyncio
@respx.mock
async def test_perfilar_cache_miss_calls_open_finance(client):
    respx.post("http://localhost:8000/open-finance/enrich/client-1").mock(
        return_value=httpx.Response(
            200,
            json={
                "income": 5_000_000,
                "savings": 1_000_000,
                "credit_score": 700,
            },
        )
    )

    resp = await client.post(
        "/perfilar", json={"client_id": "client-1", "consentimiento_id": "cons-1"}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["hit_cache"] is False
    assert body["segmento"] == "estandar"


@pytest.mark.asyncio
@respx.mock
async def test_perfilar_second_call_hits_cache(client):
    route = respx.post("http://localhost:8000/open-finance/enrich/client-2").mock(
        return_value=httpx.Response(
            200, json={"income": 3_000_000, "savings": 0, "credit_score": 800}
        )
    )

    await client.post(
        "/perfilar", json={"client_id": "client-2", "consentimiento_id": "cons-2"}
    )
    resp = await client.post(
        "/perfilar", json={"client_id": "client-2", "consentimiento_id": "cons-2"}
    )

    assert resp.json()["hit_cache"] is True
    assert route.call_count == 1


@pytest.mark.asyncio
@respx.mock
async def test_perfilar_propagates_error_on_timeout(client):
    respx.post("http://localhost:8000/open-finance/enrich/client-3").mock(
        side_effect=httpx.TimeoutException("timeout")
    )

    resp = await client.post(
        "/perfilar", json={"client_id": "client-3", "consentimiento_id": "cons-3"}
    )
    assert resp.status_code == 504
