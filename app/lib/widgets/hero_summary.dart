import 'package:flutter/material.dart';

import '../api/models.dart';
import '../format.dart';
import '../shift.dart';
import '../theme.dart';

/// Главный блок дня: «на руки» крупно, под ним выручка, комиссия,
/// поездки и пропорция наличные / карта.
class HeroSummary extends StatelessWidget {
  const HeroSummary({super.key, required this.summary, this.shift});

  final DaySummary summary;
  final ShiftStats? shift;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    final s = summary;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('НА РУКИ', style: caps(d.muted)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(s.net),
              key: const Key('net'),
              style: figures(54, weight: FontWeight.w700, color: d.accentText),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Stat(
                label: 'Поездок',
                value: '${s.trips}',
                key: const Key('stat-trips'),
              ),
              _Stat(
                label: 'Выручка',
                value: formatMoney(s.revenue),
                key: const Key('stat-revenue'),
              ),
              _Stat(
                label: 'Комиссия',
                value: formatMoney(-s.commission),
                color: s.commission > 0 ? d.negative : null,
                key: const Key('stat-commission'),
              ),
            ],
          ),
          if (s.revenue > 0) ...[
            const SizedBox(height: 20),
            _PaymentSplit(cash: s.cash, card: s.card),
          ],
          if (shift case final shift?) ...[
            const SizedBox(height: 18),
            Divider(color: d.line),
            const SizedBox(height: 14),
            _ShiftLine(shift: shift),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.style,
  });

  final String label;
  final String value;
  final Color? color;

  /// По умолчанию — цифры Onest; для времени — моноширинный «табло».
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: ui(13, color: d.muted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style:
                    style ??
                    figures(
                      18,
                      weight: FontWeight.w600,
                      color: color ?? d.text,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Полоса-пропорция: сразу видно, сколько денег уже на руках наличными.
class _PaymentSplit extends StatelessWidget {
  const _PaymentSplit({required this.cash, required this.card});

  final int cash;
  final int card;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              // stretch: иначе ColoredBox без ребёнка получает нулевую высоту.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (cash > 0)
                  Expanded(
                    flex: cash,
                    child: ColoredBox(color: d.cash),
                  ),
                if (cash > 0 && card > 0) const SizedBox(width: 3),
                if (card > 0)
                  Expanded(
                    flex: card,
                    child: ColoredBox(color: d.card),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _Legend(
                  color: d.cash,
                  label: 'нал',
                  value: formatMoney(cash),
                  key: const Key('cash'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: _Legend(
                  color: d.card,
                  label: 'карта',
                  value: formatMoney(card),
                  alignEnd: true,
                  key: const Key('card'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    super.key,
    required this.color,
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final Color color;
  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: ui(14, color: d.muted),
          ),
          TextSpan(
            text: value,
            style: figures(14, weight: FontWeight.w600, color: d.text),
          ),
        ],
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: alignEnd
          ? [text, const SizedBox(width: 8), dot]
          : [dot, const SizedBox(width: 8), text],
    );
  }
}

class _ShiftLine extends StatelessWidget {
  const _ShiftLine({required this.shift});

  final ShiftStats shift;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    final perHour = shift.netPerHour;
    return Row(
      key: const Key('shift-line'),
      children: [
        _Stat(
          label: 'Смена',
          value: '${formatTime(shift.start)}–${formatTime(shift.end)}',
          style: clock(16, weight: FontWeight.w600, color: d.text),
        ),
        _Stat(label: 'В пути', value: formatDuration(shift.driving)),
        _Stat(
          label: 'За час смены',
          value: perHour == null ? '—' : formatMoney(perHour),
        ),
      ],
    );
  }
}
