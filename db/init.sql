-- Esquema PostgreSQL para el experimento HA01 (MS Cotización).
-- Idempotente: se puede ejecutar múltiples veces sin fallar.

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

CREATE INDEX IF NOT EXISTS idx_cotizacion_client_id ON cotizacion (client_id);
CREATE INDEX IF NOT EXISTS idx_log_latencia_cotizacion_id ON log_latencia (cotizacion_id);
CREATE INDEX IF NOT EXISTS idx_log_latencia_created_at ON log_latencia (created_at);
