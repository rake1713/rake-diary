/// Форматирование для экрана. Без intl: нужно всего несколько форматов.
library;

const _nbsp = ' ';

/// 2400 → "2 400 ₸", -585 → "−585 ₸".
String formatMoney(int value, {bool signed = false}) {
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(_nbsp);
    buf.write(digits[i]);
  }
  final sign = value < 0 || (signed && value > 0) ? '−' : '';
  return '$sign$buf$_nbsp₸';
}

String _two(int v) => v.toString().padLeft(2, '0');

String formatTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// DateTime → "2026-10-01" (по календарной дате объекта, без пересчёта поясов).
String isoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime parseIsoDate(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];
const _monthsShort = [
  'янв',
  'фев',
  'мар',
  'апр',
  'мая',
  'июн',
  'июл',
  'авг',
  'сен',
  'окт',
  'ноя',
  'дек',
];
const _weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

/// "1 октября, чт".
String formatDayLong(DateTime d) =>
    '${d.day} ${_months[d.month - 1]}, ${_weekdays[d.weekday - 1]}';

/// "1 октября".
String formatDayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// "01.10.2026".
String formatDayNumeric(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year}';

/// "1 окт".
String formatDayShort(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

/// "2 поездки", "5 поездок".
String pluralTrips(int n) {
  final mod10 = n % 10, mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n поездка';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$n поездки';
  }
  return '$n поездок';
}
