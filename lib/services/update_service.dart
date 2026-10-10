import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub deposundaki `APK/latest.json` içindeki güncelleme bilgileri.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.size,
    required this.sha256,
    required this.url,
  });

  /// Yeni sürüm adı (örn. "1.0.3").
  final String version;

  /// Yeni sürüm kodu.
  final int versionCode;

  /// APK boyutu (bayt).
  final int size;

  /// APK'nın beklenen SHA256 özeti (küçük harf hex).
  final String sha256;

  /// APK indirme adresi.
  final String url;

  static const String defaultDownloadUrl =
      'https://raw.githubusercontent.com/makaydestek/makay-file-mamager/main/APK/latest.apk';

  factory UpdateInfo.fromMap(Map<String, dynamic> map) {
    final url = map['url'];
    return UpdateInfo(
      version: (map['version'] as String?) ?? '',
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      size: (map['size'] as num?)?.toInt() ?? 0,
      sha256: ((map['sha256'] as String?) ?? '').trim().toLowerCase(),
      url: (url is String && url.isNotEmpty) ? url : defaultDownloadUrl,
    );
  }
}

/// Otomatik güncelleme servisi.
///
/// Uygulama her açıldığında GitHub deposundaki `APK/latest.json` sorgulanır;
/// depodaki sürüm daha yeniyse indirilir, **SHA256 ile doğrulanır** ve
/// Android kurucuya açılır. Ağ hatalarında sessizce vazgeçilir.
class UpdateService {
  const UpdateService._();

  /// Sürüm bilgisi JSON adresi (önbellek kırıcı zaman damgası ile).
  static const String jsonUrl =
      'https://raw.githubusercontent.com/makaydestek/makay-file-mamager/main/APK/latest.json';

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static const MethodChannel _channel =
      MethodChannel('com.makay.filemanager/platform');

  /// Yeni sürüm varsa [UpdateInfo], yoksa veya hata olursa null döner.
  static Future<UpdateInfo?> check() async {
    if (!_supported) return null;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final req = await client.getUrl(Uri.parse(
            '$jsonUrl?t=${DateTime.now().millisecondsSinceEpoch}'));
        final resp = await req.close().timeout(const Duration(seconds: 12));
        if (resp.statusCode != 200) return null;
        final body = await resp.transform(utf8.decoder).join();
        final info =
            UpdateInfo.fromMap(jsonDecode(body) as Map<String, dynamic>);
        if (info.version.isEmpty || info.sha256.isEmpty) return null;
        final pkg = await PackageInfo.fromPlatform();
        return _isNewer(info.version, pkg.version) ? info : null;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // Çevrimdışı / yavaş ağ → sessizce vazgeç.
      return null;
    }
  }

  /// "1.0.3" > "1.0.2" biçiminde sürüm karşılaştırması.
  static bool _isNewer(String remote, String current) {
    final r = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final n = r.length > c.length ? r.length : c.length;
    for (var i = 0; i < n; i++) {
      final a = i < r.length ? r[i] : 0;
      final b = i < c.length ? c[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  /// APK'yı indirir; [onProgress] çağrısı (alınan bayt, toplam bayt) verir.
  static Future<File> download(
    UpdateInfo info,
    void Function(int received, int total) onProgress,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final out = File('${dir.path}/makay-update.apk');
    if (await out.exists()) {
      await out.delete();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(info.url));
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw Exception('İndirme başarısız (HTTP ${resp.statusCode})');
      }
      final total = info.size > 0 ? info.size : resp.contentLength;
      var received = 0;
      final sink = out.openWrite();
      try {
        await for (final chunk in resp) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return out;
    } finally {
      client.close(force: true);
    }
  }

  /// İndirilen dosyanın SHA256'sı beklenen özetle eşleşiyor mu?
  static Future<bool> verifySha256(File file, String expected) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expected.toLowerCase();
  }

  /// Android kurucuyu açar (FileProvider üzerinden).
  static Future<void> install(File file) async {
    await _channel.invokeMethod('installApk', {'path': file.path});
  }
}
