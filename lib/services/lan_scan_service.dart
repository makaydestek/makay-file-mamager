import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Yerel ağda (alt ağda) SMB/FTP/SFTP/WebDAV sunucusu arayan tarayıcı.
class LanDevice {
  LanDevice(this.ip, this.openPorts);

  final String ip;
  final List<int> openPorts;

  bool get hasSmb => openPorts.contains(445);
  bool get hasFtp => openPorts.contains(21);
  bool get hasSftp => openPorts.contains(22);
  bool get hasWebDav =>
      openPorts.contains(80) || openPorts.contains(443) || openPorts.contains(5005);

  String get summary {
    final labels = <String>[];
    if (hasSmb) labels.add('SMB');
    if (hasFtp) labels.add('FTP');
    if (hasSftp) labels.add('SFTP');
    if (hasWebDav) labels.add('Web/DAV');
    return labels.isEmpty ? 'Açık port yok' : labels.join(' · ');
  }
}

class LanScanService {
  /// Taranan portlar: SMB 445, FTP 21, SFTP 22, HTTP(S) 80/443, WebDAV 5005.
  static const ports = [445, 21, 22, 80, 443, 5005];

  /// Yerel ağın alt ağını ('192.168.1' gibi) bulur; bulunamazsa null.
  static Future<String?> localSubnet() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          final a = addr.address;
          if (a.startsWith('192.168.') ||
              a.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a)) {
            final parts = a.split('.');
            return '${parts[0]}.${parts[1]}.${parts[2]}';
          }
        }
      }
    } catch (_) {
      // Arayüz listesi alınamazsa null döner.
    }
    return null;
  }

  /// Alt ağı tarar. [onProgress] (tamamlanan, toplam) çağrılır.
  static Future<List<LanDevice>> scan({
    void Function(int done, int total)? onProgress,
  }) async {
    final subnet = await localSubnet();
    if (subnet == null) return [];
    final hosts = [for (var i = 1; i <= 254; i++) '$subnet.$i'];
    final found = <String, LanDevice>{};
    var done = 0;
    const batch = 48;
    for (var i = 0; i < hosts.length; i += batch) {
      final chunk = hosts.sublist(i, min(i + batch, hosts.length));
      await Future.wait(chunk.map((ip) async {
        final open = <int>[];
        for (final p in ports) {
          try {
            final s = await Socket.connect(
              ip,
              p,
              timeout: const Duration(milliseconds: 350),
            );
            open.add(p);
            s.destroy();
          } catch (_) {
            // Kapalı portlar yutulur.
          }
        }
        done++;
        onProgress?.call(done, hosts.length);
        if (open.isNotEmpty) found[ip] = LanDevice(ip, open);
      }));
    }
    final list = found.values.toList()
      ..sort((a, b) {
        final pa = a.ip.split('.').map(int.parse).toList();
        final pb = b.ip.split('.').map(int.parse).toList();
        for (var i = 0; i < 4; i++) {
          if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
        }
        return 0;
      });
    return list;
  }
}
