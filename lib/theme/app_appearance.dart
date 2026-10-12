import 'package:flutter/material.dart';

/// Uygulamanın **görünüm preset'i**.
///
/// Tema (açık / koyu / sistem) yalnızca arka planı değil tüm rengi belirler;
/// **görünüm** ise kullanıcının görsel *tarz* tercihidir ve yazı fontu,
/// ikon stili, köşe yuvarlaklığı, renk doygunluğu ile ana ekran arka planını
/// **birlikte** değiştirir. Örneğin "Canlı & Yuvarlak" görünümü, koyu temada
/// da yuvarlak ve doygun kalır — her iki boyut birbirinden bağımsızdır.
///
/// Font aileleri **asset gerektirmez**: yalnızca platformun sunduğu aileler
/// (varsayılan sans-serif, monospace) kullanılır, böylece APK boyutu ve
/// açılış hızı etkilenmez.
enum AppAppearance {
  /// Bilinen/tanıdık görünüm: turkuaz vurgu, standart köşe ve ikonlar.
  klasik,

  /// Sakin yüzey: düşük doygun renk, geniş satır aralığı, ince (narin)
  /// ikonlar, az yuvarlatılmış köşeler.
  sade,

  /// Enerjik yüzey: morumsu canlı vurgu, dolu/kalın ikonlar, belirgin
  /// yuvarlatılmış kartlar ve ana ekranda renkli gradyan arka plan.
  canli,

  /// Düzene/teknolojiye yakın: monospace yazı, keskin köşeler ve
  /// camgöbeği vurgu.
  teknolojik,

  /// Okunabilirlik öncelikli: artırılmış yazı boyutu ve yüksek kontrastlı
  /// palet (ör. yaşlı kullanıcılar veya zayıf ekranlar için).
  okunakli;

  /// Saklanan tercih anahtarı (`SettingsProvider`).
  String get id => name;

  /// Türkçe görünen ad.
  String get label => switch (this) {
        AppAppearance.klasik => 'Klasik',
        AppAppearance.sade => 'Sade & İnce',
        AppAppearance.canli => 'Canlı & Yuvarlak',
        AppAppearance.teknolojik => 'Teknolojik',
        AppAppearance.okunakli => 'Büyük & Okunaklı',
      };

  /// Ayarlar listesindeki ve seçim diyaloğundaki kısa açıklama.
  String get description => switch (this) {
        AppAppearance.klasik => 'Uygulamanın standart görünümü',
        AppAppearance.sade => 'Düşük doygun renkler, ince yazı ve narin ikonlar',
        AppAppearance.canli => 'Canlı vurgu, yuvarlak kartlar ve dolu ikonlar',
        AppAppearance.teknolojik => 'Düzenli monospace yazı ve keskin köşeler',
        AppAppearance.okunakli => 'Büyük yazı ve yüksek kontrast',
      };

  /// Paletin tohum rengi.
  ///
  /// [AppTheme.accent] (turkuaz) bu dosyadan **kopyalanmıştır**; döngüsel
  /// import olmaması için `app_theme.dart` buradan import edilmez — iki
  /// değer eşit tutulmalıdır.
  Color get seed => switch (this) {
        AppAppearance.klasik => const Color(0xFF00897B),
        AppAppearance.sade => const Color(0xFF607D8B),
        AppAppearance.canli => const Color(0xFF7C4DFF),
        AppAppearance.teknolojik => const Color(0xFF00B0FF),
        AppAppearance.okunakli => const Color(0xFF0D47A1),
      };

  /// Yalnız "Klasik" görünümü Material You (sistem) rengini kullanabilir;
  /// diğer görünümlerin kendi tarzı vardır, sistem rengi onları ezmez.
  bool get honorsDynamicSeed => this == AppAppearance.klasik;

  /// Renk paletini üretir.
  ///
  /// [dynamicSeed] yalnızca [honorsDynamicSeed] iken dikkate alınır
  /// (bkz. `SettingsProvider.dynamicColor`).
  ColorScheme scheme(Brightness brightness, {Color? dynamicSeed}) =>
      ColorScheme.fromSeed(
        seedColor: honorsDynamicSeed && dynamicSeed != null
            ? dynamicSeed
            : seed,
        brightness: brightness,
        dynamicSchemeVariant: switch (this) {
          AppAppearance.klasik => DynamicSchemeVariant.tonalSpot,
          // `neutral` doygunluğu düşük (sakin yüzey), `vibrant` yüksek
          // (canlı yüzey) palet üretir — ayrıca saturation gerekmez.
          AppAppearance.sade => DynamicSchemeVariant.neutral,
          AppAppearance.canli => DynamicSchemeVariant.vibrant,
          AppAppearance.teknolojik => DynamicSchemeVariant.expressive,
          AppAppearance.okunakli => DynamicSchemeVariant.fidelity,
        },
        // Kontrast: okunaklı görünüm erişilebilirlik için belirgin yüksek.
        contrastLevel: switch (this) {
          AppAppearance.sade => -0.1,
          AppAppearance.teknolojik => 0.15,
          AppAppearance.okunakli => 0.5,
          _ => 0.0,
        },
      );

