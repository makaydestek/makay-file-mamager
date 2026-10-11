import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'ftp_tls_cert.dart';

/// Makay Dosya Yöneticisi — gömülü mini FTP sunucusu.
///
/// Saf Dart soket implementasyonu; PASV (pasif) mod desteklidir.
/// Ek olarak FTPS (implicit TLS) portu sunar: [tlsPort] üzerinde her
/// bağlantı şifreli kurulur (FTPS istemcileri için).
class MiniFtpServer {
  MiniFtpServer({
    required this.rootPath,
    this.port = 2121,
    this.tlsPort = 2123,
    this.enableTls = true,
    required this.username,
    required this.password,
    this.showHidden = false,
    this.bindAddress,
  });

  /// Sunucunun kök dizini.
  final String rootPath;
  final int port;

  /// Şifreli (implicit TLS / FTPS) portu.
  final int tlsPort;
  final bool enableTls;

  final String username;
  final String password;
  final bool showHidden;

  /// Sunucunun bağlanacağı arayüz.
  ///
  /// Varsayılan `null` → `anyIPv4`, yani her arayüzde dinler (üretim
  /// davranışı). Testler yalnızca loopback üzerinden konuşur; loopback'e
  /// bağlanmak dışarıdan gelebilecek port taraması ya da el sıkışmadan
  /// koparmaları tamamen dışarıda bırakır.
  final InternetAddress? bindAddress;

  InternetAddress get _bind => bindAddress ?? InternetAddress.anyIPv4;

  /// Gömülü sertifika bağlamı (tek örnek).
  static final SecurityContext _tlsContext = () {
    final ctx = SecurityContext();
    ctx.useCertificateChainBytes(utf8.encode(kFtpsCertificatePem));
    ctx.usePrivateKeyBytes(utf8.encode(kFtpsPrivateKeyPem));
    return ctx;
  }();

  bool get running => _control != null || _tlsControl != null;
  ServerSocket? _control;
  ServerSocket? _tlsControl;

  /// Kontrol portunun gerçekten dinlendiği port.
  ///
  /// Yapıcıya `0` verilirse işletim sistemi boş bir port tahsis eder. Bu,
  /// "önce boş port bulup sonra bağlanmak" yaklaşımındaki yarışı (TOCTOU)
  /// tamamen ortadan kaldırır: port artık seçilmez, **tahsis edilir**.
  int get boundPort => _control?.port ?? port;

  /// FTPT (FTPS) portunun gerçekten dinlendiği port; `tlsPort` `0` verilmişse
  /// tahsis edilen port.
  int get boundTlsPort => _tlsControl?.port ?? tlsPort;
  final _log = StreamController<String>.broadcast();
  final _random = Random();

  /// Sunucu günlüğü (ekranda gösterilir).
  Stream<String> get log => _log.stream;

  Future<void> start() async {
    if (running) return;
    final control = await ServerSocket.bind(_bind, port);
    _control = control;
    _log.add('FTP sunucusu başladı: port ${control.port}');
    // onError şart: dinleyici düzeyinde gelen bir soket hatası (örn. geçici
    // EPIPE) onError yoksa aboneye hiç ulaşmaz ve bölge dışına taşar; bu da
    // beklenmedik biçimde çöküşe yol açar. Burada günlüğe yazılır.
    control.listen(
      (socket) => unawaited(_handleClient(socket)),
      onError: (Object e) => _log.add('FTP dinleyici hatası: $e'),
    );
    if (enableTls) {
      try {
        final tls = await ServerSocket.bind(_bind, tlsPort);
        _tlsControl = tls;
        _log.add('FTPS sunucusu başladı: port ${tls.port} (şifreli)');
        tls.listen(
          (socket) => unawaited(_handleTlsClient(socket)),
          onError: (Object e) => _log.add('FTPS dinleyici hatası: $e'),
        );
      } catch (e) {
        _log.add('FTPS başlatılamadı: $e');
      }
    }
  }

  Future<void> stop() async {
    await _control?.close();
    _control = null;
    await _tlsControl?.close();
    _tlsControl = null;
    _log.add('Sunucu durdu.');
  }

  /// Şifreli bağlantı kabul eder (implicit TLS / FTPS).
  Future<void> _handleTlsClient(Socket raw) async {
    try {
      final secure = await SecureSocket.secureServer(raw, _tlsContext);
      await _handleClient(secure, secureConnection: true);
    } catch (e) {
      _log.add('TLS el sıkışması başarısız: $e');
      raw.destroy();
    }
  }

