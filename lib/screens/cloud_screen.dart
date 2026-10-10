import 'package:flutter/material.dart';

import '../services/webdav_service.dart';

/// Desteklenen bulut sağlayıcıları.
const kCloudProviders = <String, String>{
  'Nextcloud': 'nextcloud',
  'ownCloud': 'webdav',
  'pCloud': 'webdav',
  'Yandex Disk': 'webdav',
  'WebDAV': 'webdav',
  'Dropbox': 'oauth',
  'Google Drive': 'oauth',
  'OneDrive': 'oauth',
  'Box': 'oauth',
};

/// Bulut konumları ekranı: hesap listesi + ekleme + gezinme.
class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  List<CloudLocation> _locations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final locations = await CloudLocationStore.load();
    if (!mounted) return;
    setState(() {
      _locations = locations;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final loc = await showDialog<CloudLocation>(
      context: context,
      builder: (_) => const _AddCloudDialog(),
    );
    if (loc == null) return;
    _locations.add(loc);
    await CloudLocationStore.save(_locations);
    setState(() {});
  }

  Future<void> _delete(CloudLocation loc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hesabı kaldır'),
        content: Text('"${loc.name}" kaldırılsın mı?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaldır')),
        ],
      ),
    );
    if (ok != true) return;
    _locations.remove(loc);
    await CloudLocationStore.save(_locations);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bulut')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Bulut konumu ekle'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _locations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_rounded,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'Henüz hesap eklenmedi.\nWebDAV tabanlı bulut '
                          'hesaplarınızı (Nextcloud, pCloud, Yandex Disk, '
                          'kendi sunucunuz) ekleyebilirsiniz.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Bir bulut konumu ekle'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _locations.length,
                  itemBuilder: (context, index) {
                    final loc = _locations[index];
                    return ListTile(
                      leading: Icon(
                        Icons.cloud_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(loc.name),
                      subtitle: Text('${loc.provider} • ${loc.username}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _delete(loc),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CloudBrowseScreen(location: loc),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Yeni bulut konumu: sağlayıcı seçimi → WebDAV formu.
class _AddCloudDialog extends StatefulWidget {
  const _AddCloudDialog();

  @override
  State<_AddCloudDialog> createState() => _AddCloudDialogState();
}

class _AddCloudDialogState extends State<_AddCloudDialog> {
  String _provider = 'Nextcloud';
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.text = 'Nextcloud';
    _url.text = 'https://sunucu.com/remote.php/dav/files/';
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onProvider(String value) {
    setState(() {
      _provider = value;
      switch (value) {
        case 'Nextcloud':
          _name.text = 'Nextcloud';
          _url.text = 'https://sunucu.com/remote.php/dav/files/';
        case 'ownCloud':
          _name.text = 'ownCloud';
          _url.text = 'https://sunucu.com/remote.php/dav/files/';
        case 'pCloud':
          _name.text = 'pCloud';
          _url.text = 'https://api.pcloud.com/';
        case 'Yandex Disk':
          _name.text = 'Yandex Disk';
          _url.text = 'https://webdav.yandex.ru/';
        default:
          _name.text = value;
          _url.text = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final needsOAuth = kCloudProviders[_provider] == 'oauth';
    return AlertDialog(
      title: const Text('Bir bulut konumu ekle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _provider,
              decoration: const InputDecoration(labelText: 'Sağlayıcı'),
              items: [
                for (final p in kCloudProviders.keys)
                  DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => _onProvider(v ?? _provider),
            ),
            const SizedBox(height: 12),
            if (needsOAuth) ...[
              Text(
                '$_provider için uygulama geliştirici API anahtarı (client ID) '
                'gereklidir. Ücretsiz sürümümüzde WebDAV tabanlı sağlayıcılar '
                '(Nextcloud, ownCloud, pCloud, Yandex Disk, kendi sunucunuz) '
                'doğrudan çalışır.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Bağlantı adı'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                decoration: const InputDecoration(
                  labelText: 'WebDAV adresi (URL)',
                  helperText:
                      'Kullanıcı adınızın URL sonuna eklendiğini unutmayın',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Kullanıcı adı'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Şifre'),
                obscureText: true,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: needsOAuth
              ? null
              : () {
                  final username = _username.text.trim();
                  Navigator.of(context).pop(CloudLocation(
                    name: _name.text.trim().isEmpty
                        ? _provider
                        : _name.text.trim(),
                    provider: _provider,
                    url: _url.text.trim().endsWith(username)
                        ? _url.text.trim()
                        : '${_url.text.trim()}$username',
                    username: username,
                    password: _password.text,
                  ));
                },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

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
      final entries =
          await _service.list(widget.location, path: _path);
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
                        const Icon(Icons.cloud_off_rounded,
                            size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: const Text('Tekrar dene')),
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
                        title: Text(e.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle:
                            Text(e.isDir ? 'Klasör' : '${e.size} bayt'),
                        onTap: () => _open(e),
                      );
                    },
                  ),
                ),
    );
  }
}
