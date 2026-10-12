"""Добавление поездки: проверка данных и защита от дублей."""

from __future__ import annotations

import threading
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from diary import db
from diary.config import Settings
from diary.trips import SaveResult, Trip, save_trip

NEW_TRIP = {
    "id": "t100",
    "start": "2026-10-05T10:00:00+05:00",
    "end": "2026-10-05T10:25:00+05:00",
    "amount": 2000,
    "payment": "card",
    "commission": 300,
}


def day(client: TestClient, auth: dict, d: str = "2026-10-05") -> dict:
    return client.get(f"/api/days/{d}", headers=auth).json()


def test_add_trip_appears_in_day(client: TestClient, auth: dict) -> None:
    r = client.post("/api/trips", json=NEW_TRIP, headers=auth)
    assert r.status_code == 201
    assert r.json()["id"] == "t100"
    body = day(client, auth)
    assert [t["id"] for t in body["trips"]] == ["t100"]
    assert body["summary"]["net"] == 1700


# ---------- дубли ----------


def test_resend_same_trip_does_not_duplicate(client: TestClient, auth: dict) -> None:
    first = client.post("/api/trips", json=NEW_TRIP, headers=auth)
    second = client.post("/api/trips", json=NEW_TRIP, headers=auth)
    third = client.post("/api/trips", json=NEW_TRIP, headers=auth)
    assert first.status_code == 201
    assert second.status_code == 200  # уже было — возвращаем сохранённую
    assert third.status_code == 200
    assert second.json() == first.json()
    body = day(client, auth)
    assert len(body["trips"]) == 1
    assert body["summary"]["revenue"] == 2000


def test_seeded_trip_resend_is_duplicate(client: TestClient, auth: dict) -> None:
    t1 = {
        "id": "t1",
        "start": "2026-10-01T08:10:00+05:00",
        "end": "2026-10-01T08:32:00+05:00",
        "amount": 2400,
        "payment": "card",
        "commission": 360,
    }
    assert client.post("/api/trips", json=t1, headers=auth).status_code == 200
    assert day(client, auth, "2026-10-01")["summary"]["trips"] == 2


def test_same_moment_in_other_timezone_is_duplicate(client: TestClient, auth: dict) -> None:
    """08:10+05:00 и 03:10Z — один и тот же момент, значит та же поездка."""
    client.post("/api/trips", json=NEW_TRIP, headers=auth)
    utc = {**NEW_TRIP, "start": "2026-10-05T05:00:00Z", "end": "2026-10-05T05:25:00Z"}
    r = client.post("/api/trips", json=utc, headers=auth)
    assert r.status_code == 200
    assert len(day(client, auth)["trips"]) == 1


def test_same_id_different_data_is_conflict(client: TestClient, auth: dict) -> None:
    client.post("/api/trips", json=NEW_TRIP, headers=auth)
    r = client.post("/api/trips", json={**NEW_TRIP, "amount": 9999}, headers=auth)
    assert r.status_code == 409
    assert r.json()["error"] == "trip_conflict"
    body = day(client, auth)
    assert body["summary"]["revenue"] == 2000  # исходная запись не перезаписана


def test_concurrent_resends_create_one_trip(settings: Settings, client: TestClient) -> None:
    """Настоящая гонка: 16 потоков, у каждого своё соединение с базой,
    одновременно сохраняют одну и ту же поездку."""
    trip = Trip(
        id="race", start_ms=1_000_000, end_ms=2_000_000, amount=500, payment="cash", commission=0
    )
    barrier = threading.Barrier(16)

    def worker(_: int) -> SaveResult:
        with db.connection(settings.db_path) as conn:
            barrier.wait()
            return save_trip(conn, 1, trip)[0]

    with ThreadPoolExecutor(max_workers=16) as pool:
        results = list(pool.map(worker, range(16)))

    assert results.count(SaveResult.CREATED) == 1
    assert results.count(SaveResult.DUPLICATE) == 15
    with db.connection(settings.db_path) as conn:
        (count,) = conn.execute("SELECT COUNT(*) FROM trips WHERE id = 'race'").fetchone()
    assert count == 1


