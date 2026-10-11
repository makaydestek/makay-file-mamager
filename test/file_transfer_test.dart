import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/models/file_entry.dart';
import 'package:makay_file_manager/services/file_service.dart';
import 'package:makay_file_manager/services/transfer.dart';

void main() {
  late Directory temp;
  late FileService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mf_transfer_');
    service = const FileService();
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {
      // Geçici dizin silinemezse testi düşürmeyiz.
    }
  });

  File writeFile(String relative, String content) {
    final file = File('${temp.path}${Platform.pathSeparator}$relative');
    file.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  String p(String relative) => '${temp.path}${Platform.pathSeparator}$relative';

  String sepJoin(List<String> parts) => parts.join(Platform.pathSeparator);

  group('kopyalama', () {
    test('tek dosya kopyalanır ve içerik korunur', () async {
      final src = writeFile('a.txt', 'merhaba dünya');
      final destDir = Directory(p('out'));
      destDir.createSync();

      final result = await service.copyPath(src.path, destDir.path);

      expect(result.files, 1);
      // Dikkat: karakter sayısı değil **bayt** sayısı doğrulanır
      // (ü, ş gibi harfler UTF-8'de 2 bayttır).
      expect(result.bytes, utf8.encode('merhaba dünya').length);
      expect(result.cancelled, isFalse);
      final copied = File(p(sepJoin(['out', 'a.txt'])));
      expect(copied.existsSync(), isTrue);
      expect(copied.readAsStringSync(), 'merhaba dünya');
    });

    test('klasör ağacı özyinelemeli kopyalanır', () async {
      writeFile(sepJoin(['tree', 'one.txt']), '12345');
      writeFile(sepJoin(['tree', 'sub', 'two.txt']), 'abc');
      writeFile(sepJoin(['tree', 'sub', 'deep', 'three.txt']), 'xyz12');
      final destDir = Directory(p('out'));
      destDir.createSync();

      final result = await service.copyPath(p('tree'), destDir.path);

      expect(result.files, 3);
      expect(result.bytes, 5 + 3 + 5);
      final deep = File(p(sepJoin(
          ['out', 'tree', 'sub', 'deep', 'three.txt'])));
      expect(deep.readAsStringSync(), 'xyz12');
    });

    test('ilerleme bildirimleri artan sırada ve tutarlı', () async {
      for (var i = 0; i < 5; i++) {
        writeFile(sepJoin(['many', 'f$i.bin']), 'x' * 1000);
      }
      final destDir = Directory(p('out'));
      destDir.createSync();
      final seen = <TransferProgress>[];

      final result = await service.copyPath(
        p('many'),
        destDir.path,
        onProgress: seen.add,
      );

      expect(seen, isNotEmpty);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i].doneBytes, greaterThanOrEqualTo(seen[i - 1].doneBytes));
        expect(seen[i].doneFiles, greaterThanOrEqualTo(seen[i - 1].doneFiles));
      }
      expect(seen.last.doneFiles, result.files);
      expect(seen.last.doneBytes, result.bytes);
      expect(seen.last.fraction, 1.0);
      expect(seen.any((s) => s.hasTotals), isTrue);
    });

    test('ad verilirse hedefte o ad kullanılır', () async {
      final src = writeFile('a.txt', '1');
      final destDir = Directory(p('out'));
      destDir.createSync();

      await service.copyPath(src.path, destDir.path, name: 'b.txt');

      expect(
          File(p(sepJoin(['out', 'b.txt']))).existsSync(), isTrue);
    });
  });

  group('ölçüm', () {
    test('estimate dosya ve bayt sayısını verir', () async {
      writeFile(sepJoin(['est', 'one.txt']), 'aaaa');
      writeFile(sepJoin(['est', 'sub', 'two.txt']), 'bb');
      final single = writeFile('solo.txt', 'ccc');

      final counted = await service.estimate([p('est'), single.path]);

      expect(counted.files, 3);
      expect(counted.bytes, 4 + 2 + 3);
    });

    test('estimate bulunamayan yolları atlar', () async {
      final counted = await service.estimate([p('yok')]);
      expect(counted.files, 0);
      expect(counted.bytes, 0);
    });
  });

  group('iptal', () {
    test('iptal edilince TransferCancelled fırlatılır ve temizlenir', () async {
      for (var i = 0; i < 40; i++) {
        writeFile(sepJoin(['big', 'f$i.bin']), 'y' * 4096);
      }
      final destDir = Directory(p('out'));
      destDir.createSync();
      final token = CancelToken();
      var reports = 0;

      await expectLater(
        service.copyPath(
          p('big'),
          destDir.path,
          cancelToken: token,
          onProgress: (_) {
            reports++;
            token.cancel();
          },
        ),
        throwsA(isA<TransferCancelled>()),
      );

      expect(reports, greaterThan(0));
      expect(Directory(p(sepJoin(['out', 'big']))).existsSync(), isFalse);
    });

    test('önceden var olan hedef iptalde silinmez', () async {
      for (var i = 0; i < 30; i++) {
        writeFile(sepJoin(['src', 'f$i.bin']), 'z' * 4096);
      }
      final destDir = Directory(p('out'));
      destDir.createSync();
      Directory(p(sepJoin(['out', 'src']))).createSync();
      final keeper =
          File(p(sepJoin(['out', 'src', 'korumalik.txt'])));
      keeper.writeAsStringSync('beni silme');

      final token = CancelToken();
      await expectLater(
        service.copyPath(p('src'), destDir.path,
            cancelToken: token, onProgress: (_) => token.cancel()),
        throwsA(isA<TransferCancelled>()),
      );

      expect(keeper.existsSync(), isTrue);
      expect(keeper.readAsStringSync(), 'beni silme');
    });

    test('iptal belirteci tekrar çağrılabilir', () {
      final token = CancelToken();
      expect(token.isCancelled, isFalse);
      token.cancel();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });
  });

  group('taşıma', () {
    test('aynı birimde taşıma anlıktır', () async {
      final src = writeFile('m.txt', 'taşınacak');
      Directory(p('dest')).createSync();

      final result = await service.movePath(src.path, p('dest'));

      expect(src.existsSync(), isFalse);
      expect(File(p(sepJoin(['dest', 'm.txt']))).readAsStringSync(),
          'taşınacak');
      expect(result.files, 1);
      expect(result.bytes, utf8.encode('taşınacak').length);
    });

    test('moveEntry FileEntry ile çalışır', () async {
      final src = writeFile('e.txt', 'abc');
      final stat = await src.stat();
      final entry = FileEntry(
        name: 'e.txt',
        path: src.path,
        isDirectory: false,
        size: stat.size,
        modified: stat.modified,
      );
      Directory(p('dest')).createSync();

      await service.moveEntry(entry, p('dest'));

      expect(
          File(p(sepJoin(['dest', 'e.txt']))).existsSync(), isTrue);
      expect(src.existsSync(), isFalse);
    });

    test('taşıma ilerleme bildirimi verir', () async {
      final src = writeFile('p.txt', '0123456789');
      Directory(p('dest')).createSync();
      final seen = <TransferProgress>[];

      await service.movePath(src.path, p('dest'), onProgress: seen.add);

      expect(seen, isNotEmpty);
      expect(seen.last.doneBytes, 10);
      expect(seen.last.fraction, 1.0);
    });
  });

  group('kopyalama kenar durumları', () {
    test('boş dizin kopyalanır', () async {
      Directory(p('bos')).createSync();
      final destDir = Directory(p('out'));
      destDir.createSync();

      final result = await service.copyPath(p('bos'), destDir.path);

      expect(result.files, 0);
      expect(result.bytes, 0);
      expect(Directory(p(sepJoin(['out', 'bos']))).existsSync(), isTrue);
    });

    test('copyEntry adı korur', () async {
      final src = writeFile('kaynak.txt', '12');
      final stat = await src.stat();
      final entry = FileEntry(
        name: 'kaynak.txt',
        path: src.path,
        isDirectory: false,
        size: stat.size,
        modified: stat.modified,
      );
      final destDir = Directory(p('out'));
      destDir.createSync();

      await service.copyEntry(entry, destDir.path);

      expect(
        File(p(sepJoin(['out', 'kaynak.txt']))).readAsStringSync(),
        '12',
      );
    });

    test('256 KB’lık blok sınırında dosya doğru kopyalanır', () async {
      final size = FileService.chunkSize * 2 + 17;
      final bytes = List<int>.generate(size, (i) => i % 251);
      final src = File(p('buyuk.bin'));
      src.createSync(recursive: true);
      src.writeAsBytesSync(bytes);
      final destDir = Directory(p('out'));
      destDir.createSync();

      final result = await service.copyPath(src.path, destDir.path);

      final copied = File(p(sepJoin(['out', 'buyuk.bin'])));
      expect(copied.lengthSync(), size);
      expect(_equalBytes(copied.readAsBytesSync(), bytes), isTrue);
      expect(result.bytes, size);
    });
  });
}

bool _equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
