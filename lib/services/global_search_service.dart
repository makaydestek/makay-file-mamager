import 'dart:async';
import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../models/file_entry.dart';
import '../utils/app_paths.dart';
import '../utils/debug_log.dart';
import 'platform_service.dart';
import 'transfer.dart';

/// Cihaz geneli arama sonucu türü.
enum SearchKind { file, folder, app, media }

/// Cihaz geneli arama sonucu (dosya, klasör, medya ya da yüklü uygulama).
class SearchHit {
  const SearchHit({
    required this.name,
    required this.kind,
    this.path,
    this.packageName,
    this.size = 0,
    this.modified,
    this.subtitle = '',
  });

  final String name;
  final SearchKind kind;

  /// Dosya/klasör/medya yolu; uygulamalarda null.
  final String? path;

  /// Yüklü uygulama paket adı; dosyalarda null.
  final String? packageName;

  final int size;
  final DateTime? modified;

  /// Satır altında ikincil metin (klasör yolu, paket adı, ...).
  final String subtitle;

  /// Arama ekranındaki önizleme için [FileEntry].
  ///
  /// Uygulama sonucu için döndürülmez (arayüz ikon kullanır).
  FileEntry? get asFileEntry => path == null
      ? null
      : FileEntry(
          name: name,
          path: path!,
          isDirectory: kind == SearchKind.folder,
          size: size,
          modified: modified ?? DateTime.now(),
        );
}

/// Cihaz geneli arama: dosya sistemi + yüklü uygulamalar + medya.
///
/// Sonuçlar **akış** (stream) halinde gelir; kullanıcı yazmaya devam
/// ettikçe eski arama [CancelToken] ile iptal edilir ve arayüz yalnız
/// güncel olanı gösterir.
///
/// Tarama sınırları (uçsuz gezinmeyi engeller):
///  • [maxDepth] — kökten itibaren klasör derinliği,
///  • [maxScanned] — taranan azami girdi (düzine binlerce dosyada bile
///    ekran donmaz),
///  • [maxHits] — dönen azami eşleşme,
///  • gizli (nokta) klasörler ve erişilemeyen yollar atlanır.
class GlobalSearchService {
  const GlobalSearchService();

  /// Taranacak kök klasör sayısı sınırı.
  static const int maxDepth = 7;

  /// Taranacak azami girdi (klasör + dosya).
  static const int maxScanned = 60000;

  /// Dönen azami eşleşme.
  static const int maxHits = 400;

  /// Android'de tarama kökleri; diğer platformlarda kullanıcı klasörü.
  static List<String> roots() {
    if (Platform.isAndroid) {
      return const ['/storage/emulated/0'];
    }
    return [AppPaths.scanRoot];
  }

  /// Metin eşleştirmesi: Türkçe küçük harfe duyarlı, sadeleştirilmiş.
  ///
  /// "Fotoğraf.JPG" sorgusu "fotograf" içerimiyle eşleşir (ğ→g, ç→c, ...).
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .trim();

  /// Sorgu [text] ile eşleşiyor mu? (küçük harf + Türkçe katlama)
  static bool matches(String text, String query) {
    final q = normalize(query);
    if (q.isEmpty) return false;
    return normalize(text).contains(q);
  }

  /// Dosya sistemi taraması: [onHit] ile eşleşmeler akışta bildirilir.
  ///
  /// [cancelToken] iptal edilirse tarama olabildiğince çabuk biter.
  Future<void> scanFiles(
    String query, {
    required void Function(SearchHit) onHit,
    CancelToken? cancelToken,
    List<String>? searchRoots,
    int limit = maxHits,
  }) async {
    if (query.trim().isEmpty) return;
    // Not: yerel ad statik `roots()` metodunu gölgelememeli.
    final scanRoots = searchRoots ?? roots();
    var hits = 0;
    var scanned = 0;

    // BFS: önce sığ klasörler; böylece derin tarama hızlı sonuç verir.
    final queue = <({String path, int depth})>[
      for (final r in scanRoots) (path: r, depth: 0),
    ];

    while (queue.isNotEmpty) {
      if (cancelToken?.isCancelled ?? false) return;
      if (scanned >= maxScanned || hits >= limit) return;
      final current = queue.removeAt(0);
      final dir = Directory(current.path);
      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (e) {
        // Erişilemeyen klasör atlanır (izin vb.).
        logSwallowed('global arama: liste', e);
        continue;
      }
      for (final entity in entries) {
        if (cancelToken?.isCancelled ?? false) return;
        if (scanned >= maxScanned || hits >= limit) return;
        scanned++;
        final name = _nameOf(entity);
        if (name.isEmpty || name.startsWith('.')) continue;
        final isDir = entity is Directory;
        if (matches(name, query)) {
          hits++;
          var size = 0;
          DateTime? modified;
          try {
            final stat = await entity.stat();
            size = isDir ? 0 : stat.size;
            modified = stat.modified;
          } catch (e) {
            logSwallowed('global arama: stat', e);
          }
          onHit(SearchHit(
            name: name,
            kind: isDir ? SearchKind.folder : SearchKind.file,
            path: entity.path,
            size: size,
            modified: modified,
            subtitle: _parentOf(entity.path),
          ));
        }
        // Alt klasör kuyruğa (derinlik sınırı içinde).
        if (isDir && current.depth < maxDepth) {
          queue.add((path: entity.path, depth: current.depth + 1));
        }
      }
    }
  }

