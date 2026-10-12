import 'package:driver_diary/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('деньги с разделителем тысяч и знаком', () {
    expect(formatMoney(2400), '2 400 ₸');
    expect(formatMoney(3315), '3 315 ₸');
    expect(formatMoney(-585), '−585 ₸');
    expect(formatMoney(0), '0 ₸');
    expect(formatMoney(1234567), '1 234 567 ₸');
  });

  test('склонение «поездка»', () {
    expect(pluralTrips(1), '1 поездка');
    expect(pluralTrips(2), '2 поездки');
    expect(pluralTrips(5), '5 поездок');
    expect(pluralTrips(11), '11 поездок');
    expect(pluralTrips(12), '12 поездок');
    expect(pluralTrips(21), '21 поездка');
    expect(pluralTrips(24), '24 поездки');
  });

  test('даты', () {
    final d = parseIsoDate('2026-10-01');
    expect(isoDate(d), '2026-10-01');
    expect(formatDayLong(d), '1 октября, чт');
    expect(formatDayNumeric(d), '01.10.2026');
    expect(isoDate(d.add(const Duration(days: 31))), '2026-11-01');
  });
}
