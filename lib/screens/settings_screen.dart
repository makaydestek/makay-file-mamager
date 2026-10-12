import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models/home_category.dart';
import '../providers/settings_provider.dart';
import '../screens/permissions_screen.dart';
import 'home_categories_screen.dart';
import '../services/platform_service.dart';
import '../services/update_service.dart';
import '../utils/formats.dart';
import '../widgets/appearance_picker.dart';
import '../widgets/update_dialog.dart';

/// Referans uygulamadaki Ayarlar ekranı.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        children: [
          _sectionHeader(context, 'Genel Ayarlar'),
          ListTile(
            title: const Text('Tema'),
            subtitle: Text(switch (settings.themeMode) {
              ThemeMode.system => 'Sistem',
              ThemeMode.light => 'Açık',
              ThemeMode.dark => 'Koyu',
            }),
            leading: const Icon(Icons.palette_rounded),
            onTap: () => _pickTheme(context, settings),
          ),
          ListTile(
            title: const Text('Görünüm'),
            subtitle: Text(
              '${settings.appearance.label} — ${settings.appearance.description}',
            ),
            leading: const Icon(Icons.style_rounded),
            onTap: () => _pickAppearance(context, settings),
          ),
          ListTile(
            title: const Text('Arayüz modu'),
            subtitle: Text(switch (settings.tvMode) {
              'tv' => 'TV (kumanda odaklı)',
              'phone' => 'Telefon / tablet',
              _ => 'Otomatik (TV algılanırsa TV arayüzü)',
            }),
            leading: const Icon(Icons.tv_rounded),
            onTap: () => _pickUiMode(context, settings),
          ),
          ListTile(
            title: const Text('Görünüm düzeni'),
            subtitle: Text(switch (settings.viewStyle) {
              'large' => 'Büyük kartlar (dikey 2 / yatay 3)',
              'medium' => 'Dengeli (dikey 3 / yatay 4)',
              'small' => 'Sıkışık (dikey 4 / yatay 6)',
              _ => 'Otomatik (cihaz genişliğine göre)',
            }),
            leading: const Icon(Icons.grid_view_rounded),
            onTap: () => _pickViewStyle(context, settings),
          ),
          ListTile(
            title: const Text('Ana ekran kartları'),
            subtitle: Text(
              'Görünmek istemediğiniz özellikleri gizleyin '
              '(${kHomeCategories.length - settings.hiddenHomeCategories.length}'
              ' / ${kHomeCategories.length} görünür)',
            ),
            leading: const Icon(Icons.visibility_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HomeCategoriesScreen()),
            ),
          ),
          SwitchListTile(
            title: const Text('Material You (sistem rengi)'),
            subtitle: const Text(
                'Android 12+ cihazlarda uygulama rengini sistemle eşleştir'),
            secondary: const Icon(Icons.format_color_fill_rounded),
            value: settings.dynamicColor,
            onChanged: (v) => settings.dynamicColor = v,
          ),
          ListTile(
            title: const Text('Kasa (gizli klasör)'),
            subtitle: const Text('PIN ile korunan şifreli dosyalar'),
            leading: const Icon(Icons.lock_outline_rounded),
            onTap: () => Navigator.of(context).pushNamed('/vault'),
          ),
          ListTile(
            title: const Text('USB / SD Kart'),
            subtitle: const Text('Bağlı harici depolama birimleri'),
            leading: const Icon(Icons.sd_card_rounded),
            onTap: () => Navigator.of(context).pushNamed('/usb'),
          ),
          ListTile(
            title: const Text('Mükerrer dosyalar'),
            subtitle: const Text('Aynı içeriğe sahip kopyaları bul'),
            leading: const Icon(Icons.copy_all_rounded),
            onTap: () => Navigator.of(context).pushNamed('/duplicates'),
          ),
          ListTile(
            title: const Text('İzinler'),
            subtitle: const Text('Dosya ve medya izinlerini yönet'),
            leading: const Icon(Icons.shield_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PermissionsScreen()),
            ),
          ),
          ListTile(
            title: const Text('Sürüm seçimini göster'),
            subtitle: const Text('Mobil-Tablet / TV seçim ekranı yeniden açılsın'),
            leading: const Icon(Icons.restart_alt_rounded),
            onTap: () {
              settings.deviceModeChosen = false;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Seçim ekranı açılışta yeniden gösterilecek'),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('Varsayılan uygulamalar'),
            subtitle: const Text('Dosya türleri için varsayılan uygulamalar'),
            leading: const Icon(Icons.open_in_new_rounded),
            onTap: () async {
              final ok = await PlatformService.openDefaultAppsSettings();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ayarlar açılamadı')),
                );
              }
            },
          ),
          ListTile(
            title: const Text('Dahili uygulamalar'),
            subtitle: const Text('Cihazla gelen (sistem) uygulamalar'),
            leading: const Icon(Icons.apps_rounded),
            onTap: () => Navigator.of(context).pushNamed('/apps/system'),
          ),
          const Divider(),
          _sectionHeader(context, 'Diğer ayarlar'),
          ListTile(
            title: const Text('Dosya boyutu birimi'),
            subtitle: Text(settings.sizeUnit),
            leading: const Icon(Icons.data_object_rounded),
            onTap: () => _pickSizeUnit(context, settings),
          ),
          ListTile(
            title: const Text('Tarih biçimi'),
            subtitle: Text(Formats.date(DateTime.now(),
                pattern: settings.datePattern)),
            leading: const Icon(Icons.event_rounded),
            onTap: () => _pickDateFormat(context, settings),
          ),
          const Divider(),
          _sectionHeader(context, 'Geçici dosyalar'),
          ListTile(
            title: const Text('Geçici dosyalar'),
            subtitle: const Text('Önbellek ve geçici dosyaları temizle'),
            leading: const Icon(Icons.cleaning_services_rounded),
            onTap: () => Navigator.of(context).pushNamed('/temp'),
          ),
          const Divider(),
          _sectionHeader(context, 'Geri Dönüşüm Kutusu Ayarları'),
          SwitchListTile(
            title: const Text('Varsayılan olarak geri dönüşüm kutusu'),
            subtitle: const Text('Silinen dosyaları kutuya taşı'),
            value: settings.recycleBinDefault,
            onChanged: (v) => settings.recycleBinDefault = v,
          ),
          SwitchListTile(
            title: const Text('Geri Dönüşüm onayını göster'),
            value: settings.recycleBinConfirm,
            onChanged: (v) => settings.recycleBinConfirm = v,
          ),
          const Divider(),
          _sectionHeader(context, 'Bildirim ayarları'),
          ListTile(
            title: const Text('Bellek dolu'),
            subtitle: Text(
                'Depolama alanı %${settings.storageWarnPercent} dolu olduğunda göster'),
            leading: const Icon(Icons.notifications_active_rounded),
            onTap: () => _pickWarnPercent(context, settings),
          ),
          const Divider(),
          _sectionHeader(context, 'Gelişmiş Ayarlar'),
          SwitchListTile(
            title: const Text('Nav icon simgesini (≡) her zaman göster'),
            value: settings.showNavIcon,
            onChanged: (v) => settings.showNavIcon = v,
          ),
          SwitchListTile(
            title: const Text('USB bağlantısını algıla'),
            value: settings.detectUsb,
            onChanged: (v) => settings.detectUsb = v,
          ),
          SwitchListTile(
            title: const Text('Sistem depolamasını göster'),
            value: settings.showSystemStorage,
            onChanged: (v) => settings.showSystemStorage = v,
          ),
          const Divider(),
          _sectionHeader(context, 'Gelişmiş menüleri göster'),
          _checkTile(context, 'Yer İmi Ekle', true),
          _checkTile(context, 'Ana Ekrana ekle', false),
          _checkTile(context, 'Gizle/Gizleme', false),
          _checkTile(context, 'Farklı aç', false),
          const Divider(),
          _sectionHeader(context, 'Hakkında'),
          ListTile(
            title: const Text('Sürüm'),
            subtitle: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) => Text(
                snapshot.hasData
                    ? '${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                    : '…',
              ),
            ),
            leading: const Icon(Icons.info_outline_rounded),
          ),
          ListTile(
            title: const Text('Güncelleme kontrolü'),
            subtitle: const Text('GitHub deposunda yeni sürüm var mı bak'),
            leading: const Icon(Icons.system_update_rounded),
            onTap: () => _checkUpdate(context),
          ),
          const ListTile(
            title: Text('Hakkında'),
            subtitle: Text(
                'Makay Dosya Yöneticisi • Reklamsız • Tüm özellikler ücretsiz'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static Widget _sectionHeader(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
      );

  static Widget _checkTile(BuildContext context, String title, bool value) =>
      CheckboxListTile(
        title: Text(title),
        value: value,
        controlAffinity: ListTileControlAffinity.trailing,
        onChanged: (_) {},
      );

  /// Elle güncelleme denetimi (A15): depoda yeni sürüm varsa diyaloğu açar.
  static Future<void> _checkUpdate(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Güncelleme kontrol ediliyor…')),
    );
    final info = await UpdateService.check();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yeni sürüm bulunamadı')),
      );
    } else {
      await showUpdateDialog(context, info);
    }
  }

  /// Görünüm (görsel preset) seçimi: yazı, ikon, köşe ve arka plan birlikte.
  static Future<void> _pickAppearance(
      BuildContext context, SettingsProvider settings) async {
    final appearance = await showAppearanceDialog(
      context,
      selected: settings.appearance,
    );
    if (appearance != null) settings.appearance = appearance;
  }

  static Future<void> _pickTheme(
      BuildContext context, SettingsProvider settings) async {
    final mode = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Tema seçin'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (v) {
              if (v != null) Navigator.of(context).pop(v);
            },
            child: Column(
              children: [
                for (final m in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    title: Text(switch (m) {
                      ThemeMode.system => 'Sistem',
                      ThemeMode.light => 'Açık',
                      ThemeMode.dark => 'Koyu',
                    }),
                    value: m,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (mode != null) settings.themeMode = mode;
  }

  static Future<void> _pickUiMode(
      BuildContext context, SettingsProvider settings) async {
    const labels = {
      'auto': 'Otomatik (TV algılanırsa TV arayüzü)',
      'tv': 'TV (kumanda odaklı büyük kartlar)',
      'phone': 'Telefon / tablet',
    };
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Arayüz modu'),
        children: [
          RadioGroup<String>(
            groupValue: settings.tvMode,
            onChanged: (v) {
              if (v != null) Navigator.of(context).pop(v);
            },
            child: Column(
              children: [
                for (final m in labels.entries)
                  RadioListTile<String>(
                    title: Text(m.value),
                    value: m.key,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (mode != null) settings.tvMode = mode;
  }

  /// Görünüm düzeni seçimi: dikey/yatay sütun sayısı.
  static Future<void> _pickViewStyle(
      BuildContext context, SettingsProvider settings) async {
    const labels = <String, String>{
      'auto': 'Otomatik (cihaz genişliğine göre)',
      'large': 'Büyük kartlar — dikey 2 / yatay 3',
      'medium': 'Dengeli — dikey 3 / yatay 4',
      'small': 'Sıkışık — dikey 4 / yatay 6',
    };
    final style = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Görünüm düzeni'),
        children: [
          RadioGroup<String>(
            groupValue: settings.viewStyle,
            onChanged: (v) {
              if (v != null) Navigator.of(context).pop(v);
            },
            child: Column(
              children: [
                for (final m in labels.entries)
                  RadioListTile<String>(
                    title: Text(m.value),
                    value: m.key,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (style != null) settings.viewStyle = style;
  }

  static Future<void> _pickSizeUnit(
      BuildContext context, SettingsProvider settings) async {
    const units = ['B', 'KB', 'MB', 'GB'];
    final unit = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Dosya boyutu birimi'),
        children: [
          RadioGroup<String>(
            groupValue: settings.sizeUnit,
            onChanged: (v) {
              if (v != null) Navigator.of(context).pop(v);
            },
            child: Column(
              children: [
                for (final u in units)
                  RadioListTile<String>(title: Text(u), value: u),
              ],
            ),
          ),
        ],
      ),
    );
    if (unit != null) settings.sizeUnit = unit;
  }

  static Future<void> _pickDateFormat(
      BuildContext context, SettingsProvider settings) async {
    final pattern = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Tarih biçimi'),
        children: [
          RadioGroup<String>(
            groupValue: settings.datePattern,
            onChanged: (v) {
              if (v != null) Navigator.of(context).pop(v);
            },
            child: Column(
              children: [
                for (final p in Formats.datePatterns)
                  RadioListTile<String>(
                    title: Text(p.label),
                    value: p.pattern,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (pattern != null) settings.datePattern = pattern;
  }

  static Future<void> _pickWarnPercent(
      BuildContext context, SettingsProvider settings) async {
    final value = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Uyarı eşiği'),
        children: [
          RadioGroup<int>(
            groupValue: settings.storageWarnPercent,
            onChanged: (v) {
              if (v != null) Navigator.of(context).pop(v);
            },
            child: Column(
              children: [
                for (final p in [80, 85, 90, 95, 98, 99])
                  RadioListTile<int>(title: Text('%$p'), value: p),
              ],
            ),
          ),
        ],
      ),
    );
    if (value != null) settings.storageWarnPercent = value;
  }
}
