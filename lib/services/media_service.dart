import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

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
class MediaService {
  const MediaService();

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

  /// Kategoriye göre albümleri getirir (ad, adet).
  Future<List<MediaAlbum>> albums(String categoryId) async {
    final paths = await PhotoManager.getAssetPathList(
      type: _typeFor(categoryId),
      onlyAll: false,
    );
    final albums = <MediaAlbum>[];
    for (final path in paths) {
      final count = await path.assetCountAsync;
      if (count == 0) continue;
      albums.add(MediaAlbum(
        id: path.id,
        name: path.name,
        count: count,
      ));
    }
    return albums;
  }

  /// Albümün varlıklarını sayfa sayfa getirir.
  Future<List<AssetEntity>> assets(
    String albumId, {
    int page = 0,
    int size = 200,
  }) async {
    final path = await AssetPathEntity.fromId(albumId);
    return path.getAssetListPaged(page: page, size: size);
  }

  /// Varlığın kare küçük resmi.
  Future<Uint8List?> thumbnail(AssetEntity asset, {int size = 400}) async {
    return asset.thumbnailDataWithSize(ThumbnailSize(size, size));
  }
}
