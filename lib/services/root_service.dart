import 'dart:io';

import 'package:flutter/foundation.dart';

/// Kök (root) erişimi yardımcıları — yalnızca root'lu cihazlarda çalışır.
///
/// Root'suz cihazda `su` komutu başarısız olur; bu durumda arayüz kullanıcıya
/// anlaşılır bir mesaj gösterir ve işlem yapılmaz. Amaç: X-plore benzeri
/// dosya yöneticilerindeki "chmod" işlemini root'lu cihazlarda sunmak.
class RootService {
  RootService._();

  /// Root durumu yaşam boyunca yalnızca bir kez sorgulanır (su yavaş olabilir).
  static bool? _rooted;

  /// Root erişimi var mı? (`su -c id` çıktısında uid=0)
  static Future<bool> isRooted() async {
    final cached = _rooted;
    if (cached != null) return cached;
    if (!Platform.isAndroid) return _rooted = false;
    try {
      final result = await Process.run('su', ['-c', 'id'])
          .timeout(const Duration(seconds: 3));
      final out = '${result.stdout}${result.stderr}';
      _rooted = result.exitCode == 0 && out.contains('uid=0');
    } catch (_) {
      _rooted = false;
    }
    return _rooted!;
  }

  /// Root durumunu sıfırlar (test/yeniden deneme için).
  @visibleForTesting
  static void resetRootCache() => _rooted = null;

  /// `chmod <octal> <path>` uygular; root yoksa false döner.
  ///
  /// [octal] yalnızca 3-4 haneli sekizlik sayı olabilir (örn. '644', '0755');
  /// güvenlik için doğrulanır ve tırnak kaçışı yapılır.
  static Future<bool> chmod(String path, String octal) async {
    if (!await isRooted()) return false;
    final mode = octal.trim();
    if (!RegExp(r'^[0-7]{3,4}$').hasMatch(mode)) {
      throw FormatException('Geçersiz izin: $octal');
    }
    // Tırnak kaçışı: yol tırnak içine alınır, tırnaklar çıkarılır.
    final safePath = path.replaceAll("'", '');
    try {
      final result = await Process.run('su', ['-c', "chmod $mode '$safePath'"])
          .timeout(const Duration(seconds: 10));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Sekizlik izin → POSIX metni (örn. 0x81A4 → '-rw-r--r--').
  static String modeToString(int mode) {
    const type = {0x4000: 'd', 0x2000: 'c', 0x6000: 'b', 0xA000: 'l'};
    final prefix = type[mode & 0xF000] ?? '-';
    const bits = [0x100, 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01];
    const chars = ['r', 'w', 'x', 'r', 'w', 'x', 'r', 'w', 'x'];
    final buffer = StringBuffer(prefix);
    for (var i = 0; i < bits.length; i++) {
      buffer.write(mode & bits[i] != 0 ? chars[i] : '-');
    }
    return buffer.toString();
  }

  /// POSIX metni → sekizlik izin ('-rw-r--r--' → '644'); geçersizse null.
  static String? parseMode(String permission) {
    if (permission.length != 10) return null;
    const chars = ['r', 'w', 'x', 'r', 'w', 'x', 'r', 'w', 'x'];
    var value = 0;
    const bits = [0x100, 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01];
    for (var i = 0; i < 9; i++) {
      final c = permission[i + 1];
      if (c == '-') continue;
      if (c != chars[i]) return null;
      value |= bits[i];
    }
    return value.toRadixString(8).padLeft(3, '0');
  }
}
