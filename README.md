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
| Google Drive | Tarayıcı ile OAuth (PKCE) bağlanma; klasör gezinme, indirme, yükleme |
| İlk açılış seçimi | Mobil-Tablet veya TV sürümünü seç; ayarlar otomatik uygulanır |
| İzin onayı | Dosya/medya izinleri kullanıcıdan istenir; onaysız açılmaz |
| Görünüm stili | Otomatik / Dengeli / Geniş / Sık — dikey-yatay sütun sayısı seçilebilir |
| Kategori boyutları | Ana ekran kartlarında başlık altında özet boyut (arka planda hesaplanır) |

## Ekranlar (referans ekranlardan)

1. **Ana Ekran** — kategori ızgarası: Ana bellek, İndirilenler, Bellek Analizi,
   Resimler, Ses, Videolar, Belgeler, Uygulamalar, Yeni Dosyalar, Bulut, Uzak, Ağdan erişim
   (kartların altında özet boyut; görüntü stili ayarlar'dan değiştirilebilir)
2. **Çekmece (Drawer)** — Ana Ekran, Ana bellek (%), Geri Dönüşüm Kutusu, ağ sunucuları,
   hızlı kategoriler (Yeni Dosyalar, Belgeler, Videolar, Ses, Resimler, İndirilenler)
3. **Dosya Tarayıcı** — breadcrumb, liste/ızgara, sıralama, filtre, arama, dosya işlemleri
4. **Bellek Analizi** — kullanım yüzdesi, kategori dağılımı, büyük dosyalar, uygulamalar
5. **Uygulamalar** — İndirilenler / Tümü sekmeleri, APK bilgisi ve paylaşımı
6. **Ağdan Erişim** — FTP sunucu başlat (rastgele şifre, gizli dosyaları göster)
7. **Uzak** — FTP/SMB uzak konum ekleme ve gezinme
8. **Bulut** — bulut sağlayıcı hesapları ekleme; Google Drive tarayıcı ile bağlanır
9. **Yeni Dosyalar** — son 7 günde değişen dosyalar, satırlarda (Tarih • Boyut)
10. **Ayarlar** — dosya boyutu birimi, tarih biçimi, **görünüm stili**, gelişmiş ayarlar,
    geri dönüşüm kutusu ayarları, bildirimler, tema (açık/koyu/sistem), izinler

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
- **A9–A18** — oynatıcı/önizleme, SMB sunucusu + FTPS + SFTP, TV kanalı,
  uzak konum türleri, marka, Premium kaldırma, GitHub Releases dağıtımı,
  ilk açılış sürüm + izin onayı
- **A19** — geri bildirim serisi: uzak bağlantı kaydı, Google Drive tarayıcı
  bağlanma (OAuth PKCE), kategori boyutları, medya açma, görüntü stili

## Otomatik Güncelleme

Uygulama **her açılışında** GitHub **Releases** sayfasını
(`github.com/makaydestek/makay-file-mamager/releases`) sorgular
(`releases/latest` API'si). Release etiketi kurulu sürümden **yeni**yse
indirme diyaloğu açılır. Release'deki `.apk` asset'i indirilir ve
**yanındaki `.apk.sha256` asset'iyle zorunlu SHA256 doğrulaması**
yapılır (eşleşmezse dosya silinir), sonra Android kurucusuna açılır.
Release notları diyalogta gösterilir.

Sürüm artışı `Apk Hazırla.bat` ile yapılır; betik **tek yapıda** tek APK
üretir (`flutter build apk --release` — arm64 + arm32 + x86_64 tek
dosyada, kullanıcı mimari seçmez), `*.apk.sha256` yan dosyasını ekler ve
APK + özet ikilisini **otomatik GitHub Release** olarak yayınlar.
Yayın biçimi: release başlığı ve açıklaması **boş bırakılır** — GitHub
sayfada etiketi ve commit mesajını (`Yayin: MakayFileManager v...`)
gösterir. Release oluşturulduğunda **eski sürümler otomatik silinir**
(release + etiket, geriye yalnızca en güncel sürüm kalır) ve yerel
`APK` klasöründeki eski sürüm dosyaları da temizlenir.
APK dosyaları git'e girmez (`APK/` yok sayılır) — dağıtım tamamen
Release üzerinden yapılır, depo hafif kalır.

## Çalıştırma

```powershell
# Web önizleme
flutter run -d chrome

# Android (cihaz/emülatör)
flutter run -d android

# Release APK (tek yapı: arm64 + arm32 + x86_64 tek dosyada)
flutter build apk --release

# Tamamlanmış sürüm (sürüm artışı + sha256 + otomatik GitHub Release): Apk Hazırla.bat
```
