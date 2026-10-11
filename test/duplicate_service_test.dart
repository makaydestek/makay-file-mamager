import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/services/duplicate_service.dart';

/// Mükerrer dosya tespiti: boyut + MD5 eşleşmesi, gizli dosya ve "Android"
/// klasörü atlaması, minSize sınırı, silme ve kazanılan alan hesabı.
void main() {
  late Directory root;
  late String base;
  late String sep;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dup_');
    base = root.path;
    sep = Platform.pathSeparator;
    // 1. grup: 3 kopya, 2048 bayt (farklı ad ve klasörlerde).
    _write('$base${sep}kopya1.bin', 'A' * 2048);
    _write('$base${sep}alt${sep}kopya2.bin', 'A' * 2048);
    _write('$base${sep}alt2${sep}kopya3.bin', 'A' * 2048);
    // 2. grup: 3 kopya; aynı boyut farklı içerik → yalnızca MD5 ayırır.
    _write('$base${sep}farkli1.bin', 'B' * 2048);
    _write('$base${sep}alt${sep}farkli2.bin', 'B' * 2048);
    _write('$base${sep}alt2${sep}farkli3.bin', 'B' * 2048);
    // Tek başına olan dosya hiçbir gruba girmez.
    _write('$base${sep}tek_benzersiz.bin', 'C' * 1500);
    // minSize (1 KB) altındaki eşleşmeler atlanır.
    _write('$base${sep}kucuk1.bin', 'D' * 500);
    _write('$base${sep}kucuk2.bin', 'D' * 500);
    // Gizli dosya ve "Android" klasöründeki kopya atlanır.
    _write('$base$sep.gizli.bin', 'A' * 2048);
    _write('$base${sep}Android${sep}sistem.bin', 'A' * 2048);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('find aynı içerikli dosyaları iki grupta toplar', () async {
    final groups = await DuplicateService.find(base);
    expect(groups, hasLength(2), reason: 'yalnızca 2 mükerrer grup olmalı');

    final kopyalar = groups
        .firstWhere((g) => g.paths.any((p) => p.endsWith('kopya1.bin')));
    expect(kopyalar.count, 3,
        reason: 'gizli ve Android klasöründeki kopyalar sayılmamalı');
    expect(kopyalar.size, 2048);
    expect(kopyalar.wasted, 4096, reason: 'boyut × (kopya sayısı - 1)');

    final farklilar = groups
        .firstWhere((g) => g.paths.any((p) => p.endsWith('farkli1.bin')));
    expect(farklilar.count, 3);
    expect(farklilar.size, 2048);

    // Tek başına olan, küçük veya atlanan dosyalar hiçbir gruba girmez.
    for (final g in groups) {
      expect(g.paths.any((p) => p.endsWith('tek_benzersiz.bin')), isFalse);
      expect(g.paths.any((p) => p.endsWith('kucuk1.bin')), isFalse);
      expect(g.paths.any((p) => p.endsWith('kucuk2.bin')), isFalse);
      expect(g.paths.any((p) => p.endsWith('.gizli.bin')), isFalse);
      expect(g.paths.any((p) => p.endsWith('sistem.bin')), isFalse);
    }
  });

  test('find olmayan dizin için boş liste döner', () async {
    expect(await DuplicateService.find('olmayan_dizin'), isEmpty);
    expect(await DuplicateService.find('$base${sep}boyle_bir_klasor_yok'),
        isEmpty);
  });

  test('delete kazanılan baytı döner ve dosyaları siler', () async {
    final groups = await DuplicateService.find(base);
    final group = groups
        .firstWhere((g) => g.paths.any((p) => p.endsWith('kopya1.bin')));
    final doomed =
        group.paths.where((p) => !p.endsWith('kopya1.bin')).toList();
    expect(doomed, hasLength(2));

    final freed = await DuplicateService.delete(doomed);
    expect(freed, 2 * 2048, reason: 'iki kopyanın boyutu kazanılmalı');
    for (final p in doomed) {
      expect(File(p).existsSync(), isFalse, reason: '$p silinmeli');
    }
    expect(File('$base${sep}kopya1.bin').existsSync(), isTrue,
        reason: 'korunan kopya yerinde kalmalı');
  });

  test('delete erişilemeyen yolları yutar', () async {
    expect(await DuplicateService.delete(['$base${sep}zaten_yok.bin']), 0);
  });
}

void _write(String path, String content) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}
