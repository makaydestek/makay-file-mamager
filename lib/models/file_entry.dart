import 'package:flutter/material.dart';

/// Dosya türleri — ikon ve renk eşlemesi için.
enum FileKind { folder, image, video, audio, document, archive, apk, other }

/// Tarayıcı listesindeki bir dosya/klasör girdisi.
class FileEntry {
  FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;

  String get extension {
    final i = name.lastIndexOf('.');
    return i > 0 ? name.substring(i + 1).toLowerCase() : '';
  }

  FileKind get kind {
    if (isDirectory) return FileKind.folder;
    return switch (extension) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'heic' ||
      'svg' || 'raw' =>
        FileKind.image,
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || 'flv' || '3gp' =>
        FileKind.video,
      'mp3' || 'wav' || 'flac' || 'aac' || 'ogg' || 'm4a' || 'wma' =>
        FileKind.audio,
      'pdf' || 'doc' || 'docx' || 'xls' || 'xlsx' || 'ppt' || 'pptx' ||
      'txt' || 'csv' || 'rtf' || 'odt' || 'md' =>
        FileKind.document,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'bz2' || 'xz' =>
        FileKind.archive,
      'apk' || 'xapk' || 'apks' => FileKind.apk,
      _ => FileKind.other,
    };
  }

  IconData get icon => switch (kind) {
        FileKind.folder => Icons.folder_rounded,
        FileKind.image => Icons.image_rounded,
        FileKind.video => Icons.video_library_rounded,
        FileKind.audio => Icons.music_note_rounded,
        FileKind.document => Icons.description_rounded,
        FileKind.archive => Icons.folder_zip_rounded,
        FileKind.apk => Icons.android_rounded,
        FileKind.other => Icons.insert_drive_file_rounded,
      };

  Color get color => switch (kind) {
        FileKind.folder => const Color(0xFFF9A825),
        FileKind.image => const Color(0xFF8E24AA),
        FileKind.video => const Color(0xFFD32F2F),
        FileKind.audio => const Color(0xFF00897B),
        FileKind.document => const Color(0xFF1976D2),
        FileKind.archive => const Color(0xFF6D4C41),
        FileKind.apk => const Color(0xFF43A047),
        FileKind.other => const Color(0xFF757575),
      };
}
