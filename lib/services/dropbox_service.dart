import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'oauth_service.dart';

// ---------------------------------------------------------------------------
// Ortak bulut tipleri (Dropbox / OneDrive / Box)
//
// Bu üç OAuth sağlayıcısı aynı modeli paylaşır; tekrarı önlemek için ortak
// [CloudItem] ve [CloudApiException] tipleri ilk sağlayıcı dosyasında tanımlı.
// ---------------------------------------------------------------------------

/// Bulut üzerindeki bir dosya veya klasör.
class CloudItem {
  CloudItem({
    required this.id,
    required this.name,
    required this.isFolder,
    this.size,
    this.modified,
  });

  /// Sağlayıcıya özgü kimlik; dosya işlemleri bu değerle yapılır
  /// (Dropbox'ta dosya/klasör yolu, OneDrive ve Box'ta nesne kimliği).
  final String id;
  final String name;
  final bool isFolder;

  /// Bayt; klasörlerde ve bazı sağlayıcılarda null.
  final int? size;
  final DateTime? modified;

  /// Dropbox, Microsoft Graph (OneDrive) ve Box liste girdilerini ayırt eder.
  ///
  /// Biçimler:
  /// - Dropbox: `{".tag": "file" | "folder", "path_display": "/Klasör/dosya"}`
  /// - OneDrive: `{"file": {...}}` veya `{"folder": {...}}` anahtarı
  /// - Box: `{"type": "file" | "folder", ...}`
  factory CloudItem.fromMap(Map<String, Object?> json) {
    final tag = json['.tag'] as String?;
    if (tag != null) {
      return CloudItem(
        id: '${json['path_display'] ?? json['id'] ?? ''}',
        name: json['name'] as String? ?? '',
        isFolder: tag == 'folder',
        size: (json['size'] as num?)?.toInt(),
        modified: DateTime.tryParse('${json['server_modified'] ?? ''}'),
      );
    }
    if (json.containsKey('file') || json.containsKey('folder')) {
      return CloudItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        isFolder: json.containsKey('folder'),
        size: (json['size'] as num?)?.toInt(),
        modified: DateTime.tryParse('${json['lastModifiedDateTime'] ?? ''}'),
      );
    }
    final type = json['type'] as String?;
    if (type == 'file' || type == 'folder') {
      final folder = type == 'folder';
      return CloudItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        isFolder: folder,
        size: folder ? null : (json['size'] as num?)?.toInt(),
        modified: DateTime.tryParse('${json['modified_at'] ?? ''}'),
      );
    }
    throw const FormatException('Bulut öğesi biçimi tanınmadı');
  }

  @override
  String toString() => name;
}

/// Bulut API hatası; [message] doğrudan kullanıcıya gösterilebilir.
class CloudApiException implements Exception {
  const CloudApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Basit uzantı → MIME eşlemesi (bulut yüklemelerinde kullanılır).
String cloudMimeOf(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'mp4' => 'video/mp4',
    'mkv' => 'video/x-matroska',
    'mov' => 'video/quicktime',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'wav' => 'audio/wav',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'zip' => 'application/zip',
    'rar' => 'application/vnd.rar',
    'apk' => 'application/vnd.android.package-archive',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
}

// ---------------------------------------------------------------------------
// Dropbox
// ---------------------------------------------------------------------------

/// Dropbox REST v2 istemcisi (OAuth 2.0 + PKCE, tarayıcı tabanlı giriş).
///
/// Token'lar ve client ID [SharedPreferences] içinde saklanır; erişim
/// token'ının süresi dolarsa yenileme token'ı ile sessizce yenilenir.
class DropboxService {
  DropboxService._();

  static const _kTokens = 'dropbox_tokens';
  static const _kClientId = 'dropbox_client_id';
  static const _kScope = 'files.content.read files.content.write';

  static final _authorizeEndpoint =
      Uri.parse('https://www.dropbox.com/oauth2/authorize');
  static final _tokenEndpoint =
      Uri.parse('https://api.dropboxapi.com/oauth2/token');
  static final _apiBase = Uri.parse('https://api.dropboxapi.com/2/');
  static final _contentBase = Uri.parse('https://content.dropboxapi.com/2/');

  // -------------------------------------------------------------------------
  // Ayarlar / oturum durumu
  // -------------------------------------------------------------------------

