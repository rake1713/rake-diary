import 'package:flutter/material.dart';

import '../api/models.dart';
import '../format.dart';
import '../shift.dart';
import '../theme.dart';

/// Лента смены: поездки по порядку, слева время, между поездками — простой.
class ShiftTimeline extends StatelessWidget {
  const ShiftTimeline({super.key, required this.trips});

  final List<Trip> trips;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, trip) in trips.indexed) ...[
          if (idleBefore(trips, i) case final idle?) _IdleGap(idle: idle),
          _TripRow(trip: trip, isFirst: i == 0, isLast: i == trips.length - 1),
        ],
      ],
    );
  }
}

const _timeColumn = 52.0;
const _railWidth = 22.0;

class _TripRow extends StatelessWidget {
  const _TripRow({
    required this.trip,
    required this.isFirst,
    required this.isLast,
  });

  final Trip trip;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    final isCash = trip.payment == Payment.cash;
    final payColor = isCash ? d.cash : d.card;
    final nextDay = isoDate(trip.end) != isoDate(trip.start);
    final minutes = trip.end.difference(trip.start).inMinutes;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _timeColumn,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatTime(trip.start),
                    style: clock(15, weight: FontWeight.w700, color: d.text),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: formatTime(trip.end)),
                        if (nextDay)
                          TextSpan(
                            text: '+1',
                            style: clock(
                              10,
                              weight: FontWeight.w700,
                              color: d.accentText,
                            ),
                          ),
                      ],
                    ),
                    style: clock(13, color: d.muted),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: _railWidth,
            child: CustomPaint(
              painter: _RailPainter(
                color: d.line,
                dot: payColor,
                top: !isFirst,
                bottom: !isLast,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                decoration: BoxDecoration(
                  color: d.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatMoney(trip.amount),
                            style: figures(
                              22,
                              weight: FontWeight.w700,
                              color: d.text,
                            ),
                          ),
                        ),
                        _PayBadge(
                          label: isCash ? 'НАЛ' : 'КАРТА',
                          color: payColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$minutes мин · комиссия ${formatMoney(trip.commission)}',
                      style: ui(13, color: d.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayBadge extends StatelessWidget {
  const _PayBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: caps(color).copyWith(fontSize: 11, letterSpacing: 1),
      ),
    );
  }
}

class _IdleGap extends StatelessWidget {
  const _IdleGap({required this.idle});

  final Duration idle;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          const SizedBox(width: _timeColumn),
          SizedBox(
            width: _railWidth,
            child: CustomPaint(
              painter: _RailPainter(color: d.line, dashed: true),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'простой ${formatDuration(idle)}',
            style: ui(13, color: d.muted),
          ),
        ],
      ),
    );
  }
}

/// Вертикальная линия смены с точкой поездки (цвет — способ оплаты).
class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.color,
    this.dot,
    this.top = true,
    this.bottom = true,
    this.dashed = false,
  });

  final Color color;
  final Color? dot;
  final bool top;
  final bool bottom;
  final bool dashed;

  static const _dotY = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final line = Paint()
      ..color = color
      ..strokeWidth = 2;
    if (dashed) {
      for (var y = 0.0; y < size.height; y += 6) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, (y + 3).clamp(0, size.height)),
          line,
        );
      }
      return;
    }
    if (top) canvas.drawLine(Offset(x, 0), Offset(x, _dotY), line);
    if (bottom) canvas.drawLine(Offset(x, _dotY), Offset(x, size.height), line);
    if (dot != null) {
      canvas.drawCircle(Offset(x, _dotY), 6, Paint()..color = dot!);
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.color != color ||
      old.dot != dot ||
      old.top != top ||
      old.bottom != bottom;
}
