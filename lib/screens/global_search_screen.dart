import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/global_search_service.dart';
import '../services/platform_service.dart';
import '../services/transfer.dart';
import '../utils/file_opener.dart';
import '../utils/formats.dart';
import '../widgets/file_thumbnail.dart';
import 'browser_screen.dart';

/// Cihaz geneli arama: dosya sistemi + medya + yüklü uygulamalar.
///
/// Sonuçlar **akış** halinde toplanır; kullanıcı yazmaya devam ettikçe
/// önceki arama iptal edilir (eski sonuçlar ekranda kalmaz). Üstte
/// tür çipleri (Tümü / Dosyalar / Klasörler / Medya / Uygulamalar) ile
/// yalnız istenen kategori taranır — bu hem hızı artırır hem de örneğin
/// uygulama ararken dosya taramasının gereksiz çalışmasını engeller.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

/// Filtre türü ve etiketleri.
enum _Filter { all, files, folders, media, apps }

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  static const _service = GlobalSearchService();

  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Yürürlükteki aramanın iptal belirteci (yeni sorgu gelince iptal).
  CancelToken? _token;

  /// Gecikme zamanlayıcısı: her tuşta değil, yazma durunca ara.
  Timer? _debounce;

  _Filter _filter = _Filter.all;

  final List<SearchHit> _hits = [];
  bool _searching = false;

  /// Sonuçların yeniden çizimi için sayac; eşleşmeler akışta gelir ve
  /// tek tek setState yerine kuyruklanır.
  bool _flushScheduled = false;

  @override
  void initState() {
    super.initState();
    // Ekran açılır açılmaz klavye odaklanır; kullanıcı hemen yazabilir.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _token?.cancel();
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    _token?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _hits.clear();
        _searching = false;
      });
      return;
    }
    final token = CancelToken();
    _token = token;
    setState(() {
      _hits.clear();
      _searching = true;
    });

    void add(SearchHit hit) {
      if (token.isCancelled || !mounted) return;
      _hits.add(hit);
      _scheduleFlush();
    }

    // Seçili filtreye göre yalnız gerekli kaynaklar taranır.
    if (_filter == _Filter.all || _filter == _Filter.files ||
        _filter == _Filter.folders) {
      await _service.scanFiles(query, onHit: add, cancelToken: token);
    }
    if (!token.isCancelled &&
        (_filter == _Filter.all || _filter == _Filter.media)) {
      await _service.scanMedia(query, onHit: add, cancelToken: token);
    }
    if (!token.isCancelled &&
        (_filter == _Filter.all || _filter == _Filter.apps)) {
      await _service.scanApps(query, onHit: add);
    }
    if (!token.isCancelled && mounted) {
      setState(() => _searching = false);
    }
  }

  /// Akışta gelen eşleşmeleri tek frame'de toplu çizer.
  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (mounted) setState(() {});
    });
  }

  /// Sonucun türüne göre açma: dosya/medya → görüntüleyici, klasör →
  /// tarayıcı, uygulama → bilgi + APK işlemleri.
  void _openHit(SearchHit hit) {
    switch (hit.kind) {
      case SearchKind.folder:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BrowserScreen(title: hit.name, rootPath: hit.path),
          ),
        );
      case SearchKind.file:
      case SearchKind.media:
        final entry = hit.asFileEntry;
        if (entry != null) {
          FileOpener.openFile(context, entry);
        }
      case SearchKind.app:
        _showAppSheet(hit);
    }
  }

  /// Yüklü uygulama sonucu: bilgi + APK yolu (kopyala) gibi işlemler.
  void _showAppSheet(SearchHit hit) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: FutureBuilder<Uint8List?>(
                future: PlatformService.appIcon(hit.packageName ?? ''),
                builder: (context, snapshot) => snapshot.data != null
                    ? Image.memory(snapshot.data!, width: 40, height: 40)
                    : const Icon(Icons.android_rounded, size: 40),
              ),
              title: Text(hit.name, maxLines: 1),
              subtitle: Text(hit.subtitle, maxLines: 1),
            ),
            if (hit.size > 0)
              ListTile(
                leading: const Icon(Icons.sd_storage_rounded),
                title: Text('Boyut: ${Formats.size(hit.size)}'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          decoration: const InputDecoration(
            hintText: 'Cihazda ara…',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: (_) => _search(_controller.text),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              tooltip: 'Temizle',
              onPressed: () {
                _controller.clear();
                _search('');
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _buildFilters(),
        ),
      ),
      body: _buildBody(),
    );
  }

  /// Tür filtresi çipleri.
  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          for (final f in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(switch (f) {
                  _Filter.all => 'Tümü',
                  _Filter.files => 'Dosyalar',
                  _Filter.folders => 'Klasörler',
                  _Filter.media => 'Medya',
                  _Filter.apps => 'Uygulamalar',
                }),
                selected: _filter == f,
                onSelected: (_) {
                  setState(() => _filter = f);
                  _search(_controller.text);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.text.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Dosyalarınızda, medyanızda ve\nyüklü uygulamalarınızda arayın.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_hits.isEmpty && _searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hits.isEmpty) {
      return Center(
        child: Text(
          'Sonuç bulunamadı',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    return ListView.builder(
      itemCount: _hits.length + (_searching ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _hits.length) {
          // Tarama sürerken altta ince ilerleme satırı.
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final hit = _hits[index];
        return ListTile(
          leading: switch (hit.kind) {
            SearchKind.app => FutureBuilder<Uint8List?>(
                future: PlatformService.appIcon(hit.packageName ?? ''),
                builder: (context, snapshot) => snapshot.data != null
                    ? Image.memory(snapshot.data!, width: 40, height: 40)
                    : const Icon(Icons.android_rounded, size: 40),
              ),
            _ when hit.asFileEntry != null =>
              SizedBox(
                width: 40,
                height: 40,
                child: FileThumbnail(entry: hit.asFileEntry!, size: 40),
              ),
            _ => const Icon(Icons.insert_drive_file_rounded, size: 40),
          },
          title: Text(hit.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            hit.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: hit.size > 0
              ? Text(
                  Formats.size(hit.size),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : null,
          onTap: () => _openHit(hit),
        );
      },
    );
  }
}
