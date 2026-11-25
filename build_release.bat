@echo off
setlocal enabledelayedexpansion
title M3U Musik Player Release Builder - Auto Version ^& Direct Server Deploy

cd /d "%~dp0"

if not exist "pubspec.yaml" (
    echo [ERROR] File pubspec.yaml tidak ditemukan di direktori saat ini!
    echo Direktori saat ini: %cd%
    pause
    exit /b 1
)

:: Jika ada argumen CLI yang diberikan langsung teruskan ke PowerShell
if not "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\build_release.ps1" %*
    exit /b %ERRORLEVEL%
)

:MENU
cls
echo ================================================================
echo       M3U MUSIK PLAYER - RELEASE ^& DIRECT SERVER DEPLOY
echo ================================================================
echo.

:: Cari versi saat ini dari pubspec.yaml
for /f "tokens=2 delims=:" %%a in ('findstr /r "^version:" pubspec.yaml') do set CURRENT_VER=%%a
:: Hapus spasi di awal
for /f "tokens=* delims= " %%a in ("!CURRENT_VER!") do set CURRENT_VER=%%a

echo Versi Saat Ini        : !CURRENT_VER!
echo Lokasi Root Project   : %~dp0
echo Target Folder Release : %~dp0public\release\^<versi^> ^& %~dp0releases\v^<versi^>
echo Varian Target Build   : 3 APK Split (arm64-v8a, armeabi-v7a, x86_64)
echo Status Git            : Folder public\release TIDAK di-gitignore (Auto Server Deploy)
echo.
echo ----------------------------------------------------------------
echo  PILIH METODE UPDATE VERSI:
echo ----------------------------------------------------------------
echo  [1] Auto Increment Patch (misal: 1.0.0 -^> 1.0.1)  [Rekomendasi / Bugfix]
echo  [2] Auto Increment Minor (misal: 1.0.0 -^> 1.1.0)  [Fitur Baru]
echo  [3] Auto Increment Major (misal: 1.0.0 -^> 2.0.0)  [Perubahan Besar]
echo  [4] Input Versi Manual   (Contoh: 1.2.0)
echo  [5] Tetap / Tanpa Update Versi (Gunakan versi saat ini)
echo  [0] Keluar / Batal
echo ----------------------------------------------------------------
echo.

set /p PILIHAN="Pilih opsi [1-5, default=1]: "
if "!PILIHAN!"=="" set PILIHAN=1

if "!PILIHAN!"=="0" (
    echo Dibatalkan oleh pengguna.
    exit /b 0
)

set BUMP_ARG=-BumpType patch
set CUSTOM_VER=

if "!PILIHAN!"=="1" (
    set BUMP_ARG=-BumpType patch
) else if "!PILIHAN!"=="2" (
    set BUMP_ARG=-BumpType minor
) else if "!PILIHAN!"=="3" (
    set BUMP_ARG=-BumpType major
) else if "!PILIHAN!"=="4" (
    echo.
    set /p CUSTOM_VER="Masukkan versi baru (contoh: 1.1.0 atau 1.1.0+2): "
    if "!CUSTOM_VER!"=="" (
        echo [ERROR] Versi tidak boleh kosong!
        timeout /t 2 >nul
        goto MENU
    )
    set BUMP_ARG=-CustomVersion "!CUSTOM_VER!"
) else if "!PILIHAN!"=="5" (
    set BUMP_ARG=-BumpType none
) else (
    echo [ERROR] Pilihan tidak valid!
    timeout /t 2 >nul
    goto MENU
)

echo.
set /p NOTES="Masukkan catatan rilis (opsional, tekan Enter untuk default): "
set NOTES_ARG=
if not "!NOTES!"=="" set NOTES_ARG=-ReleaseNotes "!NOTES!"

echo.
set /p BUILD_AAB="Sertakan build Android App Bundle (.aab) untuk Play Store? (y/N): "
set AAB_FLAG=
if /i "!BUILD_AAB!"=="y" (
    set AAB_FLAG=-IncludeAppBundle
)

echo.
echo ================================================================
echo  Memulai proses build release dengan PowerShell...
echo ================================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\build_release.ps1" !BUMP_ARG! !NOTES_ARG! !AAB_FLAG!

echo.
echo ================================================================
echo  Proses build selesai.
echo ================================================================
echo.
if exist ".git" (
    echo Status Git File Rilis:
    git status -s public/release/ pubspec.yaml
    echo.
)
echo Untuk deploy ke server, jalankan:
echo   git add public/release/ pubspec.yaml
echo   git commit -m "release: build M3U Musik app"
echo   git push
echo.
pause
