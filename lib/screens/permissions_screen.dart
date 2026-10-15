import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/permission_service.dart';

/// Ayarlar → İzinler (ve ilk açılış) için izin merkezi.
///
/// Uygulamanın ihtiyaç duyduğu **tüm** erişim izinleri tek ekranda
/// listelenir: durumları görünür, isme göre aranabilir ve her biri
/// doğrudan ilgili sistem ekranından değiştirilebilir. Sistem ayarından
/// dönüldüğünde durum otomatik tazelenir. İlk açılışta (yönlendirme
/// modunda) "Devam et" akışı gösterilir.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

/// İzin satırı tanımı (arama + gruplama için).
class _Perm {
  const _Perm({
    required this.group,
    required this.icon,
    required this.title,
    required this.keywords,
    required this.description,
    required this.technical,
    required this.granted,
    this.automatic = false,
    this.note,
    this.onAction,
  });

  /// Grup başlığı (izmin ekrandaki kategorisi).
  final String group;
  final IconData icon;
  final String title;

  /// Arama için ek anahtar kelimeler (teknik/kısa adlar).
  final String keywords;
  final String description;

  /// Teknik izin adı (ör. PACKAGE_USAGE_STATS).
  final String technical;
  final bool granted;

  /// Kullanıcı ayarı yok; sistem tarafından otomatik verilir.
  final bool automatic;

  /// Durum satırının yanındaki not (ör. "Zorunlu").
  final String? note;

  /// İzin ver/değiştir eylemi; null ise eylem yoktur.
  final Future<void> Function()? onAction;
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  static const _groupFiles = 'Dosya ve medya';
  static const _groupApp = 'Uygulama izinleri';
  static const _groupAuto = 'Otomatik verilenler';
  static const _groups = [_groupFiles, _groupApp, _groupAuto];

