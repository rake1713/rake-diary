import 'package:flutter/foundation.dart';

/// Адрес API.
/// Веб: тот же домен, с которого открыт сайт (cookie и CSP работают без CORS).
/// Мобилка: задаётся при сборке, `--dart-define=API_BASE_URL=...`.
Uri apiBaseUri() {
  if (kIsWeb) {
    final b = Uri.base;
    return Uri(scheme: b.scheme, host: b.host, port: b.port, path: '/');
  }
  const url = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://rake-diary.duckdns.org/',
  );
  final uri = Uri.parse(url.endsWith('/') ? url : '$url/');
  // В релизе токен по открытому http не отправляем.
  if (kReleaseMode && uri.scheme != 'https') {
    throw StateError('В релизной сборке API_BASE_URL должен быть https');
  }
  return uri;
}

/// Подсказка с демо-аккаунтом на экране входа.
const showDemoHint = bool.fromEnvironment('SHOW_DEMO_HINT', defaultValue: true);
