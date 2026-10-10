import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/platform_service.dart';
import '../services/update_service.dart';
import '../utils/formats.dart';
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
