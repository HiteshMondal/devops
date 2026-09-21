"""A minimal circuit breaker for the database session.

Standard three-state design: CLOSED (normal) -> OPEN (failing fast,
DB calls rejected immediately without hitting the network) -> HALF_OPEN
(after CB_RESET_SECONDS, one trial request is allowed through) -> CLOSED
again on success, or back to OPEN on failure.

Uses the CB_FAILURE_THRESHOLD / CB_RESET_SECONDS values that were already
present in devops-app-config but previously unread by the application.
"""
import logging
import threading
import time
from enum import Enum

from .config import config

logger = logging.getLogger("uvicorn.error")


class CircuitState(Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


class CircuitOpenError(Exception):
    """Raised when the breaker is open and a call is rejected without
    attempting the underlying operation."""


class CircuitBreaker:
    def __init__(self, failure_threshold: int, reset_seconds: int):
        self._failure_threshold = failure_threshold
        self._reset_seconds = reset_seconds
        self._lock = threading.Lock()
        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._opened_at = 0.0

    @property
    def state(self) -> CircuitState:
        with self._lock:
            if self._state == CircuitState.OPEN and (
                time.monotonic() - self._opened_at >= self._reset_seconds
            ):
                self._state = CircuitState.HALF_OPEN
                logger.info("Circuit breaker: OPEN -> HALF_OPEN (trial request allowed)")
            return self._state

    def _record_success(self):
        with self._lock:
            if self._state != CircuitState.CLOSED:
                logger.info("Circuit breaker: %s -> CLOSED (recovered)", self._state.value)
            self._state = CircuitState.CLOSED
            self._failure_count = 0

    def _record_failure(self):
        with self._lock:
            self._failure_count += 1
            if self._state == CircuitState.HALF_OPEN:
                self._state = CircuitState.OPEN
                self._opened_at = time.monotonic()
                logger.warning("Circuit breaker: HALF_OPEN -> OPEN (trial request failed)")
            elif self._failure_count >= self._failure_threshold:
                self._state = CircuitState.OPEN
                self._opened_at = time.monotonic()
                logger.warning(
                    "Circuit breaker: CLOSED -> OPEN (%d consecutive failures >= threshold %d)",
                    self._failure_count, self._failure_threshold,
                )

    def call(self, func, *args, **kwargs):
        current_state = self.state
        if current_state == CircuitState.OPEN:
            raise CircuitOpenError(
                f"Circuit breaker open — database calls suspended for "
                f"{self._reset_seconds}s since last failure"
            )

        try:
            result = func(*args, **kwargs)
        except Exception:
            self._record_failure()
            raise
        else:
            self._record_success()
            return result


db_circuit_breaker = CircuitBreaker(
    failure_threshold=config.CB_FAILURE_THRESHOLD,
    reset_seconds=config.CB_RESET_SECONDS,
)
