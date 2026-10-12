"""Список поездок и сводка за день через API."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


def test_day_matches_task_example(client: TestClient, auth: dict) -> None:
    r = client.get("/api/days/2026-10-01", headers=auth)
    assert r.status_code == 200
    body = r.json()
    assert body["date"] == "2026-10-01"
    assert body["utc_offset"] == "+05:00"
    assert body["summary"] == {
        "trips": 2,
        "revenue": 3900,
        "commission": 585,
        "net": 3315,
        "cash": 1500,
        "card": 2400,
    }
    assert [t["id"] for t in body["trips"]] == ["t1", "t2"]
    assert body["trips"][0]["start"] == "2026-10-01T08:10:00+05:00"
    assert body["trips"][0]["end"] == "2026-10-01T08:32:00+05:00"


def test_day_is_local_not_utc(client: TestClient, auth: dict) -> None:
    """t7 начинается 03.10 в 00:40 по Алматы — это 02.10 19:40 UTC.
    Она должна попасть в 03.10, а не в 02.10."""
    oct2 = client.get("/api/days/2026-10-02", headers=auth).json()
    oct3 = client.get("/api/days/2026-10-03", headers=auth).json()
    assert "t7" not in [t["id"] for t in oct2["trips"]]
    assert [t["id"] for t in oct3["trips"]] == ["t7"]


def test_trip_across_midnight_belongs_to_start_day(client: TestClient, auth: dict) -> None:
    """t6: 02.10 23:50 → 03.10 00:15 — относится к дню начала."""
    oct2 = client.get("/api/days/2026-10-02", headers=auth).json()
    assert [t["id"] for t in oct2["trips"]] == ["t3", "t4", "t5", "t6"]
    assert oct2["summary"]["revenue"] == 3100 + 1800 + 4200 + 2600


def test_empty_day_returns_zeros_not_404(client: TestClient, auth: dict) -> None:
    r = client.get("/api/days/2026-09-15", headers=auth)
    assert r.status_code == 200
    assert r.json()["trips"] == []
    assert r.json()["summary"] == {
        "trips": 0,
        "revenue": 0,
        "commission": 0,
        "net": 0,
        "cash": 0,
        "card": 0,
    }


def test_invalid_dates_rejected(client: TestClient, auth: dict) -> None:
    for bad in ["2026-02-30", "2026-1-1", "01.10.2026", "20261001", "1800-01-01", "x"]:
        r = client.get(f"/api/days/{bad}", headers=auth)
        assert r.status_code == 422, bad
        assert r.json()["error"] == "invalid_date"


def test_list_days_newest_first(client: TestClient, auth: dict) -> None:
    r = client.get("/api/days", headers=auth)
    assert r.status_code == 200
    assert r.json() == [
        {"date": "2026-10-03", "trips": 1, "net": 1900 - 285},
        {"date": "2026-10-02", "trips": 4, "net": 11700 - 1755},
        {"date": "2026-10-01", "trips": 2, "net": 3315},
    ]


def test_list_days_for_week(client: TestClient, auth: dict) -> None:
    """Полоса недели: только дни внутри периода, границы — по местному времени."""
    r = client.get("/api/days?from=2026-09-28&to=2026-10-02", headers=auth)
    assert [d["date"] for d in r.json()] == ["2026-10-02", "2026-10-01"]
    # t7 (03.10 00:40 по Алматы = 02.10 19:40 UTC) не должна попасть во 2 октября.
    assert r.json()[0]["trips"] == 4


@pytest.mark.parametrize(
    "query",
    [
        "from=2026-10-01",
        "to=2026-10-01",
        "from=2026-10-05&to=2026-10-01",
        "from=2026-01-01&to=2026-12-31",
        "from=bad&to=2026-10-01",
    ],
)
def test_list_days_bad_range(client: TestClient, auth: dict, query: str) -> None:
    r = client.get(f"/api/days?{query}", headers=auth)
    assert r.status_code == 422
