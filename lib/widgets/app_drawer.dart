import 'package:flutter/material.dart';

import '../services/category_size_service.dart';
import '../services/recycle_bin_service.dart';
import '../theme/app_theme.dart';
import '../utils/formats.dart';

/// Referans uygulamadaki yan çekmece (drawer) menüsü.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  int _recycleSize = 0;

  @override
  void initState() {
    super.initState();
    _loadRecycle();
  }

  Future<void> _loadRecycle() async {
    try {
      await RecycleBinService.instance.load();
      final total = RecycleBinService.instance.totalSize;
      if (mounted) setState(() => _recycleSize = total);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerItem(
                    icon: Icons.home_rounded,
                    title: 'Ana Ekran',
                    onTap: () =>
                        Navigator.of(context).pushReplacementNamed('/'),
                  ),
                  // Ana bellek: kullanılan/toplam değerini arka planda gelir.
                  ValueListenableBuilder<Map<String, String>>(
                    valueListenable: CategorySizeService.labels,
                    builder: (context, sizes, _) => _DrawerItem(
                      icon: Icons.storage_rounded,
                      title: 'Ana bellek',
                      trailing: sizes['internal'] == null
                          ? null
                          : Text(sizes['internal']!),
                      onTap: () =>
                          Navigator.of(context).pushNamed('/browse/internal'),
                    ),
                  ),
                  const Divider(),
                  _DrawerItem(
                    icon: Icons.delete_sweep_rounded,
                    title: 'Geri Dönüşüm Kutusu',
                    trailing: Text(Formats.size(_recycleSize)),
                    onTap: () => Navigator.of(context).pushNamed('/recycle'),
                  ),
                  const Divider(),
                  _DrawerItem(
                    icon: Icons.schedule_rounded,
                    title: 'Yeni Dosyalar',
                    onTap: () => Navigator.of(context).pushNamed('/recent'),
                  ),
                  _DrawerItem(
                    icon: Icons.description_rounded,
                    title: 'Belgeler',
                    onTap: () =>
                        Navigator.of(context).pushNamed('/browse/documents'),
                  ),
                  _DrawerItem(
                    icon: Icons.video_library_rounded,
                    title: 'Videolar',
                    onTap: () => Navigator.of(context).pushNamed('/browse/videos'),
                  ),
                  _DrawerItem(
                    icon: Icons.music_note_rounded,
                    title: 'Ses',
                    onTap: () => Navigator.of(context).pushNamed('/browse/audio'),
                  ),
                  _DrawerItem(
                    icon: Icons.image_rounded,
                    title: 'Resimler',
                    onTap: () =>
                        Navigator.of(context).pushNamed('/browse/images'),
                  ),
                  _DrawerItem(
                    icon: Icons.folder_zip_rounded,
                    title: 'İndirilenler',
                    onTap: () =>
                        Navigator.of(context).pushNamed('/browse/downloads'),
                  ),
                  const Divider(),
                  _DrawerItem(
                    icon: Icons.lock_outline_rounded,
                    title: 'Kasa',
                    onTap: () => Navigator.of(context).pushNamed('/vault'),
                  ),
                  _DrawerItem(
                    icon: Icons.sd_card_rounded,
                    title: 'USB / SD Kart',
                    onTap: () => Navigator.of(context).pushNamed('/usb'),
                  ),
                  _DrawerItem(
                    icon: Icons.copy_all_rounded,
                    title: 'Mükerrer dosyalar',
                    onTap: () =>
                        Navigator.of(context).pushNamed('/duplicates'),
                  ),
                  const Divider(),
                  _DrawerItem(
                    icon: Icons.desktop_windows_rounded,
                    title: 'Uzak',
                    onTap: () => Navigator.of(context).pushNamed('/remote'),
                  ),
                  _DrawerItem(
                    icon: Icons.devices_rounded,
                    title: 'Ağdan erişim',
                    onTap: () => Navigator.of(context).pushNamed('/network'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Alt bilgi: uygulama künyesi (reklamsız, tüm özellikler ücretsiz).
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Makay Dosya Yöneticisi\nReklamsız • Tüm özellikler ücretsiz',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.accent,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
