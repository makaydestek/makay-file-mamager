import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/google_drive_service.dart';
import '../services/webdav_service.dart';
import 'cloud_common.dart';
import 'cloud_utils.dart';

/// Yeni bulut konumu: sağlayıcı seçimi → WebDAV formu veya OAuth akışı.
class AddCloudDialog extends StatefulWidget {
  const AddCloudDialog({super.key, this.initialProvider = 'Nextcloud'});

  final String initialProvider;

  @override
  State<AddCloudDialog> createState() => _AddCloudDialogState();
}

class _AddCloudDialogState extends State<AddCloudDialog> {
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
        final api = oauthApiFor(provider);
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
              Navigator.of(context).pop(_webdavLocation(username));
            },
            child: const Text('Kaydet'),
          ),
      ],
    );
  }

  /// WebDAV formundan konum üretir (URL sonuna kullanıcı adı eklenir).
  CloudLocation _webdavLocation(String username) => CloudLocation(
    name: _name.text.trim().isEmpty ? _provider : _name.text.trim(),
    provider: _provider,
    url: _url.text.trim().endsWith(username)
        ? _url.text.trim()
        : '${_url.text.trim()}$username',
    username: username,
    password: _password.text,
  );

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
            helperText:
                'Ücretsizdir; yalnızca sizin Google hesabınızla çalışır',
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
            label: Text(
              _connecting ? 'Tarayıcıda giriş yapın…' : 'Google Drive’a bağlan',
            ),
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
    final uri = Uri.parse('https://console.cloud.google.com/apis/credentials');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Konsol açılamadı: $e')));
      }
    }
  }

  Future<void> _connect() async {
    final id = _clientId.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Önce ücretsiz client ID alıp yapıştırın (yukarıdaki adımlar)',
          ),
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
      return Text(
        '$_provider için rehber bulunamadı.',
        style: theme.textTheme.bodySmall,
      );
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
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_done_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_provider hesabı bağlı ✓',
                    style: theme.textTheme.titleSmall,
                  ),
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
              _connecting ? 'Tarayıcıda giriş yapın…' : '$_provider’a bağlan',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _connectGeneric() async {
    final api = oauthApiFor(_provider);
    if (api == null) return;
    final id = _clientId.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Önce ücretsiz client ID alıp yapıştırın (yukarıdaki adımlar)',
          ),
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
            SnackBar(content: Text('Bağlanılamadı: ${friendlyCloudError(e)}')),
          );
      }
    }
  }

  Future<void> _disconnectGeneric() async {
    final api = oauthApiFor(_provider);
    if (api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bağlantıyı kes'),
        content: Text('$_provider hesabı bu cihazdan kaldırılsın mı?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kes'),
          ),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sayfa açılamadı: $e')));
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
