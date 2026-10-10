import 'package:flutter/material.dart';

import '../models/home_category.dart';
import '../widgets/app_drawer.dart';

/// TV'ye özel ana ekran: odaklı büyük kart ızgarası, kumanda (D-pad)
/// ipuçları ve uzak tutma (overscan) güvenli kenar boşlukları.
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  int _focusedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Makay Dosya Yöneticisi'),
        actions: [
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_rounded, size: 30),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          // Odaklanan kartın adı büyük gösterilir.
          SizedBox(
            height: 40,
            child: Center(
              child: Text(
                kHomeCategories[_focusedIndex].title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 1200 ? 5 : 4;
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 48, vertical: 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: kHomeCategories.length,
                  itemBuilder: (context, index) => _TvCategoryCard(
                    category: kHomeCategories[index],
                    autofocus: index == 0,
                    onFocus: (focused) {
                      if (focused && mounted) {
                        setState(() => _focusedIndex = index);
                      }
                    },
                  ),
                );
              },
            ),
          ),
          // Kumanda ipuçları şeridi.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  _KeyHint(icon: Icons.gamepad_rounded, label: 'Gezin'),
                  SizedBox(width: 24),
                  _KeyHint(
                      icon: Icons.radio_button_checked_rounded, label: 'Aç'),
                  SizedBox(width: 24),
                  _KeyHint(icon: Icons.arrow_back_rounded, label: 'Geri'),
                  SizedBox(width: 24),
                  _KeyHint(icon: Icons.menu_rounded, label: 'Menü'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 6),
        Text(label, style: style?.copyWith(color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}

class _TvCategoryCard extends StatefulWidget {
  const _TvCategoryCard({
    required this.category,
    required this.onFocus,
    this.autofocus = false,
  });

  final HomeCategory category;
  final ValueChanged<bool> onFocus;
  final bool autofocus;

  @override
  State<_TvCategoryCard> createState() => _TvCategoryCardState();
}

class _TvCategoryCardState extends State<_TvCategoryCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        widget.onFocus(focused);
      },
      child: GestureDetector(
        onTap: _open,
        child: AnimatedScale(
          scale: _focused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              color: _focused
                  ? widget.category.color.withValues(alpha: 0.18)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _focused ? widget.category.color : Colors.transparent,
                width: 3,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: widget.category.color.withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.category.icon, size: 64,
                    color: widget.category.color),
                const SizedBox(height: 16),
                Text(
                  widget.category.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: _focused ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open() {
    final route = widget.category.route;
    if (route != null) {
      Navigator.of(context).pushNamed(route);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.category.title} TV\'de açılıyor…')),
      );
    }
  }
}
