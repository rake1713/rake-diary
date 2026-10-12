import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

const _weekdays = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

/// Понедельник недели, в которую входит [day].
DateTime weekStart(DateTime day) =>
    day.subtract(Duration(days: day.weekday - 1));

/// Полоса недели: 7 дней со столбиками «на руки». Видно, какой день был хорошим,
/// и в один тап можно перейти к нему.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.selected,
    required this.today,
    required this.netByDate,
    required this.onSelect,
  });

  final DateTime selected;
  final DateTime today;
  final Map<String, int> netByDate;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    final monday = weekStart(selected);
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final maxNet = days
        .map((day) => netByDate[isoDate(day)] ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return Row(
      children: [
        for (final (i, day) in days.indexed)
          Expanded(
            child: _DayCell(
              key: Key('week-${isoDate(day)}'),
              label: _weekdays[i],
              day: day,
              net: netByDate[isoDate(day)] ?? 0,
              maxNet: maxNet,
              selected: isoDate(day) == isoDate(selected),
              isToday: isoDate(day) == isoDate(today),
              isFuture: day.isAfter(today),
              colors: d,
              onTap: () => onSelect(day),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.label,
    required this.day,
    required this.net,
    required this.maxNet,
    required this.selected,
    required this.isToday,
    required this.isFuture,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final DateTime day;
  final int net;
  final int maxNet;
  final bool selected;
  final bool isToday;
  final bool isFuture;
  final Dash colors;
  final VoidCallback onTap;

  static const _barArea = 40.0;

  @override
  Widget build(BuildContext context) {
    final d = colors;
    final ratio = maxNet == 0 ? 0.0 : net / maxNet;
    final barHeight = net > 0 ? 4 + (_barArea - 4) * ratio : 2.0;
    final barColor = selected ? d.accent : (net > 0 ? d.muted : d.line);
    final fg = isFuture ? d.muted.withValues(alpha: 0.5) : d.text;

    return Semantics(
      button: true,
      selected: selected,
      label: '${formatDayLong(day)}, на руки ${formatMoney(net)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? d.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: caps(selected ? d.accentText : d.muted)
                    .copyWith(fontSize: 11),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: _barArea,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    width: 14,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${day.day}',
                style: clock(
                  15,
                  weight: selected || isToday
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: fg,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isToday ? d.accent : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
