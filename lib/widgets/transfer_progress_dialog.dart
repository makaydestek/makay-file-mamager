import 'package:flutter/material.dart';

import '../services/transfer.dart';
import '../utils/formats.dart';

/// Kopyalama / taşıma için iptal edilebilir ilerleme diyaloğu.
///
/// Kullanım:
/// ```dart
/// final result = await showTransferProgress(
///   context,
///   title: 'Kopyalanıyor',
///   action: (onProgress, token) => service.copyPath(
///     src, dst, onProgress: onProgress, cancelToken: token,
///   ),
/// );
/// ```
///
/// Kullanıcı iptal ederse [TransferCancelled] fırlatılır — çağıran tarafın
/// hata mesajı göstermesi beklenir (iptal bir hata değildir).
class TransferProgressDialog extends StatefulWidget {
  const TransferProgressDialog({
    super.key,
    required this.title,
    required this.action,
  });

  final String title;

  /// İşlemi başlatan geri çağırma; diyaloğun ilk kurulumunda çalıştırılır.
  final Future<TransferResult> Function(
    void Function(TransferProgress) onProgress,
    CancelToken cancelToken,
  ) action;

  @override
  State<TransferProgressDialog> createState() => _TransferProgressDialogState();
}

/// İlerleme diyaloğunu açar ve sonucu döner.
///
/// - İşlem bittiyse [TransferResult] döner.
/// - Kullanıcı iptal ettiyse (veya diyalog kapatıldıysa) [TransferCancelled]
///   fırlatılır — iptal bir hata değildir, çağıran sessizce devam edebilir.
/// - İşlem hata ile bittiyse hata **yeniden fırlatılır**.
Future<TransferResult> showTransferProgress(
  BuildContext context, {
  required String title,
  required Future<TransferResult> Function(
    void Function(TransferProgress) onProgress,
    CancelToken cancelToken,
  ) action,
}) async {
  final outcome = await showDialog<Object>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TransferProgressDialog(title: title, action: action),
  );
  if (outcome is TransferResult) return outcome;
  if (outcome == null) throw const TransferCancelled();
  // ignore: only_throw_errors -- kasıtlı olarak orijinal hata yeniden fırlatılır.
  throw outcome;
}

class _TransferProgressDialogState extends State<TransferProgressDialog> {
  final CancelToken _token = CancelToken();
  TransferProgress? _progress;
  Object? _error;
  bool _running = true;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    // İşlem ilk kareden hemen sonra başlar: initState içinde senkron olarak
    // başlatılırsa ilk `onProgress` çağrısı build sırasında `setState` çağırır.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  Future<void> _start() async {
    try {
      final result = await widget.action(_onProgress, _token);
      if (!mounted) return;
      setState(() => _running = false);
      Navigator.of(context).pop(result);
    } on TransferCancelled {
      if (!mounted) return;
      setState(() => _running = false);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e;
      });
    }
  }

  void _onProgress(TransferProgress progress) {
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  void _cancel() {
    _token.cancel();
    setState(() => _cancelRequested = true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _progress;
    final measuring =
        progress == null || progress.phase == TransferPhase.measuring;
    final fraction = progress?.fraction;

    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Icon(Icons.error_outline, color: scheme.error, size: 28),
                const SizedBox(height: 12),
                Text(
                  'İşlem tamamlanamadı.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  _error.toString(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ] else if (measuring) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
                Text(
                  progress?.measuringText ?? 'Ölçülüyor…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ] else ...[
                LinearProgressIndicator(value: fraction),
                const SizedBox(height: 14),
                Text(
                  progress.fileText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${Formats.size(progress.doneBytes)} / '
                  '${Formats.size(progress.totalBytes ?? 0)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                if (progress.currentPath.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    progress.currentPath.split(RegExp(r'[/\\]')).last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          if (_error != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(_error),
              child: const Text('Kapat'),
            )
          else if (_running)
            TextButton(
              onPressed: _cancelRequested ? null : _cancel,
              child: Text(_cancelRequested ? 'İptal ediliyor…' : 'İptal'),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tamam'),
            ),
        ],
      ),
    );
  }
}
