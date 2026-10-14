import 'dart:io';

import 'package:flutter/material.dart';

import '../services/platform_service.dart';
import '../services/update_service.dart';
import '../utils/formats.dart';

/// İndirilenler'de bir `.apk` dosyasına dokununca açılan kurulum diyaloğu.
///
/// F Dosya Yöneticisi'ndeki gibi: uygulama adı, paket adı, boyut, mevcut ve
/// cihazda kurulu sürümler gösterilir; düğme duruma göre **"Kur"** ya da
/// **"Güncelle"** olur ve dokununca Android kurucusu (Package Installer)
/// açılır. Bilgi okunamazsa yalnız dosya adı/boyutuyla yine de kurulabilir.
Future<void> showApkInstallDialog(BuildContext context, File file) {
  return showDialog<void>(
    context: context,
    builder: (context) => ApkInstallDialog(file: file),
  );
}

/// [showApkInstallDialog] için tek görünüm (test edilebilir).
class ApkInstallDialog extends StatefulWidget {
  const ApkInstallDialog({super.key, required this.file});

  final File file;

  @override
  State<ApkInstallDialog> createState() => _ApkInstallDialogState();
}

class _ApkInstallDialogState extends State<ApkInstallDialog> {
  /// Paket bilgisi arka planda okunur; sırada bekleme göstergesi gösterilir.
  ApkInfo? _info;
  bool _loading = true;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PlatformService.apkInfo(widget.file.path);
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  String get _fileName {
    final p = widget.file.path.replaceAll('\\', '/');
    return p.split('/').last;
  }

  /// Kurulum düğmesinin metni: kurulu değilse "Kur", eski sürümsa
  /// "Güncelle", aynı sürüm kuruluysa yine de "Güncelle" (Android
  /// kurucusu bunu zaten "Bu uygulama zaten kurulu" olarak çözer).
  String get _actionLabel {
    final info = _info;
    if (info == null || !info.installed) return 'Kur';
    return 'Güncelle';
  }

  Future<void> _install() async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      await UpdateService.install(widget.file);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _installing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kurulum başlatılamadı: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;
    final size = info?.size != null && info!.size > 0
        ? info.size
        : (widget.file.existsSync() ? widget.file.lengthSync() : -1);

    return AlertDialog(
      title: Text(
        info?.name.isNotEmpty == true ? info!.name : _fileName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: _loading
          ? const SizedBox(
              height: 72,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dosya: $_fileName'),
                if (size > 0) Text('Boyut: ${Formats.size(size)}'),
                if (info != null) ...[
                  const SizedBox(height: 4),
                  Text('Paket: ${info.packageName}'),
                  Text(
                    'Sürüm: ${info.versionName}'
                    '${info.versionCode >= 0 ? ' (${info.versionCode})' : ''}',
                  ),
                  Text(
                    info.installed
                        ? 'Cihazdaki sürüm: ${info.installedVersionName}'
                            '${info.installedVersionCode >= 0 ? ' (${info.installedVersionCode})' : ''}'
                        : 'Cihazda kurulu değil.',
                  ),
                  if (info.sameVersion)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Bu sürüm zaten kurulu.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                ] else
                  Text(
                    'Paket bilgisi okunamadı; yine de kurulum denenebilir.',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: _installing ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _loading || _installing ? null : _install,
          child: _installing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_actionLabel),
        ),
      ],
    );
  }
}
