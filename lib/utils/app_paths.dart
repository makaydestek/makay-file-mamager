import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Platform bazlı standart klasör yolları.
class AppPaths {
  AppPaths._();

  /// Ana depolama kökü; erişilemezse null (örn. web).
  static Future<String?> internalRoot() async {
    if (Platform.isAndroid) return '/storage/emulated/0';
    if (Platform.isWindows) {
      final home = await getApplicationDocumentsDirectory();
      // Windows'ta kök yerine kullanıcı klasörü açılır.
      return home.path;
    }
    if (Platform.isLinux || Platform.isMacOS) {
      final home = await getApplicationDocumentsDirectory();
      return home.path;
    }
    return null; // web
  }

  /// Ana bellek için (Android kök, diğer platformlarda kök/ilk sürücü).
  static Future<String?> mainStorage() async {
    if (Platform.isAndroid) return '/storage/emulated/0';
    if (Platform.isWindows) {
      final root = await internalRoot();
      return root == null ? null : Directory(root).parent.path;
    }
    return internalRoot();
  }

  static Future<String?> byCategory(String id) async {
    final root = await internalRoot();
    if (root == null) return null;
    final sep = Platform.pathSeparator;
    return switch (id) {
      'downloads' => '$root${sep}Download',
      'images' => '$root${sep}Pictures',
      'audio' => '$root${sep}Music',
      'videos' => '$root${sep}Movies',
      'documents' => '$root${sep}Documents',
      _ => root,
    };
  }
}
