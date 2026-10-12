/// Показатели смены по списку поездок: длительность, простои, заработок в час.
/// Чистые функции без виджетов — их и тестируем.
library;

import 'api/models.dart';

class ShiftStats {
  const ShiftStats({
    required this.start,
    required this.end,
    required this.driving,
    required this.netPerHour,
  });

  /// Начало первой и конец последней поездки (по часам водителя).
  final DateTime start;
  final DateTime end;

  /// Сумма длительностей поездок — сколько реально был в пути.
  final Duration driving;

  /// «На руки» за час смены, целые тенге. null — если смена короче часа:
  /// одна поездка на 18 минут дала бы «5 383 ₸/ч», а это не про реальную смену.
  final int? netPerHour;

  Duration get duration => end.difference(start);

  /// null — поездок нет.
  static ShiftStats? of(List<Trip> trips, int net) {
    if (trips.isEmpty) return null;
    final start = trips
        .map((t) => t.start)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final end = trips.map((t) => t.end).reduce((a, b) => a.isAfter(b) ? a : b);
    final minutes = end.difference(start).inMinutes;
    return ShiftStats(
      start: start,
      end: end,
      driving: trips.fold(
        Duration.zero,
        (sum, t) => sum + t.end.difference(t.start),
      ),
      // Целочисленно, с округлением до тенге — без float, как и все деньги.
      netPerHour: minutes < 60 ? null : (net * 60 + minutes ~/ 2) ~/ minutes,
    );
  }
}

/// Простой перед поездкой [index] (между концом предыдущей и началом этой).
/// null — для первой поездки или если поездки пересекаются.
Duration? idleBefore(List<Trip> trips, int index) {
  if (index <= 0 || index >= trips.length) return null;
  final gap = trips[index].start.difference(trips[index - 1].end);
  return gap.inMinutes >= 1 ? gap : null;
}

/// 70 мин → «1 ч 10 мин», 45 мин → «45 мин», 120 мин → «2 ч».
String formatDuration(Duration d) {
  final total = d.inMinutes;
  final h = total ~/ 60, m = total % 60;
  if (h == 0) return '$m мин';
  if (m == 0) return '$h ч';
  return '$h ч $m мин';
}

/// Комиссия по ставке парка, с округлением до тенге (без float).
int commissionFor(int amount, {int percent = 15}) =>
    (amount * percent + 50) ~/ 100;
