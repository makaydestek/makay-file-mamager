import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/home_category.dart';
import '../providers/settings_provider.dart';
import '../services/category_size_service.dart';
import '../widgets/app_drawer.dart';

/// Uygulama ana ekranı: referans uygulamadaki kategori ızgarası.
///
/// Her kategori başlığının altında içeriğin toplam boyutu (veya kayıt
/// sayısı) gösterilir; değerler arka planda hesaplanır ve önbelleklenir.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Kategori boyutları arka planda hesaplanır; önbellek varsa anında görünür.
    CategorySizeService.refresh();
  }

  Future<void> _refresh({bool force = false}) =>
      CategorySizeService.refresh(force: force);

  /// Seçili görünüm düzenine göre sütun sayısı.
  ///
  /// `auto` modu cihaz genişliğine göre davranır; diğerleri kullanıcının
  /// seçtiği dikey/yatay sütun sayılarını uygular.
  static int _columnsFor(String viewStyle, BoxConstraints constraints) {
    if (viewStyle != 'auto') {
      final portrait = constraints.maxHeight >= constraints.maxWidth;
      return switch (viewStyle) {
        'large' => portrait ? 2 : 3,
        'medium' => portrait ? 3 : 4,
        'small' => portrait ? 4 : 6,
        _ => 3,
      };
    }
    // Otomatik: geniş telefon → 3, tablet → 4, çok geniş → 5 sütun.
    return switch (constraints.maxWidth) {
      > 1000 => 5,
      > 600 => 4,
      _ => 3,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Ayar değiştiğinde ızgara anında yeniden kurulur (watch → rebuild).
    final viewStyle = context.watch<SettingsProvider>().viewStyle;
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
                  _refresh(force: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Boyutlar yenileniyor…')),
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
          final columns = _columnsFor(viewStyle, constraints);
          return RefreshIndicator(
            onRefresh: () => _refresh(force: true),
            child: ValueListenableBuilder<Map<String, String>>(
              valueListenable: CategorySizeService.labels,
              builder: (context, sizes, _) => GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.88,
                ),
                itemCount: kHomeCategories.length,
                itemBuilder: (context, index) => _CategoryTile(
                  category: kHomeCategories[index],
                  label: sizes[kHomeCategories[index].id],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, this.label});

  final HomeCategory category;

  /// Başlık altındaki özet metin (ör. "1,5 GB"); null ise gösterilmez.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          height: 1.1,
          color: Theme.of(context).colorScheme.outline,
        );
    // Yüklenirken ana bellek için yer tutucu metin.
    final fallback = category.id == 'internal' ? 'Depolama alanı' : null;
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
                if (label != null || fallback != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    label ?? fallback!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
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
