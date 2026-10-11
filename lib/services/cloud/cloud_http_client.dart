import 'dart:convert';
import 'dart:io';

import '../oauth_service.dart';
import 'cloud_types.dart';

/// Durumsuz (stateless) bulut HTTP/OAuth yardımcıları.
///
/// Dropbox / OneDrive / Box istemcilerinin tekrar eden HTTP desenlerini
/// tutar: authorization-code + PKCE değiş tokuşu, yenileme isteği,
/// 401/403 → yenile → tekrar deneme, JSON istek ve dosya akışı kaydı.
/// Sağlayıcıya özgü uçlar, gövdeler ve hata çevirisi çağrıcıda kalır.
class CloudHttpClient {
  CloudHttpClient._();

  /// authorization_code + PKCE token değiş tokuşu (form POST).
  ///
  /// Hata durumunda [errorOf] ile Türkçe mesaj üretilir; yanıt 200 ise gövde
  /// [parse] ile [OAuthSession]e çevrilir.
  static Future<OAuthSession> exchangeCode({
    required Uri tokenEndpoint,
    required String clientId,
    required String code,
    required String redirectUri,
    required String verifier,
    required String Function(int status, String body) errorOf,
    required OAuthSession Function(String body) parse,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(tokenEndpoint);
      req.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
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
        throw CloudApiException(errorOf(resp.statusCode, body));
      }
      return parse(body);
    } finally {
      client.close(force: true);
    }
  }

  /// refresh_token ile erişim token'ını yeniler; başarısızsa false döner.
  static Future<OAuthSession?> refreshToken({
    required Uri tokenEndpoint,
    required String clientId,
    required String refreshToken,
    required OAuthSession Function(String body) parse,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(tokenEndpoint);
      req.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      req.write(
        'grant_type=refresh_token'
        '&refresh_token=${Uri.encodeQueryComponent(refreshToken)}'
        '&client_id=${Uri.encodeQueryComponent(clientId)}',
      );
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) return null;
      return parse(body);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 401/403 alınırsa token'ı yeniler ve isteği bir kez tekrarlar.
  static Future<HttpClientResponse> authorized(
    Future<HttpClientResponse> Function() send, {
    required Future<bool> Function() refresh,
    required Future<void> Function() disconnect,
  }) async {
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

  /// JSON gövdeli yetkili istek; hata durumunda [friendlyMessage] ile
  /// [CloudApiException] fırlatır, boş yanıtta boş harita döner.
  static Future<Map<String, Object?>> json(
    Uri uri, {
    String method = 'GET',
    Object? body,
    required Future<String> Function() token,
    required Future<bool> Function() refresh,
    required Future<void> Function() disconnect,
    required String Function(int status, String body) friendlyMessage,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final resp = await authorized(
        () async {
          final req = await client.openUrl(method, uri);
          req.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${await token()}',
          );
          if (body != null) {
            req.headers.contentType = ContentType.json;
            req.write(body is String ? body : jsonEncode(body));
          }
          return req.close();
        },
        refresh: refresh,
        disconnect: disconnect,
      );
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

  /// Yetki başlığı taşıyan istekle dosyayı [target]e indirir (Dropbox).
  ///
  /// Başarısızlıkta hedef dosya sessizce silinir.
  static Future<void> streamToFile(
    Future<HttpClientResponse> Function(HttpClient client, String token) send,
    File target,
    void Function(double) onProgress, {
    required Future<String> Function() token,
    required Future<bool> Function() refresh,
    required Future<void> Function() disconnect,
    required String Function(int status, String body) friendlyMessage,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final resp = await authorized(
        () async => send(client, await token()),
        refresh: refresh,
        disconnect: disconnect,
      );
      if (resp.statusCode != 200) {
        final text = await resp.transform(utf8.decoder).join();
        throw CloudApiException(friendlyMessage(resp.statusCode, text));
      }
      await saveResponse(resp, target, onProgress);
    } catch (_) {
      deleteQuietly(target);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Yetki başlığı olmadan imzalı adrese (OneDrive / Box) indirme.
  ///
  /// Başarısızlıkta hedef dosya sessizce silinir.
  static Future<void> streamUnsigned(
    Uri uri,
    File target,
    void Function(double) onProgress, {
    required String Function(int status, String body) friendlyMessage,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) {
        final text = await resp.transform(utf8.decoder).join();
        throw CloudApiException(friendlyMessage(resp.statusCode, text));
      }
      await saveResponse(resp, target, onProgress);
    } catch (_) {
      deleteQuietly(target);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// HTTP yanıtını dosyaya yazar; 0..1 arası ilerleme bildirir.
  static Future<void> saveResponse(
    HttpClientResponse resp,
    File target,
    void Function(double) onProgress,
  ) async {
    final total =
        int.tryParse(
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

  /// Hedef dosyayı varsa sessizce siler.
  static void deleteQuietly(File target) {
    if (!target.existsSync()) return;
    try {
      target.deleteSync();
    } catch (_) {}
  }
}
