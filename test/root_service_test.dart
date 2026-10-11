import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/services/root_service.dart';

/// Kök yardımcıları: izin metni ↔ sekizlik dönüşümü ve chmod doğrulaması.
void main() {
  test('modeToString POSIX biçimi üretir', () {
    // regular file 0644 (-rw-r--r--): tür 0x8000 + 0644
    expect(RootService.modeToString(0x8000 | 0x1A4), '-rw-r--r--');
    // directory 0755 (drwxr-xr-x)
    expect(RootService.modeToString(0x4000 | 0x1ED), 'drwxr-xr-x');
    // regular file 0600 (sadece sahibi)
    expect(RootService.modeToString(0x8000 | 0x180), '-rw-------');
    // regular file 0777
    expect(RootService.modeToString(0x8000 | 0x1FF), '-rwxrwxrwx');
  });

  test('parseMode POSIX metnini sekizliğe çevirir', () {
    expect(RootService.parseMode('-rw-r--r--'), '644');
    expect(RootService.parseMode('drwxr-xr-x'), '755');
    expect(RootService.parseMode('-rw-------'), '600');
    expect(RootService.parseMode('-rwxrwxrwx'), '777');
  });

  test('modeToString ↔ parseMode geri dönüşümlüdür', () {
    const modes = [0x1A4, 0x1ED, 0x180, 0x1FF, 0x1C0];
    for (final m in modes) {
      final text = RootService.modeToString(0x8000 | m);
      expect(RootService.parseMode(text), m.toRadixString(8).padLeft(3, '0'));
    }
  });

  test('parseMode geçersiz girdide null döner', () {
    expect(RootService.parseMode(''), isNull);
    expect(RootService.parseMode('-rw-r--r'), isNull); // 9 karakter
    expect(RootService.parseMode('-rw-z--r--'), isNull); // geçersiz karakter
    expect(RootService.parseMode('drwxr-xrww'), isNull); // son hane 'x' olmalı
    expect(RootService.parseMode('xxxxxxxxxx'), isNull);
  });

  test('chmod root olmayan ortamda false döner ve geçersiz modu reddeder',
      () async {
    // Test ortamında (Windows/Linux, root'suz) isRooted false olmalı;
    // FormatException yine de fırlanmadan önce rooted kontrolü yapılır.
    RootService.resetRootCache();
    final rooted = await RootService.isRooted();
    if (!rooted) {
      expect(await RootService.chmod('/tmp/x', '644'), isFalse);
    } else {
      // Root'lu ortamda geçersiz mod hâlâ reddedilir.
      expect(
        () => RootService.chmod('/tmp/x', '999'),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
