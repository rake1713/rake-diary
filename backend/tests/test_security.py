"""Безопасность: доступ, сессии, CSRF, перебор паролей, заголовки, лимиты."""

from __future__ import annotations

import sqlite3

import pytest
from fastapi.testclient import TestClient

from diary.config import Settings
from tests.conftest import login_mobile, make_client, with_settings

WEB = {"X-Requested-With": "diary-web"}
PROTECTED = [
    ("GET", "/api/auth/me"),
    ("GET", "/api/days"),
    ("GET", "/api/days/2026-10-01"),
    ("POST", "/api/trips"),
]


def web_login(client: TestClient, login: str = "demo", password: str = "demo12345"):
    return client.post("/api/auth/login", json={"login": login, "password": password}, headers=WEB)


# ---------- доступ без входа ----------


@pytest.mark.parametrize(("method", "path"), PROTECTED)
def test_protected_endpoints_require_auth(client: TestClient, method: str, path: str) -> None:
    r = client.request(method, path, json={})
    assert r.status_code == 401
    assert r.json()["error"] == "unauthorized"


@pytest.mark.parametrize(
    "header", ["Bearer nope", "Bearer ", "Basic ZGVtbzpkZW1vMTIzNDU=", "Bearer " + "a" * 500]
)
def test_bad_tokens_rejected(client: TestClient, header: str) -> None:
    r = client.get("/api/days/2026-10-01", headers={"Authorization": header})
    assert r.status_code == 401


def test_health_is_public(client: TestClient) -> None:
    assert client.get("/api/health").json() == {"status": "ok"}


# ---------- изоляция водителей ----------


def test_driver_sees_only_own_trips(client: TestClient, auth2: dict) -> None:
    body = client.get("/api/days/2026-10-01", headers=auth2).json()
    assert body["trips"] == []
    assert client.get("/api/days", headers=auth2).json() == []


def test_driver_id_cannot_be_injected(client: TestClient, auth2: dict) -> None:
    trip = {
        "id": "x1",
        "start": "2026-10-01T10:00:00+05:00",
        "end": "2026-10-01T10:10:00+05:00",
        "amount": 100,
        "payment": "cash",
        "commission": 0,
        "driver_id": 1,
    }
    assert client.post("/api/trips", json=trip, headers=auth2).status_code == 422


# ---------- вход ----------


def test_wrong_password_and_unknown_login_look_the_same(client: TestClient) -> None:
    h = {"X-Client": "mobile"}
    a = client.post("/api/auth/login", json={"login": "demo", "password": "bad"}, headers=h)
    b = client.post("/api/auth/login", json={"login": "ghost", "password": "bad"}, headers=h)
    assert a.status_code == b.status_code == 401
    assert a.json() == b.json()


def test_brute_force_is_blocked(client: TestClient) -> None:
    h = {"X-Client": "mobile"}
    for _ in range(5):
        r = client.post("/api/auth/login", json={"login": "demo", "password": "x"}, headers=h)
        assert r.status_code == 401
    # Даже верный пароль не принимается, пока действует блокировка.
    r = client.post("/api/auth/login", json={"login": "demo", "password": "demo12345"}, headers=h)
    assert r.status_code == 429
    assert "retry-after" in r.headers


def test_passwords_stored_as_argon2(client: TestClient, settings: Settings) -> None:
    conn = sqlite3.connect(settings.db_path)
    hashes = [h for (h,) in conn.execute("SELECT password_hash FROM drivers")]
    conn.close()
    assert hashes and all(h.startswith("$argon2id$") for h in hashes)
    assert not any("demo12345" in h for h in hashes)


def test_session_token_stored_only_as_hash(client: TestClient, settings: Settings) -> None:
    token = login_mobile(client)["Authorization"].split()[1]
    conn = sqlite3.connect(settings.db_path)
    stored = [h for (h,) in conn.execute("SELECT token_hash FROM sessions")]
    conn.close()
    assert token not in stored
    assert len(stored) == 1 and len(stored[0]) == 64


def test_logout_revokes_token(client: TestClient, auth: dict) -> None:
    assert client.get("/api/auth/me", headers=auth).status_code == 200
    assert client.post("/api/auth/logout", headers=auth).status_code == 204
    assert client.get("/api/auth/me", headers=auth).status_code == 401


def test_expired_session_rejected(client: TestClient, auth: dict, settings: Settings) -> None:
    conn = sqlite3.connect(settings.db_path)
    conn.execute("UPDATE sessions SET expires_ms = 0")
    conn.commit()
    conn.close()
    assert client.get("/api/auth/me", headers=auth).status_code == 401


# ---------- веб: cookie и CSRF ----------


def test_web_login_sets_strict_httponly_cookie_and_no_token(client: TestClient) -> None:
    r = web_login(client)
    assert r.status_code == 200
    assert r.json()["token"] is None  # токен недоступен JavaScript
    cookie = r.headers["set-cookie"]
    assert cookie.startswith("__Host-diary_session=")
    for flag in ("HttpOnly", "Secure", "SameSite=strict", "Path=/"):
        assert flag.lower() in cookie.lower()
    assert "domain=" not in cookie.lower()


def test_web_session_reads_data(client: TestClient) -> None:
    web_login(client)
    r = client.get("/api/days/2026-10-01")
    assert r.status_code == 200
    assert r.json()["summary"]["net"] == 3315


def test_web_login_requires_csrf_header(client: TestClient) -> None:
    r = client.post("/api/auth/login", json={"login": "demo", "password": "demo12345"})
    assert r.status_code == 403
    assert r.json()["error"] == "csrf_failed"


