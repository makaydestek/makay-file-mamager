import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makay_file_manager/screens/apps_screen.dart';

/// Uygulamalar ekranı: **"TÜMÜ" sekmesi en başta ve varsayılan** olmalı.
///
/// Ekran hangi yoldan açılırsa açılsın (ana ekran kartı, çekmece,
/// `/apps/system`) kullanıcı ilk olarak Tümü listesini görmelidir.
void main() {
  testWidgets('Sekme sırası TÜMÜ → İNDİRİLENLER → DAHİLİ', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppsScreen()));
    await tester.pumpAndSettle();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    final tabs = tabBar.tabs.cast<Tab>();
    expect(
      tabs.map((t) => t.text).toList(),
      ['TÜMÜ', 'İNDİRİLENLER', 'DAHİLİ'],
      reason: '"TÜMÜ" her zaman en başta olmalı',
    );
    expect(tabBar.controller!.index, 0,
        reason: 'açılışta varsayılan sekme TÜMÜ olmalı');
  });

  testWidgets('initialIndex=2 Dahili sekmesini açar (rota: /apps/system)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppsScreen(initialIndex: 2)));
    await tester.pumpAndSettle();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 2);
    expect(tabBar.tabs.cast<Tab>().toList()[2].text, 'DAHİLİ');
  });
}
