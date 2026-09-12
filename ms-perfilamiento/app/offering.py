"""Función pura que arma la oferta personalizada a partir del perfil
enriquecido devuelto por Open Finance."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Oferta:
    segmento: str
    descuento_pct: float
    cobertura_sugerida: float


def _segmento(credit_score: int) -> str:
    if credit_score >= 750:
        return "preferencial"
    if credit_score >= 550:
        return "estandar"
    return "riesgo_alto"


def calcular_oferta(profile: dict) -> Oferta:
    credit_score = int(profile.get("credit_score", 600))
    income = float(profile.get("income", 3_000_000))
    savings = float(profile.get("savings", 0))

    segmento = _segmento(credit_score)
    descuento_pct = {
        "preferencial": 15.0,
        "estandar": 5.0,
        "riesgo_alto": 0.0,
    }[segmento]

    cobertura_sugerida = round(income * 180 + savings * 0.5, 2)

    return Oferta(
        segmento=segmento,
        descuento_pct=descuento_pct,
        cobertura_sugerida=cobertura_sugerida,
    )
