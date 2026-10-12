import 'dart:convert';

import 'package:driver_diary/api/api_client.dart';
import 'package:driver_diary/api/models.dart';
import 'package:driver_diary/api/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

final _driver = {'login': 'demo', 'name': 'Демо', 'utc_offset': '+05:00'};

NewTrip _trip() => NewTrip(
  id: 'm-1',
  start: DateTime.utc(2026, 10, 5, 10),
  end: DateTime.utc(2026, 10, 5, 10, 20),
  amount: 1000,
  payment: Payment.card,
  commission: 150,
  utcOffset: const Duration(hours: 5),
);

void main() {
  final base = Uri.parse('https://example.test/');

  test('мобилка: токен сохраняется и уходит в Authorization', () async {
    final seen = <http.BaseRequest>[];
    final tokens = MemoryTokenStore();
    final api = ApiClient(
      baseUri: base,
      isWeb: false,
      tokens: tokens,
      httpClient: MockClient((r) async {
        seen.add(r);
        if (r.url.path == '/api/auth/login') {
          return json({
            'driver': _driver,
            'token': 'secret-token',
            'expires_in': 1,
          });
        }
        return json(_driver);
      }),
    );
    await api.login('demo', 'demo12345');
    expect(await tokens.read(), 'secret-token');
    await api.me();
    expect(seen[0].headers['X-Client'], 'mobile');
    expect(seen[1].headers['Authorization'], 'Bearer secret-token');
  });

  test(
    'веб: токен не хранится, есть CSRF-заголовок, нет Authorization',
    () async {
      final seen = <http.BaseRequest>[];
      final tokens = MemoryTokenStore();
      final api = ApiClient(
        baseUri: base,
        isWeb: true,
        tokens: tokens,
        httpClient: MockClient((r) async {
          seen.add(r);
          return json({'driver': _driver, 'token': null, 'expires_in': 1});
        }),
      );
      await api.login('demo', 'demo12345');
      expect(await tokens.read(), isNull);
      expect(seen.single.headers['X-Requested-With'], 'diary-web');
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
    },
  );

  test('201 — создана, 200 — уже была, 409 — конфликт', () async {
    var status = 201;
    final api = ApiClient(
      baseUri: base,
      isWeb: false,
      httpClient: MockClient(
        (r) async => status == 409
            ? json({
                'error': 'trip_conflict',
                'message': 'Поездка уже сохранена',
              }, 409)
            : json({'id': 'm-1'}, status),
      ),
    );
    expect(await api.addTrip(_trip()), SaveOutcome.created);
    status = 200;
    expect(await api.addTrip(_trip()), SaveOutcome.alreadySaved);
    status = 409;
    await expectLater(
      api.addTrip(_trip()),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'trip_conflict'),
      ),
    );
  });

  test('ошибки валидации доходят до пользователя', () async {
    final api = ApiClient(
      baseUri: base,
      isWeb: false,
      httpClient: MockClient(
        (r) async => json({
          'error': 'validation_error',
          'message': 'Данные не прошли проверку',
          'details': [
            {
              'field': null,
              'message': 'окончание поездки должно быть позже начала',
            },
          ],
        }, 422),
      ),
    );
    await expectLater(
      api.addTrip(_trip()),
      throwsA(
        isA<ApiException>().having(
          (e) => e.toString(),
          'text',
          contains('окончание поездки должно быть позже начала'),
        ),
      ),
    );
  });

  test('обрыв связи — ApiException с isNetwork', () async {
    final api = ApiClient(
      baseUri: base,
      isWeb: false,
      httpClient: MockClient((r) async => throw http.ClientException('reset')),
    );
    await expectLater(
      api.day('2026-10-01'),
      throwsA(
        isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true),
      ),
    );
  });

  test('истёкшая сессия: me() возвращает null и стирает токен', () async {
    final tokens = MemoryTokenStore();
    await tokens.write('old');
    final api = ApiClient(
      baseUri: base,
      isWeb: false,
      tokens: tokens,
      httpClient: MockClient(
        (r) async => json({'error': 'unauthorized', 'message': 'x'}, 401),
      ),
    );
    expect(await api.me(), isNull);
    expect(await tokens.read(), isNull);
  });

  test('не-JSON ответ (например, от прокси) не роняет клиента', () async {
    final api = ApiClient(
      baseUri: base,
      isWeb: false,
      httpClient: MockClient(
        (r) async => http.Response('<html>502</html>', 502),
      ),
    );
    await expectLater(
      api.days(),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 502)),
    );
  });
}
