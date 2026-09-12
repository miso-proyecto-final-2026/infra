from app.rating import DEFAULT_PROFILE, calcular_cotizacion


def test_default_profile_produces_positive_prima():
    result = calcular_cotizacion(DEFAULT_PROFILE)
    assert result.prima_mensual > 0
    assert result.cobertura > 0


def test_higher_risk_score_increases_prima():
    base = {"income": 3_000_000, "risk_score": 0.1, "age": 35, "debt_ratio": 0.2}
    risky = {**base, "risk_score": 0.9}

    prima_base = calcular_cotizacion(base).prima_mensual
    prima_risky = calcular_cotizacion(risky).prima_mensual

    assert prima_risky > prima_base


def test_older_age_increases_prima():
    young = {"income": 3_000_000, "risk_score": 0.3, "age": 25, "debt_ratio": 0.2}
    old = {**young, "age": 65}

    assert calcular_cotizacion(old).prima_mensual > calcular_cotizacion(young).prima_mensual


def test_coverage_is_capped():
    huge_income = {
        "income": 1_000_000_000_000,
        "risk_score": 0.5,
        "age": 35,
        "debt_ratio": 0.2,
    }
    result = calcular_cotizacion(huge_income)
    assert result.cobertura <= 1_000_000_000


def test_missing_fields_fall_back_to_defaults():
    result_empty = calcular_cotizacion({})
    result_default = calcular_cotizacion(DEFAULT_PROFILE)
    assert result_empty == result_default