def test_concurrent_api_resends_create_one_trip(client: TestClient, auth: dict) -> None:
    with ThreadPoolExecutor(max_workers=8) as pool:
        codes = list(
            pool.map(
                lambda _: client.post("/api/trips", json=NEW_TRIP, headers=auth).status_code,
                range(8),
            )
        )
    assert sorted(codes) == [200] * 7 + [201]
    assert len(day(client, auth)["trips"]) == 1


def test_trip_ids_are_per_driver(client: TestClient, auth: dict, auth2: dict) -> None:
    """Второй водитель может использовать тот же id — это не дубль и не конфликт,
    и по ответу нельзя узнать, что у первого водителя такая поездка есть."""
    client.post("/api/trips", json=NEW_TRIP, headers=auth)
    r = client.post("/api/trips", json={**NEW_TRIP, "amount": 777}, headers=auth2)
    assert r.status_code == 201
    assert day(client, auth)["summary"]["revenue"] == 2000
    assert day(client, auth2)["summary"]["revenue"] == 777


# ---------- проверка данных ----------

INVALID = {
    "сумма 0": {"amount": 0},
    "сумма отрицательная": {"amount": -100},
    "сумма строкой": {"amount": "2000"},
    "сумма дробная": {"amount": 2000.5},
    "сумма bool": {"amount": True},
    "сумма огромная": {"amount": 10**12},
    "окончание = начало": {"end": NEW_TRIP["start"]},
    "окончание раньше начала": {"end": "2026-10-05T09:59:00+05:00"},
    "дольше суток": {"end": "2026-10-06T10:00:01+05:00"},
    "время без пояса": {"start": "2026-10-05T10:00:00"},
    "время числом": {"start": 1759640400},
    "время мусор": {"start": "вчера"},
    "оплата неизвестная": {"payment": "crypto"},
    "комиссия больше суммы": {"commission": 2001},
    "комиссия отрицательная": {"commission": -1},
    "id с пробелом": {"id": "t 1"},
    "id пустой": {"id": ""},
    "id длинный": {"id": "x" * 65},
    "id SQL": {"id": "1'; DROP TABLE trips;--"},
    "лишнее поле": {"driver_id": 2},
}


@pytest.mark.parametrize("patch", INVALID.values(), ids=INVALID.keys())
def test_invalid_trip_rejected(client: TestClient, auth: dict, patch: dict) -> None:
    r = client.post("/api/trips", json={**NEW_TRIP, **patch}, headers=auth)
    assert r.status_code == 422, r.text
    body = r.json()
    assert body["error"] == "validation_error"
    assert body["details"]
    assert len(day(client, auth)["trips"]) == 0


@pytest.mark.parametrize("field", ["id", "start", "end", "amount", "payment", "commission"])
def test_missing_field_rejected(client: TestClient, auth: dict, field: str) -> None:
    trip = {k: v for k, v in NEW_TRIP.items() if k != field}
    assert client.post("/api/trips", json=trip, headers=auth).status_code == 422


def test_end_before_start_message_is_readable(client: TestClient, auth: dict) -> None:
    r = client.post(
        "/api/trips", json={**NEW_TRIP, "end": "2026-10-05T09:00:00+05:00"}, headers=auth
    )
    messages = [d["message"] for d in r.json()["details"]]
    assert "окончание поездки должно быть позже начала" in messages


def test_zero_commission_allowed(client: TestClient, auth: dict) -> None:
    r = client.post("/api/trips", json={**NEW_TRIP, "commission": 0}, headers=auth)
    assert r.status_code == 201


def test_non_json_body_rejected(client: TestClient, auth: dict) -> None:
    r = client.post(
        "/api/trips",
        content=b"not json",
        headers={**auth, "Content-Type": "application/json"},
    )
    assert r.status_code == 422
