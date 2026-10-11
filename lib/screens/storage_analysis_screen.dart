import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../services/analysis_service.dart';
import '../services/platform_service.dart';
import '../utils/formats.dart';
import '../widgets/treemap_view.dart';
import 'apps_screen.dart';
import 'large_files_screen.dart';

/// Bellek Analizi ekranı — referans uygulamanın analiz ekranının karşılığı.
class StorageAnalysisScreen extends StatefulWidget {
  const StorageAnalysisScreen({super.key});

  @override
  State<StorageAnalysisScreen> createState() => _StorageAnalysisScreenState();
}

class _StorageAnalysisScreenState extends State<StorageAnalysisScreen> {
  static const _analysis = AnalysisService();

  ({int total, int free})? _storage;
  Map<String, int> _breakdown = {};
  List<InstalledApp> _topApps = [];
  int _appsTotalSize = 0;
  List<FileEntry> _largeFiles = [];
  int _largeTotal = 0;
  int _cache = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final storage = await PlatformService.storageInfo();
    final breakdown = await _analysis.categoryBreakdown();
    final apps = await PlatformService.installedApps();
    final large = await _analysis.largeFiles();
    final cache = await _analysis.cacheSize();

    apps.sort((a, b) => b.size.compareTo(a.size));
    if (!mounted) return;
    setState(() {
      _storage = storage;
      _breakdown = breakdown;
      _topApps = apps.take(2).toList();
      _appsTotalSize = apps.fold(0, (s, a) => s + (a.size > 0 ? a.size : 0));
      _largeFiles = large.take(2).toList();
      _largeTotal = large.fold(0, (s, f) => s + f.size);
      _cache = cache;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bellek Analizi')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _storageCard(theme),
                  const SizedBox(height: 12),
                  _appsCard(theme),
                  const SizedBox(height: 12),
                  _largeFilesCard(theme),
                  const SizedBox(height: 12),
                  _cacheCard(theme),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  /// Kart 1: Ana bellek — kullanım yüzdesi + kategori dağılımı.
  Widget _storageCard(ThemeData theme) {
    final total = _storage?.total ?? 0;
    final free = _storage?.free ?? 0;
    final usedPercent = total > 0 ? ((total - free) / total * 100) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Ana bellek', style: theme.textTheme.headlineSmall),
                Text(
                  'Boş ${Formats.size(free)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '${usedPercent.toStringAsFixed(0)}%',
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? usedPercent / 100 : 0,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 16),
            _breakdownGrid(theme),
            const SizedBox(height: 16),
            // Görsel depolama haritası (treemap): kategori alanları
            // kare oranına en yakın dikdörtgenlerle çizilir.
            if (_breakdownEntries().isNotEmpty) ...[
              Text('Görsel harita', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TreemapView(
                items: _breakdownEntries(),
                height: 200,
              ),
            ],
            const Divider(height: 24),
            _moreButton(context, 'DAHA FAZLA', () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const LargeFilesScreen(
                        title: 'Depolama dağılımı')),
              );
            }),
          ],
        ),
      ),
    );
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
            label: e.key,
            size: e.value,
            color: colors[e.key] ?? const Color(0xFF9E9E9E),
          ),
    ];
  }

  /// Kategori dağılımı: ikon + ad + boyut (2 sütun).
  Widget _breakdownGrid(ThemeData theme) {    const icons = <String, (IconData, Color)>{
      'Resimler': (Icons.image_rounded, Color(0xFF8E24AA)),
      'Videolar': (Icons.video_library_rounded, Color(0xFFD32F2F)),
      'Ses': (Icons.music_note_rounded, Color(0xFF00897B)),
      'Belgeler': (Icons.description_rounded, Color(0xFF1976D2)),
      'Arşivler': (Icons.folder_zip_rounded, Color(0xFF6D4C41)),
      'Diğerleri': (Icons.more_horiz_rounded, Color(0xFF757575)),
    };
    final entries = _breakdown.entries.toList();
    return Column(
      children: [
        for (var i = 0; i < entries.length; i += 2)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                for (var j = i; j < i + 2 && j < entries.length; j++) ...[
                  Expanded(
                    child: Builder(builder: (context) {
                      final e = entries[j];
                      final (icon, color) = icons[e.key] ??
                          (Icons.folder_rounded, Colors.grey);
                      return Row(
                        children: [
                          Icon(icon, color: color, size: 20),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(e.key,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium),
                          ),
                          Text(Formats.size(e.value),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.outline)),
                        ],
                      );
                    }),
                  ),
                  if (j == i && j + 1 < entries.length)
                    const SizedBox(width: 16),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// Kart 2: Uygulamalar — toplam + en büyük iki uygulama.
  Widget _appsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Uygulamalar', style: theme.textTheme.headlineSmall),
                Text(
                  Formats.size(_appsTotalSize),
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final app in _topApps)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: app.icon != null
                    ? Image.memory(app.icon!, width: 32, height: 32)
                    : const Icon(Icons.android_rounded),
                title: Text(app.name),
                trailing: Text(
                  app.size > 0 ? Formats.size(app.size) : '—',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ),
            const Divider(height: 16),
            _moreButton(context, 'DAHA FAZLA', () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AppsScreen()),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Kart 3: Büyük dosyalar — 10 MB üzeri.
  Widget _largeFilesCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Büyük dosyalar', style: theme.textTheme.headlineSmall),
                Text(
                  Formats.size(_largeTotal),
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text("10 MB'dan büyük dosyalar",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 8),
            for (final f in _largeFiles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(f.icon, color: f.color),
                title: Text(f.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(f.path
                    .replaceAll('/storage/emulated/0', '')
                    .ifEmpty('/')),
                trailing: Text(Formats.size(f.size),
                    style: TextStyle(color: theme.colorScheme.primary)),
              ),
            const Divider(height: 16),
            _moreButton(context, 'DAHA FAZLA', () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LargeFilesScreen()),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Kart 4: Önbellek dosyaları.
  Widget _cacheCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Ön bellek dosyaları',
                    style: theme.textTheme.headlineSmall),
                Text(
                  Formats.size(_cache),
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ön bellek dosyaları, uygulamalar tarafından depolanan '
              'geçici dosyalardır.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moreButton(BuildContext context, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
