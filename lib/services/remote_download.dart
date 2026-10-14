import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/debug_log.dart';
import '../widgets/apk_install_dialog.dart';

/// Uzak sunucudan (FTP/SFTP/SMB/WebDAV) dosya indirme akışı.
///
/// İki saha şikâyetini birlikte çözer:
///
///  1. Dosyalar `systemTemp` (uygulama özel önbellek) altına iniyordu;
///     kullanıcı cihazın dosya yöneticisinde indirilen dosyayı göremiyordu.
///     Artık Android'de **herkese açık Download klasörü** hedeflenir.
///  2. `.apk` dosyası indikten sonra yalnız "İndirildi" bildirimi
///     çıkıyordu; artık indirme biter bitmez **Kur / Güncelle**
///     diyaloğu (Android kurucusu) açılır.
///
/// Hedef dizin yazılamazsa (izin/taşma) sessizce uygulama önbelleğine
/// düşülür — indirme yine tamamlanır.
class RemoteDownload {
  const RemoteDownload._();

  /// Dosya adı APK mı? (uzantı büyük/küçük harf duyarsız)
  static bool isApk(String fileName) =>
      fileName.toLowerCase().endsWith('.apk');

  /// İndirme hedefi: Android'de herkese açık Download, değilse önbellek.
  static Directory targetDir() {
    if (Platform.isAndroid) {
      final public = Directory('/storage/emulated/0/Download');
      try {
        public.createSync(recursive: true);
        if (public.existsSync() && Directory(public.path).existsSync()) {
          return public;
        }
      } catch (e) {
        logSwallowed('uzak indirme: Download klasörü', e);
      }
    }
    final cache = Directory('${Directory.systemTemp.path}/makay_downloads');
    cache.createSync(recursive: true);
    return cache;
  }

  /// Ad çakışmasını çözerek yazılacak dosya yolunu üretir.
  ///
  /// Aynı adlı dosya varsa `ad (2).apk`, `ad (3).apk` ... — önceki
  /// indirmeler silinmeden korunur.
  static File uniqueTarget(Directory dir, String fileName) {
    var candidate = File('${dir.path}${Platform.pathSeparator}$fileName');
    if (!candidate.existsSync()) return candidate;
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    for (var i = 2; i < 1000; i++) {
      final next = File(
          '${dir.path}${Platform.pathSeparator}$base ($i)$ext');
      if (!next.existsSync()) return next;
    }
    return candidate;
  }

  /// Ortak akış: ilerleme göstergesi → [transfer] → APK ise kurulum
  /// diyaloğu, değilse "İndirildi" bildirimi.
  ///
  /// [context] kullanım ömrü bitmişse (ekran kapandıysa) işlem sessizce
  /// sonlandırılır; hata kullanıcıya bildirilir.
  static Future<void> run(
    BuildContext context, {
    required String fileName,
    required Future<void> Function(File target) transfer,
  }) async {
    if (!context.mounted) return;
    final target = uniqueTarget(targetDir(), fileName);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await transfer(target);
      if (!context.mounted) return;
      Navigator.of(context).pop(); // ilerleme göstergesi

      if (isApk(fileName)) {
        // İstenen davranış: APK'ya dokununca doğrudan Kur/Güncelle.
        await showApkInstallDialog(context, target);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İndirildi: ${target.path}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // ilerleme göstergesi
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İndirme başarısız: $e')),
      );
    }
  }
}
