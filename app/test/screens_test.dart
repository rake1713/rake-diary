import 'dart:convert';

import 'package:driver_diary/api/api_client.dart';
import 'package:driver_diary/api/models.dart';
import 'package:driver_diary/main.dart';
import 'package:driver_diary/screens/add_trip_sheet.dart';
import 'package:driver_diary/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

ApiClient apiFor(FakeServer server) => ApiClient(
  baseUri: Uri.parse('https://example.test/'),
  isWeb: true,
  httpClient: server.client,
);

String text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data ?? '';

Widget sheet(FakeServer server, {DateTime? today, DateTime? now}) =>
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: AddTripSheet(
          api: apiFor(server),
          date: DateTime.utc(2026, 10, 5),
          today: today,
          now: now,
          utcOffset: const Duration(hours: 5),
        ),
      ),
    );

void phone(WidgetTester tester) {
  // Узкий телефон (360 dp): проверяем и вёрстку — ничего не должно вылезать.
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('сводка как в задании и переключение дней (${mode.name})', (
      tester,
    ) async {
      phone(tester);
      final server = FakeServer();
      await tester.pumpWidget(
        DriverDiaryApp(api: apiFor(server), themeMode: mode),
      );
      await tester.pumpAndSettle();

      // Открылся последний день с поездками.
      expect(text(tester, const Key('day-title')), 'ЧТ 01.10');
      expect(text(tester, const Key('net')), '3 315 ₸');
      expect(find.text('3 900 ₸'), findsOneWidget);
      expect(find.text('−585 ₸'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      // Лента смены и показатели.
      expect(find.text('08:10'), findsWidgets);
      expect(find.text('простой 33 мин'), findsOneWidget);
      expect(find.text('37 мин'), findsOneWidget);
      expect(find.text('2\u00A0841\u00A0₸'), findsOneWidget);

      await tester.tap(find.byTooltip('Следующий день'));
      await tester.pumpAndSettle();
      expect(text(tester, const Key('day-title')), 'ПТ 02.10');
      expect(find.text('В этот день поездок нет'), findsOneWidget);
      expect(server.requests.last.url.path, startsWith('/api/days'));

      // Полоса недели: тап по 30 сентября.
      await tester.tap(find.byKey(const Key('week-2026-09-30')));
      await tester.pumpAndSettle();
      expect(text(tester, const Key('day-title')), 'СР 30.09');
    });
  }

  testWidgets('широкий экран: две колонки, кнопка в шапке', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = FakeServer();
    await tester.pumpWidget(
      DriverDiaryApp(api: apiFor(server), themeMode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();

    final net = tester.getRect(find.byKey(const Key('net')));
    final firstTrip = tester.getRect(find.text('08:10').first);
    final add = tester.getRect(find.byKey(const Key('add-trip')));
    // Сводка слева, лента смены справа — рядом, а не друг под другом.
    expect(firstTrip.left, greaterThan(net.right));
    expect(firstTrip.top, lessThan(net.bottom));
    // Кнопка добавления в шапке, а не плашкой внизу.
    expect(add.top, lessThan(100));
    expect(add.width, lessThan(400));
  });

  testWidgets('полоса недели грузит неделю с понедельника', (tester) async {
    phone(tester);
    final server = FakeServer();
    await tester.pumpWidget(
      DriverDiaryApp(api: apiFor(server), themeMode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();
    final week = server.requests.firstWhere(
      (r) => r.url.queryParameters.containsKey('from'),
    );
    expect(week.url.queryParameters, {
      'from': '2026-09-28',
      'to': '2026-10-04',
    });
  });

  testWidgets('свайп влево — следующий день', (tester) async {
    phone(tester);
    final server = FakeServer();
    await tester.pumpWidget(
      DriverDiaryApp(api: apiFor(server), themeMode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byKey(const Key('net')),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(text(tester, const Key('day-title')), 'ПТ 02.10');
  });

  testWidgets('комиссия считается сама, сумма «на руки» на кнопке', (
    tester,
  ) async {
    phone(tester);
    final server = FakeServer();
    await tester.pumpWidget(sheet(server));
    await tester.enterText(find.byKey(const Key('amount')), '2400');
    await tester.pump();
    expect(text(tester, const Key('commission-auto')), '360 ₸');
    expect(find.text('СОХРАНИТЬ · НА РУКИ 2 040 ₸'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pay-cash')));
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    final body = jsonDecode(server.requests.single.body) as Map;
    expect(body['amount'], 2400);
    expect(body['commission'], 360);
    expect(body['payment'], 'cash');
  });

  testWidgets('для сегодняшнего дня время — «только что закончилась»', (
    tester,
  ) async {
    phone(tester);
    final server = FakeServer();
    await tester.pumpWidget(
      sheet(
        server,
        today: DateTime.utc(2026, 10, 5),
        now: DateTime.utc(2026, 10, 5, 14, 37),
      ),
    );
    expect(find.text('14:17'), findsOneWidget);
    expect(find.text('14:37'), findsOneWidget);
    expect(find.text('в пути 20 мин'), findsOneWidget);
  });

  testWidgets('повтор после обрыва связи отправляет тот же id — дубля нет', (
    tester,
  ) async {
    phone(tester);
    final server = FakeServer()..dropNextTripResponses = 1;
    await tester.pumpWidget(sheet(server));
    await tester.enterText(find.byKey(const Key('amount')), '2000');

    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('дубля не будет'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    final posts = server.requests
        .where((r) => r.url.path == '/api/trips')
        .toList();
    expect(posts, hasLength(2));
    final ids = posts.map((r) => (jsonDecode(r.body) as Map)['id']).toSet();
    expect(ids, hasLength(1), reason: 'повтор должен идти с тем же id');
    expect(server.savedIds, hasLength(1));
  });

  testWidgets('форма проверяет сумму и ручную комиссию до отправки', (
    tester,
  ) async {
    phone(tester);
    final server = FakeServer();
    await tester.pumpWidget(sheet(server));
    await tester.enterText(find.byKey(const Key('amount')), '0');
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.text('Сумма должна быть больше нуля'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('amount')), '100');
    await tester.tap(find.byKey(const Key('commission-edit')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('commission')), '500');
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.text('Комиссия больше суммы'), findsOneWidget);
    expect(server.requests, isEmpty);
  });

  test('id поездки случайный и в допустимом для API формате', () {
    final a = newTripId(), b = newTripId();
    expect(a, isNot(b));
    expect(RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(a), isTrue);
  });

  test('Payment.parse отвергает неизвестное значение', () {
    expect(() => Payment.parse('crypto'), throwsFormatException);
  });
}
