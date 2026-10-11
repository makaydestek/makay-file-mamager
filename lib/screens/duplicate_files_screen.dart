import 'dart:io';

import 'package:flutter/material.dart';

import '../services/duplicate_service.dart';
import '../theme/app_theme.dart';
import '../utils/formats.dart';

/// Mükerrer dosya ekranı: [root] altındaki aynı içeriğe sahip dosyaları
/// bulur ve tek kopya bırakarak temizleme imkânı verir.
///
/// Tarama izolatta yapılır; kullanıcı açılışta döner göstergesi görür,
/// sonuçlar gruplar hâlinde listelenir.
class DuplicateFilesScreen extends StatefulWidget {
  const DuplicateFilesScreen({super.key, required this.root});

  /// Tarama kökü; Android ana depolamada '/storage/emulated/0' (testlerde
  /// geçici dizin verilir).
  final String root;

  @override
  State<DuplicateFilesScreen> createState() => _DuplicateFilesScreenState();
}

class _DuplicateFilesScreenState extends State<DuplicateFilesScreen> {
  List<DuplicateGroup>? _groups;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Boşa harcanan toplam alan (tek kopyalar hariç).
  int get _totalWasted =>
      (_groups ?? const <DuplicateGroup>[])
          .fold(0, (sum, g) => sum + g.wasted);

  Future<void> _load() async {
    final groups = await DuplicateService.find(widget.root);
    if (!mounted) return;
    setState(() => _groups = groups);
  }

  /// [paths] dosyalarını siler, listeyi günceller ve kullanıcıya bilgi verir.
  Future<void> _remove(List<String> paths) async {
    if (paths.isEmpty || _working) return;
    setState(() => _working = true);
    final freed = await DuplicateService.delete(paths);
    if (!mounted) return;
    final deleted = paths.where((p) => !File(p).existsSync()).length;
    // Yeniden tarama gerekmez: silinen yollar gruplardan düşülür.
    final removed = paths.toSet();
    setState(() {
      _groups = (_groups ?? const <DuplicateGroup>[])
          .map((g) => DuplicateGroup(
                size: g.size,
                paths: g.paths.where((p) => !removed.contains(p)).toList(),
              ))
          .where((g) => g.count > 1)
          .toList();
      _working = false;
    });
    if (deleted == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$deleted silindi, ${Formats.size(freed)} alan kazanıldı'),
      ),
    );
  }

  /// Her gruptan bir kopya bırakarak tüm mükerrerleri siler.
  Future<void> _confirmAndCleanAll() async {
    final groups = _groups ?? const <DuplicateGroup>[];
    if (groups.isEmpty || _working) return;
    final doomed = <String>[
      for (final g in groups) ...g.paths.skip(1),
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tümünü sil'),
        content: Text(
          '${doomed.length} mükerrer dosya silinecek '
          '(${Formats.size(_totalWasted)} alan geri kazanılacak); her '
          'gruptan bir kopya korunacak. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _remove(doomed);
  }

  /// Satıra dokunulunda yolun kopyalanabilmesi için bilgi diyaloğu.
  void _showPathInfo(String path) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dosya yolu'),
        content: SelectableText(path),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mükerrer Dosyalar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Yeniden tara',
            onPressed: _working || groups == null ? null : _load,
          ),
        ],
      ),
      body: groups == null
          ? const Center(child: CircularProgressIndicator())
          : groups.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Mükerrer dosya bulunamadı.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _summaryCard(theme),
                    const SizedBox(height: 8),
                    for (final g in groups) _groupCard(theme, g),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  /// Üstteki özet: grup sayısı, kazanılabilir alan ve toplu temizlik.
  Widget _summaryCard(ThemeData theme) {
    final groups = _groups ?? const <DuplicateGroup>[];
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${groups.length} grup bulundu, '
              '${Formats.size(_totalWasted)} alan geri kazanılabilir',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _working || groups.isEmpty ? null : _confirmAndCleanAll,
              icon: const Icon(Icons.cleaning_services_rounded),
              label: const Text('TEMİZLE'),
            ),
          ],
        ),
      ),
    );
  }

  /// Tek bir mükerrer grup: başlık + dosya yolları.
  Widget _groupCard(ThemeData theme, DuplicateGroup group) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.copy_all_rounded,
                    size: 20, color: AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${Formats.size(group.wasted)} • ${group.count} kopya',
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Flexible(
                  child: TextButton(
                    onPressed: _working
                        ? null
                        : () => _remove(group.paths.skip(1).toList()),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Tümünü sil (birini tut)'),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 8),
            for (final path in group.paths)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.insert_drive_file_outlined, size: 20),
                title: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Bu kopyayı sil',
                  onPressed: _working ? null : () => _remove([path]),
                ),
                onTap: () => _showPathInfo(path),
              ),
          ],
        ),
      ),
    );
  }
}
