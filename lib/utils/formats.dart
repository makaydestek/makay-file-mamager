import 'package:intl/intl.dart';

/// Boyut ve tarih biçimlendirme yardımcıları.
class Formats {
  Formats._();

  /// Bayt değerini seçili birime göre biçimlendirir (örn. "4,4 GB").
  static String size(int bytes, {String unit = 'auto'}) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = 0;
    if (unit != 'auto') {
      index = units.indexOf(unit);
      if (index < 0) index = 0;
      value = bytes / _factor(index);
      return '${_num(value)} ${units[index]}';
    }
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    return '${_num(value)} ${units[index]}';
  }

  static double _factor(int index) {
    var f = 1.0;
    for (var i = 0; i < index; i++) {
      f *= 1024;
    }
    return f;
  }

  static String _num(double v) {
    final s = (v >= 100 || v == v.roundToDouble())
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
    // Türkçe ondalık ayracı.
    return s.replaceAll('.', ',');
  }

  /// Tarih biçimi: "9 Eki 2026" (yerel: tr); pattern verilirse onu kullanır.
  ///
  /// 'tr' takvim verisi yalnızca yerelleştirme yükleyicisi çalıştığında hazır
  /// olur (test/erken açılış gibi durumlarda eksik olabilir); bu yüzden
  /// başarısız olursa varsayılan locale'e düşer.
  static String date(DateTime d, {String pattern = 'd MMM yyyy'}) {
    try {
      return DateFormat(pattern, 'tr').format(d);
    } catch (_) {
      return DateFormat(pattern).format(d);
    }
  }

  /// Ayarlar ekranındaki tarih biçimi seçenekleri (desen → önizleme).
  static const List<({String pattern, String label})> datePatterns = [
    (pattern: 'd MMM yyyy', label: '9 Eki 2026'),
    (pattern: 'dd.MM.yyyy', label: '09.10.2026'),
    (pattern: 'yyyy-MM-dd', label: '2026-10-09'),
    (pattern: 'dd/MM/yyyy', label: '09/10/2026'),
  ];

  /// Saat/dakika: "20:31".
  static String time(DateTime d) => DateFormat('HH:mm').format(d);
}
