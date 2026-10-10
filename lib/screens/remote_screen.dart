import 'package:flutter/material.dart';

import '../services/remote_service.dart';
import '../services/sftp_service.dart';
import '../services/smb_client.dart';
import '../services/webdav_service.dart';
import 'ftp_browse_screen.dart';
import 'lan_scan_screen.dart';
import 'sftp_browse_screen.dart';
import 'smb_browse_screen.dart';
import 'webdav_browse_screen.dart';

/// Uzak konumlar ekranı: kayıtlı bağlantılar (FTP/SFTP/SMB/WebDAV) + ekleme.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  List<RemoteLocation> _locations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final locations = await RemoteLocationStore.load();
    if (!mounted) return;
    setState(() {
      _locations = locations;
      _loading = false;
    });
  }

  Future<void> _add() async {
    // Adım 1: tür seçimi (Yerel Ağ / SMB / FTP / SFTP / WebDAV).
    final type = await showDialog<String>(
      context: context,
      builder: (_) => const _TypePickerDialog(),
    );
    if (type == null || !mounted) return;

    // Adım 1b: "Yerel Ağ" doğrudan tarama ekranını açar.
    if (type == 'lan') {
      final added = await Navigator.of(context).push<RemoteLocation>(
        MaterialPageRoute(builder: (_) => const LanScanScreen()),
      );
      if (added != null) await _load();
      return;
    }

    // Adım 2: türe göre doldurulabilir form.
    final loc = await showDialog<RemoteLocation>(
      context: context,
      builder: (_) => RemoteFormDialog(initialType: type),
    );
    if (loc == null) return;
    _locations.add(loc);
    await RemoteLocationStore.save(_locations);
    setState(() {});
  }

  Future<void> _delete(RemoteLocation loc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bağlantıyı sil'),
        content: Text('"${loc.name}" bağlantısı kaldırılsın mı?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _locations.remove(loc);
    await RemoteLocationStore.save(_locations);
    setState(() {});
  }

  void _open(RemoteLocation loc) {
    final Widget screen = switch (loc.type) {
      'sftp' => SftpBrowseScreen(location: loc),
      'smb' => SmbBrowseScreen(location: loc),
      'webdav' => WebDavBrowseScreen(location: loc),
      _ => FtpBrowseScreen(location: loc),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  IconData _icon(RemoteLocation loc) => switch (loc.type) {
        'sftp' => Icons.lock_rounded,
        'smb' => Icons.folder_shared_rounded,
        'webdav' => Icons.cloud_rounded,
        _ => Icons.dns_rounded,
      };

  String _subtitle(RemoteLocation loc) => switch (loc.type) {
        'smb' =>
          '\\\\${loc.host}\\${loc.share.isEmpty ? r'C$' : loc.share} '
              '(${loc.username.isEmpty ? 'misafir' : loc.username})',
        'webdav' => loc.host,
        _ => '${loc.username}@${loc.host}:${loc.port}${loc.startPath}',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uzak')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Uzak konum ekle'),
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
                        const Icon(Icons.cloud_off_rounded,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'Henüz uzak konum eklenmedi.\n'
                          'Yerel ağda SMB/FTP sunucusu bulmak için '
                          '"Yerel Ağ" türünü seçin.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Uzak bir konum ekle'),
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
                      leading: Icon(_icon(loc), color: const Color(0xFF00897B)),
                      title: Text(loc.name),
                      subtitle: Text(_subtitle(loc)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _delete(loc),
                      ),
                      onTap: () => _open(loc),
                    );
                  },
                ),
    );
  }
}

