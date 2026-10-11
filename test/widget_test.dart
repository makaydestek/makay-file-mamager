import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/providers/settings_provider.dart';
import 'package:makay_file_manager/screens/home_screen.dart';
import 'package:makay_file_manager/theme/app_theme.dart';

void main() {
  testWidgets('Ana ekran kategori ızgarasını gösterir', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsProvider.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: HomeScreen(),
          ),
        ),
      ),
    );

    expect(find.text('Makay Dosya Yöneticisi'), findsOneWidget);
    expect(find.text('Ana bellek'), findsOneWidget);
    expect(find.text('Resimler'), findsOneWidget);
    expect(find.text('Videolar'), findsOneWidget);
    expect(find.text('Ağdan erişim'), findsOneWidget);
  });

  testWidgets('Dar ekranda kategori kartlarında taşma olmaz', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsProvider.load();

    // Küçük telefon ekranı (360x640) — taşmanın görüldüğü boyut.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // RenderFlex taşması exception olarak yansır.
    expect(tester.takeException(), isNull);
    expect(find.text('Yeni Dosyalar'), findsOneWidget);
  });
}
