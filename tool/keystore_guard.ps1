# Release imzalama anahtari (keystore) koruma araci.
#
# Amac: uygulama gelistirme surecinde imza anahtarinin **deistirilmesine veya
# silinmesine izin vermemek**. Android'e bir keystore ile imzalanmis bir APK
# kurulabilmesi icin tum guncellemelerin **ayni imza** ile imzalanmasi gerekir;
# anahtar degisirse mevcut kullanicilar guncellemeyi kuramaz.
#
# Ne yapar:
#   * Onay   (varsayilan)  : dosyalarin varligini ve SHA256 ozetini dogrular.
#   * -Fix    : bozuk/eksik dosyalari docs/keystore.sha256 icindeki YEDekten
#               geri yukler (yedek yaninizda degilse raporlar).
#   * -Backup : mevcut dosyalarin ozetini docs/keystore.sha256 dosyasina yazar
#               (bilincli guncelleme sonrasi; anahtar degistirilirse APK
#               kurulumu eskisiyle uyumsuz olur -- dikkatli kullanin).
#
# Cikis kodu: 0 = dogrulandi, 1 = sorun bulundu (betik/APK hazirlama durdurulur).
[CmdletBinding()]
param(
    [switch]$Fix,
    [switch]$Backup,
    [string]$RepoRoot = ''
)

# Depo kokesi: betik dosyasi uzerinden hesaplanir (param varsayilaninda
# $PSScriptRoot bazi PowerShell surumlerinde henuz bos olabiliyor).
if ($RepoRoot -eq '') {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$ErrorActionPreference = 'Stop'

$manifest = Join-Path $RepoRoot 'docs\keystore.sha256'
$entries = @()

function Read-Manifest {
    if (-not (Test-Path $manifest)) {
        Write-Host "[KESTORE] Ozet dosyasi yok: $manifest" -ForegroundColor Yellow
        return @()
    }
    $list = @()
    foreach ($line in (Get-Content $manifest)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        # bicim: <sha256>  <yola-gore-goreli-yol>
        $parts = $t -split '\s+', 2
        if ($parts.Count -ne 2) { continue }
        $list += [pscustomobject]@{
            Hash = $parts[0].ToLower()
            Rel  = $parts[1].Trim()
        }
    }
    return $list
}

function Test-Entry($entry) {
    $path = Join-Path $RepoRoot $entry.Rel
    if (-not (Test-Path $path)) {
        return [pscustomobject]@{ Ok = $false; Path = $path; Reason = 'DOSYA YOK'; Actual = '' }
    }
    $actual = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $entry.Hash) {
        return [pscustomobject]@{ Ok = $false; Path = $path; Reason = 'OZET FARKLI'; Actual = $actual }
    }
    return [pscustomobject]@{ Ok = $true; Path = $path; Reason = ''; Actual = $actual }
}

if ($Backup) {
    $targets = @(
        @{ Rel = 'android\app\upload-keystore.jks'; Abs = (Join-Path $RepoRoot 'android\app\upload-keystore.jks') },
        @{ Rel = 'android\key.properties'; Abs = (Join-Path $RepoRoot 'android\key.properties') }
    )
    $lines = @(
        '# Release imzalama anahtari ozetleri (SHA256) -- ELLE DUSTURULMEZ.',
        '# Bu dosya keystore/protected dosyalarin DEGISTIRILMESINI veya SILINMESINI',
        '# tespit etmek icin kullanilir (tool/keystore_guard.ps1).',
        '# Guncellemek icin:  powershell -File tool/keystore_guard.ps1 -Backup',
        ''
    )
    foreach ($t in $targets) {
        if (-not (Test-Path $t.Abs)) {
            Write-Host "[KESTORE] Yedek alinamadi, dosya yok: $($t.Rel)" -ForegroundColor Red
            exit 1
        }
        $h = (Get-FileHash $t.Abs -Algorithm SHA256).Hash.ToLower()
        $lines += ('{0}  {1}' -f $h, $t.Rel)
        Write-Host ('[KESTORE] {0} -> {1}' -f $t.Rel, $h) -ForegroundColor Green
    }
    Set-Content -Path $manifest -Value $lines -Encoding UTF8
    Write-Host "[KESTORE] Ozet dosyasi guncellendi: $manifest" -ForegroundColor Green
    exit 0
}

$entries = Read-Manifest
if ($entries.Count -eq 0) {
    Write-Host '[KESTORE] Dogrulanacak ozet kaydi yok; -Backup ile olusturun.' -ForegroundColor Yellow
    exit 1
}

$failed = @()
foreach ($entry in $entries) {
    $res = Test-Entry $entry
    if ($res.Ok) {
        Write-Host ('[KESTORE] OK   {0}' -f $entry.Rel) -ForegroundColor Green
        continue
    }
    if ($Fix) {
        $backupDir = Join-Path $RepoRoot 'docs\keystore-backup'
        $backupFile = Join-Path $backupDir (Split-Path $entry.Rel -Leaf)
        if (Test-Path $backupFile) {
            # Salt okunur+gizli bayraklari gecici kaldir ki yedek uzerine
            # yazlabilsin; ardindan betik sonunda yeniden uygulanir.
            # (attrib gizli dosyada tek basina -R kabul etmez, -H ile birlikte gerekir.)
            & attrib.exe -H -R $res.Path 2>$null | Out-Null
            Copy-Item $backupFile $res.Path -Force
            $res = Test-Entry $entry
            if ($res.Ok) {
                Write-Host ('[KESTORE] FIX  {0} yedekten geri yuklendi' -f $entry.Rel) -ForegroundColor Yellow
                continue
            }
        } else {
            Write-Host ('[KESTORE] FIX  {0} icin yedek bulunamadi: {1}' -f $entry.Rel, $backupFile) -ForegroundColor Red
        }
    }
    $failed += $entry.Rel
    Write-Host ('[KESTORE] HATA {0} -- {1} (beklenen {2}, bulunan {3})' -f `
        $entry.Rel, $res.Reason, $entry.Hash, $res.Actual) -ForegroundColor Red
}

if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host '[KESTORE] IMZA ANAHTARI BOZULDU VEYA DEGISTIRILDI.' -ForegroundColor Red
    Write-Host '  Bu dosyalar asla degistirilmez/silinmez; APK bu haliyle imzalanmamalidir.' -ForegroundColor Red
    Write-Host '  Geri yukleme: docs\keystore-backup\ altindaki kopyalari ilgili yollara kopyalayin' -ForegroundColor Red
    Write-Host '  ve dogrulayin:  powershell -File tool/keystore_guard.ps1 -Fix' -ForegroundColor Red
    exit 1
}

# Dosyalari salt-okunur/yapili kilida tut (self-heal): her dogrulamada bayrak
# yeniden uygulanir; bozuk yazilim/elle kaldirils bile kilit geri gelir.
$keystorePath = Join-Path $RepoRoot 'android\app\upload-keystore.jks'
$propsPath = Join-Path $RepoRoot 'android\key.properties'
if (Test-Path $keystorePath) { & attrib.exe +R $keystorePath 2>$null | Out-Null }
if (Test-Path $propsPath) { & attrib.exe +R +H $propsPath 2>$null | Out-Null }

Write-Host '[KESTORE] Imza anahtari dogrulandi (degisiklik yok).' -ForegroundColor Green
exit 0
