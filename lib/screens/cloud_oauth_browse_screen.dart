import 'dart:io';

import 'package:flutter/material.dart';

import '../services/cloud/cloud_types.dart';
import '../utils/debug_log.dart';
import '../utils/formats.dart';
import 'cloud_utils.dart';

// ---------------------------------------------------------------------------
// OAuth tabanlı bulut sağlayıcıları için ortak gezinme ekranı
// ---------------------------------------------------------------------------

/// Klasör listeleme ([folderId] verilmezse kök).
typedef CloudListFn = Future<List<CloudItem>> Function({String? folderId});

/// Dosya indirme; [onProgress] 0..1 arası ilerleme oranını bildirir.
typedef CloudDownloadFn = Future<void> Function(
  String id,
  String name,
  String destPath,
  void Function(double) onProgress,
);

/// Klasör oluşturma.
typedef CloudCreateFolderFn = Future<void> Function(
  String parentFolderId,
  String name,
);

/// Öğe silme ([isFolder] yalnızca silme uçları farklı olan sağlayıcılarda
/// kullanılır, ör. Box).
typedef CloudRemoveFn = Future<void> Function(String id, {bool isFolder});

/// Kullanılan / toplam depolama bilgisi (verilmezse bar gizlenir).
typedef CloudAboutFn = Future<({int used, int total})?> Function();

/// Dropbox, OneDrive ve Box gezinme ekranının ortak gövdesi.
///
/// [CloudBrowseScreen] (WebDAV) desenini izler: ListView ile klasör gezinme,
/// yolda başlık, dosyada ilerme çubuklu indirme, uygulama çubuğunda
/// yenileme / yeni klasör / depolama bilgisi / bağlantı kesme.
class CloudOAuthBrowseScreen extends StatefulWidget {
  const CloudOAuthBrowseScreen({
    super.key,
    required this.title,
    required this.rootFolderId,
    required this.list,
    required this.download,
    required this.createFolder,
    required this.remove,
    this.about,
    this.onDisconnect,
  });

  /// Başlık ve kök klasör adı (ör. 'Dropbox').
  final String title;

  /// Sağlayıcının kök klasör kimliği (Dropbox: '', OneDrive: 'root', Box: '0').
  final String rootFolderId;

  final CloudListFn list;
  final CloudDownloadFn download;
  final CloudCreateFolderFn createFolder;
  final CloudRemoveFn remove;
  final CloudAboutFn? about;
  final Future<void> Function()? onDisconnect;

  @override
  State<CloudOAuthBrowseScreen> createState() => _CloudOAuthBrowseScreenState();
}

/// Ekran yığınındaki klasör.
class _OAuthFolderRef {
  const _OAuthFolderRef(this.id, this.name);

  final String id;
  final String name;
}

/// Uygulama çubuğu menü seçenekleri.
enum _BrowseMenu { newFolder, storage, disconnect }

class _CloudOAuthBrowseScreenState extends State<CloudOAuthBrowseScreen> {
  final _stack = <_OAuthFolderRef>[];
  List<CloudItem> _items = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  ({int used, int total})? _usage;
  bool _progressOpen = false;

  String get _folderId => _stack.last.id;
  String get _path => _stack.map((f) => f.name).join(' / ');