  /// Gövde yazı ailesi; `null` platform varsayılanı (sans-serif).
  String? get fontFamily => switch (this) {
        AppAppearance.teknolojik => 'monospace',
        _ => null,
      };

  /// Tüm yazıların boyut katsayısı (okunabilirlik öncelikli görünümde artar).
  double get fontSizeFactor => switch (this) {
        AppAppearance.okunakli => 1.15,
        _ => 1.0,
      };

  /// Harf aralığı **eklemesi** (piksel; yazı boyutundan bağımsız).
  double get letterSpacing => switch (this) {
        AppAppearance.sade => 0.3,
        AppAppearance.teknolojik => 0.8,
        AppAppearance.okunakli => 0.2,
        AppAppearance.canli => -0.2,
        _ => 0.0,
      };

  /// Satır yüksekliği eklemesi (0 = platform varsayılanı).
  double get lineHeightDelta => switch (this) {
        AppAppearance.sade => 0.25,
        _ => 0.0,
      };

  /// Kart yüzeyinin köşe yarıçapı.
  double get cornerRadius => switch (this) {
        AppAppearance.sade => 6,
        AppAppearance.canli => 20,
        AppAppearance.teknolojik => 4,
        AppAppearance.okunakli => 10,
        _ => 12,
      };

  /// Butonların köşe yarıçapı (karttan biraz daha az yuvarlak).
  double get buttonRadius => switch (this) {
        AppAppearance.sade => 6,
        AppAppearance.canli => 16,
        AppAppearance.teknolojik => 4,
        _ => 10,
      };

  /// İkon stili: doluluk (fill), kalınlık (weight) ve boyut birlikte.
  ///
  /// Material Symbols glifleri bu alanları okur (`Icon` → `IconTheme`), yani
  /// seçim tüm uygulamadaki ikonlara anında yansır.
  IconThemeData get iconTheme => switch (this) {
        AppAppearance.sade =>
          const IconThemeData(fill: 0, weight: 300, opticalSize: 48, size: 22),
        AppAppearance.canli =>
          const IconThemeData(fill: 1, weight: 700, opticalSize: 48, size: 26),
        AppAppearance.teknolojik =>
          const IconThemeData(fill: 0, weight: 400, opticalSize: 72, size: 22),
        AppAppearance.okunakli =>
          const IconThemeData(fill: 0, weight: 600, opticalSize: 48, size: 28),
        _ => const IconThemeData(),
      };

  /// Uygulama geneli zemin rengi.
  Color scaffoldColor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (this) {
      AppAppearance.sade => isDark ? const Color(0xFF0E1112) : const Color(0xFFFAFBFB),
      AppAppearance.canli => isDark ? const Color(0xFF12101F) : const Color(0xFFF7F4FF),
      AppAppearance.teknolojik =>
        isDark ? const Color(0xFF07121A) : const Color(0xFFEFF8FF),
      AppAppearance.okunakli => isDark ? const Color(0xFF101010) : const Color(0xFFFAFAFA),
      // Klasik: mevcut davranış korunur.
      _ => isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
    };
  }

  /// Ana ekranda arkaya çizilecek gradyan; `null` = düz zemin.
  ///
  /// Yalnız ana ekran (telefon + TV) kullanır: zeminin en çok görüldüğü
  /// yerdir ve gradyan burada belirgin, diğer ekranlarda sakin durur.
  LinearGradient? backgroundGradient(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (this) {
      AppAppearance.canli => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF1A1230), Color(0xFF0D1A19)]
              : const [Color(0xFFEFE9FF), Color(0xFFE3F3F0)],
        ),
      AppAppearance.teknolojik => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF081824), Color(0xFF050D13)]
              : const [Color(0xFFE4F3FF), Color(0xFFEFF8FF)],
        ),
      AppAppearance.sade => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF14181A), Color(0xFF0E1112)]
              : const [Color(0xFFF4F7F8), Color(0xFFFAFBFB)],
        ),
      _ => null,
    };
  }

  /// Kimlik dizesinden preset (bilinmeyen değer → [AppAppearance.klasik]).
  static AppAppearance fromId(String? id) =>
      AppAppearance.values.asNameMap()[id] ?? AppAppearance.klasik;
}
