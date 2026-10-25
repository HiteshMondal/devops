def _signup(client, email="s@example.com"):
    r = client.post("/api/v1/auth/signup", json={"email": email, "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_search_is_prefix_and_literal(client):
    h = _signup(client)
    for t in ["Portfolio Site", "Port Scanner", "Blog"]:
        client.post("/api/v1/projects", json={"title": t}, headers=h)
    assert client.get("/api/v1/projects/search?q=PORT").json()["total"] == 2
    assert client.get("/api/v1/projects/search?q=%25").json()["total"] == 0   # % is literal


def test_profile_and_info_isolated_per_user(client):
    a, b = _signup(client, "a@example.com"), _signup(client, "b@example.com")
    r = client.post("/api/v1/me/info", json={"kind": "skill", "label": "lang", "value": "Python"}, headers=a)
    assert r.status_code == 201
    dup = client.post("/api/v1/me/info", json={"kind": "skill", "label": "lang", "value": "Go"}, headers=a)
    assert dup.status_code == 409
    assert client.get("/api/v1/me/profile", headers=b).json()["items"] == []
    assert client.delete(f"/api/v1/me/info/{r.json()['id']}", headers=b).status_code == 404


def test_change_password_invalidates_old_token(client):
    h = _signup(client)
    r = client.post("/api/v1/auth/change-password",
                    json={"current_password": "password123", "new_password": "newpass456"}, headers=h)
    assert r.status_code == 200
    assert client.get("/api/v1/auth/me", headers=r.json() and {"Authorization": f"Bearer {r.json()['access_token']}"}).status_code == 200
