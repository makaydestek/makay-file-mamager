import 'package:flutter/material.dart';

import '../services/webdav_service.dart';

/// WebDAV bulut konumunda gezinme.
class CloudBrowseScreen extends StatefulWidget {
  const CloudBrowseScreen({super.key, required this.location});

  final CloudLocation location;

  @override
  State<CloudBrowseScreen> createState() => _CloudBrowseScreenState();
}

class _CloudBrowseScreenState extends State<CloudBrowseScreen> {
  static const _service = WebDavService();

  String _path = '/';
  List<DavEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _service.list(widget.location, path: _path);
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Liste alınamadı: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(DavEntry entry) {
    if (entry.isDir) {
      final next = _path.endsWith('/')
          ? '$_path${entry.name}'
          : '$_path/${entry.name}';
      setState(() => _path = next);
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$entry.name (${entry.size} bayt)')),
      );
    }
  }

  void _goUp() {
    if (_path == '/') return;
    final cleaned = _path.replaceAll(RegExp(r'/+$'), '');
    final idx = cleaned.lastIndexOf('/');
    setState(() => _path = idx <= 0 ? '/' : cleaned.substring(0, idx));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.location.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 48,
                      color: Colors.redAccent,
                    ),
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
                    title: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(e.isDir ? 'Klasör' : '${e.size} bayt'),
                    onTap: () => _open(e),
                  );
                },
              ),
            ),
    );
  }
}
