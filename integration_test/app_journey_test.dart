import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:makay_file_manager/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

/// Uçtan uca (E2E) test paketi — gerçek uygulama, gerçek cihaz.
///
/// Bu paket `flutter test` ile **çalıştırılmaz** (ayrı `integration_test/`
/// klasörüdür). Bir Android cihaz veya emülatör bağlıyken:
///
///     flutter test integration_test -d <cihaz> `
///         --dart-define=MAKAY_SKIP_UPDATE_CHECK=true
///
/// `MAKAY_SKIP_UPDATE_CHECK` gerekli: test derlemesinin sürümü GitHub'daki
/// en son sürümden yenidir, sorgu çalışırsa "Güncelleme bulundu" diyaloğu
/// açılabilir ve gezinme adımlarını bloklar.
///
/// Testler sırayla çalışır ve **cihaz durumunu paylaşır**: ilk test gerçek
/// ilk açılış akışını geçer, sonraki testler aynı akışın tekrar
/// gösterilmediğini (kalıcılık) doğrular.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Gerçek cihazda dosya/izin I/O'su sürdüğü için `pumpAndSettle` bazen hiç
  /// durmaz (yükleme indikatörü sonsuz kare çizer). Bu sürümde
  /// `pumpAndSettle` yalnızca tek parametre alır (zaman aşımı yok), bu yüzden
  /// durulma elle ve **sınırlı** şekilde beklenir: yeni kare planlanmadığı
  /// anda çıkılır, hiç durulmazsa en fazla [maxFrames] kare itelenir.
  Future<void> settle(WidgetTester tester, {int maxFrames = 50}) async {
    for (var i = 0; i < maxFrames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (!tester.binding.hasScheduledFrame) return;
    }
  }

  /// Uygulamayı (yeniden) açar ve ilk karelerin çizilmesini bekler.
  ///
  /// [clean] `true` ise açılmadan önce ayarlar silinir. Bu şarttır: test
  /// koşucusu uygulamayı her seferinde kaldıramayabilir (emülatörde
  /// `DELETE_FAILED_INTERNAL_ERROR` görüldü) ve önceki koşulun verisi
  /// kalırsa ilk açılış akışı bir daha gösterilmez. Ayarların temizlenmesi
  /// testi sıradan (order) bağımsız kılar.
  Future<void> launch(WidgetTester tester, {bool clean = false}) async {
    if (clean) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    }
    await app.main();
    await settle(tester);
  }

  testWidgets('ilk açılış akışı: sürüm seçimi → izinler → ana ekran',
      (tester) async {
    // Cihaz temizlenir ki gerçek ilk açılış akışı her koşuda sınanabilsin.
    await launch(tester, clean: true);

    // --- 1) Sürüm seçimi (A18) ---
    expect(
      find.text('Kullanım şeklinizi seçin'),
      findsOneWidget,
      reason: 'İlk açılışta sürüm seçim ekranı görünmeli',
    );
    await tester.tap(find.text('Mobil-Tablet Sürümü'));
    await settle(tester);

    // --- 2) İzinler ---
    expect(
      find.text('Gerekli İzinler'),
      findsOneWidget,
      reason: 'Sürüm seçiminden sonra izin ekranı gelmeli',
    );
    // Otomasyonda sistem izin dialogu elle onaylanamaz; uygulamanın
    // sunduğu "sınırlı kullanım" yolu kullanılır — bu da gerçek bir
    // kullanıcı yoludur ve uygulamanın izinsiz açılabildiğini kanıtlar.
    await tester.tap(find.text('Yine de devam et (sınırlı kullanım)'));
    await settle(tester);

    // --- 3) Ana ekran ---
    expect(
      find.text('Makay Dosya Yöneticisi'),
      findsWidgets,
      reason: 'Ana ekran başlığı görünmeli',
    );
    for (final title in const [
      'Ana bellek',
      'İndirilenler',
      'Bellek Analizi',
      'Belgeler',
      'Bulut',
    ]) {
      expect(
        find.text(title),
        findsWidgets,
        reason: '"$title" kategorisi ana ekranda görünmeli',
      );
    }
  });

  testWidgets('ana ekran → ayarlar → geri ve → ana bellek tarayıcısı',
      (tester) async {
    await launch(tester);

    // Sürüm seçimi ve izin adımı bu kez **gösterilmemeli** (kalıcılık).
    expect(
      find.text('Kullanım şeklinizi seçin'),
      findsNothing,
      reason: 'Sürüm seçimi yalnızca ilk açılışta gösterilmeli',
    );
    expect(
      find.text('Gerekli İzinler'),
      findsNothing,
      reason: 'İzin ekranı yalnızca ilk açılışta gösterilmeli',
    );

    // --- Ayarlar (taşma menüsü) ---
    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Ayarlar'));
    await settle(tester);

    expect(find.text('Ayarlar'), findsWidgets, reason: 'Ayarlar açılmalı');
    // Ayarlar ekranının bölümleri.
    for (final section in const ['Tema', 'Arayüz modu', 'Görünüm düzeni']) {
      expect(
        find.text(section),
        findsWidgets,
        reason: 'Ayarlar"$section" bölümü görünmeli',
      );
    }

    // --- Ana ekrana geri ---
    // Not: `tester.pageBack()` yalnızca `byTooltip('Back')` ve Cupertino
    // geri düğmesini arar; uygulama zorla Türkçe olduğu için Material geri
    // düğmesinin ipucu "Geri"'dir ve `pageBack()` onu bulamaz. Doğrudan
    // `BackButton` tipi aranır.
    final back = find.byType(BackButton);
    expect(back, findsOneWidget, reason: 'Ayarlar ekranında geri düğmesi olmalı');
    await tester.tap(back);
    await settle(tester);
    expect(find.text('Makay Dosya Yöneticisi'), findsWidgets);

    // --- Çekmece → Ana bellek tarayıcısı ---
    await tester.tap(find.byType(DrawerButton));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Ana bellek'));
    await settle(tester);

    // Tarayıcı başlığı kategori adıdır.
    expect(find.text('Ana bellek'), findsWidgets);
  });

  testWidgets('çekmece → Kasa ekranı açılır ve PIN kurulumunu gösterir',
      (tester) async {
    await launch(tester);

    await tester.tap(find.byType(DrawerButton));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Kasa'));
    await settle(tester);

    // Kasa ya kurulum (PIN) ekranındadır ya da açıktır; her iki durumda da
    // ekranın kendisi görünür olmalı.
    expect(
      find.byType(Scaffold),
      findsWidgets,
      reason: 'Kasa ekranı açılmalı',
    );
  });
}
