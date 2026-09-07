"""Prometheus metrics — request counters and latency histogram.

Exposed at GET /metrics in Prometheus text format. Deliberately
dependency-free from the rest of the app (no DB/config coupling) so it
can never be the reason a request fails.
"""
from prometheus_client import Counter, Histogram, CONTENT_TYPE_LATEST, generate_latest
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status"],
)

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "path"],
)


class PrometheusMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Avoid unbounded label cardinality from path params (e.g. /projects/123)
        path = request.scope.get("route").path if request.scope.get("route") else request.url.path

        with REQUEST_LATENCY.labels(method=request.method, path=path).time():
            response = await call_next(request)

        REQUEST_COUNT.labels(
            method=request.method, path=path, status=response.status_code
        ).inc()
        return response


def metrics_response() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)