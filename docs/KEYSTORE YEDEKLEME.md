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

## Doğrulama özeti (SHA256)

```
1c708d94aad02a98e9474138b2334d31b539cfc7785b0d415d09927206474e3c  upload-keystore.jks
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
