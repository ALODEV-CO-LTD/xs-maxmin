import 'package:flutter/material.dart';

/// MAMBA colours (frontend/src/styles/tokens.css): white background, black text, thin green borders, green accent, no
/// gradients (the customer's design). The app shows the light theme; the dark variant keeps the same green accent.
class Brand {
  static const primaryDark = Color(0xFF22C55E);
  static const primaryLight = Color(0xFF16A34A);
  static const success = Color(0xFF4ADE80);
  static const successLight = Color(0xFF15803D);
  static const danger = Color(0xFFF87171);
  static const dangerLight = Color(0xFFB91C1C);
  static const warning = Color(0xFFFBBF24);
}

ThemeData _build(Brightness b) {
  final dark = b == Brightness.dark;
  final primary = dark ? Brand.primaryDark : Brand.primaryLight;
  final bg = dark ? const Color(0xFF09090B) : Colors.white;
  final card = dark ? const Color(0xFF18181B) : Colors.white;
  final surface = dark ? const Color(0xFF232326) : const Color(0xFFF6FAF7);
  final border = dark ? const Color(0xFF343438) : const Color(0xFFD9E8DD);
  final inputBorder = primary; // thin green outline on every field and outlined button
  final text = dark ? const Color(0xFFFAFAFA) : Colors.black;
  final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: b).copyWith(
    primary: primary,
    onPrimary: dark ? const Color(0xFF052E16) : Colors.white,
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
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    cardTheme: CardThemeData(color: card, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border))),
    appBarTheme: AppBarTheme(backgroundColor: card, foregroundColor: text, elevation: 0, scrolledUnderElevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? surface : card,
      border: ob(inputBorder),
      enabledBorder: ob(inputBorder),
      focusedBorder: ob(primary, 2),
      errorBorder: ob(scheme.error),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      labelStyle: const TextStyle(fontSize: 14),
      hintStyle: const TextStyle(fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 36), textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), side: BorderSide(color: inputBorder), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
    chipTheme: ChipThemeData(shape: const StadiumBorder(), side: BorderSide(color: border)),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: card, indicatorColor: primary.withValues(alpha: dark ? 0.2 : 0.14)),
    dividerTheme: DividerThemeData(color: border),
    // Pop-ups (dropdown lists, menus, dialogs, sheets, date pickers) follow the same palette: white, thin green line, light-green highlight
    // (the Material default is a grey-tinted surface with a grey selected row).
    canvasColor: card,
    focusColor: primary.withValues(alpha: 0.12),
    hoverColor: primary.withValues(alpha: 0.08),
    highlightColor: primary.withValues(alpha: 0.10),
    splashColor: primary.withValues(alpha: 0.12),
    popupMenuTheme: PopupMenuThemeData(color: card, surfaceTintColor: Colors.transparent, elevation: 3, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border))),
    dropdownMenuTheme: DropdownMenuThemeData(menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(card), surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent), shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border))))),
    menuTheme: MenuThemeData(style: MenuStyle(backgroundColor: WidgetStatePropertyAll(card), surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent))),
    dialogTheme: DialogThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: border))),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent, modalBackgroundColor: card, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16)))),
    datePickerTheme: DatePickerThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
    timePickerTheme: TimePickerThemeData(backgroundColor: card),
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
