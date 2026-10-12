import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../models/file_entry.dart';
import '../services/clipboard_manager.dart';
import '../services/media_service.dart';
import '../utils/debug_log.dart';
import '../utils/formats.dart';
import 'image_viewer_screen.dart';
import 'media_viewer_screen.dart';

/// Bir albümün içindeki medya öğelerinin ızgarası.
///
/// Uzun basarak çoklu seçim yapılabilir; seçilen öğeler **Kopyala / Taşı /
/// Sil / Paylaş** işlemleriyle yönetilir. Kopyalanan/taşınan öğeler
/// uygulama genelindeki panoya düşer ve klasör tarayıcısındaki "Yapıştır"
/// ile hedefe alınır.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.title,
    this.categoryId = '',
    this.isVideo = false,
  });

  final String albumId;
  final String title;

  /// Medya kategorisi (images / videos / audio): Resimler ekranında yalnız
  /// resimler, Videolar ekranında yalnız videolar listelenir.
  final String categoryId;
  final bool isVideo;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  static const _service = MediaService();
  static const _pageSize = 200;

  final List<AssetEntity> _assets = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _hasMore = true;
  bool _working = false;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    final page = await _service.assets(
      widget.albumId,
      categoryId: widget.categoryId,
      offset: _assets.length,
      size: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _assets.addAll(page);
      _hasMore = page.length >= _pageSize;
      _loading = false;
    });
    // Boyutlar arka planda çözülür; başlıktaki "Toplam" hazır oldukça
    // tazelenir (ana iş parçacığı dosya boyutu okumak için durmaz).
    unawaited(MediaService.resolveSizes(page).then((_) {
      if (mounted) setState(() {});
    }));
  }

  /// Albümün toplam öğesi ve boyutu (başlık altında özet).
  int get _totalCount => _assets.length;

  int get _totalBytes => MediaService.totalSizeOf(_assets);

  void _toggleSelect(AssetEntity asset) {
    setState(() {
      if (!_selected.remove(asset.id)) _selected.add(asset.id);
    });
  }

  List<AssetEntity> get _selectedAssets =>
      _assets.where((a) => _selected.contains(a.id)).toList(growable: false);

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

  // -------------------------------------------------------------------------
  // Dosya işlemleri (kopyala / taşı / sil / paylaş)
  // -------------------------------------------------------------------------

  /// Seçili varlıkların gerçek dosyalarını çözer; erişilemeyenler atlanır.
  Future<List<FileEntry>> _resolveSelectedEntries() async {
    final entries = <FileEntry>[];
    for (final asset in _selectedAssets) {
      File? file;
      try {
        file = await asset.file;
        if (file != null && !await file.exists()) file = null;
      } catch (_) {
        file = null;
      }
      if (file == null) continue;
      final sep = Platform.pathSeparator;
      final name = file.path.split(sep).last;
      entries.add(FileEntry(
        name: name,
        path: file.path,
        isDirectory: false,
        // photo_manager'ın `size` değeri pikseldir; bayt boyutu önbellekten
        // alınır (albüm açılırken arka planda çözülmüştür).
        size: MediaService.sizeOf(asset),
        modified: asset.createDateTime,
      ));
    }
    return entries;
  }

  /// Seçilenleri uygulama panosuna alır; hedef klasörde "Yapıştır" ile
  /// taşınır/kopyalanır (tarayıcı ekranındaki pan ile aynı).
  Future<void> _copyOrCut({required bool cut}) async {
    if (_working) return;
    setState(() => _working = true);
    final entries = await _resolveSelectedEntries();
    if (!mounted) return;
    setState(() => _working = false);
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dosya çözülemedi — öğeler seçilemedi')),
      );
      return;
    }
    if (cut) {
      ClipboardManager.instance.cut(entries);
    } else {
      ClipboardManager.instance.copy(entries);
    }
    setState(_selected.clear);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cut
              ? '${entries.length} öğe taşınmak üzere alındı — hedef klasörde '
                  '"Yapıştır"a dokunun'
              : '${entries.length} öğe kopyalanmak üzere alındı — hedef '
                  'klasörde "Yapıştır"a dokunun',
        ),
      ),
    );
  }

  /// Seçili varlıkları MediaStore'dan siler (onay diyaloğu ile).
  Future<void> _deleteSelected() async {
    final ids = _selected.toList(growable: false);
    if (ids.isEmpty || _working) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sil'),
            content: Text('${ids.length} medya dosyası silinecek. '
                'Bu işlem geri alınamaz.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sil'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    final ok = await _service.deleteAssets(ids);
    if (!mounted) return;
    setState(() {
      _working = false;
      _selected.clear();
      _assets.removeWhere((a) => ids.contains(a.id));
      // Silme sonrası liste yeniden okunur (MediaStore sayaçları tazelensin).
      if (_assets.isEmpty) _hasMore = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Silindi: ${ids.length} öğe' : 'Silinemedi')),
    );
  }

  /// Seçili dosyaları sistem paylaşım sayfasıyla paylaşır.
  Future<void> _shareSelected() async {
    if (_working) return;
    setState(() => _working = true);
    final entries = await _resolveSelectedEntries();
    if (!mounted) return;
    setState(() => _working = false);
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paylaşılacak dosya çözülemedi')),
      );
      return;
    }
    setState(_selected.clear);
    await SharePlus.instance.share(
      ShareParams(files: [for (final e in entries) XFile(e.path)]),
    );
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
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(_selected.clear),
              )
            : null,
        title: _selecting
            ? Text('${_selected.length} seçili')
            : Text(widget.title),
        // Toplam özet: albümdeki öğe sayısı + toplam boyut (toplam boyutun
        // eksiksiz gösterilmesi için). Liste büyüdükçe setState ile tazelenir.
        bottom: _selecting
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _assets.isEmpty && !_hasMore
                        ? 'Öğe yok'
                        : '$_totalCount öğe • Toplam '
                            '${Formats.size(_totalBytes)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: 'Kopyala',
                  onPressed: _working ? null : () => _copyOrCut(cut: false),
                ),
                IconButton(
                  icon: const Icon(Icons.content_cut_rounded),
                  tooltip: 'Taşı',
                  onPressed: _working ? null : () => _copyOrCut(cut: true),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Sil',
                  onPressed: _working ? null : _deleteSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded),
                  tooltip: 'Paylaş',
                  onPressed: _working ? null : _shareSelected,
                ),
              ]
            : null,
      ),
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
                final selected = _selected.contains(asset.id);
                return InkWell(
                  onTap: () => _selecting
                      ? _toggleSelect(asset)
                      : _openAsset(asset),
                  onLongPress: () => _toggleSelect(asset),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _AssetThumb(asset: asset),
                      if (widget.isVideo)
                        const Center(
                          child: Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white70, size: 36),
                        ),
                      if (selected)
                        Container(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.35),
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
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
