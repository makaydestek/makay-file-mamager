import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/services/transfer.dart';
import 'package:makay_file_manager/widgets/transfer_progress_dialog.dart';

/// İlerleme diyaloğu gerçek dosya I/O'su kullanmaz; kontrol edilebilir
/// `Completer`’larla sürülür (fake-async uyumlu).
void main() {
  Widget wrap(Widget child) => Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(home: child),
      );

  ElevatedButton button(
    BuildContext context, {
    required String label,
    required Future<TransferResult> Function(
      void Function(TransferProgress) onProgress,
      CancelToken token,
    ) action,
    required void Function(Object?) onError,
  }) =>
      ElevatedButton(
        onPressed: () async {
          try {
            await showTransferProgress(context, title: label, action: action);
          } catch (e) {
            onError(e);
          }
        },
        child: const Text('Başlat'),
      );

  testWidgets('tamamlanan işlem sonucu döndürür ve diyalog kapanır',
      (tester) async {
    Object? error;
    Object? returned;

    await tester.pumpWidget(wrap(
      Builder(
        builder: (context) => button(
          context,
          label: 'Kopyalanıyor',
          onError: (e) => error = e,
          action: (onProgress, token) async {
            onProgress(const TransferProgress(
              phase: TransferPhase.copying,
              doneFiles: 1,
              doneBytes: 50,
              totalFiles: 2,
              totalBytes: 100,
              currentPath: '/a/b/dosya.txt',
            ));
            return TransferResult(files: 2, bytes: 100, cancelled: false);
          },
        ),
      ),
    ));

    await tester.tap(find.text('Başlat'));
    await tester.pump();
    await tester.pumpAndSettle();

    // İlerleme bilgileri ekranda görünmüş, ardından diyalog kapanmış olmalı.
    expect(find.byType(TransferProgressDialog), findsNothing);
    expect(error, isNull);
    expect(returned, isNull);
  });

  testWidgets('ilerleme değerleri ekranda gösterilir', (tester) async {
    final completer = Completer<TransferResult>();
    Object? error;

    await tester.pumpWidget(wrap(
      Builder(
        builder: (context) => button(
          context,
          label: 'Taşınıyor',
          onError: (e) => error = e,
          action: (onProgress, token) {
            onProgress(const TransferProgress(
              phase: TransferPhase.copying,
              doneFiles: 3,
              doneBytes: 2048,
              totalFiles: 10,
              totalBytes: 8192,
              currentPath: '/Depo/Klasor/rapor.pdf',
            ));
            return completer.future;
          },
        ),
      ),
    ));

    await tester.tap(find.text('Başlat'));
    await tester.pump(); // diyalog kurulur, işlem bir sonraki karede başlar
    await tester.pump(); // ilerleme bildirimi çizilir

    expect(find.text('Taşınıyor'), findsOneWidget);
    expect(find.text('3 / 10 dosya'), findsOneWidget);
    expect(find.textContaining('rapor.pdf'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('İptal'), findsOneWidget);

    completer
        .complete(TransferResult(files: 10, bytes: 8192, cancelled: false));
    await tester.pumpAndSettle();
    expect(find.byType(TransferProgressDialog), findsNothing);
    expect(error, isNull);
  });

  testWidgets('ölçüm aşaması belirsiz ilerleme çubuğu gösterir',
      (tester) async {
    final completer = Completer<TransferResult>();

    await tester.pumpWidget(wrap(
      Builder(
        builder: (context) => button(
          context,
          label: 'Taranıyor',
          onError: (_) {},
          action: (onProgress, token) {
            onProgress(const TransferProgress(
              phase: TransferPhase.measuring,
              doneFiles: 7,
              doneBytes: 0,
            ));
            return completer.future;
          },
        ),
      ),
    ));

    await tester.tap(find.text('Başlat'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Taranıyor'), findsOneWidget);
    expect(find.text('Ölçülüyor… (7 dosya)'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(bar.value, isNull, reason: 'ölçümde ilerleme belirsizdir');

    completer.complete(TransferResult(files: 0, bytes: 0, cancelled: false));
    await tester.pumpAndSettle();
  });

  testWidgets('İptal butonu belirteci işaretler ve diyalog kapanır',
      (tester) async {
    CancelToken? seenToken;
    final completer = Completer<TransferResult>();
    Object? error;

    await tester.pumpWidget(wrap(
      Builder(
        builder: (context) => button(
          context,
          label: 'Kopyalanıyor',
          onError: (e) => error = e,
          action: (onProgress, token) {
            seenToken = token;
            return completer.future;
          },
        ),
      ),
    ));

    await tester.tap(find.text('Başlat'));
    await tester.pump();
    await tester.pump();
    expect(seenToken, isNotNull);
    expect(seenToken!.isCancelled, isFalse);

    await tester.tap(find.text('İptal'));
    await tester.pump();

    // Buton devre dışı kalır, ikinci dokunuş etkisiz.
    expect(find.textContaining('İptal ediliyor'), findsOneWidget);
    expect(seenToken!.isCancelled, isTrue);
    final cancelButton = tester.widget<TextButton>(find.byType(TextButton));
    expect(cancelButton.onPressed, isNull);

    // İşlem iptal sonucuyla biterse diyalog kapanır, hata fırlatılmaz.
    completer.completeError(const TransferCancelled());
    await tester.pumpAndSettle();
    expect(find.byType(TransferProgressDialog), findsNothing);
    expect(error, isA<TransferCancelled>());
  });

  testWidgets('hata diyalogda gösterilir ve Kapat ile yeniden fırlatılır',
      (tester) async {
    Object? error;

    await tester.pumpWidget(wrap(
      Builder(
        builder: (context) => button(
          context,
          label: 'Kopyalanıyor',
          onError: (e) => error = e,
          action: (onProgress, token) async =>
              throw StateError('disk dolu'),
        ),
      ),
    ));

    await tester.tap(find.text('Başlat'));
    await tester.pumpAndSettle();

    expect(find.text('İşlem tamamlanamadı.'), findsOneWidget);
    // StateError.toString() "Bad state: ..." önekiyle gelir; içeriğe göre bul.
    expect(find.textContaining('disk dolu'), findsOneWidget);
    expect(find.text('Kapat'), findsOneWidget);
    expect(error, isNull, reason: 'kapatılmadan hata dışarı sızmamalı');

    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();

    expect(find.byType(TransferProgressDialog), findsNothing);
    expect(error, isA<StateError>());
  });
}