TRIP = {
    "id": "c1",
    "start": "2026-10-07T10:00:00+05:00",
    "end": "2026-10-07T10:10:00+05:00",
    "amount": 100,
    "payment": "cash",
    "commission": 0,
}


def test_cookie_write_without_csrf_header_rejected(client: TestClient) -> None:
    web_login(client)
    r = client.post("/api/trips", json=TRIP)
    assert r.status_code == 403
    assert client.post("/api/trips", json=TRIP, headers=WEB).status_code == 201


def test_cookie_write_from_foreign_origin_rejected(client: TestClient) -> None:
    web_login(client)
    r = client.post("/api/trips", json=TRIP, headers={**WEB, "Origin": "https://evil.example"})
    assert r.status_code == 403
    ok = client.post("/api/trips", json=TRIP, headers={**WEB, "Origin": "https://testserver"})
    assert ok.status_code == 201


def test_web_logout_clears_cookie_and_session(client: TestClient) -> None:
    web_login(client)
    assert client.post("/api/auth/logout", headers=WEB).status_code == 204
    assert client.get("/api/auth/me").status_code == 401


def test_no_cors_headers(client: TestClient) -> None:
    r = client.options(
        "/api/trips",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"},
    )
    assert "access-control-allow-origin" not in r.headers


# ---------- заголовки, ошибки, лимиты ----------


def test_security_headers(client: TestClient) -> None:
    r = client.get("/api/health")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["x-frame-options"] == "DENY"
    assert r.headers["referrer-policy"] == "no-referrer"
    assert "frame-ancestors 'none'" in r.headers["content-security-policy"]
    assert "unsafe-eval'" not in r.headers["content-security-policy"].replace("wasm-unsafe", "")
    assert r.headers["cache-control"] == "no-store"
    assert "server" not in r.headers


def test_validation_error_does_not_echo_input(client: TestClient, auth: dict) -> None:
    secret = "<script>alert(1)</script>"
    r = client.post("/api/trips", json={**TRIP, "payment": secret}, headers=auth)
    assert r.status_code == 422
    assert secret not in r.text
    assert "input" not in r.json()["details"][0]


def test_large_body_rejected(client: TestClient, auth: dict) -> None:
    r = client.post("/api/trips", content=b"x" * 20_000, headers=auth)
    assert r.status_code == 413


def test_large_chunked_body_rejected(client: TestClient, auth: dict) -> None:
    def chunks():
        for _ in range(40):
            yield b"x" * 1000

    r = client.post("/api/trips", content=chunks(), headers=auth)
    assert r.status_code == 413


def test_unknown_api_path_is_json_404(client: TestClient, auth: dict) -> None:
    r = client.get("/api/admin", headers=auth)
    assert r.status_code == 404
    assert r.json()["error"] == "not_found"


def test_api_rate_limit(settings: Settings) -> None:
    with make_client(with_settings(settings, api_rate_per_minute=5)) as c:
        codes = [c.get("/api/health").status_code for _ in range(7)]
    assert codes[:5] == [200] * 5
    assert codes[5:] == [429, 429]


def test_docs_disabled_in_prod(settings: Settings) -> None:
    with make_client(with_settings(settings, env="prod")) as c:
        assert c.get("/docs").status_code == 404
        assert c.get("/openapi.json").status_code == 404
        assert "strict-transport-security" in c.get("/api/health").headers


def test_docs_disabled_in_prod_with_web_client(settings: Settings, tmp_path) -> None:
    """Как в Docker-образе: прод + собранный сайт. Раздача сайта не должна
    отвечать 200 на /docs и /openapi.json (страницей приложения)."""
    web = tmp_path / "web"
    web.mkdir()
    (web / "index.html").write_text("<html>app</html>")
    with make_client(with_settings(settings, env="prod", web_dir=web)) as c:
        for path in ["/docs", "/docs/", "/openapi.json", "/redoc"]:
            assert c.get(path).status_code == 404, path
        assert c.get("/").text == "<html>app</html>"


def test_web_static_cannot_escape_dir(settings: Settings, tmp_path) -> None:
    web = tmp_path / "web"
    web.mkdir()
    (web / "index.html").write_text("<html>app</html>")
    (tmp_path / "secret.txt").write_text("TOP SECRET")
    with make_client(with_settings(settings, web_dir=web)) as c:
        for path in ["/../secret.txt", "/%2e%2e/secret.txt", "/..%2fsecret.txt"]:
            r = c.get(path)
            assert "TOP SECRET" not in r.text
        assert c.get("/").text == "<html>app</html>"
        assert c.get("/some/spa/route").text == "<html>app</html>"


def test_missing_static_file_is_404_not_html(settings: Settings, tmp_path) -> None:
    """Браузер запрашивает /favicon.ico сам; HTML вместо картинки ломает значок вкладки."""
    web = tmp_path / "web"
    web.mkdir()
    (web / "index.html").write_text("<html>app</html>")
    (web / "favicon.ico").write_bytes(b"\x00\x00\x01\x00")
    with make_client(with_settings(settings, web_dir=web)) as c:
        ico = c.get("/favicon.ico")
        assert ico.status_code == 200
        assert ico.headers["content-type"] in {"image/vnd.microsoft.icon", "image/x-icon"}
        for path in ["/missing.png", "/assets/nope.js", "/apple-touch-icon.png"]:
            r = c.get(path)
            assert r.status_code == 404, path
            assert "<html>" not in r.text
