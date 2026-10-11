import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../utils/debug_log.dart';

/// Aynı içeriğe sahip 2 veya daha fazla dosyalık mükerrer grup.
class DuplicateGroup {
  const DuplicateGroup({required this.size, required this.paths});

  /// Dosyaların ortak boyutu (bayt).
  final int size;

  /// Grup içindeki dosya yolları (en az 2 adet).
  final List<String> paths;

  /// Dosya sayısı.
  int get count => paths.length;

  /// Tek kopya dışındakilerin kapladığı toplam alan (boşuna harcanan).
  int get wasted => size * (count - 1);

  Map<String, Object?> toMap() => {'size': size, 'paths': paths};

  factory DuplicateGroup.fromMap(Map<String, Object?> map) => DuplicateGroup(
        size: (map['size'] as num?)?.toInt() ?? 0,
        paths: List<String>.of(
            (map['paths'] as List?)?.cast<String>() ?? const <String>[]),
      );
}

/// Mükerrer dosya tespiti ve silme işlemleri.
///
/// Tarama izolatta (arka plan) yürütülür; arayüz donmaz. Kapanış (closure)
/// gönderilmez; üst düzey fonksiyon + istek nesnesi kullanılır; çünkü test ve
/// sanal alan gibi özel Zone'larda `Isolate.run` kapanışı "gönderilemez"
/// hatası verir (bkz. kategori boyutu taraması ve "Yeni Dosyalar" ekranı).
class DuplicateService {
  DuplicateService._();

  /// Android ana depolama kökü (uygulama tarafından tarama kökü olarak
  /// kullanılır); diğer platformlarda kök parametre olarak verilir.
  static const String androidRoot = '/storage/emulated/0';

