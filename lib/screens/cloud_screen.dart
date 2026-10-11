import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/box_service.dart';
import '../services/dropbox_service.dart';
import '../services/google_drive_service.dart';
import '../services/onedrive_service.dart';
import '../services/webdav_service.dart';
import '../utils/formats.dart';
import 'box_screen.dart';
import 'dropbox_screen.dart';
import 'google_drive_screen.dart';
import 'onedrive_screen.dart';

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

/// Google Drive dışındaki OAuth sağlayıcıları (tile/panel sırası).
const kOAuthProviderNames = <String>['Dropbox', 'OneDrive', 'Box'];

/// Sağlayıcı adını gezinme ekranına çevirir.
Widget? oauthScreenFor(String provider) => switch (provider) {
      'Google Drive' => const GoogleDriveScreen(),
      'Dropbox' => const DropboxScreen(),
      'OneDrive' => const OneDriveScreen(),
      'Box' => const BoxScreen(),
      _ => null,
    };

/// OAuth sağlayıcısının servis uçları (panel ve durum yenileme için).
typedef _OauthApi = ({
  Future<bool> Function() hasTokens,
  Future<String?> Function() loadClientSecret,
  Future<void> Function(String) connect,
  Future<void> Function() disconnect,
});

_OauthApi? _oauthApiFor(String provider) => switch (provider) {
      'Dropbox' => (
          hasTokens: DropboxService.hasTokens,
          loadClientSecret: DropboxService.loadClientSecret,
          connect: DropboxService.connect,
          disconnect: DropboxService.disconnect,
        ),
      'OneDrive' => (
          hasTokens: OneDriveService.hasTokens,
          loadClientSecret: OneDriveService.loadClientSecret,
          connect: OneDriveService.connect,
          disconnect: OneDriveService.disconnect,
        ),
      'Box' => (
          hasTokens: BoxService.hasTokens,
          loadClientSecret: BoxService.loadClientSecret,
          connect: BoxService.connect,
          disconnect: BoxService.disconnect,
        ),
      _ => null,
    };

