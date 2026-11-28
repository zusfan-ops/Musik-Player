param (
    [string]$BumpType = "patch", # patch | minor | major | none
    [string]$CustomVersion = "",
    [string]$ReleaseNotes = "",
    [switch]$IncludeAppBundle,
    [switch]$IncludeUniversal,
    [switch]$SkipWindows
)

$ErrorActionPreference = "Stop"

# Pindah ke folder root project aplikasi
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = (Resolve-Path "$ScriptDir\..").Path
Set-Location $AppDir

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  [M3U Musik Player] Auto Release & Server Deploy" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Cyan

# 1. Bump Versi
if ($CustomVersion -ne "") {
    Write-Host "`n[1/4] Mengatur versi custom: $CustomVersion..." -ForegroundColor Yellow
    dart run tool/bump_version.dart --set $CustomVersion
} elseif ($BumpType -eq "none") {
    Write-Host "`n[1/4] Mempertahankan versi saat ini..." -ForegroundColor Yellow
    dart run tool/bump_version.dart --no-bump
} elseif ($BumpType -eq "minor") {
    Write-Host "`n[1/4] Meningkatkan versi minor..." -ForegroundColor Yellow
    dart run tool/bump_version.dart --minor
} elseif ($BumpType -eq "major") {
    Write-Host "`n[1/4] Meningkatkan versi major..." -ForegroundColor Yellow
    dart run tool/bump_version.dart --major
} else {
    Write-Host "`n[1/4] Meningkatkan versi patch otomatis..." -ForegroundColor Yellow
    dart run tool/bump_version.dart
}
if ($LASTEXITCODE -ne 0) {
    Write-Error "Proses bump_version gagal dengan exit code $LASTEXITCODE!"
    exit 1
}

# Ambil versi terbaru dari pubspec.yaml
$Pubspec = Get-Content "pubspec.yaml" -Raw
if ($Pubspec -match "version:\s*([0-9\.]+)\+([0-9]+)") {
    $VersionName = $matches[1]
    $BuildNumber = $matches[2]
} else {
    Write-Error "Gagal membaca versi dari pubspec.yaml"
    exit 1
}

$VersionClean = $VersionName.TrimStart('v','V')
Write-Host "`n[Target Versi] v$VersionClean (Build $BuildNumber)" -ForegroundColor Green

# 2. Siapkan Folder Rilis Server (public/release/<version>) dan Arsip Lokal (releases/v<version>)
$ServerReleaseBase = "$AppDir\public\release"
$ServerVersionDir = "$ServerReleaseBase\$VersionClean"
$ArchiveReleaseDir = "$AppDir\releases\v$VersionClean"

Write-Host "`n[2/4] Menyiapkan direktori rilis server & arsip..." -ForegroundColor Yellow
if (-not (Test-Path $ServerVersionDir)) {
    New-Item -ItemType Directory -Path $ServerVersionDir -Force | Out-Null
}
if (-not (Test-Path $ArchiveReleaseDir)) {
    New-Item -ItemType Directory -Path $ArchiveReleaseDir -Force | Out-Null
}
Write-Host "  -> Folder Rilis Server : $ServerVersionDir" -ForegroundColor Green
Write-Host "  -> Folder Arsip Lokal  : $ArchiveReleaseDir" -ForegroundColor Gray

# 3. Flutter Pub Get
Write-Host "`n[3/4] Menjalankan flutter pub get..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter pub get gagal dengan exit code $LASTEXITCODE!"
    exit 1
}

$ApkSourceDir = "$AppDir\build\app\outputs\flutter-apk"
if (Test-Path $ApkSourceDir) {
    Remove-Item -Path "$ApkSourceDir\*.apk" -Force -ErrorAction SilentlyContinue
}

# 4. Build APK Split per ABI (3 varian: ARM64-v8a, ARMv7-a, x86_64)
Write-Host "`n[4/4] Melakukan build APK SPLIT per ABI (3 varian: ARM64-v8a, ARMv7-a, x86_64)..." -ForegroundColor Yellow
flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Build APK Split gagal dengan exit code $LASTEXITCODE! Hentikan deploy." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ServerVersionDir)) {
    New-Item -ItemType Directory -Path $ServerVersionDir -Force | Out-Null
}
if (-not (Test-Path $ArchiveReleaseDir)) {
    New-Item -ItemType Directory -Path $ArchiveReleaseDir -Force | Out-Null
}

