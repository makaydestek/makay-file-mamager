import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/screens/vault_screen.dart';
import 'package:makay_file_manager/services/vault_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kasa ekranı: PIN oluşturma → kilitleme → doğru PIN ile listeye geçiş,
/// PIN uzunluğu doğrulaması ve kilitlenme (geri sayım + devre dışı buton).
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('vault_ui_');
    VaultService.debugRoot = root.path;
    SharedPreferences.setMockInitialValues({});
    VaultService.lock();
    VaultService.now = DateTime.now;
  });

  tearDown(() {
    VaultService.lock();
    VaultService.debugRoot = null;
    VaultService.now = DateTime.now;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Gerçek dosya G/Ç'leri FakeAsync içinde tamamlanmaz; runAsync ile
  /// döngüyle beklenir.
  Future<void> pumpUntil(
      WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: const VaultScreen()),
    );
    await tester.pumpAndSettle();
  }

  FilledButton unlockButton(WidgetTester tester) => tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, 'KİLİT AÇ'));

  testWidgets('PIN oluşturma → kilit → doğru PIN ile "Kasa boş" listesi',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Kasa Oluştur'), findsOneWidget);
    expect(find.text('OLUŞTUR'), findsOneWidget);

    // Eşleşmeyen ama geçerli uzunlukta PIN uyarısı.
    await tester.enterText(find.byType(TextField).at(0), '123456');
    await tester.enterText(find.byType(TextField).at(1), '654321');
    await tester.tap(find.text('OLUŞTUR'));
    await tester.pump();
    expect(find.text('PIN\'ler eşleşmiyor'), findsOneWidget);

    // Eşleşen PIN ile oluşturulur ve kilit ekranına geçilir.
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.text('OLUŞTUR'));
    await pumpUntil(tester, () => find.text('KİLİT AÇ').evaluate().isNotEmpty);

    expect(find.text('KİLİT AÇ'), findsOneWidget);
    expect(await VaultService.isConfigured(), isTrue);
    expect(VaultService.unlocked, isFalse, reason: 'ekran kilidi kapalı tutar');

    // Yanlış PIN hata SnackBar'ı gösterir.
    await tester.enterText(find.byType(TextField), '999999');
    await tester.tap(find.text('KİLİT AÇ'));
    await pumpUntil(tester, () => find.text('PIN hatalı').evaluate().isNotEmpty);
    expect(find.text('PIN hatalı'), findsWidgets);
    expect(VaultService.unlocked, isFalse);

    // Doğru PIN ile kasa açılır.
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('KİLİT AÇ'));
    await pumpUntil(tester, () => find.text('Kasa boş').evaluate().isNotEmpty);

    expect(find.text('Kasa boş'), findsOneWidget);
    expect(find.text('KİLİT AÇ'), findsNothing);
    expect(
      find.textContaining('Kasaya taşı'),
      findsOneWidget,
      reason: 'alt bilgi satırı görünür olmalı',
    );
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('5 haneli PIN reddedilir; 12 haneli PIN ile kasa açılır',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text('Kasa Oluştur'), findsOneWidget);

    // Kısa PIN reddedilir.
    await tester.enterText(find.byType(TextField).at(0), '12345');
    await tester.enterText(find.byType(TextField).at(1), '12345');
    await tester.tap(find.text('OLUŞTUR'));
    await tester.pump();
    expect(find.textContaining('6 ile 12 hane arasında olmalı'), findsOneWidget);
    expect(await VaultService.isConfigured(), isFalse);

    // 12 haneli PIN kabul edilir ve açılır.
    const longPin = '123456789012';
    await tester.enterText(find.byType(TextField).at(0), longPin);
    await tester.enterText(find.byType(TextField).at(1), longPin);
    await tester.tap(find.text('OLUŞTUR'));
    await pumpUntil(tester, () => find.text('KİLİT AÇ').evaluate().isNotEmpty);
    expect(await VaultService.isConfigured(), isTrue);

    await tester.enterText(find.byType(TextField), longPin);
    await tester.tap(find.text('KİLİT AÇ'));
    await pumpUntil(tester, () => find.text('Kasa boş').evaluate().isNotEmpty);
    expect(find.text('Kasa boş'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 120)));

  group('kilitlenme (üstel geri çekilmeli)', () {
    late DateTime fakeNow;

    setUp(() async {
      // Sahte saat: testler gerçek süre beklemeden geri sayımı oynatır.
      fakeNow = DateTime(2026, 10, 11, 9, 30);
      VaultService.now = () => fakeNow;
      // Gerçek dosya G/Ç'si asla testWidgets içine konmaz.
      await VaultService.create('123456');
      VaultService.lock();
    });

    testWidgets(
        '2 hatalı PIN → kilitlenme; "X saniye sonra tekrar deneyin" geri '
        'sayımı işler; buton devre dışı; süre dolunca açılır', (tester) async {
      await pumpScreen(tester);
      expect(find.text('KİLİT AÇ'), findsOneWidget);

      // 1. hatalı deneme: henüz bekleme yok, kalan deneme gösterilir.
      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('KİLİT AÇ'));
      await pumpUntil(
          tester, () => find.textContaining('Kalan deneme').evaluate().isNotEmpty);
      expect(find.textContaining('PIN hatalı. Kalan deneme: 4'), findsOneWidget);
      expect(unlockButton(tester).onPressed, isNotNull);

      // 2. hatalı deneme → 5 saniye kilitlenme.
      await tester.enterText(find.byType(TextField), '111111');
      await tester.tap(find.text('KİLİT AÇ'));
      await pumpUntil(tester,
          () => find.textContaining('saniye sonra tekrar deneyin').evaluate().isNotEmpty);
      expect(find.textContaining('5 saniye sonra tekrar deneyin'), findsOneWidget);
      expect(
        unlockButton(tester).onPressed,
        isNull,
        reason: 'kilitlenme süresince KİLİT AÇ devre dışı olmalı',
      );

      // Geri sayım saniye saniye işler.
      for (var i = 4; i >= 1; i--) {
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.textContaining('$i saniye sonra tekrar deneyin'),
          findsOneWidget,
          reason: 'geri sayım $i saniye kalmalı',
        );
        expect(unlockButton(tester).onPressed, isNull);
      }

      // Süre doldu: geri sayım biter, buton yeniden açılır.
      fakeNow = fakeNow.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('saniye sonra tekrar deneyin'), findsNothing);
      expect(find.textContaining('PIN hatalı. Kalan deneme: 3'), findsOneWidget);
      expect(unlockButton(tester).onPressed, isNotNull);

      // Doğru PIN kilit kalkmışken açar; sayaç sıfırlanır.
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('KİLİT AÇ'));
      await pumpUntil(tester, () => find.text('Kasa boş').evaluate().isNotEmpty);
      expect(find.text('Kasa boş'), findsOneWidget);
      expect(await VaultService.failedAttempts(), 0);
      expect(await VaultService.lockoutRemaining(), Duration.zero);
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
