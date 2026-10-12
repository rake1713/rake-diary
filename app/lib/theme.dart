import 'package:flutter/material.dart';

/// Палитра «приборной панели»: графит, янтарный акцент как у табло таксометра,
/// отдельные цвета для наличных и карты. Тёмная тема основная (ночные смены),
/// светлая — та же логика для яркого солнца.
@immutable
class Dash extends ThemeExtension<Dash> {
  const Dash({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.cash,
    required this.card,
    required this.negative,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color text;
  final Color muted;

  /// Заливка главной кнопки и выделения.
  final Color accent;
  final Color onAccent;

  /// Акцентный цвет для текста на фоне (на светлой теме темнее, чтобы читался).
  final Color accentText;
  final Color cash;
  final Color card;
  final Color negative;

  static const dark = Dash(
    bg: Color(0xFF0D0E10),
    surface: Color(0xFF16181B),
    surface2: Color(0xFF1F2226),
    line: Color(0xFF2B2F35),
    text: Color(0xFFF3F1EA),
    muted: Color(0xFF8D929A),
    accent: Color(0xFFFFB81C),
    onAccent: Color(0xFF15120A),
    accentText: Color(0xFFFFC23D),
    cash: Color(0xFF9AD872),
    card: Color(0xFF8FB8FF),
    negative: Color(0xFFFF7A6B),
  );

  static const light = Dash(
    bg: Color(0xFFF3F1EB),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEAE7DF),
    line: Color(0xFFD9D5CB),
    text: Color(0xFF121316),
    muted: Color(0xFF666A71),
    accent: Color(0xFFFFB81C),
    onAccent: Color(0xFF15120A),
    accentText: Color(0xFF8A5A00),
    cash: Color(0xFF3B8A2F),
    card: Color(0xFF2C5FC4),
    negative: Color(0xFFC23B2B),
  );

  static Dash of(BuildContext context) => Theme.of(context).extension<Dash>()!;

  @override
  Dash copyWith() => this;

  @override
  Dash lerp(Dash? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Dash(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      line: l(line, other.line),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentText: l(accentText, other.accentText),
      cash: l(cash, other.cash),
      card: l(card, other.card),
      negative: l(negative, other.negative),
    );
  }
}

/// Шрифты переменные (одна гарнитура — все начертания), поэтому толщину
/// задаём и через fontWeight, и через ось wght: иначе не на всех платформах
/// она применится.
TextStyle _weighted(TextStyle s, FontWeight w) => s.copyWith(
  fontWeight: w,
  fontVariations: [FontVariation('wght', w.value.toDouble())],
);

/// Время — моноширинным JetBrains Mono, как на табло таксометра.
TextStyle clock(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color? color,
}) => _weighted(
  TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: size,
    color: color,
    height: 1.1,
    letterSpacing: -0.02 * size,
  ),
  weight,
);

/// Деньги и количества — Onest с табличными цифрами: суммы не «прыгают»
/// по ширине при переключении дней, а пробелы между разрядами остаются узкими
/// (в моноширинном шрифте пробел шириной с цифру и «1 615 ₸» разваливается).
TextStyle figures(
  double size, {
  FontWeight weight = FontWeight.w600,
  Color? color,
}) => _weighted(
  TextStyle(
    fontFamily: 'Onest',
    fontSize: size,
    color: color,
    height: 1.1,
    letterSpacing: -0.01 * size,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
  weight,
);

TextStyle ui(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? letterSpacing,
}) => _weighted(
  TextStyle(
    fontFamily: 'Onest',
    fontSize: size,
    color: color,
    letterSpacing: letterSpacing,
  ),
  weight,
);

/// Подпись капсом над значением: «НА РУКИ», «СМЕНА».
TextStyle caps(Color color) =>
    ui(12, weight: FontWeight.w600, color: color, letterSpacing: 1.4);

ThemeData buildTheme(Brightness brightness) {
  final d = brightness == Brightness.dark ? Dash.dark : Dash.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: d.accent,
    onPrimary: d.onAccent,
    secondary: d.accentText,
    onSecondary: d.onAccent,
    error: d.negative,
    onError: d.bg,
    surface: d.surface,
    onSurface: d.text,
    surfaceContainerHighest: d.surface2,
    surfaceContainerHigh: d.surface2,
    surfaceContainer: d.surface,
    surfaceContainerLow: d.surface,
    onSurfaceVariant: d.muted,
    outline: d.line,
    outlineVariant: d.line,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  final text = base.textTheme.apply(
    fontFamily: 'Onest',
    bodyColor: d.text,
    displayColor: d.text,
  );
  final radius = BorderRadius.circular(16);
  return base.copyWith(
    scaffoldBackgroundColor: d.bg,
    extensions: [d],
    textTheme: text.copyWith(
      bodyLarge: _weighted(text.bodyLarge!, FontWeight.w400),
      bodyMedium: _weighted(text.bodyMedium!, FontWeight.w400),
      titleMedium: _weighted(text.titleMedium!, FontWeight.w600),
      titleLarge: _weighted(text.titleLarge!, FontWeight.w700),
      labelLarge: _weighted(text.labelLarge!, FontWeight.w600),
    ),
    splashFactory: InkSparkle.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: d.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: ui(15, color: d.muted),
      hintStyle: ui(15, color: d.muted),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: d.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: d.negative, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: d.negative, width: 2),
      ),
      errorStyle: ui(13, color: d.negative),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: d.accent,
        foregroundColor: d.onAccent,
        disabledBackgroundColor: d.surface2,
        minimumSize: const Size.fromHeight(64),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: ui(17, weight: FontWeight.w700, letterSpacing: 0.6),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: d.accentText,
        textStyle: ui(15, weight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: d.text,
        minimumSize: const Size(48, 48),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: d.text,
      contentTextStyle: ui(15, weight: FontWeight.w500, color: d.bg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: d.surface,
      showDragHandle: true,
      dragHandleColor: d.line,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: d.accent),
    dividerTheme: DividerThemeData(color: d.line, thickness: 1, space: 1),
  );
}
