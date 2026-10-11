import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makay_file_manager/services/recent_seen_store.dart';

/// "Yeni Dosyalar" geçmişi: temizlenen dosyalar bir daha listelenmez,
/// değiştirilen dosya ise "yeni" sayılır (e-posta okundu/okunmadı mantığı).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final t = DateTime.fromMillisecondsSinceEpoch(1000000);

  test('temizlenen kayıt kalıcıdır', () async {
    expect(await RecentSeenStore.load(), isEmpty);
    final key = RecentSeenStore.keyOf('/storage/emulated/0/a.txt', t);
    await RecentSeenStore.markSeen([key]);
    expect(await RecentSeenStore.load(), {key});
  });

  test('aynı dosya farklı zaman damgasıyla yeniden listelenir', () {
    final a = RecentSeenStore.keyOf('/x/a.txt', t);
    final b = RecentSeenStore.keyOf(
        '/x/a.txt', t.add(const Duration(minutes: 5)));
    expect(a, isNot(b));
  });

  test('markSeen birikimli çalışır ve eskileri sınırda atar', () async {
    final count = RecentSeenStore.maxEntries + 50;
    final keys = [
      for (var i = 0; i < count; i++)
        RecentSeenStore.keyOf('/x/$i.txt', t),
    ];
    await RecentSeenStore.markSeen(keys);
    final stored = await RecentSeenStore.load();
    expect(stored.length, RecentSeenStore.maxEntries);
    // İlk 50 kayıt (en eskiler) atıldı, en yeniler duruyor.
    expect(stored.contains(RecentSeenStore.keyOf('/x/0.txt', t)), isFalse);
    expect(stored.contains(RecentSeenStore.keyOf('/x/49.txt', t)), isFalse);
    expect(stored.contains(RecentSeenStore.keyOf('/x/50.txt', t)), isTrue);
    expect(stored.contains(RecentSeenStore.keyOf('/x/${count - 1}.txt', t)),
        isTrue);
  });

  test('forgetAll kayıtları siler, dosyalara dokunmaz', () async {
    await RecentSeenStore.markSeen([RecentSeenStore.keyOf('/x/a.txt', t)]);
    await RecentSeenStore.forgetAll();
    expect(await RecentSeenStore.load(), isEmpty);
  });

  test('boş anahtar listesi yazmaz', () async {
    await RecentSeenStore.markSeen(const []);
    expect(await RecentSeenStore.load(), isEmpty);
  });
}