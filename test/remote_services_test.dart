import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/services/remote_service.dart';
import 'package:makay_file_manager/services/sftp_service.dart';
import 'package:makay_file_manager/services/webdav_service.dart';

void main() {
  test('SFTP: kapalı portta kaç saniyede hata verir', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final sw = Stopwatch()..start();
    Object? err;
    try {
      await SftpSession.connect(RemoteLocation(
        name: 'x',
        host: '127.0.0.1',
        type: 'sftp',
        port: port,
        username: 'root',
        password: 'x',
      ));
    } catch (e) {
      err = e;
    }
    // ignore: avoid_print
    print('SFTP sonucu=${err.runtimeType} süre=${sw.elapsedMilliseconds}ms '
        'mesaj=$err');
    expect(err, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('WebDAV: kapalı portta kaç saniyede hata verir', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final sw = Stopwatch()..start();
    Object? err;
    try {
      await const WebDavService().list(CloudLocation(
        name: 'x',
        provider: 'WebDAV',
        url: 'https://127.0.0.1:$port/dav',
        username: 'u',
        password: 'p',
      ));
    } catch (e) {
      err = e;
    }
    // ignore: avoid_print
    print('WebDAV sonucu=${err.runtimeType} süre=${sw.elapsedMilliseconds}ms '
        'mesaj=$err');
    expect(err, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('WebDAV normalizeUrl davranisi', () {
    expect(WebDavService.normalizeUrl('next.site.com/dav'),
        'https://next.site.com/dav');
    expect(WebDavService.normalizeUrl('https://x.com/dav/'), 'https://x.com/dav');
    expect(WebDavService.normalizeUrl('  http://y.com  '), 'http://y.com');
  });
}
