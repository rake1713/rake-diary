"""Поездки: идемпотентное добавление и выборка за день."""

from __future__ import annotations

import sqlite3
import time
from dataclasses import dataclass
from datetime import date, timezone
from enum import Enum

from diary.db import transaction
from diary.schemas import TripIn, TripOut
from diary.summary import Payment
from diary.timeutil import day_bounds_ms, from_epoch_ms, local_date, to_epoch_ms


@dataclass(frozen=True)
class Trip:
    id: str
    start_ms: int
    end_ms: int
    amount: int
    payment: Payment
    commission: int

    @classmethod
    def from_input(cls, data: TripIn) -> Trip:
        return cls(
            id=data.id,
            start_ms=to_epoch_ms(data.start),
            end_ms=to_epoch_ms(data.end),
            amount=data.amount,
            payment=data.payment,
            commission=data.commission,
        )

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> Trip:
        return cls(
            id=row["id"],
            start_ms=row["start_ms"],
            end_ms=row["end_ms"],
            amount=row["amount"],
            payment=row["payment"],
            commission=row["commission"],
        )

    def to_out(self, tz: timezone) -> TripOut:
        return TripOut(
            id=self.id,
            start=from_epoch_ms(self.start_ms, tz),
            end=from_epoch_ms(self.end_ms, tz),
            amount=self.amount,
            payment=self.payment,
            commission=self.commission,
        )


class SaveResult(Enum):
    CREATED = "created"  # новая поездка
    DUPLICATE = "duplicate"  # тот же id и те же данные — повторная отправка
    CONFLICT = "conflict"  # тот же id, но другие данные


def save_trip(conn: sqlite3.Connection, driver_id: int, trip: Trip) -> tuple[SaveResult, Trip]:
    """Вставка через ON CONFLICT DO NOTHING: дубль ловит PRIMARY KEY в базе,
    поэтому два одновременных одинаковых запроса не создадут две записи.

    Сравниваем моменты времени, а не строки: 08:10+05:00 и 03:10Z — одна поездка.
    """
    with transaction(conn):
        cur = conn.execute(
            """
            INSERT INTO trips (driver_id, id, start_ms, end_ms,
                               amount, payment, commission, created_ms)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (driver_id, id) DO NOTHING
            """,
            (
                driver_id,
                trip.id,
                trip.start_ms,
                trip.end_ms,
                trip.amount,
                trip.payment,
                trip.commission,
                int(time.time() * 1000),
            ),
        )
        if cur.rowcount == 1:
            return SaveResult.CREATED, trip
        row = conn.execute(
            "SELECT * FROM trips WHERE driver_id = ? AND id = ?", (driver_id, trip.id)
        ).fetchone()
    existing = Trip.from_row(row)
    if existing == trip:
        return SaveResult.DUPLICATE, existing
    return SaveResult.CONFLICT, existing


def trips_for_day(conn: sqlite3.Connection, driver_id: int, day: date, tz: timezone) -> list[Trip]:
    # День водителя — полуинтервал в UTC; поездка относится к дню своего начала.
    lo, hi = day_bounds_ms(day, tz)
    rows = conn.execute(
        """
        SELECT * FROM trips
        WHERE driver_id = ? AND start_ms >= ? AND start_ms < ?
        ORDER BY start_ms, id
        """,
        (driver_id, lo, hi),
    ).fetchall()
    return [Trip.from_row(r) for r in rows]


@dataclass(frozen=True)
class DayTotal:
    date: str
    trips: int
    net: int


def day_totals(
    conn: sqlite3.Connection,
    driver_id: int,
    tz: timezone,
    start: date | None = None,
    end: date | None = None,
    limit: int = 60,
) -> list[DayTotal]:
    """Итоги по дням с поездками, от новых к старым.

    С периодом [start, end] — все дни в нём (для полосы недели),
    без периода — последние `limit` дней с поездками.
    """
    if start is not None and end is not None:
        lo, _ = day_bounds_ms(start, tz)
        _, hi = day_bounds_ms(end, tz)
    else:
        lo, hi = 0, 2**62
    rows = conn.execute(
        """
        SELECT start_ms, amount - commission AS net FROM trips
        WHERE driver_id = ? AND start_ms >= ? AND start_ms < ?
        ORDER BY start_ms DESC
        """,
        (driver_id, lo, hi),
    ).fetchall()
    totals: dict[str, list[int]] = {}
    for r in rows:
        d = local_date(r["start_ms"], tz).isoformat()
        if d not in totals:
            if start is None and len(totals) >= limit:
                break
            totals[d] = [0, 0]
        totals[d][0] += 1
        totals[d][1] += r["net"]
    return [DayTotal(date=d, trips=n, net=net) for d, (n, net) in totals.items()]
