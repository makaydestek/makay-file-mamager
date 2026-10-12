import 'package:flutter/material.dart';

import 'app_appearance.dart';

/// Makay Dosya Yöneticisi tema tanımları.
/// Referans uygulamanın turkuaz vurgu rengi ve koyu app bar'ı korunur.
///
/// Tema iki boyutta kurulur:
/// • **Tema** (açık/koyu/sistem) → aydınlık/karanlık,
/// • **Görünüm** ([AppAppearance]) → yazı, ikon, köşe, doygunluk ve arka plan.
///
/// [appearance] varsayılanı [AppAppearance.klasik]'tir; yani görünüme
/// dokunulmayan hiçbir kod mevcut görünümü değiştirmez.
class AppTheme {
  AppTheme._();

  /// Referans uygulamadaki turkuaz/teal vurgu rengi.
  static const Color accent = Color(0xFF00897B);
  static const Color accentDark = Color(0xFF26A69A);

  /// Koyu app bar rengi (referans ekranlardaki siyah bar).
  static const Color appBarDark = Color(0xFF212121);

  /// Material You: Android 12+ sistem (dinamik) ana rengi verilirse ondan
  /// palet türetilir; verilmezse görünümün kendi tohum rengi kullanılır.
  ///
  /// Not: dinamik renk yalnız **Klasik** görünümde dikkate alınır; diğer
  /// görünümlerin tarzı ezilmesin diye (bkz. [AppAppearance.honorsDynamicSeed]).
  static ThemeData light({
    Color? dynamicSeed,
    AppAppearance appearance = AppAppearance.klasik,
  }) =>
      _base(Brightness.light, dynamicSeed, appearance);

  static ThemeData dark({
    Color? dynamicSeed,
    AppAppearance appearance = AppAppearance.klasik,
  }) =>
      _base(Brightness.dark, dynamicSeed, appearance);

  /// Önizleme/diyaloglar için hazır tema (aydınlık ya da karanlık).
  static ThemeData forAppearance(AppAppearance appearance, Brightness brightness) =>
      brightness == Brightness.dark ? dark(appearance: appearance) : light(appearance: appearance);

  /// Ana ekran arka planı için gradyan; `null` = düz zemin (bkz.
  /// [AppAppearance.backgroundGradient]).
  static LinearGradient? backgroundGradient(
    AppAppearance appearance,
    Brightness brightness,
  ) =>
      appearance.backgroundGradient(brightness);

  static ThemeData _base(
    Brightness brightness,
    Color? dynamicSeed,
    AppAppearance appearance,
  ) {
    final scheme = appearance.scheme(brightness, dynamicSeed: dynamicSeed);
    final isDark = brightness == Brightness.dark;
    final radius = BorderRadius.circular(appearance.cornerRadius);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: appearance.scaffoldColor(brightness),
      // Yazı ailesi `_textTheme` içinde uygulanır (bkz. oradaki not).
      // Görünümün tipografisi: boyut katsayısı + harf/satır aralığı.
      textTheme: _textTheme(brightness, appearance),
      iconTheme: IconThemeData(
        color: isDark ? Colors.white70 : Colors.black54,
        fill: appearance.iconTheme.fill,
        weight: appearance.iconTheme.weight,
        opticalSize: appearance.iconTheme.opticalSize,
        size: appearance.iconTheme.size,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? appBarDark : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          // Boyut artışını `textScaler` üstlenir (bkz. main.dart).
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: appearance.letterSpacing,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radius),
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
      // Odaklanan öğeler belirgin halka alır (TV/D-pad). Renk paletten
      // alınır: görünüm değiştikçe vurgu rengi de ona uyar.
      focusColor: scheme.primary.withValues(alpha: isDark ? 0.24 : 0.12),
      hoverColor: scheme.primary.withValues(alpha: isDark ? 0.10 : 0.08),
      highlightColor: scheme.primary.withValues(alpha: isDark ? 0.10 : 0.08),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(appearance.buttonRadius),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : (isDark ? Colors.white54 : Colors.grey.shade400),
        ),
      ),
    );
  }

  /// Gövde tipografisi: platform varsayılanı üzerine görünümün katsayısı,
  /// harf aralığı ve satır yüksekliği uygulanır.
  static TextTheme _textTheme(Brightness brightness, AppAppearance appearance) {
    var base = ThemeData(brightness: brightness).textTheme;
    // Gövde yazı ailesi (ör. monospace): `ThemeData.fontFamily` bu sürümde
    // açıkça verilen textTheme'ü geçersiz kılmıyor; aile burada uygulanır.
    final font = appearance.fontFamily;
    if (font != null) base = base.apply(fontFamily: font);
    // Not: yazı **boyutu** buraya işlenmez — bu sürümde fontSize'lar
    // ThemeData'da taşınmadığı için artış, `MaterialApp.builder` içindeki
    // `MediaQuery.textScaler` ile uygulanır (bkz. main.dart).
    TextStyle? tweak(TextStyle? style) {
      if (style == null) return null;
      return style.copyWith(
        letterSpacing:
            (style.letterSpacing ?? 0) + appearance.letterSpacing,
        height: style.height == null
            ? null
            : style.height! + appearance.lineHeightDelta,
      );
    }

    return TextTheme(
      displayLarge: tweak(base.displayLarge),
      displayMedium: tweak(base.displayMedium),
      displaySmall: tweak(base.displaySmall),
      headlineLarge: tweak(base.headlineLarge),
      headlineMedium: tweak(base.headlineMedium),
      headlineSmall: tweak(base.headlineSmall),
      titleLarge: tweak(base.titleLarge),
      titleMedium: tweak(base.titleMedium),
      titleSmall: tweak(base.titleSmall),
      bodyLarge: tweak(base.bodyLarge),
      bodyMedium: tweak(base.bodyMedium),
      bodySmall: tweak(base.bodySmall),
      labelLarge: tweak(base.labelLarge),
      labelMedium: tweak(base.labelMedium),
      labelSmall: tweak(base.labelSmall),
    );
  }
}
