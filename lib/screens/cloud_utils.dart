/// Bulut ekranlarının ortak yardımcıları (döngü bağımsız).
///
/// Bağlantı hatalarının okunabilir metne çevrilmesi ve indirme
/// hedefi/dosya adı çözümlemesi burada tutulur.
library;

import 'dart:async';
import 'dart:io';

/// Bağlantı hatalarının kullanıcıya okunabilir metne çevrilmesi.
String friendlyCloudError(Object e) {
  if (e is SocketException) {
    final where = [
      e.address?.address,
      e.port?.toString(),
    ].where((s) => s != null && s.isNotEmpty).join(':');
    return where.isEmpty
        ? 'İnternet sunucusuna ulaşılamadı'
        : 'İnternet sunucusuna ulaşılamadı ($where)';
  }
  if (e is TimeoutException) return 'Bağlantı zaman aşımına uğradı';
  if (e is HttpException) return e.message;
  final text = '$e';
  return text.length > 160 ? '${text.substring(0, 160)}…' : text;
}

/// Android'de Download klasörü (yoksa oluşturulur); diğer platformlarda
/// ve erişilemiyorsa sistem geçici dizini.
Directory cloudDownloadDir() {
  if (Platform.isAndroid) {
    final dir = Directory('/storage/emulated/0/Download');
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      if (dir.existsSync()) return dir;
    } catch (_) {
      // Download klasörü erişilemiyorsa sistem geçici dizinine düşülür;
      // indirme hedefi her iki durumda da geçerlidir.
    }
  }
  return Directory.systemTemp;
}

/// Ad çakışmasını " (2)", " (3)" ekleyerek çözer.
String cloudUniqueName(Directory dir, String name) {
  if (!File('${dir.path}${Platform.pathSeparator}$name').existsSync()) {
    return name;
  }
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var i = 2; i < 1000; i++) {
    final candidate = '$base ($i)$ext';
    if (!File('${dir.path}${Platform.pathSeparator}$candidate').existsSync()) {
      return candidate;
    }
  }
  return name;
}
