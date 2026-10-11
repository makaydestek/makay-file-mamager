import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/media_service.dart';
import '../utils/debug_log.dart';
import 'image_viewer_screen.dart';
import 'media_viewer_screen.dart';

/// Bir albümün içindeki medya öğelerinin ızgarası.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.title,
    this.isVideo = false,
  });

  final String albumId;
  final String title;
  final bool isVideo;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  static const _service = MediaService();

  final List<AssetEntity> _assets = [];
  bool _loading = true;
  bool _hasMore = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    final page = await _service.assets(widget.albumId, page: _page);
    if (!mounted) return;
    setState(() {
      _assets.addAll(page);
      _hasMore = page.length >= 200;
      _page++;
      _loading = false;
    });
  }

  /// Öğeye göre yerleşik görüntüleyici açılır (resim / video).
  ///
  /// Büyük videolarda dosya çözümü (özellikle önbelleğe kopyalarken) zaman
  /// alabilir; bu sırada ilerleme göstergesi sunulur ve her hata okunabilir
  /// bir mesajla bildirilir — tıklamanın sessizce kaybolması önlenir.
  Future<void> _openAsset(AssetEntity asset) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    _showProgress();
    try {
      if (widget.isVideo) {
        final file = await _resolveVideo(asset);
        _hideProgress();
        if (file == null) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Video açılamadı: dosyaya erişilemedi'),
          ));
          return;
        }
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => MediaViewerScreen(file: file, isVideo: true),
          ),
        );
      } else {
        File? file;
        try {
          file = await asset.file;
          if (file != null && !await file.exists()) file = null;
        } catch (_) {
          file = null;
        }
        Uint8List? bytes;
        if (file == null) {
          // Dosya erişilemiyorsa yüksek çözünürlüklü küçük resme düşülür.
          bytes = await asset
              .thumbnailDataWithSize(const ThumbnailSize(2048, 2048));
        }
        _hideProgress();
        if (file == null && bytes == null) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Resim açılamadı: dosyaya erişilemedi'),
          ));
          return;
        }
        var title = '';
        try {
          title = await asset.titleAsync;
        } catch (e) {
          logSwallowed('albüm: başlık', e);
        }
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => file != null
                ? ImageViewerScreen(file: file, title: title)
                : ImageViewerScreen(bytes: bytes, title: title),
          ),
        );
      }
    } catch (e) {
      _hideProgress();
      messenger.showSnackBar(
        SnackBar(content: Text('Açılamadı: $e')),
      );
    }
  }

  /// Video dosyasını çözer: önce doğrudan dosya, olmazsa orijinal dosya.
  Future<File?> _resolveVideo(AssetEntity asset) async {
    File? f;
    try {
      f = await asset.file;
      if (f != null && !await f.exists()) f = null;
    } catch (_) {
      f = null;
    }
    if (f != null) return f;
    try {
      f = await asset.originFile;
      if (f != null && !await f.exists()) f = null;
    } catch (_) {
      f = null;
    }
    return f;
  }

  bool _progressOpen = false;

  void _showProgress() {
    if (_progressOpen || !mounted) return;
    _progressOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ).whenComplete(() => _progressOpen = false);
  }

  void _hideProgress() {
    if (!_progressOpen || !mounted) return;
    _progressOpen = false;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: _assets.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _assets.length) {
                  _loadPage();
                  return const Center(
                      child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ));
                }
                final asset = _assets[index];
                return InkWell(
                  onTap: () => _openAsset(asset),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _AssetThumb(asset: asset),
                      if (widget.isVideo)
                        const Center(
                          child: Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white70, size: 36),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _AssetThumb extends StatelessWidget {
  const _AssetThumb({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest);
        }
        return Image.memory(data, fit: BoxFit.cover);
      },
    );
  }
}
