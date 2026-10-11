import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/services/google_drive_service.dart';

/// Google Drive servisi: client ID saklama, oturum durumu, ücretsiz kurulum
/// akışının yönlendirici hata mesajı ve MIME eşlemesi (ağ erişimi yok).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('client ID kaydedilir, okunur ve kaldırılabilir', () async {
    expect(await GoogleDriveService.clientId(), isNull);

    await GoogleDriveService.setClientId(
        '  12345.apps.googleusercontent.com ');
    expect(await GoogleDriveService.clientId(),
        '12345.apps.googleusercontent.com',
        reason: 'boşluklar temizlenmeli');

    await GoogleDriveService.setClientId('');
    expect(await GoogleDriveService.clientId(), isNull);
  });

  test('oturum durumu token varlığına göre değişir', () async {
    expect(await GoogleDriveService.hasSession, isFalse);
    expect(await GoogleDriveService.accountEmail(), isNull);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gdrive_access_token', 'gecici');
    expect(await GoogleDriveService.hasSession, isTrue);

    await GoogleDriveService.disconnect();
    expect(await GoogleDriveService.hasSession, isFalse,
        reason: 'disconnect tüm token’ları silmeli');
  });

  test('client ID yoksa bağlanma, ücretsiz kurulum yönü veren hata fırlatır',
      () async {
    await expectLater(
      GoogleDriveService.connect(),
      throwsA(
        isA<DriveException>().having(
          (e) => e.message,
          'mesaj',
          allOf(contains('client ID'), contains('ücretsiz')),
        ),
      ),
    );
    // Hiçbir ağ çağrısı yapılmadı.
    expect(await GoogleDriveService.hasSession, isFalse);
  });

  test('mimeOf yaygın uzantıları doğru eşler', () {
    expect(GoogleDriveService.mimeOf('foto.PNG'), 'image/png');
    expect(GoogleDriveService.mimeOf('film.mp4'), 'video/mp4');
    expect(GoogleDriveService.mimeOf('sarki.mp3'), 'audio/mpeg');
    expect(GoogleDriveService.mimeOf('belge.pdf'), 'application/pdf');
    expect(GoogleDriveService.mimeOf('arsiv.zip'), 'application/zip');
    expect(GoogleDriveService.mimeOf('bilinmeyen'), 'application/octet-stream');
  });
}
