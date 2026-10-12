"""Расчёт сводки — чистая функция."""

from __future__ import annotations

from dataclasses import dataclass

from diary.summary import DaySummary, summarize


@dataclass
class T:
    amount: int
    commission: int
    payment: str


def test_example_from_task() -> None:
    """Пример из задания: 2 поездки, 3 900 ₸, комиссия 585 ₸, на руки 3 315 ₸."""
    s = summarize([T(2400, 360, "card"), T(1500, 225, "cash")])
    assert s == DaySummary(trips=2, revenue=3900, commission=585, net=3315, cash=1500, card=2400)


def test_empty_day_is_all_zeros() -> None:
    assert summarize([]) == DaySummary(0, 0, 0, 0, 0, 0)


def test_cash_and_card_add_up_to_revenue() -> None:
    trips = [T(1000, 150, "cash"), T(2000, 300, "cash"), T(3000, 0, "card")]
    s = summarize(trips)
    assert s.cash == 3000
    assert s.card == 3000
    assert s.cash + s.card == s.revenue == 6000
    assert s.net == 6000 - 450


def test_money_stays_integer() -> None:
    s = summarize([T(333, 33, "card")] * 3)
    assert s.revenue == 999 and isinstance(s.revenue, int)
    assert s.net == 900 and isinstance(s.net, int)
