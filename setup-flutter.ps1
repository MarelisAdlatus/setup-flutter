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

$scriptLogTimestamp = Get-Date -Format "yyyy.MM.dd_HH-mm-ss"
$scriptLogPath = Join-Path -Path (Get-Location).Path -ChildPath ("{0}_windows_setup-flutter.log" -f $scriptLogTimestamp)
$transcriptStarted = $false

try {
    Start-Transcript -Path $scriptLogPath -Force | Out-Null
    $transcriptStarted = $true
    Write-Host "==> Logging to: $scriptLogPath" -ForegroundColor DarkYellow
}
catch {
    Write-Warning "Could not start transcript logging: $($_.Exception.Message)"
}

trap {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
        $transcriptStarted = $false
    }
    throw
}

# ====== Settings ======
$FLUTTER_VERSION = "stable"
$BASE_DIR = "C:\"
$FLUTTER_DIR = "$BASE_DIR\Flutter"
$ANDROID_SDK_DIR = "$BASE_DIR\Android"
$ANDROID_ZIP = "$env:TEMP\android_cmdtools_latest.zip"
$CMDLINE_TOOLS_BUILD = "14742923"
$SDK_URL = "https://dl.google.com/android/repository/commandlinetools-win-$CMDLINE_TOOLS_BUILD`_latest.zip"
$SDK_VERSION_FILE = "$ANDROID_SDK_DIR\cmdline-tools\latest\source.properties"
$CMDLINE_TOOLS_MARKER_FILE = "$ANDROID_SDK_DIR\cmdline-tools\latest\.marelis-build"

# ====== Check Git ======
Write-Host "==> Checking Git for presence..." -ForegroundColor Cyan
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Git is not installed. Flutter installation cancelled." -ForegroundColor Red
    throw "Git is not installed."
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
    throw "JDK 17 is not installed or is not the default."
}

# ====== Check Google Chrome ======
Write-Host "==> Checking Google Chrome..." -ForegroundColor Cyan
$chromePath = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chromePath) {
    Write-Host "❌ Google Chrome is not installed. Flutter installation cancelled." -ForegroundColor Red
    throw "Google Chrome is not installed."
}

# ====== Choose Operation Mode ======
Write-Host ""
Write-Host "What do you want to do?" -ForegroundColor Cyan
Write-Host "  1. Install Flutter, Android SDK, and configure environment (default)"
Write-Host "  2. Uninstall Flutter, Android SDK, and clean environment"
$choice = Read-Host "Select option (1 or 2, default: 1)"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

if ($choice -eq "2") {
    Write-Host ""
    Write-Host "⚠️  UNINSTALL MODE" -ForegroundColor Yellow
    Write-Host "This will remove:" -ForegroundColor Yellow
    Write-Host "  - Flutter installation ($FLUTTER_DIR)" -ForegroundColor Yellow
    Write-Host "  - Android SDK ($ANDROID_SDK_DIR)" -ForegroundColor Yellow
    Write-Host "  - Managed Android Virtual Devices (AVD)" -ForegroundColor Yellow
    Write-Host "  - Environment PATH and ANDROID_* variables (only those added by setup script)" -ForegroundColor Yellow
    $confirm = Read-Host "Are you sure? (yes/no, default: no)"
    if ($confirm -ne "yes") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
} else {
    $choice = "1"
}

