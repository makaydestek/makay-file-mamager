import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/models/file_entry.dart';
import 'package:makay_file_manager/widgets/file_thumbnail.dart';

/// FileThumbnail geri düşme zinciri:
///
///  • Görsel olmayan tür (klasör, ses, metin) → renkli tip ikonu,
///  • okunamayan resim dosyası → hata fırlatmadan ikona düşer,
///  • video (platform kanalı test ortamında yok) → ikon + oynatma rozeti.
void main() {
  FileEntry entry({
    required String name,
    bool isDirectory = false,
    int size = 1024,
  }) =>
      FileEntry(
        name: name,
        path: '/tmp/$name',
        isDirectory: isDirectory,
        size: size,
        modified: DateTime(2026, 1, 1),
      );

  Future<void> pump(WidgetTester tester, FileThumbnail thumb) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: thumb)));
  }

  testWidgets('klasör için renkli klasör ikonu gösterir', (tester) async {
    await pump(
      tester,
      FileThumbnail(entry: entry(name: 'Resimler', isDirectory: true), size: 40),
    );

    expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('ses dosyası için ses ikonu gösterir', (tester) async {
    await pump(
      tester,
      FileThumbnail(entry: entry(name: 'sarki.mp3'), size: 40),
    );

    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  testWidgets('olmayan resim dosyası hata fırlatmadan ikona düşer',
      (tester) async {
    await pump(
      tester,
      FileThumbnail(entry: entry(name: 'yok.jpg'), size: 40),
    );
    // Dosya okuma gerçek I/O ile asenkrondur: tamamlanana kadar bekle.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // errorBuilder → renkli tip ikonu (Image kaldırılır, ikon gelir).
    expect(find.byIcon(Icons.image_rounded), findsOneWidget);
  });

  testWidgets('video platform kanalı yoksa oynatma rozetli ikona düşer',
      (tester) async {
    await pump(
      tester,
      FileThumbnail(entry: entry(name: 'video.mp4'), size: 40),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Geri düşme: video tip ikonu + play oku (Stack içinde).
    expect(find.byIcon(Icons.video_library_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('özel boyut ve köşe yarıçapı uygulanır', (tester) async {
    await pump(
      tester,
      FileThumbnail(
        // Görsel olmayan tür (fallback) Container dekorasyonu kullanır.
        entry: entry(name: 'klasor_sarkisi.mp3'),
        size: 96,
        borderRadius: 16,
      ),
    );

    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect((decoration.borderRadius as BorderRadius).topLeft.x, 16);
  });
}
