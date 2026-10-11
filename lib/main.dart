import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'models/home_category.dart';
import 'providers/settings_provider.dart';
import 'screens/browser_screen.dart';
import 'screens/device_mode_screen.dart';
import 'screens/duplicate_files_screen.dart';
import 'screens/home_screen.dart';
import 'screens/media_category_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/recent_files_screen.dart';
import 'screens/recycle_bin_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/apps_screen.dart';
import 'screens/cloud_screen.dart';
import 'screens/network_access_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/storage_analysis_screen.dart';
import 'screens/temp_cleaner_screen.dart';
import 'screens/tv_home_screen.dart';
import 'screens/usb_storage_screen.dart';
import 'screens/vault_screen.dart';
import 'services/media_service.dart';
import 'services/platform_service.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'utils/app_paths.dart';
import 'widgets/update_dialog.dart';

/// Kök navigator (açılışta güncelleme diyaloğu için).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsProvider.load();
  runApp(
    ChangeNotifierProvider.value(
      value: settings,
      child: const MakayApp(),
    ),
  );
}

class MakayApp extends StatefulWidget {
  const MakayApp({super.key});

  @override
  State<MakayApp> createState() => _MakayAppState();
}

class _MakayAppState extends State<MakayApp> {
  /// Uygulama yaşam döngüsünde yalnızca bir kez sorgulanır.
  static bool _updateChecked = false;

  /// Sürüm seçimi + izin onayı yeni tamamlandı mı?
  bool _setupDone = false;

  /// İlk açılış akışı tamam mı? (sürüm seçimi ve izinler)
  static bool _isSetupComplete(SettingsProvider s) =>
      s.deviceModeChosen && s.permissionsOnboarded;

  @override
  void initState() {
    super.initState();
    // Her açılışta GitHub depoda yeni sürüm sorgulanır (A15/A17).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupDone = _isSetupComplete(context.read<SettingsProvider>());
      _checkUpdate();
    });
  }

  Future<void> _checkUpdate() async {
    if (_updateChecked) return;
    if (!mounted) return;
    // Sürüm seçimi / izin onayı bitmeden güncelleme sorma.
    if (!_isSetupComplete(context.read<SettingsProvider>())) return;
    _updateChecked = true;
    try {
      final info = await UpdateService.check();
      if (info == null || !mounted) return;
      // Navigator her zaman kökte yaşar; taze context kullan.
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      // ignore: use_build_context_synchronously — GlobalKey context'i taze
      // okundu ve mounted ile doğrulandı; asla ana akışı bozmaz.
      await showUpdateDialog(ctx, info);
    } catch (_) {
      // Güncelleme sorgusu asla ana akışı bozmamalı.
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    // İlk açılış akışı (seçim + izinler) bittikten sonra ertelenen
    // güncelleme kontrolünü çalıştır.
    if (_isSetupComplete(settings) && !_setupDone) {
      _setupDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
    }
    // Material You: Android 12+ dinamik sistem rengi (kullanıcı kapatabilir).
    if (!settings.dynamicColor) {
      return _app(settings, null);
    }
    return DynamicColorBuilder(
      // Not: dynamic_color paketi kendi ColorScheme tipini döndürür; tip
      // çakışmasını önlemek için yalnız seed rengi alınır.
      builder: (lightDynamic, darkDynamic) => _app(
        settings,
        (light: lightDynamic?.primary, dark: darkDynamic?.primary),
      ),
    );
  }

  Widget _app(SettingsProvider settings, ({Color? light, Color? dark})? seed) {
    return MaterialApp(
      title: 'Makay Dosya Yöneticisi',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light(dynamicSeed: seed?.light),
      darkTheme: AppTheme.dark(dynamicSeed: seed?.dark),
      themeMode: settings.themeMode,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateRoute: _onGenerateRoute,
      initialRoute: '/',
    );
  }
}

