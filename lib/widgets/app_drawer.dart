import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Referans uygulamadaki yan çekmece (drawer) menüsü.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

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
                  _DrawerItem(
                    icon: Icons.storage_rounded,
                    title: 'Ana bellek',
                    trailing: const Text('%9'),
                    onTap: () =>
                        Navigator.of(context).pushNamed('/browse/internal'),
                  ),
                  const Divider(),
                  _DrawerItem(
                    icon: Icons.delete_sweep_rounded,
                    title: 'Geri Dönüşüm Kutusu',
                    trailing: const Text('0 B'),
                    onTap: () => Navigator.of(context).pushNamed('/recycle'),
                  ),
                  const Divider(),
                  _DrawerItem(
                    icon: Icons.schedule_rounded,
                    title: 'Yeni Dosyalar',
                    onTap: () => Navigator.of(context).pushNamed('/browse/recent'),
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
                    title: 'Görüntüler',
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
