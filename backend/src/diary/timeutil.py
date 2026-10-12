"""Время: всё хранится в UTC (миллисекунды), «день» — по местному времени водителя."""

from __future__ import annotations

import re
from datetime import UTC, date, datetime, timedelta, timezone

_OFFSET_RE = re.compile(r"^([+-])(\d{2}):(\d{2})$")


def parse_utc_offset(raw: str) -> timezone:
    m = _OFFSET_RE.match(raw)
    if not m:
        raise ValueError(f"Смещение должно быть вида +05:00, получено {raw!r}")
    sign = 1 if m.group(1) == "+" else -1
    delta = timedelta(hours=int(m.group(2)), minutes=int(m.group(3)))
    return timezone(sign * delta)


def format_utc_offset(tz: timezone) -> str:
    total = int(tz.utcoffset(None).total_seconds()) // 60
    sign = "+" if total >= 0 else "-"
    hours, minutes = divmod(abs(total), 60)
    return f"{sign}{hours:02d}:{minutes:02d}"


def to_epoch_ms(dt: datetime) -> int:
    if dt.tzinfo is None:
        raise ValueError("Время без часового пояса недопустимо")
    delta = dt.astimezone(UTC) - datetime(1970, 1, 1, tzinfo=UTC)
    return delta // timedelta(milliseconds=1)


def from_epoch_ms(ms: int, tz: timezone) -> datetime:
    return (datetime(1970, 1, 1, tzinfo=UTC) + timedelta(milliseconds=ms)).astimezone(tz)


def local_date(ms: int, tz: timezone) -> date:
    """День поездки — дата её начала по местному времени водителя."""
    return from_epoch_ms(ms, tz).date()


def day_bounds_ms(day: date, tz: timezone) -> tuple[int, int]:
    """Полуинтервал [начало дня, начало следующего дня) в UTC-миллисекундах."""
    start = datetime(day.year, day.month, day.day, tzinfo=tz)
    return to_epoch_ms(start), to_epoch_ms(start + timedelta(days=1))
