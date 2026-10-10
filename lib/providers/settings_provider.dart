import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama genelindeki ayarları tutar ve kalıcılaştırır.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs);

  final SharedPreferences _prefs;

  static const _kThemeMode = 'theme_mode';
  static const _kSizeUnit = 'size_unit';
  static const _kDateFormat = 'date_format';
  static const _kRecycleBinDefault = 'recycle_bin_default';
  static const _kRecycleBinConfirm = 'recycle_bin_confirm';
  static const _kShowNavIcon = 'show_nav_icon';
  static const _kDetectUsb = 'detect_usb';
  static const _kShowSystemStorage = 'show_system_storage';
  static const _kStorageWarnPercent = 'storage_warn_percent';
  static const _kTvMode = 'tv_mode';

  static Future<SettingsProvider> load() async =>
      SettingsProvider(await SharedPreferences.getInstance());

  /// Tema: system / light / dark. Her kullanıcıya açık (kısıtlama yok).
  ThemeMode get themeMode => switch (_prefs.getString(_kThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  set themeMode(ThemeMode value) {
    _prefs.setString(_kThemeMode, value.name);
    notifyListeners();
  }

  /// Dosya boyutu birimi (örn. GB).
  String get sizeUnit => _prefs.getString(_kSizeUnit) ?? 'GB';

  set sizeUnit(String value) {
    _prefs.setString(_kSizeUnit, value);
    notifyListeners();
  }

  /// Tarih biçimi deseni (örn. 'd MMM yyyy' → "9 Eki 2026").
  String get datePattern => _prefs.getString(_kDateFormat) ?? 'd MMM yyyy';

  set datePattern(String value) {
    _prefs.setString(_kDateFormat, value);
    notifyListeners();
  }

  bool get recycleBinDefault => _prefs.getBool(_kRecycleBinDefault) ?? true;

  set recycleBinDefault(bool value) {
    _prefs.setBool(_kRecycleBinDefault, value);
    notifyListeners();
  }

  bool get recycleBinConfirm => _prefs.getBool(_kRecycleBinConfirm) ?? true;

  set recycleBinConfirm(bool value) {
    _prefs.setBool(_kRecycleBinConfirm, value);
    notifyListeners();
  }

  bool get showNavIcon => _prefs.getBool(_kShowNavIcon) ?? true;

  set showNavIcon(bool value) {
    _prefs.setBool(_kShowNavIcon, value);
    notifyListeners();
  }

  bool get detectUsb => _prefs.getBool(_kDetectUsb) ?? true;

  set detectUsb(bool value) {
    _prefs.setBool(_kDetectUsb, value);
    notifyListeners();
  }

  bool get showSystemStorage => _prefs.getBool(_kShowSystemStorage) ?? false;

  set showSystemStorage(bool value) {
    _prefs.setBool(_kShowSystemStorage, value);
    notifyListeners();
  }

  /// "Bellek dolu" bildirimi eşiği (%).
  int get storageWarnPercent => _prefs.getInt(_kStorageWarnPercent) ?? 98;

  set storageWarnPercent(int value) {
    _prefs.setInt(_kStorageWarnPercent, value);
    notifyListeners();
  }

  /// Arayüz modu: 'auto' (TV algılanırsa TV), 'tv' (zorla TV), 'phone'.
  String get tvMode => _prefs.getString(_kTvMode) ?? 'auto';

  set tvMode(String value) {
    _prefs.setString(_kTvMode, value);
    notifyListeners();
  }
}
