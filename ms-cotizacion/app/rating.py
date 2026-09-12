"""Motor de rating: función pura que calcula la prima a partir del perfil.

No tiene efectos secundarios ni I/O, por lo que es trivialmente unit-testeable
y no aporta latencia relevante al flujo de cotización.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Cotizacion:
    prima_mensual: float
    cobertura: float


# Perfil por defecto usado cuando no hay datos de Open Finance disponibles
# (circuito abierto y sin valor cacheado ni stale).
DEFAULT_PROFILE = {
    "income": 3_000_000,
    "risk_score": 0.5,
    "age": 35,
    "debt_ratio": 0.3,
}

BASE_RATE = 0.00045  # tarifa base mensual sobre la cobertura
COVERAGE_MULTIPLIER = 200  # cobertura = ingreso mensual * multiplicador
MAX_COVERAGE = 1_000_000_000  # tope de cobertura (COP)


def _age_factor(age: int) -> float:
    if age < 30:
        return 0.85
    if age < 45:
        return 1.0
    if age < 60:
        return 1.35
    return 1.8


def _risk_factor(risk_score: float) -> float:
    # risk_score en [0, 1], mayor riesgo -> mayor factor
    return 0.6 + risk_score * 1.4


def _debt_factor(debt_ratio: float) -> float:
    return 1.0 + max(0.0, debt_ratio - 0.3) * 0.5


def calcular_cotizacion(profile: dict) -> Cotizacion:
    income = float(profile.get("income", DEFAULT_PROFILE["income"]))
    risk_score = float(profile.get("risk_score", DEFAULT_PROFILE["risk_score"]))
    age = int(profile.get("age", DEFAULT_PROFILE["age"]))
    debt_ratio = float(profile.get("debt_ratio", DEFAULT_PROFILE["debt_ratio"]))

    cobertura = min(income * COVERAGE_MULTIPLIER, MAX_COVERAGE)
    factor = _age_factor(age) * _risk_factor(risk_score) * _debt_factor(debt_ratio)
    prima_mensual = round(cobertura * BASE_RATE * factor / 100, 2)

    return Cotizacion(prima_mensual=prima_mensual, cobertura=round(cobertura, 2))
