import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets/checker.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.onLoggedIn});

  final ApiClient api;
  final ValueChanged<Driver> onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final driver = await widget.api.login(_login.text.trim(), _password.text);
      widget.onLoggedIn(driver);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillDemo() {
    _login.text = 'demo';
    _password.text = 'demo12345';
  }

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CheckerStrip(color: d.accent, cell: 12),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Дневник\nсмен',
                        style: ui(
                          44,
                          weight: FontWeight.w800,
                          color: d.text,
                        ).copyWith(height: 1.0),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Поездки, выручка и «на руки» за каждый день',
                        style: ui(16, color: d.muted),
                      ),
                      const SizedBox(height: 36),
                      TextFormField(
                        controller: _login,
                        decoration: const InputDecoration(labelText: 'Логин'),
                        style: ui(17, weight: FontWeight.w500, color: d.text),
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Введите логин'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        style: ui(17, weight: FontWeight.w500, color: d.text),
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Показать пароль'
                                : 'Скрыть пароль',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: d.muted,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Введите пароль' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(_error!, style: ui(14, color: d.negative)),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: d.onAccent,
                                ),
                              )
                            : const Text('ВОЙТИ'),
                      ),
                      if (showDemoHint) ...[
                        const SizedBox(height: 18),
                        Center(
                          child: TextButton(
                            key: const Key('demo-fill'),
                            onPressed: _fillDemo,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Демо-аккаунт  ',
                                    style: ui(14, color: d.muted),
                                  ),
                                  TextSpan(
                                    text: 'demo / demo12345',
                                    style: clock(
                                      14,
                                      weight: FontWeight.w600,
                                      color: d.accentText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