if (Test-Path "$ApkSourceDir\app-arm64-v8a-release.apk") {
    Copy-Item -Path "$ApkSourceDir\app-arm64-v8a-release.apk" -Destination "$ServerVersionDir\M3UMusik-v$VersionClean-arm64-v8a.apk" -Force
    Copy-Item -Path "$ApkSourceDir\app-arm64-v8a-release.apk" -Destination "$ArchiveReleaseDir\M3UMusik-v$VersionClean-arm64-v8a.apk" -Force
    Write-Host "  -> [SPLIT 1/3] ARM64-v8a APK: $ServerVersionDir\M3UMusik-v$VersionClean-arm64-v8a.apk" -ForegroundColor Green
}
if (Test-Path "$ApkSourceDir\app-armeabi-v7a-release.apk") {
    Copy-Item -Path "$ApkSourceDir\app-armeabi-v7a-release.apk" -Destination "$ServerVersionDir\M3UMusik-v$VersionClean-armeabi-v7a.apk" -Force
    Copy-Item -Path "$ApkSourceDir\app-armeabi-v7a-release.apk" -Destination "$ArchiveReleaseDir\M3UMusik-v$VersionClean-armeabi-v7a.apk" -Force
    Write-Host "  -> [SPLIT 2/3] ARMv7-a APK:   $ServerVersionDir\M3UMusik-v$VersionClean-armeabi-v7a.apk" -ForegroundColor Green
}
if (Test-Path "$ApkSourceDir\app-x86_64-release.apk") {
    Copy-Item -Path "$ApkSourceDir\app-x86_64-release.apk" -Destination "$ServerVersionDir\M3UMusik-v$VersionClean-x86_64.apk" -Force
    Copy-Item -Path "$ApkSourceDir\app-x86_64-release.apk" -Destination "$ArchiveReleaseDir\M3UMusik-v$VersionClean-x86_64.apk" -Force
    Write-Host "  -> [SPLIT 3/3] x86_64 APK:    $ServerVersionDir\M3UMusik-v$VersionClean-x86_64.apk" -ForegroundColor Green
}

# 4b. Build APK Android TV Split per ABI (--dart-define=ANDROID_TV=true)
Write-Host "`n[4b/5] Melakukan build APK Android TV SPLIT per ABI (Apple TV-style UI)..." -ForegroundColor Yellow
if (Test-Path $ApkSourceDir) {
    Remove-Item -Path "$ApkSourceDir\*.apk" -Force -ErrorAction SilentlyContinue
}
flutter build apk --release --split-per-abi --dart-define=ANDROID_TV=true
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Build APK Android TV gagal dengan exit code $LASTEXITCODE! Hentikan deploy." -ForegroundColor Red
    exit 1
}

