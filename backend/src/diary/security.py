"""Пароли, сессии, ограничение частоты запросов."""

from __future__ import annotations

import hashlib
import secrets
import sqlite3
import threading
import time
from collections import deque
from dataclasses import dataclass
from datetime import timedelta

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

_hasher = PasswordHasher()
# Хеш-пустышка: для несуществующего логина всё равно тратим время на проверку,
# чтобы по времени ответа нельзя было понять, есть ли такой пользователь.
_DUMMY_HASH = _hasher.hash(secrets.token_urlsafe(16))


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


@dataclass(frozen=True)
class Driver:
    id: int
    login: str
    name: str


def _now_ms() -> int:
    return int(time.time() * 1000)


def _token_hash(token: str) -> str:
    # Токен — 256 бит случайности, поэтому достаточно SHA-256 без соли:
    # утечка базы не даёт рабочих токенов.
    return hashlib.sha256(token.encode()).hexdigest()


def authenticate(conn: sqlite3.Connection, login: str, password: str) -> Driver | None:
    row = conn.execute(
        "SELECT id, login, name, password_hash FROM drivers WHERE login = ?", (login,)
    ).fetchone()
    ok = verify_password(row["password_hash"] if row else None, password)
    if not ok or row is None:
        return None
    return Driver(id=row["id"], login=row["login"], name=row["name"])


def create_session(conn: sqlite3.Connection, driver_id: int, ttl: timedelta) -> str:
    token = secrets.token_urlsafe(32)
    now = _now_ms()
    conn.execute("DELETE FROM sessions WHERE expires_ms <= ?", (now,))
    conn.execute(
        "INSERT INTO sessions (token_hash, driver_id, created_ms, expires_ms) VALUES (?, ?, ?, ?)",
        (_token_hash(token), driver_id, now, now + int(ttl.total_seconds() * 1000)),
    )
    return token


def resolve_session(conn: sqlite3.Connection, token: str) -> Driver | None:
    if not token or len(token) > 128:
        return None
    row = conn.execute(
        """
        SELECT d.id, d.login, d.name FROM sessions s
        JOIN drivers d ON d.id = s.driver_id
        WHERE s.token_hash = ? AND s.expires_ms > ?
        """,
        (_token_hash(token), _now_ms()),
    ).fetchone()
    if row is None:
        return None
    return Driver(id=row["id"], login=row["login"], name=row["name"])


def delete_session(conn: sqlite3.Connection, token: str) -> None:
    conn.execute("DELETE FROM sessions WHERE token_hash = ?", (_token_hash(token),))


class RateLimiter:
    """Скользящее окно в памяти процесса.

    Для одного инстанса этого достаточно; при нескольких репликах счётчики
    нужно вынести в общее хранилище (Redis).
    """

    def __init__(self, limit: int, window: timedelta, max_keys: int = 100_000) -> None:
        self.limit = limit
        self.window = window.total_seconds()
        self.max_keys = max_keys
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def _prune(self, key: str, now: float) -> deque[float]:
        hits = self._hits.get(key)
        if hits is None:
            if len(self._hits) >= self.max_keys:
                self._evict(now)
            hits = self._hits[key] = deque()
        while hits and hits[0] <= now - self.window:
            hits.popleft()
        return hits

    def _evict(self, now: float) -> None:
        stale = [k for k, h in self._hits.items() if not h or h[-1] <= now - self.window]
        for k in stale:
            del self._hits[k]
        if len(self._hits) >= self.max_keys:
            self._hits.clear()

    def is_blocked(self, key: str) -> bool:
        with self._lock:
            return len(self._prune(key, time.monotonic())) >= self.limit

    def hit(self, key: str) -> bool:
        """Учитывает попытку. Возвращает False, если лимит уже исчерпан."""
        with self._lock:
            now = time.monotonic()
            hits = self._prune(key, now)
            if len(hits) >= self.limit:
                return False
            hits.append(now)
            return True

    def reset(self, key: str) -> None:
        with self._lock:
            self._hits.pop(key, None)