/// Kategori için kök yolu hazırlayıp tarayıcıyı açar (desteklenmiyorsa uyarı).
class _BrowseLauncher extends StatelessWidget {
  const _BrowseLauncher({required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context) {
    final category = kHomeCategories.where((c) => c.id == categoryId).firstOrNull;
    // Medya kategorileri (Görüntüler/Videolar/Ses) mobilde MediaStore ile
    // taranır; diğer platformlarda klasik dosya tarayıcısı kullanılır.
    if (MediaService.supported &&
        const {'images', 'videos', 'audio'}.contains(categoryId)) {
      return MediaCategoryScreen(
        categoryId: categoryId,
        title: category?.title ?? 'Medya',
      );
    }
    return FutureBuilder<String?>(
      future: AppPaths.byCategory(categoryId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return BrowserScreen(
          title: category?.title ?? 'Dosyalar',
          rootPath: snapshot.data,
        );
      },
    );
  }
}

/// Ana ekran seçici: TV modu ayarı + cihaz algılama (A11).
class _HomeLauncher extends StatelessWidget {
  const _HomeLauncher();

  /// TV algılama sonucu uygulama yaşamı boyunca bir kez çözülür.
  static Future<bool>? _isTv;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    // İlk açılış: sürüm seçimi yapılmadıysa seçim ekranı (A18).
    if (!settings.deviceModeChosen) {
      return const DeviceModeScreen();
    }
    // Sürüm seçiminden sonra gerekli cihaz izinleri istenir (A18).
    if (!settings.permissionsOnboarded) {
      return const PermissionsScreen();
    }
    switch (settings.tvMode) {
      case 'tv':
        return const TvHomeScreen();
      case 'phone':
        return const HomeScreen();
      default:
        _isTv ??= PlatformService.isTv();
        return FutureBuilder<bool>(
          future: _isTv,
          builder: (context, snapshot) => (snapshot.data ?? false)
              ? const TvHomeScreen()
              : const HomeScreen(),
        );
    }
  }
}

/// Basit isimli rota yönlendiricisi.
Route<dynamic> _onGenerateRoute(RouteSettings settings) {
  final name = settings.name ?? '/';

  Widget screen;
  switch (name) {
    case '/':
      screen = const _HomeLauncher();
    case '/settings':
      screen = const SettingsScreen();
    case '/analysis':
      screen = const StorageAnalysisScreen();
    case '/apps':
      screen = const AppsScreen();
    case '/apps/system':
      // Dahili (cihazla gelen) uygulamalar sekmesi doğrudan açılır.
      screen = const AppsScreen(initialIndex: 2);
    case '/temp':
      screen = const TempCleanerScreen();
    case '/cloud':
      screen = const CloudScreen();
    case '/remote':
      screen = const RemoteScreen();
    case '/network':
      screen = const NetworkAccessScreen();
    case '/recent':
      // Son 7 günde değişen dosyalar (Yeni Dosyalar kategorisi).
      screen = const RecentFilesScreen();
    case '/recycle':
      screen = const RecycleBinScreen();
    case '/usb':
      // Bağlı USB / SD kart birimleri (OTG algılama).
      screen = const UsbStorageScreen();
    case '/vault':
      // PIN ile korunan şifreli kasa.
      screen = const VaultScreen();
    case '/duplicates':
      // Mükerrer dosya taraması (Geçici Dosyalar ekranından).
      screen = DuplicateFilesScreen(root: AppPaths.scanRoot);
    default:
      // /browse/internal, /browse/images, ... kategori tarayıcıları (A2/A3).
      if (name.startsWith('/browse/')) {
        final id = name.substring('/browse/'.length);
        screen = _BrowseLauncher(categoryId: id);
      } else {
        screen = const Scaffold(
          body: Center(child: Text('Ekran bulunamadı')),
        );
      }
  }
  return MaterialPageRoute(builder: (_) => screen, settings: settings);
}
