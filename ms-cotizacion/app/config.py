import os


class Settings:
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL", "postgresql://solventa:solventa@localhost:5432/solventa"
    )
    OPEN_FINANCE_URL: str = os.getenv("OPEN_FINANCE_URL", "http://localhost:8000")
    OPEN_FINANCE_TIMEOUT_S: float = float(os.getenv("OPEN_FINANCE_TIMEOUT_S", "0.7"))

    CACHE_TTL_S: int = int(os.getenv("CACHE_TTL_S", "300"))  # 5 min
    STALE_CACHE_TTL_S: int = int(os.getenv("STALE_CACHE_TTL_S", "86400"))  # 24h

    # pybreaker: 5 fallos consecutivos abren el circuito
    CB_FAIL_MAX: int = int(os.getenv("CB_FAIL_MAX", "5"))
    CB_RESET_TIMEOUT_S: int = int(os.getenv("CB_RESET_TIMEOUT_S", "30"))

    OTEL_EXPORTER_OTLP_ENDPOINT: str = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
    OTEL_SERVICE_NAME: str = os.getenv("OTEL_SERVICE_NAME", "ms-cotizacion")


settings = Settings()
