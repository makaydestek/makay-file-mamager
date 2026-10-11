import 'package:shared_preferences/shared_preferences.dart';

/// "Yeni Dosyalar" ekranında **geçmişi temizlenmiş** dosyaların kaydı.
///
/// Davranış e-posta okundu/okunmadı mantığına benzer:
///
/// 1. Tarama son 7 günde değişen dosyaları bulur.
/// 2. Kullanıcı **Temizle** dediğinde o an listelenen dosyalar buraya
///    "görüldü" diye yazılır ve listeden düşer.
/// 3. Sonraki açılışlarda aynı dosyalar **tekrar listelenmez**; yalnızca
///    sonradan cihaza eklenen (ya da değiştirilip yeni zaman damgası alan)
///    dosyalar görünür.
///
/// Dosyalar hiçbir zaman silinmez — burada yalnızca bir "görüldü" işareti
/// tutulur. Değiştirme zamanı anahtarın parçası olduğu için, dosyanın içeriği
/// değişirse yeniden listelenir.
class RecentSeenStore {
  RecentSeenStore._();

  static const _kSeen = 'recent_files_seen';

  /// Saklanan kayıt üst sınırı.
  ///
  /// SharedPreferences tamamen bellekte tutulduğu için sınırsız büyümesin.
  /// Tarama zaten yalnızca son 7 günü kapsadığından eski kayıtlar listeden
  /// düşer; sınır aşıldığında en eskiler atılır.
  static const maxEntries = 3000;

  /// Bir dosya için kararlı kayıt anahtarı: yol + değiştirme zamanı.
  ///
  /// Değiştirme zamanı bilerek anahtara dâhildir: aynı dosya yeniden
  /// yazılırsa yeni zaman damgası alır ve "yeni dosya" olarak yeniden listelenir.
  static String keyOf(String path, DateTime modified) =>
      '$path|${modified.millisecondsSinceEpoch}';

  /// "Görüldü" işaretlenmiş kayıt kümesi.
  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_kSeen) ?? const <String>[]).toSet();
  }

  /// Verilen dosyaları "görüldü" olarak işaretler.
  static Future<void> markSeen(Iterable<String> keys) async {
    if (keys.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final merged = <String>{
      ...?prefs.getStringList(_kSeen),
      ...keys,
    };
    final list = merged.toList();
    // Sınır aşılırsa en eskiler atılır.
    if (list.length > maxEntries) {
      list.removeRange(0, list.length - maxEntries);
    }
    await prefs.setStringList(_kSeen, list);
  }

  /// Kayıtları tamamen siler (dosyalara dokunmaz) — hepsi yeniden görünür.
  static Future<void> forgetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSeen);
  }
}