  static Future<void> saveClientSecret(String id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id.trim().isEmpty) {
      await prefs.remove(_kClientId);
    } else {
      await prefs.setString(_kClientId, id.trim());
    }
  }

  static Future<String?> loadClientSecret() async =>
      (await SharedPreferences.getInstance()).getString(_kClientId);

  /// Kullanıcı daha önce bağlandı mı (erişim veya yenileme token'ı var mı)?
  static Future<bool> hasTokens() async {
    final session = await _loadTokens();
    return session != null &&
        (session.accessToken.isNotEmpty ||
            (session.refreshToken?.isNotEmpty ?? false));
  }

  /// Yerel oturumu siler (yenileme token'ı da geçersiz olur).
  static Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokens);
  }

  // -------------------------------------------------------------------------
  // Bağlantı (tarayıcı akışı)
  // -------------------------------------------------------------------------

  /// Tarayıcıda Dropbox girişini başlatır ve oturumu kaydeder.
  ///
  /// [clientId] boşsa kayıtlı client ID kullanılır; ikisi de yoksa
  /// [CloudApiException] fırlatır (ücretsiz kurulum adımları ekranda gösterilir).
  static Future<void> connect(String clientId) async {
    var id = clientId.trim();
    if (id.isEmpty) {
      id = (await loadClientSecret())?.trim() ?? '';
    }
    if (id.isEmpty) {
      throw const CloudApiException(
        'Dropbox client ID gerekli — Bulut ekranındaki ücretsiz kurulum '
        'adımlarını izleyip yapıştırın.',
      );
    }
    await saveClientSecret(id);

    final session = await OAuthService.authorize(
      buildAuthorizeUrl: (redirectUri, state, challenge) =>
          _authorizeEndpoint.replace(queryParameters: {
        'client_id': id,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'token_access_type': 'offline',
        'scope': _kScope,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      }),
      exchangeCode: (code, redirectUri, verifier) =>
          _exchange(id, code, redirectUri, verifier),
    );
    await _saveTokens(session);
  }

  static Future<OAuthSession> _exchange(
    String clientId,
    String code,
    String redirectUri,
    String verifier,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(_tokenEndpoint);
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      req.write(
        'grant_type=authorization_code'
        '&code=${Uri.encodeQueryComponent(code)}'
        '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}'
        '&client_id=${Uri.encodeQueryComponent(clientId)}'
        '&code_verifier=${Uri.encodeQueryComponent(verifier)}',
      );
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        throw CloudApiException(friendlyMessage(resp.statusCode, body));
      }
      return parseTokenJson(body);
    } finally {
      client.close(force: true);
    }
  }

  /// Token yanıtının JSON'unu ayrıştırır (ağ erişimi yok, test edilebilir).
  @visibleForTesting
  static OAuthSession parseTokenJson(String body) {
    final map = jsonDecode(body) as Map<String, Object?>;
    final access = map['access_token'] as String?;
    if (access == null || access.isEmpty) {
      throw const CloudApiException('Dropbox token alınamadı');
    }
    return OAuthSession(
      accessToken: access,
      refreshToken: map['refresh_token'] as String?,
      expiresAt: DateTime.now().add(
        Duration(seconds: (map['expires_in'] as num?)?.toInt() ?? 14400),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Token yönetimi
  // -------------------------------------------------------------------------

  static Future<void> _saveTokens(OAuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kTokens,
      jsonEncode({
        'access_token': session.accessToken,
        'refresh_token': session.refreshToken,
        'expires_at': session.expiresAt.millisecondsSinceEpoch,
      }),
    );
  }

  static Future<OAuthSession?> _loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTokens);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, Object?>;
      final access = map['access_token'] as String? ?? '';
      final refresh = map['refresh_token'] as String?;
      if (access.isEmpty && refresh == null) return null;
      return OAuthSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (map['expires_at'] as num?)?.toInt() ?? 0,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Erişim token'ını yenileme token'ı ile tazeler; olamazsa false döner.
  static Future<bool> refresh() async {
    final stored = await _loadTokens();
    final refreshToken = stored?.refreshToken;
    final clientId = await loadClientSecret();
    if (refreshToken == null || clientId == null) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(_tokenEndpoint);
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      req.write(
        'grant_type=refresh_token'
        '&refresh_token=${Uri.encodeQueryComponent(refreshToken)}'
        '&client_id=${Uri.encodeQueryComponent(clientId)}',
      );
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) return false;
      final fresh = parseTokenJson(body);
      await _saveTokens(OAuthSession(
        accessToken: fresh.accessToken,
        refreshToken: fresh.refreshToken ?? refreshToken,
        expiresAt: fresh.expiresAt,
      ));
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Süresi dolmak üzere olan token'ı gerekirse yenileyerek döner.
  static Future<String> _token() async {
    final stored = await _loadTokens();
    if (stored == null) {
      throw const CloudApiException('Dropbox bağlı değil — önce bağlanın.');
    }
    final soon = DateTime.now().add(const Duration(seconds: 90));
    if (stored.accessToken.isNotEmpty && stored.expiresAt.isAfter(soon)) {
      return stored.accessToken;
    }
    if (await refresh()) {
      final next = await _loadTokens();
      if (next != null && next.accessToken.isNotEmpty) {
        return next.accessToken;
      }
    }
    await disconnect();
    throw const CloudApiException('Oturum süresi doldu — tekrar bağlanın.');
  }

  // -------------------------------------------------------------------------
  // Dropbox API
  // -------------------------------------------------------------------------

  /// Klasör içeriğini listeler; [folderId] verilmezse kök listelenir.
  static Future<List<CloudItem>> list({String? folderId}) async {
    final items = <CloudItem>[];
    var cursor = '';
    var first = true;
    while (true) {
      final Map<String, Object?> data;
      if (first) {
        first = false;
        data = await _json(
          _apiBase.replace(path: '${_apiBase.path}files/list_folder'),
          body: {'path': folderId ?? '', 'limit': 500},
        );
      } else {
        data = await _json(
          _apiBase.replace(path: '${_apiBase.path}files/list_folder/continue'),
          body: {'cursor': cursor},
        );
      }
      final entries = data['entries'];
      if (entries is List) {
        items.addAll(
          entries.whereType<Map<String, Object?>>().map(CloudItem.fromMap),
        );
      }
      if (data['has_more'] != true) break;
      cursor = data['cursor'] as String? ?? '';
      if (cursor.isEmpty) break;
    }
    return items;
  }

  /// Dosyayı [destPath] konumuna indirir; [onProgress] 0..1 arası ilerleme.
  static Future<void> download(
    String id,
    String name,
    String destPath,
    void Function(double) onProgress,
  ) async {
    await _streamToFile(
      (client, token) async {
        final req = await client.postUrl(
          _contentBase.replace(path: '${_contentBase.path}files/download'),
        );
        req.headers
          ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
          ..set('Dropbox-API-Arg', jsonEncode({'path': id}));
        return req.close();
      },
      File(destPath),
      onProgress,
    );
  }

  /// Yerel dosyayı [folderId] klasörüne yükler.
  static Future<void> upload(
    String folderId,
    String srcPath, {
    void Function(double)? onProgress,
  }) async {
    final src = File(srcPath);
    if (!src.existsSync()) {
      throw CloudApiException('Dosya bulunamadı: $srcPath');
    }
    final name = src.uri.pathSegments.last;
    final total = await src.length();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 60);
    try {
      final req = await client.postUrl(
        _contentBase.replace(path: '${_contentBase.path}files/upload'),
      );
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${await _token()}')
        ..set(
          'Dropbox-API-Arg',
          jsonEncode({
            'path': _joinPath(folderId, name),
            'mode': 'add',
            'autorename': true,
            'mute': false,
          }),
        )
        ..contentType = ContentType.parse(cloudMimeOf(name));
      var sent = 0;
      await for (final chunk in src.openRead()) {
        sent += chunk.length;
        req.add(chunk);
        if (total > 0) {
          onProgress?.call((sent / total).clamp(0.0, 1.0).toDouble());
        }
      }
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        throw CloudApiException(friendlyMessage(resp.statusCode, text));
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Klasör oluşturur.
  static Future<void> createFolder(String parentFolderId, String name) async {
    await _json(
      _apiBase.replace(path: '${_apiBase.path}files/create_folder_v2'),
      body: {'path': _joinPath(parentFolderId, name), 'autorename': false},
    );
  }

  /// Dosyayı veya klasörü kalıcı olarak siler.
  static Future<void> remove(String id, {bool isFolder = false}) async {
    // delete_v2 hem dosya hem klasör için çalışır; isFolder imzası için.
    await _json(
      _apiBase.replace(path: '${_apiBase.path}files/delete_v2'),
      body: {'path': id},
    );
  }

  /// Kullanılan / toplam depolama bilgisi.
  static Future<({int used, int total})?> about() async {
    final data = await _json(
      _apiBase.replace(path: '${_apiBase.path}users/get_space_usage'),
      body: const <String, Object?>{},
    );
    final used = (data['used'] as num?)?.toInt() ?? 0;
    final allocation = data['allocation'];
    final total = allocation is Map<String, Object?>
        ? (allocation['allocated'] as num?)?.toInt() ?? used
        : used;
    return (used: used, total: total);
  }

  /// Dropbox hata yanıtını Türkçe, okunabilir metne çevirir.
  @visibleForTesting
  static String friendlyMessage(int status, String body) {
    var detail = body;
    try {
      final map = jsonDecode(body) as Map<String, Object?>;
      final error = map['error'];
      detail = '${map['error_summary'] ?? (error is Map<String, Object?>
          ? error['.tag'] ?? body
          : error ?? body)}';
    } catch (_) {}
    if (status == 401 || status == 403) {
      return 'Oturum süresi doldu veya erişim reddedildi — tekrar bağlanın';
    }
    if (detail.contains('not_found')) return 'Öğe bulunamadı veya silinmiş';
    if (detail.contains('conflict')) return 'Aynı adlı bir öğe zaten var';
    if (detail.contains('too_many')) {
      return 'İstek limiti aşıldı — biraz bekleyip tekrar deneyin';
    }
    if (status >= 500) return 'Dropbox sunucu hatası ($status)';
    return 'Dropbox hatası ($status): $detail';
  }

  // -------------------------------------------------------------------------
  // HTTP yardımcıları
  // -------------------------------------------------------------------------

  /// 401/403 alınırsa token'ı yeniler ve isteği bir kez tekrarlar.
  static Future<HttpClientResponse> _authorized(
    Future<HttpClientResponse> Function() send,
  ) async {
    var resp = await send();
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      await resp.drain<void>();
      if (await refresh()) {
        resp = await send();
      } else {
        await disconnect();
        throw const CloudApiException('Oturum süresi doldu — tekrar bağlanın.');
      }
    }
    return resp;
  }

  static Future<Map<String, Object?>> _json(
    Uri uri, {
    String method = 'POST',
    Object? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final resp = await _authorized(() async {
        final req = await client.openUrl(method, uri);
        req.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer ${await _token()}');
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(body is String ? body : jsonEncode(body));
        }
        return req.close();
      });
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 400) {
        throw CloudApiException(friendlyMessage(resp.statusCode, text));
      }
      if (text.isEmpty) return const {};
      return jsonDecode(text) as Map<String, Object?>;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _streamToFile(
    Future<HttpClientResponse> Function(HttpClient client, String token) send,
    File target,
    void Function(double) onProgress,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final resp = await _authorized(() async => send(client, await _token()));
      if (resp.statusCode != 200) {
        final text = await resp.transform(utf8.decoder).join();
        throw CloudApiException(friendlyMessage(resp.statusCode, text));
      }
      await _saveResponse(resp, target, onProgress);
    } catch (_) {
      _deleteQuietly(target);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _saveResponse(
    HttpClientResponse resp,
    File target,
    void Function(double) onProgress,
  ) async {
    final total = int.tryParse(
          resp.headers.value(HttpHeaders.contentLengthHeader) ?? '',
        ) ??
        0;
    var received = 0;
    final sink = target.openWrite();
    try {
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress((received / total).clamp(0.0, 1.0).toDouble());
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  static void _deleteQuietly(File target) {
    if (!target.existsSync()) return;
    try {
      target.deleteSync();
    } catch (_) {}
  }

  /// Kök ('' veya '/') ile dosya adını birleştirir.
  static String _joinPath(String parent, String name) {
    if (parent.isEmpty) return '/$name';
    if (parent.endsWith('/')) return '$parent$name';
    return '$parent/$name';
  }
}