/// Bağlantı türü seçici (Yerel Ağ / SMB / FTP / SFTP / WebDAV).
class _TypePickerDialog extends StatelessWidget {
  const _TypePickerDialog();

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Bağlantı türü seçin'),
      children: [
        _tile(
          context,
          icon: Icons.wifi_tethering_rounded,
          title: 'Yerel Ağ',
          subtitle: 'Ağdaki SMB/FTP/SFTP sunucularını tara',
          type: 'lan',
        ),
        _tile(
          context,
          icon: Icons.folder_shared_rounded,
          title: 'SMB',
          subtitle: 'Windows/Samba paylaşımı (\\\\sunucu\\paylaşım)',
          type: 'smb',
        ),
        _tile(
          context,
          icon: Icons.dns_rounded,
          title: 'FTP',
          subtitle: 'Klasik FTP sunucusu (port 21)',
          type: 'ftp',
        ),
        _tile(
          context,
          icon: Icons.lock_rounded,
          title: 'SFTP',
          subtitle: 'SSH tabanlı güvenli aktarım (port 22)',
          type: 'sftp',
        ),
        _tile(
          context,
          icon: Icons.cloud_rounded,
          title: 'WebDAV',
          subtitle: 'Nextcloud, ownCloud, pCloud vb.',
          type: 'webdav',
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String type,
  }) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, type),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: const Color(0xFF00897B)),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// Tür bazlı uzak konum formu (SMB / FTP / SFTP / WebDAV).
///
/// [defaults] verilirse alanlar önden doldurulur (yerel ağ taramasından
/// gelen hızlı ekleme akışı).
class RemoteFormDialog extends StatefulWidget {
  const RemoteFormDialog({
    super.key,
    required this.initialType,
    this.defaults,
  });

  final String initialType;
  final RemoteLocation? defaults;

  @override
  State<RemoteFormDialog> createState() => _RemoteFormDialogState();
}

class _RemoteFormDialogState extends State<RemoteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _share;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late String _type;
  bool _testing = false;

  static int _defaultPort(String type) => switch (type) {
        'sftp' => 22,
        'smb' => 445,
        'webdav' => 80,
        _ => 21,
      };

  @override
  void initState() {
    super.initState();
    final d = widget.defaults;
    _type = widget.initialType;
    _name = TextEditingController(text: d?.name ?? '');
    _host = TextEditingController(text: d?.host ?? '');
    _port = TextEditingController(text: '${d?.port ?? _defaultPort(_type)}');
    _share = TextEditingController(text: d?.share ?? '');
    _username = TextEditingController(text: d?.username ?? '');
    _password = TextEditingController(text: d?.password ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _share.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  RemoteLocation _location() => RemoteLocation(
        name: _name.text.trim().isEmpty ? _host.text.trim() : _name.text.trim(),
        host: _host.text.trim(),
        type: _type,
        port: int.tryParse(_port.text) ?? _defaultPort(_type),
        username: _username.text.trim(),
        password: _password.text,
        share: _share.text.trim(),
      );

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final loc = _location();
    setState(() => _testing = true);
    try {
      switch (loc.type) {
        case 'sftp':
          final session = await SftpSession.connect(loc);
          await session.close();
        case 'smb':
          final client = await SmbClient.connect(loc);
          await client.list('');
          await client.close();
        case 'webdav':
          await WebDavService().list(
            CloudLocation(
              name: loc.name,
              provider: 'WebDAV',
              url: loc.host,
              username: loc.username,
              password: loc.password,
            ),
          );
        default:
          await const FtpClientService().test(loc);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı başarılı ✅')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bağlantı başarısız: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_location());
  }

  @override
  Widget build(BuildContext context) {
    final isSmb = _type == 'smb';
    final isWebDav = _type == 'webdav';
    return AlertDialog(
      title: Text('${_type.toUpperCase()} konumu ekle'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Bağlantı adı'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _host,
                decoration: InputDecoration(
                  labelText: isWebDav ? 'Adres (URL)' : 'Sunucu (host / IP)',
                  hintText: isWebDav ? 'https://sunucu/dav/yol' : null,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Sunucu adresi gerekli'
                    : null,
              ),
              if (!isWebDav) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _port,
                  decoration: const InputDecoration(labelText: 'Port'),
                  keyboardType: TextInputType.number,
                ),
              ],
              if (isSmb) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _share,
                  decoration: const InputDecoration(
                    labelText: 'Paylaşım adı',
                    hintText: 'örn. Paylasim, home veya C\$',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Paylaşım adı gerekli (örn. C\$)'
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                decoration: InputDecoration(
                  labelText: 'Kullanıcı adı',
                  hintText: _type == 'ftp' ? 'anonymous' : null,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Şifre'),
                obscureText: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _testing ? null : _test,
          child: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Test et'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _testing ? null : _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
