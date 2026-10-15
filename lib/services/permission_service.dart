import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Uygulamanın ihtiyaç duyduğu cihaz izinlerinin durumu.
class PermissionStatus {
  const PermissionStatus({
    required this.allFiles,
    required this.media,
    this.usage = true,
    this.install = true,
  });

  /// Android 11+ "Tüm dosyalara erişim" (MANAGE_EXTERNAL_STORAGE).
  final bool allFiles;

  /// Granüler medya izni (Android 13+) veya READ_EXTERNAL_STORAGE (eski).
  final bool media;

  /// Kullanım erişimi (PACKAGE_USAGE_STATS): Uygulamalar ekranındaki
  /// tam boyutların (uygulama + veri) okunabilmesi için.
  final bool usage;

  /// Bilinmeyen kaynaklardan APK kurulumu (REQUEST_INSTALL_PACKAGES):
  /// indirilen APK'ların kur/güncelle ekranıyla açılabilmesi için.
  final bool install;

  /// Dosya yönetimi için gerekli izin verildi mi?
  /// "Tüm dosyalara erişim" verildiyse medya izni zaten kapsanır.
  bool get ready => allFiles || media;

  /// Açık izin gerektirenlerden kaçı verildi (0-4).
  int get grantedCount =>
      (allFiles ? 1 : 0) +
      ((media || allFiles) ? 1 : 0) +
      (usage ? 1 : 0) +
      (install ? 1 : 0);
}

/// İzin servisi: Android sistem ekranlarından izin ister ve durumu okur.
///
/// Ayarlar → İzinler ekranındaki **tüm** erişim izinleri bu servis
/// üzerinden sorgulanır/değiştirilir.
class PermissionService {
  const PermissionService._();

  static const MethodChannel _channel =
      MethodChannel('com.makay.filemanager/platform');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Desteklenmeyen platformda her izin "verilmiş" sayılır (test dahil).
  static const PermissionStatus _auto =
      PermissionStatus(allFiles: true, media: true, usage: true, install: true);

  /// Mevcut izin durumu (desteklenmeyen platformda hep "verilmiş" sayılır).
  static Future<PermissionStatus> check() async {
    if (!_supported) return _auto;
    bool allFiles = false;
    bool media = false;
    try {
      final map = await _channel.invokeMapMethod<String, bool>(
        'checkPermissions',
      );
      allFiles = map?['allFiles'] ?? false;
      media = map?['media'] ?? false;
    } catch (_) {
      // Ana kanal çalışmıyor: hiçbir izin verilmemiş sayılır.
      return const PermissionStatus(
        allFiles: false,
        media: false,
        usage: false,
        install: false,
      );
    }
    // İkincil izinler tek tek sorgulanır; biri düşerse diğeri kaybolmaz.
    var usage = false;
    try {
      usage = await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
    } catch (_) {
      usage = false;
    }
    var install = true;
    try {
      install =
          await _channel.invokeMethod<bool>('canRequestPackageInstalls') ?? true;
    } catch (_) {
      install = true;
    }
    return PermissionStatus(
      allFiles: allFiles,
      media: media,
      usage: usage,
      install: install,
    );
  }

  /// "Tüm dosyalara erişim" ayar ekranını açar (kullanıcı orada onaylar).
  static Future<PermissionStatus> requestAllFilesAccess() async {
    if (!_supported) return _auto;
    try {
      await _channel.invokeMethod<bool>('requestAllFilesAccess');
    } catch (_) {
      // Ayar ekranı açılamadı; durum yine de yeniden okunur.
    }
    return check();
  }

  /// Android'in çalışma zamanı medya izni diyaloğunu gösterir.
  static Future<PermissionStatus> requestMediaPermissions() async {
    if (!_supported) return _auto;
    try {
      await _channel.invokeMethod<bool>('requestMediaPermissions');
    } catch (_) {
      // Diyalog gösterilemedi; durum sessizce yeniden okunur.
    }
    return check();
  }

  /// "Kullanım erişimi" ayar ekranını açar ve tazelenmiş durumu verir
  /// (verilmiş izin de aynı ekrandan değiştirilebilir).
  static Future<PermissionStatus> openUsageAccess() async {
    if (!_supported) return check();
    try {
      await _channel.invokeMethod<bool>('openUsageAccessSettings');
    } catch (_) {
      // Açılamadı; durum yine de yeniden okunur.
    }
    return check();
  }

  /// "Bilinmeyen kaynaklar" (APK kurulumu) ayarını açar.
  static Future<PermissionStatus> openInstallUnknownSources() async {
    if (!_supported) return check();
    try {
      await _channel.invokeMethod<bool>('openInstallUnknownSources');
    } catch (_) {
      // Açılamadı; durum yine de yeniden okunur.
    }
    return check();
  }

  /// Uygulamanın uygulama bilgi sayfasını açar (izinleri değiştirmek için).
  static Future<PermissionStatus> openAppInfo() async {
    if (!_supported) return check();
    try {
      await _channel.invokeMethod<bool>('openAppSettings');
    } catch (_) {
      // Açılamadı; durum yine de yeniden okunur.
    }
    return check();
  }
}