/// Bağlantı hatalarının kullanıcıya okunabilir metne çevrilmesi.
String _friendlyError(Object e) {
  if (e is SocketException) {
    final where = [e.address?.address, e.port?.toString()]
        .where((s) => s != null && s.isNotEmpty)
        .join(':');
    return where.isEmpty
        ? 'İnternet sunucusuna ulaşılamadı'
        : 'İnternet sunucusuna ulaşılamadı ($where)';
  }
  if (e is TimeoutException) return 'Bağlantı zaman aşımına uğradı';
  if (e is HttpException) return e.message;
  final text = '$e';
  return text.length > 160 ? '${text.substring(0, 160)}…' : text;
}

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
  final _oauthConnected = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final locations = await CloudLocationStore.load();
    await _refreshGdrive();
    await _refreshOauth();
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

  /// Dropbox / OneDrive / Box oturum durumları (bağlıysa listede görünür).
  Future<void> _refreshOauth() async {
    final connected = <String, bool>{};
    for (final name in kOAuthProviderNames) {
      try {
        connected[name] = await _oauthApiFor(name)?.hasTokens() ?? false;
      } catch (_) {
        connected[name] = false;
      }
    }
    if (!mounted) return;
    setState(() => _oauthConnected
      ..clear()
      ..addAll(connected));
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
    await _afterDialog(result);
  }

  /// Diyalog kapandıktan sonra durumları tazeler; OAuth sağlayıcısı
  /// bağlanmışsa gezinme ekranını açar (Google Drive davranışı değişmez).
  Future<void> _afterDialog(Object? result) async {
    if (result is String) {
      final screen = oauthScreenFor(result);
      if (screen != null && mounted) {
        await Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));
      }
    }
    await _refreshGdrive();
    await _refreshOauth();
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
          : _showEmpty
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
                          'Henüz hesap eklenmedi.\nGoogle Drive, Dropbox, '
                          'OneDrive ve Box\'a tarayıcı girişiyle '
                          'bağlanabilir veya WebDAV tabanlı bulut '
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
                    for (final name in kOAuthProviderNames)
                      _oauthTile(context, name),
                    for (final loc in _locations) _locationTile(loc),
                  ],
                ),
    );
  }

  /// Hiçbir hesap eklenmemiş ve hiçbir OAuth sağlayıcısı bağlı değilse
  /// boş durum gösterilir.
  bool get _showEmpty =>
      _locations.isEmpty &&
      !_gdriveConnected &&
      !_oauthConnected.containsValue(true);

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

  /// Dropbox / OneDrive / Box satırı: bağlıysa gezinmeye, değilse
  /// bağlanma akışına (ücretsiz client ID rehberi) açılır.
  Widget _oauthTile(BuildContext context, String name) {
    final connected = _oauthConnected[name] ?? false;
    return ListTile(
      leading: Icon(
        connected ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
        color: connected ? Theme.of(context).colorScheme.primary : Colors.grey,
      ),
      title: Text(name),
      subtitle: Text(
        connected
            ? 'Bağlı ✓ — dokunup gezinin'
            : 'Bağlı değil — ücretsiz client ID ile bağlanın',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: connected
          ? const Icon(Icons.chevron_right_rounded)
          : FilledButton.tonal(
              onPressed: () => _openConnect(name),
              child: const Text('Bağlan'),
            ),
      onTap: connected
          ? () {
              final screen = oauthScreenFor(name);
              if (screen != null) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => screen),
                );
              }
            }
          : null,
    );
  }

  Future<void> _openConnect([String provider = 'Google Drive']) async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => _AddCloudDialog(initialProvider: provider),
    );
    await _afterDialog(result);
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

  /// Seçili OAuth sağlayıcısı şu anda bağlı mı (Dropbox/OneDrive/Box).
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _provider = widget.initialProvider;
    _onProvider(_provider);
  }

  /// Seçili sağlayıcının kayıtlı client ID'sini ve oturum durumunu yükler.
  Future<void> _loadProviderState() async {
    final provider = _provider;
    var saved = '';
    var connected = false;
    try {
      if (provider == 'Google Drive') {
        saved = await GoogleDriveService.clientId() ?? '';
      } else {
        final api = _oauthApiFor(provider);
        if (api != null) {
          saved = await api.loadClientSecret() ?? '';
          connected = await api.hasTokens();
        }
      }
    } catch (_) {}
    if (!mounted || provider != _provider) return;
    _clientId.text = saved;
    setState(() {
      _clientIdLoaded = true;
      _connected = connected;
    });
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
      _clientIdLoaded = false;
      _connected = false;
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
    _loadProviderState();
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
  // OAuth panelleri (Google Drive + Dropbox / OneDrive / Box)
  // -------------------------------------------------------------------------

  /// Sağlayıcı OAuth ise: ücretsiz client ID rehberi + bağlanma düğmesi.
  ///
  /// Google Drive kendi panelini (özgün kurulum adımlarıyla) kullanır;
  /// diğer OAuth sağlayıcıları ortak [_genericOauthPanel]ı gösterir.
  Widget _oauthPanel(BuildContext context) {
    if (_provider == 'Google Drive') {
      return _googleOauthPanel(context);
    }
    return _genericOauthPanel(context);
  }

  /// Google Drive paneli: ücretsiz client ID rehberi + bağlanma düğmesi.
  Widget _googleOauthPanel(BuildContext context) {
    final theme = Theme.of(context);
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

  // -------------------------------------------------------------------------
  // OAuth paneli — Dropbox / OneDrive / Box
  // -------------------------------------------------------------------------

  /// Dropbox, OneDrive ve Box için ortak panel.
  ///
  /// Bağlı değilken: ücretsiz developer hesabı rehberi + client ID alanı +
  /// "Bağlan" düğmesi. Bağlıyken: "Bağlı ✓" durumu, gezinme ve
  /// "Bağlantıyı kes" seçenekleri.
  Widget _genericOauthPanel(BuildContext context) {
    final theme = Theme.of(context);
    final guide = _oauthGuides[_provider];
    if (guide == null) {
      return Text('$_provider için rehber bulunamadı.',
          style: theme.textTheme.bodySmall);
    }
    if (!_clientIdLoaded) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_connected) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_done_rounded,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$_provider hesabı bağlı ✓',
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_provider),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Gezin'),
          ),
          TextButton(
            onPressed: _connecting ? null : _disconnectGeneric,
            child: const Text('Bağlantıyı kes'),
          ),
        ],
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
                  guide.steps,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openConsoleUrl(guide.consoleUrl),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(guide.consoleLabel),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _clientId,
          decoration: InputDecoration(
            labelText: '$_provider client ID',
            helperText: 'Ücretsizdir; yalnızca sizin hesabınızla çalışır',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _connecting ? null : _connectGeneric,
            icon: _connecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(
                _connecting ? 'Tarayıcıda giriş yapın…' : '$_provider’a bağlan'),
          ),
        ),
      ],
    );
  }

  Future<void> _connectGeneric() async {
    final api = _oauthApiFor(_provider);
    if (api == null) return;
    final id = _clientId.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Önce ücretsiz client ID alıp yapıştırın (yukarıdaki adımlar)'),
        ),
      );
      return;
    }
    setState(() => _connecting = true);
    try {
      await api.connect(id);
      // Bağlandı; gezinme ekranını üst katman açar.
      if (mounted) Navigator.of(context).pop(_provider);
    } catch (e) {
      if (mounted) {
        setState(() => _connecting = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
              SnackBar(content: Text('Bağlanılamadı: ${_friendlyError(e)}')));
      }
    }
  }

  Future<void> _disconnectGeneric() async {
    final api = _oauthApiFor(_provider);
    if (api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bağlantıyı kes'),
        content: Text('$_provider hesabı bu cihazdan kaldırılsın mı?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kes')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _connecting = true);
    try {
      await api.disconnect();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _connecting = false;
        _connected = false;
      });
    }
  }

  Future<void> _openConsoleUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sayfa açılamadı: $e')),
        );
      }
    }
  }
}

