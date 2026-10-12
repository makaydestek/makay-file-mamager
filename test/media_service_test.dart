import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/services/media_service.dart';
import 'package:photo_manager/photo_manager.dart';

/// Medya servisi: kategori ayrımı (resim/video/ses) ve "Tümü" albümünün
/// Türkçe gösterim adı ("Recent" → "Tüm Dosyalar").
void main() {
  AssetEntity assetOf(AssetType type) => AssetEntity(
        id: 'id-${type.name}',
        typeInt: AssetType.values.indexOf(type),
        width: 10,
        height: 10,
      );

  group('kategoriler birbirine karışmaz', () {
    final image = assetOf(AssetType.image);
    final video = assetOf(AssetType.video);
    final audio = assetOf(AssetType.audio);

    test('resim yalnızca Resimler ekranında', () {
      expect(MediaService.matches(image, 'images'), isTrue);
      expect(MediaService.matches(image, 'videos'), isFalse);
      expect(MediaService.matches(image, 'audio'), isFalse);
    });

    test('video yalnızca Videolar ekranında', () {
      expect(MediaService.matches(video, 'videos'), isTrue);
      expect(MediaService.matches(video, 'images'), isFalse);
      expect(MediaService.matches(video, 'audio'), isFalse);
    });

    test('ses yalnızca Ses ekranında', () {
      expect(MediaService.matches(audio, 'audio'), isTrue);
      expect(MediaService.matches(audio, 'images'), isFalse);
      expect(MediaService.matches(audio, 'videos'), isFalse);
    });

    test('kategori verilmediğinde süzgeç uygulanmaz', () {
      expect(MediaService.matches(image, ''), isTrue);
      expect(MediaService.matches(video, ''), isTrue);
      expect(MediaService.matches(audio, ''), isTrue);
    });
  });

  group('"Tümü" albümü "Tüm Dosyalar" adını taşır', () {
    test('photo_manager isAll albümü (cihaz dili ne olursa olsun)', () {
      final all = AssetPathEntity(id: 'all', name: 'Recent', isAll: true);
      expect(MediaService.albumTitle(all), 'Tüm Dosyalar');
    });

    test('İngilizce ve Türkçe takma adlar tanınır', () {
      for (final name in ['Recent', 'All', 'Recent items', 'Tümü', 'Son']) {
        final path = AssetPathEntity(id: 'x', name: name);
        expect(MediaService.albumTitle(path), 'Tüm Dosyalar',
            reason: '"$name" adı Türkçe karşılığıyla gösterilmeli');
      }
    });

    test('normal klasör adları olduğu gibi korunur', () {
      for (final name in ['WhatsApp Images', 'Camera', 'Ekran görüntüleri']) {
        final path = AssetPathEntity(id: 'x', name: name);
        expect(MediaService.albumTitle(path), name);
      }
    });

    test('başlık sabiti Türkçe metin', () {
      expect(MediaService.allAlbumTitle, 'Tüm Dosyalar');
    });
  });
}