  /// Bağlanan istemci oturumu.
  Future<void> _handleClient(Socket socket,
      {bool secureConnection = false}) async {
    final session =
        _FtpSession(socket, this, isSecure: secureConnection);
    try {
      await session.run();
    } catch (_) {
      // Oturum hataları yutulur; bağlantı kapanır.
    } finally {
      socket.destroy();
    }
  }

  String resolve(String virtualPath) {
    var p = virtualPath.replaceAll('\\', '/');
    if (!p.startsWith('/')) p = '/$p';
    final segments = <String>[];
    for (final seg in p.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(seg);
    }
    final joined = segments.join(Platform.pathSeparator);
    return joined.isEmpty
        ? rootPath
        : '$rootPath${Platform.pathSeparator}$joined';
  }

  /// İstemciye gösterilecek sanal yol ("/", "/DCIM").
  String toVirtual(String fsPath) {
    if (fsPath == rootPath) return '/';
    final rel = fsPath.startsWith(rootPath)
        ? fsPath.substring(rootPath.length).replaceAll('\\', '/')
        : '/';
    return rel.startsWith('/') ? rel : '/$rel';
  }

  /// Dinamik PASV veri portu (kontrol portunun1-38 üstü).
  /// Dönen port tahmini bir adaydır; bağlanırken [MiniFtpServer]'daki
  /// yeniden deneme döngüsü dolu portları eleyip sonunda port 0'a düşer.
  int pickDataPort() => boundPort + 1 + _random.nextInt(38);
}

/// Tek istemci oturumu.
class _FtpSession {
  _FtpSession(this.socket, this.server, {this.isSecure = false});

  final Socket socket;
  final MiniFtpServer server;

  /// Bağlantı şifreli mi (implicit TLS / FTPS portu).
  final bool isSecure;

  /// PROT P sonrası veri bağlantıları da TLS ile mi kurulacak.
  bool protPrivate = false;

  String? user;
  bool authed = false;
  String cwd = '/';
  _FtpTransfer? transfer;
  ServerSocket? dataServer;
  Socket? dataSocket;
  Completer<Socket>? _dataReady;

