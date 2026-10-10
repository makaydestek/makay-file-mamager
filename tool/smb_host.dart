// Geliştirme aracı: SMB2 sunucusunu doğrudan PC üzerinde ayağa kaldırır
// (gerçek Windows istemcisiyle elle test için).
//
// Kullanım: dart run tool/smb_host.dart <kök_dizin>
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:makay_file_manager/services/smb_server.dart';

Future<void> main(List<String> args) async {
  final root = args.isNotEmpty ? args[0] : Directory.systemTemp.path;
  final server = MiniSmbServer(
    rootPath: root,
    port: 445,
    shareName: 'makay',
    showHidden: false,
  );
  server.log.listen(print);
  await server.start();
  print('READY: \\\\127.0.0.1\\makay -> $root');
  final done = Completer<void>();
  ProcessSignal.sigterm.watch().listen((_) => done.complete());
  await done.future;
}
