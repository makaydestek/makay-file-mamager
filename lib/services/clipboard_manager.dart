import 'package:flutter/foundation.dart';

import '../models/file_entry.dart';

/// Kopyala/taşı işlemleri için uygulama genelinde tek örnek pano.
class ClipboardManager extends ChangeNotifier {
  ClipboardManager._();

  static final ClipboardManager instance = ClipboardManager._();

  List<FileEntry> _entries = [];
  bool _isCut = false;

  List<FileEntry> get entries => List.unmodifiable(_entries);
  bool get isCut => _isCut;
  bool get isEmpty => _entries.isEmpty;

  void copy(List<FileEntry> entries) {
    _entries = List.of(entries);
    _isCut = false;
    notifyListeners();
  }

  void cut(List<FileEntry> entries) {
    _entries = List.of(entries);
    _isCut = true;
    notifyListeners();
  }

  void clear() {
    _entries = [];
    _isCut = false;
    notifyListeners();
  }
}
