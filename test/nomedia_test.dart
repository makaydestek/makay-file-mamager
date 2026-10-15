import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/utils/nomedia.dart';

/// Galeri gizlemesi (`.nomedia`) kuralı: işaretli klasörler uygulamada da
/// gizli tutulur; WhatsApp/Telegram/Signal kendi `.nomedia` dosyalarını
/// kendileri yazdığı için bu klasörler gizlenmez.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('nomedia_test_');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('.nomedia dosyası klasörü gizli yapar', () async {
    final folder = await Directory('${temp.path}/Albüm').create();
    expect(isHiddenByNomedia(folder.path), isFalse);

    await File('${folder.path}/.nomedia').create();
    expect(isHiddenByNomedia(folder.path), isTrue);
    expect(await isHiddenByNomediaAsync(folder.path), isTrue);
  });

  test('WhatsApp klasörü kendi .nomedia dosyasıyla gizlenmez', () async {
    final wa = await Directory('${temp.path}/WhatsApp').create();
    await File('${wa.path}/.nomedia').create();
    expect(isHiddenByNomedia(wa.path), isFalse);
    expect(await isHiddenByNomediaAsync(wa.path), isFalse);
  });

  test('Telegram ve Signal için de istisna geçerlidir', () async {
    for (final name in ['Telegram', 'signal']) {
      final dir = await Directory('${temp.path}/$name').create();
      await File('${dir.path}/.nomedia').create();
      expect(isHiddenByNomedia(dir.path), isFalse, reason: name);
    }
  });

  test('ad parametresi kuralın klasör adı olarak uygulanır', () async {
    // Boyut hesapları yol yerine ad ile kontrol eder: `.nomedia` dosyası
    // olan klasör ad verilince gizli, WhatsApp istisnasıyla ad verilince
    // gizli değildir.
    final folder = await Directory('${temp.path}/Gizli').create();
    await File('${folder.path}/.nomedia').create();

    expect(isHiddenByNomedia(folder.path, name: 'Gizli'), isTrue);
    expect(
      isHiddenByNomedia(folder.path, name: 'WhatsApp'),
      isFalse,
      reason: 'WhatsApp istisnası ad üzerinden de uygulanır',
    );
  });
}
