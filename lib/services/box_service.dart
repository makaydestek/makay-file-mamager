import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/debug_log.dart';
import 'cloud/cloud_oauth_flow.dart';
import 'cloud/cloud_types.dart';
import 'oauth_service.dart';

/// Box REST 2.0 istemcisi (OAuth 2.0 + PKCE, tarayıcı tabanlı giriş).
///
/// Token'lar ve client ID [SharedPreferences] içinde saklanır; erişim
/// token'ının süresi dolarsa yenileme token'ı ile sessizce yenilenir.
/// Kök klasör kimliği `'0'` olarak kullanılır. Ortak OAuth/HTTP mantığı
/// [CloudOAuthClient] üzerinde yürür.
class BoxService {
  BoxService._();

  static final _authorizeEndpoint = Uri.parse(
    'https://account.box.com/api/oauth2/authorize',
  );
  static final _apiBase = Uri.parse('https://api.box.com/2.0/');
  static final _uploadBase = Uri.parse('https://upload.box.com/api/2.0/');

  /// Box OAuth/HTTP katmanı (token deposu + yenileme + yetkili istek).
  static final _api = CloudOAuthClient(
    provider: 'Box',
    clientLabel: 'Box',
    tokensKey: 'box_tokens',
    clientIdKey: 'box_client_id',
    tokenEndpoint: Uri.parse('https://api.box.com/oauth2/token'),
    defaultExpirySeconds: 3600,
    friendlyMessage: friendlyMessage,
  );

  // -------------------------------------------------------------------------
  // Ayarlar / oturum durumu
  // -------------------------------------------------------------------------

  static Future<void> saveClientSecret(String id) => _api.saveClientId(id);

  static Future<String?> loadClientSecret() => _api.loadClientId();

  /// Kullanıcı daha önce bağlandı mı (erişim veya yenileme token'ı var mı)?
  static Future<bool> hasTokens() => _api.hasTokens();

  /// Yerel oturumu siler (yenileme token'ı da geçersiz olur).
  static Future<void> disconnect() => _api.disconnect();

  // -------------------------------------------------------------------------
  // Bağlantı (tarayıcı akışı)
  // -------------------------------------------------------------------------

  /// Tarayıcıda Box girişini başlatır ve oturumu kaydeder.
  ///
  /// [clientId] boşsa kayıtlı client ID kullanılır; ikisi de yoksa
  /// [CloudApiException] fırlatır.
  static Future<void> connect(String clientId) async {
    final id = await _api.requireClientId(clientId);
    final session = await OAuthService.authorize(
      buildAuthorizeUrl: (redirectUri, state, challenge) =>
          _authorizeEndpoint.replace(
            queryParameters: {
              'client_id': id,
              'redirect_uri': redirectUri,
              'response_type': 'code',
              'state': state,
              'code_challenge': challenge,
              'code_challenge_method': 'S256',
            },
          ),
      exchangeCode: (code, redirectUri, verifier) => _api.exchangeCode(
        clientId: id,
        code: code,
        redirectUri: redirectUri,
        verifier: verifier,
      ),
    );
    await _api.saveTokens(session);
  }

  /// Token yanıtının JSON'unu ayrıştırır (ağ erişimi yok, test edilebilir).
  @visibleForTesting
  static OAuthSession parseTokenJson(String body) => _api.parseTokenJson(body);

  /// Erişim token'ını yenileme token'ı ile tazeler; olamazsa false döner.
  static Future<bool> refresh() => _api.refresh();

  // -------------------------------------------------------------------------
  // Box API
  // -------------------------------------------------------------------------

  /// Klasör içeriğini listeler; [folderId] verilmezse kök ('0') listelenir.
  static Future<List<CloudItem>> list({String? folderId}) async {
    final id = (folderId == null || folderId.isEmpty) ? '0' : folderId;
    final items = <CloudItem>[];
    var offset = 0;
    for (var page = 0; page < 20; page++) {
      final data = await _api.json(
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
      final pageItems = cloudItemsOf(data['entries']);
      final count = pageItems.length;
      items.addAll(pageItems);
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final resp = await _api.authorized(() async {
        final req = await client.getUrl(
          _apiBase.replace(path: '${_apiBase.path}files/$id/content'),
        );
        req.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${await _api.token()}',
        );
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
      await _api.streamUnsigned(
        Uri.parse(location),
        File(destPath),
        onProgress,
      );
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    try {
      final req = await client.postUrl(
        _uploadBase.replace(path: '${_uploadBase.path}files/content'),
      );
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${await _api.token()}')
        ..contentType = ContentType.parse(
          'multipart/form-data; boundary=$boundary',
        );
      req.write(
        multipartPreamble(
          boundary: boundary,
          attributesJson: jsonEncode({
            'name': name,
            'parent_id': folderId.isEmpty ? '0' : folderId,
          }),
          fileName: name,
          mimeType: cloudMimeOf(name),
        ),
      );
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
    await _api.json(
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
    await _api.json(uri, method: 'DELETE');
  }

  /// Kullanılan / toplam depolama bilgisi.
  static Future<({int used, int total})?> about() async {
    final data = await _api.json(
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
    } catch (e) {
      logSwallowed('box: hata gövdesi ayrıştırma', e);
    }
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
}
