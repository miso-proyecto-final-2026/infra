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
    assert resp.json()["status"] == "ok"


@pytest.mark.asyncio
@respx.mock
async def test_cotizar_cache_miss_calls_open_finance(client):
    respx.post("http://localhost:8000/open-finance/profile/client-1").mock(
        return_value=httpx.Response(
            200,
            json={"income": 4_000_000, "risk_score": 0.4, "age": 30, "debt_ratio": 0.2},
        )
    )

    resp = await client.post("/cotizar", json={"client_id": "client-1"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["client_id"] == "client-1"
    assert body["hit_cache"] is False
    assert body["degradada"] is False
    assert body["prima_mensual"] > 0


@pytest.mark.asyncio
@respx.mock
async def test_cotizar_second_call_hits_cache(client):
    route = respx.post("http://localhost:8000/open-finance/profile/client-2").mock(
        return_value=httpx.Response(
            200,
            json={"income": 4_000_000, "risk_score": 0.4, "age": 30, "debt_ratio": 0.2},
        )
    )

    await client.post("/cotizar", json={"client_id": "client-2"})
    resp = await client.post("/cotizar", json={"client_id": "client-2"})

    assert resp.json()["hit_cache"] is True
    assert route.call_count == 1


@pytest.mark.asyncio
@respx.mock
async def test_cotizar_never_fails_when_open_finance_times_out(client):
    respx.post("http://localhost:8000/open-finance/profile/client-3").mock(
        side_effect=httpx.TimeoutException("timeout")
    )

    resp = await client.post("/cotizar", json={"client_id": "client-3"})

    assert resp.status_code == 200
    body = resp.json()
    assert body["degradada"] is True
    assert body["prima_mensual"] > 0
