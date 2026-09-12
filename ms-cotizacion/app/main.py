"""MS Cotización.

Flujo POST /cotizar:
1. Redis (profile:{client_id})
2. Miss -> Open Finance protegido por timeout 700ms + circuit breaker
3. Circuito abierto / fallo -> último valor cacheado (stale) o default
   (degradación controlada; NUNCA falla la cotización)
4. Motor de rating (función pura)
5. Persistencia en PostgreSQL (cotizacion + log_latencia)

Instrumentado con OpenTelemetry: spans cache, open_finance, rating,
persistencia.
"""
import time
from contextlib import asynccontextmanager

import httpx
import pybreaker
from fastapi import FastAPI
from pydantic import BaseModel

from app import cache, db
from app.circuit_breaker import circuit_state, fetch_profile_protected
from app.rating import DEFAULT_PROFILE, calcular_cotizacion
from app.telemetry import tracer


class CotizarRequest(BaseModel):
    client_id: str


class CotizarResponse(BaseModel):
    id: str
    client_id: str
    prima_mensual: float
    cobertura: float
    degradada: bool
    hit_cache: bool
    tiempo_total_ms: int


@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.get_pool()
    yield
    await db.close_pool()
    await cache.close_redis()


app = FastAPI(title="MS Cotizacion", version="1.0.0", lifespan=lifespan)


def _elapsed_ms(start: float) -> int:
    return int((time.perf_counter() - start) * 1000)


@app.get("/health")
async def health():
    return {"status": "ok", "circuit_breaker": circuit_state()}


@app.post("/cotizar", response_model=CotizarResponse)
async def cotizar(req: CotizarRequest):
    t_total_start = time.perf_counter()
    client_id = req.client_id

    # --- Etapa cache ---
    with tracer.start_as_current_span("cache") as span:
        t0 = time.perf_counter()
        profile = await cache.get_fresh_profile(client_id)
        hit_cache = profile is not None
        tiempo_cache_ms = _elapsed_ms(t0)
        span.set_attribute("cache.hit", hit_cache)

    tiempo_open_finance_ms = 0
    degradada = False

    # --- Etapa open_finance (solo si hubo miss) ---
    if not hit_cache:
        with tracer.start_as_current_span("open_finance") as span:
            t0 = time.perf_counter()
            try:
                profile = await fetch_profile_protected(client_id)
                await cache.set_profile(client_id, profile)
                span.set_attribute("open_finance.outcome", "success")
            except pybreaker.CircuitBreakerError:
                span.set_attribute("open_finance.outcome", "circuit_open")
                profile = await cache.get_stale_profile(client_id) or DEFAULT_PROFILE
                degradada = True
            except (httpx.TimeoutException, httpx.HTTPError):
                span.set_attribute("open_finance.outcome", "error")
                profile = await cache.get_stale_profile(client_id) or DEFAULT_PROFILE
                degradada = True
            tiempo_open_finance_ms = _elapsed_ms(t0)

    # --- Etapa rating ---
    with tracer.start_as_current_span("rating") as span:
        t0 = time.perf_counter()
        resultado = calcular_cotizacion(profile)
        tiempo_rating_ms = _elapsed_ms(t0)
        span.set_attribute("rating.prima_mensual", resultado.prima_mensual)

    # --- Etapa persistencia ---
    with tracer.start_as_current_span("persistencia") as span:
        t0 = time.perf_counter()
        cotizacion_id = await db.insert_cotizacion(
            client_id, resultado.prima_mensual, resultado.cobertura, degradada
        )
        tiempo_total_ms = _elapsed_ms(t_total_start)
        await db.insert_log_latencia(
            cotizacion_id=cotizacion_id,
            tiempo_total_ms=tiempo_total_ms,
            tiempo_cache_ms=tiempo_cache_ms,
            tiempo_open_finance_ms=tiempo_open_finance_ms,
            tiempo_rating_ms=tiempo_rating_ms,
            tiempo_pg_ms=_elapsed_ms(t0),
            hit_cache=hit_cache,
        )
        span.set_attribute("persistencia.cotizacion_id", cotizacion_id)

    return CotizarResponse(
        id=cotizacion_id,
        client_id=client_id,
        prima_mensual=resultado.prima_mensual,
        cobertura=resultado.cobertura,
        degradada=degradada,
        hit_cache=hit_cache,
        tiempo_total_ms=tiempo_total_ms,
    )
