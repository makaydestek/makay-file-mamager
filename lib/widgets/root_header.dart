import 'package:flutter/material.dart';

import '../services/platform_service.dart';

/// Klasör gezinme başlığı (referans uygulamadaki "Ana bellek" üst satırı):
///
/// solda **ana simge > klasör simgesi** yol göstergesi, sağda **kullanım
/// rozeti** ("KULLANILAN %9"). Rozet tıklanınca Bellek Analizi ekranı açılır,
/// ana simge tıklanınca uygulamanın ilk (ana) ekranına dönülür.
///
/// Yalnızca kök seviyedeki tarayıcı ekranlarında gösterilir (bkz.
/// `BrowserScreen.showRootDrawer`); iç içe klasör gezinmesinde geri ok
/// bulunacağı için bu satıra gerek yoktur.
class RootHeader extends StatefulWidget {
  const RootHeader({super.key});

  @override
  State<RootHeader> createState() => _RootHeaderState();
}

class _RootHeaderState extends State<RootHeader> {
  /// Kullanım yüzdesi (null → cihaz bilgisi alınamadı; rozet gizlenir).
  int? _usedPercent;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final info = await PlatformService.storageInfo();
    if (!mounted || info == null || info.total <= 0) return;
    final used = info.total - info.free;
    setState(() => _usedPercent = (used / info.total * 100).round());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 4, right: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.home_rounded,
                size: 22, color: theme.colorScheme.primary),
            tooltip: 'Ana ekran',
            // Taşma menüsündeki "Ana ekrana dön" ile aynı davranış.
            onPressed: () =>
                Navigator.of(context).popUntil((r) => r.isFirst),
            visualDensity: VisualDensity.compact,
          ),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: theme.colorScheme.outline),
          Icon(Icons.folder_rounded,
              size: 20, color: theme.colorScheme.outline),
          const Spacer(),
          if (_usedPercent != null) _usageBadge(context),
        ],
      ),
    );
  }

  /// "● KULLANILAN %9" rozeti — Bellek Analizi'ne kısayol.
  Widget _usageBadge(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).pushNamed('/analysis'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 12, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'KULLANILAN %$_usedPercent',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
