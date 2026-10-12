"""Демо-водители и поездки из data/trips.json. Повторный запуск ничего не дублирует."""

from __future__ import annotations

import json
import logging
import sqlite3
from pathlib import Path

from diary.config import Settings
from diary.db import transaction
from diary.schemas import TripIn
from diary.security import hash_password, verify_password
from diary.trips import SaveResult, Trip, save_trip

log = logging.getLogger("diary.seed")


def seed(conn: sqlite3.Connection, settings: Settings) -> None:
    for demo in settings.demo_drivers:
        row = conn.execute(
            "SELECT id, password_hash FROM drivers WHERE login = ?", (demo.login,)
        ).fetchone()
        if row is None:
            with transaction(conn):
                cur = conn.execute(
                    "INSERT INTO drivers (login, password_hash, name) VALUES (?, ?, ?)",
                    (demo.login, hash_password(demo.password), demo.name),
                )
            driver_id = cur.lastrowid
        else:
            driver_id = row["id"]
            if not verify_password(row["password_hash"], demo.password):
                conn.execute(
                    "UPDATE drivers SET password_hash = ? WHERE id = ?",
                    (hash_password(demo.password), driver_id),
                )
        if demo.seed_trips and settings.seed_path and settings.seed_path.exists():
            _import_trips(conn, int(driver_id), settings.seed_path)


def _import_trips(conn: sqlite3.Connection, driver_id: int, path: Path) -> None:
    raw = json.loads(path.read_text(encoding="utf-8"))
    created = 0
    for item in raw:
        # Те же проверки, что и у API: в базу не попадает ничего невалидного.
        trip = Trip.from_input(TripIn.model_validate(item))
        result, _ = save_trip(conn, driver_id, trip)
        if result is SaveResult.CONFLICT:
            log.warning("seed: поездка %s в базе отличается от файла, оставляю как есть", trip.id)
        created += result is SaveResult.CREATED
    if created:
        log.info("seed: добавлено поездок: %d", created)
