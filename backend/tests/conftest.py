from __future__ import annotations

from collections.abc import Iterator
from dataclasses import replace
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from diary.app import create_app
from diary.config import DemoDriver, Settings

DATA = Path(__file__).resolve().parents[2] / "data" / "trips.json"

DEMO = DemoDriver(login="demo", password="demo12345", name="Демо", seed_trips=True)
DEMO2 = DemoDriver(login="demo2", password="demo2pass", name="Второй", seed_trips=False)


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    return Settings(
        env="dev",
        db_path=str(tmp_path / "test.db"),
        seed_path=DATA,
        web_dir=None,
        cookie_secure=True,
        api_rate_per_minute=10_000,
        demo_drivers=(DEMO, DEMO2),
    )


def make_client(settings: Settings) -> TestClient:
    # https: cookie с флагом Secure по http клиент не отправил бы — как и браузер.
    return TestClient(create_app(settings), base_url="https://testserver")


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    with make_client(settings) as c:
        yield c


def login_mobile(client: TestClient, login: str = "demo", password: str = "demo12345") -> dict:
    r = client.post(
        "/api/auth/login",
        json={"login": login, "password": password},
        headers={"X-Client": "mobile"},
    )
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


@pytest.fixture
def auth(client: TestClient) -> dict:
    return login_mobile(client)


@pytest.fixture
def auth2(client: TestClient) -> dict:
    return login_mobile(client, "demo2", "demo2pass")


def with_settings(settings: Settings, **changes) -> Settings:
    return replace(settings, **changes)
