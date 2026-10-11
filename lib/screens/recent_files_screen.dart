import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../utils/debug_log.dart';
import '../utils/formats.dart';
import '../services/recent_seen_store.dart';
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

  /// Kullanıcı listeyi "Temizle" ile boşalttı mı?
  ///
  /// Tarama gerçekten boş döndüğü ile kullanıcının temizlediği ayrı mesajlar
  /// gösterir; dosyalar hiçbir durumda silinmez.
  bool _cleared = false;

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
      final scanned = raw.map(RecentFile.fromMap).toList();
      // Geçmişi temizlenenler ("okunmuş") tekrar listelenmez — e-posta
      // okundu/okunmadı mantığı. Yalnızca sonradan eklenen/değişen dosyalar
      // burada kalır.
      final seen = await RecentSeenStore.load();
      final files = scanned
          .where((f) =>
              !seen.contains(RecentSeenStore.keyOf(f.path, f.modified)))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _files = files;
        // `_cleared` bilinçli olarak SIFIRLANMAZ: aşağı kaydırmak taramayı
        // yeniler ama geçmişi geri getirmez; "Tüm geçmişi tekrar göster"
        // düğmesi bu yüzden yenilemeden sonra da ekranda kalır.
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _files = const []);
    } finally {
      port.close();
    }
  }

  /// Temizle butonu: tek dokunuşla listeyi boşaltır.
  ///
  /// **Dosyalar silinmez** — yalnızca o an listelenenler "görüldü" olarak
  /// işaretlenir ve bir daha listelenmez. Cihaza sonradan eklenen (ya da
  /// değiştirilen) dosyalar yine burada belirir. Onay diyaloğu yoktur:
  /// işlem geri alınamaz bir veri kaybı değildir.
  Future<void> _clearList() async {
    await RecentSeenStore.markSeen(
      (_files ?? const <RecentFile>[])
          .map((f) => RecentSeenStore.keyOf(f.path, f.modified)),
    );
    if (!mounted) return;
    setState(() {
      _files = const [];
      _cleared = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Liste temizlendi — dosyalarınız silinmedi')),
    );
  }

  /// "Tüm geçmişi tekrar göster": temizleme ("görüldü") işaretlerini siler ve
  /// listeyi geri getirir.
  ///
  /// Dosyalara yine dokunulmaz; yalnızca okundu işareti kalkar. Aşağı
  /// kaydırmak bunu yapmaz — o yalnızca taramayı yeniler (yeni/değişen
  /// dosyalar gelir, temizlenenler gelmez).
  Future<void> _restoreHistory() async {
    await RecentSeenStore.forgetAll();
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    final hasFiles = files != null && files.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Dosyalar'),
        actions: [
          // Yalnızca liste doluyken anlamlı; dosyalara dokunulmaz.
          if (hasFiles)
            IconButton(
              icon: const Icon(Icons.cleaning_services_rounded),
              tooltip: 'Temizle',
              onPressed: _clearList,
            ),
        ],
      ),
      body: files == null
          ? const Center(child: CircularProgressIndicator())
          : hasFiles
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: files.length,
                    itemBuilder: (context, index) =>
                        _row(context, files[index]),
                  ),
                )
              : _emptyState(),
    );
  }

  /// Liste boşken: kaydırarak yenilemeye izin veren kaydırılabilir boş ekran.
  ///
  /// Temizleme sonrası (`_cleared`) "Tüm geçmişi tekrar göster" düğmesi de
  /// çıkar; aşağı kaydırmak bunu **yapmaz**. İkisi ayrıdır:
  ///
  /// * **Aşağı kaydırma** → tarama yenilenir; yalnızca sonradan eklenen ya da
  ///   değiştirilen dosyalar gelir, temizlenenler gelmez.
  /// * **Düğme** → `RecentSeenStore.forgetAll` ile okundu işaretleri silinir,
  ///   liste baştan dolar.
  Widget _emptyState() {
    final message = _cleared
        ? 'Geçmişiniz temizlendi.\n'
            'Cihaza eklenen yeni dosyalar burada belirir.'
        : 'Son 7 günde değişen yeni dosya yok.\n'
            'Cihaza yeni dosya eklendiğinde burada görünecek.';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  height: 1.5,
                ),
          ),
          if (_cleared) ...[
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton.icon(
                onPressed: _restoreHistory,
                icon: const Icon(Icons.history_rounded),
                label: const Text('Tüm geçmişi tekrar göster'),
              ),
            ),
          ],
        ],
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