  Future<void> run() async {
    _reply('220 Makay FTP Sunucu hazır');
    final lines =
        socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      final done = await _handle(line.trim());
      if (done) break;
    }
    await _cleanupTransfer();
  }

  void _reply(String message) {
    socket.write('$message\r\n');
  }

  Future<bool> _handle(String line) async {
    if (line.isEmpty) return false;
    final space = line.indexOf(' ');
    final cmd = (space == -1 ? line : line.substring(0, space)).toUpperCase();
    final arg = space == -1 ? '' : line.substring(space + 1).trim();
    server._log.add('> $line');

    if (!authed && cmd != 'USER' && cmd != 'PASS' && cmd != 'QUIT') {
      _reply('530 Lütfen önce giriş yapın.');
      return false;
    }

    switch (cmd) {
      case 'USER':
        user = arg;
        _reply('331 Kullanıcı adı alındı, şifre bekleniyor');
      case 'PASS':
        if (user == server.username && arg == server.password) {
          authed = true;
          _reply('230 Giriş başarılı. Hoş geldiniz.');
        } else {
          _reply('530 Kullanıcı adı veya şifre hatalı.');
        }
      case 'SYST':
        _reply('215 UNIX Type: L8');
      case 'FEAT':
        _reply(
            '211-Özellikler:\n PASV\n UTF8\n SIZE\n MDTM\n REST STREAM\n211 Son');
      case 'PWD':
      case 'XPWD':
        // cwd zaten sanal yol ('/DCIM' gibi) — doğrudan yazılır.
        _reply('257 "$cwd" mevcut dizin');
      case 'CWD':
        final target = server.resolve(
            arg.startsWith('/') ? arg : '${server.toVirtual(cwd)}/$arg');
        if (Directory(target).existsSync()) {
          cwd = server.toVirtual(target);
          _reply('250 Dizin değiştirildi: $cwd');
        } else {
          _reply('550 Dizin bulunamadı: $arg');
        }
      case 'CDUP':
        final parent = cwd == '/' ? '/' : cwd.substring(0, cwd.lastIndexOf('/').clamp(0, cwd.length));
        cwd = parent.isEmpty ? '/' : parent;
        _reply('250 Üst dizine çıkıldı: $cwd');
      case 'TYPE':
        _reply('200 TYPE $arg kabul edildi');
      case 'PASV':
        await _cleanupTransfer();
        // PASV veri portu tahmin edilemez: seçilen port başka bir süreç
        // tarafından tutulmuş olabilir (özellikle CI/paralel testlerde).
        // Bu yüzden birkaç aday denenir; hiçbiri boş değilse işletim
        // sistemi tahsis eder (port 0) ve **gerçekten dinlenen port**
        // duyurulur.
        dataServer = await _bindDataServer();
        final dataPort = dataServer!.port;
        // İstemci sunucuya loopback'ten bağlanıyorsa PASV da loopback
        // sunar; aksi halde aynı cihazdaki veri bağlantısı yerel ağ
        // arayüzüne gidip güvenlik duvarına takılabilir.
        final remote = socket.remoteAddress;
        final host = remote.isLoopback ? '127.0.0.1' : await _localAddress();
        final parts = host.split('.');
        final p1 = dataPort >> 8;
        final p2 = dataPort & 0xFF;
        _reply(
            '227 Entering Passive Mode (${parts[0]},${parts[1]},${parts[2]},${parts[3]},$p1,$p2)');
        _dataReady = Completer<Socket>();
        dataServer!.listen((s) {
          dataSocket = s;
          if (!(_dataReady?.isCompleted ?? true)) {
            _dataReady!.complete(s);
          }
        });
      case 'LIST':
      case 'NLST':
        await _doList(arg, nlst: cmd == 'NLST');
      case 'RETR':
        await _doRetrieve(arg);
      case 'STOR':
        await _doStore(arg);
      case 'DELE':
        final f = File(server.resolve(_absolute(arg)));
        if (f.existsSync()) {
          f.deleteSync();
          _reply('250 Silindi: $arg');
        } else {
          _reply('550 Dosya bulunamadı.');
        }
      case 'MKD':
      case 'XMKD':
        final d = Directory(server.resolve(_absolute(arg)));
        d.createSync(recursive: true);
        _reply('257 "${server.toVirtual(d.path)}" oluşturuldu');
      case 'RMD':
      case 'XRMD':
        final d = Directory(server.resolve(_absolute(arg)));
        if (d.existsSync()) {
          d.deleteSync(recursive: true);
          _reply('250 Klasör silindi.');
        } else {
          _reply('550 Klasör bulunamadı.');
        }
      case 'SIZE':
        final f = File(server.resolve(_absolute(arg)));
        if (f.existsSync()) {
          _reply('213 ${f.lengthSync()}');
        } else {
          _reply('550 Dosya bulunamadı.');
        }
      case 'MDTM':
        final f = File(server.resolve(_absolute(arg)));
        if (f.existsSync()) {
          final t = f.statSync().modified.toUtc();
          final stamp =
              '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}'
              '${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}${t.second.toString().padLeft(2, '0')}';
          _reply('213 $stamp');
        } else {
          _reply('550 Dosya bulunamadı.');
        }
      case 'OPTS':
        _reply('200 OK');
      case 'AUTH':
        // Açık portta orta seviye yükseltme (explicit AUTH TLS) yerine
        // dedicated şifreli port kullanılır — daha güvenilir.
        final scheme = arg.toUpperCase();
        if (scheme == 'TLS' || scheme == 'SSL' || scheme == 'TLS-C') {
          _reply('502 Bu sunucu yalnızca şifreli porttan (FTPS: '
              '${server.boundTlsPort}) bağlantı kabul eder.');
        } else {
          _reply('504 Desteklenmeyen güvenlik türü: $arg');
        }
      case 'PBSZ':
        _reply('200 PBSZ=0');
      case 'PROT':
        final mode = arg.toUpperCase();
        if (mode == 'P') {
          if (isSecure) {
            protPrivate = true;
            _reply('200 PROT P kabul edildi (veri bağlantısı şifreli)');
          } else {
            _reply(
                '536 PROT P yalnızca şifreli (FTPS) bağlantıda çalışır — '
                'port ${server.boundTlsPort} kullanın');
          }
        } else {
          protPrivate = false;
          _reply('200 PROT C kabul edildi');
        }
      case 'NOOP':
        _reply('200 OK');
      case 'QUIT':
        _reply('221 Görüşürüz');
        return true;
      default:
        _reply('502 Komut desteklenmiyor: $cmd');
    }
    return false;
  }

  String _absolute(String arg) {
    if (arg.startsWith('/')) return arg;
    return '${server.toVirtual(cwd)}/$arg';
  }

  /// Sunucunun yerel ağ IPv4 adresi (wlan/eth öncelikli).
  Future<String> _localAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      // Wi-Fi / ethernet arayüzlerini önceliklendir.
      for (final i in interfaces) {
        final name = i.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wi-fi') ||
            name.contains('eth')) {
          for (final a in i.addresses) {
            if (!a.isLoopback) return a.address;
          }
        }
      }
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback) return a.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Future<void> _doList(String arg, {bool nlst = false}) async {
    final data = await _acceptData();
    if (data == null) {
      _reply('425 Veri bağlantısı açılamadı.');
      return;
    }
    _reply(nlst ? '150 Dosya listesi gönderiliyor' : '150 Liste gönderiliyor');
    final dirPath = arg.isEmpty
        ? server.resolve(cwd)
        : server.resolve(_absolute(arg));
    final dir = Directory(dirPath);
    final buffer = StringBuffer();
    try {
      for (final e in dir.listSync(followLinks: false)) {
        // URI'de klasörler sondaki eğik çizgiyle biter → boş segment atlanır.
        final segments =
            e.uri.pathSegments.where((s) => s.isNotEmpty).toList();
        final name = segments.isEmpty
            ? e.path.split(Platform.pathSeparator).last
            : segments.last;
        if (!server.showHidden && name.startsWith('.')) continue;
        if (nlst) {
          buffer.writeln(name);
        } else {
          final stat = e.statSync();
          final isDir = e is Directory;
          final perms = isDir ? 'drwxr-xr-x' : '-rw-r--r--';
          final date = stat.modified;
          final mon = const [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
          ][date.month - 1];
          final stamp =
              '$mon ${date.day.toString().padLeft(2, ' ')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
          buffer.writeln(
              '$perms 1 owner group ${stat.size.toString().padLeft(12)} $stamp $name');
        }
      }
      data.write(buffer.toString());
    } catch (_) {
      _reply('550 Liste alınamadı.');
    } finally {
      await data.flush();
      await data.close();
      await _closeDataServer();
    }
    _reply('226 Liste tamamlandı');
  }

  Future<void> _doRetrieve(String arg) async {
    final file = File(server.resolve(_absolute(arg)));
    if (!file.existsSync()) {
      _reply('550 Dosya bulunamadı.');
      return;
    }
    final data = await _acceptData();
    if (data == null) {
      _reply('425 Veri bağlantısı açılamadı.');
      return;
    }
    _reply('150 Dosya gönderiliyor (${file.lengthSync()} bayt)');
    try {
      await file.openRead().pipe(data);
      _reply('226 Transfer tamamlandı');
    } catch (_) {
      _reply('426 Transfer kesildi');
    } finally {
      await data.close();
      await _closeDataServer();
    }
  }

  Future<void> _doStore(String arg) async {
    final data = await _acceptData();
    if (data == null) {
      _reply('425 Veri bağlantısı açılamadı.');
      return;
    }
    _reply('150 Dosya alınıyor');
    final file = File(server.resolve(_absolute(arg)));
    try {
      final sink = file.openWrite();
      await data.listen(sink.add).asFuture();
      await sink.flush();
      await sink.close();
      _reply('226 Transfer tamamlandı');
    } catch (_) {
      _reply('426 Transfer kesildi');
    } finally {
      await data.close();
      await _closeDataServer();
    }
  }

  Future<Socket?> _acceptData() async {
    final ready = _dataReady;
    if (ready == null || dataServer == null) return null;
    Socket raw;
    try {
      raw = await ready.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    // PROT P: veri bağlantısı da TLS ile kurulur.
    if (protPrivate) {
      try {
        return await SecureSocket.secureServer(
            raw, MiniFtpServer._tlsContext);
      } catch (_) {
        raw.destroy();
        return null;
      }
    }
    return raw;
  }

  Future<void> _closeDataServer() async {
    await dataServer?.close();
    dataServer = null;
  }

  /// PASV veri soketini bağlar.
  ///
  /// Aday portlar [MiniFtpServer.pickDataPort] ile sırayla denenir; dolu
  /// olanlar `SocketException` ile elenir. Hiçbiri boş değilse port `0`
  /// istenir — işletim sistemi boş bir port tahsis eder ve dinlenen port
  /// [ServerSocket.port] üzerinden duyurulur. Böylece PASV asla "adres
  /// kullanımda" ile düşmez.
  Future<ServerSocket> _bindDataServer() async {
    const maxCandidates = 8;
    for (var attempt = 0; attempt < maxCandidates; attempt++) {
      try {
        return await ServerSocket.bind(
          _bind,
          server.pickDataPort(),
        );
      } on SocketException {
        // Bu port dolu — sıradaki adaya geç.
      }
    }
    return ServerSocket.bind(_bind, 0);
  }

  Future<void> _cleanupTransfer() async {
    await _closeDataServer();
    try {
      dataSocket?.destroy();
    } catch (_) {}
    dataSocket = null;
    _dataReady = null;
  }
}

/// Transfer durumu (kullanılmıyor; genişletmeye hazır).
class _FtpTransfer {
  _FtpTransfer(this.path, this.isUpload);

  final String path;
  final bool isUpload;
}
