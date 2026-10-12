import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/services/category_size_service.dart';
import 'package:makay_file_manager/services/file_service.dart';

/// Kategori boyutu **önbelleği**: dosya işlemleri önbelleği geçersiz kılmalı
/// ve hesaplamadan dönen **kısmi/boş** sonuç ekrandaki değerleri silmemeli.
///
/// Bu iki davranış, kullanıcı şikâyetinin kök nedenidir: dosya silinip boyutu
/// 0 B olduğunda ana ekran kartı bayat boyutu göstermeye devam ediyordu.
///
/// (Klasör taraması/son 7 gün penceresi için bkz.
/// `category_size_service_test.dart`.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cacheKey = 'category_sizes_cache';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CategorySizeService.labels.value = const {};
  });

  group('invalidate', () {
    test('dosya silince önbellek geçersiz kılınır', () async {
      // Önbellekte taze bir kayıt varsayalım (cacheMaxAge'den yeni).
      SharedPreferences.setMockInitialValues({
        cacheKey: jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'values': {'internal': '1 GB'},
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(cacheKey), isNotNull, reason: 'kurulum');

      final dir = Directory.systemTemp.createTempSync('invalidate_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final file = File('${dir.path}${Platform.pathSeparator}a.txt')
        ..writeAsStringSync('x' * 32);

      await const FileService().deleteEntry(file.path);

      expect(file.existsSync(), isFalse, reason: 'dosya silinmiş olmalı');
      expect(prefs.getString(cacheKey), isNull,
          reason:
              'silme sonrası önbellek boş olmalı; yoksa ana ekran kartı '
              'silinen dosyanın boyutunu göstermeye devam ederdi');
    });

    test('dosya yeniden adlandırınca önbellek geçersiz kılınır', () async {
      SharedPreferences.setMockInitialValues({
        cacheKey: jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'values': {'internal': '1 GB'},
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final dir = Directory.systemTemp.createTempSync('rename_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final file = File('${dir.path}${Platform.pathSeparator}eski.txt')
        ..writeAsStringSync('y' * 16);

      await const FileService().rename(file.path, 'yeni.txt');

      expect(
          File('${dir.path}${Platform.pathSeparator}yeni.txt').existsSync(),
          isTrue);
      expect(prefs.getString(cacheKey), isNull);
    });

    test('okuma işlemleri önbelleği bozmaz (yalnızca içerik değiştirenler)',
        () async {
      SharedPreferences.setMockInitialValues({
        cacheKey: jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'values': {'internal': '1 GB'},
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final dir = Directory.systemTemp.createTempSync('readonly_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      await const FileService().listDirectory(dir.path);
      await const FileService().countChildren(dir.path);
      await const FileService().directorySize(dir.path);

      expect(prefs.getString(cacheKey), isNotNull,
          reason: 'yalnızca okuma yapan çağrılar önbelleği silmemeli');
    });
  });

  group('refresh', () {
    test('hesap boş dönerse ekrandaki etiketler SİLİNMEZ', () async {
      // Test ortamında platform kanalı yok: `storageInfo` null döner ve
      // Android olmayan platformda klasör taraması yapılmaz, yani hesap
      // boştur. Eskiden bu durum etiketleri tamamen boşaltırdı.
      CategorySizeService.labels.value =
          Map.unmodifiable({'internal': '1 GB', 'downloads': '200 MB'});

      await CategorySizeService.refresh();

      expect(CategorySizeService.labels.value['internal'], '1 GB',
          reason: 'boş hesap sonucu önceki değeri silmemeli');
      expect(CategorySizeService.labels.value['downloads'], '200 MB');
    });

    test('boş hesap önbelleğe yazılmaz (bayatlık yayılmaz)', () async {
      final prefs = await SharedPreferences.getInstance();

      await CategorySizeService.refresh();

      expect(prefs.getString(cacheKey), isNull,
          reason: 'boş sonucu "taze" yazmak sonraki açılışta da eksik '
              'etiket gösterirdi');
    });

    test('çalışırken gelen zorunlu istek yutulmaz', () async {
      // Sürerken iki kez force iste; ilki yutulmamalı (sonucu doğrudan
      // göremiyoruz, ama servis çökmemeli ve `_running` sıfırlanmalı).
      final first = CategorySizeService.refresh();
      final second = CategorySizeService.refresh(force: true);
      await Future.wait([first, second]);

      expect(CategorySizeService.running, isFalse);
      // Sonraki force çağrısı sorunsuz çalışır (pending temizlenmiş olmalı).
      await CategorySizeService.refresh(force: true);
      expect(CategorySizeService.running, isFalse);
    });
  });
}
