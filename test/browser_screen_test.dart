import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/providers/settings_provider.dart';
import 'package:makay_file_manager/screens/browser_screen.dart';
import 'package:makay_file_manager/theme/app_theme.dart';

/// Dosya tarayıcı başlığı: yol (breadcrumb) şeridi gösterilmez — ekran
/// yalnızca "geri oku + başlık" içeren tek satırlık bir üst çubukla başlar
/// (albüm ekranlarındaki görünümle aynı).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Directory> pumpBrowser(WidgetTester tester) async {
    final root = Directory.systemTemp.createTempSync('browser_nav_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    File('${root.path}${Platform.pathSeparator}rapor.txt')
        .writeAsStringSync('x');

    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: BrowserScreen(title: 'Belgeler', rootPath: root.path),
          ),
        ),
      ),
    );
    // Dizin listesi gerçek dosya G/Ç'siyle gelir: runAsync + bekle.
    var loaded = false;
    for (var i = 0; i < 200 && !loaded; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      loaded = find.text('rapor.txt').evaluate().isNotEmpty;
    }
    return root;
  }

  testWidgets('Yol şeridi (breadcrumb) gösterilmez', (tester) async {
    final root = await pumpBrowser(tester);

    expect(find.text('Belgeler'), findsOneWidget);
    expect(find.text('rapor.txt'), findsOneWidget);

    // Yolun son ögesi artık başlık şeridinde tekrarlanmıyor.
    expect(find.text(root.path.split(Platform.pathSeparator).last),
        findsNothing);
    expect(find.text('storage'), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byIcon(Icons.home_rounded), findsNothing);
  });

  testWidgets('Başlık çubuğu doğrudan listeyle birleşir', (tester) async {
    await pumpBrowser(tester);

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    // Başlık, arama, sıralama ve taşma menüsü — ek bir satır yok.
    expect(appBar.bottom, isNull);
    expect(find.byType(Scaffold), findsOneWidget);
    // "Ana ekrana dön" kısayolu taşma menüsüne taşındı.
    // Arama + sıralama + liste/ızgara geçişi = 3 düğme (taşma menüsü hariç).
    expect(appBar.actions?.whereType<IconButton>().length ?? 0,
        lessThanOrEqualTo(3));
  });
}