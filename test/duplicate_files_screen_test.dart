import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/screens/duplicate_files_screen.dart';

/// Mükerrer dosyalar ekranı: tarama sonunda grup başlıkları ve özet kartı
/// görünür; mükerrer olmayan dosya listelenmez.
void main() {
  testWidgets('Gruplar listelenir, tek başına olan dosya görünmez',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('dup_ui_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final sep = Platform.pathSeparator;
    // 2 kopya (2048 bayt) + tek başına olan bir dosya.
    _write('${root.path}${sep}kopya1.bin', 'A' * 2048);
    _write('${root.path}${sep}alt${sep}kopya2.bin', 'A' * 2048);
    _write('${root.path}${sep}tek_benzersiz.bin', 'C' * 1500);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(home: DuplicateFilesScreen(root: root.path)),
      ),
    );

    // Açılışta döner göstergesi görünür.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Tarama izolatta gerçek zamanda biter; döngüyle beklenir.
    var found = false;
    for (var i = 0; i < 200 && !found; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      found = find.textContaining('2 kopya').evaluate().isNotEmpty;
    }

    expect(found, isTrue, reason: 'grup başlığı görünmeli');
    expect(find.textContaining('2 KB • 2 kopya'), findsOneWidget,
        reason: 'başlıkta kazanılan alan ve kopya sayısı olmalı');
    expect(find.textContaining('tek_benzersiz'), findsNothing,
        reason: 'mükerrer olmayan dosya listelenmemeli');

    // Özet kartı: grup sayısı ve kazanılabilir alan.
    expect(find.textContaining('1 grup bulundu'), findsOneWidget);
    expect(find.textContaining('2 KB alan geri kazanılabilir'), findsOneWidget);
    expect(find.text('TEMİZLE'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Hiç mükerrer yokken boş durum gösterilir', (tester) async {
    final root = Directory.systemTemp.createTempSync('dup_ui_empty_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    _write('${root.path}${Platform.pathSeparator}tek.bin', 'C' * 1500);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(home: DuplicateFilesScreen(root: root.path)),
      ),
    );

    var empty = false;
    for (var i = 0; i < 200 && !empty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      empty = find.text('Mükerrer dosya bulunamadı.').evaluate().isNotEmpty;
    }

    expect(empty, isTrue, reason: 'boş durum metni görünmeli');
  }, timeout: const Timeout(Duration(seconds: 60)));
}

void _write(String path, String content) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}
