import fakeredis.aioredis
import pytest

from app import cache, db


@pytest.fixture(autouse=True)
def _fake_redis(monkeypatch):
    fake = fakeredis.aioredis.FakeRedis(decode_responses=True)
    monkeypatch.setattr(cache, "_redis", None)
    monkeypatch.setattr(cache, "get_redis", lambda: fake)
    yield fake


@pytest.fixture(autouse=True)
def _fake_db(monkeypatch):
    """Evita tocar Postgres real: intercepta las funciones de persistencia."""
    inserted = {"cotizaciones": [], "logs": []}

    async def fake_insert_cotizacion(client_id, prima_mensual, cobertura, degradada):
        cid = f"fake-{len(inserted['cotizaciones'])}"
        inserted["cotizaciones"].append(
            (cid, client_id, prima_mensual, cobertura, degradada)
        )
        return cid

    async def fake_insert_log_latencia(**kwargs):
        inserted["logs"].append(kwargs)

    async def fake_get_pool():
        return None

    async def fake_close_pool():
        return None

    monkeypatch.setattr(db, "insert_cotizacion", fake_insert_cotizacion)
    monkeypatch.setattr(db, "insert_log_latencia", fake_insert_log_latencia)
    monkeypatch.setattr(db, "get_pool", fake_get_pool)
    monkeypatch.setattr(db, "close_pool", fake_close_pool)
    yield inserted
