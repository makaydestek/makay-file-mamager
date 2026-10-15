import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/providers/settings_provider.dart';
import 'package:makay_file_manager/screens/permissions_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('İzin ekranı gerekli izinleri listeler', (tester) async {
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const PermissionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Uygulamanın çalışması için izinler'), findsOneWidget);
    expect(find.text('Tüm dosyalara erişim'), findsOneWidget);
    expect(find.text('Medya erişimi'), findsOneWidget);
    expect(settings.permissionsOnboarded, false);
  });

  // Test ortamı Android olmadığı için izinler "verilmiş" kabul edilir;
  // amaç "Devam et" akışının akışı tamamladığını doğrulamak.
  testWidgets('Devam et akışı tamamlar', (tester) async {
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const PermissionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Akış butonları listenin altındadır: listeyi kaydırıp buluruz.
    final buttonFinder = find.widgetWithText(FilledButton, 'Devam et');
    await tester.scrollUntilVisible(
      buttonFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(buttonFinder);
    expect(button.onPressed, isNotNull);

    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pump();

    expect(settings.permissionsOnboarded, true);
  });

  testWidgets('Sınırlı kullanılımdan sonra akış tamamlanır', (tester) async {
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const PermissionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final skip = find.text('Yine de devam et (sınırlı kullanım)');
    await tester.scrollUntilVisible(
      skip,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pump();

    expect(settings.permissionsOnboarded, true);
  });

  testWidgets('Tüm erişim izinleri listelenir ve aranabilir', (tester) async {
    final settings = await SettingsProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const PermissionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Üst kısım görünür: dosya/medya grubu ve özet.
    expect(find.text('Tüm dosyalara erişim'), findsOneWidget);
    expect(find.text('Medya erişimi'), findsOneWidget);
    expect(find.text('Dosya ve medya'), findsOneWidget);
    // Test ortamı Android olmadığından tüm izinler "verilmiş" sayılır.
    expect(find.text('4 / 4 izin verildi'), findsOneWidget);

    // Arama: yalnız eşleşen izin kalır.
    await tester.enterText(find.byType(TextField), 'kullanım');
    await tester.pump();
    expect(find.text('Kullanım erişimi'), findsOneWidget);
    expect(find.text('Ağ erişimi'), findsNothing);
    expect(find.text('Tüm dosyalara erişim'), findsNothing);

    // Sonuç yoksa bilgilendirme görünür.
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(
      find.text('Aramanızla eşleşen izin bulunamadı.'),
      findsOneWidget,
    );

    // Listeyi geri getirip alt grupları tek tek kaydırarak görürüz:
    // her başlık kaydırıldığı konumda doğrulanır (üstteki başlıklar o
    // konumda ağaçtan düşebildiği için).
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    await _scrollTo(tester, 'Uygulama izinleri');
    expect(find.text('Uygulama izinleri'), findsOneWidget);

    await _scrollTo(tester, 'Kullanım erişimi');
    expect(find.text('Kullanım erişimi'), findsOneWidget);

    await _scrollTo(tester, 'Bilinmeyen kaynaklardan kurulum');
    expect(find.text('Bilinmeyen kaynaklardan kurulum'), findsOneWidget);

    await _scrollTo(tester, 'Otomatik verilenler');
    expect(find.text('Otomatik verilenler'), findsOneWidget);

    await _scrollTo(tester, 'Uygulama listesi');
    expect(find.text('Uygulama listesi'), findsOneWidget);

    await _scrollTo(tester, 'Ağ erişimi');
    expect(find.text('Ağ erişimi'), findsOneWidget);
  });
}

/// Verilen metni içene kadar listeyi kaydırır.
Future<void> _scrollTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}