  /// [root] altındaki mükerrer dosyaları bulur.
  ///
  /// Önce [minSize] ve üstü dosyalar boyuta göre gruplanır, aynı boyuttaki
  /// dosyalar MD5 özetiyle ayrılır; 2 veya daha fazla dosyalık gruplar en
  /// büyükten küçüğe sıralanarak döndürülür. Gizli (nokta ile başlayan)
  /// dosyalar ve `Android` klasörleri atlanır; [maxEntries] tarama işleme
  /// sınırıdır.
  static Future<List<DuplicateGroup>> find(
    String root, {
    int maxEntries = 60000,
    int minSize = 1024,
  }) async {
    final port = ReceivePort();
    try {
      await Isolate.spawn(
        _findIsolateEntry,
        _DuplicateScanRequest(
          root: root,
          maxEntries: maxEntries,
          minSize: minSize,
          reply: port.sendPort,
        ),
      );
      final raw = await port.first;
      if (raw is! List) return const [];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map((m) => DuplicateGroup.fromMap(Map<String, Object?>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    } finally {
      port.close();
    }
  }

  /// Verilen dosyaları siler; dönen değer kazanılan toplam bayttır.
  ///
  /// Erişim hataları yutulur (dosya önceden silinmiş olabilir).
  static Future<int> delete(Iterable<String> paths) async {
    var freed = 0;
    for (final path in paths) {
      try {
        final file = File(path);
        freed += await file.length();
        await file.delete();
      } catch (_) {
        // Dosya önceden silinmiş ya da erişime kapalı olabilir; kazanılan
        // alan kısmen sayılır, diğer dosyalar silinmeye devam eder.
      }
    }
    return freed;
  }
}

// ---------------------------------------------------------------------------
// İzolat çalıştırma
// ---------------------------------------------------------------------------

/// İzolata gönderilecek tarama isteği (yalnızca gönderilebilir alanlar).
class _DuplicateScanRequest {
  const _DuplicateScanRequest({
    required this.root,
    required this.maxEntries,
    required this.minSize,
    required this.reply,
  });

  final String root;
  final int maxEntries;
  final int minSize;
  final SendPort reply;
}

/// İzolat giriş noktası: kapanış yerine üst düzey fonksiyon kullanılır.
void _findIsolateEntry(_DuplicateScanRequest req) {
  try {
    req.reply.send(_findDuplicates(
      req.root,
      maxEntries: req.maxEntries,
      minSize: req.minSize,
    ));
  } catch (_) {
    req.reply.send(const <Map<String, Object?>>[]);
  }
}

// ---------------------------------------------------------------------------
// İzolat içi tarama (yalnızca dart:io + crypto kullanır)
// ---------------------------------------------------------------------------

/// [root] altındaki mükerrer grupları harita listesi olarak tarar.
List<Map<String, Object?>> _findDuplicates(
  String root, {
  required int maxEntries,
  required int minSize,
}) {
  // 1) Adaylar: [minSize] ve üstü dosyalar boyuta göre gruplanır.
  final bySize = <int, List<String>>{};
  var visited = 0;
  final stack = <String>[root];
  while (stack.isNotEmpty && visited < maxEntries) {
    final path = stack.removeLast();
    List<FileSystemEntity> items;
    try {
      items = Directory(path).listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in items) {
      if (++visited >= maxEntries) break;
      // uri.pathSegments.last dizinlerde boş döner; ad yoldan alınır.
      final name = _nameOf(e.path);
      if (name.isEmpty || name.startsWith('.')) continue; // gizli dosyalar
      if (e is Directory) {
        if (name == 'Android') continue; // sistem klasörü
        stack.add(e.path);
      } else if (e is File) {
        try {
          final size = e.lengthSync();
          if (size < minSize) continue;
          bySize.putIfAbsent(size, () => <String>[]).add(e.path);
        } catch (e) {
          logSwallowed('mükerrer: dosya boyutu', e);
        }
      }
    }
  }

  // 2) Aynı boyuttaki dosyalar MD5 özetiyle ayrılır (farklı içerikli ama
  //    aynı boyutlu dosyalar gruba girmez).
  final groups = <Map<String, Object?>>[];
  for (final entry in bySize.entries) {
    if (entry.value.length < 2) continue;
    final byHash = <String, List<String>>{};
    for (final path in entry.value) {
      try {
        final digest = _md5Of(File(path));
        if (digest.isEmpty) continue;
        byHash.putIfAbsent(digest, () => <String>[]).add(path);
      } catch (e) {
        logSwallowed('mükerrer: md5 özeti', e);
      }
    }
    for (final paths in byHash.values) {
      if (paths.length < 2) continue;
      groups.add({'size': entry.key, 'paths': paths});
    }
  }

  // 3) Boşa harcanan alana göre en büyükten küçüğe sıralanır.
  groups.sort((a, b) {
    final wastedA = (a['size'] as int) * ((a['paths'] as List).length - 1);
    final wastedB = (b['size'] as int) * ((b['paths'] as List).length - 1);
    return wastedB.compareTo(wastedA);
  });
  return groups;
}

/// Dosyanın MD5 özeti; parça parça okunur (büyük dosyalarda bellek güvenli).
String _md5Of(File file) {
  final collector = _DigestCollector();
  final sink = md5.startChunkedConversion(collector);
  final raf = file.openSync();
  try {
    final buffer = Uint8List(64 * 1024);
    int read;
    while ((read = raf.readIntoSync(buffer)) > 0) {
      sink.add(buffer.sublist(0, read));
    }
  } finally {
    raf.closeSync();
  }
  sink.close();
  return collector.value?.toString() ?? '';
}

/// MD5 özetini toplayan basit sink (crypto paketi bunu dışa aktarmaz).
class _DigestCollector implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Yolun son ögesi (dosya/dizin adı); ayraç farklarını yutar.
String _nameOf(String path) {
  final sep = Platform.pathSeparator;
  final normalized = sep == '/' ? path : path.replaceAll('/', sep);
  final parts = normalized.split(sep);
  for (var i = parts.length - 1; i >= 0; i--) {
    if (parts[i].isNotEmpty) return parts[i];
  }
  return '';
}
