def _signup(client, email="owner@example.com", password="password123"):
    resp = client.post("/api/v1/auth/signup", json={"email": email, "password": password})
    assert resp.status_code == 200
    return resp.json()["access_token"]


def _auth_headers(token):
    return {"Authorization": f"Bearer {token}"}


def test_list_projects_empty(client):
    resp = client.get("/api/v1/projects")
    assert resp.status_code == 200
    body = resp.json()
    assert body["items"] == []
    assert body["total"] == 0
    assert body["page"] == 1


def test_create_requires_auth(client):
    resp = client.post(
        "/api/v1/projects",
        json={"title": "Portfolio Site", "description": "A FastAPI app", "link": "https://example.com"},
    )
    assert resp.status_code == 401


def test_create_and_list_project(client):
    token = _signup(client)

    create_resp = client.post(
        "/api/v1/projects",
        json={"title": "Portfolio Site", "description": "A FastAPI app", "link": "https://example.com"},
        headers=_auth_headers(token),
    )
    assert create_resp.status_code == 200
    created = create_resp.json()
    assert "id" in created
    assert created["owner_id"] is not None

    list_resp = client.get("/api/v1/projects")
    assert list_resp.status_code == 200
    body = list_resp.json()
    assert body["total"] == 1
    assert body["items"][0]["title"] == "Portfolio Site"
    assert body["items"][0]["link"] == "https://example.com"


def test_create_project_requires_title(client):
    token = _signup(client)
    resp = client.post(
        "/api/v1/projects",
        json={"description": "missing title"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 422


def test_get_single_project(client):
    token = _signup(client)
    created = client.post(
        "/api/v1/projects", json={"title": "Solo"}, headers=_auth_headers(token)
    ).json()

    resp = client.get(f"/api/v1/projects/{created['id']}")
    assert resp.status_code == 200
    assert resp.json()["title"] == "Solo"


def test_get_missing_project_404(client):
    resp = client.get("/api/v1/projects/999999")
    assert resp.status_code == 404


def test_update_project_by_owner(client):
    token = _signup(client)
    created = client.post(
        "/api/v1/projects", json={"title": "Old title"}, headers=_auth_headers(token)
    ).json()

    resp = client.patch(
        f"/api/v1/projects/{created['id']}",
        json={"title": "New title"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 200
    assert resp.json()["title"] == "New title"


def test_update_project_by_non_owner_is_404(client):
    token_a = _signup(client, email="a@example.com")
    token_b = _signup(client, email="b@example.com")

    created = client.post(
        "/api/v1/projects", json={"title": "Owned by A"}, headers=_auth_headers(token_a)
    ).json()

    resp = client.patch(
        f"/api/v1/projects/{created['id']}",
        json={"title": "Hijacked"},
        headers=_auth_headers(token_b),
    )
    assert resp.status_code == 404


def test_delete_project_by_owner(client):
    token = _signup(client)
    created = client.post(
        "/api/v1/projects", json={"title": "Temp"}, headers=_auth_headers(token)
    ).json()

    resp = client.delete(f"/api/v1/projects/{created['id']}", headers=_auth_headers(token))
    assert resp.status_code == 204

    resp = client.get(f"/api/v1/projects/{created['id']}")
    assert resp.status_code == 404


def test_delete_project_by_non_owner_is_404(client):
    token_a = _signup(client, email="a2@example.com")
    token_b = _signup(client, email="b2@example.com")

    created = client.post(
        "/api/v1/projects", json={"title": "Owned by A"}, headers=_auth_headers(token_a)
    ).json()

    resp = client.delete(f"/api/v1/projects/{created['id']}", headers=_auth_headers(token_b))
    assert resp.status_code == 404


def test_my_projects_only_returns_owned(client):
    token_a = _signup(client, email="a3@example.com")
    token_b = _signup(client, email="b3@example.com")

    client.post("/api/v1/projects", json={"title": "A's project"}, headers=_auth_headers(token_a))
    client.post("/api/v1/projects", json={"title": "B's project"}, headers=_auth_headers(token_b))

    resp = client.get("/api/v1/projects/mine", headers=_auth_headers(token_a))
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 1
    assert body["items"][0]["title"] == "A's project"


def test_my_projects_requires_auth(client):
    resp = client.get("/api/v1/projects/mine")
    assert resp.status_code == 401


def test_projects_pagination(client):
    token = _signup(client)
    for i in range(5):
        client.post(
            "/api/v1/projects", json={"title": f"Project {i}"}, headers=_auth_headers(token)
        )

    resp = client.get("/api/v1/projects?page=1&page_size=2")
    body = resp.json()
    assert len(body["items"]) == 2
    assert body["total"] == 5
    assert body["total_pages"] == 3

    resp2 = client.get("/api/v1/projects?page=2&page_size=2")
    body2 = resp2.json()
    assert len(body2["items"]) == 2
    assert body2["items"][0]["id"] != body["items"][0]["id"]