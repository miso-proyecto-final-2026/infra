import fakeredis.aioredis
import pytest

from app import cache


@pytest.fixture(autouse=True)
def _fake_redis(monkeypatch):
    fake = fakeredis.aioredis.FakeRedis(decode_responses=True)
    monkeypatch.setattr(cache, "_redis", None)
    monkeypatch.setattr(cache, "get_redis", lambda: fake)
    yield fake