# ====== Install / Update Flutter ======
if ($choice -eq "1") {
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

function Get-InstalledCmdlineToolsBuild {
    if (Test-Path $CMDLINE_TOOLS_MARKER_FILE) {
        return (Get-Content $CMDLINE_TOOLS_MARKER_FILE -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    }
    return $null
}

function Install-AndroidCmdlineTools {
    Write-Host "==> Downloading Android command-line tools build $CMDLINE_TOOLS_BUILD..." -ForegroundColor Cyan

    $tempRoot = Join-Path $env:TEMP ("android-cmdline-tools-" + [guid]::NewGuid().ToString("N"))
    $extractRoot = Join-Path $tempRoot "extract"
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

    try {
        Invoke-WebRequest $SDK_URL -OutFile $ANDROID_ZIP | Out-Null
        Expand-Archive $ANDROID_ZIP -DestinationPath $extractRoot -Force

        $extractedDir = Join-Path $extractRoot "cmdline-tools"
        if (-not (Test-Path $extractedDir)) {
            throw "Downloaded archive does not contain the expected 'cmdline-tools' directory."
        }

        if (Test-Path "$ANDROID_SDK_DIR\cmdline-tools") {
            Get-ChildItem "$ANDROID_SDK_DIR\cmdline-tools" -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Force -Path "$ANDROID_SDK_DIR\cmdline-tools" | Out-Null

        Copy-Item $extractedDir -Destination "$ANDROID_SDK_DIR\cmdline-tools\latest" -Recurse -Force
        Set-Content -Path $CMDLINE_TOOLS_MARKER_FILE -Value $CMDLINE_TOOLS_BUILD -NoNewline
        Write-Host "✅ Android command-line tools updated to build $CMDLINE_TOOLS_BUILD." -ForegroundColor Green
    }
    finally {
        if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $ANDROID_ZIP) { Remove-Item $ANDROID_ZIP -Force -ErrorAction SilentlyContinue }
    }
}

$installedBuild = Get-InstalledCmdlineToolsBuild
if ($installedBuild -ne $CMDLINE_TOOLS_BUILD) {
    Install-AndroidCmdlineTools
} else {
    Write-Host "ℹ️ Android command-line tools build $CMDLINE_TOOLS_BUILD already installed." -ForegroundColor DarkYellow
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

# ====== Prevent duplicate-package warnings caused by backup folders inside SDK root ======
function Move-SdkBackupOutsideRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $source = Join-Path $ANDROID_SDK_DIR $Name
    if (-not (Test-Path $source)) { return }

    $backupRoot = "C:\Android-Backups"
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

    $destination = Join-Path $backupRoot $Name
    if (Test-Path $destination) {
        Remove-Item $destination -Recurse -Force
    }

    Move-Item $source $destination -Force
    Write-Host "ℹ️ Moved '$source' to '$destination' to avoid sdkmanager duplicate-package warnings." -ForegroundColor DarkYellow
}

Move-SdkBackupOutsideRoot -Name "platform-tools.backup"

# ====== Acceptance of SDK licenses ======
Write-Host "==> I accept Android SDK licenses..." -ForegroundColor Cyan
"y`n" * 20 | & "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager" --sdk_root=$ANDROID_SDK_DIR --licenses

# ====== Installation of build-tools, platforms, emulators for API 34, 35 and 36 ======
Write-Host "==> Installing build-tools and system images for API 34, 35 and 36..." -ForegroundColor Cyan

& "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root=$ANDROID_SDK_DIR `
    "platform-tools" "emulator" `
    "platforms;android-36" "build-tools;36.0.0" "system-images;android-36;google_apis;x86_64" `
    "platforms;android-35" "build-tools;35.0.0" "system-images;android-35;google_apis;x86_64" `
    "platforms;android-34" "build-tools;34.0.0" "system-images;android-34;google_apis;x86_64"

# ====== Installation of NDK ======
Write-Host "==> Detecting latest Android NDK version..." -ForegroundColor Cyan


# Číselné řazení NDK verzí (správně i pro víceciferné verze)
$latestNdk = (& "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat" --list 2>$null |
    Select-String "ndk;" |
    ForEach-Object { ($_ -replace '.*ndk;([0-9\.]+).*', '$1') } |
    Where-Object { $_ -match '^[0-9]+(\.[0-9]+)*$' } |
    Sort-Object { [Version]$_ } -Descending |
    Select-Object -First 1)

Write-Host "==> Installing Android NDK $latestNdk..." -ForegroundColor Cyan
& "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root=$ANDROID_SDK_DIR "ndk;$latestNdk"


# ====== Creating default AVDs ======
$avdManager = "$ANDROID_SDK_DIR\cmdline-tools\latest\bin\avdmanager.bat"

function Get-ExistingAvdNames {
    $avdRoot = Join-Path $env:USERPROFILE ".android\avd"
    if (-not (Test-Path $avdRoot)) { return @() }

    return Get-ChildItem $avdRoot -Filter "*.ini" -File |
        Select-Object -ExpandProperty BaseName
}

function Get-AvailableDeviceListText {
    return ((& $script:avdManager list device 2>&1) -join "`n")
}

function Resolve-AvdDevice {
    param(
        [string]$Label,
        [string[]]$Candidates
    )

    $deviceListText = Get-AvailableDeviceListText
    foreach ($candidate in $Candidates) {
        if ($deviceListText -match [regex]::Escape($candidate)) {
            if ($candidate -ne $Candidates[0]) {
                Write-Host "ℹ️ Device '$($Candidates[0])' is not available, using fallback '$candidate' for $Label." -ForegroundColor DarkYellow
            }
            return $candidate
        }
    }

    Write-Host "⚠️ No supported device profile found for $Label. Candidates tried: $($Candidates -join ', ')" -ForegroundColor Yellow
    return $null
}

function New-DefaultAvd {
    param(
        [string]$Name,
        [string]$Image,
        [AllowNull()]
        [string]$Device
    )

    $existingAvds = Get-ExistingAvdNames
    if ($existingAvds -contains $Name) {
        Write-Host "ℹ️ Emulator '$Name' already exists - skipped." -ForegroundColor DarkYellow
        return
    }

    if ([string]::IsNullOrWhiteSpace($Device)) {
        Write-Host "⚠️ Emulator '$Name' skipped because no compatible hardware profile is available." -ForegroundColor Yellow
        return
    }

    Write-Host "==> Creating emulator '$Name' with device '$Device'..." -ForegroundColor Cyan
    "no" | & $script:avdManager create avd -n $Name -k $Image --device $Device | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️ Failed to create emulator '$Name'." -ForegroundColor Yellow
    }
}

