import 'package:flutter/material.dart';

import '../services/google_drive_service.dart';
import '../services/webdav_service.dart';
import 'cloud_add_dialog.dart';
import 'cloud_common.dart';
import 'cloud_webdav_browse_screen.dart';
import 'google_drive_screen.dart';

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
        connected[name] = await oauthApiFor(name)?.hasTokens() ?? false;
      } catch (_) {
        connected[name] = false;
      }
    }
    if (!mounted) return;
    setState(
      () => _oauthConnected
        ..clear()
        ..addAll(connected),
    );
  }

  Future<void> _add() async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => const AddCloudDialog(),
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
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır'),
          ),
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
                    const Icon(
                      Icons.cloud_rounded,
                      size: 64,
                      color: Colors.grey,
                    ),
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
          ? () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const GoogleDriveScreen()))
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
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => screen));
              }
            }
          : null,
    );
  }

  Future<void> _openConnect([String provider = 'Google Drive']) async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => AddCloudDialog(initialProvider: provider),
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
        MaterialPageRoute(builder: (_) => CloudBrowseScreen(location: loc)),
      ),
    );
  }
}
