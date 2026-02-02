#
# Copyright 2025 Marek Liška <adlatus@marelis.cz>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ====== Settings ======
$FLUTTER_VERSION = "stable"
$BASE_DIR = "C:\"
$FLUTTER_DIR = "$BASE_DIR\Flutter"
$ANDROID_SDK_DIR = "$BASE_DIR\Android"
$ANDROID_ZIP = "$env:TEMP\android_cmdtools_latest.zip"
$CMDLINE_TOOLS_BUILD = "11076708"
$SDK_URL = "https://dl.google.com/android/repository/commandlinetools-win-$CMDLINE_TOOLS_BUILD`_latest.zip"
$SDK_VERSION_FILE = "$ANDROID_SDK_DIR\cmdline-tools\latest\source.properties"

# ====== Check Git ======
Write-Host "==> Checking Git for presence..." -ForegroundColor Cyan
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Git is not installed. Flutter installation cancelled." -ForegroundColor Red
    exit 1
}

# ====== Check JDK 17 ======
Write-Host "==> Checking for JDK 17 presence..." -ForegroundColor Cyan
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
    Write-Host "❌ JDK 17 is not installed or is not the default." -ForegroundColor Red
    exit 1
}

# ====== Check Google Chrome ======
Write-Host "==> Checking Google Chrome..." -ForegroundColor Cyan
$chromePath = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chromePath) {
    Write-Host "❌ Google Chrome is not installed. Flutter installation cancelled." -ForegroundColor Red
    exit 1
}

# ====== Install / Update Flutter ======
if (-Not (Test-Path "$FLUTTER_DIR\.git")) {
    Write-Host "==> Clone the Flutter SDK ($FLUTTER_VERSION) from GitHub..." -ForegroundColor Cyan
    git clone -b $FLUTTER_VERSION https://github.com/flutter/flutter.git $FLUTTER_DIR
} else {
    Write-Host "✅ Flutter already exists - I'm doing a safe update to origin/$FLUTTER_VERSION" -ForegroundColor Yellow
    Push-Location $FLUTTER_DIR
    git fetch --all --prune
    git reset --hard origin/$FLUTTER_VERSION
    Pop-Location
}
Write-Host "==> Running flutter upgrade..." -ForegroundColor Cyan
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
    Write-Host "==> Downloading the latest Android command-line tools..." -ForegroundColor Cyan
    Invoke-WebRequest $SDK_URL -OutFile $ANDROID_ZIP | Out-Null
    if (Test-Path "$ANDROID_SDK_DIR\cmdline-tools\latest") { Remove-Item "$ANDROID_SDK_DIR\cmdline-tools\latest" -Recurse -Force }
    Expand-Archive $ANDROID_ZIP -DestinationPath "$ANDROID_SDK_DIR\cmdline-tools"
    Rename-Item "$ANDROID_SDK_DIR\cmdline-tools\cmdline-tools" "latest"
    Write-Host "✅ Android command-line tools updated." -ForegroundColor Green
}

# ====== Setting PATH variables ======
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
[System.Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $ANDROID_SDK_DIR, "User")

# ====== Acceptance of SDK licenses ======
Write-Host "==> I accept Android SDK licenses..." -ForegroundColor Cyan
"y`n" * 20 | & "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager" --sdk_root=$ANDROID_SDK_DIR --licenses

# ====== Installation of build-tools, platforms, emulators for API 34 and 36 ======
Write-Host "==> Installing build-tools and system images for API 34 and 36..." -ForegroundColor Cyan

# API 36
& "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root=$ANDROID_SDK_DIR `
    "platform-tools" "platforms;android-36" "build-tools;36.0.0" "emulator" "system-images;android-36;google_apis;x86_64"

# API 34
& "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root=$ANDROID_SDK_DIR `
    "platforms;android-34" "build-tools;34.0.0" "system-images;android-34;google_apis;x86_64"

# ====== Installation of NDK ======
Write-Host "==> Detecting latest Android NDK version..." -ForegroundColor Cyan

$latestNdk = (& "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat" --list 2>$null |
    Select-String "ndk;" |
    ForEach-Object { ($_ -replace '.*ndk;([0-9\.]+).*', '$1') } |
    Sort-Object -Descending |
    Select-Object -First 1)

Write-Host "==> Installing Android NDK $latestNdk..." -ForegroundColor Cyan
& "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root=$ANDROID_SDK_DIR "ndk;$latestNdk"


# ====== Creating default AVDs ======
$avdManager = "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\avdmanager.bat"

# API 36 Emulator
$avdName36 = "Pixel_5_API_36"
$avdList = & $avdManager list avd 2>&1
if ($avdList -notmatch $avdName36) {
    & $avdManager create avd -n $avdName36 -k "system-images;android-36;google_apis;x86_64" --device "pixel_5"
}

# API 34 Emulator
$avdName34 = "Pixel_5_API_34"
if ($avdList -notmatch $avdName34) {
    & $avdManager create avd -n $avdName34 -k "system-images;android-34;google_apis;x86_64" --device "pixel_5"
}

# ====== Tablet AVDs ======

# 7" tablet (Generic)
$avdTab7 = "Tablet_7_API_36"
if ($avdList -notmatch $avdTab7) {
    & $avdManager create avd `
        -n $avdTab7 `
        -k "system-images;android-36;google_apis;x86_64" `
        --device "7in WSVGA (Tablet)"
}

# 10.1" tablet (Generic)
$avdTab10 = "Tablet_10_API_36"
if ($avdList -notmatch $avdTab10) {
    & $avdManager create avd `
        -n $avdTab10 `
        -k "system-images;android-36;google_apis;x86_64" `
        --device "10.1in WXGA (Tablet)"
}

# ====== Function to edit AVD's config.ini ======
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

# ====== Setting AVD parameters ======
# Example of setting multiple parameters for AVD in PowerShell:
# Keys are parameter names in config.ini, values ​​are set values
# You can freely expand with other items
# $params = @{
# "hw.keyboard" = "yes" # enable hardware keyboard
# "hw.ramSize" = "4096" # RAM size in MB
# "skin.name" = "pixel_5" # emulator skin
# "hw.gpu.enabled" = "yes" # enable GPU acceleration
# }

# Common AVD hardware settings
$params = @{
    "hw.keyboard"    = "yes"   # Enable host keyboard input
    "hw.ramSize"     = "4096"  # RAM in MB (recommended for tablets)
    "hw.gpu.enabled" = "yes"   # Enable GPU acceleration
    "hw.gpu.mode"    = "auto"  # Auto-select GPU backend
}

# Apply settings
Set-AvdConfigValues $avdName36 $params
Set-AvdConfigValues $avdName34 $params
Set-AvdConfigValues $avdTab7  $params
Set-AvdConfigValues $avdTab10 $params

# ====== Configuring Flutter ======
Write-Host "==> Setting up Flutter on Android SDK..." -ForegroundColor Cyan
& "$FLUTTER_DIR\bin\flutter.bat" config --android-sdk $ANDROID_SDK_DIR

# ====== Flutter doctor and precache ======
Write-Host "==> Running flutter doctor..." -ForegroundColor Cyan
& "$FLUTTER_DIR\bin\flutter.bat" doctor

Write-Host "==> Downloading the optional SDK (Android, Web, Windows)..." -ForegroundColor Cyan
& "$FLUTTER_DIR\bin\flutter.bat" precache --android --web --windows

Write-Host "`n✅ Installation complete! Open a new PowerShell to load the new PATH." -ForegroundColor Green
Write-Host "📱 Pixel and Tablet emulators are ready." -ForegroundColor Yellow
