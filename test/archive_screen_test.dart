import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/screens/archive_screen.dart';

/// ArchiveScreen widget testleri: klasör gezinme, hata durumu, satır menüsü
/// ve "Tümünü çıkar" akışı. Arşiv dosyaları setUp() içinde gerçek dosya
/// sisteminde hazırlanır; test gövdelerindeki dosya işlemleri
/// `tester.runAsync` ile sarmalanır (FakeAsync tuzağı).
void main() {
  final sep = Platform.pathSeparator;
  late Directory root;
  late String zipPath;
  late String corruptPath;

  setUp(() {
    root = Directory.systemTemp.createTempSync('archive_ui_');
    final archive = Archive()
      ..add(ArchiveFile.string('dosya.txt', 'ana icerik'))
      ..add(ArchiveFile.string('klasor/alt.txt', 'alt icerik'))
      ..add(ArchiveFile.string('klasor/daha/dip.txt', 'dip icerik'));
    zipPath = '${root.path}${sep}ornek.zip';
    File(zipPath).writeAsBytesSync(ZipEncoder().encodeBytes(archive));

    corruptPath = '${root.path}${sep}bozuk.zip';
    File(corruptPath).writeAsBytesSync(const [9, 8, 7, 6]);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Gerçek dosya G/Ç'leri FakeAsync içinde tamamlanmaz; runAsync ile
  /// döngüyle beklenir (repo kanıtlanmış deseni).
  Future<void> pumpUntil(
      WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  testWidgets('girişler listelenir, klasöre inilir ve breadcrumb ile dönülür',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: ArchiveScreen(archivePath: zipPath)));
    await pumpUntil(tester, () => find.text('dosya.txt').evaluate().isNotEmpty);

    // Başlık: dosya adı ve özet bilgi.
    expect(find.text('ornek.zip'), findsOneWidget);
    expect(find.textContaining('3 dosya'), findsOneWidget);
    // Kökte klasörler ve dosyalar görünür.
    expect(find.text('klasor'), findsOneWidget);
    expect(find.text('dosya.txt'), findsOneWidget);

    // Klasöre in.
    await tester.tap(find.text('klasor'));
    await tester.pump();
    expect(find.text('alt.txt'), findsOneWidget);
    expect(find.text('daha'), findsOneWidget);
    expect(find.text('dosya.txt'), findsNothing);

    // Daha derine in (sentezlenen klasör).
    await tester.tap(find.text('daha'));
    await tester.pump();
    expect(find.text('dip.txt'), findsOneWidget);

    // Breadcrumb'dan kökü geri dön.
    await tester.tap(find.text('Arşiv'));
    await tester.pump();
    expect(find.text('dosya.txt'), findsOneWidget);
    expect(find.text('dip.txt'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('bozuk arşiv dostça hata durumu gösterir', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: ArchiveScreen(archivePath: corruptPath)));
    await pumpUntil(
        tester, () => find.textContaining('okunamadı').evaluate().isNotEmpty);

    expect(find.textContaining('okunamadı'), findsOneWidget);
    expect(find.text('Yeniden dene'), findsOneWidget);
    // Çıkar butonu etkin değil.
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'TÜMÜNÜ ÇIKAR'));
    expect(button.onPressed, isNull);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('dosya satır menüsü: Bilgiler diyaloğu açılır', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ArchiveScreen(archivePath: zipPath)));
    await pumpUntil(tester, () => find.text('dosya.txt').evaluate().isNotEmpty);

    // Kökte tek dosya olduğundan tek ⋮ menüsü var.
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Buraya çıkar'), findsOneWidget);
    expect(find.text('Dışa aktar / Paylaş'), findsOneWidget);
    expect(find.text('Bilgi'), findsOneWidget);

    // Bilgi öğesine dokunulunca bilgi diyaloğu açılır (Çıkar/I/O tetiklenmez).
    await tester.tap(find.text('Bilgi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Boyut:'), findsOneWidget);
    expect(find.textContaining('Tür: Dosya'), findsOneWidget);
    expect(find.textContaining('Yol: dosya.txt'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('"Tümünü çıkar" ilerlemeyle çalışır ve SnackBar verir',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: ArchiveScreen(archivePath: zipPath)));
    await pumpUntil(tester, () => find.text('dosya.txt').evaluate().isNotEmpty);

    // Uzantı menüsünde de "Tümünü çıkar" var.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Tümünü çıkar'), findsOneWidget);
    expect(find.text('Arşiv bilgileri'), findsOneWidget);
    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();

    // Alt bardaki ana eylem.
    await tester.tap(find.widgetWithText(FilledButton, 'TÜMÜNÜ ÇIKAR'));
    await pumpUntil(
        tester, () => find.textContaining('Çıkarıldı').evaluate().isNotEmpty);

    expect(find.textContaining('Çıkarıldı'), findsOneWidget);
    expect(find.textContaining('Çıkarıldı: 3 dosya'), findsOneWidget);

    // Gerçek dosyalar diske çıkmış olmalı (arşivin yanındaki klasör).
    final dest = '${root.path}${sep}ornek';
    expect(File('$dest${sep}dosya.txt').readAsStringSync(), 'ana icerik');
    expect(File('$dest${sep}klasor${sep}alt.txt').readAsStringSync(),
        'alt icerik');
    expect(
        File('$dest${sep}klasor${sep}daha${sep}dip.txt').readAsStringSync(),
        'dip icerik');
  }, timeout: const Timeout(Duration(seconds: 120)));
}
