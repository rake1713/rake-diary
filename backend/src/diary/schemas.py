"""Схемы API. Строгие: лишние поля и «2400» строкой вместо числа — ошибка."""

from __future__ import annotations

import re
from datetime import datetime, timedelta
from typing import Annotated, Any, Literal

from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    StrictInt,
    StrictStr,
    model_validator,
)

MAX_AMOUNT = 10_000_000  # 10 млн ₸ за поездку — заведомо больше реального
MAX_TRIP_DURATION = timedelta(hours=24)
# Строго: дата, время и явное смещение (Z или ±HH:MM). Без смещения время неоднозначно.
_ISO_WITH_OFFSET = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$"
)


def _require_iso_string(value: Any) -> Any:
    if not isinstance(value, str) or not _ISO_WITH_OFFSET.match(value):
        raise ValueError(
            "ожидается время ISO 8601 с часовым поясом, например 2026-10-01T08:10:00+05:00"
        )
    return value


def _sane_year(value: datetime) -> datetime:
    if not 2000 <= value.year <= 2100:
        raise ValueError("год вне допустимого диапазона")
    return value


IsoDateTime = Annotated[datetime, BeforeValidator(_require_iso_string), AfterValidator(_sane_year)]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class TripIn(Strict):
    id: Annotated[StrictStr, Field(pattern=r"^[A-Za-z0-9_-]{1,64}$")]
    start: IsoDateTime
    end: IsoDateTime
    amount: Annotated[StrictInt, Field(gt=0, le=MAX_AMOUNT)]
    payment: Literal["cash", "card"]
    commission: Annotated[StrictInt, Field(ge=0, le=MAX_AMOUNT)]

    @model_validator(mode="after")
    def _check_consistency(self) -> TripIn:
        if self.end <= self.start:
            raise ValueError("окончание поездки должно быть позже начала")
        if self.end - self.start > MAX_TRIP_DURATION:
            raise ValueError("поездка не может длиться больше 24 часов")
        if self.commission > self.amount:
            raise ValueError("комиссия не может быть больше суммы поездки")
        return self


class TripOut(BaseModel):
    id: str
    start: datetime
    end: datetime
    amount: int
    payment: Literal["cash", "card"]
    commission: int


class SummaryOut(BaseModel):
    trips: int
    revenue: int
    commission: int
    net: int
    cash: int
    card: int


class DayOut(BaseModel):
    date: str
    utc_offset: str
    summary: SummaryOut
    trips: list[TripOut]


class DayListItem(BaseModel):
    date: str
    trips: int
    net: int


class LoginIn(Strict):
    login: Annotated[StrictStr, Field(min_length=1, max_length=64)]
    password: Annotated[StrictStr, Field(min_length=1, max_length=256)]


class MeOut(BaseModel):
    login: str
    name: str
    utc_offset: str


class LoginOut(BaseModel):
    driver: MeOut
    # Только для мобильного клиента. Веб получает сессию в HttpOnly-cookie,
    # а токен в теле ответа сделал бы её доступной для JavaScript.
    token: str | None = None
    expires_in: int