$PreferredTvApkName = $null
if (Test-Path "$ApkSourceDir\app-arm64-v8a-release.apk") {
    $TvArm64Name = "MediaCenter-TV-v$VersionClean-arm64-v8a.apk"
    Copy-Item -Path "$ApkSourceDir\app-arm64-v8a-release.apk" -Destination "$ServerVersionDir\$TvArm64Name" -Force
    Copy-Item -Path "$ApkSourceDir\app-arm64-v8a-release.apk" -Destination "$ArchiveReleaseDir\$TvArm64Name" -Force
    $PreferredTvApkName = $TvArm64Name
    Write-Host "  -> [TV 1/3] ARM64-v8a APK: $ServerVersionDir\$TvArm64Name" -ForegroundColor Green
}
if (Test-Path "$ApkSourceDir\app-armeabi-v7a-release.apk") {
    $TvArmv7Name = "MediaCenter-TV-v$VersionClean-armeabi-v7a.apk"
    Copy-Item -Path "$ApkSourceDir\app-armeabi-v7a-release.apk" -Destination "$ServerVersionDir\$TvArmv7Name" -Force
    Copy-Item -Path "$ApkSourceDir\app-armeabi-v7a-release.apk" -Destination "$ArchiveReleaseDir\$TvArmv7Name" -Force
    if (-not $PreferredTvApkName) { $PreferredTvApkName = $TvArmv7Name }
    Write-Host "  -> [TV 2/3] ARMv7-a APK:   $ServerVersionDir\$TvArmv7Name" -ForegroundColor Green
}
if (Test-Path "$ApkSourceDir\app-x86_64-release.apk") {
    $TvX64Name = "MediaCenter-TV-v$VersionClean-x86_64.apk"
    Copy-Item -Path "$ApkSourceDir\app-x86_64-release.apk" -Destination "$ServerVersionDir\$TvX64Name" -Force
    Copy-Item -Path "$ApkSourceDir\app-x86_64-release.apk" -Destination "$ArchiveReleaseDir\$TvX64Name" -Force
    Write-Host "  -> [TV 3/3] x86_64 APK:    $ServerVersionDir\$TvX64Name" -ForegroundColor Green
}

# Opsional: Build APK Universal HANYA jika diminta secara eksplisit dengan flag -IncludeUniversal
if ($IncludeUniversal) {
    Write-Host "`n[OPSIONAL] Melakukan build APK UNIVERSAL (All-in-one)..." -ForegroundColor Yellow
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build APK Universal gagal dengan exit code $LASTEXITCODE! Hentikan deploy."
        exit 1
    }

    if (Test-Path "$ApkSourceDir\app-release.apk") {
        Copy-Item -Path "$ApkSourceDir\app-release.apk" -Destination "$ServerVersionDir\M3UMusik-v$VersionClean-universal.apk" -Force
        Copy-Item -Path "$ApkSourceDir\app-release.apk" -Destination "$ArchiveReleaseDir\M3UMusik-v$VersionClean-universal.apk" -Force
        Write-Host "  -> [UNIVERSAL] Full APK:  $ServerVersionDir\M3UMusik-v$VersionClean-universal.apk" -ForegroundColor Green
    }
}

# 5. Build Windows Release & Installer (.exe) jika tidak di-skip
$WindowsInstallerName = $null
if (-not $SkipWindows) {
    Write-Host "`n[5/5] Melakukan build Windows Desktop & Installer (.exe)..." -ForegroundColor Yellow
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build Windows release gagal dengan exit code $LASTEXITCODE! Hentikan deploy."
        exit 1
    }

    $isccCandidates = @(
        (Get-Command "iscc.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }

    $isccPath = $isccCandidates | Select-Object -First 1
    if ($isccPath) {
        & $isccPath "/DMyAppVersion=$VersionClean" "$AppDir\windows\installer\MediaCenter.iss"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "ISCC.exe gagal membuat installer Windows dengan exit code $LASTEXITCODE!"
            exit 1
        }
        $BuiltInstallerName = "MediaCenter-Setup-v$VersionClean-x64.exe"
        $BuiltInstallerServerPath = "$ServerVersionDir\$BuiltInstallerName"
        if (Test-Path $BuiltInstallerServerPath) {
            Copy-Item -Path $BuiltInstallerServerPath -Destination "$ArchiveReleaseDir\$BuiltInstallerName" -Force
            $WindowsInstallerName = $BuiltInstallerName
            Write-Host "  -> [WINDOWS] Installer EXE: $BuiltInstallerServerPath" -ForegroundColor Green
        }
    } else {
        Write-Host "  -> [PERINGATAN] Inno Setup 6 (ISCC.exe) belum terpasang. Installer .exe dilewati." -ForegroundColor Yellow
    }
}

# Catatan Rilis (release_notes.txt)
$NotesContent = if ($ReleaseNotes -ne "") {
    $ReleaseNotes
} else {
    "Pembaruan rilis M3U Musik Player v$VersionClean (Build $BuildNumber)."
}
Set-Content -Path "$ServerVersionDir\release_notes.txt" -Value $NotesContent -Encoding utf8
Set-Content -Path "$ArchiveReleaseDir\release_notes.txt" -Value $NotesContent -Encoding utf8
Write-Host "  -> Catatan rilis disimpan: $ServerVersionDir\release_notes.txt" -ForegroundColor Gray

