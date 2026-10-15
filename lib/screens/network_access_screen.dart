import 'dart:io';

import 'package:flutter/material.dart';

import '../services/ftp_server.dart';
import '../services/smb_server.dart';
import '../utils/app_paths.dart';

/// Ağdan erişim ekranı: gömülü FTP/FTPS ve SMB2 sunucularını başlat/durdur.
///
/// Referans uygulamadaki "Ağdan erişim" ekranının karşılığı: sunucu adresi
/// `ftp://<ip>:6586`, kullanıcı adı `admin`, şifre rastgele (her açılışta
/// değişir), gizli dosyaları göster, BAŞLAT/DURDUR.
class NetworkAccessScreen extends StatefulWidget {
  const NetworkAccessScreen({super.key});

  @override
  State<NetworkAccessScreen> createState() => _NetworkAccessScreenState();
}

class _NetworkAccessScreenState extends State<NetworkAccessScreen> {
  MiniFtpServer? _server;
  MiniSmbServer? _smb;
  final _logLines = <String>[];

  bool _randomPassword = true;
  bool _showHidden = false;

  /// Referans uygulamayla birebir: FTP kullanıcısı `admin`,
  /// şifre her açılışta rastgele üretilir.
  final _username = 'admin';
  String _password = '';
  String _ipAddress = '…';

  @override
  void initState() {
    super.initState();
    _password = _generatePassword();
    _resolveIp();
  }

  Future<void> _resolveIp() async {
    String? ip;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final i in interfaces) {
        for (final a in i.addresses) {
          final addr = a.address;
          if (!addr.startsWith('127.') && addr.startsWith('192.168.')) {
            ip = addr;
            break;
          }
        }
        if (ip != null) break;
      }
      ip ??= interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .firstWhere((addr) => !addr.startsWith('127.'),
              orElse: () => '127.0.0.1');
    } catch (_) {
      ip = '127.0.0.1';
    }
    if (mounted) setState(() => _ipAddress = ip!);
  }

  String _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final rnd = DateTime.now().microsecondsSinceEpoch;
    final buf = StringBuffer();
    var x = rnd;
    for (var i = 0; i < 10; i++) {
      x = (x * 1103515245 + 12345) & 0x7fffffff;
      buf.write(chars[x % chars.length]);
    }
    return buf.toString();
  }

  Future<void> _toggle() async {
    if (_server?.running ?? false) {
      await _server!.stop();
      setState(() {});
      return;
    }
    final root = await AppPaths.byCategory('internal');
    final server = MiniFtpServer(
      rootPath: root ?? '/',
      port: 6586,
      tlsPort: 6588,
      username: _username,
      password: _randomPassword ? _password : _password,
      showHidden: _showHidden,
    );
    server.log.listen((line) {
      if (!mounted) return;
      setState(() {
        _logLines.add(line);
        if (_logLines.length > 200) _logLines.removeAt(0);
      });
    });
    try {
      await server.start();
      if (mounted) setState(() => _server = server);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sunucu başlatılamadı: $e')),
        );
      }
    }
  }

  Future<void> _toggleSmb() async {
    if (_smb?.running ?? false) {
      await _smb!.stop();
      setState(() {});
      return;
    }
    final root = await AppPaths.byCategory('internal');
    final server = MiniSmbServer(
      rootPath: root ?? '/',
      port: 445,
      shareName: 'makay',
      showHidden: _showHidden,
    );
    server.log.listen((line) {
      if (!mounted) return;
      setState(() {
        _logLines.add(line);
        if (_logLines.length > 200) _logLines.removeAt(0);
      });
    });
    try {
      await server.start();
      if (mounted) setState(() => _smb = server);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SMB sunucusu başlatılamadı: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = _server?.running ?? false;
    final smbRunning = _smb?.running ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Ağdan erişim')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FTP Sunucusu', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Aynı ağdaki bilgisayar veya mobil cihazlardan, bir FTP '
                    'istemcisiyle bu cihazdaki dosyalara erişebilirsiniz.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Rastgele şifre'),
                    subtitle: Text(_randomPassword
                        ? 'Her açılışta değişir: $_password'
                        : 'Kendi şifrenizi belirleyin'),
                    value: _randomPassword,
                    onChanged: running
                        ? null
                        : (v) => setState(() {
                              _randomPassword = v;
                              if (v) _password = _generatePassword();
                            }),
                  ),
                  if (!_randomPassword)
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Şifre',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !running,
                      onChanged: (v) => _password = v,
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Gizli dosyaları göster'),
                    value: _showHidden,
                    onChanged: running
                        ? null
                        : (v) => setState(() => _showHidden = v),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_rounded),
                    title: Text('Kullanıcı adı: $_username'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.language_rounded),
                    title: Text('Sunucu adresi: $_ipAddress:6586'),
                    subtitle: Text(
                      running
                          ? 'Kullanıcı: admin  •  Şifre yukarıda\n'
                              'Şifreli FTPS: $_ipAddress:6588 '
                              '(kendi kendine imzalı sertifika)'
                          : 'Şifreli FTPS: port 6588',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: running
                          ? FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error)
                          : null,
                      icon: Icon(running
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded),
                      label: Text(running ? 'DURDUR' : 'BAŞLAT'),
                      onPressed: _toggle,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SMB2 paylaşımı (Windows)',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Telefon, Windows/Mac/Linux bilgisayarların ağdaki '
                    'paylaşımları gibi görünür. Salt okunurdur; hiçbir '
                    'şifre kabul edilir (yalnızca güvendiğiniz ağda '
                    'etkinleştirin).',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_shared_rounded),
                    title: Text(smbRunning
                        ? 'Paylaşım yolu: \\\\$_ipAddress\\makay'
                        : 'Paylaşım: \\\\IP\\makay (port 445)'),
                    subtitle: smbRunning
                        ? const Text('PC: Win+R → \\\\IP\\makay')
                        : null,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: smbRunning
                          ? FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error)
                          : null,
                      icon: Icon(smbRunning
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded),
                      label: Text(smbRunning ? 'DURDUR' : 'BAŞLAT'),
                      onPressed: _toggleSmb,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sunucu günlüğü', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_logLines.isEmpty)
                    Text('Henüz bağlantı yok.',
                        style: TextStyle(color: theme.colorScheme.outline))
                  else
                    Container(
                      height: 160,
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: _logLines.length,
                        itemBuilder: (context, i) => Text(
                          _logLines[i],
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'İpucu: Bilgisayarınızda dosya yöneticisinin "Ağ / FTP" '
                'bağlantısıyla bu adrese bağlanabilir ya da tarayıcıdan '
                'ftp://$_ipAddress:6586 adresini ziyaret edebilirsiniz.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _server?.stop();
    _smb?.stop();
    super.dispose();
  }
}
