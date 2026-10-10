import 'dart:convert';
import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uzak FTP/SFTP/SMB/WebDAV konumu (kullanıcının kaydettiği bağlantı).
class RemoteLocation {
  RemoteLocation({
    required this.name,
    required this.host,
    this.type = 'ftp',
    this.port = 21,
    this.username = 'anonymous',
    this.password = '',
    this.startPath = '/',
    this.share = '',
  });

  /// Bağlantı türü: 'ftp', 'sftp' (SSH), 'smb' veya 'webdav'.
  /// 'webdav' türünde [host] alanı tam adresi (örn. https://sunucu/dav) tutar.
  final String type;

  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final String startPath;

  /// SMB paylaşım adı (yalnızca 'smb' türünde; ör. 'Paylasim' veya 'C$').
  final String share;

  bool get isSftp => type == 'sftp';
  bool get isSmb => type == 'smb';
  bool get isWebDav => type == 'webdav';

  /// Türkçe tür etiketi.
  String get typeLabel => switch (type) {
        'sftp' => 'SFTP',
        'smb' => 'SMB',
        'webdav' => 'WebDAV',
        _ => 'FTP',
      };

  Map<String, Object?> toJson() => {
        'name': name,
        'host': host,
        'type': type,
        'port': port,
        'username': username,
        'password': password,
        'startPath': startPath,
        'share': share,
      };

  factory RemoteLocation.fromJson(Map<String, Object?> json) => RemoteLocation(
        name: (json['name'] as String?) ?? '',
        host: (json['host'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'ftp',
        port: (json['port'] as num?)?.toInt() ?? 21,
        username: (json['username'] as String?) ?? 'anonymous',
        password: (json['password'] as String?) ?? '',
        startPath: (json['startPath'] as String?) ?? '/',
        share: (json['share'] as String?) ?? '',
      );
}

/// Uzak konum listesinin kalıcı saklayıcısı.
class RemoteLocationStore {
  static const _key = 'remote_locations';

  static Future<List<RemoteLocation>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map(RemoteLocation.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<RemoteLocation> locations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(locations.map((e) => e.toJson()).toList()));
  }
}

/// FTP istemcisi sarmalayıcısı: bağlantı testi, dizin listeleme, indirme.
class FtpClientService {
  const FtpClientService();

  FTPConnect _connect(RemoteLocation loc) => FTPConnect(
        loc.host,
        port: loc.port,
        user: loc.username,
        pass: loc.password,
        timeout: 12,
        // LIST her FTP sunucusunda çalışır (MLSD her yerde yok).
        listCommand: ListCommand.list,
      );

  Future<void> test(RemoteLocation loc) async {
    final ftp = _connect(loc);
    await ftp.connect();
    await ftp.disconnect();
  }

  Future<List<FTPEntry>> list(RemoteLocation loc, String path) async {
    final ftp = _connect(loc);
    await ftp.connect();
    try {
      return await ftp.listDirectoryContent(path);
    } finally {
      await ftp.disconnect();
    }
  }

  Future<void> download(
    RemoteLocation loc,
    String remotePath,
    File target,
  ) async {
    final ftp = _connect(loc);
    await ftp.connect();
    try {
      await ftp.downloadFile(remotePath, target);
    } finally {
      await ftp.disconnect();
    }
  }

  Future<void> upload(
    RemoteLocation loc,
    File source,
    String remotePath,
  ) async {
    final ftp = _connect(loc);
    await ftp.connect();
    try {
      await ftp.uploadFile(source, sRemoteName: remotePath);
    } finally {
      await ftp.disconnect();
    }
  }
}