# Anti-403 Forbidden untuk Nginx: Generate index.php auto-redirector di folder versi
$IndexPhpContent = @"
<?php
`$apks = glob(__DIR__ . '/*.apk');
if (!empty(`$apks)) {
    `$selected = `$apks[0];
    foreach (`$apks as `$apk) {
        if (stripos(`$apk, 'arm64') !== false) {
            `$selected = `$apk;
            break;
        }
    }
    header('Location: ' . basename(`$selected), true, 302);
    exit;
}
header('Location: ../', true, 302);
exit;
"@
Set-Content -Path "$ServerVersionDir\index.php" -Value $IndexPhpContent -Encoding utf8
Write-Host "  -> Anti-403 index.php dibuat: $ServerVersionDir\index.php" -ForegroundColor Gray

# Update latest.json di root public/release/
$LatestJsonPath = "$ServerReleaseBase\latest.json"
$PreferredApkName = if (Test-Path "$ServerVersionDir\M3UMusik-v$VersionClean-arm64-v8a.apk") {
    "M3UMusik-v$VersionClean-arm64-v8a.apk"
} elseif (Test-Path "$ServerVersionDir\M3UMusik-v$VersionClean-universal.apk") {
    "M3UMusik-v$VersionClean-universal.apk"
} else {
    "M3UMusik-v$VersionClean-arm64-v8a.apk"
}

$LatestDataMap = [ordered]@{
    version = $VersionClean
    build_number = [int]$BuildNumber
    release_date = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    download_url = "/release/$VersionClean/$PreferredApkName"
    changelog = $NotesContent
}
if ($WindowsInstallerName) {
    $LatestDataMap["windows_download_url"] = "/release/$VersionClean/$WindowsInstallerName"
}
if ($PreferredTvApkName) {
    $LatestDataMap["tv_download_url"] = "/release/$VersionClean/$PreferredTvApkName"
}
$LatestData = $LatestDataMap | ConvertTo-Json -Depth 4
Set-Content -Path $LatestJsonPath -Value $LatestData -Encoding utf8
Write-Host "  -> public/release/latest.json diperbarui ke v$VersionClean." -ForegroundColor Green

# Optional: Build App Bundle jika ada flag -IncludeAppBundle
if ($IncludeAppBundle) {
    Write-Host "`n[BONUS] Melakukan build Android App Bundle (.aab) untuk Play Store..." -ForegroundColor Yellow
    flutter build appbundle --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build Android App Bundle (.aab) gagal dengan exit code $LASTEXITCODE!"
        exit 1
    }
    $AabSource = "$AppDir\build\app\outputs\bundle\release\app-release.aab"
    if (Test-Path $AabSource) {
        Copy-Item -Path $AabSource -Destination "$ArchiveReleaseDir\M3UMusik-v$VersionClean.aab" -Force
        Copy-Item -Path $AabSource -Destination "$ServerVersionDir\M3UMusik-v$VersionClean.aab" -Force
        Write-Host "  -> [BUNDLE] App Bundle:   $ServerVersionDir\M3UMusik-v$VersionClean.aab" -ForegroundColor Green
    }
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " BUILD RELEASE & SERVER DEPLOY v$VersionClean SUKSES!  " -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Lokasi File Rilis Siap Deploy ke Server:" -ForegroundColor Yellow
Write-Host "Direktori Server : $ServerVersionDir" -ForegroundColor White
Write-Host "Direktori Arsip  : $ArchiveReleaseDir" -ForegroundColor White
Write-Host "`nDaftar File yang Dihasilkan:" -ForegroundColor Cyan
Get-ChildItem $ServerVersionDir | ForEach-Object {
    $SizeMB = [math]::Round($_.Length / 1MB, 2)
    Write-Host "  * $($_.Name) ($SizeMB MB)" -ForegroundColor White
}
Write-Host "=======================================================`n" -ForegroundColor Yellow
