import 'package:flutter/material.dart';
import 'package:ftpconnect/ftpconnect.dart';

import '../services/remote_download.dart';
import '../services/remote_service.dart';
import '../utils/formats.dart';

/// Uzak FTP sunucusunda gezinme: dizin listesi + dosya indirme.
class FtpBrowseScreen extends StatefulWidget {
  const FtpBrowseScreen({super.key, required this.location});

  final RemoteLocation location;

  @override
  State<FtpBrowseScreen> createState() => _FtpBrowseScreenState();
}

class _FtpBrowseScreenState extends State<FtpBrowseScreen> {
  static const _client = FtpClientService();

  String _path = '/';
  List<FTPEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = widget.location.startPath;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _client.list(widget.location, _path);
      entries.sort((a, b) {
        final aDir = a.type == FTPEntryType.dir;
        final bDir = b.type == FTPEntryType.dir;
        if (aDir != bDir) return aDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Liste alınamadı: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(FTPEntry entry) {
    if (entry.type == FTPEntryType.dir) {
      final next = _path.endsWith('/')
          ? '$_path${entry.name}'
          : '$_path/${entry.name}';
      setState(() => _path = next);
      _load();
    } else {
      _download(entry);
    }
  }

  void _goUp() {
    if (_path == '/' || _path.isEmpty) return;
    final cleaned = _path.replaceAll(RegExp(r'/+$'), '');
    final idx = cleaned.lastIndexOf('/');
    setState(() => _path = idx <= 0 ? '/' : cleaned.substring(0, idx));
    _load();
  }

  Future<void> _download(FTPEntry entry) async {
    final remote = _path.endsWith('/')
        ? '$_path${entry.name}'
        : '$_path/${entry.name}';
    // Download klasörüne iner; APK ise bitince Kur/Güncelle diyaloğu açılır.
    await RemoteDownload.run(
      context,
      fileName: entry.name,
      transfer: (target) => _client.download(widget.location, remote, target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = _path.split('/').where((s) => s.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.location.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.dns_rounded, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _crumb(theme, '/', '/', isRoot: true),
                        for (var i = 0; i < segments.length; i++)
                          _crumb(
                            theme,
                            segments[i],
                            '/${segments.sublist(0, i + 1).join('/')}',
                          ),
                      ],
                    ),
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
                          onPressed: _load,
                          child: const Text('Tekrar dene'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _entries.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('Bu dizin boş')),
                          ],
                        )
                      : ListView.builder(
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
                            final isDir = e.type == FTPEntryType.dir;
                            return ListTile(
                              leading: Icon(
                                isDir
                                    ? Icons.folder_rounded
                                    : Icons.insert_drive_file_rounded,
                                color: isDir
                                    ? const Color(0xFFFFB300)
                                    : theme.colorScheme.primary,
                              ),
                              title: Text(e.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(isDir
                                  ? 'Klasör'
                                  : Formats.size(e.size ?? 0)),
                              trailing: e.modifyTime != null
                                  ? Text(
                                      Formats.date(e.modifyTime!),
                                      style: theme.textTheme.bodySmall,
                                    )
                                  : null,
                              onTap: () => _open(e),
                            );
                          },
                        ),
                ),
    );
  }

  Widget _crumb(ThemeData theme, String label, String path,
      {bool isRoot = false}) {
    final active = path == _path;
    return InkWell(
      onTap: () {
        setState(() => _path = path);
        _load();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          isRoot ? '/' : label,
          style: TextStyle(
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
