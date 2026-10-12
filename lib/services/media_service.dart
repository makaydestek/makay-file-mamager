import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../utils/debug_log.dart';
import 'category_size_service.dart';

/// Bir medya albümü (klasör).
class MediaAlbum {
  MediaAlbum({
    required this.id,
    required this.name,
    required this.count,
  });

  final String id;
  final String name;
  final int count;
}

/// Medya tarama servisi (photo_manager / MediaStore).
///
/// **Kategori ayrımı servis düzeyinde yapılır:** Resimler ekranında yalnız
/// resim, Videolar ekranında yalnız video, Ses ekranında yalnız ses
/// dosyaları listelenir. photo_manager kimi cihazlarda klasör albümlerinde
/// (ve "Tümü" albümünde) karışık varlık döndürür; buradaki [matches]
/// süzgeci bunu ekrana yansıtmadan engeller.
///
/// **"Tümü" albümü adı:** photo_manager bunu cihaz diline göre "Recent" /
/// "All" olarak adlandırır; uygulama dili Türkçe olduğu için uygulamada
/// **"Tüm Dosyalar"** yazısı gösterilir.
class MediaService {
  const MediaService();

  /// Bir albüm sayfası için istenen varlık sayısı.
  static const int pageSize = 500;

  /// Bir albümde bellekte tutulacak azami varlık (güvenlik sınırı).
  ///
  /// Aşılırsa sayaç `assetCountAsync` değerine düşer ve liste yine de
  /// sayfa sayfa sunulur.
  static const int maxAlbumAssets = 20000;

  /// photo_manager "Tümü" albümünün gösterilecek adı.
  static const String allAlbumTitle = 'Tüm Dosyalar';

  /// photo_manager "Tümü" albümünün cihaz diline göre olası adları.
  ///
  /// Türkçe ("Tümü", "Tüm Öğeler"), İngilizce ("Recent", "All") ve birkaç
  /// yaygın yerel ad burada tanınır; tanınmayan ad olduğu gibi korunur.
  static const Set<String> _allAlbumAliases = {
    'recent',
    'all',
    'all media',
    'all items',
    'recent items',
    'camera roll',
    'galeri',
    'tümü',
    'tüm öğeler',
    'tüm medya',
    'son',
    'son öğeler',
  };

  /// Desteklenen platform (Android/iOS); diğerlerinde false.
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// İzin durumunu kontrol eder; gerekirse izin ister.
  Future<bool> ensurePermission({bool request = true}) async {
    final state = await PhotoManager.requestPermissionExtend();
    if (state.hasAccess) return true;
    if (!request) return false;
    return PhotoManager.requestPermissionExtend().then((s) => s.hasAccess);
  }

  RequestType _typeFor(String categoryId) => switch (categoryId) {
        'images' => RequestType.image,
        'videos' => RequestType.video,
        'audio' => RequestType.audio,
        _ => RequestType.common,
      };

  /// Varlık istenen kategoriye ait mi? (Resim/Videolar/Ses ayrımı)
  static bool matches(AssetEntity asset, String categoryId) =>
      switch (categoryId) {
        'images' => asset.type == AssetType.image,
        'videos' => asset.type == AssetType.video,
        'audio' => asset.type == AssetType.audio,
        _ => true,
      };

  /// Albüm adı: "Tümü" albümü (photo_manager `isAll`) ve onun bilinen
  /// takma adları "Tüm Dosyalar" olarak gösterilir.
  static String albumTitle(AssetPathEntity path) {
    final name = path.name.trim();
    if (path.isAll) return allAlbumTitle;
    if (_allAlbumAliases.contains(name.toLowerCase())) return allAlbumTitle;
    return name;
  }

