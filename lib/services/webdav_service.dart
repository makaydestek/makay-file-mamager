import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

/// Bulut konumu (WebDAV tabanlı: Nextcloud, ownCloud, pCloud Drive vb.).
class CloudLocation {
  CloudLocation({
    required this.name,
    required this.provider,
    required this.url,
    required this.username,
    this.password = '',
  });

  final String name;
  final String provider; // Nextcloud / WebDAV / ...
  final String url; // WebDAV kökü, ör. https://nc.ornek.com/remote.php/dav/files/kullanici
  final String username;
  final String password;

  Map<String, Object?> toJson() => {
        'name': name,
        'provider': provider,
        'url': url,
        'username': username,
        'password': password,
      };

  factory CloudLocation.fromJson(Map<String, Object?> json) => CloudLocation(
        name: (json['name'] as String?) ?? '',
        provider: (json['provider'] as String?) ?? 'WebDAV',
        url: (json['url'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
      );
}

/// Bulut konumlarının kalıcı saklayıcısı.
class CloudLocationStore {
  static const _key = 'cloud_locations';

  static Future<List<CloudLocation>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map(CloudLocation.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<CloudLocation> locations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(locations.map((e) => e.toJson()).toList()));
  }
}

/// WebDAV dizin girişi.
class DavEntry {
  DavEntry({required this.name, required this.isDir, this.size = 0});

  final String name;
  final bool isDir;
  final int size;
}

/// Minimal WebDAV istemcisi: PROPFIND ile dizin listeleme.
class WebDavService {
  const WebDavService();

  /// [path] WebDAV köküne göre yol ('/' ile başlar).
  Future<List<DavEntry>> list(
    CloudLocation loc, {
    String path = '/',
  }) async {
    final base = loc.url.endsWith('/')
        ? loc.url.substring(0, loc.url.length - 1)
        : loc.url;
    final uri = Uri.parse('$base${path.isEmpty ? '/' : path}');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl('PROPFIND', uri);
      req.headers.set('Depth', '1');
      req.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('${loc.username}:${loc.password}'))}',
      );
      req.headers.contentType =
          ContentType('application', 'xml', charset: 'utf-8');
      req.write(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<D:propfind xmlns:D="DAV:">'
        '<D:prop><D:displayname/><D:resourcetype/>'
        '<D:getcontentlength/></D:prop></D:propfind>',
      );
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 207 && resp.statusCode != 200) {
        throw HttpException(
            'Sunucu ${resp.statusCode} yanıtı verdi (y kimlik kontrolü?)');
      }
      return _parse(body, selfName: path == '/' ? '' : path.split('/').last);
    } finally {
      client.close(force: true);
    }
  }

  List<DavEntry> _parse(String body, {String selfName = ''}) {
    final doc = XmlDocument.parse(body);
    final entries = <DavEntry>[];
    for (final response in doc.findAllElements('D:response')) {
      final href = response.getElement('D:href')?.innerText ?? '';
      // propstat > prop
      final prop = response
          .getElement('D:propstat')
          ?.getElement('D:prop');
      if (prop == null) continue;
      final name = prop.getElement('D:displayname')?.innerText ??
          Uri.decodeComponent(href.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '');
      if (name.isEmpty || name == selfName) continue;
      final isDir = prop
              .getElement('D:resourcetype')
              ?.getElement('D:collection') !=
          null;
      final size = int.tryParse(
              prop.getElement('D:getcontentlength')?.innerText ?? '') ??
          0;
      entries.add(DavEntry(name: name, isDir: isDir, size: size));
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// [path] dosyasını yerel [target] dosyasına indirir (HTTP GET).
  Future<void> download(
    CloudLocation loc,
    String path,
    File target,
  ) async {
    final base = loc.url.endsWith('/')
        ? loc.url.substring(0, loc.url.length - 1)
        : loc.url;
    final uri = Uri.parse('$base${path.isEmpty ? '/' : path}');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('${loc.username}:${loc.password}'))}',
      );
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Sunucu ${resp.statusCode} yanıtı verdi');
      }
      await resp.pipe(target.openWrite());
    } finally {
      client.close(force: true);
    }
  }
}
