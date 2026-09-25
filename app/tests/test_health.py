def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert "app" in body
    assert "env" in body


def test_health_versioned_alias(client):
    resp = client.get("/api/v1/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_ready(client):
    resp = client.get("/ready")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ready"
    assert body["checks"]["database"] == "ok"


def test_ready_versioned_alias(client):
    resp = client.get("/api/v1/ready")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ready"
    assert body["checks"]["database"] == "ok"

def test_ready_uses_real_database_context_manager(client, monkeypatch):
    """Readiness must call get_session() as a context manager."""
    from src import main

    class FakeSession:
        def __init__(self):
            self.executed = False

        def execute(self, statement):
            self.executed = True

    session = FakeSession()

    class FakeContextManager:
        def __enter__(self):
            return session

        def __exit__(self, exc_type, exc, tb):
            return False

    monkeypatch.setattr(main, "get_session", lambda: FakeContextManager())

    resp = client.get("/api/v1/ready")

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ready"
    assert body["checks"]["database"] == "ok"
    assert session.executed is True

def test_ready_reports_unhealthy_db(client, monkeypatch):
    """If the DB context manager fails, /ready must return 503."""
    from src import main

    class BrokenSession:
        def execute(self, *args, **kwargs):
            raise RuntimeError("simulated db outage")

    class BrokenContextManager:
        def __enter__(self):
            return BrokenSession()

        def __exit__(self, exc_type, exc, tb):
            return False

    monkeypatch.setattr(main, "get_session", lambda: BrokenContextManager())

    resp = client.get("/ready")

    assert resp.status_code == 503
    body = resp.json()
    assert body["status"] == "not_ready"
    assert body["checks"]["database"] == "unreachable"


def test_config_hides_secrets(client):
    resp = client.get("/config")
    assert resp.status_code == 200
    body = resp.json()
    for secret_key in ("jwt_secret", "api_key", "session_secret", "db_password"):
        assert secret_key not in body


def test_config_versioned_alias(client):
    resp = client.get("/api/v1/config")
    assert resp.status_code == 200
    body = resp.json()
    for secret_key in ("jwt_secret", "api_key", "session_secret", "db_password"):
        assert secret_key not in body


def test_metrics_endpoint_exposes_prometheus_format(client):
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/plain")
    assert b"http_requests_total" in resp.content or b"# HELP" in resp.content


def test_response_includes_request_id_header(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert "x-request-id" in resp.headers
    assert len(resp.headers["x-request-id"]) > 0


def test_request_id_is_echoed_when_provided(client):
    custom_id = "test-request-id-12345"
    resp = client.get("/health", headers={"X-Request-ID": custom_id})
    assert resp.status_code == 200
    assert resp.headers["x-request-id"] == custom_id
