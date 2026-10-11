import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formats.dart';

/// Squarified treemap için tek bir öğe (kategori/dosya grubu).
class TreemapItem {
  const TreemapItem({
    required this.label,
    required this.size,
    this.color = Colors.transparent,
  });

  /// Karo üzerinde gösterilen etiket (örn. "Belgeler").
  final String label;

  /// Boyut (bayt); negatif olamaz.
  final int size;

  /// Dolgu rengi. [Colors.transparent] verilirse görünüm, öğenin sırasına
  /// göre [TreemapView] içindeki kategori paletinden bir renk atar.
  final Color color;
}

/// Squarified treemap yerleşimi (Bruls vd., "Squarified Treemap: An
/// Improved Treemapping Algorithm").
///
/// [areas] içindeki değerler, [rect] alanına ölçeklenir; böylece üretilen
/// dikdörtgenlerin toplam alanı her zaman `rect.width * rect.height` olur.
/// Algoritma sırasında öğeler alana göre **azalan** sırayla işlenir, ancak
/// çıktı listesi girdi sırasını korur: `result[i]`, `areas[i]` öğesinin
/// dikdörtgenidir.
///
/// En-boy oranı 1'e en yakın kareye yakın karolar üretmek için kısa kenara
/// boyunca "satır"lar doldurulur; satıra yeni öğe eklemenin oranı bozup
/// bozmadığı `_worstRatio` ile sınanır.
@visibleForTesting
List<Rect> squarify(List<double> areas, Rect rect) {
  final count = areas.length;
  if (count == 0) return const [];

  final rectArea = rect.width * rect.height;
  var inputTotal = 0.0;
  for (final area in areas) {
    if (area.isFinite && area > 0) inputTotal += area;
  }

  // Yerleşim yapılamazsa (toplam 0 veya geçersiz dikdörtgen) tüm öğelere
  // sıfır boyutlu, köşede kalmış dikdörtgenler verilir.
  if (inputTotal <= 0 || !rectArea.isFinite || rectArea <= 0) {
    return List<Rect>.filled(count, Rect.fromLTWH(rect.left, rect.top, 0, 0));
  }

  final factor = rectArea / inputTotal;
  final scaled = <double>[
    for (final area in areas) (area.isFinite && area > 0) ? area * factor : 0,
  ];

  // Alanı sıfır olanlar satıra alınmaz (oran hesabı bölme hatasına düşer);
  // bunlar zaten sıfır boyutlu dikdörtgenle eşlenmiştir.
  final pending = <int>[
    for (var i = 0; i < count; i++)
      if (scaled[i] > 0) i,
  ]..sort((a, b) => scaled[b].compareTo(scaled[a]));

  final result = List<Rect>.filled(
    count,
    Rect.fromLTWH(rect.left, rect.top, 0, 0),
  );

  var current = rect;
  while (pending.isNotEmpty) {
    if (current.width <= 0 || current.height <= 0) break;

    // Satır, dikdörtgenin kısa kenarı boyunca yerleştirilir.
    final side = math.min(current.width, current.height);
    final row = <int>[];
    var rowArea = 0.0;
    var rowMax = 0.0;
    var rowMin = double.infinity;

    while (pending.isNotEmpty) {
      final index = pending.first;
      final area = scaled[index];
      if (row.isEmpty) {
        row.add(pending.removeAt(0));
        rowArea = area;
        rowMax = area;
        rowMin = area;
        continue;
      }
      final candidateArea = rowArea + area;
      // Yeni öğe satırın en-boy dengesini bozmadığı sürece satıra eklenir.
      final stillBalanced =
          _worstRatio(
            candidateArea,
            math.max(rowMax, area),
            math.min(rowMin, area),
            side,
          ) <=
          _worstRatio(rowArea, rowMax, rowMin, side);
      if (!stillBalanced) break;
      row.add(pending.removeAt(0));
      rowArea = candidateArea;
      rowMax = math.max(rowMax, area);
      rowMin = math.min(rowMin, area);
    }

    if (current.width <= current.height) {
      // Yatay şerit: tam genişlik, üstten aşağı doğru ilerler.
      final thickness = rowArea / current.width;
      var x = current.left;
      for (final index in row) {
        final w = thickness > 0 ? scaled[index] / thickness : 0.0;
        result[index] = Rect.fromLTWH(x, current.top, w, thickness);
        x += w;
      }
      current = Rect.fromLTWH(
        current.left,
        current.top + thickness,
        current.width,
        current.height - thickness,
      );
    } else {
      // Dikey şerit: tam yükseklik, soldan sağa ilerler.
      final thickness = rowArea / current.height;
      var y = current.top;
      for (final index in row) {
        final h = thickness > 0 ? scaled[index] / thickness : 0.0;
        result[index] = Rect.fromLTWH(current.left, y, thickness, h);
        y += h;
      }
      current = Rect.fromLTWH(
        current.left + thickness,
        current.top,
        current.width - thickness,
        current.height,
      );
    }
  }

  return result;
}

