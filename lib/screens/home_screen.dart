import 'package:flutter/material.dart';

import '../models/home_category.dart';
import '../widgets/app_drawer.dart';

/// Uygulama ana ekranı: referans uygulamadaki kategori ızgarası.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Makay Dosya Yöneticisi'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  Navigator.of(context).pushNamed('/settings');
                case 'analysis':
                  Navigator.of(context).pushNamed('/analysis');
                case 'refresh':
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Yenilendi')),
                  );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'settings', child: Text('Ayarlar')),
              PopupMenuItem(value: 'analysis', child: Text('Analiz et')),
              PopupMenuItem(value: 'refresh', child: Text('Yenile')),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Telefon: 3 sütun; tablet/TV: genişliğe göre daha fazla sütun.
          final columns = switch (constraints.maxWidth) {
            > 1000 => 5,
            > 600 => 4,
            _ => 3,
          };
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.88,
            ),
            itemCount: kHomeCategories.length,
            itemBuilder: (context, index) =>
                _CategoryTile(category: kHomeCategories[index]),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});

  final HomeCategory category;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final route = category.route;
          if (route != null) {
            Navigator.of(context).pushNamed(route);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(6),
          // Kart içeriği taşmasın: sığmazsa hafifçe küçülür.
          child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(category.icon, size: 28, color: category.color),
                ),
                const SizedBox(height: 8),
                Text(
                  category.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                ),
                if (category.id == 'internal') ...[
                  const SizedBox(height: 2),
                  Text(
                    'Depolama alanı',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          height: 1.1,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
