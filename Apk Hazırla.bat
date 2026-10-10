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

echo APK derleniyor (uc mimari ayri - split-per-abi, birkac dakika surebilir)...
call flutter build apk --release --split-per-abi
if errorlevel 1 (
  echo.
  echo APK derlemesi BASARISIZ oldu! Hatalari kontrol edin.
  pause
  exit /b 1
)

set SPLIT=build\app\outputs\flutter-apk
if not exist "%SPLIT%\app-arm64-v8a-release.apk" (
  echo Cikti APK bulunamadi: %SPLIT%
  pause
  exit /b 1
)

del /q "APK\latest.apk" >nul 2>&1
for %%A in (arm64-v8a armeabi-v7a x86_64) do (
  if exist "%SPLIT%\app-%%A-release.apk" (
    copy /y "%SPLIT%\app-%%A-release.apk" "APK\MakayFileManager-%VER%-%%A.apk" >nul
    copy /y "%SPLIT%\app-%%A-release.apk" "APK\latest-%%A.apk" >nul
  )
)

echo SHA256 ozetleri ve guncelleme JSON'u hazirlaniyor...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\make_release_json.ps1"
if errorlevel 1 (
  echo SHA256/JSON hazirlanamadi!
  pause
  exit /b 1
)

echo Depoya yayinlaniyor (git)...
git add -A "APK" "version.properties" "pubspec.yaml" >nul 2>&1
git diff --cached --quiet >nul 2>&1
if not errorlevel 1 goto :nopublish
git commit -m "Yayin: MakayFileManager v%VER%" >nul 2>&1
git push origin main >nul 2>&1
if errorlevel 1 echo [Uyari] Depoya itilemedi - manuel "git push" yapin.
:nopublish

start "" "%~dp0APK"
echo.
echo APK hazir: APK\MakayFileManager-%VER%-arm64-v8a.apk (+ arm32, x86_64)
pause
