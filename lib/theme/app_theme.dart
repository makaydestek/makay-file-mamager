import 'package:flutter/material.dart';

/// Makay Dosya Yöneticisi tema tanımları.
/// Referans uygulamanın turkuaz vurgu rengi ve koyu app bar'ı korunur.
class AppTheme {
  AppTheme._();

  /// Referans uygulamadaki turkuaz/teal vurgu rengi.
  static const Color accent = Color(0xFF00897B);
  static const Color accentDark = Color(0xFF26A69A);

  /// Koyu app bar rengi (referans ekranlardaki siyah bar).
  static const Color appBarDark = Color(0xFF212121);

  /// Material You: Android 12+ sistem (dinamik) ana rengi verilirse ondan
  /// palet türetilir; verilmezse turkuaz tohum rengi kullanılır.
  static ThemeData light({Color? dynamicSeed}) =>
      _base(Brightness.light, dynamicSeed);
  static ThemeData dark({Color? dynamicSeed}) =>
      _base(Brightness.dark, dynamicSeed);

  static ThemeData _base(Brightness brightness, Color? dynamicSeed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: dynamicSeed ?? accent,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? appBarDark : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white12 : Colors.black12,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: isDark ? Colors.white70 : Colors.black54,
      ),
      // Odaklanan öğeler belirgin halka alır (TV/D-pad).
      focusColor: isDark ? Colors.white24 : accent.withValues(alpha: 0.12),
      hoverColor: isDark ? Colors.white10 : accent.withValues(alpha: 0.08),
      highlightColor: isDark ? Colors.white10 : accent.withValues(alpha: 0.08),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : (isDark ? Colors.white54 : Colors.grey.shade400),
        ),
      ),
    );
  }
}
