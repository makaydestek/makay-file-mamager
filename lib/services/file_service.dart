import 'dart:io';

import '../models/file_entry.dart';

/// Dosya sistemi okuma/yazma işlemleri.
class FileService {
  const FileService();

  /// Bir dizini listeler; gizli dosyalar (nokta ile başlayanlar) atlanır.
  Future<List<FileEntry>> listDirectory(
    String path, {
    bool showHidden = false,
  }) async {
    final dir = Directory(path);
    if (!await dir.exists()) return const [];
    final entries = <FileEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments[entity.uri.pathSegments.length - 1];
      final cleanName = name.isEmpty ? entity.path.split(Platform.pathSeparator).last : name;
      if (!showHidden && cleanName.startsWith('.')) continue;
      try {
        final stat = await entity.stat();
        entries.add(FileEntry(
          name: cleanName,
          path: entity.path,
          isDirectory: entity is Directory,
          size: stat.size,
          modified: stat.modified,
        ));
      } catch (_) {
        // Erişilemeyen girdiler atlanır (izin vb.).
      }
    }
    return entries;
  }

  /// Klasör içindeki alt öğe sayısı.
  Future<int> countChildren(String path) async {
    try {
      final dir = Directory(path);
      var count = 0;
      await for (final _ in dir.list(followLinks: false)) {
        count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Klasörün özyinelemeli toplam boyutu (dosyalar).
  Future<int> directorySize(String path) async {
    var total = 0;
    try {
      final dir = Directory(path);
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> createDirectory(String path) => Directory(path).create();

  Future<void> rename(String path, String newName) async {
    final entity = FileSystemEntity.isDirectorySync(path)
        ? Directory(path)
        : File(path);
    final parent = entity.parent.path;
    await entity.rename('$parent${Platform.pathSeparator}$newName');
  }

  Future<void> copyEntry(FileEntry entry, String targetDir) =>
      copyPath(entry.path, targetDir, name: entry.name);

  /// Yol tabanlı kopyalama (sürükle-bırak / paneller arası).
  Future<void> copyPath(
    String source,
    String targetDir, {
    String? name,
  }) async {
    final sourceName = source.split(Platform.pathSeparator).last;
    final target = '$targetDir${Platform.pathSeparator}${name ?? sourceName}';
    final sourceEntity = Directory(source);
    if (sourceEntity.existsSync()) {
      await _copyDir(sourceEntity, Directory(target));
    } else {
      await File(source).copy(target);
    }
  }

  Future<void> _copyDir(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments[entity.uri.pathSegments.length - 1];
      final newPath =
          '${destination.path}${Platform.pathSeparator}${entity.uri.pathSegments.isEmpty ? '' : name}';
      if (entity is Directory) {
        await _copyDir(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  Future<void> moveEntry(FileEntry entry, String targetDir) async {
    final target = '$targetDir${Platform.pathSeparator}${entry.name}';
    try {
      await File(entry.path).rename(target);
    } on FileSystemException {
      // Bazı durumlarda (farklı birimler) kopyala+sil gerekir.
      await copyEntry(entry, targetDir);
      await deleteEntry(entry.path, useRecycleBin: false);
    }
  }

  /// Kalıcı silme veya geri dönüşüm kutusuna taşıma.
  /// Geri dönüşüm entegrasyonu RecycleBinService tarafından sağlanır.
  Future<void> deleteEntry(String path, {bool useRecycleBin = false}) async {
    if (useRecycleBin) {
      // Geri dönüşüm mantığı RecycleBinService.moveToRecycle ile yapılır;
      // buraya gelindiyette kalıcı silinir.
    }
    final entity =
        FileSystemEntity.isDirectorySync(path) ? Directory(path) : File(path);
    if (entity is Directory) {
      await entity.delete(recursive: true);
    } else {
      await entity.delete();
    }
  }
}
