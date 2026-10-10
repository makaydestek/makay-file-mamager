# Builds APK/latest.json + .sha256 sidecar files for split-per-abi releases.
# Run from Apk Hazirla.bat after the three APKs are copied into APK\.
# ASCII-only (PowerShell 5.1 reads .ps1 without BOM as ANSI).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot   # tool\ -> project root

$props = @{}
Get-Content (Join-Path $root 'version.properties') | ForEach-Object {
    if ($_ -match '^([A-Za-z_]+)=(.*)$') { $props[$Matches[1]] = $Matches[2].Trim() }
}
$name = $props['VERSION_NAME']
$code = [int]$props['VERSION_CODE']

$base = 'https://raw.githubusercontent.com/makaydestek/makay-file-mamager/main/APK'
$abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
$entries = [ordered]@{}
$primary = $null

foreach ($abi in $abis) {
    $apk = Join-Path $root ("APK\MakayFileManager-$name-$abi.apk")
    if (-not (Test-Path $apk)) { continue }
    $h = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
    $size = (Get-Item $apk).Length
    $leaf = Split-Path $apk -Leaf
    # sha256sum uyumlu yan dosya: "<hash>  <dosya>" (versiyonlu)
    [IO.File]::WriteAllText(($apk + '.sha256'), ($h + '  ' + $leaf + [Environment]::NewLine))
    # ve yayinlanan kopya icin
    [IO.File]::WriteAllText((Join-Path $root ("APK\latest-$abi.apk.sha256")),
        ($h + '  latest-' + $abi + '.apk' + [Environment]::NewLine))
    $entries[$abi] = @{ url = ($base + '/latest-' + $abi + '.apk'); size = $size; sha256 = $h }
    if ($abi -eq 'arm64-v8a') {
        $primary = @{ abi = $abi; url = $entries[$abi].url; size = $size; sha256 = $h }
    }
}

if ($entries.Count -eq 0) { throw 'Release APK not found in APK folder' }
if ($null -eq $primary) {
    $k = $entries.Keys[0]
    $primary = @{ abi = $k; url = $entries[$k].url; size = $entries[$k].size; sha256 = $entries[$k].sha256 }
}

$abisJson = ($entries.GetEnumerator() | ForEach-Object {
    '"' + $_.Key + '":{"url":"' + $_.Value.url + '","size":' + $_.Value.size +
        ',"sha256":"' + $_.Value.sha256 + '"}'
}) -join ','

# Birincil alanlar arm64-v8a (eski istemcilerle uyumlu) + abis haritasi (yeni istemciler)
$json = '{"app":"MakayFileManager","version":"' + $name + '","versionCode":' + $code +
    ',"minAndroid":21,"abi":"' + $primary.abi + '","url":"' + $primary.url +
    '","size":' + $primary.size + ',"sha256":"' + $primary.sha256 +
    '","abis":{' + $abisJson + '}}'
[IO.File]::WriteAllText((Join-Path $root 'APK\latest.json'), $json)
Write-Output ('SHA256 (' + $primary.abi + '): ' + $primary.sha256)
