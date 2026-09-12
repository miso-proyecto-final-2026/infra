"""Acceso a PostgreSQL (tablas cotizacion y log_latencia) vía asyncpg."""
from typing import Optional

import asyncpg

from app.config import settings

_pool: Optional[asyncpg.Pool] = None

INIT_SQL = """
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS cotizacion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id VARCHAR(50) NOT NULL,
    prima_mensual NUMERIC(12,2) NOT NULL,
    cobertura NUMERIC(15,2) NOT NULL,
    degradada BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS log_latencia (
    id SERIAL PRIMARY KEY,
    cotizacion_id UUID NOT NULL,
    tiempo_total_ms INTEGER NOT NULL,
    tiempo_cache_ms INTEGER NOT NULL,
    tiempo_open_finance_ms INTEGER NOT NULL,
    tiempo_rating_ms INTEGER NOT NULL,
    tiempo_pg_ms INTEGER NOT NULL,
    hit_cache BOOLEAN NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
"""


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(
            dsn=settings.DATABASE_URL, min_size=2, max_size=10
        )
        async with _pool.acquire() as conn:
            await conn.execute(INIT_SQL)
    return _pool


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


async def insert_cotizacion(
    client_id: str, prima_mensual: float, cobertura: float, degradada: bool
) -> str:
    pool = await get_pool()
    row = await pool.fetchrow(
        """
        INSERT INTO cotizacion (client_id, prima_mensual, cobertura, degradada)
        VALUES ($1, $2, $3, $4)
        RETURNING id
        """,
        client_id,
        prima_mensual,
        cobertura,
        degradada,
    )
    return str(row["id"])


async def insert_log_latencia(
    cotizacion_id: str,
    tiempo_total_ms: int,
    tiempo_cache_ms: int,
    tiempo_open_finance_ms: int,
    tiempo_rating_ms: int,
    tiempo_pg_ms: int,
    hit_cache: bool,
) -> None:
    pool = await get_pool()
    await pool.execute(
        """
        INSERT INTO log_latencia (
            cotizacion_id, tiempo_total_ms, tiempo_cache_ms,
            tiempo_open_finance_ms, tiempo_rating_ms, tiempo_pg_ms, hit_cache
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        """,
        cotizacion_id,
        tiempo_total_ms,
        tiempo_cache_ms,
        tiempo_open_finance_ms,
        tiempo_rating_ms,
        tiempo_pg_ms,
        hit_cache,
    )
