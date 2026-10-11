import 'package:flutter/foundation.dart';

/// En iyi niyetli (best-effort) işlemlerde hataları **sessizce yutmak yerine**
/// kısaca günlüğe yazar. Hata yutulur (kullanıcıya gösterilmez) ama
/// izlenebilir olur; sahada "bu özellik neden yanlış sonuç veriyor"
/// sorusunun cevabıdır.
void logSwallowed(String where, Object error) {
  debugPrint('[atlandı] $where: $error');
}