  @override
  void initState() {
    super.initState();
    _stack.add(_OAuthFolderRef(widget.rootFolderId, widget.title));
    _load();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final about = widget.about;
    if (about == null) return;
    try {
      final usage = await about();
      if (!mounted || usage == null) return;
      setState(() => _usage = usage);
    } catch (e) {
      logSwallowed('oauth gezinme: kullanım', e);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.list(folderId: _folderId);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyCloudError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------------------------------------------------------
  // Klasör gezinme
  // -------------------------------------------------------------------------

  void _open(CloudItem item) {
    if (item.isFolder) {
      setState(() => _stack.add(_OAuthFolderRef(item.id, item.name)));
      _load();
      return;
    }
    _download(item);
  }

  void _goUp() {
    if (_stack.length <= 1) return;
    setState(() => _stack.removeLast());
    _load();
  }

  // -------------------------------------------------------------------------
  // Dosya işlemleri
  // -------------------------------------------------------------------------

  /// Dosyayı indirir; hedef Android'de Download klasörü, diğer
  /// platformlarda geçici dizindir. Başarılı olursa "X indirildi" bildirimi.
  Future<void> _download(CloudItem item) async {
    final dir = cloudDownloadDir();
    final target = File(
      '${dir.path}${Platform.pathSeparator}${cloudUniqueName(dir, item.name)}',
    );

    final progress = ValueNotifier<double?>(null);
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
              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              ValueListenableBuilder<double?>(
                valueListenable: progress,
                builder: (context, value, _) =>
                    LinearProgressIndicator(value: value),
              ),
              const SizedBox(height: 8),
              Text(
                'İndiriliyor…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    try {
      await widget.download(
        item.id,
        item.name,
        target.path,
        (value) => progress.value = value.clamp(0.0, 1.0),
      );
      _closeProgress();
      _toast('${item.name} indirildi');
    } catch (e) {
      _closeProgress();
      _toast('İndirilemedi: ${friendlyCloudError(e)}');
    }
    // Notifier diyaloğun çıkış animasyonu sırasında kullanılabileceği için
    // bilinçli olarak dispose edilmez (kısa ömürlü nesnedir).
  }

  Future<void> _delete(CloudItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sil'),
        content: Text('"${item.name}" kalıcı olarak silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.remove(item.id, isFolder: item.isFolder);
      _toast('"${item.name}" silindi');
      await _load();
    } catch (e) {
      _toast('Silinemedi: ${friendlyCloudError(e)}');
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
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.createFolder(_folderId, name);
      _toast('"$name" klasörü oluşturuldu');
      await _load();
    } catch (e) {
      _toast('Oluşturulamadı: ${friendlyCloudError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _info(CloudItem item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tür: ${item.isFolder ? 'Klasör' : 'Dosya'}'),
            Text(
              'Boyut: ${item.size == null ? '—' : Formats.size(item.size!)}',
            ),
            if (item.modified != null)
              Text('Değiştirilme: ${Formats.date(item.modified!)}'),
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

  Future<void> _disconnect() async {
    final onDisconnect = widget.onDisconnect;
    if (onDisconnect == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bağlantıyı kes'),
        content: Text('${widget.title} hesabı bu cihazdan kaldırılsın mı?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kes'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await onDisconnect();
    } catch (_) {
      // Oturum zaten düşmüş ya da revize edilmiş olabilir; gezinme ekranı
      // yine de kapatılır, yeniden bağlanma akışı bozulmaz.
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _closeProgress() {
    if (_progressOpen && mounted) {
      _progressOpen = false;
      Navigator.of(context).pop();
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [..._items]
      ..sort((a, b) {
        if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(_path, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
          PopupMenuButton<_BrowseMenu>(
            onSelected: (action) => switch (action) {
              _BrowseMenu.newFolder => _createFolder(),
              _BrowseMenu.storage => _showStorage(),
              _BrowseMenu.disconnect => _disconnect(),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _BrowseMenu.newFolder,
                child: ListTile(
                  leading: Icon(Icons.create_new_folder_rounded),
                  title: Text('Yeni klasör'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (widget.about != null)
                const PopupMenuItem(
                  value: _BrowseMenu.storage,
                  child: ListTile(
                    leading: Icon(Icons.donut_small_rounded),
                    title: Text('Depolama bilgisi'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (widget.onDisconnect != null)
                const PopupMenuItem(
                  value: _BrowseMenu.disconnect,
                  child: ListTile(
                    leading: Icon(Icons.link_off_rounded),
                    title: Text('Bağlantıyı kes'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_usage != null) _usageBar(theme),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _errorView()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: items.length + 1,
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
                        final item = items[index - 1];
                        return ListTile(
                          leading: Icon(
                            item.isFolder
                                ? Icons.folder_rounded
                                : Icons.insert_drive_file_rounded,
                            color: item.isFolder
                                ? const Color(0xFFFFB300)
                                : theme.colorScheme.primary,
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.isFolder
                                ? 'Klasör'
                                : (item.size == null
                                      ? 'Dosya'
                                      : Formats.size(item.size!)),
                            maxLines: 1,
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Seçenekler',
                            icon: const Icon(Icons.more_vert_rounded),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'info',
                                child: Text('Bilgi'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Sil'),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'info') {
                                _info(item);
                              } else {
                                _delete(item);
                              }
                            },
                          ),
                          onTap: _busy ? null : () => _open(item),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showStorage() {
    final usage = _usage;
    if (usage == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${widget.title} depolama'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kullanılan: ${Formats.size(usage.used)}'),
            Text(
              usage.total > 0
                  ? 'Toplam: ${Formats.size(usage.total)}'
                  : 'Toplam: sınırsız görünüyor',
            ),
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

  Widget _usageBar(ThemeData theme) {
    final usage = _usage!;
    final suffix = usage.total > 0
        ? ' • ${Formats.size(usage.used)} / ${Formats.size(usage.total)}'
        : ' • ${Formats.size(usage.used)} kullanımda';
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.cloud_rounded),
        title: Text(
          '${widget.title}$suffix',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: widget.onDisconnect == null
            ? null
            : IconButton(
                tooltip: 'Bağlantıyı kes',
                icon: const Icon(Icons.link_off_rounded),
                onPressed: _disconnect,
              ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}
