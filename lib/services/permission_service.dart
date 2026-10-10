import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Uygulamanın ihtiyaç duyduğu cihaz izinlerinin durumu.
class PermissionStatus {
  const PermissionStatus({required this.allFiles, required this.media});

  /// Android 11+ "Tüm dosyalara erişim" (MANAGE_EXTERNAL_STORAGE).
  final bool allFiles;

  /// Granüler medya izni (Android 13+) veya READ_EXTERNAL_STORAGE (eski).
  final bool media;

  /// Dosya yönetimi için gerekli izin verildi mi?
  /// "Tüm dosyalara erişim" verildiyse medya izni zaten kapsanır.
  bool get ready => allFiles || media;
}

/// İzin servisi: Android sistem ekranlarından izin ister ve durumu okur.
class PermissionService {
  const PermissionService._();

  static const MethodChannel _channel =
      MethodChannel('com.makay.filemanager/platform');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Mevcut izin durumu (desteklenmeyen platformda hep "verilmiş" sayılır).
  static Future<PermissionStatus> check() async {
    if (!_supported) return const PermissionStatus(allFiles: true, media: true);
    try {
      final map = await _channel.invokeMapMethod<String, bool>(
        'checkPermissions',
      );
      if (map == null) {
        return const PermissionStatus(allFiles: true, media: true);
      }
      return PermissionStatus(
        allFiles: map['allFiles'] ?? false,
        media: map['media'] ?? false,
      );
    } catch (_) {
      return const PermissionStatus(allFiles: false, media: false);
    }
  }

  /// "Tüm dosyalara erişim" ayar ekranını açar (kullanıcı orada onaylar).
  static Future<PermissionStatus> requestAllFilesAccess() async {
    if (!_supported) return const PermissionStatus(allFiles: true, media: true);
    try {
      await _channel.invokeMethod<bool>('requestAllFilesAccess');
    } catch (_) {
      // Ayar ekranı açılamadı; durum yine de yeniden okunur.
    }
    return check();
  }

  /// Android'in çalışma zamanı medya izni diyaloğunu gösterir.
  static Future<PermissionStatus> requestMediaPermissions() async {
    if (!_supported) return const PermissionStatus(allFiles: true, media: true);
    try {
      await _channel.invokeMethod<bool>('requestMediaPermissions');
    } catch (_) {
      // Diyalog gösterilemedi; durum sessizce yeniden okunur.
    }
    return check();
  }
}