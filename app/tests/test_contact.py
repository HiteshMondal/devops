def test_submit_contact_valid_email(client):
    resp = client.post(
        "/api/v1/contact",
        json={"name": "Ada", "email": "ada@example.com", "message": "Hello!"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "received"
    assert "id" in body


def test_submit_contact_rejects_invalid_email(client):
    resp = client.post(
        "/api/v1/contact",
        json={"name": "Ada", "email": "not-an-email", "message": "Hello!"},
    )
    assert resp.status_code == 422


def test_submit_contact_missing_fields(client):
    resp = client.post("/api/v1/contact", json={"name": "Ada"})
    assert resp.status_code == 422


def test_contact_notification_noop_without_webhook_env(client, monkeypatch):
    """With CONTACT_WEBHOOK_URL unset, the request must still succeed and
    no outbound HTTP call should be attempted."""
    monkeypatch.delenv("CONTACT_WEBHOOK_URL", raising=False)

    resp = client.post(
        "/api/v1/contact",
        json={"name": "Grace", "email": "grace@example.com", "message": "Hi there"},
    )
    assert resp.status_code == 200


def test_contact_notification_fires_background_task(client, monkeypatch):
    calls = []

    def fake_post(url, json=None, timeout=None):
        calls.append((url, json))

        class FakeResponse:
            status_code = 200

        return FakeResponse()

    monkeypatch.setenv("CONTACT_WEBHOOK_URL", "https://example.com/webhook")
    monkeypatch.setattr("src.main.httpx.post", fake_post)

    resp = client.post(
        "/api/v1/contact",
        json={"name": "Grace", "email": "grace@example.com", "message": "Hi there"},
    )
    assert resp.status_code == 200
    assert len(calls) == 1
    assert calls[0][0] == "https://example.com/webhook"
    assert "Grace" in calls[0][1]["content"]