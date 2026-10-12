/// Модели ответа API. Деньги — целые тенге, время — с явным смещением водителя.
library;

enum Payment {
  cash('cash', 'нал.'),
  card('card', 'карта');

  const Payment(this.wire, this.label);
  final String wire;
  final String label;

  static Payment parse(String value) => Payment.values.firstWhere(
    (p) => p.wire == value,
    orElse: () => throw FormatException('Неизвестный способ оплаты: $value'),
  );
}

/// Смещение вида "+05:00" → Duration.
Duration parseUtcOffset(String raw) {
  final m = RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(raw);
  if (m == null) throw FormatException('Неверное смещение: $raw');
  final d = Duration(hours: int.parse(m[2]!), minutes: int.parse(m[3]!));
  return m[1] == '-' ? -d : d;
}

String formatUtcOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final h = abs.inHours.toString().padLeft(2, '0');
  final m = (abs.inMinutes % 60).toString().padLeft(2, '0');
  return '$sign$h:$m';
}

/// Местное время водителя. Не используем часовой пояс устройства:
/// телефон может быть в другом поясе, а день считается по поясу водителя.
DateTime toDriverWallClock(String iso, Duration offset) =>
    DateTime.parse(iso).toUtc().add(offset);

class Trip {
  const Trip({
    required this.id,
    required this.start,
    required this.end,
    required this.amount,
    required this.payment,
    required this.commission,
  });

  final String id;

  /// Время по часам водителя (объект в UTC, но показывает местные часы).
  final DateTime start;
  final DateTime end;
  final int amount;
  final Payment payment;
  final int commission;

  factory Trip.fromJson(Map<String, dynamic> json, Duration offset) => Trip(
    id: json['id'] as String,
    start: toDriverWallClock(json['start'] as String, offset),
    end: toDriverWallClock(json['end'] as String, offset),
    amount: json['amount'] as int,
    payment: Payment.parse(json['payment'] as String),
    commission: json['commission'] as int,
  );
}

class DaySummary {
  const DaySummary({
    required this.trips,
    required this.revenue,
    required this.commission,
    required this.net,
    required this.cash,
    required this.card,
  });

  final int trips;
  final int revenue;
  final int commission;
  final int net;
  final int cash;
  final int card;

  factory DaySummary.fromJson(Map<String, dynamic> json) => DaySummary(
    trips: json['trips'] as int,
    revenue: json['revenue'] as int,
    commission: json['commission'] as int,
    net: json['net'] as int,
    cash: json['cash'] as int,
    card: json['card'] as int,
  );
}

class Day {
  const Day({required this.date, required this.summary, required this.trips});

  final String date;
  final DaySummary summary;
  final List<Trip> trips;

  factory Day.fromJson(Map<String, dynamic> json) {
    final offset = parseUtcOffset(json['utc_offset'] as String);
    return Day(
      date: json['date'] as String,
      summary: DaySummary.fromJson(json['summary'] as Map<String, dynamic>),
      trips: [
        for (final t in json['trips'] as List)
          Trip.fromJson(t as Map<String, dynamic>, offset),
      ],
    );
  }
}

/// Итог дня для полосы недели.
class DayWithTrips {
  const DayWithTrips(this.date, this.trips, this.net);
  final String date;
  final int trips;
  final int net;
}

class Driver {
  const Driver({
    required this.login,
    required this.name,
    required this.utcOffset,
  });

  final String login;
  final String name;
  final Duration utcOffset;

  factory Driver.fromJson(Map<String, dynamic> json) => Driver(
    login: json['login'] as String,
    name: json['name'] as String,
    utcOffset: parseUtcOffset(json['utc_offset'] as String),
  );
}

/// Новая поездка. id создаётся один раз при открытии формы, поэтому повторная
/// отправка после обрыва связи не создаст дубль: сервер узнает тот же id.
class NewTrip {
  const NewTrip({
    required this.id,
    required this.start,
    required this.end,
    required this.amount,
    required this.payment,
    required this.commission,
    required this.utcOffset,
  });

  final String id;

  /// Время по часам водителя.
  final DateTime start;
  final DateTime end;
  final int amount;
  final Payment payment;
  final int commission;
  final Duration utcOffset;

  Map<String, dynamic> toJson() => {
    'id': id,
    'start': _iso(start),
    'end': _iso(end),
    'amount': amount,
    'payment': payment.wire,
    'commission': commission,
  };

  String _iso(DateTime wall) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${wall.year}-${two(wall.month)}-${two(wall.day)}'
        'T${two(wall.hour)}:${two(wall.minute)}:00${formatUtcOffset(utcOffset)}';
  }
}
