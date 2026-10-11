import 'dart:io';

import 'package:flutter/material.dart';

import '../services/google_drive_service.dart';
import '../utils/debug_log.dart';
import '../utils/formats.dart';
import 'browser_screen.dart' show kAudioExts, kImageExts, kVideoExts;
import 'image_viewer_screen.dart';
import 'media_viewer_screen.dart';

/// Gezinilen klasör (ekran yığını).
class _FolderRef {
  const _FolderRef(this.id, this.name);

  final String id;
  final String name;
}

/// Google Drive gezinme ekranı: klasör ağacı, indirme, yeniden adlandırma
/// yerine standart dosya işlemleri (indir / bilgi / çöp kutusu).
class GoogleDriveScreen extends StatefulWidget {
  const GoogleDriveScreen({super.key});

  @override
  State<GoogleDriveScreen> createState() => _GoogleDriveScreenState();
}

class _GoogleDriveScreenState extends State<GoogleDriveScreen> {
  final _stack = <_FolderRef>[];
  List<DriveFile> _files = [];
  bool _loading = true;
  String? _error;
  DriveAccount? _account;
  bool _busy = false;
  bool _progressOpen = false;

  String get _folderId => _stack.isEmpty ? 'root' : _stack.last.id;

  @override
  void initState() {
    super.initState();
    _stack.add(const _FolderRef('root', 'Drive'));
    _load();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    try {
      final account = await GoogleDriveService.account();
      if (mounted) setState(() => _account = account);
    } catch (e) {
      logSwallowed('gdrive: hesap', e);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await GoogleDriveService.list(_folderId);
      if (!mounted) return;
      setState(() => _files = files);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------------------------------------------------------
  // Klasör gezinme
  // -------------------------------------------------------------------------

  void _open(DriveFile file) {
    if (file.isFolder) {
      setState(() => _stack.add(_FolderRef(file.id, file.name)));
      _load();
      return;
    }
    _fileActions(file);
  }

  void _goUp() {
    if (_stack.length <= 1) return;
    setState(() => _stack.removeLast());
    _load();
  }

  // -------------------------------------------------------------------------
  // Dosya işlemleri
  // -------------------------------------------------------------------------

  void _fileActions(DriveFile file) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('İndir'),
              subtitle: Text(
                file.isGoogleDoc
                    ? 'Google belgesi PDF olarak dışa aktarılır'
                    : (file.size == null
                        ? ''
                        : Formats.size(file.size!)),
                maxLines: 1,
              ),
              onTap: () {
                Navigator.pop(context);
                _download(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Bilgi'),
              onTap: () {
                Navigator.pop(context);
                _info(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Çöp kutusuna taşı'),
              onTap: () {
                Navigator.pop(context);
                _trash(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _info(DriveFile file) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boyut: ${file.size == null ? '—' : Formats.size(file.size!)}'),
            Text('Tür: ${file.mimeType}'),
            if (file.modified != null)
              Text('Değiştirilme: ${Formats.date(file.modified!)}'),
            const SizedBox(height: 8),
            SelectableText('Kimlik: ${file.id}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _trash(DriveFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çöp kutusuna taşı'),
        content: Text('"${file.name}" çöp kutusuna taşısın mı?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Taşı')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await GoogleDriveService.trash(file.id);
      _toast('"${file.name}" çöp kutusuna taşındı');
      await _load();
    } catch (e) {
      _toast('Taşınamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni klasör'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Klasör adı'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Oluştur')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await GoogleDriveService.createFolder(_folderId, name);
      _toast('"$name" klasörü oluşturuldu');
      await _load();
    } catch (e) {
      _toast('Oluşturulamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Dosyayı indirir; başarısızlıkta açık hata, başarısızlıkta "Aç" eylemi.
  Future<void> _download(DriveFile file) async {
    var name = file.name;
    if (file.isGoogleDoc && !name.contains('.')) name = '$name.pdf';
    final dir = Directory(
        Platform.isAndroid ? '/storage/emulated/0/Download' : _tempPath());
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {
        // Download klasörü erişilemiyorsa indirme yazma adımı hatayı
        // zaten açıkça kullanıcıya gösterir; burada yalnızca ön hazırlık.
      }
    }
    final target = File('${dir.path}${Platform.pathSeparator}${_unique(dir, name)}');

    final progress = ValueNotifier<double?>(null);
    final totalNotifier = ValueNotifier<int?>(null);
    if (mounted && !_progressOpen) {
      _progressOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              ValueListenableBuilder<double?>(
                valueListenable: progress,
                builder: (context, value, _) =>
                    LinearProgressIndicator(value: value),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<int?>(
                valueListenable: totalNotifier,
                builder: (context, total, _) => ValueListenableBuilder<double?>(
                  valueListenable: progress,
                  builder: (context, value, _) => Text(
                    total == null || value == null
                        ? 'İndiriliyor…'
                        : '${Formats.size((total * value).round())} / '
                            '${Formats.size(total)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    try {
      await GoogleDriveService.download(
        file,
        target,
        onProgress: (received, total) {
          if (total == null || total <= 0) {
            progress.value = null;
          } else {
            totalNotifier.value = total;
            progress.value = (received / total).clamp(0.0, 1.0);
          }
        },
      );
      _closeProgress();
      _toast('İndirildi: ${target.path}', action: _mediaAction(target, name));
    } catch (e) {
      _closeProgress();
      _toast('İndirilemedi: $e');
    }
  }

  SnackBarAction? _mediaAction(File file, String name) {
    final ext =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!kImageExts.contains(ext) &&
        !kVideoExts.contains(ext) &&
        !kAudioExts.contains(ext)) {
      return null;
    }
    return SnackBarAction(
      label: 'Aç',
      onPressed: () {
        final isVideo = kVideoExts.contains(ext);
        final isAudio = kAudioExts.contains(ext);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => isVideo || isAudio
                ? MediaViewerScreen(file: file, isVideo: isVideo)
                : ImageViewerScreen(file: file, title: name),
          ),
        );
      },
    );
  }

  void _closeProgress() {
    if (_progressOpen && mounted) {
      _progressOpen = false;
      Navigator.of(context).pop();
    }
    // Notifier'lar diyaloğun çıkış animasyonu sırasında kullanılabileceği
    // için bilinçli olarak dispose edilmez (kısa ömürlü nesnelerdir).
  }

  static String _tempPath() => Directory.systemTemp.path;

  /// Ad çakışmasını " (2)", " (3)" ekleyerek çözer.
  static String _unique(Directory dir, String name) {
    if (!File('${dir.path}${Platform.pathSeparator}$name').existsSync()) {
      return name;
    }
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 2; i < 1000; i++) {
      final candidate = '$base ($i)$ext';
      if (!File('${dir.path}${Platform.pathSeparator}$candidate')
          .existsSync()) {
        return candidate;
      }
    }
    return name;
  }

  void _toast(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = [..._files]
      ..sort((a, b) {
        if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(_stack.last.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _createFolder,
        icon: const Icon(Icons.create_new_folder_rounded),
        label: const Text('Yeni klasör'),
      ),
      body: Column(
        children: [
          if (_account != null) _accountBar(theme),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _errorView()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: files.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              if (_stack.length <= 1) {
                                return const SizedBox.shrink();
                              }
                              return ListTile(
                                leading: const Icon(Icons.drive_folder_upload),
                                title: const Text('..'),
                                onTap: _goUp,
                              );
                            }
                            final f = files[index - 1];
                            return ListTile(
                              leading: Icon(
                                f.isFolder
                                    ? Icons.folder_rounded
                                    : _iconFor(f.mimeType),
                                color: f.isFolder
                                    ? const Color(0xFFFFB300)
                                    : theme.colorScheme.primary,
                              ),
                              title: Text(f.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                f.isFolder
                                    ? '(Klasör${f.modified == null ? '' : ' • ${Formats.date(f.modified!)}'})'
                                    : '(${f.modified == null ? '' : '${Formats.date(f.modified!)} • '}'
                                        '${f.size == null ? 'Google belgesi' : Formats.size(f.size!)})',
                                maxLines: 1,
                              ),
                              onTap: () => _open(f),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _accountBar(ThemeData theme) {
    final account = _account!;
    final usage = account.usageBytes == 0
        ? ''
        : ' • ${Formats.size(account.usageBytes)} / '
            '${Formats.size(account.quotaBytes)}';
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.account_circle_rounded),
        title: Text(account.email, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('Google Drive$usage'),
        trailing: IconButton(
          tooltip: 'Bağlantıyı kes',
          icon: const Icon(Icons.link_off_rounded),
          onPressed: () => _disconnect(),
        ),
      ),
    );
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bağlantıyı kes'),
        content: const Text('Google Drive hesabı bu cihazdan kaldırılsın mı?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kes')),
        ],
      ),
    );
    if (ok != true) return;
    await GoogleDriveService.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String mime) {
    if (mime.startsWith('image/')) return Icons.image_rounded;
    if (mime.startsWith('video/')) return Icons.video_file_rounded;
    if (mime.startsWith('audio/')) return Icons.audio_file_rounded;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_rounded;
    if (mime.contains('zip') || mime.contains('compressed')) {
      return Icons.folder_zip_rounded;
    }
    if (mime.startsWith('text/')) return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }
}
