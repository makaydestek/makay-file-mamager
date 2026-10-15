import 'package:flutter/material.dart';

/// Klasör adına göre klasörün içine çizilen küçük simge.
///
/// Referans uygulamadaki gibi DCIM → kamera, Download → indirme oku,
/// Movies → film, Music → nota, Pictures → resim gibi bilinen klasörler
/// kendi simgeleriyle; bilinmeyen klasörler düz (simgesiz) gösterilir.
class FolderGlyph {
  const FolderGlyph._();

  /// Klasör adı için iç simge; bilinmeyen adlarda null.
  static IconData? of(String name) {
    final n = name.trim().toLowerCase();
    return switch (n) {
      // Kamera / fotoğrafların çekildiği klasör.
      'dcim' || 'camera' || 'kamera' => Icons.photo_camera_outlined,
      // İndirilen dosyalar.
      'download' ||
      'downloads' ||
      'indirilenler' =>
        Icons.file_download_outlined,
      // Video kütüphaneleri.
      'movies' || 'filmler' || 'film' => Icons.movie_outlined,
      'videos' || 'videolar' => Icons.video_library_outlined,
      // Ses.
      'music' || 'müzik' || 'songs' => Icons.music_note_outlined,
      // Görseller.
      'pictures' ||
      'images' ||
      'resimler' ||
      'galeri' ||
      'gallery' =>
        Icons.image_outlined,
      // Belgeler.
      'documents' || 'belgeler' || 'dokumanlar' => Icons.description_outlined,
      // Sistem / uygulama alanları.
      'android' || 'apks' || 'apk' => Icons.android_outlined,
      'miui' => Icons.smartphone_rounded,
      'data' || 'obb' => Icons.folder_special_outlined,
      // Yaygın uygulama klasörleri.
      'whatsapp' => Icons.chat_bubble_outline_rounded,
      'telegram' => Icons.send_rounded,
      'screenshots' || 'ekran goruntuleri' => Icons.screenshot_rounded,
      'podcasts' => Icons.podcasts_rounded,
      _ => null,
    };
  }
}
