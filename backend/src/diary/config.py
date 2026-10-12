"""Настройки из переменных окружения.

Секретов для подписи токенов нет: сессии — случайные строки, в базе лежит только их хеш.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from datetime import timedelta, timezone
from pathlib import Path

from diary.timeutil import parse_utc_offset

ROOT = Path(__file__).resolve().parents[3]


def _env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_path(name: str, default: Path | None) -> Path | None:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return Path(raw) if raw else None


@dataclass(frozen=True)
class DemoDriver:
    login: str
    password: str
    name: str
    seed_trips: bool


@dataclass(frozen=True)
class Settings:
    env: str = "dev"
    db_path: str = str(ROOT / "backend" / "diary.db")
    seed_path: Path | None = ROOT / "data" / "trips.json"
    web_dir: Path | None = ROOT / "app" / "build" / "web"
    # Часовой пояс водителя: «день» считается по местному времени, а не по UTC.
    # Казахстан с 01.03.2024 живёт в UTC+5 без перехода на летнее время.
    driver_utc_offset: timezone = timezone(timedelta(hours=5))
    session_ttl: timedelta = timedelta(hours=12)
    cookie_secure: bool = True
    max_body_bytes: int = 16 * 1024
    login_max_failures: int = 5
    login_window: timedelta = timedelta(minutes=15)
    api_rate_per_minute: int = 120
    demo_drivers: tuple[DemoDriver, ...] = field(default_factory=tuple)

    @property
    def is_prod(self) -> bool:
        return self.env == "prod"

    @classmethod
    def from_env(cls) -> Settings:
        env = _env("DIARY_ENV", "dev")
        demo = (
            DemoDriver(
                login="demo",
                password=_env("DIARY_DEMO_PASSWORD", "demo12345"),
                name="Демо водитель",
                seed_trips=True,
            ),
            DemoDriver(
                login="demo2",
                password=_env("DIARY_DEMO2_PASSWORD", "demo2pass"),
                name="Второй водитель",
                seed_trips=False,
            ),
        )
        defaults = cls()
        return cls(
            env=env,
            db_path=_env("DIARY_DB_PATH", defaults.db_path),
            seed_path=_env_path("DIARY_SEED_PATH", defaults.seed_path),
            web_dir=_env_path("DIARY_WEB_DIR", defaults.web_dir),
            driver_utc_offset=parse_utc_offset(_env("DIARY_UTC_OFFSET", "+05:00")),
            session_ttl=timedelta(hours=int(_env("DIARY_SESSION_TTL_HOURS", "12"))),
            cookie_secure=_env_bool("DIARY_COOKIE_SECURE", True),
            demo_drivers=demo if _env_bool("DIARY_DEMO_ACCOUNTS", True) else (),
        )
