import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/screens/hex_viewer_screen.dart';
import 'package:makay_file_manager/screens/text_editor_screen.dart';

/// Hex görüntüleyici ve metin editörü: açma, gösterme, düzenleme akışları.
///
/// Not: dosya hazırlama `setUp` (gerçek async) içinde yapılır; `testWidgets`
/// fake-async zone'unda bekleyen dosya I/O'su hiç tamamlanmaz.
void main() {
  late Directory dir;
  late File binFile;
  late File smallFile;
  late File bigFile;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('viewer_');
    binFile = File('${dir.path}${Platform.pathSeparator}ornek.bin');
    // 32 bayt: 0..31
    await binFile.writeAsBytes(List<int>.generate(32, (i) => i));
    smallFile = File('${dir.path}${Platform.pathSeparator}not.txt');
    await smallFile.writeAsString('merhaba dünya');
    bigFile = File('${dir.path}${Platform.pathSeparator}buyuk.txt');
    // 1 MB + 10 bayt düz metin.
    await bigFile.writeAsString('a' * (1024 * 1024 + 10));
  });

  tearDown(() {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows'ta dosya kolu hâlâ kapandıysa sessizce geç (testi bozma).
    }
  });

  /// Dönen çubuğu kaybolana kadar gerçek zamanlı bekle (fake-async dışı).
  Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      final spinning =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      if (!spinning) break;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pump();
  }

  /// Ekranı ağaçtan çıkarır (dosya kolları kapanır) ve temizliği dener.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  testWidgets('HexViewer satır ve offset gösterir', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HexViewerScreen(file: binFile, title: 'ornek.bin'),
      ),
    );
    await settle(tester);
    // Satırlar async yüklenir; gerçek satır içeriği (başlık değil) bekle.
    const rowHex =
        '00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F ';
    for (var i = 0;
        i < 40 && find.text(rowHex).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(find.text('ornek.bin'), findsOneWidget);
    // İlk satır offset'i görünür.
    expect(find.textContaining('00000000'), findsWidgets);
    // İlk satırın hex içeriği (başlık satırından ayrı) görünür.
    expect(find.text(rowHex), findsOneWidget);
    // ASCII sütunu: denetim karakterleri nokta olarak çizilir.
    expect(find.textContaining('........'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('TextEditor dosyayı gösterir ve kaydeder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TextEditorScreen(file: smallFile, title: 'not.txt'),
      ),
    );
    await settle(tester);

    expect(find.text('not.txt'), findsOneWidget);
    expect(find.textContaining('merhaba dünya'), findsOneWidget);
    // Satır/karakter bilgisi görünür.
    expect(find.textContaining('1 satır'), findsOneWidget);

    // Düzenle moduna geç, metni değiştir, kaydet.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'yeni içerik');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.save_rounded));
    // Kaydetme gerçek dosya I/O'su içerir; runAsync ile bitmesini bekle.
    String? saved;
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      saved = await tester.runAsync(() => smallFile.readAsString()) ;
      // Kaydedildi bildirimi de çizildiyse döngüden çık.
      if (saved == 'yeni içerik' &&
          find.textContaining('kaydedildi').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(saved, 'yeni içerik');
    // Kaydedildi bildirimi görünür.
    expect(find.textContaining('kaydedildi'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('TextEditor 1 MB üstü dosyayı kırpıp salt-okunur gösterir',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TextEditorScreen(file: bigFile, title: 'buyuk.txt'),
      ),
    );
    await settle(tester, rounds: 80);

    // Uyarı bandı görünür (düzenleme sınırı).
    expect(find.textContaining('salt okunur'), findsOneWidget);
    // Görünüm kırpılmıştır: devamı çizilmez uyarısı.
    expect(find.textContaining('devamı görüntülenmiyor'), findsOneWidget);
    await unmount(tester);
  });
}
