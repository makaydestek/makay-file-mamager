import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/providers/settings_provider.dart';
import 'package:makay_file_manager/screens/device_mode_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Seçim ekranı iki sürümü kart olarak gösterir', (tester) async {
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const DeviceModeScreen(),
          ),
        ),
      ),
    );

    expect(find.text('Makay Dosya Yöneticisi'), findsOneWidget);
    expect(find.text('Mobil-Tablet Sürümü'), findsOneWidget);
    expect(find.text('TV Sürümü'), findsOneWidget);
    expect(settings.deviceModeChosen, false);
  });

  testWidgets('TV seçimi TV arayüzünü + koyu temayı otomatik uygular', (tester) async {
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const DeviceModeScreen(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('TV Sürümü'));
    await tester.pumpAndSettle();

    expect(settings.tvMode, 'tv');
    expect(settings.deviceModeChosen, true);
    // TV sürümünde koyu tema otomatik etkinleşir.
    expect(settings.themeMode, ThemeMode.dark);
  });

  testWidgets('Mobil-Tablet seçimi klasik arayüzü uygular', (tester) async {
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const DeviceModeScreen(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mobil-Tablet Sürümü'));
    await tester.pumpAndSettle();

    expect(settings.tvMode, 'phone');
    expect(settings.deviceModeChosen, true);
    expect(settings.themeMode, ThemeMode.system);
  });
}
