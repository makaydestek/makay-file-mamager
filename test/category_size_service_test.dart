import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/services/category_size_service.dart';

/// Ana ekran kategori boyutlarının hesaplanması:
/// klasör taraması, son 7 gün penceresi ve erişilemeyen dizin davranışı.
void main() {
  late Directory root;
  late String base;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cat_size_');
    base = root.path;
    final sep = Platform.pathSeparator;
    _write('$base${sep}Download${sep}a.txt', 100);
    _write('$base${sep}Download${sep}alt${sep}ic.txt', 5);
    _write('$base${sep}Download${sep}eski.txt', 77, stale: true);
    _write('$base${sep}Pictures${sep}p.png', 50);
    _write('$base${sep}DCIM${sep}c.jpg', 25);
    _write('$base${sep}Movies${sep}v.mp4', 40);
    _write('$base${sep}Music${sep}m.mp3', 10);
    _write('$base${sep}Documents${sep}d.pdf', 30);
    // Kategori dizini dışındaki dosya yalnızca "recent" sayımına girer.
    _write('$base${sep}kaynak.dart', 999);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('dirSize özyinelemeli toplar, olmayan dizin için 0 döner', () {
    final sep = Platform.pathSeparator;
    final downloads = CategorySizeService.dirSize('$base${sep}Download');
    expect(downloads, 182,
        reason: 'a.txt (100) + alt/ic.txt (5) + eski.txt (77)');

    expect(CategorySizeService.dirSize('$base${sep}BoyleBirKlasor'), 0);
  });

  test('scan kategori başına toplamları hesaplar', () {
    final sizes = CategorySizeService.scan(base);

    expect(sizes['downloads'], 182, reason: 'Download alt klasörüyle birlikte');
    expect(sizes['images'], 75, reason: 'DCIM + Pictures');
    expect(sizes['videos'], 40);
    expect(sizes['audio'], 10);
    expect(sizes['documents'], 30);

    // Klasör toplamları: kökteki kaynak.dart (999) bunlara girmez.
    final folderSum = sizes['downloads']! +
        sizes['images']! +
        sizes['videos']! +
        sizes['audio']! +
        sizes['documents']!;
    expect(folderSum, 182 + 75 + 40 + 10 + 30);
  });

  test('recentSize yalnız son 7 günde değişen dosyaları sayar', () {
    final recent = CategorySizeService.recentSize(base);
    // Kök dosya (999) + Download (100 + 5) + klasör dosyaları
    // (50 + 25 + 40 + 10 + 30); 30 günlük eski.txt (77) hariç.
    expect(recent, 999 + 100 + 5 + 50 + 25 + 40 + 10 + 30,
        reason: '30 günlük eski.txt sayılmamalı, kök dosya sayılmalı');
  });

  test('recentSize erişilemeyen dizinde sessizce atlar', () {
    expect(
        CategorySizeService.recentSize('$base${Platform.pathSeparator}yok'),
        0);
  });
}

void _write(String path, int bytes, {bool stale = false}) {
  final file = File(path)..createSync(recursive: true);
  file.writeAsBytesSync(List<int>.filled(bytes, 1));
  if (stale) {
    file.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));
  }
}
