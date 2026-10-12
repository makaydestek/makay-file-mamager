import 'package:flutter/material.dart';

import '../theme/app_appearance.dart';
import '../theme/app_theme.dart';

/// Görünüm preset'i seçim diyaloğu.
///
/// Her seçenek; adı, açıklaması ve **canlı bir önizlemesiyle** (kart rengi,
/// köşe yuvarlaklığı, ikon stili ve yazı karakteri) sunulur — kullanıcı
/// seçmeden önce görünümü örnekte görebilir.
///
/// Seçilen görünüm `null` yerine [AppAppearance] olarak döner; çağıran
/// taraf kalıcılaştırmayı kendisi yapar (ör. `SettingsProvider.appearance`).
Future<AppAppearance?> showAppearanceDialog(
  BuildContext context, {
  required AppAppearance selected,
}) {
  return showDialog<AppAppearance>(
    context: context,
    builder: (context) => AppearancePickerDialog(selected: selected),
  );
}

/// İçerik: radyo gruplu preset listesi, her satırda mini önizleme.
class AppearancePickerDialog extends StatelessWidget {
  const AppearancePickerDialog({super.key, required this.selected});

  final AppAppearance selected;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Görünüm seçin'),
      children: [
        RadioGroup<AppAppearance>(
          groupValue: selected,
          onChanged: (v) {
            if (v != null) Navigator.of(context).pop(v);
          },
          child: Column(
            children: [
              for (final appearance in AppAppearance.values)
                RadioListTile<AppAppearance>(
                  value: appearance,
                  secondary: _AppearanceThumb(appearance: appearance),
                  title: Text(appearance.label),
                  subtitle: Text(
                    appearance.description,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
          child: Text(
            'Görünüm; yazı, ikon, köşe ve arka planı birlikte değiştirir. '
            'Aydınlık/karanlık tercihi ayrı bir seçimdir (Tema) ve korunur.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
        // SimpleDialog `actions` kabul etmez; kapatma yolu children'a girer.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
        ),
      ],
    );
  }
}

/// Bir görünümün küçük canlı örneği: zemin + kart + ikon + yazı.
///
/// Önizleme gerçek tema değerlerinden üretilir (`AppTheme.forAppearance`),
/// yani listede görülen, uygulamada görülecek olandır.
class _AppearanceThumb extends StatelessWidget {
  const _AppearanceThumb({required this.appearance});

  final AppAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final preview = AppTheme.forAppearance(appearance, brightness);
    final gradient = AppTheme.backgroundGradient(appearance, brightness);
    final shape = preview.cardTheme.shape;
    final cardRadius = shape is RoundedRectangleBorder
        ? shape.borderRadius.resolve(TextDirection.ltr)
        : BorderRadius.circular(appearance.cornerRadius);
    return Container(
      width: 60,
      height: 46,
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? preview.scaffoldBackgroundColor : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: preview.cardTheme.color,
            borderRadius: cardRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_rounded,
                size: (preview.iconTheme.size ?? 20) * 0.6,
                fill: preview.iconTheme.fill,
                weight: preview.iconTheme.weight,
                opticalSize: preview.iconTheme.opticalSize,
                color: preview.colorScheme.primary,
              ),
              const SizedBox(width: 3),
              // Flexible: dar satırda taşma (RenderFlex) hatası vermesin.
              Flexible(
                child: Text(
                  'Aa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: preview.textTheme.labelSmall?.copyWith(
                    color: preview.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
