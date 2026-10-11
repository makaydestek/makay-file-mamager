import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/home_category.dart';
import '../providers/settings_provider.dart';

/// Ana ekran kartlarını göster/gizleme ekranı.
///
/// Kullanıcı istemediği özellikleri (örn. "Kasa", "USB / SD") ana ekrandan
/// kaldırabilir. Gizleme yalnızca **ana ekran ızgarasını** etkiler; çekmece,
/// ayarlar ve rotalar olduğu gibi kalır, yani özelliğe erişim kaybolmaz.
class HomeCategoriesScreen extends StatelessWidget {
  const HomeCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final hidden = settings.hiddenHomeCategories;
    final hiddenCount = hidden.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ana Ekran Kartları'),
        actions: [
          if (hiddenCount > 0)
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded),
              tooltip: 'Tümünü göster',
              onPressed: () {
                settings.resetHiddenHomeCategories();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tüm kartlar yeniden gösteriliyor')),
                );
              },
            ),
        ],
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Kapatılan kartlar ana ekranda görünmez. '
              'Çekmece ve ayarlardan erişmeye devam edebilirsin.',
              style: TextStyle(height: 1.35),
            ),
          ),
          for (final c in kHomeCategories)
            SwitchListTile(
              value: settings.isCategoryVisible(c.id),
              secondary: Icon(c.icon, color: c.color),
              title: Text(c.title),
              subtitle: Text(
                settings.isCategoryVisible(c.id) ? 'Görünür' : 'Gizli',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onChanged: (v) => settings.setCategoryVisible(c.id, v),
            ),
          if (hiddenCount == kHomeCategories.length)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Tüm kartlar gizlendi — ana ekran boş görünecek.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}