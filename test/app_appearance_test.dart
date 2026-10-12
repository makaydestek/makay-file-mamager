import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/providers/settings_provider.dart';
import 'package:makay_file_manager/theme/app_appearance.dart';
import 'package:makay_file_manager/theme/app_theme.dart';

/// Görünüm preset'i: her seçenek yazı, ikon, köşe ve zemini birlikte
/// değiştirmeli; **Klasik** ise mevcut görünümün aynısı olmalı (regresyon).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppAppearance — tema üretimi', () {
    test('her preset hem aydınlık hem karanlık temayı bozmadan üretir', () {
      for (final a in AppAppearance.values) {
        final light = AppTheme.light(appearance: a);
        final dark = AppTheme.dark(appearance: a);
        expect(light.brightness, Brightness.light, reason: a.label);
        expect(dark.brightness, Brightness.dark, reason: a.label);
        expect(light.useMaterial3, isTrue, reason: a.label);
        // Tipografi tüm stiller için uygulanmış olmalı (null kalmamalı).
        expect(light.textTheme.titleLarge, isNotNull, reason: a.label);
        expect(light.textTheme.bodyMedium, isNotNull, reason: a.label);
      }
    });

    test('KLASİK regresyonu: mevcut görünümün aynısıdır', () {
      final byDefault = AppTheme.light();
      final explicit = AppTheme.light(appearance: AppAppearance.klasik);
      expect(byDefault.colorScheme.primary, explicit.colorScheme.primary);
      expect(byDefault.scaffoldBackgroundColor,
          const Color(0xFFF5F5F5), reason: 'eski açık zemin korunmalı');
      final shape = byDefault.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(12),
          reason: 'eski kart köşesi korunmalı');
    });

    test('dinamik (Material You) renk yalnız Klasik\'te dikkate alınır', () {
      const seed = Color(0xFFFF0000);
      final plain = AppTheme.light(appearance: AppAppearance.canli);
      final dyn = AppTheme.light(
        dynamicSeed: seed,
        appearance: AppAppearance.klasik,
      );
      expect(dyn.colorScheme.primary, isNot(plain.colorScheme.primary),
          reason: 'Klasik, sistem rengini kullanmalı');

      final dynCanli = AppTheme.light(
        dynamicSeed: seed,
        appearance: AppAppearance.canli,
      );
      expect(dynCanli.colorScheme.primary, plain.colorScheme.primary,
          reason: 'görünümün kendi tarzı ezilmemeli');
    });
  });

  group('AppAppearance — boyutlar birlikte değişir', () {
    test('TEKNOLOJİK yazı ailesini monospace yapar', () {
      expect(
        AppTheme.light(appearance: AppAppearance.teknolojik)
            .textTheme
            .bodyMedium
            ?.fontFamily,
        'monospace',
      );
      expect(AppTheme.light().textTheme.bodyMedium?.fontFamily,
          isNot('monospace'),
          reason: 'Klasik platform fontunu bozmaz');
    });

    test('OKUNAKLI yazı ölçeğini büyütür (textScaler katsayısı)', () {
      // Boyut artışı `MediaQuery.textScaler` ile uygulanır; bkz. main.dart
      // ve `AppTheme._textTheme` notları (fontSize'lar theme'de taşınmaz).
      expect(AppAppearance.okunakli.fontSizeFactor, greaterThan(1.0));
      expect(AppAppearance.klasik.fontSizeFactor, 1.0,
          reason: 'Klasik mevcut yazı ölçeğini bozmaz');
      // Satır aralığı da okunabilirlik için açılır.
      expect(AppAppearance.sade.lineHeightDelta, greaterThan(0));
      expect(AppAppearance.klasik.lineHeightDelta, 0);
    });

    test('CANLI kartları yuvarlatır, SADE ikonları inceltir', () {
      final canli =
          AppTheme.light(appearance: AppAppearance.canli);
      final shape = canli.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(20));

      final sade = AppTheme.light(appearance: AppAppearance.sade);
      expect(sade.iconTheme.weight, 300);
      expect(sade.iconTheme.fill, 0);

      final canliIcons = canli.iconTheme;
      expect(canliIcons.weight, 700);
      expect(canliIcons.fill, 1);
    });

    test('zemin ve gradyan preset ile birlikte gelir', () {
      const light = Brightness.light;
      expect(AppAppearance.klasik.backgroundGradient(light), isNull,
          reason: 'Klasik düz zemin (mevcut davranış)');
      expect(AppAppearance.okunakli.backgroundGradient(light), isNull);
      expect(AppAppearance.canli.backgroundGradient(light), isNotNull);
      expect(AppAppearance.sade.backgroundGradient(light), isNotNull);
      expect(AppAppearance.teknolojik.backgroundGradient(light), isNotNull);
      // Koyu temada da zemin değişir.
      expect(AppAppearance.canli.scaffoldColor(Brightness.dark),
          isNot(AppAppearance.canli.scaffoldColor(light)));
    });

    test('bilinmeyen kimlik Klasik\'e döner', () {
      expect(AppAppearance.fromId('boyle-bir-sey'), AppAppearance.klasik);
      expect(AppAppearance.fromId(null), AppAppearance.klasik);
      expect(AppAppearance.fromId('canli'), AppAppearance.canli);
    });
  });

  group('SettingsProvider.appearance', () {
    test('varsayılan Klasik\'tir ve kalıcıdır', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await SettingsProvider.load();
      expect(first.appearance, AppAppearance.klasik);

      first.appearance = AppAppearance.okunakli;

      final second = await SettingsProvider.load();
      expect(second.appearance, AppAppearance.okunakli);
    });

    test('değişim dinleyicileri uyarır (ekran anında yenilenir)', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsProvider.load();
      var notified = 0;
      settings.addListener(() => notified++);

      settings.appearance = AppAppearance.sade;
      expect(notified, 1);
    });
  });
}