  /// Yüklü uygulama araması (ad + paket adı).
  Future<void> scanApps(
    String query, {
    required void Function(SearchHit) onHit,
    int limit = 100,
  }) async {
    final apps = await PlatformService.installedApps();
    var hits = 0;
    for (final app in apps) {
      if (hits >= limit) return;
      if (matches(app.name, query) || matches(app.packageName, query)) {
        hits++;
        onHit(SearchHit(
          name: app.name,
          kind: SearchKind.app,
          packageName: app.packageName,
          size: app.size,
          subtitle: app.packageName,
        ));
      }
    }
  }

  /// Medya araması (MediaStore başlıkları: resim/video/ses dosya adları).
  ///
  /// Medya izni yoksa sessizce atlanır. Sonuçlar sayfa sayfa gelir ve
  /// eşleşmeler akışta bildirilir.
  Future<void> scanMedia(
    String query, {
    required void Function(SearchHit) onHit,
    CancelToken? cancelToken,
    int limit = 200,
  }) async {
    try {
      final state = await PhotoManager.requestPermissionExtend();
      if (!state.hasAccess) return;
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      if (paths.isEmpty) return;
      final all = paths.first;
      const pageSize = 500;
      var hits = 0;
      var loaded = 0;
      final total = await all.assetCountAsync;
      while (loaded < total) {
        if (cancelToken?.isCancelled ?? false) return;
        if (hits >= limit) return;
        final page = await all.getAssetListPaged(
          page: loaded ~/ pageSize,
          size: pageSize,
        );
        if (page.isEmpty) break;
        loaded += page.length;
        for (final asset in page) {
          if (cancelToken?.isCancelled ?? false) return;
          // photo_manager 3.x: başlık ve boyut async getter'larla okunur.
          final title = await asset.titleAsync;
          if (!matches(title, query)) continue;
          hits++;
          // Dosya yolu alınamazsa yalnız ad gösterilir.
          String? path;
          try {
            final file = await asset.originFile;
            path = file?.path;
          } catch (e) {
            logSwallowed('global arama: medya yolu', e);
          }
          if (path == null) continue;
          var size = 0;
          try {
            size = await asset.fileSize;
          } catch (e) {
            logSwallowed('global arama: medya boyut', e);
          }
          onHit(SearchHit(
            name: title,
            kind: SearchKind.media,
            path: path,
            size: size,
            modified: asset.createDateTime,
            subtitle: _parentOf(path),
          ));
        }
      }
    } catch (e) {
      logSwallowed('global arama: medya', e);
    }
  }

  /// Dosya adı (klasör uri'sinde son segment boş olabilir).
  static String _nameOf(FileSystemEntity entity) {
    final trimmed = entity.path.replaceAll(RegExp(r'[/\\]+$'), '');
    final index = trimmed.lastIndexOf(RegExp(r'[/\\]'));
    return index < 0 ? trimmed : trimmed.substring(index + 1);
  }

  /// Üst klasör yolu (satır altı gösterim).
  static String _parentOf(String path) {
    final trimmed = path.replaceAll(RegExp(r'[/\\]+$'), '');
    final index = trimmed.lastIndexOf(RegExp(r'[/\\]'));
    return index <= 0 ? '' : trimmed.substring(0, index);
  }
}
