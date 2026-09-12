"""Circuit breaker (pybreaker) para el llamado a Open Finance.

5 fallos consecutivos (timeout o error) abren el circuito durante
``CB_RESET_TIMEOUT_S`` segundos. Mientras está abierto, las llamadas fallan
inmediatamente con ``pybreaker.CircuitBreakerError`` sin golpear la red.

Nota: ``pybreaker.CircuitBreaker.call_async`` internamente usa
``tornado.gen.coroutine`` para envolver la corrutina — sin `tornado`
instalado, la llamada falla con ``NameError`` en tiempo de ejecución (no en
import). Por eso ``tornado`` está en requirements.txt aunque no se importe
explícitamente en este módulo.
"""
import httpx
import pybreaker

from app.config import settings

breaker = pybreaker.CircuitBreaker(
    fail_max=settings.CB_FAIL_MAX,
    reset_timeout=settings.CB_RESET_TIMEOUT_S,
    exclude=[],
)


async def _fetch_profile(client_id: str) -> dict:
    url = f"{settings.OPEN_FINANCE_URL}/open-finance/profile/{client_id}"
    async with httpx.AsyncClient(timeout=settings.OPEN_FINANCE_TIMEOUT_S) as client:
        resp = await client.post(url)
        resp.raise_for_status()
        return resp.json()


async def fetch_profile_protected(client_id: str) -> dict:
    """Llama a Open Finance protegido por el circuit breaker.

    Puede lanzar ``pybreaker.CircuitBreakerError`` (circuito abierto),
    ``httpx.TimeoutException`` o ``httpx.HTTPStatusError`` (fallo de red),
    todos manejados por el llamador para degradar controladamente.
    """
    return await breaker.call_async(_fetch_profile, client_id)


def circuit_state() -> str:
    return breaker.current_state
