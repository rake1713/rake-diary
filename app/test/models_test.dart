import 'package:driver_diary/api/models.dart';
import 'package:driver_diary/format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

void main() {
  test('время показывается по поясу водителя, а не устройства', () {
    final day = Day.fromJson(FakeServer.day1);
    expect(formatTime(day.trips[0].start), '08:10');
    expect(formatTime(day.trips[0].end), '08:32');
    expect(day.trips[1].payment, Payment.cash);
    expect(day.summary.net, 3315);
  });

  test('UTC-время из API переводится в +05:00', () {
    final wall = toDriverWallClock(
      '2026-10-02T19:40:00Z',
      const Duration(hours: 5),
    );
    expect(isoDate(wall), '2026-10-03');
    expect(formatTime(wall), '00:40');
  });

  test('смещение туда и обратно', () {
    expect(parseUtcOffset('+05:00'), const Duration(hours: 5));
    expect(parseUtcOffset('-03:30'), const Duration(hours: -3, minutes: -30));
    expect(formatUtcOffset(const Duration(hours: 5)), '+05:00');
    expect(formatUtcOffset(const Duration(hours: -3, minutes: -30)), '-03:30');
    expect(() => parseUtcOffset('5'), throwsFormatException);
  });

  test('новая поездка сериализуется со смещением водителя', () {
    final trip = NewTrip(
      id: 'm-1',
      start: DateTime.utc(2026, 10, 2, 23, 50),
      end: DateTime.utc(2026, 10, 3, 0, 15),
      amount: 2600,
      payment: Payment.cash,
      commission: 390,
      utcOffset: const Duration(hours: 5),
    );
    expect(trip.toJson(), {
      'id': 'm-1',
      'start': '2026-10-02T23:50:00+05:00',
      'end': '2026-10-03T00:15:00+05:00',
      'amount': 2600,
      'payment': 'cash',
      'commission': 390,
    });
  });
}