/// OAuth sağlayıcısı için ücretsiz kurulum rehberi.
class _OauthGuide {
  const _OauthGuide(this.consoleUrl, this.consoleLabel, this.steps);

  /// Developer konsolunun adresi ve düğme etiketi.
  final String consoleUrl;
  final String consoleLabel;

  /// Ücretsiz client ID alınış adımları.
  final String steps;
}

/// Dropbox / OneDrive / Box için geliştirici konsolu ve kurulum adımları.
const _oauthGuides = <String, _OauthGuide>{
  'Dropbox': _OauthGuide(
    'https://www.dropbox.com/developers/apps',
    'Dropbox App Console’u aç',
    '1. Aşağıdaki düğmeyle Dropbox App Console’u açıp ücretsiz hesabınızla '
        'giriş yapın.\n'
        '2. “Create app” → “Scoped access” → erişim türü: “Full Dropbox” → '
        'uygulama adı verip oluşturun.\n'
        '3. “Permissions” sekmesinde files.content.read ve '
        'files.content.write izinlerini işaretleyip “Submit” deyin.\n'
        '4. “Settings” sekmesindeki “OAuth2 client identifier” değerini '
        'kopyalayıp aşağıya yapıştırın ve “Bağlan” deyin.\n'
        '5. Tarayıcıda Dropbox hesabınızla giriş yapıp erişimi onaylayın.',
  ),
  'OneDrive': _OauthGuide(
    'https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade',
    'Microsoft Azure Portal’ı aç',
    '1. Aşağıdaki düğmeyle Azure Portal’ı açıp ücretsiz Microsoft hesabınızla '
        'giriş yapın.\n'
        '2. “App registrations” → “New registration” seçin.\n'
        '3. Uygulama adı verin; Supported account types: “Personal Microsoft '
        'accounts only”; Redirect URI türü: “Mobile and desktop '
        'applications” → “http://localhost” yazın (uygulama döngü '
        'arayüzünden döner; Microsoft portu yok sayar).\n'
        '4. Oluşturulan “Application (client ID)” değerini kopyalayıp '
        'aşağıya yapıştırın ve “Bağlan” deyin.\n'
        '5. Tarayıcıda Microsoft hesabınızla giriş yapıp erişimi onaylayın.',
  ),
  'Box': _OauthGuide(
    'https://app.box.com/developers/console',
    'Box Developer Console’u aç',
    '1. Aşağıdaki düğmeyle Box Developer Console’u açıp ücretsiz developer '
        'hesabıyla giriş yapın.\n'
        '2. “Create New App” → “Custom App” → Authentication Type: “Standard” '
        'seçin.\n'
        '3. “Configuration” sekmesinde “OAuth 2.0 Redirect URI” alanına '
        '“http://127.0.0.1/callback” yazın (Box döngü arayüzünde portu yok '
        'sayar) ve kaydedin.\n'
        '4. “Client ID” değerini kopyalayıp aşağıya yapıştırın ve “Bağlan” '
        'deyin.\n'
        '5. Tarayıcıda Box hesabınızla giriş yapıp erişimi onaylayın.',
  ),
};

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

