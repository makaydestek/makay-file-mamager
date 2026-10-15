import 'dart:io';

/// Galeri'de "Gizli" durumuna alınan klasörler `.nomedia` dosyasıyla
/// işaretlenir; bu uygulamada (dosya tarayıcısı ve medya listeleri) da
/// gizli tutulur.
///
/// İstisna: WhatsApp/Telegram/Signal `.nomedia` dosyalarını kendileri
/// yazar; bu bir galeri gizlemesi olmadığından bu klasörler gizlenmez.
bool isHiddenByNomedia(String path, {String? name}) {
  if (_selfNomediaFolders.contains(_folderName(path, name))) return false;
  try {
    return File('$path/.nomedia').existsSync();
  } catch (_) {
    return false;
  }
}

/// Asenkron sürümü: dizin listelemesi sırasında her klasör için çağrılır.
Future<bool> isHiddenByNomediaAsync(String path, {String? name}) async {
  if (_selfNomediaFolders.contains(_folderName(path, name))) return false;
  try {
    return await File('$path/.nomedia').exists();
  } catch (_) {
    return false;
  }
}

/// `.nomedia` dosyasını kendi yazan uygulama klasörleri (gizleme değil).
const _selfNomediaFolders = {'whatsapp', 'telegram', 'signal'};

/// Hem `/` (Android) hem `\` (Windows test ortamı) yol ayracı.
final _pathSep = RegExp(r'[/\\]');

String _folderName(String path, String? name) {
  if (name != null && name.isNotEmpty) return name.toLowerCase();
  var cleaned = path;
  while (cleaned.length > 1 &&
      (cleaned.endsWith('/') || cleaned.endsWith('\\'))) {
    cleaned = cleaned.substring(0, cleaned.length - 1);
  }
  final i = cleaned.lastIndexOf(_pathSep);
  return (i >= 0 ? cleaned.substring(i + 1) : cleaned).toLowerCase();
}
