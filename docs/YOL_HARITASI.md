# Makay Dosya Yöneticisi — Yol Haritası

## Teknik Altyapı

| Konu | Karar |
|---|---|
| Framework | Flutter 3.47.7 (stable) / Dart 3.13 |
| Minimum SDK | Android 7.0 (API 24), hedef API 36 |
| Paket adı | `com.makay.filemanager` |
| Durum yönetimi | `ChangeNotifier` + `Provider` (basit, yeterli) |
| Ayarlar kalıcılığı | `shared_preferences` |
| Dosya erişimi | `dart:io` + `path_provider` (Android 11+ MANAGE_MEDIA / SAF notları A2'de) |
| Medya tarama | `photo_manager` (görüntü/video), kategori taraması `dart:io` |
| Grafikler | elle çizilen yüzdelik çubuklar (ek paket yok) |
| Arşiv | `archive` (zip/rar açma) |
| FTP sunucu | saf Dart soket tabanlı mini FTP sunucu (A7) + implicit TLS/FTPS (A10) |
| FTP istemci | `ftpconnect` (A7) |
| SMB sunucu | saf Dart SMB2 (2.0.2) mini sunucu, salt okunur paylaşım (A10) |
| SFTP istemci | `dartssh2` (A10) |
| Oynatıcı | `video_player` (video + ses) (A9) |
| Paylaşım | `share_plus` (A9) |
| Tema | açık / koyu / sistem — tümü ücretsiz |

## Aşamalar

### A0 — Ortam Kurulumu ✅
- [x] Android SDK doğrulandı (`C:\android\sdk`, API 36, build-tools 34/35)
- [x] Java 21 (OpenJDK), Git, Node mevcut
- [x] Flutter SDK 3.47.7 indirildi → `D:\flutter` PATH'e eklendi
- [x] `flutter doctor` temizlendi (lisanslar kabul edildi)

### A1 — Proje İskeleti ✅
- [x] `flutter create --org com.makay --project-name makay_file_manager`
- [x] Renk/tema sistemi (turkuaz vurgu rengi, açık+koyu)
- [x] `HomeScreen`: kategori ızgarası (12 karo, resimdeki sırayla)
- [x] `AppDrawer`: çekmece (resimdeki liste + %bellek satırı + alt künye)
- [x] Üst app bar: başlık, 3 nokta menü (Ayarlar/Analiz et/Yenile)
- [x] Boş ekran bileşeni ("Boş Klasör")
- [x] Türkçe yerelleştirme (flutter_localizations, locale: tr)

### A2 — Dosya Tarayıcı ✅
- [x] Klasör/liste görünümü, breadcrumb (Ana > klasör), yatay kaydırma
- [x] Sıralama (ad/tarih, artan/azalan, klasörler önce)
- [x] Arama (app bar içinde filtreleme)
- [x] Dosya işlemleri: kopyala, taşı, sil, yapıştır, yeniden adlandır, yeni klasör
- [x] Çoklu seçim modu (uzun basma) + bilgi diyaloğu
- [x] Geri dönüşüm kutusu: taşı/geri yükle/kalıcı sil/boşalt (manifest ile)
- [x] Birim testleri (file_service, formats, file entry) — 7/7 geçiyor

### A3 — Kategori Ekranları ✅
- [x] photo_manager ile MediaStore tarama (izin akışı + reddedildiğinde izin ekranı)
- [x] Görüntüler/Videolar: albüm ızgarası (küçük resim + "Ad (adet)")
- [x] Ses: liste görünümü (küçük resim + ad + adet)
- [x] Albüm içi ızgara + tam ekran görüntüleyici (yakınlaştırma, kaydırma)
- [x] Videolar için oynat simgesi katmanı
- [x] Web/masaüstü fallback: klasik dosya tarayıcısı

### A4 — Bellek Analizi ✅
- [x] Kotlin platform kanalı (StatFs): toplam/boş depolama
- [x] Kategori dağılımı: Görüntüler/Videolar/Ses/Belgeler/Arşivler/Diğerleri
- [x] Kullanım yüzdesi + ilerleme çubuğu + "Boş X GB"
- [x] Büyük dosyalar kartı (10 MB+) + tam liste ekranı ("DAHA FAZLA")
- [x] Uygulamalar kartı → Uygulamalar ekranına bağlantı
- [x] Önbellek dosyaları kartı

### A5 — Ayarlar Entegrasyonu ✅
- [x] Tarih biçimi seçimi gerçekten uygulanıyor (4 desen, Türkçe aylar)
- [x] Dosya boyutu birimi ayarı (B/KB/MB/GB/otomatik)
- [x] Tema seçimi (Açık/Koyu/Sistem) kalıcı
- [x] Geri dönüşüm kutusu/bildirim/Gelişmiş ayarları kalıcı (shared_preferences)

### A6 — Uygulamalar ✅
- [x] Kotlin kanalı: yüklü uygulama listesi (ad, paket, sürüm, ikon PNG, boyut)
- [x] İndirilenler sekmesi: Download klasöründeki APK'lar
- [x] Tümü sekmesi: boyuta göre sıralama + arama

### A7 — Ağ ve Bulut ✅
- [x] Ağdan erişim: gömülü mini FTP sunucusu (saf Dart, PASV mod, gerçek protokol testi 4/4)
- [x] Rastgele şifre, gizli dosyaları göster, BAŞLAT/DURDUR + canlı sunucu günlüğü
- [x] Otomatik yerel IP bulma (Wi-Fi öncelikli) + FTP istemci ipuçları
- [x] Uzak: FTP bağlantısı ekleme (ad/host/port/kimlik) + bağlantı testi + gezinme + indirme
- [x] Bulut: sağlayıcı diyaloğu (Nextcloud/ownCloud/pCloud/Yandex/WebDAV + OAuth sağlayıcılar bilgi)
- [x] Gerçek WebDAV gezinme (PROPFIND, Basic auth, dizin ağacı)

### A8 — Tablet / TV Uyarlaması ✅
- [x] Tablet: ≥900 px genişlikte iki panel (sol klasör ağacı + sağ liste, lazy yükleme)
- [x] Android TV: leanback launcher intent-filter, `tv_banner` drawable (320x180 XML)
- [x] Dokunmatik/leanback `uses-feature` required=false (TV mağaza uyumu)
- [x] D-pad/klavye odak vurgusu (tema: focus/hover/highlight renkleri, buton köşe teması)
- [x] Release APK üretildi (54.4 MB) — A7/A8 dahil güncel sürüm
- [x] Birim+entegrasyon testleri: 11/11 geçiyor (FTP sunucu uçtan uca protokol testi dahil)

### A9 — Oynatıcı, Önizleme, Paylaşım ✅
- [x] `video_player` ile yerleşik medya oynatıcı (video: tam ekran + gizlenen
      denetimler, seek; ses: sanat alanı + zaman çubuğu)
- [x] Tam ekran resim görüntüleyici (dosya/bellek, çift dokunma + yakınlaştırma)
- [x] Tarayıcıda dosya türüne göre otomatik önizleme (resim/video/ses açılır,
      diğerleri bilgi diyaloğu)
- [x] Albüm ekranından görüntü/video yerleşik görüntüleyicilerle açılıyor
- [x] Çoklu seçimden `share_plus` ile sistem paylaşım sayfası ("Paylaş")

### A10 — SMB Sunucusu, FTPS, SFTP ✅
- [x] Saf Dart SMB2 (dialect 2.0.2) sunucu: negotiate, NTLM (tüm şifreler
      kabul), tree connect, create/read/close, query directory (5 bilgi
      sınıfı), query info (dosya + dosya sistemi), salt okunur paylaşım
- [x] SMB gerçek uçtan uca protokol testi 2/2 (tam oturum + hata durumu)
- [x] FTPS: gömülü kendi kendine imzalı sertifika (RSA-2048, 10 yıl) +
      implicit TLS portu 2123 + PROT P veri bağlantısı şifrelemesi
- [x] SFTP istemci (dartssh2): Uzak ekranında FTP/SFTP tür seçimi,
      bağlantı testi, gezinme, indirme ekranı
- [x] Ağdan erişim ekranında SMB bölümü (\\IP\makay, BAŞLAT/DURDUR)
- [x] Testler: FTP 6/6 (FTPS el sıkışma + PROT reddi dahil), SMB 2/2

### A11 — TV'ye Özel Kanal ✅
- [x] Kotlin `isTv` kanalı (leanback veya dokunmatik ekran yok)
- [x] `TvHomeScreen`: odaklı büyük kart ızgarası (vurgu + ölçek + gölge),
      odaklanan kartın adı üstte büyük, kumanda ipuçları şeridi
- [x] Ayarlar → "Arayüz modu": Otomatik / TV (zorla) / Telefon-tablet
- [x] Kök rota TV moduna göre otomatik seçiliyor (_HomeLauncher)

### A12 — Uzak Konum Türleri + APK Derleme Yapısı ✅
- [x] "Uzak konum ekle" ekranı yenilendi: tür seçici (Yerel Ağ / SMB / FTP /
      SFTP / WebDAV) + türe göre dinamik form (SMB'de paylaşım adı, WebDAV'da URL)
- [x] SMB2 istemcisi (saf Dart, salt okunur): NTLMv2 kimlik doğrulama
      (saf Dart MD4 + NTOWFv2 HMAC-MD5, MS-NLMP 4.2.4 resmi vektörleriyle
      doğrulandı), negotiate → session setup → tree connect → liste → indirme;
      Windows/Samba paylaşımlarına `\\sunucu\paylaşım` gezinme + indirme
- [x] Yerel ağ taraması: alt ağ (192.168/10/172.16-31) taranır; 445/21/22/
      80/443/5005 portları sınanır, bulunan cihazlar tek dokunuşla
      SMB/FTP/SFTP/WebDAV konumu olarak eklenir
- [x] WebDAV konumları artık uzak konum olarak eklenebilir (URL + Basic auth,
      PROPFIND gezinme + GET indirme)
- [x] Uzak liste: türe göre ikon + özet (SMB: \\host\paylaşım, WebDAV: URL)
- [x] APK derleme yapısı: `Apk Hazırla.bat` (sürüm otomatik artırır —
      version.properties + pubspec senkron —, release APK derler, `APK\`
      klasörüne `MakayFileManager-<sürüm>.apk` + `latest.apk` kopyalar,
      SHA256 + latest.json üretir); bundan sonraki TÜM derlemeler APK
      klasörüne aktarılır
- [x] SMB sunucu CREATE yanıt düzeltmesi (FileId MS-SMB2 ofseti 64) +
      37. sınıf dizin girdisi MS-FSCC'ye uyarlandı (reserved u16)
- [x] Testler 30/30: MD4 7 vektör + NTLMv2 resmi vektör + SMB istemci↔sunucu
      tam oturum (liste + alt dizin + indirme + hata) + FTP 6 + SMB sunucu 2
      + servis/format/widget

### A13 — Marka: Logo & Uygulama İkonu ✅
- [x] Makay ailesi stiline özel ikon tasarımı (GDI+ ile üretilir):
      koyu petrol→teal diagonal degrade, cam parlaklığı, üstte "Makay"
      logosu, ortada beyaz klasör + teal doküman çizgileri
- [x] Android klasik mipmap'ler (48/72/96/144/192 — mdpi…xxxhdpi) üretildi
      ve `ic_launcher.png` olarak yerleştirildi
- [x] TV banner'ı PNG olarak yenilendi (640×360, sol ikon + "Makay /
      Dosya Yöneticisi" yazısı, drawable-xhdpi)
- [x] Web ikonları güncellendi: Icon-192/512 + maskable sürümler + favicon
      (sadeleştirilmiş klasör)
- [x] Üretim betiği: `tool/make_icon.ps1` (çalıştırınca `tool/generated/`
      içine tüm boyutları üretir — yeni boyut/lar kolayca eklenebilir)

### A14 — Premium Kavramının Tamamen Kaldırılması ✅
- [x] `PremiumScreen` silindi (`lib/screens/premium_screen.dart`) + `/premium` rota kaldırıldı
- [x] Ana ekran app bar'ındaki premium taç ikonu kaldırıldı
- [x] Çekmece altındaki "PREMIUM'A YÜKSELT" bağlantısı → sabit künye
      ("Reklamsız • Tüm özellikler ücretsiz") olarak değiştirildi
- [x] Ayarlar'daki "Premium" bölümü tamamen silindi
- [x] Tema seçimi dahil tüm özellikler zaten herkese açıktı; kavram olarak
      hiçbir ekranda "premium/satın alma/ücretli" ibaresi kalmadı
- [x] README + bu yol haritası güncel

### A15 — Yayınlama Altyapısı & Otomatik Güncelleme ✅
- [x] **Release keystore**: `android/app/upload-keystore.jks` (RSA-2048,
      10.000 gün) + `android/key.properties` (git'e girmez) + Gradle'da
      release imzalama yapılandırması — release APK artık kendi imzamızla
      çıkar
- [x] **Paket adı**: `applicationId = com.makay.filemanager` (uygulama ADI
      manifestte "Makay Dosya Yöneticisi" — ikisi farklı alanlar)
- [x] **Git deposu**: `https://github.com/makaydestek/makay-file-mamager`
      (main) — ilk commit + uzak; `.gitignore` ile keystore ve sürüm
      APK'ları koruma altında, yalnızca güncelleme üçlüsü yayılır
- [x] **Otomatik güncelleme** (`UpdateService` + `update_dialog`):
      her açılışta depodaki `APK/latest.json` sorgulanır → yeni sürüm
      varsa indirme diyaloğu (ilerleme çubuğu) → **SHA256 doğrulama**
      (eşleşmezse dosya silinir) → FileProvider ile Android kurucusu
- [x] **SHA256 yayını**: `Apk Hazırla.bat` artık `*.apk.sha256` yan
      dosyalarını (sürümü + latest) ve `url` alanlı `latest.json` üretir
- [x] Kanal/metot: `installApk` (FileProvider + REQUEST_INSTALL_PACKAGES),
      `openDefaultAppsSettings` (Ayarlar → Varsayılan uygulamalar)
- [x] Ayarlar'daki 3 yarım özellik tamamlandı:
      • **Varsayılan uygulamalar** → Android'in varsayılan uygulama ayarı
      • **Dahili uygulamalar** → Uygulamalar ekranında "DAHİLİ" sekmesi
        (cihazla gelen uygulamalar, `/apps/system` rotası)
      • **Geçici dosyalar** → önbellek + .thumbnails + .tmp/.part
        temizleyici ekranı (`/temp` rotası)
- [x] Ayarlar → Hakkında: gerçek sürüm (PackageInfo) + "Güncelleme
      kontrolü" (elle sorgulama)
- [x] `package_info_plus` eklendi; analiz temiz, testler 30/30

### A16 — APK Boyut Optimizasyonu ✅
> **Not (kullanıcı kararı)**: split-per-abi denemesi geri alındı —
> kullanıcı mimariyi bilemeyeceği için **tek yapı** sürdürülecek.
> Dağıtım güncellemesi A17'ye taşındı: tek APK + GitHub Releases.
- [x] Ölçüm: 61 MB'ın %97'si `lib/` — **3 mimari tek APK'da** geliyordu
      (arm64 19,9 + arm32 17,9 + x86_64 21,4 MB)
- [x] `flutter build apk --release --split-per-abi` → tek cihaz yalnızca
      kendi mimarisini indirir (**~20 MB**, 3 kat küçülme) — *sonradan
      kullanıcı kararıyla iptal edildi*
- [x] Kullanılmayan `installed_apps` bağımlılığı kaldırıldı

### A17 — GitHub Releases Tabanlı Güncelleme & Tek Yapı ✅
- [x] **Tek APK yapısı** (kullanıcı kararı): `--split-per-abi` geri
      alındı → `flutter build apk --release` tek fat APK (~61 MB);
      kullanıcı mimari seçmez, tek yapı dağıtılmaya devam eder
- [x] **UpdateService** → GitHub **Releases API**
      (`releases/latest`): `tag_name` (baştaki `v` atılır) kurulu
      sürümden yeniyse → Release'deki `.apk` asset'i indirilir,
      **`.apk.sha256` asset'i okunup zorunlu SHA256 doğrulaması**
      yapılır, Release notları (`body`) diyalogta gösterilir
- [x] **Betik**: tek APK + `*.apk.sha256` yan dosyası üretir →
      `gh api` ile Release'ı **otomatik yayınlar**; APK'lar git'e
      girmez (`APK/` gitignore) — depo hafif, dağıtım Release üzerinden
- [x] **Release biçimi** (kullanıcı isteği, referans: makay-video-player):
      başlık/açıklama boş → GitHub sayfada etiketi ve commit mesajını
      (`Yayin: MakayFileManager v...`) gri kutuda gösterir; betik commit
     'i release'ten önce atar ki etiket doğru mesaja işaret etsin
- [x] **Otomatik eski sürüm temizliği** (kullanıcı isteği): yeni release
      oluşturulduğunda diğer tüm release'lar **etiketiyle birlikte**
      silinir (`gh release delete --cleanup-tag`), yerel `APK`
      klasöründeki eski sürüm dosyaları da kaldırılır — geriye yalnızca
      güncel sürüm kalır
- [x] Eski `latest.json`/split dosyaları/`make_release_json.ps1`
      temizlendi (sürüm ayrıştırma artık regex değil `jsonDecode`)
- [x] `flutter analyze` temiz

### A18 — İlk Açılış Sürüm Seçimi (Mobil-Tablet / TV) ✅
- [x] **DeviceModeScreen**: uygulama ilk açıldığında iki kart —
      "Mobil-Tablet Sürümü" (dokunmatik klasik arayüz) ve
      "TV Sürümü" (kumanda odaklı, büyük kart arayüz); tek dokunuş/D-pad
      ile seçim kalıcılaşır, ekran bir daha gösterilmez
- [x] **Otomatik ayarlar**: seçim `SettingsProvider.applyDeviceMode`
      ile uygulanır — TV → `tvMode=tv` + koyu tema + TV ana ekran
      (TvHomeScreen); Mobil-Tablet → `tvMode=phone` + klasik HomeScreen
- [x] **Güncelleme kontrolü** iki adımlı: sürüm seçimi yapılmadan
      güncelleme sormaz, seçim yapıldıktan hemen sonra sorgular
- [x] Ayarlar → **"Sürüm seçimini göster"**: seçim ekranı yeniden açılır
- [x] 3 yeni widget testi (seçim ekranı + mod uygulama); analiz temiz,
      testler 33/33

## Riskler / Notlar
- Android 11+ (API 30+) kapsamlı dosya erişimi için `MANAGE_EXTERNAL_STORAGE`
  izni gerekir — Play Store'da kısıtlı, APK yan yüklemeye uygun.
- Medya okuma için Android 13+ `READ_MEDIA_IMAGES/VIDEO/AUDIO` izinleri A3'te eklenecek.
- TV platformu ayrı build değil, aynı APK'ya leanback destek + banner eklenir.
