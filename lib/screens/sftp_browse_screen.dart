import 'package:flutter/material.dart';

import '../services/remote_download.dart';
import '../services/remote_service.dart';
import '../services/sftp_service.dart';
import '../utils/formats.dart';

/// Uzak SSH sunucusunda SFTP gezinme: dizin listesi + dosya indirme.
class SftpBrowseScreen extends StatefulWidget {
  const SftpBrowseScreen({super.key, required this.location});

  final RemoteLocation location;

  @override
  State<SftpBrowseScreen> createState() => _SftpBrowseScreenState();
}

class _SftpBrowseScreenState extends State<SftpBrowseScreen> {
  SftpSession? _session;
  String _path = '/';
  List<SftpEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = widget.location.startPath;
    _connect();
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _session ??= await SftpSession.connect(widget.location);
      final entries = await _session!.list(_path);
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Bağlantı/liste hatası: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(SftpEntry entry) {
    if (entry.isDir) {
      final next = _path.endsWith('/')
          ? '$_path${entry.name}'
          : '$_path/${entry.name}';
      setState(() => _path = next);
      _connect();
    } else {
      _download(entry);
    }
  }

  void _goUp() {
    if (_path == '/') return;
    final cleaned = _path.replaceAll(RegExp(r'/+$'), '');
    final idx = cleaned.lastIndexOf('/');
    setState(() => _path = idx <= 0 ? '/' : cleaned.substring(0, idx));
    _connect();
  }

  Future<void> _download(SftpEntry entry) async {
    final remote = _path.endsWith('/')
        ? '$_path${entry.name}'
        : '$_path/${entry.name}';
    if (!mounted) return;
    // Download klasörüne iner; APK ise bitince Kur/Güncelle diyaloğu açılır.
    await RemoteDownload.run(
      context,
      fileName: entry.name,
      transfer: (target) => _session!.download(remote, target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.location.name} (SFTP)'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _connect,
                          child: const Text('Tekrar dene'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _connect,
                  child: ListView.builder(
                    itemCount: _entries.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        if (_path == '/') return const SizedBox.shrink();
                        return ListTile(
                          leading: const Icon(Icons.drive_folder_upload),
                          title: const Text('..'),
                          onTap: _goUp,
                        );
                      }
                      final e = _entries[index - 1];
                      return ListTile(
                        leading: Icon(
                          e.isDir
                              ? Icons.folder_rounded
                              : Icons.insert_drive_file_rounded,
                          color: e.isDir
                              ? const Color(0xFFFFB300)
                              : theme.colorScheme.primary,
                        ),
                        title: Text(e.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle:
                            Text(e.isDir ? 'Klasör' : Formats.size(e.size)),
                        trailing: e.modified != null
                            ? Text(Formats.date(e.modified!),
                                style: theme.textTheme.bodySmall)
                            : null,
                        onTap: () => _open(e),
                      );
                    },
                  ),
                ),
    );
  }
}
