# 🔐 Keystore Yedekleme Rehberi

> **EN KRİTİK TEK DOSYA.** Bu keystore kaybolursa mevcut kullanıcılar
> uygulamanın **hiçbir güncellemesini kuramaz** (imza parmak izi değişir →
> "uygulama yüklenemedi" hatası). Yeni keystore ile çıkılan sürüm, eski
> sürümün üzerine **yazılamaz**.

## Dosyalar

| Dosya | Rol | git |
|---|---|---|
| `android/app/upload-keystore.jks` | İmza anahtarı (2.664 bayt) | ❌ commit edilmez |
| `android/key.properties` | Şifreler + anahtar yolu | ❌ commit edilmez |

`.gitignore` içinde `*.jks`, `*.keystore` ve `android/key.properties`
satırlarıyla korunur — **bu satırları asla silmeyin.**

## Koruma: değiştirme / silme engeli

İmza anahtarı geliştirme sürecinde **hiçbir şekilde değiştirilmeyecek veya
silinmeyecektir**. Bu kural dört katmanda zorlanır:

| Katman | Ne yapar | Nerede |
|---|---|---|
| **Salt okunur öznitelik** | Windows'ta dosyanın üzerine yazılmasını/silinmesini engeller (`attrib +R`, `key.properties` için `+R +H`) | `android/app/upload-keystore.jks`, `android/key.properties` |
| **Derleme öncesi doğrulama** | Dosyanın SHA256 özeti `docs/keystore.sha256` ile karşılaştırılır; **fark varsa derleme durur** | `tool/keystore_guard.ps1` + Gradle `verifyKeystore` görevi |
| **Yerel yedek** | Bozulma halinde `docs/keystore-backup/` içindeki aynı özete sahip kopyadan onarım | `docs/keystore-backup/` (git-ignore'lı) |
| **Git ignore** | Dosyalar git'te takip edilmez; `git checkout`/`restore` eski haline **getiremez**, yanlışlıkla commit edilemez, düz `git clean -fd` silmez | `android/.gitignore`: `key.properties`, `**/*.jks` |

### Otomatik kontroller

```powershell
# Elle doğrula (0 = sağlam, 1 = değişmiş/eksik)
powershell -File tool\keystore_guard.ps1

# Bozulursa yedekten onar (docs/keystore-backup/)
powershell -File tool\keystore_guard.ps1 -Fix
```

* **`Apk Hazırla.bat`** derlemeden önce `tool\keystore_guard.ps1` çalıştırır;
  özet uyuşmazsa APK üretmez ve durur.
* **Gradle** tarafında `verifyKeystore` görevi `assembleRelease` /
  `bundleRelease` işlerine bağlıdır; keystore **değiştirilmişse release
  derlemesi hata verir**. (Dosyanın yokluğu hata sayılmaz — anahtar zaten
  git'e girmez; bu durumda yalnızca uyarı yazılır.)
* **Kendi kendini onaran kilit:** guard her çalıştığında salt okunur/gizli
  öznitelikleri yeniden uygular (`self-heal`) — öznitelik elle kaldırılsa bile
  bir sonraki doğrulamada kilit geri gelir.
* `-Fix` bozuk dosyayı yedekten geri yükledikten sonra öznitelikleri otomatik
  geri uygular.
* Bu dosyalar git'e girmediğinden **değiştirilmeleri commit'lenemez**; tek
  risk yerel kazadır ve yukarıdaki doğrulamalar bunu derleme anında yakalar.

### Özeti bilinçli güncelleme

Anahtar **kasıtlı olarak** yenilenirse (yeniden üretimi yalnızca bilinçli
karardır — mevcut kullanıcılar güncellemez!):

```powershell
powershell -File tool\keystore_guard.ps1 -Backup   # yeni özetleri yazar
```

## Doğrulama özeti (SHA256)

```
1c708d94aad02a98e9474138b2334d31b539cfc7785b0d415d09927206474e3c  upload-keystore.jks
f37c2bb06c0ff915fdffb291b80ef56e82a949e86c90fb245a3e617a0bab1a34  android/key.properties
```

Yedekten geri yüklemeden önce bu özet ile doğrulayın:

```powershell
Get-FileHash .\upload-keystore.jks -Algorithm SHA256
```

## Yedekleme (en az 3 farklı yerde)

1. **Fiziksel disk** (USB bellek / harici HDD) — ana kopya
2. **Şifreli bulut** (Google Drive / Dropbox / Proton Drive klasörü)
3. **Ayrı bir bilgisayar** — felaket senaryosu için

Her yedek klasöründe şu ikisi **birlikte** bulunmalı:

```
upload-keystore.jks
key.properties
```

## Geri yükleme

1. `upload-keystore.jks` → `android/app/` klasörüne kopyalayın
2. `key.properties` → `android/` klasörüne kopyalayın
3. SHA256 özetini yukarıdakıyla karşılaştırın
4. `flutter build apk --release` ile doğrulayın

## Parolalar

`android/key.properties` dosyasında saklanır (git-ignore'lı).
Depoya **asla** yazmayın. Parolaları ayrıca bir parola yöneticisinde
tutmanız önerilir (KeePassXC, Bitwarden vb.).

## Güvenlik notu

- Bu dosyayı herkese açık bir yere (GitHub, forum, e-posta) **yüklemeyin**.
- Keystore'unuz ele geçerse birisi sizin adınıza güncelleme yayınlayabilir.
- Yedeği alırken dosyanın bozulmadığını SHA256 ile doğrulayın.