// ---------------------------------------------------------------------------
// OAuth tabanlı bulut sağlayıcıları için ortak gezinme ekranı
// ---------------------------------------------------------------------------

/// Klasör listeleme ([folderId] verilmezse kök).
typedef CloudListFn = Future<List<CloudItem>> Function({String? folderId});

/// Dosya indirme; [onProgress] 0..1 arası ilerleme oranını bildirir.
typedef CloudDownloadFn = Future<void> Function(
    String id, String name, String destPath, void Function(double) onProgress);

/// Klasör oluşturma.
typedef CloudCreateFolderFn =
    Future<void> Function(String parentFolderId, String name);

/// Öğe silme ([isFolder] yalnızca silme uçları farklı olan sağlayıcılarda
/// kullanılır, ör. Box).
typedef CloudRemoveFn = Future<void> Function(String id, {bool isFolder});

/// Kullanılan / toplam depolama bilgisi (verilmezse bar gizlenir).
typedef CloudAboutFn = Future<({int used, int total})?> Function();

/// Dropbox, OneDrive ve Box gezinme ekranının ortak gövdesi.
///
/// [CloudBrowseScreen] (WebDAV) desenini izler: ListView ile klasör gezinme,
/// yolda başlık, dosyada ilerme çubuklu indirme, uygulama çubuğunda
/// yenileme / yeni klasör / depolama bilgisi / bağlantı kesme.
class CloudOAuthBrowseScreen extends StatefulWidget {
  const CloudOAuthBrowseScreen({
    super.key,
    required this.title,
    required this.rootFolderId,
    required this.list,
    required this.download,
    required this.createFolder,
    required this.remove,
    this.about,
    this.onDisconnect,
  });

  /// Başlık ve kök klasör adı (ör. 'Dropbox').
  final String title;

  /// Sağlayıcının kök klasör kimliği (Dropbox: '', OneDrive: 'root', Box: '0').
  final String rootFolderId;

  final CloudListFn list;
  final CloudDownloadFn download;
  final CloudCreateFolderFn createFolder;
  final CloudRemoveFn remove;
  final CloudAboutFn? about;
  final Future<void> Function()? onDisconnect;

  @override
  State<CloudOAuthBrowseScreen> createState() => _CloudOAuthBrowseScreenState();
}

