#!/bin/bash
set -e

# ====== Settings ======
FLUTTER_VERSION="stable"
FLUTTER_DIR="$HOME/flutter"
ANDROID_SDK_DIR="$HOME/android"
ANDROID_ZIP="/tmp/android_cmdtools_latest.zip"
SDK_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
SDK_VERSION_FILE="$ANDROID_SDK_DIR/cmdline-tools/latest/source.properties"
BASHRC="$HOME/.bashrc"

append_if_missing() {
    local KEY="$1"
    local VALUE="$2"
    if grep -q "$KEY" "$BASHRC"; then
        echo "ℹ️ Položka '$KEY' již existuje v $BASHRC – přeskočeno."
    else
        echo "$VALUE" >> "$BASHRC"
        echo "✅ Přidána položka '$KEY' do $BASHRC"
    fi
}

get_sdkmanager_version() {
    if [ -f "$SDK_VERSION_FILE" ]; then
        grep "Pkg.Revision=" "$SDK_VERSION_FILE" | cut -d= -f2
    else
        echo ""
    fi
}

echo "==> Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

# ====== Installing dependencies ======
echo "==> Installing tools..."
sudo apt install -y git curl unzip xz-utils zip wget build-essential clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libstdc++6 openjdk-17-jdk mesa-utils

# ====== Kontrola Git ======
if ! command -v git &> /dev/null; then
    echo "❌ Git is not available."
    exit 1
fi

# ====== Check JDK 17 ======
JAVA_VER=$(java -version 2>&1 | head -n 1)
if [[ "$JAVA_VER" =~ \"([0-9]+)\. ]]; then
    if [ "${BASH_REMATCH[1]}" -ne 17 ]; then
        echo "❌ Java version found is not 17: $JAVA_VER"
        exit 1
    fi
else
    echo "❌ Java version could not be detected."
    exit 1
fi

# ====== Install Chromium ======
if ! command -v chromium-browser &>/dev/null && ! command -v chromium &>/dev/null; then
    echo "⚠️ Chromium not installed - Installing..."
    sudo apt install -y chromium-browser || sudo apt install -y chromium
fi
CHROME_PATH=$(command -v chromium-browser || command -v chromium)
append_if_missing "CHROME_EXECUTABLE" "export CHROME_EXECUTABLE=\"$CHROME_PATH\""
export CHROME_EXECUTABLE="$CHROME_PATH"

# ====== Install / Update Flutter ======
if [ ! -d "$FLUTTER_DIR/.git" ]; then
    echo "==> Clone the Flutter SDK..."
    git clone https://github.com/flutter/flutter.git -b $FLUTTER_VERSION "$FLUTTER_DIR"
else
    echo "✅ Flutter exists - update"
    git -C "$FLUTTER_DIR" fetch --all --prune
    git -C "$FLUTTER_DIR" reset --hard origin/$FLUTTER_VERSION
fi
append_if_missing "$FLUTTER_DIR/bin" "export PATH=\"\$PATH:$FLUTTER_DIR/bin\""
export PATH="$PATH:$FLUTTER_DIR/bin"

echo "==> Running flutter upgrade..."
"$FLUTTER_DIR/bin/flutter" upgrade

# ====== Android SDK ======
mkdir -p "$ANDROID_SDK_DIR/cmdline-tools"

SDK_VER=$(get_sdkmanager_version)
MAJOR_VER=$(echo "$SDK_VER" | cut -d. -f1)

if [ -z "$SDK_VER" ] || [ "$MAJOR_VER" -lt 12 ]; then
    echo "==> Downloading Android command-line tools..."
    rm -rf "$ANDROID_SDK_DIR/cmdline-tools/latest"
    wget -O "$ANDROID_ZIP" "$SDK_URL"
    unzip -qo "$ANDROID_ZIP" -d "$ANDROID_SDK_DIR/cmdline-tools"
    mv "$ANDROID_SDK_DIR/cmdline-tools/cmdline-tools" "$ANDROID_SDK_DIR/cmdline-tools/latest"
    echo "✅ Android command-line tools updated."
fi

append_if_missing "ANDROID_HOME" "export ANDROID_HOME=$ANDROID_SDK_DIR"
append_if_missing "\$ANDROID_HOME/cmdline-tools/latest/bin" "export PATH=\$PATH:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator"
export ANDROID_HOME=$ANDROID_SDK_DIR
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

# ====== Accepting SDK licenses ======
echo "==> I accept Android SDK licenses..."
yes | sdkmanager --sdk_root=$ANDROID_HOME --licenses

# ====== Installation of build-tools and system-images for API 36 and 34 ======
echo "==> Installing platform-build-tools and system-images..."
sdkmanager --sdk_root=$ANDROID_HOME "platform-tools" "platforms;android-36" "build-tools;36.0.0" "emulator" "system-images;android-36;google_apis;x86_64"
sdkmanager --sdk_root=$ANDROID_HOME "platforms;android-34" "build-tools;34.0.0" "system-images;android-34;google_apis;x86_64"

# ====== NDK installation ======
echo "==> Installing Android NDK 27.0.12077973..."
sdkmanager --sdk_root=$ANDROID_HOME "ndk;27.0.12077973"

# ====== Creating an AVD ======
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"

create_avd() {
    local NAME="$1"
    local IMG="$2"
    if $AVDMANAGER list avd | grep -q "^ *Name: $NAME"; then
        echo "⚠️ Emulator '$NAME' already exists, skipped."
    else
        echo "==> Creating emulator '$NAME'..."
        echo "no" | $AVDMANAGER create avd -n "$NAME" -k "$IMG" --device "pixel"
    fi
}

create_avd "Pixel_API_36" "system-images;android-36;google_apis;x86_64"
create_avd "Pixel_API_34" "system-images;android-34;google_apis;x86_64"

# ====== Function to edit AVD's config.ini ======
set_avd_config() {
    local avd_name="$1"
    declare -A params=("${!2}")  # associative array with parameters

    local cfg="$HOME/.android/avd/$avd_name.avd/config.ini"
    [ ! -f "$cfg" ] && return

    for key in "${!params[@]}"; do
        if grep -q "^$key=" "$cfg"; then
            # we will replace the existing line
            sed -i "s|^$key=.*|$key=${params[$key]}|" "$cfg"
        else
            # if it doesn't exist, we add it to the end
            echo "$key=${params[$key]}" >> "$cfg"
        fi
    done
}

# ====== Usage for both emulators ======

# Example of setting multiple parameters for AVD:
# Each key is a parameter in config.ini and the value is a set value
# You can add any additional parameters as needed
# declare -A avd_params=(
# ["hw.keyboard"]="yes" # enable hardware keyboard
# ["hw.ramSize"]="4096" # RAM size in MB
# ["skin.name"]="pixel_5" # emulator skin
# ["hw.gpu.enabled"]="yes" # enable GPU acceleration
# )

declare -A avd_params=( ["hw.keyboard"]="yes" )

set_avd_config "Pixel_API_36" avd_params[@]
set_avd_config "Pixel_API_34" avd_params[@]

# ====== Flutter settings ======
echo "==> I'm setting up Flutter on the Android SDK..."
flutter config --android-sdk $ANDROID_HOME

# ====== Setting JDK 17 as default ======
sudo update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-17-openjdk-amd64/bin/java 1
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java

echo "==> Running flutter doctor..."
flutter doctor

echo "==> Downloading more SDKs for Android, Web, Linux..."
flutter precache --android --web --linux

echo
echo "✅ Installation complete!"
echo "Open a new terminal or run: source ~/.bashrc"
echo "📱 Pixel_API_36 and Pixel_API_34 emulators are ready."
