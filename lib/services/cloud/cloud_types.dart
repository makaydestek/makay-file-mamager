// ---------------------------------------------------------------------------
// Ortak bulut tipleri (Dropbox / OneDrive / Box)
//
// Bu üç OAuth sağlayıcısı aynı modeli paylaşır; tekrarı önlemek için ortak
// [CloudItem] ve [CloudApiException] tipleri burada tanımlıdır. Mevcut
// `dropbox_service.dart` import yollarını korumak için o dosya bu tipleri
// yeniden dışa aktarır.
// ---------------------------------------------------------------------------

/// Bulut üzerindeki bir dosya veya klasör.
class CloudItem {
  CloudItem({
    required this.id,
    required this.name,
    required this.isFolder,
    this.size,
    this.modified,
  });

  /// Sağlayıcıya özgü kimlik; dosya işlemleri bu değerle yapılır
  /// (Dropbox'ta dosya/klasör yolu, OneDrive ve Box'ta nesne kimliği).
  final String id;
  final String name;
  final bool isFolder;

  /// Bayt; klasörlerde ve bazı sağlayıcılarda null.
  final int? size;
  final DateTime? modified;

  /// Dropbox, Microsoft Graph (OneDrive) ve Box liste girdilerini ayırt eder.
  ///
  /// Biçimler:
  /// - Dropbox: `{".tag": "file" | "folder", "path_display": "/Klasör/dosya"}`
  /// - OneDrive: `{"file": {...}}` veya `{"folder": {...}}` anahtarı
  /// - Box: `{"type": "file" | "folder", ...}`
  factory CloudItem.fromMap(Map<String, Object?> json) {
    final tag = json['.tag'] as String?;
    if (tag != null) {
      return CloudItem(
        id: '${json['path_display'] ?? json['id'] ?? ''}',
        name: json['name'] as String? ?? '',
        isFolder: tag == 'folder',
        size: (json['size'] as num?)?.toInt(),
        modified: DateTime.tryParse('${json['server_modified'] ?? ''}'),
      );
    }
    if (json.containsKey('file') || json.containsKey('folder')) {
      return CloudItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        isFolder: json.containsKey('folder'),
        size: (json['size'] as num?)?.toInt(),
        modified: DateTime.tryParse('${json['lastModifiedDateTime'] ?? ''}'),
      );
    }
    final type = json['type'] as String?;
    if (type == 'file' || type == 'folder') {
      final folder = type == 'folder';
      return CloudItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        isFolder: folder,
        size: folder ? null : (json['size'] as num?)?.toInt(),
        modified: DateTime.tryParse('${json['modified_at'] ?? ''}'),
      );
    }
    throw const FormatException('Bulut öğesi biçimi tanınmadı');
  }

  @override
  String toString() => name;
}

/// Sağlayıcı liste yanıtındaki girdileri [CloudItem] listesine çevirir.
///
/// Liste anahtarı yoksa veya boşsa boş liste döner.
List<CloudItem> cloudItemsOf(Object? entries) {
  if (entries is! List) return const [];
  return entries
      .whereType<Map<String, Object?>>()
      .map(CloudItem.fromMap)
      .toList();
}

/// Bulut API hatası; [message] doğrudan kullanıcıya gösterilebilir.
class CloudApiException implements Exception {
  const CloudApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Basit uzantı → MIME eşlemesi (bulut yüklemelerinde kullanılır).
String cloudMimeOf(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'mp4' => 'video/mp4',
    'mkv' => 'video/x-matroska',
    'mov' => 'video/quicktime',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'wav' => 'audio/wav',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'zip' => 'application/zip',
    'rar' => 'application/vnd.rar',
    'apk' => 'application/vnd.android.package-archive',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
}
