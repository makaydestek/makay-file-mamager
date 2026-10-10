import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

/// İlk açılıştaki sürüm seçim ekranı (Mobil-Tablet / TV).
///
/// Kullanıcı seçimini yaptığında [SettingsProvider.applyDeviceMode] ile
/// gerekli ayarlar (arayüz modu, TV için koyu tema) otomatik uygulanır ve
/// seçim ekranı bir daha gösterilmez; ana ekran seçime göre gelir.
class DeviceModeScreen extends StatelessWidget {
  const DeviceModeScreen({super.key});

  Future<void> _pick(BuildContext context, String mode, bool isTv) async {
    final settings = context.read<SettingsProvider>();
    settings.applyDeviceMode(mode);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isTv
            ? 'TV sürümü etkin — kumanda odaklı arayüz'
            : 'Mobil-Tablet sürümü etkin — dokunmatik arayüz'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_rounded,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Makay Dosya Yöneticisi',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kullanım şeklinizi seçin',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final phone = _ModeCard(
                        icon: Icons.smartphone_rounded,
                        title: 'Mobil-Tablet Sürümü',
                        subtitle: 'Telefon ve tablet için dokunmatik arayüz',
                        bullets: const [
                          'Klasik ana ekran ve çekmece menü',
                          'Dokunmatik gezinme',
                          'Tüm özellikler ücretsiz',
                        ],
                        onTap: () => _pick(context, 'phone', false),
                      );
                      final tv = _ModeCard(
                        icon: Icons.tv_rounded,
                        title: 'TV Sürümü',
                        subtitle: 'Android TV için kumanda odaklı arayüz',
                        bullets: const [
                          'Büyük odaklı kart arayüzü',
                          'Kumanda (D-pad) ile gezinme',
                          'Uzak tutma güvenli kenar boşlukları',
                          'Otomatik koyu tema',
                        ],
                        autofocus: false,
                        onTap: () => _pick(context, 'tv', true),
                      );
                      // Geniş ekran/TV: iki kart yan yana, eşit yüksek.
                      if (constraints.maxWidth >= 700) {
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: phone),
                              const SizedBox(width: 16),
                              Expanded(child: tv),
                            ],
                          ),
                        );
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          phone,
                          const SizedBox(height: 12),
                          tv,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Seçim ayarlar otomatik olarak uygulanır ve daha sonra '
                    'Ayarlar → Arayüz modu bölümünden değiştirilebilir.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        autofocus: autofocus,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final b in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(b, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
