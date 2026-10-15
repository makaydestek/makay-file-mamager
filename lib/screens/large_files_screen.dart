import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../services/analysis_service.dart';
import '../utils/formats.dart';
import '../utils/text_utils.dart';
import '../widgets/treemap_view.dart';

/// Büyük dosyaların tam listesi ("DAHA FAZLA" ekranı).
///
/// [showBreakdown] ile en üste kategori dağılımı haritası (treemap) de
/// eklenir; bu mod, analiz ekranındaki "Depolama dağılımı" bağlantısının
/// hedefidir.
class LargeFilesScreen extends StatefulWidget {
  const LargeFilesScreen({
    super.key,
    this.title = 'Büyük dosyalar',
    this.showBreakdown = false,
  });

  final String title;

  /// En üste kategori dağılımı (treemap) bölümü gösterilsin mi.
  final bool showBreakdown;

  @override
  State<LargeFilesScreen> createState() => _LargeFilesScreenState();
}

class _LargeFilesScreenState extends State<LargeFilesScreen> {
  static const _analysis = AnalysisService();

  var _loading = true;
  List<FileEntry> _files = const [];
  Map<String, int> _breakdown = const {};

  /// Kategori adı gösterimi (referans ekranda "Resimler" → "Görüntüler").
  static String _label(String key) => key == 'Resimler' ? 'Görüntüler' : key;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await _analysis.largeFiles(limit: 500);
    final breakdown =
        widget.showBreakdown ? await _analysis.categoryBreakdown() : const <String, int>{};
    if (!mounted) return;
    setState(() {
      _files = files;
      _breakdown = breakdown;
      _loading = false;
    });
  }

  /// Kategori dağılımı → treemap öğeleri (boyut > 0).
  List<TreemapItem> _breakdownEntries() {
    const colors = <String, Color>{
      'Resimler': Color(0xFF8E24AA),
      'Videolar': Color(0xFFD32F2F),
      'Ses': Color(0xFF00897B),
      'Belgeler': Color(0xFF1976D2),
      'Arşivler': Color(0xFF6D4C41),
      'Diğerleri': Color(0xFF757575),
    };
    return [
      for (final e in _breakdown.entries)
        if (e.value > 0)
          TreemapItem(
            label: _label(e.key),
            size: e.value,
            color: colors[e.key] ?? const Color(0xFF9E9E9E),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  // Depolama dağılımı modunda: kategori haritası en üste.
                  if (widget.showBreakdown &&
                      _breakdownEntries().isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Text('Kategori dağılımı',
                          style: theme.textTheme.titleMedium),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TreemapView(items: _breakdownEntries(), height: 200),
                    ),
                    const Divider(height: 1),
                  ],
                  if (_files.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: Text('10 MB üzerinde dosya bulunamadı')),
                    )
                  else
                    for (final f in _files) _fileTile(theme, f),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _fileTile(ThemeData theme, FileEntry f) {
    return ListTile(
      leading: Icon(f.icon, color: f.color),
      title:
          Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        f.path
            .replaceAll('/storage/emulated/0', '')
            .ifEmpty('/'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(Formats.size(f.size),
          style: TextStyle(color: theme.colorScheme.primary)),
    );
  }
}
