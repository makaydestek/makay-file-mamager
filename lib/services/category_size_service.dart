import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import '../utils/formats.dart';
import 'platform_service.dart';
import 'recent_seen_store.dart';
import 'remote_service.dart';
import 'webdav_service.dart';

/// Ana ekran kategori başlıklarının altına gösterilecek özet metinler.
///
/// Tüm tarama işi izolatta (arka plan) yürütülür; sonuç önbelleğe alınır.
/// Ekran ilk açıldığında önbellekteki değer anında gösterilir, taze hesap
/// tamamlanınca başlıklar sessizce güncellenir.
class CategorySizeService {
  CategorySizeService._();

  static const _cacheKey = 'category_sizes_cache';

  /// Önbelleğin taze sayıldığı süre; dolarsa yeniden hesaplanır.
  ///
  /// Dosya işlemleri (silme/taşıma/temizlik) [invalidate] ile önbelleği
  /// anında siler; bu süre yalnızca "değişiklik olmayan" durumlarda geçerli
  /// kalan bayatlık payıdır — bu yüzden kısa tutulur.
  static const cacheMaxAge = Duration(minutes: 10);

  /// Kategori kimliği → başlık altı metin (ör. "1,5 GB", "3 hesap").
  static final ValueNotifier<Map<String, String>> labels =
      ValueNotifier(const {});

  static bool _running = false;

  /// Bir hesaplama sürerken gelen zorunlu istek (bkz. [refresh]).
  static bool _pendingForce = false;

  /// Tarama sürüyor mu (test/uyarı amaçlı).
  static bool get running => _running;

