import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/api_client.dart';
import 'api/models.dart';
import 'api/token_store.dart';
import 'config.dart';
import 'screens/diary_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

void main() {
  final api = ApiClient(
    baseUri: apiBaseUri(),
    isWeb: kIsWeb,
    tokens: kIsWeb ? null : SecureTokenStore(),
  );
  runApp(DriverDiaryApp(api: api));
}

class DriverDiaryApp extends StatelessWidget {
  const DriverDiaryApp({
    super.key,
    required this.api,
    this.themeMode = ThemeMode.system,
  });

  final ApiClient api;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Дневник смен',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Тёмная тема — основная (ночные смены); светлая — если так в системе.
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      home: AuthGate(api: api),
    );
  }
}

/// При запуске проверяет сессию и показывает вход или дневник.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.api});

  final ApiClient api;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Driver? _driver;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    Driver? driver;
    try {
      driver = await widget.api.me();
    } on ApiException {
      driver = null;
    }
    if (!mounted) return;
    setState(() {
      _driver = driver;
      _checking = false;
    });
  }

  void _onLoggedIn(Driver d) => setState(() => _driver = d);

  Future<void> _onLogout() async {
    await widget.api.logout();
    if (mounted) setState(() => _driver = null);
  }

  void _onSessionExpired() => setState(() => _driver = null);

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final driver = _driver;
    if (driver == null) {
      return LoginScreen(api: widget.api, onLoggedIn: _onLoggedIn);
    }
    return DiaryScreen(
      api: widget.api,
      driver: driver,
      onLogout: _onLogout,
      onSessionExpired: _onSessionExpired,
    );
  }
}
