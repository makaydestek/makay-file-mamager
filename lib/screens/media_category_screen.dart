import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/media_service.dart';
import 'album_screen.dart';

/// Kategori ekranı: albüm ızgarası (Görüntüler/Videolar) veya listesi (Ses).
///
/// Referans uygulamadaki "Görüntüler" ve "Videolar" ekranlarının karşılığı.
class MediaCategoryScreen extends StatefulWidget {
  const MediaCategoryScreen({
    super.key,
    required this.categoryId,
    required this.title,
  });

  final String categoryId; // images / videos / audio
  final String title;

  @override
  State<MediaCategoryScreen> createState() => _MediaCategoryScreenState();
}

class _MediaCategoryScreenState extends State<MediaCategoryScreen> {
  static const _service = MediaService();

  List<MediaAlbum>? _albums;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool fresh = false}) async {
    final allowed = await _service.ensurePermission();
    if (!allowed) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    // Aşağı kaydırmada önbellekler tazelenir: MediaStore'a sonradan eklenen
    // dosyalar, değişen adetler ve "Tüm Dosyalar" adı böylece yansır.
    // Albümden dönüldüğünde önbellek korunur (silme işleminde servis kendi
    // kayıtlarını zaten temizler) — liste taraması tekrarlanmaz.
    if (fresh) MediaService.clearCache();
    final albums = await _service.albums(widget.categoryId);
    if (!mounted) return;
    setState(() => _albums = albums);
  }

  @override
  Widget build(BuildContext context) {
    final albums = _albums;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _denied
          ? _PermissionBody(onRetry: () {
              setState(() => _denied = false);
              _load();
            })
          : albums == null
              ? const Center(child: CircularProgressIndicator())
              : albums.isEmpty
                  ? const Center(child: Text('Öğe bulunamadı'))
                  : RefreshIndicator(
                      // Aşağı kaydırma: önbelleklerle birlikte tam yenileme.
                      onRefresh: () => _load(fresh: true),
                      child: widget.categoryId == 'audio'
                          ? _audioList()
                          : _albumGrid(),
                    ),
    );
  }

  /// Ses: liste görünümü (küçük resim + ad + adet) — referans "Ses" ekranı.
  Widget _audioList() {
    final albums = _albums ?? const <MediaAlbum>[];
    return ListView.builder(
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return ListTile(
          leading: _AlbumThumb(
            album: album,
            categoryId: widget.categoryId,
            size: 56,
            rounded: 4,
          ),
          title: Text(album.name),
          trailing: Text('(${album.count})'),
          onTap: () => _openAlbum(album),
        );
      },
    );
  }

  /// Görüntüler/Videolar: kare ızgara — referans "Görüntüler" ekranı.
  Widget _albumGrid() {
    final albums = _albums ?? const <MediaAlbum>[];
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openAlbum(album),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _AlbumThumb(
                        album: album,
                        categoryId: widget.categoryId,
                        size: 300,
                      ),
                      if (widget.categoryId == 'videos')
                        const Center(
                          child: Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white70, size: 42),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${album.name} (${album.count})',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAlbum(MediaAlbum album) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumScreen(
          albumId: album.id,
          title: album.name,
          categoryId: widget.categoryId,
          isVideo: widget.categoryId == 'videos',
        ),
      ),
    );
    // Albümde silme/kopyalama yapılmış olabilir: adetler ve kapaklar
    // tazelensin (üstelik "Tüm Dosyalar" adı da yeniden adlandırılır).
    if (mounted) _load();
  }
}

/// Albüm küçük resmi; alınamazsa tür ikonu gösterir.
class _AlbumThumb extends StatelessWidget {
  const _AlbumThumb({
    required this.album,
    required this.categoryId,
    required this.size,
    this.rounded = 8,
  });

  final MediaAlbum album;

  /// Küçük resmin ait olduğu kategori (karışık albümlerde kapak da süzülür).
  final String categoryId;
  final double size;
  final double rounded;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _thumbFuture(album, categoryId),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(rounded),
            child: Image.memory(data, fit: BoxFit.cover),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(rounded),
          ),
          child: const Icon(Icons.photo_rounded, size: 28),
        );
      },
    );
  }

  static Future<Uint8List?> _thumbFuture(MediaAlbum album, String categoryId) {
    final cacheKey = '$categoryId|${album.id}';
    final cached = MediaService.cachedThumb(cacheKey);
    if (cached != null) return Future.value(cached);
    return () async {
      final allowed = await const MediaService().ensurePermission();
      if (!allowed) return null;
      final assets = await const MediaService()
          .assets(album.id, categoryId: categoryId, size: 1);
      if (assets.isEmpty) return null;
      final data = await const MediaService().thumbnail(assets.first);
      MediaService.cacheThumb(cacheKey, data);
      return data;
    }();
  }
}

class _PermissionBody extends StatelessWidget {
  const _PermissionBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.perm_media_rounded, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Medya dosyalarına erişim izni gerekli.\n'
              'Görüntüler, videolar ve ses dosyalarını göstermek için '
              'izin verin.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('İzin ver')),
          ],
        ),
      ),
    );
  }
}
