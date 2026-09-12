"""
Mock de Open Finance.

Simula las APIs de Open Finance con latencia inyectable en caliente, para
soportar los experimentos HA01 (cotizacion) y HA02 (perfilamiento).
"""
import asyncio
import hashlib
import random
import threading
from typing import Optional

from fastapi import FastAPI
from pydantic import BaseModel, Field

app = FastAPI(title="Mock Open Finance", version="1.0.0")

# Configuración de latencia mutable en caliente, protegida por lock porque
# k6 puede disparar PUT /config/latency concurrentemente con el tráfico de
# lectura de los otros dos endpoints.
_lock = threading.Lock()
_config = {"min_ms": 200, "max_ms": 500}


class LatencyConfig(BaseModel):
    min_ms: int = Field(ge=0, description="Latencia mínima en milisegundos")
    max_ms: int = Field(ge=0, description="Latencia máxima en milisegundos")


def _current_config() -> dict:
    with _lock:
        return dict(_config)


def _seeded_random(client_id: str) -> random.Random:
    """RNG determinístico por client_id para que el perfil mock sea estable
    entre llamadas (importante para el hit-rate de caché)."""
    seed = int(hashlib.sha256(client_id.encode()).hexdigest(), 16) % (2**32)
    return random.Random(seed)


async def _inject_latency() -> int:
    cfg = _current_config()
    min_ms, max_ms = cfg["min_ms"], cfg["max_ms"]
    if max_ms < min_ms:
        max_ms = min_ms
    delay_ms = random.uniform(min_ms, max_ms)
    await asyncio.sleep(delay_ms / 1000.0)
    return round(delay_ms)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/config")
async def get_config():
    return _current_config()


@app.put("/config/latency")
async def set_latency(cfg: LatencyConfig):
    with _lock:
        _config["min_ms"] = cfg.min_ms
        _config["max_ms"] = cfg.max_ms
    return {"status": "updated", "config": _current_config()}


@app.post("/open-finance/profile/{client_id}")
async def profile(client_id: str):
    delay_ms = await _inject_latency()
    rng = _seeded_random(client_id)
    income = rng.randint(1_500_000, 15_000_000)
    risk_score = round(rng.uniform(0.05, 0.95), 3)
    age = rng.randint(18, 70)
    debt_ratio = round(rng.uniform(0.0, 0.6), 3)
    return {
        "client_id": client_id,
        "income": income,
        "risk_score": risk_score,
        "age": age,
        "debt_ratio": debt_ratio,
        "source": "open-finance-mock",
        "injected_latency_ms": delay_ms,
    }


@app.post("/open-finance/enrich/{client_id}")
async def enrich(client_id: str, consentimiento_id: Optional[str] = None):
    delay_ms = await _inject_latency()
    rng = _seeded_random(f"enrich:{client_id}")
    income = rng.randint(1_500_000, 20_000_000)
    savings = rng.randint(0, 30_000_000)
    credit_score = rng.randint(300, 900)
    products = rng.sample(
        ["cuenta_ahorro", "tarjeta_credito", "credito_hipotecario", "cdt", "leasing"],
        k=rng.randint(1, 3),
    )
    return {
        "client_id": client_id,
        "consentimiento_id": consentimiento_id,
        "income": income,
        "savings": savings,
        "credit_score": credit_score,
        "products": products,
        "source": "open-finance-mock",
        "injected_latency_ms": delay_ms,
    }
