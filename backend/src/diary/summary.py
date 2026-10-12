"""Расчёт сводки за день. Чистая функция без базы — её и тестируем."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from typing import Literal, Protocol

Payment = Literal["cash", "card"]


class TripLike(Protocol):
    @property
    def amount(self) -> int: ...
    @property
    def commission(self) -> int: ...
    @property
    def payment(self) -> Payment: ...


@dataclass(frozen=True)
class DaySummary:
    trips: int
    revenue: int
    commission: int
    net: int
    cash: int
    card: int


def summarize(trips: Iterable[TripLike]) -> DaySummary:
    """Все суммы — целые тенге. Float для денег не используем."""
    count = revenue = commission = cash = card = 0
    for t in trips:
        count += 1
        revenue += t.amount
        commission += t.commission
        if t.payment == "cash":
            cash += t.amount
        elif t.payment == "card":
            card += t.amount
        else:  # pragma: no cover — защищено валидацией и CHECK в базе
            raise ValueError(f"Неизвестный способ оплаты: {t.payment!r}")
    return DaySummary(
        trips=count,
        revenue=revenue,
        commission=commission,
        net=revenue - commission,
        cash=cash,
        card=card,
    )
