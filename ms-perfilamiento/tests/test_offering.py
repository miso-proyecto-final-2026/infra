from app.offering import calcular_oferta


def test_high_credit_score_gets_preferential_segment():
    oferta = calcular_oferta({"credit_score": 800, "income": 5_000_000, "savings": 0})
    assert oferta.segmento == "preferencial"
    assert oferta.descuento_pct == 15.0


def test_low_credit_score_gets_no_discount():
    oferta = calcular_oferta({"credit_score": 400, "income": 2_000_000, "savings": 0})
    assert oferta.segmento == "riesgo_alto"
    assert oferta.descuento_pct == 0.0


def test_mid_credit_score_gets_standard_segment():
    oferta = calcular_oferta({"credit_score": 650, "income": 3_000_000, "savings": 0})
    assert oferta.segmento == "estandar"
    assert oferta.descuento_pct == 5.0


def test_missing_fields_use_defaults():
    oferta = calcular_oferta({})
    assert oferta.segmento == "estandar"
    assert oferta.cobertura_sugerida > 0
