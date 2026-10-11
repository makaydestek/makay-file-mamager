import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dropbox_service.dart' show CloudApiException, CloudItem, cloudMimeOf;
import 'oauth_service.dart';

/// Box REST 2.0 istemcisi (OAuth 2.0 + PKCE, tarayıcı tabanlı giriş).
///
/// Token'lar ve client ID [SharedPreferences] içinde saklanır; erişim
/// token'ının süresi dolarsa yenileme token'ı ile sessizce yenilenir.
/// Kök klasör kimliği `'0'` olarak kullanılır.
class BoxService {
  BoxService._();

  static const _kTokens = 'box_tokens';
  static const _kClientId = 'box_client_id';

  static final _authorizeEndpoint =
      Uri.parse('https://account.box.com/api/oauth2/authorize');
  static final _tokenEndpoint = Uri.parse('https://api.box.com/oauth2/token');
  static final _apiBase = Uri.parse('https://api.box.com/2.0/');
  static final _uploadBase = Uri.parse('https://upload.box.com/api/2.0/');

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

  /// Tarayıcıda Box girişini başlatır ve oturumu kaydeder.
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
        'Box client ID gerekli — Bulut ekranındaki ücretsiz kurulum '
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
      throw const CloudApiException('Box token alınamadı');
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
      throw const CloudApiException('Box bağlı değil — önce bağlanın.');
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
  // Box API
  // -------------------------------------------------------------------------

  /// Klasör içeriğini listeler; [folderId] verilmezse kök ('0') listelenir.
  static Future<List<CloudItem>> list({String? folderId}) async {
    final id = (folderId == null || folderId.isEmpty) ? '0' : folderId;
    final items = <CloudItem>[];
    var offset = 0;
    for (var page = 0; page < 20; page++) {
      final data = await _json(
        _apiBase.replace(
          path: '${_apiBase.path}folders/$id/items',
          queryParameters: {
            'limit': '100',
            'offset': '$offset',
            'fields': 'id,name,type,size,modified_at',
          },
        ),
        method: 'GET',
      );
      final entries = data['entries'];
      final count = entries is List ? entries.length : 0;
      if (entries is List) {
        items.addAll(
          entries.whereType<Map<String, Object?>>().map(CloudItem.fromMap),
        );
      }
      final total = (data['total_count'] as num?)?.toInt() ?? items.length;
      if (count == 0 || offset + count >= total) break;
      offset += count;
    }
    return items;
  }