/// Satırın ürettiği en kötü en-boy oranı (Bruls vd. 2.2 denklemi).
///
/// [rowArea] satırın toplam alanı, [rowMax]/[rowMin] satırdaki en büyük ve
/// en küçük öğe alanı, [side] satırın boyunca yerleştiği kenar uzunluğudur.
double _worstRatio(double rowArea, double rowMax, double rowMin, double side) {
  if (rowArea <= 0 || rowMin <= 0 || side <= 0) return double.infinity;
  final areaSquared = rowArea * rowArea;
  final sideSquared = side * side;
  final stretched = sideSquared * rowMax / areaSquared;
  final shrunk = areaSquared / (sideSquared * rowMin);
  return math.max(stretched, shrunk);
}

/// Görsel depolama analizi için squarified treemap görünümü.
///
/// [items] toplam boyutuna göre alan paylaştırılır ve her öğe, oranı 1'e
/// yakın dikdörtgenlere bölünmüş bir karo olarak çizilir. Karolar
/// dokunmatiktir; dokunma olayında ilgili [TreemapItem] [onTap] ile
/// geri çağrılır.
class TreemapView extends StatelessWidget {
  const TreemapView({
    super.key,
    required this.items,
    this.onTap,
    this.height = 280,
  });

  /// Görselde gösterilecek öğeler (boş bırakılabilir).
  final List<TreemapItem> items;

  /// Bir karoya dokunulduğunda çağrılır; `null` ise dokunma kapalıdır.
  final ValueChanged<TreemapItem>? onTap;

  /// Görünümün yüksekliği (varsayılan 280).
  final double height;

  @override
  Widget build(BuildContext context) {
    var total = 0;
    for (final item in items) {
      if (item.size > 0) total += item.size;
    }
    if (items.isEmpty || total <= 0) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('Veri yok')),
      );
    }

    final palette = _categoryColors(context);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          // Sınırsız (ör. sütun içinde) veya boş alanda yerleşim yapılmaz.
          if (!size.isFinite || size.isEmpty) {
            return const Center(child: Text('Veri yok'));
          }

          final rect = Offset.zero & size;
          final totalArea = rect.width * rect.height;
          final areas = <double>[
            for (final item in items)
              item.size > 0 ? item.size / total * totalArea : 0,
          ];
          final rects = squarify(areas, rect);

          return Stack(
            children: [
              for (var i = 0; i < items.length; i++)
                _buildTile(items[i], itemColor(items[i], palette, i), rects[i]),
            ],
          );
        },
      ),
    );
  }

  /// Verilen karo için [Positioned] + [GestureDetector] ağacını kurar.
  Widget _buildTile(TreemapItem item, Color fill, Rect rect) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        onTap: onTap == null ? null : () => onTap!(item),
        child: ColoredBox(color: fill, child: _tileLabel(fill, item, rect)),
      ),
    );
  }

  /// Karonun dolgu rengi: öğe rengi verilmemişse paletten atanır.
  static Color itemColor(TreemapItem item, List<Color> palette, int index) {
    if (item.color != Colors.transparent) return item.color;
    return palette[index % palette.length];
  }

  /// Karo üzerindeki etiket: `Etiket • Boyut`.
  ///
  /// Karo çok küçükse (`< 24px`) metin üretilmez; `FittedBox` metni karoya
  /// sığdıracak biçimde ölçekler, taşma olmaz.
  Widget? _tileLabel(Color fill, TreemapItem item, Rect tile) {
    if (tile.width < 24 || tile.height < 24) return null;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          '${item.label} • ${Formats.size(item.size)}',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _readableOn(fill),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Zemin rengine göre okunur metin rengi seçer (basit luminance kontrolü):
  /// koyu zeminde beyaz, açık zeminde siyah.
  static Color _readableOn(Color background) {
    final luminance = background.computeLuminance();
    // Kontrast oranları karşılaştırılır; hangisi büyükse o renk kullanılır.
    final whiteContrast = 1.05 / (luminance + 0.05);
    final blackContrast = (luminance + 0.05) / 0.05;
    return whiteContrast >= blackContrast ? Colors.white : Colors.black87;
  }

  /// Kategori paleti: `AppTheme.accent` tabanlı tonlar ve renk çemberinde
  /// komşu tonlar. Koyu/açık temada açıklık ve saçlık ayarlanır, böylece
  /// her iki temada da metin okunur kalır.
  static List<Color> _categoryColors(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final base = HSLColor.fromColor(
      Color.lerp(AppTheme.accent, scheme.primary, 0.5)!,
    );
    // Renk çemberindeki kaydırmalar (derece) ve açıklık farkları.
    const shifts = <double>[0, 34, -34, 70, 150, 210, 275, 320];
    const lightnessOffsets = <double>[
      -0.16,
      0,
      0.06,
      -0.08,
      0.03,
      0.08,
      0.26,
      -0.04,
    ];
    final saturation = isDark ? 0.50 : 0.58;
    final lightness = isDark ? 0.51 : 0.45;
    return [
      for (var i = 0; i < shifts.length; i++)
        HSLColor.fromAHSL(
          1,
          (base.hue + shifts[i] + 360) % 360,
          saturation,
          (lightness + lightnessOffsets[i]).clamp(0.12, 0.90).toDouble(),
        ).toColor(),
    ];
  }
}
