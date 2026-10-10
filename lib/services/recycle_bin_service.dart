import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/file_entry.dart';

/// Geri dönüşüm kutusu öğesi (manifest kaydı).
class RecycleItem {
  RecycleItem({
    required this.storedName,
    required this.originalPath,
    required this.name,
    required this.size,
    required this.isDirectory,
    required this.deletedAt,
  });

  final String storedName;
  final String originalPath;
  final String name;
  final int size;
  final bool isDirectory;
  final DateTime deletedAt;

  Map<String, dynamic> toJson() => {
        'storedName': storedName,
        'originalPath': originalPath,
        'name': name,
        'size': size,
        'isDirectory': isDirectory,
        'deletedAt': deletedAt.toIso8601String(),
      };

  factory RecycleItem.fromJson(Map<String, dynamic> json) => RecycleItem(
        storedName: json['storedName'] as String,
        originalPath: json['originalPath'] as String,
        name: json['name'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        isDirectory: json['isDirectory'] as bool? ?? false,
        deletedAt: DateTime.parse(json['deletedAt'] as String),
      );
}

/// Uygulama veri dizininde tutulan geri dönüşüm kutusu.
class RecycleBinService {
  RecycleBinService._();

  static final RecycleBinService instance = RecycleBinService._();

  List<RecycleItem> _items = [];
  List<RecycleItem> get items => List.unmodifiable(_items);

  Future<Directory> _binDir() async {
    final base = await getApplicationSupportDirectory();
    final dir =
        Directory('${base.path}${Platform.pathSeparator}recycle_bin');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _manifest() async {
    final dir = await _binDir();
    return File('${dir.path}${Platform.pathSeparator}manifest.json');
  }

  Future<void> load() async {
    try {
      final file = await _manifest();
      if (!await file.exists()) {
        _items = [];
        return;
      }
      final data = jsonDecode(await file.readAsString()) as List<dynamic>;
      _items = data
          .map((e) => RecycleItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _items = [];
    }
  }

  Future<void> _save() async {
    final file = await _manifest();
    await file.writeAsString(
        jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  /// Dosyayı/klasörü geri dönüşüm kutusuna taşır.
  Future<void> moveToRecycle(FileEntry entry) async {
    final bin = await _binDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final storedName = '${stamp}__${entry.name}';
    final source = FileSystemEntity.isDirectorySync(entry.path)
        ? Directory(entry.path)
        : File(entry.path);
    try {
      if (source is Directory) {
        await source.rename('${bin.path}${Platform.pathSeparator}$storedName');
      } else {
        await source.rename('${bin.path}${Platform.pathSeparator}$storedName');
      }
    } on FileSystemException {
      return; // taşınamadı (izin vb.) — silme yapılmaz.
    }
    _items.insert(
      0,
      RecycleItem(
        storedName: storedName,
        originalPath: entry.path,
        name: entry.name,
        size: entry.size,
        isDirectory: entry.isDirectory,
        deletedAt: DateTime.now(),
      ),
    );
    await _save();
  }

  /// Kutudan geri yükler: özgün konumuna döner.
  Future<void> restore(RecycleItem item) async {
    final bin = await _binDir();
    final stored = File('${bin.path}${Platform.pathSeparator}${item.storedName}');
    final storedDir = Directory(stored.path);
    final source = await stored.exists()
        ? stored
        : (await storedDir.exists() ? storedDir : null);
    if (source == null) {
      _items.remove(item);
      await _save();
      return;
    }
    final target = item.originalPath;
    try {
      final parent = Directory(target).parent;
      if (!await parent.exists()) await parent.create(recursive: true);
      await source.rename(target);
    } on FileSystemException {
      // Hedef mevcutsa ad çakışması: özgün ad + " (geri yüklendi)".
      final dot = target.lastIndexOf(Platform.pathSeparator);
      final dir = target.substring(0, dot);
      final name = target.substring(dot + 1);
      final alt = '$dir${Platform.pathSeparator}geri_$name';
      await source.rename(alt);
    }
    _items.remove(item);
    await _save();
  }

  Future<void> deletePermanently(RecycleItem item) async {
    final bin = await _binDir();
    final path = '${bin.path}${Platform.pathSeparator}${item.storedName}';
    final asDir = Directory(path);
    if (await asDir.exists()) {
      await asDir.delete(recursive: true);
    } else {
      final asFile = File(path);
      if (await asFile.exists()) await asFile.delete();
    }
    _items.remove(item);
    await _save();
  }

  Future<void> empty() async {
    final bin = await _binDir();
    await for (final entity in bin.list(followLinks: false)) {
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments[entity.uri.pathSegments.length - 1];
      if (name == 'manifest.json') continue;
      try {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else {
          await entity.delete();
        }
      } catch (_) {}
    }
    _items.clear();
    await _save();
  }

  /// Kutudaki toplam boyut.
  int get totalSize => _items.fold(0, (sum, i) => sum + i.size);
}
