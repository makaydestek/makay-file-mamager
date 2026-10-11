import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/services/box_service.dart';
import 'package:makay_file_manager/services/dropbox_service.dart';
import 'package:makay_file_manager/services/onedrive_service.dart';

/// Bulut sağlayıcıları (Dropbox / OneDrive / Box): ortak [CloudItem] modeli,
/// token JSON ayrıştırma, Box multipart gövdesi, OneDrive yol kodlaması,
/// Türkçe hata mesajları ve SharedPreferences oturum durumu.
/// Ağ çağrısı yapan metotlar test edilmez.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CloudItem.fromMap', () {
    test('Dropbox dosya ve klasör girdileri', () {
      final file = CloudItem.fromMap({
        '.tag': 'file',
        'name': 'foto.png',
        'path_lower': '/klasor/foto.png',
        'path_display': '/Klasör/foto.png',
        'id': 'id:AAAA',
        'server_modified': '2026-01-05T10:30:00Z',
        'size': 2048,
      });
      expect(file.isFolder, isFalse);
      expect(file.id, '/Klasör/foto.png',
          reason: 'Dropbox tüm uçlarda yolu kimlik olarak kullanır');
      expect(file.name, 'foto.png');
      expect(file.size, 2048);
      expect(file.modified, DateTime.parse('2026-01-05T10:30:00Z'));

      final folder = CloudItem.fromMap({
        '.tag': 'folder',
        'name': 'Klasör',
        'path_display': '/Klasör',
        'id': 'id:BBBB',
      });
      expect(folder.isFolder, isTrue);
      expect(folder.id, '/Klasör');
      expect(folder.size, isNull);
      expect(folder.modified, isNull);
    });

    test('OneDrive (Microsoft Graph) dosya ve klasör girdileri', () {
      final file = CloudItem.fromMap({
        '@odata.type': '#microsoft.graph.file',
        'id': 'GRAPHFILE',
        'name': 'rapor.pdf',
        'size': 100,
        'lastModifiedDateTime': '2026-02-01T08:00:00Z',
        'file': {'mimeType': 'application/pdf'},
      });
      expect(file.isFolder, isFalse);
      expect(file.id, 'GRAPHFILE');
      expect(file.name, 'rapor.pdf');
      expect(file.size, 100);
      expect(file.modified, DateTime.parse('2026-02-01T08:00:00Z'));

      final folder = CloudItem.fromMap({
        '@odata.type': '#microsoft.graph.folder',
        'id': 'GRAPHFOLDER',
        'name': 'Belgeler',
        'folder': {'childCount': 3},
      });
      expect(folder.isFolder, isTrue);
      expect(folder.size, isNull);
    });

    test('Box dosya ve klasör girdileri', () {
      final file = CloudItem.fromMap({
        'type': 'file',
        'id': '111',
        'name': 'not.txt',
        'size': 12,
        'modified_at': '2026-03-01T12:00:00-08:00',
      });
      expect(file.isFolder, isFalse);
      expect(file.id, '111');
      expect(file.size, 12);

      final folder = CloudItem.fromMap({
        'type': 'folder',
        'id': '222',
        'name': 'Arşiv',
        'size': 0,
        'modified_at': '2026-03-02T12:00:00-08:00',
      });
      expect(folder.isFolder, isTrue);
      expect(folder.size, isNull,
          reason: 'Box klasörlerde boyut 0 döner; modelde null olmalı');
    });

    test('tanınmayan biçim hata fırlatır', () {
      expect(() => CloudItem.fromMap({'foo': 'bar'}),
          throwsA(isA<FormatException>()));
    });
  });

  group('token JSON ayrıştırma', () {
    test('Dropbox access + refresh token ve süre ayrıştırılır', () {
      final session = DropboxService.parseTokenJson(
          '{"access_token":"dbx","refresh_token":"r1","expires_in":14400}');
      expect(session.accessToken, 'dbx');
      expect(session.refreshToken, 'r1');
      expect(
        session.expiresAt.difference(DateTime.now()).inMinutes,
        greaterThan(139),
      );
    });

    test('OneDrive yanıtında refresh token korunur', () {
      final session = OneDriveService.parseTokenJson(
          '{"token_type":"Bearer","scope":"Files.ReadWrite","expires_in":3600,'
          '"access_token":"ms","refresh_token":"rr"}');
      expect(session.accessToken, 'ms');
      expect(session.refreshToken, 'rr');
    });

    test('Box yanıtı ayrıştırılır; refresh token opsiyoneldir', () {
      final withRefresh = BoxService.parseTokenJson(
          '{"access_token":"box","refresh_token":"br","expires_in":3600}');
      expect(withRefresh.accessToken, 'box');
      expect(withRefresh.refreshToken, 'br');

      final onlyAccess =
          BoxService.parseTokenJson('{"access_token":"box2","expires_in":60}');
      expect(onlyAccess.refreshToken, isNull);
    });

    test('access_token yoksa hata fırlatır', () {
      expect(
        () => DropboxService.parseTokenJson('{"expires_in":60}'),
        throwsA(isA<CloudApiException>()),
      );
      expect(
        () => OneDriveService.parseTokenJson('{"expires_in":60}'),
        throwsA(isA<CloudApiException>()),
      );
      expect(
        () => BoxService.parseTokenJson('{"expires_in":60}'),
        throwsA(isA<CloudApiException>()),
      );
    });
  });

  group('Box multipart gövdesi', () {
    test('attributes ve file alanları doğru biçimde oluşturulur', () {
      final preamble = BoxService.multipartPreamble(
        boundary: 'BND123',
        attributesJson: '{"name":"a.png","parent_id":"0"}',
        fileName: 'a.png',
        mimeType: 'image/png',
      );
      expect(preamble, contains('--BND123'));
      expect(preamble, contains('name="attributes"'));
      expect(preamble, contains('{"name":"a.png","parent_id":"0"}'));
      expect(preamble, contains('name="file"; filename="a.png"'));
      expect(preamble, contains('Content-Type: image/png'));
      expect(preamble, endsWith('\r\n\r\n'),
          reason: 'dosya baytları doğrudan bu bölümden sonra gelir');
    });

    test('dosya adındaki tırnaklar güvenli hale getirilir', () {
      final preamble = BoxService.multipartPreamble(
        boundary: 'B',
        attributesJson: '{}',
        fileName: 'a"b.png',
        mimeType: 'image/png',
      );
      expect(preamble, isNot(contains('filename="a"b.png"')));
      expect(preamble, contains('filename="a_b.png"'));
    });
  });

  group('OneDrive yol kodlama', () {
    test('boşluklu yollar kodlanır, bölücüler korunur', () {
      expect(OneDriveService.encodePath('/a b/c.txt'), 'a%20b/c.txt');
      expect(OneDriveService.encodePath(''), '');
      expect(OneDriveService.encodePath('/'), '');
      expect(OneDriveService.encodePath('/a//b/'), 'a//b');
    });

    test('Türkçe karakterler UTF-8 ile kodlanır', () {
      expect(
        OneDriveService.encodePath('/Kişisel Fotoğraf/yaz 2026.jpg'),
        'Ki%C5%9Fisel%20Foto%C4%9Fraf/yaz%202026.jpg',
      );
    });
  });

  group('hata mesajları Türkçeleştirilir', () {
    test('Dropbox', () {
      expect(DropboxService.friendlyMessage(401, '{}'),
          contains('Oturum süresi doldu'));
      expect(
        DropboxService.friendlyMessage(
            409, '{"error_summary":"path/conflict/folder/"}'),
        contains('zaten var'),
      );
      expect(
        DropboxService.friendlyMessage(
            404, '{"error_summary":"path/not_found/.."}'),
        contains('bulunamadı'),
      );
    });

    test('OneDrive (Graph)', () {
      const expired =
          '{"error":{"code":"InvalidAuthenticationToken","message":"expired"}}';
      expect(OneDriveService.friendlyMessage(401, expired),
          contains('Oturum süresi doldu'));
      const notFound =
          '{"error":{"code":"itemNotFound","message":"Item not found"}}';
      expect(OneDriveService.friendlyMessage(404, notFound),
          contains('bulunamadı'));
      const quota =
          '{"error":{"code":"quotaLimitReached","message":"Quota exceeded"}}';
      expect(OneDriveService.friendlyMessage(400, quota), contains('kota'));
    });

    test('Box', () {
      const invalid =
          '{"type":"error","code":"invalid_token","message":"bad token"}';
      expect(BoxService.friendlyMessage(401, invalid),
          contains('Oturum süresi doldu'));
      const notFound =
          '{"type":"error","code":"item_not_found","message":"not found"}';
      expect(BoxService.friendlyMessage(404, notFound), contains('bulunamadı'));
      const full = '{"type":"error","code":"storage_limit_exceeded",'
          '"message":"over quota"}';
      expect(BoxService.friendlyMessage(400, full), contains('kota'));
    });
  });

  group('SharedPreferences oturum durumu', () {
    test('client ID saklanır, okunur ve kaldırılır (anahtarlar ayrık)', () async {
      expect(await DropboxService.loadClientSecret(), isNull);
      await DropboxService.saveClientSecret('  dbx-id  ');
      expect(await DropboxService.loadClientSecret(), 'dbx-id',
          reason: 'boşluklar temizlenmeli');
      await DropboxService.saveClientSecret('');
      expect(await DropboxService.loadClientSecret(), isNull);

      await OneDriveService.saveClientSecret('ms-id');
      await BoxService.saveClientSecret('box-id');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('onedrive_client_id'), 'ms-id');
      expect(prefs.getString('box_client_id'), 'box-id');
      expect(prefs.getString('dropbox_client_id'), isNull,
          reason: 'sağlayıcı başına ayrı anahtar kullanılır');
    });

    test('hasTokens yalnızca kendi anahtarına bakar; disconnect siler', () async {
      expect(await DropboxService.hasTokens(), isFalse);
      expect(await OneDriveService.hasTokens(), isFalse);
      expect(await BoxService.hasTokens(), isFalse);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'dropbox_tokens',
        '{"access_token":"a","refresh_token":"r","expires_at":0}',
      );
      expect(await DropboxService.hasTokens(), isTrue);
      expect(await OneDriveService.hasTokens(), isFalse);
      expect(await BoxService.hasTokens(), isFalse);

      await DropboxService.disconnect();
      expect(await DropboxService.hasTokens(), isFalse,
          reason: 'disconnect tüm token’ları silmeli');

      await prefs.setString('box_tokens', 'bozuk-json');
      expect(await BoxService.hasTokens(), isFalse,
          reason: 'bozuk token JSON’u oturum var sayılmaz');
    });
  });

  group('bağlanma ön kontrolleri (ağ yok)', () {
    test('client ID yoksa connect hata fırlatır ve oturum oluşturmaz', () async {
      await expectLater(
        DropboxService.connect(''),
        throwsA(isA<CloudApiException>().having(
          (e) => e.message,
          'mesaj',
          allOf(contains('client ID'), contains('ücretsiz')),
        )),
      );
      await expectLater(
        OneDriveService.connect(''),
        throwsA(isA<CloudApiException>().having(
          (e) => e.message,
          'mesaj',
          allOf(contains('client ID'), contains('ücretsiz')),
        )),
      );
      await expectLater(
        BoxService.connect(''),
        throwsA(isA<CloudApiException>().having(
          (e) => e.message,
          'mesaj',
          allOf(contains('client ID'), contains('ücretsiz')),
        )),
      );
      expect(await DropboxService.hasTokens(), isFalse);
      expect(await OneDriveService.hasTokens(), isFalse);
      expect(await BoxService.hasTokens(), isFalse);
    });
  });

  test('cloudMimeOf yaygın uzantıları eşler', () {
    expect(cloudMimeOf('foto.PNG'), 'image/png');
    expect(cloudMimeOf('film.mp4'), 'video/mp4');
    expect(cloudMimeOf('sarki.mp3'), 'audio/mpeg');
    expect(cloudMimeOf('belge.pdf'), 'application/pdf');
    expect(cloudMimeOf('bilinmeyen'), 'application/octet-stream');
  });
}
