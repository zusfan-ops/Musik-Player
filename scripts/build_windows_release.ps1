$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $RootDir

# 1. Read version from pubspec.yaml (keep in sync with Android)
$pubspecLine = Select-String -Path "pubspec.yaml" -Pattern '^version:\s*([^\s]+)' | Select-Object -First 1
if (-not $pubspecLine) {
    throw "Could not find version in pubspec.yaml"
}
$fullVersion = $pubspecLine.Matches[0].Groups[1].Value
$semVer = $fullVersion.Split('+')[0]
$buildNumber = if ($fullVersion.Contains('+')) { [int]$fullVersion.Split('+')[1] } else { 1 }

Write-Host "Building MediaCenter Windows Release v$semVer+$buildNumber..." -ForegroundColor Cyan

# 2. Build Flutter Windows Release
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows --release failed with exit code $LASTEXITCODE"
}

# 3. Locate Inno Setup Compiler (ISCC.exe)
$isccCandidates = @(
    (Get-Command "iscc.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) }

$isccPath = $isccCandidates | Select-Object -First 1
if (-not $isccPath) {
    throw "Inno Setup 6 (ISCC.exe) not found. Install Inno Setup 6 and re-run this script."
}

# 4. Ensure public/release/<version> exists and compile installer
$releaseDir = Join-Path $RootDir "public\release\$semVer"
if (-not (Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
}

& $isccPath "/DMyAppVersion=$semVer" "windows\installer\MediaCenter.iss"
if ($LASTEXITCODE -ne 0) {
    throw "ISCC.exe failed with exit code $LASTEXITCODE"
}

$installerName = "MediaCenter-Setup-v$semVer-x64.exe"
$installerPath = Join-Path $releaseDir $installerName
Write-Host "Installer created: $installerPath" -ForegroundColor Green

# 5. Update public/release/latest.json with windows_download_url
$latestJsonPath = Join-Path $RootDir "public\release\latest.json"
if (Test-Path $latestJsonPath) {
    $latest = Get-Content $latestJsonPath -Raw | ConvertFrom-Json
} else {
    $latest = [PSCustomObject]@{}
}
$latest | Add-Member -NotePropertyName "version" -NotePropertyValue $semVer -Force
$latest | Add-Member -NotePropertyName "build_number" -NotePropertyValue $buildNumber -Force
$latest | Add-Member -NotePropertyName "windows_download_url" -NotePropertyValue "/release/$semVer/$installerName" -Force
$latest | Add-Member -NotePropertyName "release_date" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
$latest | ConvertTo-Json -Depth 4 | Set-Content -Path $latestJsonPath -Encoding UTF8

Write-Host "Updated $latestJsonPath" -ForegroundColor Green
