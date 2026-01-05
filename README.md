# Flutter Setup Scripts

This repository contains **automated setup scripts** for installing and configuring Flutter and the Android SDK on **Linux (Ubuntu/Debian)** and **Windows (PowerShell)**.  
They handle dependencies, environment variables, SDK downloads, emulator creation, and Flutter configuration.

## 📂 Scripts

- **Linux (Bash):** `setup-flutter.sh`
- **Windows (PowerShell):** `setup-flutter.ps1`

## 🚀 Features

- Installs and updates **Flutter SDK** (`stable` branch).
- Installs and configures **Android SDK + command-line tools**.
- Ensures **JDK 17** is available and set as default.
- Adds required **PATH environment variables** automatically.
- Accepts Android SDK licenses.
- Installs:
  - Platform tools, build-tools, emulator
  - API levels **34** and **36** (including system images with Google APIs)
  - **NDK 27.0.12077973**
- Creates ready-to-use **Android emulators**:
  - `Pixel_API_36` (Linux)
  - `Pixel_API_34` (Linux)
  - `Pixel_5_API_36` (Windows)
  - `Pixel_5_API_34` (Windows)
- Provides full support for **Android tablets**  
  (tablet AVDs can be created using the same installed system images).
- Runs `flutter doctor` and `flutter precache` to prepare SDKs (Android, Web, Desktop).

## 📋 Requirements

### Linux

- Ubuntu/Debian-based distro
- `sudo` privileges
- Internet connection

The script installs required packages automatically:

- `git`, `curl`, `unzip`, `wget`, `build-essential`, `openjdk-17-jdk`, `chromium`, and more.

### Windows

- PowerShell 5+ (recommended: PowerShell 7+)
- Git installed and available in `PATH`
- JDK 17 installed (e.g., Eclipse Adoptium)
- Google Chrome installed
- Visual Studio with the “Desktop development with C++” workload installed  
  (download from https://visualstudio.microsoft.com/downloads)

## ⚡ Usage

### Linux

```bash
chmod +x setup-flutter.sh
./setup-flutter.sh
````

After completion:

```bash
source ~/.bashrc
```

### Windows

Run in **PowerShell (as user)**:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup-flutter.ps1
```

Then restart PowerShell to load updated environment variables.

## 🧪 Verification

After running the script, verify the setup with:

```bash
flutter doctor
```

Expected: no major issues reported.

To list created emulators:

```bash
flutter emulators
```

To start one:

```bash
flutter emulators --launch Pixel_API_36
```

(Windows: replace with `Pixel_5_API_36`)

## ⚠️ Notes

* The script **resets Flutter SDK** to the latest `stable` branch.
* Existing AVDs with the same names are skipped (not overwritten).
* On Linux, if Chromium is not installed, it will be added automatically.
* On Windows, if Chrome or JDK 17 are missing, the script **aborts**.

## 📱 Ready-to-Use Emulators (Phones)

* Pixel API 36 (Android 14+)
* Pixel API 34 (Android 14)

Both come with:

* Google APIs
* Hardware keyboard enabled by default

## 📱 Android Tablets Support

This setup fully supports **Android tablet development**.

Key points:

* The scripts install **generic Google APIs system images**, usable for both phones and tablets.
* Default emulators created by the scripts are **phone profiles** (Pixel / Pixel 5).
* No additional SDK packages are required for tablets.

### Creating a Tablet Emulator

Recommended settings:

* Hardware profile: **Tablet** (Pixel Tablet, Nexus 10, custom tablet)
* API level: **34 or 36**
* System image: **Google APIs**
* Screen size: **10–13 inches**
* Resolution: **2560×1600** or similar
* RAM: **4096 MB or more**
* Graphics: **Hardware / Automatic**
* Hardware keyboard: optional

### Physical Android Tablets

* Enable **Developer options → USB debugging**.
* Connect via USB or Wi-Fi debugging.
* Verify detection:

```bash
flutter devices
```

✅ After running these scripts, your system will be ready for **Flutter app development on Android phones, tablets, Web, and Desktop**.

## License

This project is licensed under the [Apache License 2.0](LICENSE).