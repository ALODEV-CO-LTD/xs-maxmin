import 'package:flutter/material.dart';

/// MAMBA colours (frontend/src/styles/tokens.css): dark by default, with the light variant.
class Brand {
  static const primaryDark = Color(0xFF8B5CF6);
  static const primaryLight = Color(0xFF7C3AED);
  static const gold = Color(0xFFD4AF37);
  static const success = Color(0xFF4ADE80);
  static const successLight = Color(0xFF15803D);
  static const danger = Color(0xFFF87171);
  static const dangerLight = Color(0xFFB91C1C);
  static const warning = Color(0xFFFBBF24);
}

ThemeData _build(Brightness b) {
  final dark = b == Brightness.dark;
  final primary = dark ? Brand.primaryDark : Brand.primaryLight;
  final bg = dark ? const Color(0xFF09090B) : const Color(0xFFF8FAFC);
  final card = dark ? const Color(0xFF18181B) : Colors.white;
  final surface = dark ? const Color(0xFF232326) : const Color(0xFFF1F5F9);
  final border = dark ? const Color(0xFF343438) : const Color(0xFFE2E8F0);
  final inputBorder = dark ? const Color(0xFF71717A) : const Color(0xFF7C889B);
  final text = dark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B);
  final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: b).copyWith(
    primary: primary,
    onPrimary: Colors.white,
    surface: card,
    onSurface: text,
    surfaceContainerHighest: surface,
    outline: inputBorder,
    outlineVariant: border,
    error: dark ? Brand.danger : Brand.dangerLight,
  );
  OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    cardTheme: CardThemeData(color: card, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border))),
    appBarTheme: AppBarTheme(backgroundColor: card, foregroundColor: text, elevation: 0, scrolledUnderElevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: ob(inputBorder),
      enabledBorder: ob(inputBorder),
      focusedBorder: ob(primary, 2),
      errorBorder: ob(scheme.error),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), side: BorderSide(color: inputBorder), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
    chipTheme: ChipThemeData(shape: const StadiumBorder(), side: BorderSide(color: border)),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: card, indicatorColor: primary.withValues(alpha: 0.2)),
    dividerTheme: DividerThemeData(color: border),
  );
}

final ThemeData darkTheme = _build(Brightness.dark);
final ThemeData lightTheme = _build(Brightness.light);

/// Display helpers shared by the screens.
extension BrandColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get okColor => isDark ? Brand.success : Brand.successLight;
  Color get badColor => isDark ? Brand.danger : Brand.dangerLight;
  Color get mutedColor => Theme.of(this).colorScheme.onSurface.withValues(alpha: 0.62);
}
