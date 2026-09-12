import os


class Settings:
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/1")
    OPEN_FINANCE_URL: str = os.getenv("OPEN_FINANCE_URL", "http://localhost:8000")
    OPEN_FINANCE_TIMEOUT_S: float = float(os.getenv("OPEN_FINANCE_TIMEOUT_S", "0.7"))

    CACHE_TTL_S: int = int(os.getenv("CACHE_TTL_S", "900"))  # 15 min

    OTEL_EXPORTER_OTLP_ENDPOINT: str = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
    OTEL_SERVICE_NAME: str = os.getenv("OTEL_SERVICE_NAME", "ms-perfilamiento")


settings = Settings()
