import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/screens/recent_files_screen.dart';

/// "Yeni Dosyalar" ekranı: yalnız son 7 günde değişen dosyalar listelenir
/// ve satırlar "(Tarih • Boyut)" biçiminde gösterilir.
void main() {
  setUp(() {
    // Geçmiş (okundu) kayıtları her testte sıfırdan başlar.
    SharedPreferences.setMockInitialValues({});
  });
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

  testWidgets('"Temizle" listeyi boşaltır ama dosyaları silmez',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('recent_clear_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final sep = Platform.pathSeparator;
    final file = File('${root.path}${sep}yeni.txt')
      ..writeAsStringSync('x' * 40);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(home: RecentFilesScreen(root: root.path)),
      ),
    );

    var found = false;
    for (var i = 0; i < 200 && !found; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      found = find.text('yeni.txt').evaluate().isNotEmpty;
    }
    expect(found, isTrue);

    // Temizle düğmesi tek dokunuşla temizler (onay diyaloğu yok).
    await tester.tap(find.byTooltip('Temizle'));
    await tester.pumpAndSettle();

    // Liste boşaldı…
    expect(find.text('yeni.txt'), findsNothing);
    expect(find.textContaining('Geçmişiniz temizlendi'), findsWidgets);
    // …ama dosya diskte duruyor.
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync().length, 40);

    // Temizle düğmesi artık yok (zaten boş liste).
    expect(find.byTooltip('Temizle'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Temizlenen dosya ekrana bir daha gelmez, yeni dosya gelir',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('recent_history_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final sep = Platform.pathSeparator;
    final eski = File('${root.path}${sep}eski.txt')
      ..writeAsStringSync('a' * 10);

    var pumpCount = 0;

    Future<void> pumpScreen() async {
      // Aynı ağaç verilirse Flutter State'i yeniden kullanır ve initState
      // çalışmaz; yeni key ile ekranı gerçekten yeniden kuruyoruz.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            key: ValueKey(pumpCount++),
            home: RecentFilesScreen(root: root.path),
          ),
        ),
      );
      // İzolat taraması gerçek zamanda biter: spinner kaybolana kadar bekle
      // (yoksa "yeni dosya yok" boş ekranı erken görünür ve erken çıkılır).
      for (var i = 0; i < 400; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          await tester.pump();
          return;
        }
      }
      fail('tarama zamanında bitmedi');
    }

    // 1) Dosya listede görünür.
    await pumpScreen();
    expect(find.text('eski.txt'), findsOneWidget);

    // Tek dokunuşla Temizle → dosya listeden düşer ama diskte kalır.
    await tester.tap(find.byTooltip('Temizle'));
    await tester.pumpAndSettle();
    expect(find.text('eski.txt'), findsNothing);
    expect(eski.existsSync(), isTrue, reason: 'dosya silinmemeli');

    // 2) Aynı dosya hâlâ cihazda ama ekrana bir daha gelmez.
    await pumpScreen();
    expect(find.text('eski.txt'), findsNothing,
        reason: 'temizlenen dosya tekrar listelenmemeli');

    // 3) Cihaza yeni bir dosya eklenince o görünür.
    File('${root.path}${sep}taze.txt').writeAsStringSync('b' * 20);
    await pumpScreen();
    expect(find.text('taze.txt'), findsOneWidget);
    expect(find.text('eski.txt'), findsNothing);

    // 4) Temizlenen bir dosya DEĞİŞTİRİLİRSE yeniden "yeni" sayılır.
    await tester.tap(find.byTooltip('Temizle'));
    await tester.pumpAndSettle();

    eski.writeAsStringSync('güncellendi');
    await pumpScreen();
    expect(find.text('eski.txt'), findsOneWidget,
        reason: 'değiştirilen dosya yeni dosya gibi yeniden görünmeli');
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('Temizlemeden önce hiçbir şeye dokunulmaz', (tester) async {
    final root = Directory.systemTemp.createTempSync('recent_nodialog_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final sep = Platform.pathSeparator;
    final file = File('${root.path}${sep}yeni.txt')
      ..writeAsStringSync('x' * 40);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(home: RecentFilesScreen(root: root.path)),
      ),
    );

    var found = false;
    for (var i = 0; i < 200 && !found; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      found = find.text('yeni.txt').evaluate().isNotEmpty;
    }
    expect(found, isTrue);

    // Tek dokunuş — onay diyaloğu çıkmaz, işlem doğrudan yapılır.
    await tester.tap(find.byTooltip('Temizle'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('yeni.txt'), findsNothing);
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync().length, 40);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets(
      'Aşağı kaydırma geçmişi geri getirmez, düğme getirir', (tester) async {
    final root = Directory.systemTemp.createTempSync('recent_restore_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final sep = Platform.pathSeparator;
    File('${root.path}${sep}eski.txt').writeAsStringSync('a' * 10);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(home: RecentFilesScreen(root: root.path)),
      ),
    );

    var found = false;
    for (var i = 0; i < 200 && !found; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      found = find.text('eski.txt').evaluate().isNotEmpty;
    }
    expect(found, isTrue);

    await tester.tap(find.byTooltip('Temizle'));
    await tester.pumpAndSettle();
    expect(find.text('eski.txt'), findsNothing);

    // Aşağı kaydırma yalnızca taramayı yeniler: okundu işaretleri durduğu
    // için temizlenen dosya GERİ GELMEZ, düğme ise ekranda kalır.
    //
    // Not: `pumpAndSettle` kullanılmıyor — RefreshIndicator + kaydırma
    // momentumu asla "yerleşmez" ve test çerçevesi zaman aşımına uğrar.
    // Bunun yerine gerçek zaman (runAsync) ve sınırlı pump döngüsü var.
    await tester.fling(find.byType(ListView), const Offset(0, 350), 1000);
    await tester.pump();
    var sawRefresh = false;
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.byType(RefreshProgressIndicator).evaluate().isNotEmpty) {
        sawRefresh = true;
      }
      if (find.text('eski.txt').evaluate().isNotEmpty) break;
    }
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(sawRefresh, isTrue, reason: 'aşağı kaydırma taramayı tetiklemeli');
    expect(find.text('eski.txt'), findsNothing,
        reason: 'yenileme temizlenen dosyayı geri getirmemeli');
    expect(find.text('Tüm geçmişi tekrar göster'), findsOneWidget,
        reason: 'düğme yenilemeden sonra da erişilebilir kalmalı');

    // Düğme ise geçmişi geri getirir.
    await tester.tap(find.text('Tüm geçmişi tekrar göster'));
    var restored = false;
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.text('eski.txt').evaluate().isNotEmpty) {
        restored = true;
        break;
      }
    }
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(restored, isTrue,
        reason: 'düğme temizlenen dosyaları listeye döndürmeli');
    expect(find.text('Tüm geçmişi tekrar göster'), findsNothing,
        reason: 'liste dolunca düğme kaybolur');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