  PermissionStatus? _status;
  bool _busy = false;
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sistem ayar ekranından dönüldüğünde durum tazelenir.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await PermissionService.check();
    if (!mounted) return;
    setState(() => _status = status);
  }

  /// Eylemi çalıştırır, dönen durumu ekrana yazar ve meşgul bayrağını sıfırlar.
  Future<void> _run(Future<PermissionStatus> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final status = await action();
    if (!mounted) return;
    setState(() {
      _status = status;
      _busy = false;
    });
  }

  /// Medya izni verilmişse değiştirmek için uygulama bilgisi sayfası;
  /// değilse çalışma zamanı istek diyaloğu açılır.
  Future<PermissionStatus> _mediaAction() async {
    if (_status?.media ?? false) {
      return PermissionService.openAppInfo();
    }
    return PermissionService.requestMediaPermissions();
  }

  /// İzin satırları (duruma göre izin verilen/değiştirilebilir hâle gelir).
  List<_Perm> _buildPerms(PermissionStatus s) {
    final allFilesOk = s.allFiles;
    final mediaOk = s.media || allFilesOk;
    return [
      _Perm(
        group: _groupFiles,
        icon: Icons.folder_special_rounded,
        title: 'Tüm dosyalara erişim',
        keywords: 'tüm tümü dosya storage manage depolama',
        description:
            'Dosyaları listelemek, kopyalamak, taşımak ve silmek için gereklidir.',
        technical: 'MANAGE_EXTERNAL_STORAGE',
        granted: allFilesOk,
        note: allFilesOk ? null : 'Zorunlu',
        onAction: () =>
            _run(() => PermissionService.requestAllFilesAccess()),
      ),
      _Perm(
        group: _groupFiles,
        icon: Icons.perm_media_rounded,
        title: 'Medya erişimi',
        keywords: 'resim görüntü fotoğraf video ses medya read_media',
        description: 'Görüntüler, Videolar ve Ses ekranlarının dosyaları '
            'görebilmesi için gereklidir.',
        technical: 'READ_MEDIA_IMAGES / VIDEO / AUDIO',
        granted: mediaOk,
        note: allFilesOk && !s.media ? 'Tüm dosyalara erişim ile kapsanıyor' : null,
        onAction: _mediaAction,
      ),
      _Perm(
        group: _groupApp,
        icon: Icons.bar_chart_rounded,
        title: 'Kullanım erişimi',
        keywords: 'kullanım verileri usage boyut uygulama boyutları stats',
        description: 'Uygulamalar ekranındaki tam boyutlar (uygulama + veri) '
            'gösterilebilmesi için gereklidir.',
        technical: 'PACKAGE_USAGE_STATS',
        granted: s.usage,
        onAction: () => _run(() => PermissionService.openUsageAccess()),
      ),
      _Perm(
        group: _groupApp,
        icon: Icons.system_update_alt_rounded,
        title: 'Bilinmeyen kaynaklardan kurulum',
        keywords: 'apk kurulum güncelle install bilinmeyen kaynak',
        description: 'İndirilen APK dosyalarının kur/güncelle ekranıyla '
            'açılabilmesi için gereklidir.',
        technical: 'REQUEST_INSTALL_PACKAGES',
        granted: s.install,
        onAction: () => _run(() => PermissionService.openInstallUnknownSources()),
      ),
      _Perm(
        group: _groupAuto,
        icon: Icons.apps_rounded,
        title: 'Uygulama listesi',
        keywords: 'uygulama liste query paket yüklü uygulamalar',
        description: 'Yüklü uygulamaları, ikonlarını ve boyutlarını '
            'görebilmek için kullanılır.',
        technical: 'QUERY_ALL_PACKAGES',
        granted: true,
        automatic: true,
      ),
      _Perm(
        group: _groupAuto,
        icon: Icons.wifi_rounded,
        title: 'Ağ erişimi',
        keywords: 'internet ağ wifi ftp smb webdav sftp bağlantı sunucu',
        description: 'FTP/SMB sunucusu ve uzak bağlantılar (FTP, SFTP, SMB, '
            'WebDAV) için gereklidir.',
        technical: 'INTERNET / ACCESS_NETWORK_STATE',
        granted: true,
        automatic: true,
      ),
    ];
  }

  void _continue() {
    context.read<SettingsProvider>().permissionsOnboarded = true;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _skip() {
    context.read<SettingsProvider>().permissionsOnboarded = true;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// Satır için buton metni: verilmemişse "İzin ver", verilmiş ve
  /// değiştirilebilirse "Ayarlar", otomatik izinde buton yoktur.
  static String? _actionLabel(_Perm p) {
    if (p.automatic || p.onAction == null) return null;
    return p.granted ? 'Ayarlar' : 'İzin ver';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    // Yönlendirme (ilk açılış) modu: geri gidecek yol yoktur.
    final onboard = !Navigator.of(context).canPop();

    return Scaffold(
      appBar: AppBar(title: const Text('İzinler')),
      body: SafeArea(
        child: status == null
            ? const Center(child: CircularProgressIndicator())
            : _buildList(theme, status, onboard),
      ),
    );
  }

  Widget _buildList(ThemeData theme, PermissionStatus status, bool onboard) {
    final allPerms = _buildPerms(status);
    final q = _query.trim().toLowerCase();
    bool matches(_Perm p) =>
        q.isEmpty ||
        p.title.toLowerCase().contains(q) ||
        p.technical.toLowerCase().contains(q) ||
        p.description.toLowerCase().contains(q) ||
        p.keywords.contains(q);
    final perms = allPerms.where(matches).toList(growable: false);
    final ready = status.ready;
    final restricted = !status.usage || !status.install;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Icon(Icons.shield_rounded, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 10),
        Text(
          'Uygulamanın çalışması için izinler',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Tüm erişim izinlerini burada görebilir, arayabilir ve her birini '
          'doğrudan değiştirebilirsiniz. İzinler yalnızca cihazınızda kalır.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        // Arama: kullanıcı aradığı izini hızla bulur.
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'İzin ara (örn. kullanım, kurulum, medya…)',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    tooltip: 'Temizle',
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                status.grantedCount == 4
                    ? Icons.check_circle_rounded
                    : Icons.tune_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              label: Text('${status.grantedCount} / 4 izin verildi'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Yenile'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final g in _groups) ...[
          if (perms.any((p) => p.group == g)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(
                g,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final p in perms.where((p) => p.group == g)) ...[
              _PermRow(perm: p, busy: _busy, label: _actionLabel(p)),
              const SizedBox(height: 10),
            ],
          ],
        ],
        if (perms.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Aramanızla eşleşen izin bulunamadı.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (restricted) ...[
          const SizedBox(height: 6),
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'İzin açılmıyorsa (MIUI / Android 13+ kısıtlı '
                          'ayarlar)',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '"Uygulama bilgisini aç" deyin, sağ üstteki ⋮ menüsünden '
                    '"Kısıtlı ayarlara izin ver" seçeneğini açın ve ilgili '
                    'izini yeniden deneyin.',
                    style: theme.textTheme.bodySmall,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() => PermissionService.openAppInfo()),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Uygulama bilgisini aç'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (onboard) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: ready ? _continue : null,
            icon: const Icon(Icons.check_rounded),
            label: Text(ready ? 'Devam et' : 'Devam etmek için izin ver'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _skip,
            child: const Text('Yine de devam et (sınırlı kullanım)'),
          ),
        ],
      ],
    );
  }
}

/// Tek bir izin satırı: ikon, ad + teknik ad, açıklama, durum ve eylem.
class _PermRow extends StatelessWidget {
  const _PermRow({
    required this.perm,
    required this.busy,
    required this.label,
  });

  final _Perm perm;
  final bool busy;

  /// Buton metni; null ise buton gösterilmez.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = perm.granted;
    final statusColor = perm.automatic
        ? Colors.blue.shade700
        : ok
            ? Colors.green
            : Colors.orange;
    final statusText =
        perm.automatic ? 'Otomatik verildi' : (ok ? 'İzin verildi' : 'Verilmedi');

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(perm.icon, size: 30, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    perm.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    perm.technical,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(perm.description, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        ok
                            ? Icons.check_circle_rounded
                            : Icons.error_outline,
                        size: 18,
                        color: statusColor,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          statusText,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: statusColor),
                        ),
                      ),
                      if (perm.note != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            perm.note!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (label != null)
              FilledButton.tonal(
                onPressed: busy ? null : () => perm.onAction!(),
                child: Text(label!),
              ),
          ],
        ),
      ),
    );
  }
}
