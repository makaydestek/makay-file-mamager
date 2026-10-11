import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/services/vault_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kasa hizmeti: PIN/anahtar, AES-256-GCM şifreleme, dışa aktarma,
/// yeniden şifreleme ve sıfırlama akışları.
void main() {
  late Directory root;
  late Directory outside;

  setUp(() {
    root = Directory.systemTemp.createTempSync('vault_');
    outside = Directory.systemTemp.createTempSync('vault_src_');
    VaultService.debugRoot = root.path;
    // SharedPreferences, setMockInitialValues çağrısından sonra hazırlanır.
    SharedPreferences.setMockInitialValues({});
    VaultService.lock();
  });

  tearDown(() {
    VaultService.lock();
    VaultService.debugRoot = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (outside.existsSync()) outside.deleteSync(recursive: true);
  });

  File makeSource(String name, String content) {
    final file = File('${outside.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync(content);
    return file;
  }

  test('create → unlocked; add → listede 1 kayıt, ad/boyut doğru',
      () async {
    expect(await VaultService.isConfigured(), isFalse);
    await VaultService.create('1234');
    expect(VaultService.unlocked, isTrue);
    expect(await VaultService.isConfigured(), isTrue);

    final source = makeSource('belge.txt', 'x' * 500);
    final entry = await VaultService.add(source);

    final items = await VaultService.list();
    expect(items, hasLength(1));
    expect(items.first.id, entry.id);
    expect(items.first.name, 'belge.txt');
    expect(items.first.size, 500);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('kasa dosyası şifreli; kaynak dosya yerinde kalır', () async {
    await VaultService.create('4321');
    const content = 'gizli-kasa-icerigi';
    final source = makeSource('sir.txt', content);
    await VaultService.add(source);

    final encFiles = root
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.enc'))
        .toList();
    expect(encFiles, hasLength(1));
    final enc = await encFiles.first.readAsBytes();
    // Şifreli gövde düz metin içermez ve GCM/nonce başlığı nedeniyle
    // orijinal içerikten daha uzundur.
    expect(enc, isNot(Uint8List.fromList(content.codeUnits)));
    expect(String.fromCharCodes(enc.where((b) => b >= 0x20 && b < 0x7f))
        .contains(content),
        isFalse);
    expect(enc.length, greaterThan(content.length));

    expect(source.existsSync(), isTrue);
    expect(source.readAsStringSync(), content);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('kilitsizken list throws; yanlış PIN false, doğru PIN true',
      () async {
    await VaultService.create('9876');
    VaultService.lock();
    expect(VaultService.unlocked, isFalse);

    await expectLater(VaultService.list(), throwsA(isA<StateError>()));

    expect(await VaultService.unlock('0000'), isFalse);
    expect(VaultService.unlocked, isFalse);
    expect(await VaultService.unlock('9876'), isTrue);
    expect(VaultService.unlocked, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('exportTo çözülen baytları orijinalle birebir aynı', () async {
    await VaultService.create('1357');
    final bytes = List<int>.generate(300, (i) => i % 251);
    final source = File('${outside.path}${Platform.pathSeparator}veri.bin')
      ..writeAsBytesSync(bytes);
    final entry = await VaultService.add(source);

    final dest = Directory('${outside.path}${Platform.pathSeparator}disa');
    final out = await VaultService.exportTo(entry.id, dest.path);

    expect(out.readAsBytesSync(), bytes);
    expect(out.path.endsWith('veri.bin'), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('remove sonrası kayıt listeden düşer', () async {
    await VaultService.create('2468');
    final a = await VaultService.add(makeSource('a.txt', 'aaa'));
    await VaultService.add(makeSource('b.txt', 'bbb'));
    expect(await VaultService.list(), hasLength(2));

    await VaultService.remove(a.id);

    final items = await VaultService.list();
    expect(items, hasLength(1));
    expect(items.single.name, 'b.txt');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('changePin sonrası eski PIN açmaz, yeni PIN açar ve dosya çözülür',
      () async {
    await VaultService.create('1111');
    final content = 'yeniden-sifrelenmis';
    final entry =
        await VaultService.add(makeSource('not.txt', content));

    await VaultService.changePin('1111', '9999');

    VaultService.lock();
    expect(await VaultService.unlock('1111'), isFalse,
        reason: 'eski PIN artık çalışmamalı');
    expect(await VaultService.unlock('9999'), isTrue);

    final items = await VaultService.list();
    expect(items.single.name, 'not.txt');
    final out = await VaultService.exportTo(
        entry.id, '${outside.path}${Platform.pathSeparator}cp');
    expect(out.readAsStringSync(), content);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('reset sonrası isConfigured false ve kasa dizini silinir', () async {
    await VaultService.create('5555');
    await VaultService.add(makeSource('kayip.txt', 'zzz'));
    expect(await VaultService.isConfigured(), isTrue);

    await VaultService.reset();

    expect(await VaultService.isConfigured(), isFalse);
    expect(VaultService.unlocked, isFalse);
    expect(root.existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
