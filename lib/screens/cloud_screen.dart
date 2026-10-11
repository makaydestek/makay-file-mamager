import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/google_drive_service.dart';
import '../services/webdav_service.dart';
import 'google_drive_screen.dart';

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
  bool _gdriveConnected = false;
  String? _gdriveEmail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final locations = await CloudLocationStore.load();
    await _refreshGdrive();
    if (!mounted) return;
    setState(() {
      _locations = locations;
      _loading = false;
    });
  }

  /// Google Drive oturum durumu (bağlıysa listede görünür).
  Future<void> _refreshGdrive() async {
    try {
      final has = await GoogleDriveService.hasSession;
      final email = has ? await GoogleDriveService.accountEmail() : null;
      if (!mounted) return;
      setState(() {
        _gdriveConnected = has;
        _gdriveEmail = email;
      });
    } catch (_) {}
  }

  Future<void> _add() async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => const _AddCloudDialog(),
    );
    if (result is CloudLocation) {
      _locations.add(result);
      await CloudLocationStore.save(_locations);
    }
    // Google Drive bağlantısı bu diyalogtan kurulmuş olabilir.
    await _refreshGdrive();
    if (mounted) setState(() {});
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
                          'Henüz hesap eklenmedi.\nGoogle Drive\'a tarayıcı '
                          'girişiyle bağlanabilir veya WebDAV tabanlı bulut '
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
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    _gdriveTile(context),
                    for (final loc in _locations) _locationTile(loc),
                  ],
                ),
    );
  }

  /// Google Drive satırı: bağlıysa gezinmeye, değilse bağlanma akışına açılır.
  Widget _gdriveTile(BuildContext context) {
    return ListTile(
      leading: Icon(
        _gdriveConnected ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
        color: _gdriveConnected ? const Color(0xFF1E88E5) : Colors.grey,
      ),
      title: const Text('Google Drive'),
      subtitle: Text(
        _gdriveConnected
            ? (_gdriveEmail == null || _gdriveEmail!.isEmpty
                ? 'Bağlı'
                : _gdriveEmail!)
            : 'Bağlı değil — tarayıcıyla giriş yapın',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _gdriveConnected
          ? const Icon(Icons.chevron_right_rounded)
          : FilledButton.tonal(
              onPressed: () => _openConnect(),
              child: const Text('Bağlan'),
            ),
      onTap: _gdriveConnected
          ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GoogleDriveScreen()),
              )
          : null,
    );
  }

  Future<void> _openConnect() async {
    await showDialog<Object?>(
      context: context,
      builder: (_) => const _AddCloudDialog(initialProvider: 'Google Drive'),
    );
    await _refreshGdrive();
    if (mounted) setState(() {});
  }

  Widget _locationTile(CloudLocation loc) {
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
  }
}

/// Yeni bulut konumu: sağlayıcı seçimi → WebDAV formu veya OAuth akışı.
class _AddCloudDialog extends StatefulWidget {
  const _AddCloudDialog({this.initialProvider = 'Nextcloud'});

  final String initialProvider;

  @override
  State<_AddCloudDialog> createState() => _AddCloudDialogState();
}

class _AddCloudDialogState extends State<_AddCloudDialog> {
  late String _provider;
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _clientId = TextEditingController();

  bool _clientIdLoaded = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _provider = widget.initialProvider;
    _onProvider(_provider);
    _loadClientId();
  }

  Future<void> _loadClientId() async {
    final saved = await GoogleDriveService.clientId();
    if (!mounted) return;
    _clientId.text = saved ?? '';
    setState(() => _clientIdLoaded = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _clientId.dispose();
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
            if (needsOAuth)
              _oauthPanel(context)
            else ...[
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
          child: Text(needsOAuth ? 'Kapat' : 'Vazgeç'),
        ),
        if (!needsOAuth)
          FilledButton(
            onPressed: () {
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

  // -------------------------------------------------------------------------
  // OAuth (Google Drive) paneli
  // -------------------------------------------------------------------------

  /// Sağlayıcı OAuth ise: ücretsiz client ID rehberi + bağlanma düğmesi.
  Widget _oauthPanel(BuildContext context) {
    final theme = Theme.of(context);
    if (_provider != 'Google Drive') {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '$_provider bağlantısı sonraki sürümde açılacak. Şu anda OAuth ile '
          'çalışan sağlayıcı Google Drive’dır; WebDAV tabanlı hesaplar '
          '(Nextcloud, ownCloud, pCloud, Yandex Disk, kendi sunucunuz) ise '
          'doğrudan çalışır.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    if (!_clientIdLoaded) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final hasId = _clientId.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasId) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ücretsiz client ID alın (yaklaşık 2 dakika)',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Aşağıdaki düğmeyle Google Cloud Konsolu’nu açın.\n'
                  '2. Yeni proje oluşturun (örn. “Makay”).\n'
                  '3. APIs & Services → OAuth consent screen → External → '
                  'Test users alanına kendi Gmail adresinizi ekleyin.\n'
                  '4. APIs & Services → Credentials → Create credentials → '
                  'OAuth client ID → Uygulama türü: “Desktop app” → Create.\n'
                  '5. Verilen client ID’yi aşağıya yapıştırın ve “Bağlan”.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openConsole,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Google Cloud Konsolu’nu aç'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _clientId,
          decoration: const InputDecoration(
            labelText: 'Google Drive client ID',
            hintText: 'xxxx.apps.googleusercontent.com',
            helperText: 'Ücretsizdir; yalnızca sizin Google hesabınızla çalışır',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _connecting ? null : _connect,
            icon: _connecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(_connecting
                ? 'Tarayıcıda giriş yapın…'
                : 'Google Drive’a bağlan'),
          ),
        ),
        if (hasId && !_connecting)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                await GoogleDriveService.setClientId('');
                if (context.mounted) {
                  setState(() => _clientId.clear());
                }
              },
              child: const Text('Kayıtlı ID’yi kaldır'),
            ),
          ),
      ],
    );
  }

  Future<void> _openConsole() async {
    final uri =
        Uri.parse('https://console.cloud.google.com/apis/credentials');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konsol açılamadı: $e')),
        );
      }
    }
  }

  Future<void> _connect() async {
    final id = _clientId.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce ücretsiz client ID alıp yapıştırın (yukarıdaki adımlar)'),
        ),
      );
      return;
    }
    setState(() => _connecting = true);
    try {
      await GoogleDriveService.connect(clientID: id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _connecting = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Bağlanılamadı: $e')));
      }
    }
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
