import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Yüklü bir uygulama (Uygulamalar ekranı için).
class InstalledApp {
  InstalledApp({
    required this.name,
    required this.packageName,
    required this.versionName,
    required this.isSystem,
    required this.size,
    required this.icon,
  });

  final String name;
  final String packageName;
  final String versionName;
  final bool isSystem;

  /// Boyut bayt; alınamazsa -1.
  final int size;

  /// PNG ikon baytları; alınamazsa null.
  final Uint8List? icon;

  factory InstalledApp.fromMap(Map<Object?, Object?> map) {
    final iconData = map['icon'];
    return InstalledApp(
      name: (map['name'] as String?) ?? '?',
      packageName: (map['packageName'] as String?) ?? '',
      versionName: (map['versionName'] as String?) ?? '',
      isSystem: (map['isSystem'] as bool?) ?? false,
      size: (map['size'] as num?)?.toInt() ?? -1,
      icon: iconData is Uint8List
          ? iconData
          : (iconData is List ? Uint8List.fromList(iconData.cast<int>()) : null),
    );
  }
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

  /// Yüklü uygulamaların listesi.
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
}
