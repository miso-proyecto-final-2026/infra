"""Cache-aside sobre Redis para perfiles enriquecidos (sin circuit breaker,
a diferencia de MS Cotización)."""
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


def _key(client_id: str) -> str:
    return f"enriched_profile:{client_id}"


async def get_enriched_profile(client_id: str) -> Optional[dict]:
    raw = await get_redis().get(_key(client_id))
    return json.loads(raw) if raw else None


async def set_enriched_profile(client_id: str, profile: dict) -> None:
    await get_redis().set(_key(client_id), json.dumps(profile), ex=settings.CACHE_TTL_S)
