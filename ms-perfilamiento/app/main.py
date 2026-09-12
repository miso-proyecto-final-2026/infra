"""MS Perfilamiento.

Flujo POST /perfilar:
1. Redis (enriched_profile:{client_id})
2. Miss -> Open Finance /open-finance/enrich/{client_id} con timeout 700ms
   (SIN circuit breaker, a diferencia de MS Cotización)
3. Guarda en caché y responde con oferta personalizada

Instrumentado con OpenTelemetry: spans cache, open_finance, offering.
"""
import time
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from app import cache
from app.config import settings
from app.offering import calcular_oferta
from app.telemetry import tracer


class PerfilarRequest(BaseModel):
    client_id: str
    consentimiento_id: str


class PerfilarResponse(BaseModel):
    client_id: str
    segmento: str
    descuento_pct: float
    cobertura_sugerida: float
    hit_cache: bool
    tiempo_total_ms: int


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    await cache.close_redis()


app = FastAPI(title="MS Perfilamiento", version="1.0.0", lifespan=lifespan)


def _elapsed_ms(start: float) -> int:
    return int((time.perf_counter() - start) * 1000)


async def _fetch_enriched_profile(client_id: str, consentimiento_id: str) -> dict:
    url = f"{settings.OPEN_FINANCE_URL}/open-finance/enrich/{client_id}"
    async with httpx.AsyncClient(timeout=settings.OPEN_FINANCE_TIMEOUT_S) as client:
        resp = await client.post(
            url, params={"consentimiento_id": consentimiento_id}
        )
        resp.raise_for_status()
        return resp.json()


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/perfilar", response_model=PerfilarResponse)
async def perfilar(req: PerfilarRequest):
    t_total_start = time.perf_counter()
    client_id = req.client_id

    with tracer.start_as_current_span("cache") as span:
        profile = await cache.get_enriched_profile(client_id)
        hit_cache = profile is not None
        span.set_attribute("cache.hit", hit_cache)

    if not hit_cache:
        with tracer.start_as_current_span("open_finance") as span:
            try:
                profile = await _fetch_enriched_profile(
                    client_id, req.consentimiento_id
                )
                span.set_attribute("open_finance.outcome", "success")
            except (httpx.TimeoutException, httpx.HTTPError) as exc:
                span.set_attribute("open_finance.outcome", "error")
                raise HTTPException(
                    status_code=504, detail=f"open_finance no disponible: {exc}"
                ) from exc
        await cache.set_enriched_profile(client_id, profile)

    with tracer.start_as_current_span("offering") as span:
        oferta = calcular_oferta(profile)
        span.set_attribute("offering.segmento", oferta.segmento)

    return PerfilarResponse(
        client_id=client_id,
        segmento=oferta.segmento,
        descuento_pct=oferta.descuento_pct,
        cobertura_sugerida=oferta.cobertura_sugerida,
        hit_cache=hit_cache,
        tiempo_total_ms=_elapsed_ms(t_total_start),
    )
