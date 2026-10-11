import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Yüklü bir uygulama (Uygulamalar ekranı için).
///
/// **İkon listede taşınmaz**: ikon üretimi bitmap rasterleştirme + PNG
/// sıkıştırmadır ve yüzlerce pakette onlarca saniye sürerdi (Android ana iş
/// parçacığında ANR'a yol açıyordu). İkon [PlatformService.appIcon] ile tek
/// tek, satır görünür olduğunda istenir.
class InstalledApp {
  const InstalledApp({
    required this.name,
    required this.packageName,
    required this.versionName,
    required this.isSystem,
    required this.size,
    required this.sourceDir,
  });

  final String name;
  final String packageName;
  final String versionName;
  final bool isSystem;

  /// Boyut bayt; alınamazsa -1.
  final int size;

  /// Kurulum APK'sının yolu (yedekleme için); alınamazsa boş.
  final String sourceDir;

  factory InstalledApp.fromMap(Map<Object?, Object?> map) => InstalledApp(
        name: (map['name'] as String?) ?? '?',
        packageName: (map['packageName'] as String?) ?? '',
        versionName: (map['versionName'] as String?) ?? '',
        isSystem: (map['isSystem'] as bool?) ?? false,
        size: (map['size'] as num?)?.toInt() ?? -1,
        sourceDir: (map['sourceDir'] as String?) ?? '',
      );
}

/// Bağlı depolama birimi (USB OTG / SD kart).
class StorageVolumeInfo {
  StorageVolumeInfo({
    required this.description,
    required this.isRemovable,
    required this.isEmulated,
    required this.path,
    required this.isMounted,
    this.state = '',
  });

  final String description;
  final bool isRemovable;

  /// Dahili (emüle edilmiş) birim mi — harici listesinden çıkarılır.
  final bool isEmulated;

  /// Erişim yolu; alınamazsa boş (ör. Android 11+ kısıtları).
  final String path;

  /// Birim "mounted" durumunda mı (kullanılabilir).
  final bool isMounted;

  /// Ham durum metni (ör. "mounted", "ejected").
  final String state;

  factory StorageVolumeInfo.fromMap(Map<Object?, Object?> map) =>
      StorageVolumeInfo(
        description: (map['description'] as String?) ?? '',
        isRemovable: (map['isRemovable'] as bool?) ?? false,
        isEmulated: (map['isEmulated'] as bool?) ?? false,
        path: (map['path'] as String?) ?? '',
        isMounted: (map['state'] as String?) == 'mounted',
        state: (map['state'] as String?) ?? '',
      );
}

/// Android platform kanalı sarmalayıcısı (StatFs, uygulama listesi).
class PlatformService {
  const PlatformService._();

  static const MethodChannel _channel =
      MethodChannel('com.makay.filemanager/platform');

  /// Kanalın çalıştığı platform (şimdilik yalnızca Android).
  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Depolama bilgisi: toplam ve boş bayt.
  static Future<({int total, int free})?> storageInfo() async {
    if (!supported) return null;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
          'getStorageInfo');
      if (map == null) return null;
      return (
        total: (map['total'] as num?)?.toInt() ?? 0,
        free: (map['free'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Yüklü uygulamaların listesi (ikonlar hariç — bkz. [appIcon]).
  static Future<List<InstalledApp>> installedApps() async {
    if (!supported) return const [];
    try {
      final list =
          await _channel.invokeListMethod<Map<Object?, Object?>>(
              'getInstalledApps');
      return (list ?? const [])
          .map(InstalledApp.fromMap)
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Tek bir uygulamanın PNG ikonu (tembel yükleme).
  ///
  /// Sonuçlar [iconCache] içinde tutulur: liste kaydırılırken aynı uygulama
  /// için ikinci kez platform çağrısı yapılmaz.
  static final Map<String, Uint8List?> _iconCache = {};

  static Uint8List? cachedIcon(String packageName) =>
      _iconCache[packageName];

  static Future<Uint8List?> appIcon(String packageName) async {
    if (!supported || packageName.isEmpty) return null;
    if (_iconCache.containsKey(packageName)) return _iconCache[packageName];
    Uint8List? bytes;
    try {
      bytes = await _channel
          .invokeMethod<Uint8List>('getAppIcon', {'packageName': packageName});
    } on PlatformException {
      bytes = null;
    } on MissingPluginException {
      bytes = null;
    }
    _iconCache[packageName] = bytes;
    return bytes;
  }

  /// Cihaz Android TV mi? (Leanback desteği var mı)
  static Future<bool> isTv() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isTv') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Android'in "Varsayılan uygulamalar" ayarını açar (A15).
  static Future<bool> openDefaultAppsSettings() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('openDefaultAppsSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Bağlı depolama birimleri (USB OTG / SD kart / dahili).
  static Future<List<StorageVolumeInfo>> storageVolumes() async {
    if (!supported) return const [];
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>(
          'getStorageVolumes');
      return (list ?? const [])
          .map(StorageVolumeInfo.fromMap)
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
