@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if not exist "APK" mkdir "APK"

echo Surum artiriliyor...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p = Join-Path '%~dp0' 'version.properties';" ^
  "$name = '1.0.0'; $code = 1;" ^
  "if (Test-Path $p) {" ^
  "  Get-Content $p | ForEach-Object {" ^
  "    if ($_ -match '^VERSION_NAME=(.+)$') { $name = $Matches[1].Trim() }" ^
  "    if ($_ -match '^VERSION_CODE=(.+)$') { $code = [int]$Matches[1].Trim() }" ^
  "  }" ^
  "}" ^
  "$parts = $name.Split('.');" ^
  "if ($parts.Length -lt 3) { $parts = @('1','0','0') }" ^
  "$parts[2] = [string](([int]$parts[2]) + 1);" ^
  "$name = $parts[0] + '.' + $parts[1] + '.' + $parts[2];" ^
  "$code = $code + 1;" ^
  "[IO.File]::WriteAllText($p, ('VERSION_NAME=' + $name + [Environment]::NewLine + 'VERSION_CODE=' + $code + [Environment]::NewLine));" ^
  "$pp = Join-Path '%~dp0' 'pubspec.yaml';" ^
  "$c = [IO.File]::ReadAllText($pp);" ^
  "$c = [regex]::Replace($c, '(?m)^version: .+$', ('version: ' + $name + '+' + $code));" ^
  "[IO.File]::WriteAllText($pp, $c);" ^
  "Write-Output $name" > "%TEMP%\mf_ver.txt"
set /p VER=<"%TEMP%\mf_ver.txt"

echo APK derleniyor (bu birkac dakika surebilir)...
call flutter build apk --release
if errorlevel 1 (
  echo.
  echo APK derlemesi BASARISIZ oldu! Hatalari kontrol edin.
  pause
  exit /b 1
)

set OUT=build\app\outputs\flutter-apk\app-release.apk
if not exist "%OUT%" (
  echo Cikti APK bulunamadi: %OUT%
  pause
  exit /b 1
)

copy /y "%OUT%" "APK\MakayFileManager-%VER%.apk" >nul
del /q "APK\latest.apk" >nul 2>&1
copy /y "%OUT%" "APK\latest.apk" >nul

echo SHA256 ozetleri ve guncelleme JSON'u hazirlaniyor...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$f = Get-Content (Join-Path '%~dp0' 'version.properties') | ConvertFrom-StringData;" ^
  "$apk = Join-Path '%~dp0' ('APK\MakayFileManager-' + $f.VERSION_NAME + '.apk');" ^
  "$h = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower();" ^
  "$url = 'https://raw.githubusercontent.com/makaydestek/makay-file-mamager/main/APK/latest.apk';" ^
  "$json = '{\"app\":\"MakayFileManager\",\"version\":\"' + $f.VERSION_NAME + '\",\"versionCode\":' + $f.VERSION_CODE + ',\"minAndroid\":21,\"size\":' + (Get-Item $apk).Length + ',\"sha256\":\"' + $h + '\",\"url\":\"' + $url + '\"}';" ^
  "[IO.File]::WriteAllText((Join-Path '%~dp0' 'APK\latest.json'), $json);" ^
  "[IO.File]::WriteAllText(($apk + '.sha256'), ($h + '  ' + (Split-Path $apk -Leaf) + [Environment]::NewLine));" ^
  "[IO.File]::WriteAllText((Join-Path '%~dp0' 'APK\latest.apk.sha256'), ($h + '  latest.apk' + [Environment]::NewLine));" ^
  "Write-Output ('SHA256: ' + $h)"

echo Depoya yayinlaniyor (git)...
git add "APK/latest.apk" "APK/latest.apk.sha256" "APK/latest.json" "APK/MakayFileManager-%VER%.apk.sha256" "version.properties" "pubspec.yaml" >nul 2>&1
git diff --cached --quiet >nul 2>&1
if not errorlevel 1 goto :nopublish
git commit -m "Yayin: MakayFileManager v%VER%" >nul 2>&1
git push origin main >nul 2>&1
if errorlevel 1 echo [Uyari] Depoya itilemedi - manuel "git push" yapin.
:nopublish

start "" "%~dp0APK"
echo.
echo APK hazir: APK\MakayFileManager-%VER%.apk
pause
