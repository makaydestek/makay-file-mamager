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
    expect(find.text('Görüntüler'), findsOneWidget);
    expect(find.text('Videolar'), findsOneWidget);
    expect(find.text('Ağdan erişim'), findsOneWidget);
  });
}
