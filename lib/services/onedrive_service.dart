import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dropbox_service.dart' show CloudApiException, CloudItem, cloudMimeOf;
import 'oauth_service.dart';

/// Microsoft Graph (OneDrive) REST istemcisi (OAuth 2.0 + PKCE).
///
/// Token'lar ve client ID [SharedPreferences] içinde saklanır; erişim
/// token'ının süresi dolarsa yenileme token'ı ile sessizce yenilenir.
/// Kök klasör kimliği `'root'` olarak kullanılır.
class OneDriveService {
  OneDriveService._();

  static const _kTokens = 'onedrive_tokens';
  static const _kClientId = 'onedrive_client_id';
  static const _kScope = 'offline_access Files.ReadWrite';

  static final _authorizeEndpoint = Uri.parse(
      'https://login.microsoftonline.com/common/oauth2/v2.0/authorize');
  static final _tokenEndpoint = Uri.parse(
      'https://login.microsoftonline.com/common/oauth2/v2.0/token');
  static final _apiBase = Uri.parse('https://graph.microsoft.com/v1.0/me/drive/');
  static final _driveEndpoint =
      Uri.parse('https://graph.microsoft.com/v1.0/me/drive');

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

  /// Tarayıcıda Microsoft girişini başlatır ve oturumu kaydeder.
  ///
  /// [clientId] boşsa kayıtlı client ID kullanılır; ikisi de yoksa
  /// [CloudApiException] fırlatır.
  static Future<void> connect(String clientId) async {
    var id = clientId.trim();
    if (id.isEmpty) {
      id = (await loadClientSecret())?.trim() ?? '';
    }
    if (id.isEmpty) {
      throw const CloudApiException(
        'OneDrive (Microsoft) client ID gerekli — Bulut ekranındaki ücretsiz '
        'kurulum adımlarını izleyip yapıştırın.',
      );
    }
    await saveClientSecret(id);

    final session = await OAuthService.authorize(
      buildAuthorizeUrl: (redirectUri, state, challenge) =>
          _authorizeEndpoint.replace(queryParameters: {
        'client_id': id,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'response_mode': 'query',
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
      throw const CloudApiException('OneDrive token alınamadı');
    }
    return OAuthSession(
      accessToken: access,
      refreshToken: map['refresh_token'] as String?,
      expiresAt: DateTime.now().add(
        Duration(seconds: (map['expires_in'] as num?)?.toInt() ?? 3600),
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
      throw const CloudApiException('OneDrive bağlı değil — önce bağlanın.');
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
  // Graph API
  // -------------------------------------------------------------------------

  /// Klasör içeriğini listeler; [folderId] verilmezse kök ('root') listelenir.
  static Future<List<CloudItem>> list({String? folderId}) async {
    final id = (folderId == null || folderId.isEmpty) ? 'root' : folderId;
    final data = await _json(
      _apiBase.replace(
        path: '${_apiBase.path}items/$id/children',
        queryParameters: {
          r'$select': 'id,name,size,folder,file,lastModifiedDateTime',
          'top': '200',
        },
      ),
      method: 'GET',
    );
    final values = data['value'];
    if (values is! List) return const [];
    return values
        .whereType<Map<String, Object?>>()
        .map(CloudItem.fromMap)
        .toList();
  }

  /// Dosyayı [destPath] konumuna indirir; [onProgress] 0..1 arası ilerleme.
  ///
  /// Graph, dosya JSON'u içinde imzalı ve yetki gerektirmeyen bir indirme
  /// adresi ([@microsoft.graph.downloadUrl]) döner.
  static Future<void> download(
    String id,
    String name,
    String destPath,
    void Function(double) onProgress,
  ) async {
    final data = await _json(
      _apiBase.replace(path: '${_apiBase.path}items/$id'),
      method: 'GET',
    );
    final url = data['@microsoft.graph.downloadUrl'] as String?;
    if (url == null || url.isEmpty) {
      throw const CloudApiException(
          'İndirme adresi alınamadı — öğe dosya olmayabilir');
    }
    await _streamToFile(Uri.parse(url), File(destPath), onProgress);
  }

  /// Yerel dosyayı [folderId] klasörüne yükler (yol kodlanarak PUT edilir).
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
    final folderPath = await _folderPath(folderId);
    // Graph yol adreslemesi: /root:{yol}:/content (baştaki '/' korunur).
    final uri = _apiBase.replace(
      path: '${_apiBase.path}root:/${encodePath('$folderPath/$name')}:/content',
    );
    final total = await src.length();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 60);
    try {
      final req = await client.putUrl(uri);
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${await _token()}')
        ..contentType = ContentType.parse(cloudMimeOf(name));
      var sent = 0;
      await req.addStream(src.openRead().map((chunk) {
        sent += chunk.length;
        if (total > 0) {
          onProgress?.call((sent / total).clamp(0.0, 1.0).toDouble());
        }
        return chunk;
      }));
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 400) {
        throw CloudApiException(friendlyMessage(resp.statusCode, text));
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Klasör oluşturur.
  static Future<void> createFolder(String parentFolderId, String name) async {
    final parent = parentFolderId.isEmpty ? 'root' : parentFolderId;
    await _json(
      _apiBase.replace(path: '${_apiBase.path}items/$parent/children'),
      method: 'POST',
      body: {'name': name, 'folder': <String, Object?>{}},
    );
  }

  /// Dosyayı veya klasörü siler (Graph aynı uçla ikisini de siler).
  static Future<void> remove(String id, {bool isFolder = false}) async {
    await _json(
      _apiBase.replace(path: '${_apiBase.path}items/$id'),
      method: 'DELETE',
    );
  }

  /// Kullanılan / toplam depolama bilgisi (kişisel hesaplarda toplam 0 = sınırsız).
  static Future<({int used, int total})?> about() async {
    final data = await _json(
      _driveEndpoint.replace(queryParameters: {r'$select': 'quota'}),
      method: 'GET',
    );
    final quota = data['quota'];
    if (quota is! Map<String, Object?>) return null;
    return (
      used: (quota['used'] as num?)?.toInt() ?? 0,
      total: (quota['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Graph hata yanıtını Türkçe, okunabilir metne çevirir.
  @visibleForTesting
  static String friendlyMessage(int status, String body) {
    var code = '';
    var detail = body;
    try {
      final map = jsonDecode(body) as Map<String, Object?>;
      final error = map['error'];
      if (error is Map<String, Object?>) {
        code = '${error['code'] ?? ''}';
        detail = '${error['message'] ?? body}';
      }
    } catch (_) {}
    if (status == 401 ||
        status == 403 ||
        code == 'InvalidAuthenticationToken' ||
        code == 'accessDenied') {
      return 'Oturum süresi doldu veya erişim reddedildi — tekrar bağlanın';
    }
    if (code == 'itemNotFound') return 'Öğe bulunamadı veya silinmiş';
    if (code == 'nameAlreadyExists') return 'Aynı adlı bir öğe zaten var';
    if (code == 'quotaLimitReached') return 'Depolama kotası doldu';
    if (code == 'activityLimitReached' || code == 'tooManyRequests') {
      return 'İstek limiti aşıldı — biraz bekleyip tekrar deneyin';
    }
    if (status >= 500) return 'Microsoft Graph sunucu hatası ($status)';
    return 'OneDrive hatası ($status): $detail';
  }

  // -------------------------------------------------------------------------
  // Yol yardımcıları
  // -------------------------------------------------------------------------

  /// OneDrive yolunu URI parçalarına göre kodlar ('/' korunur).
  ///
  /// Örnek: `'/a b/c.txt'` → `'a%20b/c.txt'`.
  @visibleForTesting
  static String encodePath(String path) {
    final cleaned = path.replaceAll(RegExp(r'^/+|/+$'), '');
    if (cleaned.isEmpty) return '';
    return cleaned.split('/').map(Uri.encodeComponent).join('/');
  }

  /// Klasörün köke göre yolunu çözümler (yüklemede PUT yolu için).
  ///
  /// `parentReference.path` biçimi `'/drive/root:/Klasör'` şeklindedir;
  /// kök çocuklarında yalnızca `'/drive/root:'` döner.
  static Future<String> _folderPath(String folderId) async {
    if (folderId.isEmpty || folderId == 'root') return '';
    final data = await _json(
      _apiBase.replace(
        path: '${_apiBase.path}items/$folderId',
        queryParameters: {r'$select': 'name,parentReference'},
      ),
      method: 'GET',
    );
    final name = data['name'] as String? ?? '';
    final parent = data['parentReference'];
    var parentPath = '';
    if (parent is Map<String, Object?>) {
      final raw = parent['path'] as String? ?? '';
      final idx = raw.indexOf(':');
      parentPath = idx >= 0 ? raw.substring(idx + 1) : '';
    }
    return '$parentPath/$name';
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
    String method = 'GET',
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
          req.write(jsonEncode(body));
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

  /// İmzalı adrese (yetki başlığı olmadan) dosyayı indirir.
  static Future<void> _streamToFile(
    Uri uri,
    File target,
    void Function(double) onProgress,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) {
        final text = await resp.transform(utf8.decoder).join();
        throw CloudApiException(friendlyMessage(resp.statusCode, text));
      }
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
    } catch (_) {
      if (target.existsSync()) {
        try {
          target.deleteSync();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
