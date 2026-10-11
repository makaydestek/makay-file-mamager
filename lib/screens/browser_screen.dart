import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/file_entry.dart';
import '../providers/settings_provider.dart';
import '../services/clipboard_manager.dart';
import '../services/file_service.dart';
import '../services/recycle_bin_service.dart';
import '../services/root_service.dart';
import '../services/vault_service.dart';
import '../utils/formats.dart';
import '../widgets/folder_tree_panel.dart';
import 'hex_viewer_screen.dart';
import 'image_viewer_screen.dart';
import 'media_viewer_screen.dart';
import 'sqlite_viewer_screen.dart';
import 'text_editor_screen.dart';

/// Önizleme destekli dosya uzantıları.
const kImageExts = {
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'heic', 'heif', 'tif',
  'tiff'
};
const kVideoExts = {
  'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', '3gp', 'm4v', 'ts', 'wmv'
};
const kAudioExts = {'mp3', 'm4a', 'aac', 'flac', 'ogg', 'opus', 'wav', 'wma'};

/// Metin editörüyle açılan düz metin uzantıları.
const kTextExts = {
  'txt', 'md', 'log', 'csv', 'json', 'xml', 'yaml', 'yml', 'ini', 'conf',
  'cfg', 'toml', 'html', 'css', 'js', 'dart', 'kt', 'java', 'py', 'sh', 'bat',
  'gradle', 'properties', 'env', 'srt', 'vtt'
};

/// SQLite veritabanı uzantıları (salt okunur görüntüleyici).
const kSqliteExts = {'db', 'sqlite', 'sqlite3'};

