import 'dart:io';

import 'package:flutter/material.dart';

import '../services/platform_service.dart';
import '../utils/formats.dart';
import '../widgets/apk_install_dialog.dart';
import '../widgets/app_icon.dart';

/// Uygulamalar ekranı: Tümü / İndirilenler (APK'lar) / Dahili (sistem).
///
/// **"TÜMÜ" her zaman en önde ve varsayılan sekmedir** — ekran hangi
/// yoldan (ana ekran kartı, çekmece, `/apps/system`) açılırsa açılsın
/// ilk görülen sekme budur.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key, this.initialIndex = 0});

  /// Açılışta gösterilecek sekme (0: tümü, 1: indirilenler, 2: dahili).
  final int initialIndex;

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;

  List<InstalledApp> _apps = [];
  List<File> _apkFiles = [];
  bool _loading = true;
  bool _sortDesc = true;
  bool _showSystemApps = true;

  /// StorageStats izni yoksa boyutlar yalnız base.apk kadar görünür;
  /// kullanıcı Ayarlar → Kullanım erişimi ile tam boyutları alır.
  bool _usageAccess = true;

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initialIndex < 0 ? 0 : (widget.initialIndex > 2 ? 2 : widget.initialIndex);
    _tabController = TabController(length: 3, vsync: this, initialIndex: initial);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  /// Ayarlar → Kullanım erişimi'nden dönülünce boyutlar tazelensin.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // `installedApps` hata/desteklenmeyen durumda `const []` döndürür;
    // sabit liste `sort` ile değiştirilemediği için MUTLAKA kopyalanır.
    final apps = List<InstalledApp>.of(await PlatformService.installedApps());
    final apks = _downloadedApks();
    final usage = await PlatformService.hasUsageAccess();
    apps.sort((a, b) =>
        _sortDesc ? b.size.compareTo(a.size) : a.size.compareTo(b.size));
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _apkFiles = apks;
      _usageAccess = usage;
      _loading = false;
    });
  }

  /// Download klasöründeki APK dosyaları ("İndirilenler" sekmesi).
  List<File> _downloadedApks() {
    if (!Platform.isAndroid) return const [];
    final dir = Directory('/storage/emulated/0/Download');
    if (!dir.existsSync()) return const [];
    try {
      return dir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.apk'))
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uygulamalar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => showSearch(
              context: context,
              delegate: _AppSearchDelegate(_apps),
            ),
          ),
          IconButton(
            icon: Icon(_showSystemApps
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded),
            onPressed: () =>
                setState(() => _showSystemApps = !_showSystemApps),
            tooltip: _showSystemApps
                ? 'Sistem uygulamalarını gizle'
                : 'Sistem uygulamalarını göster',
          ),
          IconButton(
            icon: const Icon(Icons.sort_rounded),
            onPressed: () {
              setState(() {
                _sortDesc = !_sortDesc;
                _apps.sort((a, b) => _sortDesc
                    ? b.size.compareTo(a.size)
                    : a.size.compareTo(b.size));
              });
            },
            tooltip: 'Boyuta göre sırala',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // "TÜMÜ" her zaman en başta ve varsayılan sekmedir.
          tabs: const [
            Tab(text: 'TÜMÜ'),
            Tab(text: 'İNDİRİLENLER'),
            Tab(text: 'DAHİLİ'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!_usageAccess) _usageAccessBanner(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _appsList(_apps, 'Yüklü uygulama bulunamadı'),
                      _downloadsTab(),
                      _appsList(
                        _apps.where((a) => a.isSystem).toList(growable: false),
                        'Cihazla gelen uygulama bulunamadı',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// Boyutlar yalnız base.apk kadar görünüyor: tam boyut (uygulama +
  /// veri) için Ayarlar → Kullanım erişimi izni gerekir.
  Widget _usageAccessBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: ListTile(
        leading: Icon(Icons.info_outline_rounded, color: scheme.primary),
        title: const Text('Uygulama boyutları eksik görünüyor'),
        subtitle: const Text(
            'Tam boyut için Kullanım erişimi iznini açın.'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => PlatformService.openUsageAccessSettings(),
      ),
    );
  }

  /// İndirilenler: Download klasöründeki APK'lar.
  Widget _downloadsTab() {
    if (_apkFiles.isEmpty) {
      return const Center(child: Text('İndirilmiş APK bulunamadı'));
    }
    return ListView.builder(
      itemCount: _apkFiles.length,
      itemBuilder: (context, index) {
        final file = _apkFiles[index];
        final name = file.uri.pathSegments.isEmpty
            ? file.path.split(Platform.pathSeparator).last
            : file.uri.pathSegments[file.uri.pathSegments.length - 1];
        final size = file.lengthSync();
        return ListTile(
          leading:
              const Icon(Icons.android_rounded, color: Color(0xFF43A047)),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(Formats.size(size)),
          // APK'ya dokununca bilgi yerine Kur/Güncelle ekranı açılır.
          onTap: () => showApkInstallDialog(context, file),
        );
      },
    );
  }

  /// Yüklenmiş uygulama listesi (TÜMÜ ve DAHİLİ sekmeleri paylaşır).
  Widget _appsList(List<InstalledApp> apps, String emptyMessage) {
    // _showSystemApps false olduğunda system uygulamalarını gizle.
    final visibleApps = _showSystemApps
        ? apps
        : apps.where((a) => !a.isSystem).toList(growable: false);

    if (visibleApps.isEmpty) {
      return Center(
        child: Text(emptyMessage),
      );
    }
    return ListView.builder(
      itemCount: visibleApps.length,
      itemBuilder: (context, index) {
        final app = visibleApps[index];
        return ListTile(
          leading: AppIcon(app),
          title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(app.packageName),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                app.size > 0 ? Formats.size(app.size) : '—',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              if (app.versionName.isNotEmpty)
                Text(app.versionName,
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          onTap: () => _appActions(app),
        );
      },
    );
  }

  /// Uygulama işlemleri: APK yedekleme + sistem ayarları.
  Future<void> _appActions(InstalledApp app) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AppIcon(app, size: 32),
              title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${app.packageName} • ${app.versionName}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: const Text('APK\'yı yedekle'),
              subtitle: const Text('Kurulum APK\'sını Download klasörüne kopyalar'),
              enabled: app.sourceDir.isNotEmpty,
              onTap: () => Navigator.pop(context, 'backup'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Uygulama bilgisi'),
              onTap: () => Navigator.pop(context, 'info'),
            ),
          ],
        ),
      ),
    );
    if (action == 'backup') _backupApk(app);
    if (action == 'info') _showAppInfo(app);
  }

  /// Kurulum APK'sı `Download/<ad>-<sürüm>.apk` olarak kopyalanır.
  Future<void> _backupApk(InstalledApp app) async {
    if (app.sourceDir.isEmpty) return;
    setState(() => _loading = true);
    try {
      final source = File(app.sourceDir);
      if (!await source.exists()) throw 'APK kaynağı bulunamadı';
      final dir = Directory('/storage/emulated/0/Download');
      await dir.create(recursive: true);
      final safeName = app.name.replaceAll(RegExp(r'[^\p{L}\p{N} ._-]', unicode: true), '_');
      final dest =
          '${dir.path}${Platform.pathSeparator}$safeName-${app.versionName}.apk';
      await source.copy(dest);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yedeklendi: $dest')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yedeklenemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAppInfo(InstalledApp app) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(app.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paket: ${app.packageName}'),
            Text('Sürüm: ${app.versionName}'),
            Text('Tür: ${app.isSystem ? 'Dahili (sistem)' : 'Yüklü'}'),
            Text('Boyut: ${app.size > 0 ? Formats.size(app.size) : 'Bilinmiyor'}'),
            const SizedBox(height: 8),
            SelectableText('APK: ${app.sourceDir}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}

class _AppSearchDelegate extends SearchDelegate<String> {
  _AppSearchDelegate(this.apps);

  final List<InstalledApp> apps;

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, ''),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final q = query.toLowerCase();
    final results = apps
        .where((a) =>
            a.name.toLowerCase().contains(q) ||
            a.packageName.toLowerCase().contains(q))
        .toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final app = results[index];
        return ListTile(
          leading: AppIcon(app),
          title: Text(app.name),
          subtitle: Text(app.packageName),
          trailing: Text(app.size > 0 ? Formats.size(app.size) : '—'),
        );
      },
    );
  }
}
