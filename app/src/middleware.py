"""Request-scoped logging middleware.

Attaches a unique request ID to every incoming request (reusing an
inbound X-Request-ID header if the caller/proxy already set one), logs
method/path/status/duration in a single structured line per request, and
echoes the ID back in the response header so it can be correlated across
services and in Loki.
"""
import logging
import time
import uuid
from contextvars import ContextVar

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

logger = logging.getLogger("uvicorn.access")

_request_id_ctx: ContextVar[str] = ContextVar("request_id", default="-")


def get_request_id() -> str:
    return _request_id_ctx.get()


class RequestContextLogMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        token = _request_id_ctx.set(request_id)
        start = time.perf_counter()

        try:
            response = await call_next(request)
        except Exception:
            duration_ms = (time.perf_counter() - start) * 1000
            logger.exception(
                "request_id=%s method=%s path=%s status=500 duration_ms=%.2f",
                request_id, request.method, request.url.path, duration_ms,
            )
            raise
        else:
            duration_ms = (time.perf_counter() - start) * 1000
            logger.info(
                "request_id=%s method=%s path=%s status=%d duration_ms=%.2f",
                request_id, request.method, request.url.path,
                response.status_code, duration_ms,
            )
            response.headers["X-Request-ID"] = request_id
            return response
        finally:
            _request_id_ctx.reset(token)