/// Dosya tarayıcı ekranı: breadcrumb, liste, sıralama, arama, dosya işlemleri.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.title,
    required this.rootPath,
    this.showHomeShortcut = true,
  });

  final String title;

  /// Gezinilecek başlangıç dizini (null ise desteklenmeyen platform).
  final String? rootPath;

  /// Breadcrumb'da "Ana" kısayol ikonu gösterilsin mi.
  final bool showHomeShortcut;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  static const _service = FileService();

  late String _path;
  List<FileEntry> _entries = [];
  bool _loading = true;

  // Sıralama.
  bool _sortByName = true;
  bool _sortDescending = false;

  // Arama.
  bool _searchActive = false;
  final _searchController = TextEditingController();
  String _query = '';

  // Çoklu seçim.
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _path = widget.rootPath ?? '';
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_path.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final showHidden = false;
    var entries = await _service.listDirectory(_path, showHidden: showHidden);
    entries = _sort(entries);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
      _selected.clear();
    });
  }

  List<FileEntry> _sort(List<FileEntry> entries) {
    int cmp(FileEntry a, FileEntry b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      final r = switch ((_sortByName, _sortDescending)) {
        (true, false) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        (true, true) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        (false, false) => a.modified.compareTo(b.modified),
        (false, true) => b.modified.compareTo(a.modified),
      };
      return r;
    }

    return List.of(entries)..sort(cmp);
  }

  List<FileEntry> get _visible {
    if (_query.isEmpty) return _entries;
    final q = _query.toLowerCase();
    return _entries.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  void _toggleSelect(FileEntry e) {
    setState(() {
      if (!_selected.remove(e.path)) _selected.add(e.path);
    });
  }

  Future<void> _open(FileEntry e) async {
    if (_selecting) {
      _toggleSelect(e);
      return;
    }
    if (e.isDirectory) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BrowserScreen(
            title: e.name,
            rootPath: e.path,
            showHomeShortcut: widget.showHomeShortcut,
          ),
        ),
      );
      if (mounted) _load();
    } else {
      _openPreview(e);
    }
  }

  /// Dosya türüne göre yerleşik önizleme açılır; desteklenmeyen türde
  /// bilgi diyaloğu gösterilir.
  void _openPreview(FileEntry e) {
    final ext = e.name.contains('.')
        ? e.name.split('.').last.toLowerCase()
        : '';
    if (kImageExts.contains(ext)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerScreen(file: File(e.path), title: e.name),
        ),
      );
    } else if (kVideoExts.contains(ext)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaViewerScreen(
              file: File(e.path), isVideo: true),
        ),
      );
    } else if (kAudioExts.contains(ext)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaViewerScreen(
              file: File(e.path), isVideo: false),
        ),
      );
    } else if (kTextExts.contains(ext)) {
      // Metin editörü: görüntüle + düzenleyip kaydet.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TextEditorScreen(file: File(e.path), title: e.name),
        ),
      );
    } else if (kSqliteExts.contains(ext)) {
      // SQLite görüntüleyici: tablolar + satırlar (salt okunur).
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SqliteViewerScreen(file: File(e.path), title: e.name),
        ),
      );
    } else {
      _showInfo(e);
    }
  }

  /// Satır menüsü: bilgi, metin/hex/SQLite açma, kasaya taşıma.
  void _rowMenu(FileEntry e) {
    final ext = e.name.contains('.') ? e.name.split('.').last.toLowerCase() : '';
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Bilgi'),
              onTap: () {
                Navigator.pop(context);
                _showInfo(e);
              },
            ),
            if (!e.isDirectory && kTextExts.contains(ext))
              ListTile(
                leading: const Icon(Icons.text_snippet_outlined),
                title: const Text('Metin olarak aç'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TextEditorScreen(file: File(e.path), title: e.name),
                    ),
                  );
                },
              ),
            if (!e.isDirectory)
              ListTile(
                leading: const Icon(Icons.data_object_rounded),
                title: const Text('Hex görüntüle'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          HexViewerScreen(file: File(e.path), title: e.name),
                    ),
                  );
                },
              ),
            if (!e.isDirectory && kSqliteExts.contains(ext))
              ListTile(
                leading: const Icon(Icons.table_chart_rounded),
                title: const Text('SQLite tablolarını görüntüle'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SqliteViewerScreen(
                          file: File(e.path), title: e.name),
                    ),
                  );
                },
              ),
            if (!e.isDirectory)
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Kasaya taşı'),
                subtitle: const Text('PIN ile şifrelenir, kasa dışında saklanır'),
                onTap: () {
                  Navigator.pop(context);
                  _addToVault(e);
                },
              ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('İzinleri değiştir (chmod)'),
              subtitle: const Text('Root\'lu cihazlarda dosya izinleri'),
              onTap: () {
                Navigator.pop(context);
                _chmodDialog(e);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Dosyayı kopyalayıp şifreli kasaya ekler (kaynak dosya yerinde kalır).
  Future<void> _addToVault(FileEntry e) async {
    if (!VaultService.unlocked) {
      // Önce kasa ekranı açılır; kullanıcı PIN ile girip döner.
      final opened = await Navigator.of(context).pushNamed('/vault');
      if (opened != true || !mounted) return;
    }
    if (!mounted || !VaultService.unlocked) return;
    try {
      final entry = await VaultService.add(File(e.path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.name} kasaya eklendi (şifrelendi)')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kasaya eklenemedi: $err')),
      );
    }
  }

  /// Root'lu cihazlarda izin değiştirme diyaloğu; root yoksa bilgilendirir.
  Future<void> _chmodDialog(FileEntry e) async {
    final rooted = await RootService.isRooted();
    if (!mounted) return;
    if (!rooted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Kök (root) erişimi bulunamadı. chmod yalnızca root\'lu '
              'cihazlarda çalışır.'),
        ),
      );
      return;
    }
    var current = '';
    try {
      current = RootService.modeToString(File(e.path).statSync().mode);
    } catch (_) {}
    final controller = TextEditingController(text: RootService.parseMode(current) ?? '644');
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İzinleri değiştir (chmod)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text('Mevcut: $current'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Yeni izin (sekizlik)',
                hintText: '644, 755, 0755 …',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    if (mode == null || mode.isEmpty) return;
    try {
      final ok = await RootService.chmod(e.path, mode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'İzinler güncellendi: $mode'
              : 'chmod başarısız oldu'),
        ),
      );
      if (ok && mounted) _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $err')),
      );
    }
  }

  /// Çift panel sürükle-bırak: dosya hedef klasöre kopyalanır.
  Future<void> _copyToFolder(String filePath, String targetFolder) async {
    if (filePath == targetFolder) return;
    // Kendi kendine kopyalama engeli.
    final parent = File(filePath).parent.path;
    if (parent == targetFolder) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dosya zaten bu klasörde')),
      );
      return;
    }
    try {
      await _service.copyPath(filePath, targetFolder);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${File(filePath).path.split(Platform.pathSeparator).last} '
              'kopyalandı → $targetFolder'),
        ),
      );
      // Hedef bu ekrandaysa liste tazelenir.
      if (targetFolder == _path && mounted) _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kopyalanamadı: $err')),
      );
    }
  }

  /// Seçili dosyaları sistem paylaşım sayfasıyla paylaş.
  Future<void> _shareSelected() async {
    final paths = _entries
        .where((e) => _selected.contains(e.path) && !e.isDirectory)
        .map((e) => e.path)
        .toList();
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paylaşılacak dosya seçin')),
      );
      return;
    }
    setState(_selected.clear);
    await SharePlus.instance.share(
      ShareParams(files: [for (final p in paths) XFile(p)]),
    );
  }

  Future<void> _paste() async {
    final clipboard = ClipboardManager.instance;
    if (clipboard.isEmpty) return;
    final target = _path;
    for (final entry in clipboard.entries) {
      try {
        if (clipboard.isCut) {
          await _service.moveEntry(entry, target);
        } else {
          await _service.copyEntry(entry, target);
        }
      } catch (_) {}
    }
    if (clipboard.isCut) clipboard.clear();
    if (mounted) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yapıştırıldı: ${clipboard.entries.length} öğe')),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final settings = context.read<SettingsProvider>();
    final count = _selected.length;
    final useBin = settings.recycleBinDefault;
    var confirmed = !settings.recycleBinConfirm;
    if (!confirmed) {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(useBin ? 'Geri dönüşüm kutusuna taşı' : 'Kalıcı sil'),
              content: Text('$count öğe silinecek.'),
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
    }
    if (!confirmed) return;
    for (final path in _selected) {
      final entry = _entries.where((e) => e.path == path).firstOrNull;
      if (entry == null) continue;
      try {
        if (useBin) {
          await RecycleBinService.instance.moveToRecycle(entry);
        } else {
          await _service.deleteEntry(path, useRecycleBin: false);
        }
      } catch (_) {}
    }
    if (mounted) _load();
  }

  Future<void> _rename(FileEntry e) async {
    final controller = TextEditingController(text: e.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeniden adlandır'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Yeni ad'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == e.name) return;
    try {
      await _service.rename(e.path, newName);
    } catch (_) {}
    if (mounted) _load();
  }

  Future<void> _newFolder() async {
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
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await _service.createDirectory('$_path${Platform.pathSeparator}$name');
    } catch (_) {}
    if (mounted) _load();
  }

  void _showInfo(FileEntry e) {
    final datePattern = context.read<SettingsProvider>().datePattern;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(e.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tür: ${e.kind.name}'),
            Text('Boyut: ${Formats.size(e.size)}'),
            Text(
                'Değiştirilme: ${Formats.date(e.modified, pattern: datePattern)}'),
            if (_permissionText(e.path) != null)
              Text('İzinler: ${_permissionText(e.path)}'),
            const SizedBox(height: 8),
            SelectableText('Konum: ${e.path}'),
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

  /// POSIX izin metni (ör. "-rw-r--r--"); alınamazsa null.
  static String? _permissionText(String path) {
    try {
      final stat = File(path).statSync();
      return RootService.modeToString(stat.mode);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickSort() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => SimpleDialog(
          title: const Text('Sırala'),
          children: [
            RadioGroup<bool>(
              groupValue: _sortByName,
              onChanged: (v) {
                if (v != null) {
                  setDialogState(() => _sortByName = v);
                  setState(() => _entries = _sort(_entries));
                }
              },
              child: Column(
                children: [
                  const RadioListTile<bool>(title: Text('Ad'), value: true),
                  const RadioListTile<bool>(
                      title: Text('Değiştirilme tarihi'), value: false),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Azalan'),
              value: _sortDescending,
              onChanged: (v) {
                setDialogState(() => _sortDescending = v);
                setState(() => _entries = _sort(_entries));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clipboard = ListenableBuilder(
      listenable: ClipboardManager.instance,
      builder: (context, _) => const SizedBox.shrink(),
    );

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
            : (_searchActive
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.black87),
                    decoration: const InputDecoration(
                      hintText: 'Ara…',
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  )
                : Text(widget.title)),
        actions: [
          if (!_selecting) ...[
            IconButton(
              icon: Icon(_searchActive ? Icons.close_rounded : Icons.search),
              onPressed: () {
                setState(() {
                  _searchActive = !_searchActive;
                  if (!_searchActive) {
                    _searchController.clear();
                    _query = '';
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.sort_rounded),
              onPressed: _pickSort,
              tooltip: 'Sırala',
            ),
            if (!ClipboardManager.instance.isEmpty && !_searchActive)
              IconButton(
                icon: const Icon(Icons.paste_rounded),
                onPressed: _paste,
                tooltip: 'Yapıştır',
              ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'new_folder':
                    _newFolder();
                  case 'refresh':
                    _load();
                  case 'select_all':
                    setState(() {
                      _selected
                        ..clear()
                        ..addAll(_visible.map((e) => e.path));
                    });
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'new_folder', child: Text('Yeni klasör')),
                PopupMenuItem(value: 'select_all', child: Text('Tümünü seç')),
                PopupMenuItem(value: 'refresh', child: Text('Yenile')),
              ],
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () {
                ClipboardManager.instance.copy(
                    _entries.where((e) => _selected.contains(e.path)).toList());
                setState(_selected.clear);
              },
              tooltip: 'Kopyala',
            ),
            IconButton(
              icon: const Icon(Icons.content_cut_rounded),
              onPressed: () {
                ClipboardManager.instance.cut(
                    _entries.where((e) => _selected.contains(e.path)).toList());
                setState(_selected.clear);
              },
              tooltip: 'Taşı',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deleteSelected,
              tooltip: 'Sil',
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded),
              onPressed: _shareSelected,
              tooltip: 'Paylaş',
            ),
            IconButton(
              icon: const Icon(Icons.drive_file_rename_outline_rounded),
              onPressed: _selected.length == 1
                  ? () => _rename(_entries
                      .where((e) => _selected.contains(e.path))
                      .first)
                  : null,
              tooltip: 'Yeniden adlandır',
            ),
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: _selected.length == 1
                  ? () => _showInfo(_entries
                      .where((e) => _selected.contains(e.path))
                      .first)
                  : null,
              tooltip: 'Bilgi',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Yer tutucu: ListenableBuilder'ı gövdede tutmak için.
          Offstage(child: clipboard),
          if (!_selecting) _breadcrumb(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Geniş ekran (tablet): sol klasör ağacı + sağ içerik.
                if (constraints.maxWidth < 900 || widget.rootPath == null) {
                  return _buildBody(context);
                }
                return Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: FolderTreePanel(
                        rootPath: widget.rootPath!,
                        currentPath: _path,
                        onSelected: (path) {
                          if (path == _path) return;
                          final sep = '/';
                          final i = path.lastIndexOf(sep);
                          final name =
                              i >= 0 ? path.substring(i + 1) : path;
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => BrowserScreen(
                                title: name.isEmpty ? path : name,
                                rootPath: path,
                                showHomeShortcut: widget.showHomeShortcut,
                              ),
                            ),
                          );
                        },
                        // Çift panel: listeden ağaç düğümüne sürüklenen dosya
                        // kopyalanır (X-plore tarzı).
                        onDrop: _copyToFolder,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildBody(context)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumb() {
    final sep = Platform.pathSeparator;
    final parts = <String>[];
    var rest = _path;
    while (rest.isNotEmpty) {
      final i = rest.lastIndexOf(sep);
      final seg = i >= 0 ? rest.substring(i + 1) : rest;
      parts.insert(0, seg);
      rest = i >= 0 ? rest.substring(0, i) : '';
    }
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            if (widget.showHomeShortcut)
              IconButton(
                icon: const Icon(Icons.home_rounded, size: 22),
                tooltip: 'Ana dizin',
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              ),
            for (var i = 0; i < parts.length; i++) ...[
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Colors.grey),
              TextButton(
                onPressed: () {
                  // İlgili segmente kadar yol bulunur ve oraya dönülür.
                  final idx = _path.indexOf(sep);
                  var acc = i == 0 && idx == 0 ? sep : '';
                  for (var k = 0; k <= i; k++) {
                    acc = k == 0
                        ? (i == 0 && idx == 0 ? sep : parts[0])
                        : '$acc$sep${parts[k]}';
                  }
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => BrowserScreen(
                        title: parts[i],
                        rootPath: acc,
                        showHomeShortcut: widget.showHomeShortcut,
                      ),
                    ),
                  );
                },
                child: Text(parts[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final datePattern = context.select<SettingsProvider, String>(
        (s) => s.datePattern);
    if (widget.rootPath == null || _path.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Bu platformda dosya erişimi desteklenmiyor.\n'
            'Android cihazda tam işlevsellik sunulur.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'Boş Klasör' : 'Sonuç bulunamadı',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final e = visible[index];
          final selected = _selected.contains(e.path);
          final tile = ListTile(
            selected: selected,
            selectedTileColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            leading: Icon(e.icon, color: e.color, size: 32),
            title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            // Referans uygulamadaki gibi "(Tarih • Boyut)" biçiminde.
            subtitle: Text(
              '(${Formats.date(e.modified, pattern: datePattern)}'
              '${e.isDirectory ? ' • Klasör' : ' • ${Formats.size(e.size)}'})',
              maxLines: 1,
            ),
            trailing: _selecting
                ? Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  )
                : IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    tooltip: 'Daha fazla',
                    onPressed: () => _rowMenu(e),
                  ),
            onTap: () => _open(e),
            onLongPress: () => _toggleSelect(e),
          );
          // Çift panel (tablet): uzun basıp sürükleyerek sol paneldeki
          // klasör ağacına kopyalanır; seçiliyken sürüklenemez.
          if (_selecting) return tile;
          return LongPressDraggable<String>(
            data: e.path,
            feedback: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: ListTile(
                  dense: true,
                  leading: Icon(e.icon, color: e.color, size: 24),
                  title: Text(e.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            childWhenDragging:
                Opacity(opacity: 0.4, child: tile),
            child: tile,
          );
        },
      ),
    );
  }
}
