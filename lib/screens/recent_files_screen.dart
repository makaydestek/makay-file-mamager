import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../utils/debug_log.dart';
import '../utils/formats.dart';
import 'browser_screen.dart' show kAudioExts, kImageExts, kVideoExts;
import 'image_viewer_screen.dart';
import 'media_viewer_screen.dart';

/// Son değiştirilen dosya.
class RecentFile {
  RecentFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;

  factory RecentFile.fromMap(Map<String, Object?> map) => RecentFile(
        path: '${map['path']}',
        name: '${map['name']}',
        size: (map['size'] as num?)?.toInt() ?? 0,
        modified: DateTime.fromMillisecondsSinceEpoch(
            (map['modified'] as num?)?.toInt() ?? 0),
      );
}

/// "Yeni Dosyalar" ekranı: son 7 günde değişen dosyalar, büyükten küçüğe.
///
/// Tarama izolatta yapılır; kullanıcı "…" yer tutucusu görür ve sonuç
/// "(Tarih • Boyut)" biçimiyle listelenir.
class RecentFilesScreen extends StatefulWidget {
  const RecentFilesScreen({super.key, this.root});

  /// Tarama kökü; verilmezse platforma göre seçilir (testlerde verilir).
  final String? root;

  @override
  State<RecentFilesScreen> createState() => _RecentFilesScreenState();
}

class _RecentFilesScreenState extends State<RecentFilesScreen> {
  List<RecentFile>? _files;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Tarama kökü: Android ana depolama, diğer platformlarda kullanıcı klasörü.
    final root = widget.root ??
        (Platform.isAndroid
            ? '/storage/emulated/0'
            : (Platform.environment['USERPROFILE'] ??
                Directory.systemTemp.path));

    // İzolat, kapanış (closure) gönderilmeden başlatılır: test/sanal alan
    // gibi özel Zone'larda `Isolate.run` gönderilemez nesne hatası verir.
    final port = ReceivePort();
    try {
      await Isolate.spawn(
        _scanIsolateEntry,
        _ScanRequest(root: root, limit: 500, reply: port.sendPort),
      );
      final raw = await port.first as List<Map<String, Object?>>;
      final files = raw.map(RecentFile.fromMap).toList();
      if (!mounted) return;
      setState(() => _files = files);
    } catch (_) {
      if (!mounted) return;
      setState(() => _files = const []);
    } finally {
      port.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Dosyalar')),
      body: files == null
          ? const Center(child: CircularProgressIndicator())
          : files.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Son 7 günde değişen dosya bulunamadı.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: files.length,
                    itemBuilder: (context, index) =>
                        _row(context, files[index]),
                  ),
                ),
    );
  }

  Widget _row(BuildContext context, RecentFile f) {
    final ext =
        f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
    final icon = switch (ext) {
      _ when kImageExts.contains(ext) => Icons.image_rounded,
      _ when kVideoExts.contains(ext) => Icons.video_file_rounded,
      _ when kAudioExts.contains(ext) => Icons.audio_file_rounded,
      'apk' => Icons.android_rounded,
      'pdf' => Icons.picture_as_pdf_rounded,
      'zip' ||
      'rar' ||
      '7z' =>
        Icons.folder_zip_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
    return ListTile(
      leading: Icon(icon, size: 32, color: const Color(0xFF00897B)),
      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '(${Formats.date(f.modified)} • ${Formats.size(f.size)})',
        maxLines: 1,
      ),
      onTap: () => _open(f),
    );
  }

  /// Dosya türüne göre önizleme; desteklenmeyen türde bilgi diyaloğu.
  void _open(RecentFile f) {
    final ext =
        f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
    final file = File(f.path);
    if (kImageExts.contains(ext)) {
      Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => ImageViewerScreen(file: file, title: f.name)),
      );
    } else if (kVideoExts.contains(ext)) {
      Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => MediaViewerScreen(file: file, isVideo: true)),
      );
    } else if (kAudioExts.contains(ext)) {
      Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => MediaViewerScreen(file: file, isVideo: false)),
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Boyut: ${Formats.size(f.size)}'),
              Text('Değiştirilme: ${Formats.date(f.modified)}'),
              const SizedBox(height: 8),
              SelectableText('Konum: ${f.path}'),
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
  }
}

/// İzolata gönderilecek tarama isteği (yalnızca gönderilebilir alanlar).
class _ScanRequest {
  const _ScanRequest({
    required this.root,
    required this.limit,
    required this.reply,
  });

  final String root;
  final int limit;
  final SendPort reply;
}

/// İzolat giriş noktası: kapanış yerine üst düzey fonksiyon kullanılır.
void _scanIsolateEntry(_ScanRequest req) {
  try {
    req.reply
        .send(_scanRecent(req.root, limit: req.limit, maxEntries: 60000));
  } catch (_) {
    req.reply.send(const <Map<String, Object?>>[]);
  }
}

/// İzolat içinde çalışan tarama: son 7 günde değişen dosyalar.
List<Map<String, Object?>> _scanRecent(String root,
    {int limit = 500, int maxEntries = 60000}) {
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  final found = <Map<String, Object?>>[];
  var visited = 0;
  final stack = <String>[root];
  while (stack.isNotEmpty && visited < maxEntries) {
    final path = stack.removeLast();
    List<FileSystemEntity> items;
    try {
      items = Directory(path).listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in items) {
      if (++visited >= maxEntries) break;
      if (e is Directory) {
        // uri.pathSegments.last dizinlerde boş döner; ad yoldan alınır.
        final name = _nameOf(e.path);
        if (name.isEmpty || name.startsWith('.')) continue;
        if (name == 'Android' || name == 'LOST.DIR') continue;
        stack.add(e.path);
      } else if (e is File) {
        try {
          final stat = e.statSync();
          if (!stat.modified.isAfter(cutoff)) continue;
          found.add({
            'path': e.path,
            'name': _nameOf(e.path),
            'size': stat.size,
            'modified': stat.modified.millisecondsSinceEpoch,
          });
        } catch (e) {
          logSwallowed('son dosyalar: stat', e);
        }
      }
    }
  }
  found.sort((a, b) => (b['modified'] as num).compareTo(a['modified'] as num));
  return found.length > limit ? found.sublist(0, limit) : found;
}

/// Yolun son ögesi (dosya/dizin adı); ayraç farklarını yutar.
String _nameOf(String path) {
  final sep = Platform.pathSeparator;
  final normalized = sep == '/' ? path : path.replaceAll('/', sep);
  final parts = normalized.split(sep);
  for (var i = parts.length - 1; i >= 0; i--) {
    if (parts[i].isNotEmpty) return parts[i];
  }
  return '';
}
