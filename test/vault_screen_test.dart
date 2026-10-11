import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/screens/vault_screen.dart';
import 'package:makay_file_manager/services/vault_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kasa ekranı: PIN oluşturma → kilitleme → doğru PIN ile listeye geçiş.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('vault_ui_');
    VaultService.debugRoot = root.path;
    SharedPreferences.setMockInitialValues({});
    VaultService.lock();
  });

  tearDown(() {
    VaultService.lock();
    VaultService.debugRoot = null;
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

  testWidgets('PIN oluşturma → kilit → doğru PIN ile "Kasa boş" listesi',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Kasa Oluştur'), findsOneWidget);
    expect(find.text('OLUŞTUR'), findsOneWidget);

    // Eşleşmeyen PIN uyarısı.
    await tester.enterText(find.byType(TextField).at(0), '1234');
    await tester.enterText(find.byType(TextField).at(1), '4321');
    await tester.tap(find.text('OLUŞTUR'));
    await tester.pump();
    expect(find.text('PIN\'ler eşleşmiyor'), findsOneWidget);

    // Eşleşen PIN ile oluşturulur ve kilit ekranına geçilir.
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('OLUŞTUR'));
    await pumpUntil(tester, () => find.text('KİLİT AÇ').evaluate().isNotEmpty);

    expect(find.text('KİLİT AÇ'), findsOneWidget);
    expect(await VaultService.isConfigured(), isTrue);
    expect(VaultService.unlocked, isFalse, reason: 'ekran kilidi kapalı tutar');

    // Yanlış PIN hata SnackBar'ı gösterir.
    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('KİLİT AÇ'));
    await pumpUntil(tester, () => find.text('PIN hatalı').evaluate().isNotEmpty);
    expect(find.text('PIN hatalı'), findsWidgets);
    expect(VaultService.unlocked, isFalse);

    // Doğru PIN ile kasa açılır.
    await tester.enterText(find.byType(TextField), '1234');
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
}
