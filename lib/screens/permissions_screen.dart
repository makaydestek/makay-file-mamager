import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/permission_service.dart';

/// İlk açılışta (ve Ayarlar'dan) cihaz izinlerini isteyen ekran (A18).
///
/// Sistem "tüm dosyalara erişim" ekranından dönüldüğünde durum otomatik
/// tazelenir. En az bir izin verilmeden "Devam et" açılmaz.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  PermissionStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sistem ayar ekranından dönüldü.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await PermissionService.check();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _requestAllFiles() async {
    setState(() => _busy = true);
    final status = await PermissionService.requestAllFilesAccess();
    if (!mounted) return;
    setState(() {
      _status = status;
      _busy = false;
    });
  }

  Future<void> _requestMedia() async {
    setState(() => _busy = true);
    final status = await PermissionService.requestMediaPermissions();
    if (!mounted) return;
    setState(() {
      _status = status;
      _busy = false;
    });
  }

  void _continue() {
    context.read<SettingsProvider>().permissionsOnboarded = true;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _skip() {
    context.read<SettingsProvider>().permissionsOnboarded = true;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    final allFilesOk = status?.allFiles ?? false;
    final mediaOk = (status?.media ?? false) || allFilesOk;
    final ready = status?.ready ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Gerekli İzinler')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.shield_rounded,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'Uygulamanın çalışması için izinler',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Dosyalarınızı görmek ve düzenlemek için aşağıdaki izinleri '
                'vermeniz gerekiyor. İzinler yalnızca cihazınızda kalır.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (status == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                _PermissionCard(
                  icon: Icons.folder_special_rounded,
                  title: 'Tüm dosyalara erişim',
                  description:
                      'Dosyaları listelemek, kopyalamak, taşımak ve silmek için '
                      'gereklidir. Android ayarlarında açılır.',
                  granted: allFilesOk,
                  grantedNote: allFilesOk ? null : 'Zorunlu',
                  busy: _busy,
                  onRequest: _requestAllFiles,
                ),
                const SizedBox(height: 12),
                _PermissionCard(
                  icon: Icons.perm_media_rounded,
                  title: 'Medya erişimi',
                  description: 'Görüntüler, Videolar ve Ses ekranlarının '
                      'dosyaları görebilmesi için gereklidir.',
                  granted: mediaOk,
                  busy: _busy,
                  onRequest: _requestMedia,
                  coveredByAllFiles: allFilesOk && !status.media,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: ready ? _continue : null,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(ready ? 'Devam et' : 'Devam etmek için izin ver'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _skip,
                  child: const Text('Yine de devam et (sınırlı kullanım)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.busy,
    required this.onRequest,
    this.grantedNote,
    this.coveredByAllFiles = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final bool busy;
  final Future<void> Function() onRequest;
  final String? grantedNote;
  final bool coveredByAllFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = granted;
    final statusColor = ok ? Colors.green : Colors.orange;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: (ok ? Colors.green : Colors.orange).withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    coveredByAllFiles
                        ? '$description (Tüm dosyalara erişim ile kapsanıyor)'
                        : description,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        ok ? Icons.check_circle_rounded : Icons.error_outline,
                        size: 18,
                        color: statusColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        ok ? 'İzin verildi' : 'İzin verilmedi',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: statusColor),
                      ),
                      if (grantedNote != null) ...[
                        const SizedBox(width: 6),
                        Text(grantedNote!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!ok)
              FilledButton.tonal(
                onPressed: busy ? null : () => onRequest(),
                child: const Text('İzin ver'),
              ),
          ],
        ),
      ),
    );
  }
}