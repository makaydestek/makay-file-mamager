import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/screens/network_access_screen.dart';

/// Ağdan erişim ekranı referans uygulamayla birebir aynı kimlik bilgilerini
/// gösterir: `ftp://<ip>:6586`, kullanıcı `admin`, şifre rastgele değişir.
void main() {
  testWidgets('FTP kimlik bilgileri referansla aynı (admin / 6586)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NetworkAccessScreen()),
    );
    await tester.pump();

    expect(find.text('Kullanıcı adı: admin'), findsOneWidget);
    expect(find.textContaining('Sunucu adresi: '), findsOneWidget);
    expect(find.textContaining(':6586'), findsWidgets);
    expect(find.textContaining('6588'), findsWidgets);

    // Eski yapı görünmemeli.
    expect(find.textContaining('Kullanıcı: android'), findsNothing);
    expect(find.textContaining(':2121'), findsNothing);

    // Rastgele şifre anahtarı açık gelir (her açılışta değişir);
    // BAŞLAT FTP ve SMB kartlarında birer kez bulunur.
    expect(find.byType(SwitchListTile), findsWidgets);
    expect(find.text('BAŞLAT'), findsWidgets);

    // En alttaki ipucu satırı kaydırınca görünür.
    await tester.scrollUntilVisible(
      find.textContaining('ftp://'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('ftp://'), findsOneWidget);
    expect(find.textContaining(':6586'), findsWidgets);
  });
}
