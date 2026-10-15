import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/providers/settings_provider.dart';
import 'package:makay_file_manager/screens/browser_screen.dart';
import 'package:makay_file_manager/screens/storage_analysis_screen.dart';
import 'package:makay_file_manager/theme/app_theme.dart';
import 'package:makay_file_manager/widgets/root_header.dart';

/// Referans görünüme göre düzeltmeler:
///
///  • **Ana bellek** (kök seviye): hamburger menü + çekmece, app bar altında
///    yol/kullanım satırı (RootHeader), klasör satırları "N öğe" + dosya
///    satırı boyut.
///  • **Bellek Analizi**: hamburger menü + çekmece, taşma menüsü.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Gerçek dosya G/Ç'si sahte zaman döngüsünde BİTMEZ: runAsync ile gerçek
  /// zaman verilip `pump()` ile frame basılır (browser_screen_test kalıbı).
  Future<bool> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxIterations = 200,
  }) async {
    for (var i = 0; i < maxIterations; i++) {
      if (condition()) return true;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    return condition();
  }

  Future<void> pumpRootBrowser(WidgetTester tester, Directory root) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: BrowserScreen(
            title: 'Ana bellek',
            rootPath: root.path,
            showRootDrawer: true,
          ),
        ),
      ),
    );
    // Liste + arka plandaki klasör adetleri ("2 öğe") bitsin.
    final ok = await pumpUntil(
        tester, () => find.text('2 öğe').evaluate().isNotEmpty);
    expect(ok, isTrue,
        reason: 'Klasör listesi ve adetleri yüklenmedi (zaman aşımı).');
  }

  group('Ana bellek (kök seviye tarayıcı)', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('root_browser_');
      Directory('${root.path}/DCIM').createSync();
      File('${root.path}/rapor.pdf').writeAsStringSync('x');
      File('${root.path}/DCIM/fot1.jpg').writeAsStringSync('x');
      File('${root.path}/DCIM/fot2.jpg').writeAsStringSync('x');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    testWidgets('hamburger menü + çekmece vardır ve açılır', (tester) async {
      await pumpRootBrowser(tester, root);

      // App bar'da hamburger menü düğmesi (geri ok değil).
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);

      // Çekmece açılır ve menü öğeleri görünür.
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Ana Ekran'), findsOneWidget);
      expect(find.text('Geri Dönüşüm Kutusu'), findsOneWidget);
    });

    testWidgets('üst satırda yol göstergesi (RootHeader) vardır',
        (tester) async {
      await pumpRootBrowser(tester, root);

      // Ana simge > klasör simgesi satırı app bar altında, tekil.
      expect(find.byType(RootHeader), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(RootHeader), matching: find.byIcon(Icons.home_rounded)),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byType(RootHeader),
            matching: find.byIcon(Icons.chevron_right_rounded)),
        findsOneWidget,
      );
    });

    testWidgets('klasör satırı "N öğe", dosya satırı boyut gösterir',
        (tester) async {
      await pumpRootBrowser(tester, root);

      // DCIM klasörü: fot1 + fot2 = 2 öğe (kök kendi satırında görünmez).
      expect(find.text('2 öğe'), findsOneWidget);
      // Dosya satırı: adet değil boyut ("1 B").
      expect(find.text('rapor.pdf'), findsOneWidget);
      expect(find.text('1 B'), findsOneWidget);
    });

    testWidgets('klasör satırında amber klasör + iç simge görünür',
        (tester) async {
      await pumpRootBrowser(tester, root);

      // DCIM klasörü kamera simgesiyle gösterilir.
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.byIcon(Icons.folder_rounded), findsWidgets);
    });
  });

  group('Bellek Analizi', () {
    testWidgets('hamburger menü + çekmece + taşma menüsü vardır',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsProvider.load();
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const StorageAnalysisScreen(),
          ),
        ),
      );
      // Üst çubuk ilk frame'de hazırdır; içerik yükleme gerçek G/Ç ister.
      await tester.pump();

      expect(find.text('Bellek Analizi'), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      // Taşma menüsü: Yenile + Ayarlar (sınırlı pump: menü animasyonu).
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Yenile'), findsOneWidget);
      expect(find.text('Ayarlar'), findsOneWidget);
    });
  });
}
