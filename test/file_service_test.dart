import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/models/file_entry.dart';
import 'package:makay_file_manager/services/file_service.dart';
import 'package:makay_file_manager/utils/formats.dart';

void main() {
  const service = FileService();
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('makay_test_');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('listDirectory klasör ve dosyaları listeler, gizli dosyaları atlar',
      () async {
    File('${temp.path}/dosya.txt').writeAsStringSync('merhaba');
    Directory('${temp.path}/klasor').createSync();
    File('${temp.path}/.gizli').writeAsStringSync('x');

    final entries = await service.listDirectory(temp.path);
    final names = entries.map((e) => e.name).toList()..sort();

    expect(names, ['dosya.txt', 'klasor']);
    expect(entries.firstWhere((e) => e.name == 'klasor').isDirectory, isTrue);
    expect(entries.firstWhere((e) => e.name == 'dosya.txt').isDirectory,
        isFalse);
  });

  test('createDirectory + rename çalışır', () async {
    final dir = '${temp.path}/yeni';
    await service.createDirectory(dir);
    expect(Directory(dir).existsSync(), isTrue);

    final file = File('${temp.path}/a.txt')..writeAsStringSync('1');
    await service.rename(file.path, 'b.txt');
    expect(File('${temp.path}/b.txt').existsSync(), isTrue);
  });

  test('copyEntry dosyayı kopyalar', () async {
    final src = File('${temp.path}/kaynak.txt')..writeAsStringSync('içerik');
    final target = Directory('${temp.path}/hedef')..createSync();
    final entry = FileEntry(
      name: 'kaynak.txt',
      path: src.path,
      isDirectory: false,
      size: 7,
      modified: DateTime.now(),
    );
    await service.copyEntry(entry, target.path);
    expect(File('${target.path}/kaynak.txt').readAsStringSync(), 'içerik');
    expect(src.existsSync(), isTrue); // kopya silmez
  });

  test('deleteEntry kalıcı siler', () async {
    final file = File('${temp.path}/sil.txt')..writeAsStringSync('x');
    await service.deleteEntry(file.path, useRecycleBin: false);
    expect(file.existsSync(), isFalse);
  });

  test('FileEntry tür algılama', () {
    FileEntry make(String name, {bool dir = false}) => FileEntry(
          name: name,
          path: '/tmp/$name',
          isDirectory: dir,
          size: 0,
          modified: DateTime.now(),
        );
    expect(make('a.jpg').kind, FileKind.image);
    expect(make('a.mp4').kind, FileKind.video);
    expect(make('a.mp3').kind, FileKind.audio);
    expect(make('a.pdf').kind, FileKind.document);
    expect(make('a.zip').kind, FileKind.archive);
    expect(make('a.apk').kind, FileKind.apk);
    expect(make('a.bin').kind, FileKind.other);
    expect(make('klasor', dir: true).kind, FileKind.folder);
  });

  test('Formats.size okunabilir değer üretir', () {
    expect(Formats.size(0), '0 B');
    expect(Formats.size(1024), '1 KB');
    expect(Formats.size(1024 * 1024 * 5), '5 MB');
    expect(Formats.size(1536), '1,5 KB');
  });
}
