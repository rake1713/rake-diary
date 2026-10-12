import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Мини-сервер для тестов клиента: два дня из примера и запись запросов.
class FakeServer {
  final requests = <http.Request>[];
  final savedIds = <String>{};

  /// Сколько следующих POST /api/trips «потерять» (сервер сохранил, ответ не дошёл).
  int dropNextTripResponses = 0;

  static const day1 = {
    'date': '2026-10-01',
    'utc_offset': '+05:00',
    'summary': {
      'trips': 2,
      'revenue': 3900,
      'commission': 585,
      'net': 3315,
      'cash': 1500,
      'card': 2400,
    },
    'trips': [
      {
        'id': 't1',
        'start': '2026-10-01T08:10:00+05:00',
        'end': '2026-10-01T08:32:00+05:00',
        'amount': 2400,
        'payment': 'card',
        'commission': 360,
      },
      {
        'id': 't2',
        'start': '2026-10-01T09:05:00+05:00',
        'end': '2026-10-01T09:20:00+05:00',
        'amount': 1500,
        'payment': 'cash',
        'commission': 225,
      },
    ],
  };

  static Map<String, dynamic> emptyDay(String date) => {
    'date': date,
    'utc_offset': '+05:00',
    'summary': {
      'trips': 0,
      'revenue': 0,
      'commission': 0,
      'net': 0,
      'cash': 0,
      'card': 0,
    },
    'trips': <Object>[],
  };

  http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/api/auth/me') {
      return _json({'login': 'demo', 'name': 'Демо', 'utc_offset': '+05:00'});
    }
    if (path == '/api/days') {
      return _json([
        {'date': '2026-10-01', 'trips': 2, 'net': 3315},
      ]);
    }
    if (path == '/api/days/2026-10-01') return _json(day1);
    if (path.startsWith('/api/days/')) {
      return _json(emptyDay(path.split('/').last));
    }
    if (path == '/api/trips' && request.method == 'POST') {
      final id = (jsonDecode(request.body) as Map)['id'] as String;
      final isNew = savedIds.add(id);
      if (dropNextTripResponses > 0) {
        dropNextTripResponses--;
        throw http.ClientException('Connection reset');
      }
      return _json({'id': id}, isNew ? 201 : 200);
    }
    return _json({'error': 'not_found', 'message': 'нет'}, 404);
  });
}
