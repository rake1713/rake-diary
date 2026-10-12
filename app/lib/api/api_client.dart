import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'token_store.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.details = const []]);

  /// 0 — нет связи с сервером.
  final int status;
  final String code;
  final String message;
  final List<String> details;

  bool get isUnauthorized => status == 401;
  bool get isNetwork => status == 0;

  @override
  String toString() =>
      details.isEmpty ? message : '$message: ${details.join('; ')}';
}

enum SaveOutcome { created, alreadySaved }

/// Клиент API.
///
/// Веб: сессия в HttpOnly-cookie (браузер шлёт её сам), а на изменяющие запросы
/// добавляем заголовок X-Requested-With — защита от CSRF.
/// Мобилка: токен в заголовке Authorization, хранится в [TokenStore].
class ApiClient {
  ApiClient({
    required this.baseUri,
    required this.isWeb,
    http.Client? httpClient,
    TokenStore? tokens,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client(),
       _tokens = tokens ?? MemoryTokenStore();

  final Uri baseUri;
  final bool isWeb;
  final Duration timeout;
  final http.Client _http;
  final TokenStore _tokens;

  Uri _uri(String path) => baseUri.resolve(path);

  Future<Map<String, String>> _headers({bool json = false}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (json) headers['Content-Type'] = 'application/json';
    if (isWeb) {
      headers['X-Requested-With'] = 'diary-web';
    } else {
      headers['X-Client'] = 'mobile';
      final token = await _tokens.read();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final request = http.Request(method, _uri(path))
      ..headers.addAll(await _headers(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    try {
      final streamed = await _http.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'Сервер не отвечает');
    } on http.ClientException {
      throw ApiException(0, 'network', 'Нет связи с сервером');
    }
  }

  Never _fail(http.Response r) {
    try {
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final details = [
        for (final d in (body['details'] as List? ?? const []))
          (d as Map<String, dynamic>)['message'] as String,
      ];
      throw ApiException(
        r.statusCode,
        body['error'] as String? ?? 'error',
        body['message'] as String? ?? 'Ошибка ${r.statusCode}',
        details,
      );
    } on FormatException {
      throw ApiException(
        r.statusCode,
        'error',
        'Ошибка сервера (${r.statusCode})',
      );
    } on TypeError {
      throw ApiException(
        r.statusCode,
        'error',
        'Ошибка сервера (${r.statusCode})',
      );
    }
  }

  dynamic _json(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes));

  Future<Driver> login(String login, String password) async {
    final r = await _send(
      'POST',
      'api/auth/login',
      body: {'login': login, 'password': password},
    );
    if (r.statusCode != 200) _fail(r);
    final body = _json(r) as Map<String, dynamic>;
    final token = body['token'] as String?;
    if (!isWeb && token != null) await _tokens.write(token);
    return Driver.fromJson(body['driver'] as Map<String, dynamic>);
  }

  /// Восстановление сессии при запуске. null — нужно войти.
  Future<Driver?> me() async {
    if (!isWeb && await _tokens.read() == null) return null;
    final r = await _send('GET', 'api/auth/me');
    if (r.statusCode == 401) {
      await _tokens.clear();
      return null;
    }
    if (r.statusCode != 200) _fail(r);
    return Driver.fromJson(_json(r) as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await _send('POST', 'api/auth/logout');
    } on ApiException {
      // Локально выходим в любом случае.
    } finally {
      await _tokens.clear();
    }
  }

  /// Дни с поездками. С [from]/[to] (ГГГГ-ММ-ДД) — за период, иначе последние.
  Future<List<DayWithTrips>> days({String? from, String? to}) async {
    final query = from != null && to != null ? '?from=$from&to=$to' : '';
    final r = await _send('GET', 'api/days$query');
    if (r.statusCode != 200) _fail(r);
    return [
      for (final d in _json(r) as List)
        DayWithTrips(
          (d as Map<String, dynamic>)['date'] as String,
          d['trips'] as int,
          d['net'] as int,
        ),
    ];
  }

  Future<Day> day(String date) async {
    final r = await _send('GET', 'api/days/$date');
    if (r.statusCode != 200) _fail(r);
    return Day.fromJson(_json(r) as Map<String, dynamic>);
  }

  /// 201 — создана, 200 — такая поездка уже была (повторная отправка), 409 — конфликт.
  Future<SaveOutcome> addTrip(NewTrip trip) async {
    final r = await _send('POST', 'api/trips', body: trip.toJson());
    if (r.statusCode == 201) return SaveOutcome.created;
    if (r.statusCode == 200) return SaveOutcome.alreadySaved;
    _fail(r);
  }
}
