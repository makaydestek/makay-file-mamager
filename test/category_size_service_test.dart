import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/services/category_size_service.dart';
import 'package:makay_file_manager/services/recent_seen_store.dart';

/// Ana ekran kategori boyutlarının hesaplanması:
/// klasör taraması, uzantıya göre kategori ayrımı, son 7 gün penceresi,
/// "Temizle" (görüldü) filtresi ve erişilemeyen dizin davranışı.
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
    _write('$base${sep}Download${sep}eklenti.png', 11);
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
    expect(downloads, 193,
        reason: 'a.txt (100) + alt/ic.txt (5) + eski.txt (77) + eklenti.png (11)');

    expect(CategorySizeService.dirSize('$base${sep}BoyleBirKlasor'), 0);
  });

  test('dirSize(skipHidden) gizli dosyaları atlar; kart ekranla aynı',
      () {
    final sep = Platform.pathSeparator;
    _write('$base${sep}Download$sep.gizli', 40);
    expect(CategorySizeService.dirSize('$base${sep}Download'), 233,
        reason: 'varsayılan: gizli dosyalar dâhil');
    expect(CategorySizeService.dirSize('$base${sep}Download', skipHidden: true),
        193,
        reason: 'kart, Belgeler/İndirilenler ekranının gizli gizleyen '
            'varsayılan görünümüyle aynı toplamı verir');

    final sizes = CategorySizeService.scan(base);
    expect(sizes['downloads'], 193, reason: 'scan gizliyi kartlara almaz');
  });

  test('scan kategori başına toplamları hesaplar', () {
    final sizes = CategorySizeService.scan(base);

    expect(sizes['downloads'], 193,
        reason: 'Download klasörünün tamamı (İndirilenler ekranı da onu açar)');
    expect(sizes['images'], 86,
        reason: 'DCIM (25) + Pictures (50) + Download içindeki png (11)');
    expect(sizes['videos'], 40);
    expect(sizes['audio'], 10);
    // Belgeler kartı, Belgeler EKRANININ açtığı Documents klasörünü sayar:
    // Download içindeki metin/PDF dosyaları o ekranda görünmediği için
    // karta da girmez (saha şikâyeti: ekran "Boş Klasör" derken kart
    // 158 KB gösteriyordu).
    expect(sizes['documents'], 30,
        reason: 'yalnız Documents/d.pdf; Download txt dosyaları hariç');
  });

  test('Belgeler ekranı boşken kart da 0 verir', () {
    final sep = Platform.pathSeparator;
    // Documents olmayan ama doc uzantılı dosyalar barındıran bir kök:
    final temp = Directory.systemTemp.createTempSync('cat_empty_');
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    _write('${temp.path}${sep}Download${sep}notlar.txt', 4096);

    final sizes = CategorySizeService.scan(temp.path);
    expect(sizes['documents'], 0,
        reason: 'boş Belgeler klasörü → kart 0; ekranla aynı');
    expect(sizes['downloads'], 4096,
        reason: 'İndirilenler klasör içeriği ekranla aynı');
  });

  test('classifySizes dosyayı yalnız bir kategoriye yazar', () {
    final totals = CategorySizeService.classifySizes(base);
    final sum = totals.values.fold<int>(0, (a, b) => a + b);
    // Download/eklenti.png hem downloads hem images toplamına girer; burada
    // ise tek bir kategoriye yazıldığı için toplam şişmez.
    expect(sum, 86 + 40 + 10);
    expect(totals['images'], 86);
    // Belgeler/İndirilenler sınıflandırmaya girmez (doğrudan klasör boyutu).
    expect(totals.containsKey('documents'), isFalse);
  });

  test('categoryOfExtension uzantıları doğru kategoriye ayırır', () {
    expect(CategorySizeService.categoryOfExtension('png'), 'images');
    expect(CategorySizeService.categoryOfExtension('MP4'), 'videos');
    expect(CategorySizeService.categoryOfExtension('mp3'), 'audio');
    expect(CategorySizeService.categoryOfExtension('pdf'), 'documents');
    expect(CategorySizeService.categoryOfExtension('exe'), isNull);
    expect(CategorySizeService.categoryOfExtension(''), isNull);
  });

  test('recentSize yalnız son 7 günde değişen dosyaları sayar', () {
    final recent = CategorySizeService.recentSize(base);
    // Kök dosya (999) + Download (100 + 5 + 11) + klasör dosyaları
    // (50 + 25 + 40 + 10 + 30); 30 günlük eski.txt (77) hariç.
    expect(recent, 999 + 100 + 5 + 11 + 50 + 25 + 40 + 10 + 30,
        reason: '30 günlük eski.txt sayılmamalı, kök dosya sayılmalı');
  });

  test('recentSize görülmüş ("Temizle") dosyaları hariç tutar', () {
    final sep = Platform.pathSeparator;
    final a = File('$base${sep}Download${sep}a.txt');
    final key = RecentSeenStore.keyOf(
        a.path, a.statSync().modified);

    final filtered = CategorySizeService.recentSize(base, seen: {key});
    final all = CategorySizeService.recentSize(base);
    expect(filtered, all - 100,
        reason: 'görülen dosya kart boyutuna girmemeli');
  });

  test('scan, görülmüş dosyaları "recent" boyutundan düşer', () {
    final sep = Platform.pathSeparator;
    final png = File('$base${sep}Pictures${sep}p.png');
    final key =
        RecentSeenStore.keyOf(png.path, png.statSync().modified);

    final sizes = CategorySizeService.scan(base, seenRecent: {key});
    final plain = CategorySizeService.scan(base);
    expect(sizes['recent'], plain['recent']! - 50,
        reason: 'Ana Sayfa kartı temizlenen dosyayı göstermemeli');
    // Diğer kategoriler etkilenmez: temizleme yalnız "Yeni Dosyalar" listesini
    // ilgilendirir, dosya silinmemiştir.
    expect(sizes['images'], plain['images']);
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