function Remove-UnmanagedAvds {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ManagedNames
    )

    $existingAvds = Get-ExistingAvdNames
    $unmanaged = $existingAvds | Where-Object { $_ -notin $ManagedNames }

    foreach ($name in $unmanaged) {
        Write-Host "==> Removing unmanaged emulator '$name'..." -ForegroundColor Cyan
        & $script:avdManager delete avd -n $name | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "⚠️ Failed to remove emulator '$name'." -ForegroundColor Yellow
        }
    }
}

# Pixel emulators
$avdName36 = "Pixel_5_API_36"
$avdName35 = "Pixel_5_API_35"
$avdName34 = "Pixel_5_API_34"

# Pixel 9 emulators
$avdNamePixel936 = "Pixel_9_API_36"
$avdNamePixel935 = "Pixel_9_API_35"
$avdNamePixel934 = "Pixel_9_API_34"

# Tablet AVDs
$avdTab736 = "Tablet_7_API_36"
$avdTab735 = "Tablet_7_API_35"
$avdTab734 = "Tablet_7_API_34"

$avdTab1036 = "Tablet_10_API_36"
$avdTab1035 = "Tablet_10_API_35"
$avdTab1034 = "Tablet_10_API_34"

$managedAvdNames = @(
    $avdName36, $avdName35, $avdName34,
    $avdNamePixel936, $avdNamePixel935, $avdNamePixel934,
    $avdTab736, $avdTab735, $avdTab734,
    $avdTab1036, $avdTab1035, $avdTab1034
)

Remove-UnmanagedAvds -ManagedNames $managedAvdNames

$pixel5Device = Resolve-AvdDevice -Label "Pixel 5" -Candidates @("pixel_5", "pixel")
$pixel9Device = Resolve-AvdDevice -Label "Pixel 9 phone" -Candidates @(
    "pixel_9", "pixel_9_pro", "pixel_9_pro_xl", "pixel_8_pro", "pixel_7_pro", "pixel_6_pro", "pixel_xl", "pixel_5", "pixel"
)
# Kandidáti sjednoceni s Linux skriptem, fail-fast logika zachována
$tablet7Device = Resolve-AvdDevice -Label '7" tablet' -Candidates @('7in WSVGA (Tablet)', '7in WSVGA', 'Medium Tablet')
$tablet10Device = Resolve-AvdDevice -Label '10.1" tablet' -Candidates @('10.1in WXGA (Tablet)', '10.1in WXGA', 'Nexus 10')

New-DefaultAvd -Name $avdName36 -Image "system-images;android-36;google_apis;x86_64" -Device $pixel5Device
New-DefaultAvd -Name $avdName35 -Image "system-images;android-35;google_apis;x86_64" -Device $pixel5Device
New-DefaultAvd -Name $avdName34 -Image "system-images;android-34;google_apis;x86_64" -Device $pixel5Device

New-DefaultAvd -Name $avdNamePixel936 -Image "system-images;android-36;google_apis;x86_64" -Device $pixel9Device
New-DefaultAvd -Name $avdNamePixel935 -Image "system-images;android-35;google_apis;x86_64" -Device $pixel9Device
New-DefaultAvd -Name $avdNamePixel934 -Image "system-images;android-34;google_apis;x86_64" -Device $pixel9Device

