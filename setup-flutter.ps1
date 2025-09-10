Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ====== Nastavení ======
$FLUTTER_VERSION = "stable"
$FLUTTER_DIR = "$env:USERPROFILE\flutter"
$ANDROID_SDK_DIR = "$env:USERPROFILE\android"
$ANDROID_ZIP = "$env:TEMP\android_cmdtools_latest.zip"
$SDK_URL = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
$SDK_VERSION_FILE = "$ANDROID_SDK_DIR\cmdline-tools\latest\source.properties"

# ====== Kontrola Git ======
Write-Host "==> Kontroluji přítomnost Git..." -ForegroundColor Cyan
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Git není nainstalován. Instalace Flutteru zrušena." -ForegroundColor Red
    exit 1
}

# ====== Kontrola JDK 17 ======
Write-Host "==> Kontroluji přítomnost JDK 17..." -ForegroundColor Cyan
$javaOk = $false
try {
    $javaOutput = & java -version 2>&1
    if ($javaOutput[0] -match '"(\d+)\.(\d+)\.(\d+)"') {
        $major = [int]$matches[1]
        if ($major -eq 17) { $javaOk = $true }
    }
} catch {}
if (-not $javaOk) {
    $jdkPath = Get-ChildItem "C:\Program Files\Eclipse Adoptium\" -Filter "jdk-17*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($jdkPath) {
        $javaExe = Join-Path $jdkPath.FullName "bin\java.exe"
        if (Test-Path $javaExe) { $javaOk = $true }
    }
}
if (-not $javaOk) {
    Write-Host "❌ JDK 17 není nainstalováno nebo není výchozí." -ForegroundColor Red
    exit 1
}

# ====== Kontrola Google Chrome ======
Write-Host "==> Kontroluji Google Chrome..." -ForegroundColor Cyan
$chromePath = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chromePath) {
    Write-Host "❌ Google Chrome není nainstalován. Instalace Flutteru zrušena." -ForegroundColor Red
    exit 1
}

# ====== Instalace / Aktualizace Flutter ======
if (-Not (Test-Path "$FLUTTER_DIR\.git")) {
    Write-Host "==> Klonuji Flutter SDK ($FLUTTER_VERSION) z GitHubu..." -ForegroundColor Cyan
    git clone -b $FLUTTER_VERSION https://github.com/flutter/flutter.git $FLUTTER_DIR
} else {
    Write-Host "✅ Flutter již existuje – provádím bezpečnou aktualizaci na origin/$FLUTTER_VERSION" -ForegroundColor Yellow
    Push-Location $FLUTTER_DIR
    git fetch --all --prune
    git reset --hard origin/$FLUTTER_VERSION
    Pop-Location
}
Write-Host "==> Spouštím flutter upgrade..." -ForegroundColor Cyan
& "$FLUTTER_DIR\bin\flutter.bat" upgrade

# ====== Android SDK ======
New-Item -ItemType Directory -Force -Path "$ANDROID_SDK_DIR\cmdline-tools" | Out-Null

function Get-SdkManagerVersion {
    $version = $null
    if (Test-Path $SDK_VERSION_FILE) {
        $content = Get-Content $SDK_VERSION_FILE
        foreach ($line in $content) {
            if ($line -match "Pkg.Revision=(\d+(\.\d+)+)") { $version = $matches[1]; break }
        }
    }
    $sdkManagerExe = "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat"
    if (-not $version -and (Test-Path $sdkManagerExe)) {
        try {
            $output = & $sdkManagerExe --version
            if ($output -match "^\d+(\.\d+)+") { $version = $output.Trim() }
        } catch {}
    }
    return $version
}

$existingVersion = Get-SdkManagerVersion
$minMajorVersion = 12
$shouldDownload = $true
if ($existingVersion) {
    $majorVersionString = ($existingVersion -split '[^0-9\.]')[0]
    $majorVersion = ($majorVersionString -split '\.')[0]
    if ([int]$majorVersion -ge $minMajorVersion) { $shouldDownload = $false }
}

if ($shouldDownload) {
    Write-Host "==> Stahuji nejnovější Android command-line tools..." -ForegroundColor Cyan
    Invoke-WebRequest $SDK_URL -OutFile $ANDROID_ZIP | Out-Null
    if (Test-Path "$ANDROID_SDK_DIR\cmdline-tools\latest") { Remove-Item "$ANDROID_SDK_DIR\cmdline-tools\latest" -Recurse -Force }
    Expand-Archive $ANDROID_ZIP -DestinationPath "$ANDROID_SDK_DIR\cmdline-tools"
    Rename-Item "$ANDROID_SDK_DIR\cmdline-tools\cmdline-tools" "latest"
    Write-Host "✅ Android command-line tools aktualizovány." -ForegroundColor Green
}

