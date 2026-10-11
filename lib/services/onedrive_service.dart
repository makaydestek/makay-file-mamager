import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'cloud/cloud_oauth_flow.dart';
import 'cloud/cloud_types.dart';
import 'oauth_service.dart';

/// Microsoft Graph (OneDrive) REST istemcisi (OAuth 2.0 + PKCE).
///
/// Token'lar ve client ID [SharedPreferences] içinde saklanır; erişim
/// token'ının süresi dolarsa yenileme token'ı ile sessizce yenilenir.
/// Kök klasör kimliği `'root'` olarak kullanılır. Ortak OAuth/HTTP mantığı
/// [CloudOAuthClient] üzerinde yürür.
class OneDriveService {
  OneDriveService._();

  static const _kScope = 'offline_access Files.ReadWrite';

  static final _authorizeEndpoint = Uri.parse(
    'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
  );
  static final _apiBase = Uri.parse(
    'https://graph.microsoft.com/v1.0/me/drive/',
  );
  static final _driveEndpoint = Uri.parse(
    'https://graph.microsoft.com/v1.0/me/drive',
  );

  /// OneDrive OAuth/HTTP katmanı (token deposu + yenileme + yetkili istek).
  static final _api = CloudOAuthClient(
    provider: 'OneDrive',
    clientLabel: 'OneDrive (Microsoft)',
    tokensKey: 'onedrive_tokens',
    clientIdKey: 'onedrive_client_id',
    tokenEndpoint: Uri.parse(
      'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    ),
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

  /// Tarayıcıda Microsoft girişini başlatır ve oturumu kaydeder.
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
              'response_mode': 'query',
              'scope': _kScope,
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
  // Graph API
  // -------------------------------------------------------------------------

  /// Klasör içeriğini listeler; [folderId] verilmezse kök ('root') listelenir.
  static Future<List<CloudItem>> list({String? folderId}) async {
    final id = (folderId == null || folderId.isEmpty) ? 'root' : folderId;
    final data = await _api.json(
      _apiBase.replace(
        path: '${_apiBase.path}items/$id/children',
        queryParameters: {
          r'$select': 'id,name,size,folder,file,lastModifiedDateTime',
          'top': '200',
        },
      ),
      method: 'GET',
    );
    return cloudItemsOf(data['value']);
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
    final data = await _api.json(
      _apiBase.replace(path: '${_apiBase.path}items/$id'),
      method: 'GET',
    );
    final url = data['@microsoft.graph.downloadUrl'] as String?;
    if (url == null || url.isEmpty) {
      throw const CloudApiException(
        'İndirme adresi alınamadı — öğe dosya olmayabilir',
      );
    }
    await _api.streamUnsigned(Uri.parse(url), File(destPath), onProgress);
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    try {
      final req = await client.putUrl(uri);
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${await _api.token()}')
        ..contentType = ContentType.parse(cloudMimeOf(name));
      var sent = 0;
      await req.addStream(
        src.openRead().map((chunk) {
          sent += chunk.length;
          if (total > 0) {
            onProgress?.call((sent / total).clamp(0.0, 1.0).toDouble());
          }
          return chunk;
        }),
      );
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
    await _api.json(
      _apiBase.replace(path: '${_apiBase.path}items/$parent/children'),
      method: 'POST',
      body: {'name': name, 'folder': <String, Object?>{}},
    );
  }

  /// Dosyayı veya klasörü siler (Graph aynı uçla ikisini de siler).
  static Future<void> remove(String id, {bool isFolder = false}) async {
    await _api.json(
      _apiBase.replace(path: '${_apiBase.path}items/$id'),
      method: 'DELETE',
    );
  }

  /// Kullanılan / toplam depolama bilgisi (kişisel hesaplarda toplam 0 = sınırsız).
  static Future<({int used, int total})?> about() async {
    final data = await _api.json(
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
    final data = await _api.json(
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
}
