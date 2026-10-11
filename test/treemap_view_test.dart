import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/widgets/treemap_view.dart';

/// [Rect] alanı (kare piksel).
double areaOf(Rect rect) => rect.width * rect.height;

void main() {
  const rect = Rect.fromLTWH(0, 0, 200, 100);

  group('squarify', () {
    test('tek öğe tüm alanı kaplar', () {
      final out = squarify([2500], rect);

      expect(out, hasLength(1));
      expect(out.single.left, closeTo(rect.left, 1e-6));
      expect(out.single.top, closeTo(rect.top, 1e-6));
      expect(out.single.width, closeTo(rect.width, 1e-6));
      expect(out.single.height, closeTo(rect.height, 1e-6));
      expect(areaOf(out.single), closeTo(areaOf(rect), 1e-6));
    });

    test('iki eşit öğe alanı eşit bölüşür, toplam korunur', () {
      final out = squarify([50, 50], rect);
      final half = areaOf(rect) / 2;

      expect(out, hasLength(2));
      expect(
        areaOf(out[0]) + areaOf(out[1]),
        closeTo(areaOf(rect), areaOf(rect) * 0.01),
      );
      expect(areaOf(out[0]), closeTo(half, half * 0.01));
      expect(areaOf(out[1]), closeTo(half, half * 0.01));
    });

    test('sıralama: büyük alan küçük alandan büyük dikdörtgen alır', () {
      // Girdi bilinçli olarak artan sırada verilir.
      final out = squarify([10, 90], rect);

      expect(areaOf(out[1]), greaterThan(areaOf(out[0])));
      expect(areaOf(out[1]) / areaOf(out[0]), closeTo(9, 1e-6));
    });

    test('dikdörtgenler verilen Rect içinde kalır ve kesişmez', () {
      const areas = <double>[64, 32, 16, 8, 4, 2, 1, 1];
      final out = squarify(areas, rect);
      const eps = 1e-6;

      expect(out, hasLength(areas.length));
      for (final r in out) {
        expect(r.left, greaterThanOrEqualTo(rect.left - eps));
        expect(r.top, greaterThanOrEqualTo(rect.top - eps));
        expect(r.right, lessThanOrEqualTo(rect.right + eps));
        expect(r.bottom, lessThanOrEqualTo(rect.bottom + eps));
      }

      for (var i = 0; i < out.length; i++) {
        for (var j = i + 1; j < out.length; j++) {
          final overlapWidth =
              math.min(out[i].right, out[j].right) -
              math.max(out[i].left, out[j].left);
          final overlapHeight =
              math.min(out[i].bottom, out[j].bottom) -
              math.max(out[i].top, out[j].top);
          expect(
            overlapWidth <= eps || overlapHeight <= eps,
            isTrue,
            reason: '$i. ve $j. dikdörtgen örtüşüyor',
          );
        }
      }
    });

    test('toplam alan rect alanına eşittir (±%1)', () {
      const areas = <double>[40, 30, 20, 10, 5, 5];
      final out = squarify(areas, rect);
      final total = out.fold<double>(0, (sum, r) => sum + areaOf(r));

      expect(out, hasLength(areas.length));
      expect(total, closeTo(areaOf(rect), areaOf(rect) * 0.01));
    });
  });

  group('TreemapView', () {
    const items = <TreemapItem>[
      TreemapItem(label: 'Belgeler', size: 400 * 1024, color: Colors.teal),
      TreemapItem(label: 'Resimler', size: 300 * 1024),
      TreemapItem(label: 'Videolar', size: 200 * 1024, color: Colors.indigo),
      TreemapItem(label: 'Müzik', size: 100 * 1024),
    ];

    testWidgets('dört öğe dört Positioned çizer ve etiket görünür', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TreemapView(items: items)),
        ),
      );

      final tiles = find.descendant(
        of: find.byType(TreemapView),
        matching: find.byType(Positioned),
      );
      expect(tiles, findsNWidgets(4));
      expect(find.textContaining('Belgeler'), findsOneWidget);
      expect(find.textContaining('Veri yok'), findsNothing);
    });

    testWidgets('boş liste "Veri yok" yer tutucusunu gösterir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TreemapView(items: [])),
        ),
      );

      expect(find.text('Veri yok'), findsOneWidget);
      expect(find.byType(Positioned), findsNothing);
    });

    testWidgets('toplam boyutu sıfır olan liste "Veri yok" gösterir', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TreemapView(items: [TreemapItem(label: 'Boş', size: 0)]),
          ),
        ),
      );

      expect(find.text('Veri yok'), findsOneWidget);
      expect(find.byType(Positioned), findsNothing);
    });
  });
}