# ====== Nastavení proměnných PATH ======
$currentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
$newPaths = @(
    "$FLUTTER_DIR\bin",
    "$ANDROID_SDK_DIR\cmdline-tools\latest\bin",
    "$ANDROID_SDK_DIR\platform-tools",
    "$ANDROID_SDK_DIR\emulator"
)
foreach ($p in $newPaths) { if ($currentPath -notlike "*$p*") { $currentPath += ";$p" } }
[System.Environment]::SetEnvironmentVariable("Path", $currentPath, "User")
foreach ($p in $newPaths) { if ($env:Path -notlike "*$p*") { $env:Path += ";$p" } }
[System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $ANDROID_SDK_DIR, "User")

# ====== Přijetí SDK licencí ======
Write-Host "==> Přijímám Android SDK licence..." -ForegroundColor Cyan
"y`n" * 20 | & "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager" --sdk_root=$ANDROID_SDK_DIR --licenses

# ====== Instalace build-tools, platforem, emulátorů pro API 34 i 36 ======
Write-Host "==> Instalace build-tools a systémových obrazů pro API 34 a 36..." -ForegroundColor Cyan

# API 36
& "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root=$ANDROID_SDK_DIR `
    "platform-tools" "platforms;android-36" "build-tools;36.0.0" "emulator" "system-images;android-36;google_apis;x86_64"

# API 34
& "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root=$ANDROID_SDK_DIR `
    "platforms;android-34" "build-tools;34.0.0" "system-images;android-34;google_apis;x86_64"

# ====== Instalace NDK ======
Write-Host "==> Instalace Android NDK 27.0.12077973..." -ForegroundColor Cyan
& "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root=$ANDROID_SDK_DIR "ndk;27.0.12077973"

# ====== Vytvoření výchozích AVD ======
$avdManager = "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\avdmanager.bat"

# Emulátor API 36
$avdName36 = "Pixel_5_API_36"
$avdList = & $avdManager list avd 2>&1
if ($avdList -notmatch $avdName36) {
    & $avdManager create avd -n $avdName36 -k "system-images;android-36;google_apis;x86_64" --device "pixel_5"
}

# Emulátor API 34
$avdName34 = "Pixel_5_API_34"
if ($avdList -notmatch $avdName34) {
    & $avdManager create avd -n $avdName34 -k "system-images;android-34;google_apis;x86_64" --device "pixel_5"
}

# ====== Funkce pro úpravu config.ini AVD ======
function Set-AvdConfigValues($avdName, $params) {
    $configPath = "$env:USERPROFILE\.android\avd\$avdName.avd\config.ini"
    if (-not (Test-Path $configPath)) { return }
    $lines = Get-Content $configPath
    foreach ($key in $params.Keys) {
        $found = $false
        $lines = $lines | ForEach-Object {
            if ($_ -match "^$key=") {
                $found = $true
                "$key = $($params[$key])"
            } else {
                $_
            }
        }
        if (-not $found) {
            $lines += "$key = $($params[$key])"
        }
    }
    Set-Content $configPath $lines
}

# ====== Nastavení parametrů AVD ======
# Příklad nastavení více parametrů pro AVD v PowerShellu:
# Klíče jsou názvy parametrů v config.ini, hodnoty jsou nastavené hodnoty
# Můžeš libovolně rozšířit o další položky
# $params = @{
#     "hw.keyboard" = "yes"       # povolit hardwarovou klávesnici
#     "hw.ramSize"  = "4096"      # velikost RAM v MB
#     "skin.name"   = "pixel_5"   # skin emulátoru
#     "hw.gpu.enabled" = "yes"    # povolit GPU akceleraci
# }

$params = @{ "hw.keyboard" = "yes" }

# Použití pro oba emulátory
Set-AvdConfigValues $avdName36 $params
Set-AvdConfigValues $avdName34 $params

# ====== Konfigurace Flutteru ======
Write-Host "==> Nastavuji Flutter na Android SDK..." -ForegroundColor Cyan
& "$FLUTTER_DIR\bin\flutter.bat" config --android-sdk $ANDROID_SDK_DIR

# ====== Flutter doctor a precache ======
Write-Host "==> Spouštím flutter doctor..." -ForegroundColor Cyan
& "$FLUTTER_DIR\bin\flutter.bat" doctor

Write-Host "==> Stahuji volitelné SDK (Android, Web, Windows)..." -ForegroundColor Cyan
& "$FLUTTER_DIR\bin\flutter.bat" precache --android --web --windows

Write-Host "`n✅ Instalace dokončena! Otevři nový PowerShell pro načtení nového PATH." -ForegroundColor Green
Write-Host "📱 Emulátory Pixel_5_API_36 a Pixel_5_API_34 jsou připraveny." -ForegroundColor Yellow
