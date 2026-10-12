import 'package:driver_diary/api/models.dart';
import 'package:driver_diary/shift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

void main() {
  final day = Day.fromJson(FakeServer.day1);

  test('смена: с начала первой до конца последней поездки', () {
    final s = ShiftStats.of(day.trips, day.summary.net)!;
    expect(s.duration, const Duration(minutes: 70)); // 08:10–09:20
    expect(s.driving, const Duration(minutes: 37)); // 22 + 15 мин в пути
    // 3 315 ₸ за 70 минут = 2 841,4 ₸/ч → 2 841.
    expect(s.netPerHour, 2841);
  });

  test('смена короче часа — без заработка в час', () {
    final short = [day.trips.first]; // 08:10–08:32, 22 минуты
    final s = ShiftStats.of(short, 1615)!;
    expect(s.duration, const Duration(minutes: 22));
    expect(s.netPerHour, isNull);
  });

  test('нет поездок — нет смены', () {
    expect(ShiftStats.of(const [], 0), isNull);
  });

  test('простой между поездками', () {
    expect(idleBefore(day.trips, 0), isNull);
    expect(
      idleBefore(day.trips, 1),
      const Duration(minutes: 33),
    ); // 08:32 → 09:05
  });

  test('длительность словами', () {
    expect(formatDuration(const Duration(minutes: 45)), '45 мин');
    expect(formatDuration(const Duration(minutes: 70)), '1 ч 10 мин');
    expect(formatDuration(const Duration(minutes: 120)), '2 ч');
  });

  test('комиссия 15% как в данных задания, целыми тенге', () {
    expect(commissionFor(2400), 360);
    expect(commissionFor(1500), 225);
    expect(commissionFor(1001), 150); // 150,15 → 150
    expect(commissionFor(1003), 150); // 150,45 → 150
    expect(commissionFor(1004), 151); // 150,6 → 151
    expect(commissionFor(0), 0);
  });
}