  /// Dosyayı [destPath] konumuna indirir; [onProgress] 0..1 arası ilerleme.
  ///
  /// Box, /content ucunda 302 ile imzalı adrese yönlendirir; yönlendirme
  /// elle takip edilir (imzalı adres yetki başlığı istemez).
  static Future<void> download(
    String id,
    String name,
    String destPath,
    void Function(double) onProgress,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final resp = await _authorized(() async {
        final req = await client
            .getUrl(_apiBase.replace(path: '${_apiBase.path}files/$id/content'));
        req.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer ${await _token()}');
        req.followRedirects = false;
        return req.close();
      });
      if (resp.statusCode != 302 && resp.statusCode != 200) {
        final text = await resp.transform(utf8.decoder).join();
        throw CloudApiException(friendlyMessage(resp.statusCode, text));
      }
      final location = resp.headers.value(HttpHeaders.locationHeader);
      await resp.drain<void>();
      if (location == null || location.isEmpty) {
        throw const CloudApiException('İndirme adresi alınamadı');
      }
      await _streamToFile(Uri.parse(location), File(destPath), onProgress);
    } finally {
      client.close(force: true);
    }
  }

  /// Yerel dosyayı [folderId] klasörüne yükler (multipart gövde).
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
    final boundary = 'makayfm_${DateTime.now().millisecondsSinceEpoch}';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 60);
    try {
      final req = await client.postUrl(
        _uploadBase.replace(path: '${_uploadBase.path}files/content'),
      );
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${await _token()}')
        ..contentType = ContentType.parse('multipart/form-data; boundary=$boundary');
      req.write(multipartPreamble(
        boundary: boundary,
        attributesJson: jsonEncode({
          'name': name,
          'parent_id': folderId.isEmpty ? '0' : folderId,
        }),
        fileName: name,
        mimeType: cloudMimeOf(name),
      ));
      var sent = 0;
      await for (final chunk in src.openRead()) {
        sent += chunk.length;
        req.add(chunk);
        if (total > 0) {
          onProgress?.call((sent / total).clamp(0.0, 1.0).toDouble());
        }
      }
      req.write('\r\n--$boundary--\r\n');
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 201) {
        throw CloudApiException(friendlyMessage(resp.statusCode, text));
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Çok parçalı (multipart) yükleme gövdesinin dosyadan önceki bölümü.
  ///
  /// Kutu biçimi: `attributes` (JSON) + `file` (dosya) alanları.
  @visibleForTesting
  static String multipartPreamble({
    required String boundary,
    required String attributesJson,
    required String fileName,
    required String mimeType,
  }) {
    final safeName = fileName.replaceAll('"', '_');
    return '--$boundary\r\n'
        'Content-Disposition: form-data; name="attributes"\r\n'
        'Content-Type: application/json\r\n\r\n'
        '$attributesJson\r\n'
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="$safeName"\r\n'
        'Content-Type: $mimeType\r\n\r\n';
  }

  /// Klasör oluşturur.
  static Future<void> createFolder(String parentFolderId, String name) async {
    await _json(
      _apiBase.replace(path: '${_apiBase.path}folders'),
      method: 'POST',
      body: {
        'name': name,
        'parent_id': parentFolderId.isEmpty ? '0' : parentFolderId,
      },
    );
  }

  /// Dosyayı siler; klasörlerde `recursive=true` gerekir.
  static Future<void> remove(String id, {bool isFolder = false}) async {
    final uri = isFolder
        ? _apiBase.replace(
            path: '${_apiBase.path}folders/$id',
            queryParameters: {'recursive': 'true'},
          )
        : _apiBase.replace(path: '${_apiBase.path}files/$id');
    await _json(uri, method: 'DELETE');
  }

  /// Kullanılan / toplam depolama bilgisi.
  static Future<({int used, int total})?> about() async {
    final data = await _json(
      _apiBase.replace(path: '${_apiBase.path}users/me'),
      method: 'GET',
    );
    final used = (data['space_used'] as num?)?.toInt();
    if (used == null) return null;
    return (used: used, total: (data['space_amount'] as num?)?.toInt() ?? 0);
  }

  /// Box hata yanıtını Türkçe, okunabilir metne çevirir.
  @visibleForTesting
  static String friendlyMessage(int status, String body) {
    var code = '';
    var detail = body;
    try {
      final map = jsonDecode(body) as Map<String, Object?>;
      code = '${map['code'] ?? ''}';
      detail = '${map['message'] ?? body}';
    } catch (_) {}
    if (status == 401 ||
        status == 403 ||
        code == 'invalid_token' ||
        code == 'unauthorized') {
      return 'Oturum süresi doldu veya erişim reddedildi — tekrar bağlanın';
    }
    if (code == 'item_not_found') return 'Öğe bulunamadı veya silinmiş';
    if (code == 'folder_name_already_in_use' || code == 'name_already_in_use') {
      return 'Aynı adlı bir öğe zaten var';
    }
    if (code == 'storage_limit_exceeded') return 'Depolama kotası doldu';
    if (code == 'rate_limit_exceeded') {
      return 'İstek limiti aşıldı — biraz bekleyip tekrar deneyin';
    }
    if (status >= 500) return 'Box sunucu hatası ($status)';
    return 'Box hatası ($status): $detail';
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