New-DefaultAvd -Name $avdTab736 -Image "system-images;android-36;google_apis;x86_64" -Device $tablet7Device
New-DefaultAvd -Name $avdTab735 -Image "system-images;android-35;google_apis;x86_64" -Device $tablet7Device
New-DefaultAvd -Name $avdTab734 -Image "system-images;android-34;google_apis;x86_64" -Device $tablet7Device

New-DefaultAvd -Name $avdTab1036 -Image "system-images;android-36;google_apis;x86_64" -Device $tablet10Device
New-DefaultAvd -Name $avdTab1035 -Image "system-images;android-35;google_apis;x86_64" -Device $tablet10Device
New-DefaultAvd -Name $avdTab1034 -Image "system-images;android-34;google_apis;x86_64" -Device $tablet10Device

# ====== Function to edit AVD's config.ini ======
function Set-AvdConfigValues($avdName, $params) {
    $configPath = "$env:USERPROFILE\.android\avd\$avdName.avd\config.ini"
    if (-not (Test-Path $configPath)) { return }

    $lines = Get-Content $configPath
    foreach ($key in $params.Keys) {
        $pattern = '^{0}\s*=' -f [regex]::Escape($key)
        $found = $false

        $lines = $lines | ForEach-Object {
            if ($_ -match $pattern) {
                $found = $true
                "$key=$($params[$key])"
            } else {
                $_
            }
        }

        if (-not $found) {
            $lines += "$key=$($params[$key])"
        }
    }

    Set-Content $configPath $lines -Encoding UTF8
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
Set-AvdConfigValues $avdName36            $params
Set-AvdConfigValues $avdName35            $params
Set-AvdConfigValues $avdName34            $params

Set-AvdConfigValues $avdNamePixel936      $params
Set-AvdConfigValues $avdNamePixel935      $params
Set-AvdConfigValues $avdNamePixel934      $params

Set-AvdConfigValues $avdTab736            $params
Set-AvdConfigValues $avdTab735            $params
Set-AvdConfigValues $avdTab734            $params

Set-AvdConfigValues $avdTab1036           $params
Set-AvdConfigValues $avdTab1035           $params
Set-AvdConfigValues $avdTab1034           $params

# ====== Configuring Flutter ======
Write-Host "==> Setting up Flutter on Android SDK..." -ForegroundColor Cyan
& "$FLUTTER_DIR\bin\flutter.bat" config --android-sdk $ANDROID_SDK_DIR

# ====== Flutter doctor and precache ======
Write-Host "==> Running flutter doctor..." -ForegroundColor Cyan

$previousConsoleOutputEncoding = [Console]::OutputEncoding
$previousOutputEncoding = $OutputEncoding
$flutterDoctorExitCode = 0
try {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom

    & "$FLUTTER_DIR\bin\flutter.bat" doctor
    $flutterDoctorExitCode = $LASTEXITCODE
}
finally {
    [Console]::OutputEncoding = $previousConsoleOutputEncoding
    $OutputEncoding = $previousOutputEncoding
}

if ($flutterDoctorExitCode -ne 0) {
    throw "flutter doctor failed with exit code $flutterDoctorExitCode"
}

Write-Host "==> Downloading the optional SDK (Android, Web, Windows)..." -ForegroundColor Cyan
& "$FLUTTER_DIR\bin\flutter.bat" precache --android --web --windows

$managedExistingAvds = Get-ExistingAvdNames | Where-Object { $_ -in $managedAvdNames } | Sort-Object

Write-Host "`n✅ Installation complete! Open a new PowerShell to load the new PATH." -ForegroundColor Green
if ($managedExistingAvds) {
    Write-Host "📱 Managed emulators present:" -ForegroundColor Yellow
    $managedExistingAvds | ForEach-Object { Write-Host ("   - " + $_) -ForegroundColor Yellow }
} else {
    Write-Host "⚠️ No managed emulators are currently present." -ForegroundColor Yellow
}

} else {
    # ====== UNINSTALL MODE ======
    Write-Host ""
    Write-Host "==> Starting uninstallation..." -ForegroundColor Yellow

    # Remove Flutter directory
    if (Test-Path $FLUTTER_DIR) {
        Write-Host "==> Removing Flutter installation: $FLUTTER_DIR" -ForegroundColor Cyan
        Remove-Item -Path $FLUTTER_DIR -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        if (Test-Path $FLUTTER_DIR) {
            Write-Host "❌ Failed to remove Flutter directory. It may be in use." -ForegroundColor Red
        } else {
            Write-Host "✅ Flutter removed." -ForegroundColor Green
        }
    } else {
        Write-Host "ℹ️ Flutter not found at $FLUTTER_DIR" -ForegroundColor DarkYellow
    }

    # Remove Android SDK directory
    if (Test-Path $ANDROID_SDK_DIR) {
        Write-Host "==> Removing Android SDK: $ANDROID_SDK_DIR" -ForegroundColor Cyan
        Remove-Item -Path $ANDROID_SDK_DIR -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        if (Test-Path $ANDROID_SDK_DIR) {
            Write-Host "❌ Failed to remove Android SDK directory. It may be in use." -ForegroundColor Red
        } else {
            Write-Host "✅ Android SDK removed." -ForegroundColor Green
        }
    } else {
        Write-Host "ℹ️ Android SDK not found at $ANDROID_SDK_DIR" -ForegroundColor DarkYellow
    }

    # Remove Android backups directory if present
    $androidBackups = "C:\Android-Backups"
    if (Test-Path $androidBackups) {
        Write-Host "==> Removing Android backups: $androidBackups" -ForegroundColor Cyan
        Remove-Item -Path $androidBackups -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        if (Test-Path $androidBackups) {
            Write-Host "❌ Failed to remove Android backups. It may be in use." -ForegroundColor Red
        } else {
            Write-Host "✅ Android backups removed." -ForegroundColor Green
        }
    }

    # Remove managed AVDs
    $avdRoot = Join-Path $env:USERPROFILE ".android\avd"
    if (Test-Path $avdRoot) {
        Write-Host "==> Removing managed Android Virtual Devices..." -ForegroundColor Cyan
        $managedAvds = @("Pixel_9", "Pixel_9_Fold", "Pixel_Tablet")
        foreach ($avd in $managedAvds) {
            $avdDir = Join-Path $avdRoot $avd
            $avdIni = Join-Path $avdRoot "${avd}.ini"
            if (Test-Path $avdDir) {
                Remove-Item -Path $avdDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                Write-Host "✅ Removed AVD: $avd" -ForegroundColor Green
            }
            if (Test-Path $avdIni) {
                Remove-Item -Path $avdIni -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }

    # Remove user .android folder (after managed AVD removal)
    $userDotAndroid = Join-Path $env:USERPROFILE ".android"
    if (Test-Path $userDotAndroid) {
        Write-Host "==> Removing user .android folder: $userDotAndroid" -ForegroundColor Cyan
        Remove-Item -Path $userDotAndroid -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        if (Test-Path $userDotAndroid) {
            Write-Host "❌ Failed to remove $userDotAndroid. It may be in use." -ForegroundColor Red
        } else {
            Write-Host "✅ Removed $userDotAndroid." -ForegroundColor Green
        }
    }

    # Remove from PATH
    Write-Host "==> Cleaning up PATH..." -ForegroundColor Cyan
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $pathsToRemove = @(
        "$FLUTTER_DIR\bin",
        "$ANDROID_SDK_DIR\cmdline-tools\latest\bin",
        "$ANDROID_SDK_DIR\platform-tools",
        "$ANDROID_SDK_DIR\emulator"
    )
    foreach ($p in $pathsToRemove) {
            if ($currentPath -like "*$p*") {
                $currentPath = $currentPath -replace [regex]::Escape("$p;"), "" -replace [regex]::Escape(";$p"), ""
        }
    }
    [System.Environment]::SetEnvironmentVariable("Path", $currentPath, "User")
    Write-Host "✅ PATH cleaned." -ForegroundColor Green

    # Remove environment variables
    Write-Host "==> Removing environment variables..." -ForegroundColor Cyan
    [System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $null, "User")
    [System.Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $null, "User")
    Write-Host "✅ Environment variables removed." -ForegroundColor Green

    Write-Host ""
    Write-Host "✅ Uninstallation complete! Open a new PowerShell for changes to take effect." -ForegroundColor Green
}

if ($transcriptStarted) {
    Stop-Transcript | Out-Null
}
