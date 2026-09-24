def _signup(client, email="admin@example.com", password="password123"):
    resp = client.post("/api/v1/auth/signup", json={"email": email, "password": password})
    assert resp.status_code == 200
    return resp.json()["access_token"]


def test_list_contact_messages_requires_auth(client):
    resp = client.get("/api/v1/contact")
    assert resp.status_code == 401


def test_list_contact_messages_when_authenticated(client):
    token = _signup(client)

    client.post(
        "/api/v1/contact",
        json={"name": "Ada", "email": "ada@example.com", "message": "Hello!"},
    )
    client.post(
        "/api/v1/contact",
        json={"name": "Grace", "email": "grace@example.com", "message": "Hi there"},
    )

    resp = client.get("/api/v1/contact", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 2
    # Most recent first
    assert body["items"][0]["name"] == "Grace"
    assert body["items"][1]["name"] == "Ada"


def test_contact_messages_pagination(client):
    token = _signup(client)
    for i in range(3):
        client.post(
            "/api/v1/contact",
            json={"name": f"User{i}", "email": f"user{i}@example.com", "message": "hi"},
        )

    resp = client.get(
        "/api/v1/contact?page=1&page_size=2",
        headers={"Authorization": f"Bearer {token}"},
    )
    body = resp.json()
    assert len(body["items"]) == 2
    assert body["total"] == 3
    assert body["total_pages"] == 2
