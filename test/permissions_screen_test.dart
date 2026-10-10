import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/providers/settings_provider.dart';
import 'package:makay_file_manager/screens/permissions_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('İzin ekranı gerekli izinleri listeler', (tester) async {
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const PermissionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Uygulamanın çalışması için izinler'), findsOneWidget);
    expect(find.text('Tüm dosyalara erişim'), findsOneWidget);
    expect(find.text('Medya erişimi'), findsOneWidget);
    expect(settings.permissionsOnboarded, false);
  });

  // Test ortamı Android olmadığı için izinler "verilmiş" kabul edilir;
  // amaç "Devam et" akışının akışı tamamladığını doğrulamak.
  testWidgets('Devam et akışı tamamlar', (tester) async {
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const PermissionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Devam et'),
    );
    expect(button.onPressed, isNotNull);

    await tester.ensureVisible(find.text('Devam et'));
    await tester.tap(find.text('Devam et'));
    await tester.pump();

    expect(settings.permissionsOnboarded, true);
  });

  testWidgets('Sınırlı kullanılımdan sonra akış tamamlanır', (tester) async {
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const PermissionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final skip = find.text('Yine de devam et (sınırlı kullanım)');
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pump();

    expect(settings.permissionsOnboarded, true);
  });
}