import 'package:flutter/material.dart';

import '../services/remote_download.dart';
import '../services/remote_service.dart';
import '../services/smb_client.dart';
import '../utils/formats.dart';

/// SMB paylaşımında gezinme: dizin listesi + dosya indirme (salt okunur).
class SmbBrowseScreen extends StatefulWidget {
  const SmbBrowseScreen({super.key, required this.location});

  final RemoteLocation location;

  @override
  State<SmbBrowseScreen> createState() => _SmbBrowseScreenState();
}

class _SmbBrowseScreenState extends State<SmbBrowseScreen> {
  SmbClient? _client;
  String _path = '';
  List<SmbEntry> _entries = [];
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
    _client?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _client ??= await SmbClient.connect(widget.location);
      final entries = await _client!.list(_path);
      if (!mounted) return;
      setState(() => _entries = entries);
    } on SmbException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Bağlantı/liste hatası: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(SmbEntry entry) {
    if (entry.isDir) {
      final next = _path.isEmpty ? entry.name : '$_path\\${entry.name}';
      setState(() => _path = next);
      _connect();
    } else {
      _download(entry);
    }
  }

  void _goUp() {
    if (_path.isEmpty) return;
    final idx = _path.lastIndexOf(r'\');
    setState(() => _path = idx < 0 ? '' : _path.substring(0, idx));
    _connect();
  }

  Future<void> _download(SmbEntry entry) async {
    final remote = _path.isEmpty ? entry.name : '$_path\\${entry.name}';
    if (!mounted) return;
    // Download klasörüne iner; APK ise bitince Kur/Güncelle diyaloğu açılır.
    await RemoteDownload.run(
      context,
      fileName: entry.name,
      transfer: (target) => _client!.download(remote, target),
    );
  }

  String get _displayPath => '\\\\${widget.location.host}\\'
      '${widget.location.share.isEmpty ? 'C\$' : widget.location.share}'
      '${_path.isEmpty ? '' : '\\$_path'}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.location.name} (SMB)'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.folder_shared_rounded, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _displayPath,
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
                              if (_path.isEmpty) return const SizedBox.shrink();
                              return ListTile(
                                leading:
                                    const Icon(Icons.drive_folder_upload),
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
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
