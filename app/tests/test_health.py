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


def test_ready_reports_unhealthy_db(client, monkeypatch):
    """If the DB session raises on the readiness probe, /ready must
    report 503 rather than crash or falsely report healthy."""
    from src.main import app, db_session

    original_override = app.dependency_overrides.get(db_session)

    class BrokenSession:
        def execute(self, *args, **kwargs):
            raise RuntimeError("simulated db outage")

    def override_broken_session():
        yield BrokenSession()

    app.dependency_overrides[db_session] = override_broken_session
    try:
        resp = client.get("/ready")
        assert resp.status_code == 503
        body = resp.json()
        assert body["status"] == "not_ready"
        assert body["checks"]["database"] == "unreachable"
    finally:
        if original_override is not None:
            app.dependency_overrides[db_session] = original_override
        else:
            app.dependency_overrides.pop(db_session, None)


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
    # Confirm at least the request counter metric name appears after
    # this same client has made prior requests in this test session.
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