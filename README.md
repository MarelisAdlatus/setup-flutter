# Flutter Setup Scripts

This repository contains two setup scripts for preparing a Flutter development environment with Android SDK tooling and a predefined Android emulator set:

- `setup-flutter.sh` for Linux (Ubuntu/Debian-based systems)
- `setup-flutter.ps1` for Windows (PowerShell)

The scripts are intended to bootstrap a repeatable local environment for Flutter development on Android, Web, and desktop.

## What the scripts do

Both scripts start with an interactive mode selection:

- `1` install/update (default)
- `2` uninstall

Each run also writes a log file to the current working directory:

- Linux: `YYYY.MM.DD_HH-MM-SS_linux_setup-flutter.log`
- Windows: `YYYY.MM.DD_HH-MM-SS_windows_setup-flutter.log`

Install mode behavior:

both scripts:

- install or update Flutter from the `stable` branch
- install Android command-line tools build `14742923`
- configure Android SDK paths and Flutter Android SDK integration
- accept Android SDK licenses
- install:
  - `platform-tools`
  - `emulator`
  - Android platforms `34`, `35`, and `36`
  - build-tools `34.0.0`, `35.0.0`, and `36.0.0`
  - Google APIs x86_64 system images for API 34, 35, and 36
- detect and install the latest available Android NDK
- maintain a managed AVD set
- apply common AVD configuration:
  - hardware keyboard enabled
  - 4096 MB RAM
  - GPU enabled
  - GPU mode `auto`
- run `flutter doctor`
- run `flutter precache`

Uninstall mode behavior:

- removes Flutter and Android SDK directories used by the scripts
- removes managed AVD entries created/maintained by the scripts
- removes environment configuration entries added by the scripts

## Managed emulator set

The scripts keep the following emulator names under management:

- `Pixel_5_API_36`
- `Pixel_5_API_35`
- `Pixel_5_API_34`
- `Pixel_9_API_36`
- `Pixel_9_API_35`
- `Pixel_9_API_34`
- `Tablet_7_API_36`
- `Tablet_7_API_35`
- `Tablet_7_API_34`
- `Tablet_10_API_36`
- `Tablet_10_API_35`
- `Tablet_10_API_34`

Behavior of the managed set:

- existing managed AVDs are kept
- missing managed AVDs are created
- unmanaged AVDs are removed
- if an exact hardware profile is unavailable, the scripts may use a supported fallback device profile

## Linux script

Script: `setup-flutter.sh`

### Linux-specific behavior

The Bash script:

- updates system packages with `apt`
- installs required packages automatically, including:
  - `git`
  - `curl`
  - `unzip`
  - `xz-utils`
  - `zip`
  - `wget`
  - `build-essential`
  - `clang`
  - `cmake`
  - `ninja-build`
  - `pkg-config`
  - `libgtk-3-dev`
  - `liblzma-dev`
  - `libstdc++6`
  - `openjdk-17-jdk`
  - `mesa-utils`
- installs Chromium automatically if it is missing
- writes environment variables to `~/.bashrc`
- uses:
  - `FLUTTER_DIR="$HOME/flutter"`
  - `ANDROID_SDK_DIR="$HOME/android"`
- moves conflicting SDK backup directories such as `platform-tools.backup`, `platform-tools.old`, and `platform-tools.bak` out of the SDK root
- sets Java 17 through `update-alternatives` when the expected binary is present
- precaches Flutter artifacts for `--android --web --linux`
- in uninstall mode also removes additional user-scoped items when present:
  - `~/.android`
  - `~/.config/flutter`
  - `~/.dart-tool`
  - `~/android-sdk-backups`
  - `~/.flutter`

### Linux requirements

- Ubuntu or Debian-based distribution
- `sudo` privileges
- internet connection

### Linux usage

```bash
chmod +x setup-flutter.sh
./setup-flutter.sh
```

After the script finishes:

```bash
source ~/.bashrc
```

## Windows script

Script: `setup-flutter.ps1`

### Windows-specific behavior

The PowerShell script:

- requires Git to be available in `PATH`
- checks for JDK 17 and aborts if it is missing
- checks for Google Chrome and aborts if it is missing
- sets user environment variables for:
  - Flutter `bin`
  - Android `cmdline-tools\latest\bin`
  - `platform-tools`
  - `emulator`
  - `ANDROID_HOME`
  - `ANDROID_SDK_ROOT`
- uses:
  - `FLUTTER_DIR="C:\Flutter"`
  - `ANDROID_SDK_DIR="C:\Android"`
- moves `C:\Android\platform-tools.backup` to `C:\Android-Backups` to avoid duplicate package warnings
- runs `flutter doctor` with UTF-8 console output handling
- precaches Flutter artifacts for `--android --web --windows`
- in uninstall mode also removes:
  - `C:\Android-Backups`
  - `%USERPROFILE%\.android`

### Windows requirements

- Windows 11
- PowerShell 5 or newer
- Git installed and available in `PATH`
- JDK 17 installed
- Google Chrome installed
- Visual Studio with desktop C++ support for Windows desktop Flutter development
- internet connection

### Windows usage

Run in PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup-flutter.ps1
```

After the script finishes, open a new PowerShell session.

When running uninstall on Windows, a restart can be required for complete cleanup if some SDK files are locked by running processes.

## Verification

After running the script, verify the environment:

```bash
flutter doctor
flutter emulators
flutter devices
```

Example emulator launch:

```bash
flutter emulators --launch Pixel_9_API_36
```

## Notes

- The Flutter checkout is reset to `origin/stable` during updates.
- The scripts are designed for a clean, reproducible local setup rather than preserving arbitrary existing AVD collections.
- The Android emulator system images are x86_64 Google APIs images for API 34, 35, and 36.
- The NDK version is not hardcoded; the scripts install the latest version reported by `sdkmanager` at runtime.
- Linux and Windows differ intentionally in dependency handling:
  - Linux installs most prerequisites automatically.
  - Windows validates required prerequisites and stops if key components are missing.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
