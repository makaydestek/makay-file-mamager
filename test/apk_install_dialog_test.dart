import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makay_file_manager/widgets/apk_install_dialog.dart';

/// İndirilenler'de `.apk` dosyasına dokununca açılan kurulum diyaloğu:
/// bilgi okunamasa bile dosya adı + "Kur" düğmesiyle Android kurucusu
/// çağrılabilir olmalı (saha şikâyeti: bilgi diyaloğu geliyordu).
void main() {
  late File apk;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('apk_dialog_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    apk = File('${dir.path}${Platform.pathSeparator}uzak_tanitim_v1.apk')
      ..writeAsBytesSync(List<int>.filled(2048, 1));
  });

  testWidgets('APK diyaloğu dosya adını ve "Kur" düğmesini gösterir',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showApkInstallDialog(context, apk),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    // Dosya adı başlıkta görünür (paket bilgisi platforma bağlıdır).
    expect(find.textContaining('uzak_tanitim_v1.apk'), findsWidgets);
    // Bilgi okunamasa da kurulum mümkün: "Kur" ve "İptal" düğmeleri var.
    expect(find.text('Kur'), findsOneWidget);
    expect(find.text('İptal'), findsOneWidget);
    // Eski davranış: yalnız "Tamam" ile kapanan bilgi diyaloğu OLMAmALI.
    expect(find.text('Tamam'), findsNothing);

    // İptal diyaloğu kapatır.
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();
    expect(find.text('Kur'), findsNothing);
  });
}
