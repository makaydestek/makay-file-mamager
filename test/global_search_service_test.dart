import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/services/global_search_service.dart';
import 'package:makay_file_manager/services/transfer.dart';

/// Cihaz geneli arama servisi:
///
///  • Türkçe duyarlı eşleştirme ("Fotograf" ↔ "Fotoğraf"),
///  • dosya sistemi BFS taraması (derinlik + gizli dosya atlaması),
///  • CancelToken ile erken iptal.
void main() {
  const service = GlobalSearchService();

  group('matches / normalize', () {
    test('büyük-küçük harf duyarsız', () {
          expect(GlobalSearchService.matches('Rapor.PDF', 'rapor'), isTrue);
          expect(GlobalSearchService.matches('Rapor.PDF', 'RAPOR'), isTrue);
        });

        test('Türkçe karakterleri katlar (ğ→g, ç→c, ı→i)', () {
          expect(
            GlobalSearchService.matches('Fotoğraf 2026.jpg', 'fotograf'),
            isTrue,
          );
          expect(
            GlobalSearchService.matches('çıkar.zip', 'cikar'),
            isTrue,
          );
          expect(
            GlobalSearchService.matches('Irmak.mp3', 'irmak'),
            isTrue,
          );
        });

        test('boş sorgu eşleşmez', () {
          expect(GlobalSearchService.matches('hersey.txt', '   '), isFalse);
          expect(GlobalSearchService.matches('hersey.txt', ''), isFalse);
        });

        test('içermeyen ad eşleşmez', () {
          expect(GlobalSearchService.matches('sunucu.log', 'fatura'), isFalse);
        });
  });

  group('scanFiles', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('global_search_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('eşleşen dosya ve klasörleri akışta bildirir', () async {
      File('${root.path}/Fatura_2026.pdf').writeAsStringSync('x');
      Directory('${root.path}/Faturalar').createSync();
      File('${root.path}/fotograf.jpg').writeAsStringSync('x');
      File('${root.path}/eşleşmeyen.txt').writeAsStringSync('x');

      final hits = <SearchHit>[];
      await service.scanFiles(
        'fatura',
        onHit: hits.add,
        searchRoots: [root.path],
      );

      final names = hits.map((h) => h.name).toSet();
      expect(names, contains('Fatura_2026.pdf'));
      expect(names, contains('Faturalar'));
      expect(names, isNot(contains('eşleşmeyen.txt')));
      // Klasör sonucu türe göre ayrılır.
      final folder = hits.firstWhere((h) => h.name == 'Faturalar');
      expect(folder.kind, SearchKind.folder);
      // Dosya sonucu boyut ve üst yol taşır.
      final file = hits.firstWhere((h) => h.name == 'Fatura_2026.pdf');
      expect(file.kind, SearchKind.file);
      expect(file.size, greaterThan(0));
      expect(file.subtitle, root.path);
    });

    test('nokta ile başlayan gizli dosyalar atlanır', () async {
      File('${root.path}/.gizli_fatura.pdf').writeAsStringSync('x');
      File('${root.path}/gorunur_fatura.pdf').writeAsStringSync('x');

      final hits = <SearchHit>[];
      await service.scanFiles(
        'fatura',
        onHit: hits.add,
        searchRoots: [root.path],
      );

      expect(hits.map((h) => h.name), ['gorunur_fatura.pdf']);
    });

    test('limit dolunca yeni eşleşme üretmez', () async {
      for (var i = 0; i < 10; i++) {
        File('${root.path}/kayit_$i.txt').writeAsStringSync('x');
      }

      final hits = <SearchHit>[];
      await service.scanFiles(
        'kayit',
        onHit: hits.add,
        searchRoots: [root.path],
        limit: 3,
      );

      expect(hits.length, 3);
    });

    test('önceden iptal edilen token ile hiç eşleşme gelmez', () async {
      File('${root.path}/kayit.txt').writeAsStringSync('x');
      final token = CancelToken()..cancel();

      final hits = <SearchHit>[];
      await service.scanFiles(
        'kayit',
        onHit: hits.add,
        cancelToken: token,
        searchRoots: [root.path],
      );

      expect(hits, isEmpty);
    });

    test('alt klasörlerdeki dosyalar da bulunur', () async {
      final sub = Directory('${root.path}/derin/alt')..createSync(recursive: true);
      File('${sub.path}/proje_planı.md').writeAsStringSync('x');

      final hits = <SearchHit>[];
      await service.scanFiles(
        'proje',
        onHit: hits.add,
        searchRoots: [root.path],
      );

      expect(hits.single.name, 'proje_planı.md');
    });
  });
}
