"""SQLite. Одно соединение на запрос; ограничения дублируются CHECK-ами в схеме."""

from __future__ import annotations

import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager

SCHEMA = """
CREATE TABLE IF NOT EXISTS drivers (
    id            INTEGER PRIMARY KEY,
    login         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    name          TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    driver_id  INTEGER NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    created_ms INTEGER NOT NULL,
    expires_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_expires ON sessions(expires_ms);

-- Ключ (driver_id, id): защита от дублей на уровне базы, а не «проверил и вставил».
-- id уникален в пределах водителя, поэтому по ответу на дубль нельзя узнать,
-- есть ли поездка с таким id у другого водителя.
CREATE TABLE IF NOT EXISTS trips (
    driver_id   INTEGER NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    id          TEXT    NOT NULL,
    start_ms    INTEGER NOT NULL,
    end_ms      INTEGER NOT NULL,
    amount      INTEGER NOT NULL CHECK (amount > 0),
    payment     TEXT    NOT NULL CHECK (payment IN ('cash', 'card')),
    commission  INTEGER NOT NULL CHECK (commission >= 0 AND commission <= amount),
    created_ms  INTEGER NOT NULL,
    PRIMARY KEY (driver_id, id),
    CHECK (end_ms > start_ms)
);
CREATE INDEX IF NOT EXISTS trips_by_start ON trips(driver_id, start_ms);
"""


def connect(path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(path, timeout=5.0, isolation_level=None, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA busy_timeout = 5000")
    return conn


def init_db(path: str) -> None:
    with connection(path) as conn:
        if path != ":memory:" and not path.startswith("file:"):
            conn.execute("PRAGMA journal_mode = WAL")
        conn.executescript(SCHEMA)


@contextmanager
def connection(path: str) -> Iterator[sqlite3.Connection]:
    conn = connect(path)
    try:
        yield conn
    finally:
        conn.close()


@contextmanager
def transaction(conn: sqlite3.Connection) -> Iterator[sqlite3.Connection]:
    """BEGIN IMMEDIATE: берём блокировку на запись сразу, без гонки «прочитал — записал»."""
    conn.execute("BEGIN IMMEDIATE")
    try:
        yield conn
    except BaseException:
        conn.execute("ROLLBACK")
        raise
    else:
        conn.execute("COMMIT")
