import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../services/file_service.dart';

/// Tablet/Geniş ekran için klasör ağacı paneli (sol panel).
///
/// Kök dizinden başlayarak açılan klasörleri lazy yükler; bir klasöre
/// tıklandığında [onSelected] çağrılır.
class FolderTreePanel extends StatefulWidget {
  const FolderTreePanel({
    super.key,
    required this.rootPath,
    required this.currentPath,
    required this.onSelected,
    this.onDrop,
  });

  final String rootPath;
  final String currentPath;
  final ValueChanged<String> onSelected;

  /// Klasör düğümüne bir dosya sürüklendiğinde (yol, hedef klasör).
  /// Verilirse ağaç düğümleri sürükleme hedefi olur (çift panel kopyalama).
  final void Function(String filePath, String targetFolder)? onDrop;

  @override
  State<FolderTreePanel> createState() => _FolderTreePanelState();
}

class _FolderTreePanelState extends State<FolderTreePanel> {
  static const _service = FileService();

  /// Klasör yolu → alt klasörler.
  final _children = <String, List<FileEntry>>{};
  final _loadingPaths = <String>{};

  @override
  void initState() {
    super.initState();
    _expandTo(widget.currentPath);
  }

  @override
  void didUpdateWidget(covariant FolderTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPath != widget.currentPath) {
      _expandTo(widget.currentPath);
    }
  }

  /// [path]'e kadar tüm üst klasörleri otomatik açar.
  void _expandTo(String path) {
    if (path.isEmpty) return;
    final sep = String.fromCharCode(0x2F); // '/'
    final parts = <String>[];
    var rest = path;
    while (rest.isNotEmpty) {
      final i = rest.lastIndexOf(sep);
      final seg = i >= 0 ? rest.substring(i + 1) : rest;
      parts.insert(0, seg);
      rest = i >= 0 ? rest.substring(0, i) : '';
    }
    // Kökten başlayarak her seviyeyi yükle.
    var acc = '';
    for (var i = 0; i < parts.length; i++) {
      acc = i == 0 ? (path.startsWith('/') ? '/${parts[0]}' : parts[0]) : '$acc$sep${parts[i]}';
      if (i < parts.length - 1) _ensureLoaded(acc);
    }
    // Son düğümün (klasörün) altlarını da yükle ki seçili görünür olsun.
    _ensureLoaded(path);
  }

  Future<void> _ensureLoaded(String path) async {
    if (_children.containsKey(path) || _loadingPaths.contains(path)) return;
    _loadingPaths.add(path);
    try {
      final entries = await _service.listDirectory(path);
      if (!mounted) return;
      setState(() {
        _children[path] =
            entries.where((e) => e.isDirectory).toList(growable: false);
      });
    } catch (_) {
      if (mounted) setState(() => _children[path] = const []);
    } finally {
      _loadingPaths.remove(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _node(theme, widget.rootPath, _basename(widget.rootPath),
            isRoot: true),
      ],
    );
  }

  String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i >= 0 && i < path.length - 1 ? path.substring(i + 1) : path;
  }

  Widget _node(ThemeData theme, String path, String name, {bool isRoot = false}) {
    final kids = _children[path];
    final loading = _loadingPaths.contains(path);
    final selected = path == widget.currentPath;
    final sep = '/';
    final childPaths = path.endsWith(sep) && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;

    Widget label = Row(
      children: [
        Icon(
          isRoot ? Icons.home_rounded : Icons.folder_rounded,
          size: 18,
          color: selected
              ? theme.colorScheme.primary
              : const Color(0xFFFFB300),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? theme.colorScheme.primary : null,
            ),
          ),
        ),
        if (loading)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );

    // Sürükle-bırak hedefi: dosya bu klasöre bırakılınca [onDrop] çağrılır.
    Widget node = label;
    final onDrop = widget.onDrop;
    if (onDrop != null) {
      node = DragTarget<String>(
        onWillAcceptWithDetails: (details) =>
            details.data.isNotEmpty && details.data != path,
        onAcceptWithDetails: (details) => onDrop(details.data, path),
        builder: (context, candidate, rejected) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: candidate.isNotEmpty
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: label,
        ),
      );
    }

    if (kids == null || kids.isEmpty) {
      // Yaprak: tıklanabilir düğüm.
      return InkWell(
        onTap: () {
          if (kids == null) _ensureLoaded(path);
          widget.onSelected(path);
        },
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: SizedBox(height: 36, child: node),
        ),
      );
    }

    return ExpansionTile(
      initiallyExpanded: selected ||
          widget.currentPath.startsWith('$childPaths$sep'),
      dense: true,
      tilePadding: const EdgeInsets.only(left: 4, right: 8),
      childrenPadding: const EdgeInsets.only(left: 12),
      onExpansionChanged: (open) {
        if (open) _ensureLoaded(path);
      },
      title: GestureDetector(onTap: () => widget.onSelected(path), child: node),
      children: [
        for (final kid in kids)
          _node(theme, kid.path, kid.name),
      ],
    );
  }
}