/// Ekran yığınındaki klasör.
class _OAuthFolderRef {
  const _OAuthFolderRef(this.id, this.name);

  final String id;
  final String name;
}

/// Uygulama çubuğu menü seçenekleri.
enum _BrowseMenu { newFolder, storage, disconnect }

class _CloudOAuthBrowseScreenState extends State<CloudOAuthBrowseScreen> {
  final _stack = <_OAuthFolderRef>[];
  List<CloudItem> _items = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  ({int used, int total})? _usage;
  bool _progressOpen = false;

  String get _folderId => _stack.last.id;
  String get _path => _stack.map((f) => f.name).join(' / ');

  @override
  void initState() {
    super.initState();
    _stack.add(_OAuthFolderRef(widget.rootFolderId, widget.title));
    _load();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final about = widget.about;
    if (about == null) return;
    try {
      final usage = await about();
      if (!mounted || usage == null) return;
      setState(() => _usage = usage);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.list(folderId: _folderId);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------------------------------------------------------
  // Klasör gezinme
  // -------------------------------------------------------------------------

  void _open(CloudItem item) {
    if (item.isFolder) {
      setState(() => _stack.add(_OAuthFolderRef(item.id, item.name)));
      _load();
      return;
    }
    _download(item);
  }

  void _goUp() {
    if (_stack.length <= 1) return;
    setState(() => _stack.removeLast());
    _load();
  }

  // -------------------------------------------------------------------------
  // Dosya işlemleri
  // -------------------------------------------------------------------------

  /// Dosyayı indirir; hedef Android'de Download klasörü, diğer
  /// platformlarda geçici dizindir. Başarılı olursa "X indirildi" bildirimi.
  Future<void> _download(CloudItem item) async {
    final dir = _downloadDir();
    final target =
        File('${dir.path}${Platform.pathSeparator}${_unique(dir, item.name)}');

    final progress = ValueNotifier<double?>(null);
    if (mounted && !_progressOpen) {
      _progressOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              ValueListenableBuilder<double?>(
                valueListenable: progress,
                builder: (context, value, _) =>
                    LinearProgressIndicator(value: value),
              ),
              const SizedBox(height: 8),
              Text('İndiriliyor…', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    try {
      await widget.download(item.id, item.name, target.path,
          (value) => progress.value = value.clamp(0.0, 1.0));
      _closeProgress();
      _toast('${item.name} indirildi');
    } catch (e) {
      _closeProgress();
      _toast('İndirilemedi: ${_friendlyError(e)}');
    }
    // Notifier diyaloğun çıkış animasyonu sırasında kullanılabileceği için
    // bilinçli olarak dispose edilmez (kısa ömürlü nesnedir).
  }

  Future<void> _delete(CloudItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sil'),
        content: Text('"${item.name}" kalıcı olarak silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.remove(item.id, isFolder: item.isFolder);
      _toast('"${item.name}" silindi');
      await _load();
    } catch (e) {
      _toast('Silinemedi: ${_friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni klasör'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Klasör adı'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Oluştur')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.createFolder(_folderId, name);
      _toast('"$name" klasörü oluşturuldu');
      await _load();
    } catch (e) {
      _toast('Oluşturulamadı: ${_friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _info(CloudItem item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tür: ${item.isFolder ? 'Klasör' : 'Dosya'}'),
            Text('Boyut: ${item.size == null ? '—' : Formats.size(item.size!)}'),
            if (item.modified != null)
              Text('Değiştirilme: ${Formats.date(item.modified!)}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    final onDisconnect = widget.onDisconnect;
    if (onDisconnect == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bağlantıyı kes'),
        content: Text('${widget.title} hesabı bu cihazdan kaldırılsın mı?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kes')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await onDisconnect();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  /// Android'de Download klasörü (yoksa oluşturulur); diğer platformlarda
  /// ve erişilemiyorsa sistem geçici dizini.
  static Directory _downloadDir() {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        if (dir.existsSync()) return dir;
      } catch (_) {}
    }
    return Directory.systemTemp;
  }

  /// Ad çakışmasını " (2)", " (3)" ekleyerek çözer.
  static String _unique(Directory dir, String name) {
    if (!File('${dir.path}${Platform.pathSeparator}$name').existsSync()) {
      return name;
    }
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 2; i < 1000; i++) {
      final candidate = '$base ($i)$ext';
      if (!File('${dir.path}${Platform.pathSeparator}$candidate')
          .existsSync()) {
        return candidate;
      }
    }
    return name;
  }

  void _closeProgress() {
    if (_progressOpen && mounted) {
      _progressOpen = false;
      Navigator.of(context).pop();
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [..._items]
      ..sort((a, b) {
        if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(_path, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
          PopupMenuButton<_BrowseMenu>(
            onSelected: (action) => switch (action) {
              _BrowseMenu.newFolder => _createFolder(),
              _BrowseMenu.storage => _showStorage(),
              _BrowseMenu.disconnect => _disconnect(),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _BrowseMenu.newFolder,
                child: ListTile(
                  leading: Icon(Icons.create_new_folder_rounded),
                  title: Text('Yeni klasör'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (widget.about != null)
                const PopupMenuItem(
                  value: _BrowseMenu.storage,
                  child: ListTile(
                    leading: Icon(Icons.donut_small_rounded),
                    title: Text('Depolama bilgisi'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (widget.onDisconnect != null)
                const PopupMenuItem(
                  value: _BrowseMenu.disconnect,
                  child: ListTile(
                    leading: Icon(Icons.link_off_rounded),
                    title: Text('Bağlantıyı kes'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_usage != null) _usageBar(theme),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _errorView()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: items.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              if (_stack.length <= 1) {
                                return const SizedBox.shrink();
                              }
                              return ListTile(
                                leading: const Icon(Icons.drive_folder_upload),
                                title: const Text('..'),
                                onTap: _goUp,
                              );
                            }
                            final item = items[index - 1];
                            return ListTile(
                              leading: Icon(
                                item.isFolder
                                    ? Icons.folder_rounded
                                    : Icons.insert_drive_file_rounded,
                                color: item.isFolder
                                    ? const Color(0xFFFFB300)
                                    : theme.colorScheme.primary,
                              ),
                              title: Text(item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                item.isFolder
                                    ? 'Klasör'
                                    : (item.size == null
                                        ? 'Dosya'
                                        : Formats.size(item.size!)),
                                maxLines: 1,
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Seçenekler',
                                icon: const Icon(Icons.more_vert_rounded),
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'info',
                                    child: Text('Bilgi'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Sil'),
                                  ),
                                ],
                                onSelected: (value) {
                                  if (value == 'info') {
                                    _info(item);
                                  } else {
                                    _delete(item);
                                  }
                                },
                              ),
                              onTap: _busy ? null : () => _open(item),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showStorage() {
    final usage = _usage;
    if (usage == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${widget.title} depolama'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kullanılan: ${Formats.size(usage.used)}'),
            Text(usage.total > 0
                ? 'Toplam: ${Formats.size(usage.total)}'
                : 'Toplam: sınırsız görünüyor'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Widget _usageBar(ThemeData theme) {
    final usage = _usage!;
    final suffix = usage.total > 0
        ? ' • ${Formats.size(usage.used)} / ${Formats.size(usage.total)}'
        : ' • ${Formats.size(usage.used)} kullanımda';
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.cloud_rounded),
        title: Text('${widget.title}$suffix',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: widget.onDisconnect == null
            ? null
            : IconButton(
                tooltip: 'Bağlantıyı kes',
                icon: const Icon(Icons.link_off_rounded),
                onPressed: _disconnect,
              ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
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
            FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}
