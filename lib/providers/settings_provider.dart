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
  static const _kViewStyle = 'view_style';
  static const _kDeviceModeChosen = 'device_mode_chosen';
  static const _kPermissionsOnboarded = 'permissions_onboarded';
  static const _kDynamicColor = 'dynamic_color';
  static const _kHiddenHomeCategories = 'hidden_home_categories';

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

  /// Görünüm düzeni: ana ekran ızgarasındaki sütun sayısı.
  ///
  /// • `auto`   → cihaz genişliğine göre (3/4/5)
  /// • `large`  → büyük kartlar: dikey 2 / yatay 3
  /// • `medium` → dengeli: dikey 3 / yatay 4
  /// • `small`  → sıkışık: dikey 4 / yatay 6
  String get viewStyle => _prefs.getString(_kViewStyle) ?? 'auto';

  set viewStyle(String value) {
    _prefs.setString(_kViewStyle, value);
    notifyListeners();
  }

  /// İlk açılıştaki "Mobil-Tablet / TV sürümü" seçimi yapıldı mı.
  /// Yapılmadıysa uygulama [DeviceModeScreen] ile açılır.
  bool get deviceModeChosen => _prefs.getBool(_kDeviceModeChosen) ?? false;

  set deviceModeChosen(bool value) {
    _prefs.setBool(_kDeviceModeChosen, value);
    notifyListeners();
  }

  /// Sürüm seçimi: 'phone' (Mobil-Tablet) veya 'tv' (TV Sürümü).
  /// Seçime göre gereken ayarları otomatik uygular:
  /// • TV → kumanda odaklı TV arayüzü + koyu tema
  /// • Telefon/tablet → klasik dokunmatik arayüz
  void applyDeviceMode(String mode) {
    tvMode = mode;
    if (mode == 'tv') {
      themeMode = ThemeMode.dark;
    }
    deviceModeChosen = true;
  }

  /// İlk açılıştaki izin onayı tamamlandı mı?
  bool get permissionsOnboarded => _prefs.getBool(_kPermissionsOnboarded) ?? false;

  set permissionsOnboarded(bool value) {
    _prefs.setBool(_kPermissionsOnboarded, value);
    notifyListeners();
  }

  /// Material You: Android 12+ sistem (dinamik) rengi kullanılsın mı?
  /// Eski sürüm/cihazda etkisizdir (dinamik palet yoksa turkuaza döner).
  bool get dynamicColor => _prefs.getBool(_kDynamicColor) ?? true;

  set dynamicColor(bool value) {
    _prefs.setBool(_kDynamicColor, value);
    notifyListeners();
  }

  /// Ana ekranda **gizlenmiş** kategori kimlikleri.
  ///
  /// Boş küme = tüm kartlar görünür (varsayılan). Gizlenen kart yalnızca
  /// ana ekrandan kaldırılır; çekmece, ayarlar ve rotalar etkilenmez, yani
  /// özellik tamamen erişilemez olmaz.
  ///
  /// Kullanıcıya hiç sunulmayan kartlar (örn. doğrulaması tamamlanmamış
  /// "Bulut") zaten `kHomeCategories` listesinde yer almaz; bunlar bu kümeye
  /// hiç girmez, gizleme listesi yalnızca gösterilen kartlarla ilgilidir.
  Set<String> get hiddenHomeCategories =>
      (_prefs.getStringList(_kHiddenHomeCategories) ?? const <String>[])
          .toSet();

  set hiddenHomeCategories(Set<String> value) {
    // Sıralı saklanır: prefs içeriği kararlı ve testlerde öngörülebilir olur.
    _prefs.setStringList(_kHiddenHomeCategories, value.toList()..sort());
    notifyListeners();
  }

  /// Kategori ana ekranda görünür mü?
  bool isCategoryVisible(String id) => !hiddenHomeCategories.contains(id);

  /// Tek bir kategoriyi gösterir veya gizler.
  void setCategoryVisible(String id, bool visible) {
    final hidden = hiddenHomeCategories;
    if (visible) {
      hidden.remove(id);
    } else {
      hidden.add(id);
    }
    hiddenHomeCategories = hidden;
  }

  /// Tüm ana ekran kartlarını yeniden gösterir.
  ///
  /// Bu, kullanıcının kendi kararını da siler: kartlar **hiçbiri varsayılan
  /// olarak gizli olmadığından** hepsi yeniden görünür olur. Varsayılandan
  /// gizli kart kavramı bilinçli olarak yoktur — yeni bir kart eklendiğinde
  /// kullanıcı onu istemediği sürece görünür başlar.
  void resetHiddenHomeCategories() => hiddenHomeCategories = <String>{};
}
