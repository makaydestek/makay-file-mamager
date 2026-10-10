import 'dart:io';

import 'package:flutter/material.dart';

import '../services/platform_service.dart';
import '../utils/formats.dart';

/// Uygulamalar ekranı: İndirilenler (APK'lar) / Tümü / Dahili (sistem).
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key, this.initialIndex = 0});

  /// Açılışta gösterilecek sekme (0: indirilenler, 1: tümü, 2: dahili).
  final int initialIndex;

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<InstalledApp> _apps = [];
  List<File> _apkFiles = [];
  bool _loading = true;
  bool _sortDesc = true;

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initialIndex < 0 ? 0 : (widget.initialIndex > 2 ? 2 : widget.initialIndex);
    _tabController = TabController(length: 3, vsync: this, initialIndex: initial);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final apps = await PlatformService.installedApps();
    final apks = _downloadedApks();
    apps.sort((a, b) =>
        _sortDesc ? b.size.compareTo(a.size) : a.size.compareTo(b.size));
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _apkFiles = apks;
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
          tabs: const [
            Tab(text: 'İNDİRİLENLER'),
            Tab(text: 'TÜMÜ'),
            Tab(text: 'DAHİLİ'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _downloadsTab(),
                _appsList(_apps, 'Yüklü uygulama bulunamadı'),
                _appsList(
                  _apps.where((a) => a.isSystem).toList(growable: false),
                  'Cihazla gelen uygulama bulunamadı',
                ),
              ],
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
        );
      },
    );
  }

  /// Yüklenmiş uygulama listesi (TÜMÜ ve DAHİLİ sekmeleri paylaşır).
  Widget _appsList(List<InstalledApp> apps, String emptyMessage) {
    if (apps.isEmpty) {
      return Center(
        child: Text(emptyMessage),
      );
    }
    return ListView.builder(
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        return ListTile(
          leading: app.icon != null
              ? Image.memory(app.icon!, width: 36, height: 36)
              : const Icon(Icons.android_rounded),
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
        );
      },
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
          leading: app.icon != null
              ? Image.memory(app.icon!, width: 36, height: 36)
              : const Icon(Icons.android_rounded),
          title: Text(app.name),
          subtitle: Text(app.packageName),
          trailing: Text(app.size > 0 ? Formats.size(app.size) : '—'),
        );
      },
    );
  }
}
