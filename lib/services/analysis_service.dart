import 'dart:io';

import '../models/file_entry.dart';

/// Kategori kırılımı: kategori adı → toplam boyut (bayt).
typedef CategoryBreakdown = Map<String, int>;

/// Bellek analizi tarama servisi.
///
/// Medya ve diğer kategoriler bilinen standart klasörlerde dart:io ile
/// taranır (MANAGE_EXTERNAL_STORAGE izni ile).
class AnalysisService {
  const AnalysisService();

  /// Kategori bazlı depolama dağılımı.
  Future<CategoryBreakdown> categoryBreakdown() async {
    final result = <String, int>{};

    final root = Platform.isAndroid ? '/storage/emulated/0' : null;
    if (root != null) {
      result['Görüntüler'] = await _dirSize('$root/DCIM') +
          await _dirSize('$root/Pictures');
      result['Videolar'] = await _dirSize('$root/Movies') +
          await _dirSize('$root/WhatsApp/Media/WhatsApp Video');
      result['Ses'] = await _dirSize('$root/Music') +
          await _dirSize('$root/WhatsApp/Media/WhatsApp Audio');
      result['Belgeler'] = await _dirSize('$root/Documents') +
          await _dirSize('$root/Download');
      result['Arşivler'] = await _scanArchives(Directory(root), depth: 3);
      result['Diğerleri'] = await _dirSize('$root/Android') +
          await _dirSize('$root/WhatsApp') +
          await _dirSize('$root/Telegram');
    } else {
      result
        ..putIfAbsent('Görüntüler', () => 0)
        ..putIfAbsent('Videolar', () => 0)
        ..putIfAbsent('Ses', () => 0)
        ..putIfAbsent('Belgeler', () => 0)
        ..putIfAbsent('Arşivler', () => 0)
        ..putIfAbsent('Diğerleri', () => 0);
    }
    return result;
  }

  Future<int> _dirSize(String path) async {
    var total = 0;
    try {
      final dir = Directory(path);
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  Future<int> _scanArchives(Directory root, {int depth = 3}) async {
    var total = 0;
    const exts = {'.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz'};
    Future<void> walk(Directory dir, int left) async {
      if (left < 0) return;
      try {
        await for (final e in dir.list(followLinks: false)) {
          if (e is File) {
            final lower = e.path.toLowerCase();
            if (exts.any(lower.endsWith)) {
              try {
                total += await e.length();
              } catch (_) {}
            }
          } else if (e is Directory) {
            final name = e.uri.pathSegments.isEmpty
                ? ''
                : e.uri.pathSegments[e.uri.pathSegments.length - 2];
            if (name == 'Android' || name.startsWith('.')) continue;
            await walk(e, left - 1);
          }
        }
      } catch (_) {}
    }

    await walk(root, depth);
    return total;
  }

  /// Belirtilen boyutun üzerindeki dosyalar (sınırlı sayıda).
  ///
  /// [root] kökünden özyinelemeli taranır; [skipDirs] klasörleri atlanır.
  Future<List<FileEntry>> largeFiles({
    String root = '/storage/emulated/0',
    int minBytes = 10 * 1024 * 1024,
    int limit = 300,
    int maxDepth = 5,
  }) async {
    final found = <FileEntry>[];
    const skipDirs = {'Android', 'data', 'obb', '.thumbnails', 'LOST.DIR'};

    Future<void> walk(Directory dir, int depth) async {
      if (depth < 0 || found.length >= limit) return;
      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        return;
      }
      for (final e in entries) {
        if (found.length >= limit) return;
        final name = e.uri.pathSegments.isEmpty
            ? ''
            : e.uri.pathSegments[e.uri.pathSegments.length - 1];
        if (name.startsWith('.')) continue;
        if (e is File) {
          try {
            final len = await e.length();
            if (len >= minBytes) {
              final stat = await e.stat();
              found.add(FileEntry(
                name: name.isEmpty ? e.path : name,
                path: e.path,
                isDirectory: false,
                size: len,
                modified: stat.modified,
              ));
            }
          } catch (_) {}
        } else if (e is Directory) {
          if (skipDirs.contains(name)) continue;
          await walk(e, depth - 1);
        }
      }
    }

    await walk(Directory(root), maxDepth);
    found.sort((a, b) => b.size.compareTo(a.size));
    return found;
  }

  /// Uygulama önbellek klasörlerinin toplam boyutu (kaba tahmin).
  Future<int> cacheSize() async {
    if (!Platform.isAndroid) return 0;
    return _dirSize('/storage/emulated/0/Android/data');
  }
}