  /// Önbelleği geçersiz kılar: bir sonraki [refresh] bayatlık payına
  /// bakılmaksızın yeniden hesaplar.
  ///
  /// **Dosya değiştiren her işlem sonrası çağrılır** (silme, taşıma,
  /// kopyalama, temizleme). Yoksa ana ekran kartları 10 dakika boyunca
  /// silinmiş bir dosyanın boyutunu göstermeye devam ederdi.
  ///
  /// Yalnızca önbelleği siler; hesap [refresh] çağrısında yapılır (ağır
  /// tarama olduğundan her dosya işleminde hemen çalıştırılmaz).
  static Future<void> invalidate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (e) {
      // Önbellek silinemezse bayat değer bir sonraki açılışta tazelenir.
      logSwallowed('kategori boyutu: önbellek silme', e);
    }
  }

  /// Kategori özetlerini yükler; [force] ile önbellek atlanır.
  ///
  /// Hesaplama sürerken gelen zorunlu istek **yutulmaz**: bir sonraki
  /// hesap bitiminde yeniden çalıştırılır. Yoksa kullanıcı "Yenile" dese
  /// bile bayat etiket değişmezdi.
  static Future<void> refresh({bool force = false}) async {
    if (_running) {
      if (force) _pendingForce = true;
      return;
    }
    _running = true;
    try {
      final cached = await _readCache();
      if (cached != null) {
        labels.value = Map.unmodifiable(cached.$2);
        final fresh =
            DateTime.now().difference(cached.$1) < cacheMaxAge;
        if (fresh && !force) return;
      }
      final computed = await _compute();
      // Kısmi sonuç (izin hatası, izolat düşüşü) ekrandaki değerleri
      // SİLMEZ: yeni gelenlerle birleştirilir; hiç gelmediyse eskisi korunur.
      if (computed.isEmpty) return;
      final merged = <String, String>{...labels.value, ...computed};
      await _writeCache(merged);
      labels.value = Map.unmodifiable(merged);
    } catch (e) {
      // Boyut hesaplaması ana akışı asla bozmamalı; yutulduğu izlenebilsin.
      logSwallowed('kategori boyutu: yenileme', e);
    } finally {
      _running = false;
      if (_pendingForce) {
        _pendingForce = false;
        await refresh(force: true);
      }
    }
  }

  /// Hesaplama: depolama bilgisi + klasör taraması + uygulama boyutları.
  static Future<Map<String, String>> _compute() async {
    final out = <String, String>{};

    // Ana bellek: kullanılan / toplam; Bellek Analizi: kalan boş alan.
    final storage = await PlatformService.storageInfo();
    if (storage != null && storage.total > 0) {
      out['internal'] =
          '${Formats.size(storage.total - storage.free)} / ${Formats.size(storage.total)}';
      out['analysis'] = '${Formats.size(storage.free)} boş';
    }

    // Klasör bazlı boyutlar izolatta (arayüz donmadan) hesaplanır.
    // Kapanış gönderilmez; test/sanal alan Zone'larında bu hataya yol açar.
    if (Platform.isAndroid) {
      const root = '/storage/emulated/0';
      // "Yeni Dosyalar" boyutu ekrandaki listeyle aynıdır: kullanıcının
      // "Temizle" ile işaretlediği (görülen) dosyalar hariç tutulur. Yoksa
      // kart ile ekran arasındaki değer hiç değişmezdi.
      Set<String> seen;
      try {
        seen = await RecentSeenStore.load();
      } catch (e) {
        logSwallowed('kategori boyutu: görülen dosyalar', e);
        seen = const {};
      }
      final folder = await _scanInIsolate(root, seen);
      for (final e in folder.entries) {
        out[e.key] = Formats.size(e.value);
      }

      // Uygulamalar: yüklü paket boyutları toplamı.
      final apps = await PlatformService.installedApps();
      final appsBytes =
          apps.fold<int>(0, (sum, a) => sum + (a.size > 0 ? a.size : 0));
      if (appsBytes > 0) out['apps'] = Formats.size(appsBytes);
    }

    // Bağlantılı hesap sayıları (Bulut / Uzak).
    try {
      final clouds = await CloudLocationStore.load();
      if (clouds.isNotEmpty) out['cloud'] = '${clouds.length} hesap';
    } catch (e) {
      logSwallowed('kategori: bulut hesapları', e);
    }
    try {
      final remotes = await RemoteLocationStore.load();
      if (remotes.isNotEmpty) out['remote'] = '${remotes.length} bağlantı';
    } catch (e) {
      logSwallowed('kategori: uzak bağlantılar', e);
    }

    return out;
  }

  // -------------------------------------------------------------------------
  // İzolat çalıştırma
  // -------------------------------------------------------------------------

  /// Taramayı izolatta çalıştırır; hata/erişilemeyen durumda boş harita.
  ///
  /// Kapanış (closure) göndermek yerine istek nesnesi gönderilir; çünkü test
  /// veya sanal alan gibi özel Zone'larda kapanış "gönderilemez" sayılır.
  static Future<Map<String, int>> _scanInIsolate(
    String root,
    Set<String> seenRecent,
  ) async {
    final port = ReceivePort();
    try {
      await Isolate.spawn(
        _scanIsolateEntry,
        _SizeScanRequest(
          root: root,
          seenRecent: seenRecent.toList(growable: false),
          reply: port.sendPort,
        ),
      );
      final raw = await port.first;
      if (raw is Map<String, int>) return raw;
      return const {};
    } catch (_) {
      return const {};
    } finally {
      port.close();
    }
  }

  // -------------------------------------------------------------------------
  // İzolat içi tarama (yalnızca dart:io kullanır — channel/builder yok)
  // -------------------------------------------------------------------------

  /// Taranan klasör kökleri (kategoriye göre dosyaların tamamı buradan gelir).
  ///
  /// Resimler/Videolar/Ses ekranları MediaStore üzerinden **cihazın tamamını**
  /// listelediği için, karttaki boyut da yalnızca tek bir klasörü değil bu
  /// klasörlerin tamamını kapsar. Klasör adı geçen uygulamaların medyası
  /// (WhatsApp, Telegram, Instagram …) böylece kategori toplamına girer.
  static const List<String> _scanFolders = [
    'Download',
    'DCIM',
    'Pictures',
    'Screenshots',
    'Camera',
    'Movies',
    'Music',
    'Documents',
    'Recordings',
    'Ringtones',
    'Notifications',
    'Podcasts',
    'Audiobooks',
    'WhatsApp',
    'Telegram',
    'Messenger',
    'Signal',
    'Instagram',
    'Snapchat',
    // Android/media altındaki uygulama medyası (Android 11+ yolu).
    'Android/media',
  ];

  /// Dosya uzantısı → kategori kimliği; bilinmeyen uzantı null.
  ///
  /// Bu sınıflandırma, dosyanın **hangi kategoride listeleneceğini** de
  /// belirler; kategori ekranıyla karttaki toplam böylece aynı dosyaları
  /// sayar (karışık klasörlerde bir dosya tek kategoriye girer).
  static String? categoryOfExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' || 'svg' ||
        'heic' || 'heif' || 'tif' || 'tiff' || 'raw' || 'dng' || 'ico':
        return 'images';
      case 'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || 'flv' || '3gp' ||
        'm4v' || 'ts' || 'wmv' || 'mpg' || 'mpeg' || 'ogv' || '3g2':
        return 'videos';
      case 'mp3' || 'm4a' || 'aac' || 'flac' || 'ogg' || 'opus' || 'wav' ||
        'wma' || 'amr' || 'mid' || 'mka' || 'ape':
        return 'audio';
      case 'pdf' || 'doc' || 'docx' || 'xls' || 'xlsx' || 'ppt' || 'pptx' ||
        'txt' || 'csv' || 'rtf' || 'odt' || 'ods' || 'odp' || 'md' || 'epub' ||
        'json' || 'xml' || 'html' || 'htm' || 'log':
        return 'documents';
      default:
        return null;
    }
  }

  /// Kategori kimliği → toplam bayt.
  ///
  /// * `downloads` → `Download` klasörünün **içindeki her şey** (ekran da
  ///   o klasörü açtığı için kart da onu gösterir).
  /// * `images` / `videos` / `audio` / `documents` → yukarıdaki klasörlerde
  ///   **uzantısına göre** sınıflandırılan dosyaların toplamı; böylece
  ///   resim yalnız Resimler, video yalnız Videolar kartına yazılır ve
  ///   toplamlar kategori ekranlarıyla örtüşür.
  /// * `recent` → son 7 günde değişen ve **henüz "Temizle" ile
  ///   işaretlenmemiş** dosyalar (ekranla birebir aynı).
  ///
  /// [root] test için parametre olarak verilir.
  @visibleForTesting
  static Map<String, int> scan(
    String root, {
    Set<String> seenRecent = const {},
    int maxEntries = 60000,
  }) {
    final sep = Platform.pathSeparator;
    return {
      'downloads': dirSize('$root${sep}Download'),
      ...classifySizes(root, maxEntries: maxEntries),
      'recent': recentSize(root, maxEntries: maxEntries, seen: seenRecent),
    };
  }

  /// Klasörlerdeki dosyaları uzantısına göre kategorilere böler.
  ///
  /// Tek bir yürüyüşte her dosya **yalnızca bir** kategoriye yazılır; böylece
  /// toplamlar şişmez ve Resimler/Videolar/Ses ayrımı doğru olur.
  @visibleForTesting
  static Map<String, int> classifySizes(
    String root, {
    int maxEntries = 60000,
  }) {
    final sep = Platform.pathSeparator;
    final totals = <String, int>{
      'images': 0,
      'videos': 0,
      'audio': 0,
      'documents': 0,
    };
    var visited = 0;
    final stack = <String>[
      for (final folder in _scanFolders) '$root$sep$folder',
    ];
    while (stack.isNotEmpty && visited < maxEntries) {
      final path = stack.removeLast();
      List<FileSystemEntity> items;
      try {
        items = Directory(path).listSync(followLinks: false);
      } catch (_) {
        continue; // Erişilemeyen klasör yok sayılır.
      }
      for (final e in items) {
        if (++visited >= maxEntries) break;
        final name = _nameOf(e.path);
        if (name.isEmpty || name.startsWith('.')) continue;
        if (e is Directory) {
          if (name == 'LOST.DIR') continue;
          stack.add(e.path);
        } else if (e is File) {
          final category = categoryOfExtension(_extensionOf(name));
          if (category == null) continue;
          try {
            totals[category] = totals[category]! + e.lengthSync();
          } catch (e) {
            logSwallowed('kategori boyutu: dosya boyutu', e);
          }
        }
      }
    }
    return totals;
  }

  /// Klasörün özyinelemeli toplam boyutu (erişim hataları yutulur).
  @visibleForTesting
  static int dirSize(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return 0;
    var total = 0;
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is File) {
          try {
            total += e.lengthSync();
          } catch (e) {
            logSwallowed('kategori boyutu: dosya boyutu', e);
          }
        } else if (e is Directory) {
          total += dirSize(e.path);
        }
      }
    } catch (e) {
      logSwallowed('kategori boyutu: yürüyüş', e);
    }
    return total;
  }

  /// Son 7 günde değişen dosyaların toplam boyutu ("Yeni Dosyalar").
  ///
  /// [seen] kümesindeki dosyalar (kullanıcının "Temizle" ile işaretledikleri)
  /// **sayılmaz**: kart, ekranda gerçekten listelenen toplamı gösterir.
  ///
  /// Tarama erişilemeyen/ağır dizimler atlanır ve işlem sayısı
  /// sınırlandırılır; böylece arka plan taraması makul sürede biter.
  @visibleForTesting
  static int recentSize(
    String root, {
    int maxEntries = 60000,
    Set<String> seen = const {},
  }) {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    var total = 0;
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
        // Not: uri.pathSegments.last dizinlerde boş döner (sondaki "/" yüzünden);
        // bu yüzden ad her zaman yolun son ögesinden alınır.
        final name = _nameOf(e.path);
        if (name.isEmpty || name.startsWith('.')) continue;
        if (e is Directory) {
          // Ağır/sistem dizimleri atlanır (izolasyon hataları vb.).
          if (name == 'Android' || name == 'LOST.DIR') continue;
          stack.add(e.path);
        } else if (e is File) {
          try {
            final stat = e.statSync();
            if (!stat.modified.isAfter(cutoff)) continue;
            // "Temizle" ile görülmüş dosya kart boyutuna girmez.
            if (seen.contains(RecentSeenStore.keyOf(e.path, stat.modified))) {
              continue;
            }
            total += stat.size;
          } catch (e) {
            logSwallowed('kategori boyutu: son 7 gün', e);
          }
        }
      }
    }
    return total;
  }

  /// Dosya adının uzantısı (nokta yoksa boş).
  static String _extensionOf(String name) {
    final i = name.lastIndexOf('.');
    return i > 0 ? name.substring(i + 1).toLowerCase() : '';
  }

  /// Yolun son ögesi (dosya/dizin adı); ayraç farklarını yutar.
  static String _nameOf(String path) {
    final sep = Platform.pathSeparator;
    final normalized = sep == '/' ? path : path.replaceAll('/', sep);
    final parts = normalized.split(sep);
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].isNotEmpty) return parts[i];
    }
    return '';
  }

  // -------------------------------------------------------------------------
  // Önbellek
  // -------------------------------------------------------------------------

  static Future<(DateTime, Map<String, String>)?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, Object?>;
      final at = DateTime.fromMillisecondsSinceEpoch(
          (map['at'] as num?)?.toInt() ?? 0);
      final values = (map['values'] as Map<String, Object?>?) ?? const {};
      final parsed = <String, String>{
        for (final e in values.entries) e.key: '${e.value}',
      };
      if (at.millisecondsSinceEpoch == 0 || parsed.isEmpty) return null;
      return (at, parsed);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(Map<String, String> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'values': values,
        }),
      );
    } catch (_) {
      // Önbellek yazılamazsa bir sonraki açılışta yeniden hesaplanır;
      // taze sonuç zaten labels'a yazılmıştı, kullanıcı hiçbir şey fark etmez.
    }
  }
}

/// İzolata gönderilecek boyut tarama isteği.
class _SizeScanRequest {
  const _SizeScanRequest({
    required this.root,
    required this.seenRecent,
    required this.reply,
  });

  final String root;

  /// "Temizle" ile görülmüş dosyalar (yol + değiştirme zamanı anahtarı).
  final List<String> seenRecent;
  final SendPort reply;
}

/// İzolat giriş noktası: kapanış yerine üst düzey fonksiyon kullanılır.
void _scanIsolateEntry(_SizeScanRequest req) {
  try {
    req.reply.send(CategorySizeService.scan(
      req.root,
      seenRecent: req.seenRecent.toSet(),
    ));
  } catch (_) {
    req.reply.send(const <String, int>{});
  }
}