  /// Kategoriye göre albümleri getirir (ad, adet).
  ///
  /// Sayı, kategori süzgecinden **geçmiş** varlık sayısıdır; bir klasörde
  /// hem resim hem video varsa Resimler ekranındaki adet yalnız resimleri
  /// sayar. "Tüm Dosyalar" albümü her zaman listenin başında yer alır.
  Future<List<MediaAlbum>> albums(String categoryId) async {
    final paths = await PhotoManager.getAssetPathList(
      type: _typeFor(categoryId),
      onlyAll: false,
    );
    final albums = <MediaAlbum>[];
    for (final path in paths) {
      final assets = await _loadAll(path, categoryId);
      var count = assets.length;
      if (assets.length >= maxAlbumAssets) {
        // Güvenlik sınırına ulaşıldı: sayı MediaStore sayacıyla tamamlanır.
        try {
          count = await path.assetCountAsync;
        } catch (e) {
          logSwallowed('medya: albüm sayısı', e);
        }
      }
      if (count == 0) continue;
      albums.add(MediaAlbum(
        id: path.id,
        name: albumTitle(path),
        count: count,
      ));
    }
    // "Tüm Dosyalar" en başta, diğerleri alfabetik.
    albums.sort((a, b) {
      final aAll = a.name == allAlbumTitle;
      final bAll = b.name == allAlbumTitle;
      if (aAll != bAll) return aAll ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return albums;
  }

  /// Albümün varlıklarını sayfa sayfa getirir (yalnız istenen kategori).
  ///
  /// [offset] kategori süzgecinden **geçmiş** indekstir; bu yüzden önceki
  /// sayfaların süzülmesi kaybolan öğeye yol açmaz. Sonuç, albüm önbelleğinden
  /// (ilk çağrıda doldurulur) verildiği için art arda çağrılar tutarlıdır.
  Future<List<AssetEntity>> assets(
    String albumId, {
    String categoryId = '',
    int offset = 0,
    int size = 200,
  }) async {
    final list = await _cachedAssets(albumId, categoryId);
    if (offset >= list.length) return const [];
    final end = math.min(offset + size, list.length);
    return list.sublist(offset, end);
  }

  /// Varlığın kare küçük resmi.
  Future<Uint8List?> thumbnail(AssetEntity asset, {int size = 400}) async {
    return asset.thumbnailDataWithSize(ThumbnailSize(size, size));
  }

  /// Varlığın bayt boyutu; bilinmiyorsa 0.
  ///
  /// photo_manager'da `AssetEntity.size` **piksel boyutu**dur; bayt boyutu
  /// [AssetEntity.fileSize] ile asenkron alınır. Bu yüzden değer
  /// [resolveSize] ile ilk çözüldüğünde önbelleğe yazılır ve toplamlar
  /// buradan okunur.
  static int sizeOf(AssetEntity asset) => _sizeCache[asset.id] ?? 0;

  /// Varlığın bayt boyutunu asenkron çözüp önbelleğe yazar.
  static Future<int> resolveSize(AssetEntity asset) async {
    final cached = _sizeCache[asset.id];
    if (cached != null) return cached;
    var bytes = 0;
    try {
      bytes = await asset.fileSize;
    } catch (e) {
      logSwallowed('medya: boyut', e);
    }
    _sizeCache[asset.id] = bytes;
    return bytes;
  }

  /// Varlıkların toplam boyutu; çözülmüş değerler kullanılır.
  ///
  /// Albüm listelerinde toplam, önceden [resolveSize] ile çözülmüş boyutların
  /// toplamıdır (eksikler 0 sayılır) — ana iş parçacığı asla dosya boyutu
  /// okumak için durmaz.
  static int totalSizeOf(Iterable<AssetEntity> assets) =>
      assets.fold<int>(0, (sum, a) => sum + sizeOf(a));

  /// Bir albümün tüm varlıklarının boyutlarını arka planda çözer.
  ///
  /// Sonuç [totalSizeOf] ile okunur; ekran boyutlar hazır oldukça sessizce
  /// tazelenir.
  static Future<void> resolveSizes(List<AssetEntity> assets) async {
    for (final asset in assets) {
      if (_sizeCache.containsKey(asset.id)) continue;
      await resolveSize(asset);
    }
  }

  /// Seçili varlıkları MediaStore'dan siler ve önbellekleri tazeler.
  ///
  /// Android 11+ sistem onay diyaloğu gösterebilir; kullanıcı vazgeçerse
  /// silinen kimlik listesi boş döner ve false dönülür.
  Future<bool> deleteAssets(List<String> ids) async {
    if (ids.isEmpty) return true;
    List<String> deleted;
    try {
      deleted = await PhotoManager.editor.deleteWithIds(ids);
    } catch (e) {
      logSwallowed('medya: silme', e);
      return false;
    }
    // Önbellek tazelenir: albüm listelerinden silinenler DÜŞÜRÜLÜR (sayfa
    // kaydırmalarının yerini kaybetmemesi için), kapak küçük resimleri ve
    // boyut kayıtları tamamen silinir.
    final removed = (deleted.isEmpty ? ids : deleted).toSet();
    _cache.updateAll(
      (_, assets) =>
          assets.where((a) => !removed.contains(a.id)).toList(growable: false),
    );
    _thumbCache.clear();
    for (final id in removed) {
      _sizeCache.remove(id);
    }
    // Ana ekran kategori etiketleri tazelenmeli (dosya sayısı/boyutu düştü).
    await CategorySizeService.invalidate();
    return deleted.isNotEmpty;
  }

  /// Önbellekleri siler (yenileme/temizleme sonrası çağrılır).
  static void clearCache() {
    _cache.clear();
    _thumbCache.clear();
    _sizeCache.clear();
  }

  // -------------------------------------------------------------------------
  // Önbellek
  // -------------------------------------------------------------------------

  static final Map<String, List<AssetEntity>> _cache = {};

  /// Küçük resim önbelleği (medya kategori ekranı albüm kapakları).
  static final Map<String, Uint8List?> _thumbCache = {};

  /// Varlık bayt boyutları önbelleği (asset kimliği → bayt).
  static final Map<String, int> _sizeCache = {};

  static Future<List<AssetEntity>> _cachedAssets(
    String albumId,
    String categoryId,
  ) async {
    final key = '$categoryId|$albumId';
    final cached = _cache[key];
    if (cached != null) return cached;
    AssetPathEntity? path;
    try {
      path = await AssetPathEntity.fromId(albumId);
    } catch (e) {
      logSwallowed('medya: albüm açma', e);
    }
    if (path == null) return const [];
    final assets = await _loadAll(path, categoryId);
    _cache[key] = assets;
    return assets;
  }

  /// Albümün tüm varlıklarını sayfa sayfa okur ve kategori süzgecinden
  /// geçirir. Sonuç, sonraki [assets] çağrıları için önbelleklenir.
  static Future<List<AssetEntity>> _loadAll(
    AssetPathEntity path,
    String categoryId,
  ) async {
    final key = '$categoryId|${path.id}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final out = <AssetEntity>[];
    var page = 0;
    while (out.length < maxAlbumAssets) {
      List<AssetEntity> batch;
      try {
        batch = await path.getAssetListPaged(page: page, size: pageSize);
      } catch (e) {
        logSwallowed('medya: albüm sayfası', e);
        break;
      }
      out.addAll(batch.where((a) => matches(a, categoryId)));
      if (batch.length < pageSize) break;
      page++;
    }
    _cache[key] = out;
    return out;
  }

  /// Küçük resim önbelleği erişimi (kategori ekranı kullanır).
  static Uint8List? cachedThumb(String key) => _thumbCache[key];

  static void cacheThumb(String key, Uint8List? data) => _thumbCache[key] = data;
}
