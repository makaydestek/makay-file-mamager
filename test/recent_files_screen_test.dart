import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/screens/recent_files_screen.dart';

/// "Yeni Dosyalar" ekranı: yalnız son 7 günde değişen dosyalar listelenir
/// ve satırlar "(Tarih • Boyut)" biçiminde gösterilir.
void main() {
  testWidgets('Son 7 günün dosyaları listelenir, eskiler hariç tutulur',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('recent_ui_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final sep = Platform.pathSeparator;
    final fresh = File('${root.path}${sep}yeni.txt')
      ..writeAsStringSync('x' * 40);
    final old = File('${root.path}${sep}eski.txt')
      ..writeAsStringSync('y' * 10);
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));
    expect(fresh.existsSync(), isTrue);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(home: RecentFilesScreen(root: root.path)),
      ),
    );

    // İzolat taraması gerçek zamanda biter; döngüyle beklenir.
    var found = false;
    for (var i = 0; i < 200 && !found; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      found = find.text('yeni.txt').evaluate().isNotEmpty;
    }

    expect(found, isTrue, reason: 'yeni dosya listelenmeli');
    expect(find.text('eski.txt'), findsNothing,
        reason: '30 günlük dosya sayılmamalı');

    // Satır alt başlığı "(Tarih • Boyut)" biçiminde olmalı.
    expect(find.textContaining('('), findsWidgets);
    expect(find.textContaining('40 B'), findsWidgets);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
