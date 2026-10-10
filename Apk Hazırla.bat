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

echo APK derleniyor (tek yapilandirma, birkac dakika surebilir)...
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

echo SHA256 ozeti hazirlaniyor...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$apk = Join-Path '%~dp0' 'APK\MakayFileManager-%VER%.apk';" ^
  "$h = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower();" ^
  "[IO.File]::WriteAllText(($apk + '.sha256'), ($h + '  ' + (Split-Path $apk -Leaf) + [Environment]::NewLine));" ^
  "Write-Output ('SHA256: ' + $h)"
if errorlevel 1 (
  echo SHA256 ozeti hazirlanamadi!
  pause
  exit /b 1
)

echo GitHub Release yayinlaniyor...
gh release view "%VER%" >nul 2>&1
if errorlevel 1 goto :createrelease
gh release upload "%VER%" "APK\MakayFileManager-%VER%.apk" "APK\MakayFileManager-%VER%.apk.sha256" --clobber >nul 2>&1
if errorlevel 1 echo [Uyari] Release guncellenemedi - "gh auth status" kontrol edin.
goto :releaseend
:createrelease
gh release create "%VER%" "APK\MakayFileManager-%VER%.apk" "APK\MakayFileManager-%VER%.apk.sha256" --title "MakayFileManager v%VER%" --notes "Yayin: MakayFileManager v%VER% - APK ve SHA256 ozeti eklenmistir." >nul 2>&1
if errorlevel 1 echo [Uyari] GitHub Release olusturulamadi - "gh auth status" kontrol edin.
:releaseend

echo Depoya yayinlaniyor (git)...
git add "version.properties" "pubspec.yaml" >nul 2>&1
git diff --cached --quiet >nul 2>&1
if not errorlevel 1 goto :nopublish
git commit -m "Yayin: MakayFileManager v%VER%" >nul 2>&1
git push origin main >nul 2>&1
if errorlevel 1 echo [Uyari] Depoya itilemedi - manuel "git push" yapin.
:nopublish

start "" "%~dp0APK"
echo.
echo APK hazir: APK\MakayFileManager-%VER%.apk
echo GitHub Release %VER% yayinda - uygulama acilista guncelleme isteyecektir.
pause
