import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import '../utils/formats.dart';
import 'platform_service.dart';
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
      final folder = await _scanInIsolate(root);
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
  static Future<Map<String, int>> _scanInIsolate(String root) async {
    final port = ReceivePort();
    try {
      await Isolate.spawn(
        _scanIsolateEntry,
        _SizeScanRequest(root: root, reply: port.sendPort),
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

  /// Kategori kimliği → toplam bayt.
  ///
  /// Android kök dizinine göre hesaplanır; erişilemeyen klasörler yok
  /// sayılır. [root] test için parametre olarak verilir.
  /// Not: `analysis` (Bellek Analizi) bu haritada yer almaz; o başlık için
  /// boş alan gösterilir (bkz. [_compute]).
  @visibleForTesting
  static Map<String, int> scan(String root) {
    final sep = Platform.pathSeparator;
    return {
      'downloads': dirSize('$root${sep}Download'),
      'images':
          dirSize('$root${sep}DCIM') + dirSize('$root${sep}Pictures'),
      'videos': dirSize('$root${sep}Movies') +
          dirSize('$root${sep}WhatsApp${sep}Media${sep}WhatsApp Video'),
      'audio': dirSize('$root${sep}Music') +
          dirSize('$root${sep}WhatsApp${sep}Media${sep}WhatsApp Audio'),
      'documents': dirSize('$root${sep}Documents'),
      'recent': recentSize(root),
    };
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
  /// Tarama erişilemeyen/ağır dizimler atlanır ve işlem sayısı
  /// sınırlandırılır; böylece arka plan taraması makul sürede biter.
  @visibleForTesting
  static int recentSize(String root, {int maxEntries = 60000}) {
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
            if (stat.modified.isAfter(cutoff)) total += stat.size;
          } catch (e) {
            logSwallowed('kategori boyutu: son 7 gün', e);
          }
        }
      }
    }
    return total;
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
  const _SizeScanRequest({required this.root, required this.reply});

  final String root;
  final SendPort reply;
}

/// İzolat giriş noktası: kapanış yerine üst düzey fonksiyon kullanılır.
void _scanIsolateEntry(_SizeScanRequest req) {
  try {
    req.reply.send(CategorySizeService.scan(req.root));
  } catch (_) {
    req.reply.send(const <String, int>{});
  }
}
