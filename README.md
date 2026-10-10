# Makay Dosya Yöneticisi

F Dosya Yöneticisi ++ esinlenmesiyle geliştirilen, **Mobil / Tablet / TV** için 3 platformu
tek kod tabanıyla kapsayan dosya yöneticisi uygulaması.

- **Uygulama adı:** Makay Dosya Yöneticisi
- **Paket adı:** `com.makay.filemanager`
- **Teknoloji:** Flutter (Dart)
- **Hedef platformlar:** Android telefon, Android tablet, Android TV (+ Web önizleme)
- **Dil:** Türkçe (arayüz varsayılanı)

## Tüm Özellikler Ücretsiz

Uygulamada **hiçbir premium/satın alma kavramı yoktur** — kategori ayrımı yapılmadan
tüm özellikler her kullanıcıya açıktır:

| Özellik | Açıklama |
|---|---|
| Reklam yok | Uygulamada hiçbir yerde reklam gösterilmez |
| Koyu tema | Açık / koyu / sistem teması seçimi |
| Gelişmiş menüler | Yer imi, ana ekrana ekleme, gizle/gizleme, farklı aç |
| Bellek analizi | Kategori bazlı depolama analizi |
| FTP / Ağ erişimi | Ağdan erişim (FTP sunucu) ve uzak konumlar |
| Bulut bağlantıları | Dropbox, Drive, OneDrive, Box, Nextcloud, pCloud, Yandex |

## Ekranlar (referans ekranlardan)

1. **Ana Ekran** — kategori ızgarası: Ana bellek, İndirilenler, Bellek Analizi,
   Görüntüler, Ses, Videolar, Belgeler, Uygulamalar, Yeni Dosyalar, Bulut, Uzak, Ağdan erişim
2. **Çekmece (Drawer)** — Ana Ekran, Ana bellek (%), Geri Dönüşüm Kutusu, ağ sunucuları,
   hızlı kategoriler (Yeni Dosyalar, Belgeler, Videolar, Ses, Görüntüler, İndirilenler)
3. **Dosya Tarayıcı** — breadcrumb, liste/ızgara, sıralama, filtre, arama, dosya işlemleri
4. **Bellek Analizi** — kullanım yüzdesi, kategori dağılımı, büyük dosyalar, uygulamalar
5. **Uygulamalar** — İndirilenler / Tümü sekmeleri, APK bilgisi ve paylaşımı
6. **Ağdan Erişim** — FTP sunucu başlat (rastgele şifre, gizli dosyaları göster)
7. **Uzak** — FTP/SMB uzak konum ekleme ve gezinme
8. **Bulut** — bulut sağlayıcı hesapları ekleme
9. **Ayarlar** — dosya boyutu birimi, tarih biçimi, gelişmiş ayarlar, geri dönüşüm
   kutusu ayarları, bildirimler, tema (açık/koyu/sistem)

## Geliştirme Aşamaları

Ayrıntılar: [docs/YOL_HARITASI.md](docs/YOL_HARITASI.md)

- **A0** — Ortam kurulumu (Flutter SDK, Android SDK) ✅
- **A1** — Proje iskeleti: tema, navigasyon, ana ekran, çekmece
- **A2** — Dosya tarayıcı (gezinme, breadcrumb, sıralama, arama, dosya işlemleri)
- **A3** — Kategori ekranları (Görüntüler/Videolar/Ses/Belgeler/İndirilenler/Yeni Dosyalar)
- **A4** — Bellek analizi + depolama bilgileri
- **A5** — Ayarlar + tema + geri dönüşüm kutusu
- **A6** — Uygulamalar (APK yönetimi)
- **A7** — Ağdan erişim (FTP sunucu), Uzak (FTP/SMB), Bulut
- **A8** — Tablet/TV uyarlaması (D-pad odak, geniş ekran), beta APK üretimi

## Otomatik Güncelleme

Uygulama **her açılışında** GitHub deposunu
(`github.com/makaydestek/makay-file-mamager`) sorgular; `APK/latest.json`
içinde yeni sürüm varsa indirme diyaloğu açılır. İndirilen APK **SHA256**
ile doğrulanır (eşleşmezse silinir) ve Android kurucusuna açılır.
Sürüm artışı `Apk Hazırla.bat` ile yapılır; betik **mimariye bölünmüş**
(`--split-per-abi`, cihaz başına ~20 MB) üç APK üretir, `*.sha256` yan
dosyalarını ekler ve `latest-<abi>.apk` + `latest-<abi>.apk.sha256` +
`latest.json` dosyalarını depoya iter; cihaz kendi mimarisine (arm64-v8a /
armeabi-v7a / x86_64) uygun paketi indirir.

## Çalıştırma

```powershell
# Web önizleme
flutter run -d chrome

# Android (cihaz/emülatör)
flutter run -d android

# Release APK (mimariye bölünmüş: arm64-v8a / armeabi-v7a / x86_64)
flutter build apk --release --split-per-abi

# Tamamlanmış sürüm (sürüm artışı + sha256 + depoya yayın): Apk Hazırla.bat
```
