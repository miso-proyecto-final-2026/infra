"""Cache-aside sobre Redis para perfiles de Open Finance.

Se manejan dos familias de keys:
- ``profile:{client_id}``       -> valor "fresco", TTL corto (5 min).
- ``profile:stale:{client_id}`` -> última copia conocida, TTL largo (24h),
  usada como fallback de degradación controlada cuando el circuito está
  abierto y no hay valor fresco.
"""
import json
from typing import Optional

import redis.asyncio as redis

from app.config import settings

_redis: Optional[redis.Redis] = None


def get_redis() -> redis.Redis:
    global _redis
    if _redis is None:
        _redis = redis.from_url(settings.REDIS_URL, decode_responses=True)
    return _redis


async def close_redis() -> None:
    global _redis
    if _redis is not None:
        await _redis.close()
        _redis = None


def _fresh_key(client_id: str) -> str:
    return f"profile:{client_id}"


def _stale_key(client_id: str) -> str:
    return f"profile:stale:{client_id}"


async def get_fresh_profile(client_id: str) -> Optional[dict]:
    raw = await get_redis().get(_fresh_key(client_id))
    return json.loads(raw) if raw else None


async def get_stale_profile(client_id: str) -> Optional[dict]:
    raw = await get_redis().get(_stale_key(client_id))
    return json.loads(raw) if raw else None


async def set_profile(client_id: str, profile: dict) -> None:
    payload = json.dumps(profile)
    r = get_redis()
    await r.set(_fresh_key(client_id), payload, ex=settings.CACHE_TTL_S)
    await r.set(_stale_key(client_id), payload, ex=settings.STALE_CACHE_TTL_S)
