#!/bin/bash

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

set -e

LOG_TIMESTAMP="$(date +%Y.%m.%d_%H-%M-%S)"
LOG_FILE="$PWD/${LOG_TIMESTAMP}_linux_setup-flutter.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "==> Logging to: $LOG_FILE"

# ====== Settings ======
FLUTTER_VERSION="stable"
FLUTTER_DIR="$HOME/flutter"
ANDROID_SDK_DIR="$HOME/android"
ANDROID_ZIP="/tmp/android_cmdtools_latest.zip"
CMDLINE_TOOLS_VER="14742923"
SDK_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VER}_latest.zip"
SDK_VERSION_FILE="$ANDROID_SDK_DIR/cmdline-tools/latest/source.properties"
CMDLINE_TOOLS_MARKER_FILE="$ANDROID_SDK_DIR/cmdline-tools/latest/.marelis-build"
BASHRC="$HOME/.bashrc"
BACKUP_ROOT="$HOME/android-sdk-backups"

append_if_missing() {
    local key="$1"
    local value="$2"

    touch "$BASHRC"
    if grep -Fq "$key" "$BASHRC"; then
        echo "ℹ️  Entry '$key' already exists in $BASHRC – skipped."
    else
        printf '%s\n' "$value" >> "$BASHRC"
        echo "✅ Entry '$key' added to $BASHRC"
    fi
}

get_installed_cmdline_tools_build() {
    if [[ -f "$CMDLINE_TOOLS_MARKER_FILE" ]]; then
        head -n 1 "$CMDLINE_TOOLS_MARKER_FILE"
    fi
}

install_android_cmdline_tools() {
    echo "==> Downloading Android command-line tools build $CMDLINE_TOOLS_VER..."

    local tmp_root extract_root extracted_dir
    tmp_root="$(mktemp -d)"
    extract_root="$tmp_root/extract"
    mkdir -p "$extract_root"

    wget -O "$ANDROID_ZIP" "$SDK_URL"
    unzip -qo "$ANDROID_ZIP" -d "$extract_root"

    extracted_dir="$extract_root/cmdline-tools"
    if [[ ! -d "$extracted_dir" ]]; then
        echo "❌ Downloaded archive does not contain the expected 'cmdline-tools' directory."
        rm -rf "$tmp_root"
        rm -f "$ANDROID_ZIP"
        exit 1
    fi

    rm -rf "$ANDROID_SDK_DIR/cmdline-tools"
    mkdir -p "$ANDROID_SDK_DIR/cmdline-tools"
    cp -a "$extracted_dir" "$ANDROID_SDK_DIR/cmdline-tools/latest"

    rm -rf "$tmp_root"
    rm -f "$ANDROID_ZIP"
    echo "✅ Android command-line tools updated to build $CMDLINE_TOOLS_VER."
}

clean_sdk_conflicts() {
    mkdir -p "$BACKUP_ROOT"

    local moved_any=0
    while IFS= read -r -d '' path; do
        local base ts dest
        base="$(basename "$path")"
        ts="$(date +%Y%m%d-%H%M%S)"
        dest="$BACKUP_ROOT/${base}-${ts}"

        echo "==> Moving conflicting SDK directory '$path' to '$dest'..."
        mv "$path" "$dest"
        moved_any=1
    done < <(find "$ANDROID_SDK_DIR" -mindepth 1 -maxdepth 1 -type d \( -name 'platform-tools.backup' -o -name 'platform-tools.old' -o -name 'platform-tools.bak' \) -print0 2>/dev/null || true)

    if [[ $moved_any -eq 1 ]]; then
        echo "✅ Conflicting SDK backup directories moved out of SDK root."
    fi
}

run_repeating_input_to_command() {
    local input_text="$1"
    shift

    local old_pipefail=0
    if set -o | grep -Eq '^pipefail[[:space:]]+on$'; then
        old_pipefail=1
        set +o pipefail
    fi

    yes "$input_text" | "$@"
    local cmd_status=${PIPESTATUS[1]}

    if [[ $old_pipefail -eq 1 ]]; then
        set -o pipefail
    fi

    return $cmd_status
}

list_avd_names() {
    "$AVDMANAGER" list avd 2>/dev/null | sed -n 's/^[[:space:]]*Name:[[:space:]]*//p'
}

avd_exists() {
    local name="$1"
    list_avd_names | grep -Fxq "$name"
}

sync_avds() {
    local desired=("$@")
    local existing

    mapfile -t existing < <(list_avd_names)

    for avd in "${existing[@]:-}"; do
        [[ -z "$avd" ]] && continue

        local keep=0
        for wanted in "${desired[@]}"; do
            if [[ "$avd" == "$wanted" ]]; then
                keep=1
                break
            fi
        done

        if [[ $keep -eq 0 ]]; then
            echo "==> Removing unmanaged emulator '$avd'..."
            "$AVDMANAGER" delete avd -n "$avd"
            echo
        fi
    done
}

get_device_catalog() {
    "$AVDMANAGER" list device 2>/dev/null || true
}

resolve_device() {
    local catalog="$1"
    shift

    local candidate
    for candidate in "$@"; do
        [[ -z "$candidate" ]] && continue

        if grep -Fq ""$candidate"" <<< "$catalog" || grep -Fq "Name: $candidate" <<< "$catalog"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

create_avd() {
    local name="$1"
    local image="$2"
    local device="$3"

    if avd_exists "$name"; then
        echo "ℹ️  Emulator '$name' already exists – kept."
        return 0
    fi

    echo "==> Creating emulator '$name' with device profile '$device'..."
    printf 'no\n' | "$AVDMANAGER" create avd -n "$name" -k "$image" --device "$device"
    echo
}

set_avd_config() {
    local avd_name="$1"
    local map_name="$2"

    local cfg="$HOME/.android/avd/$avd_name.avd/config.ini"
    [[ -f "$cfg" ]] || return 0

    # shellcheck disable=SC2178,SC2034
    local -n params="$map_name"

    local key escaped_key value
    for key in "${!params[@]}"; do
        value="${params[$key]}"
        escaped_key="$(printf '%s' "$key" | sed 's/[][\\.^$*+?(){}|/]/\\&/g')"

        if grep -Eq "^${escaped_key}[[:space:]]*=" "$cfg"; then
            sed -i -E "s|^${escaped_key}[[:space:]]*=.*|${key}=${value}|" "$cfg"
        else
            printf '%s=%s\n' "$key" "$value" >> "$cfg"
        fi
    done
}

# ====== Choose Operation Mode ======
echo ""
echo "What do you want to do?"
echo "  1. Install Flutter, Android SDK, and configure environment (default)"
echo "  2. Uninstall Flutter, Android SDK, and clean environment"
read -p "Select option (1 or 2, default: 1): " choice
choice=${choice:-1}

if [[ "$choice" == "2" ]]; then
    echo ""
    echo "⚠️  UNINSTALL MODE"
    echo "This will remove:"
    echo "  - Flutter installation ($FLUTTER_DIR)"
    echo "  - Android SDK ($ANDROID_SDK_DIR)"
    echo "  - Managed Android Virtual Devices (AVD)"
    echo "  - Environment setup in ~/.bashrc (only entries added by setup script)"
    read -p "Are you sure? (yes/no, default: no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

if [[ "$choice" == "1" ]]; then

echo "==> Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

echo "==> Installing tools..."
sudo apt install -y git curl unzip xz-utils zip wget build-essential clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libstdc++6 openjdk-17-jdk mesa-utils

if ! command -v git >/dev/null 2>&1; then
    echo "❌ Git is not available."
    exit 1
fi

JAVA_VER="$(java -version 2>&1 | head -n 1 || true)"
if [[ $JAVA_VER =~ ([0-9]+)(\.[0-9]+.*)? ]]; then
    if [[ "${BASH_REMATCH[1]}" -ne 17 ]]; then
        echo "❌ Java version found is not 17: $JAVA_VER"
        exit 1
    fi
else
    echo "❌ Java version could not be detected."
    exit 1
fi

if ! command -v chromium-browser >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1; then
    echo "⚠️  Chromium not installed - installing..."
    sudo apt install -y chromium-browser || sudo apt install -y chromium
fi
CHROME_PATH="$(command -v chromium-browser || command -v chromium)"
append_if_missing "CHROME_EXECUTABLE" "export CHROME_EXECUTABLE=\"\$CHROME_PATH\""
export CHROME_EXECUTABLE="$CHROME_PATH"

flutter_was_cloned=0
if [[ ! -d "$FLUTTER_DIR/.git" ]]; then
    echo "==> Clone the Flutter SDK..."
    git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" "$FLUTTER_DIR"
    flutter_was_cloned=1
else
    echo "✅ Flutter exists - safe update to origin/$FLUTTER_VERSION"
    git -C "$FLUTTER_DIR" fetch --all --prune
    git -C "$FLUTTER_DIR" reset --hard "origin/$FLUTTER_VERSION"
fi
append_if_missing "$FLUTTER_DIR/bin" "export PATH="\$PATH:$FLUTTER_DIR/bin""
export PATH="$PATH:$FLUTTER_DIR/bin"

if [[ "$flutter_was_cloned" -eq 1 ]]; then
    echo "==> Fresh Flutter clone detected - skipping flutter upgrade."
else
    echo "==> Running flutter upgrade..."
    "$FLUTTER_DIR/bin/flutter" upgrade
fi

mkdir -p "$ANDROID_SDK_DIR/cmdline-tools"
clean_sdk_conflicts

INSTALLED_CMDLINE_BUILD="$(get_installed_cmdline_tools_build || true)"
if [[ "$INSTALLED_CMDLINE_BUILD" != "$CMDLINE_TOOLS_VER" ]]; then
    install_android_cmdline_tools
else
    echo "ℹ️  Android command-line tools build $CMDLINE_TOOLS_VER already installed."
fi

append_if_missing "ANDROID_HOME" "export ANDROID_HOME=\"\$ANDROID_SDK_DIR\""
append_if_missing "ANDROID_SDK_ROOT" "export ANDROID_SDK_ROOT=\"\$ANDROID_SDK_DIR\""
append_if_missing "cmdline-tools/latest/bin" "export PATH="\$PATH:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator""
export ANDROID_HOME="$ANDROID_SDK_DIR"
export ANDROID_SDK_ROOT="$ANDROID_SDK_DIR"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"

echo "==> I accept Android SDK licenses..."
run_repeating_input_to_command "y" "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses

echo "==> Installing platform-tools, build-tools and system images for API 34, 35 and 36..."
"$SDKMANAGER" --sdk_root="$ANDROID_HOME" \
    "platform-tools" "emulator" \
    "platforms;android-36" "build-tools;36.0.0" "system-images;android-36;google_apis;x86_64" \
    "platforms;android-35" "build-tools;35.0.0" "system-images;android-35;google_apis;x86_64" \
    "platforms;android-34" "build-tools;34.0.0" "system-images;android-34;google_apis;x86_64"

echo "==> Detecting latest Android NDK version..."
NDK="$($SDKMANAGER --list 2>/dev/null | sed -n 's/.*ndk;\([0-9.][0-9.]*\).*/\1/p' | sort -Vr | head -n 1)"
if [[ -n "$NDK" ]]; then
    echo "==> Installing Android NDK $NDK..."
    "$SDKMANAGER" --sdk_root="$ANDROID_HOME" "ndk;$NDK"
else
    echo "⚠️  Latest Android NDK version could not be detected - skipped."
fi

DESIRED_AVDS=(
    "Pixel_5_API_36"
    "Pixel_5_API_35"
    "Pixel_5_API_34"
    "Pixel_9_API_36"
    "Pixel_9_API_35"
    "Pixel_9_API_34"
    "Tablet_7_API_36"
    "Tablet_7_API_35"
    "Tablet_7_API_34"
    "Tablet_10_API_36"
    "Tablet_10_API_35"
    "Tablet_10_API_34"
)

echo "==> Removing emulators not listed in the script..."
sync_avds "${DESIRED_AVDS[@]}"

DEVICE_CATALOG="$(get_device_catalog)"

PIXEL5_DEVICE="$(resolve_device "$DEVICE_CATALOG" pixel_5 pixel 2>/dev/null || true)"
if [[ -z "$PIXEL5_DEVICE" ]]; then
    echo "❌ No suitable device profile found for Pixel_5 AVDs."
    exit 1
fi

PIXEL9_DEVICE="$(resolve_device "$DEVICE_CATALOG" pixel_9 pixel_9_pro pixel_9_pro_xl pixel_8_pro pixel_7_pro pixel_6_pro pixel_xl pixel_5 pixel 2>/dev/null || true)"
if [[ -z "$PIXEL9_DEVICE" ]]; then
    echo "❌ No suitable device profile found for Pixel_9 AVDs."
    exit 1
fi
if [[ "$PIXEL9_DEVICE" != "pixel_9" ]]; then
    echo "ℹ️  Device 'pixel_9' is not available, using fallback '$PIXEL9_DEVICE' for Pixel_9 AVDs."
fi

TABLET7_DEVICE="$(resolve_device "$DEVICE_CATALOG" '7in WSVGA (Tablet)' 'Nexus 7' pixel_c 2>/dev/null || true)"
if [[ -z "$TABLET7_DEVICE" ]]; then
    echo "❌ No suitable device profile found for 7-inch tablet AVDs."
    exit 1
fi

TABLET10_DEVICE="$(resolve_device "$DEVICE_CATALOG" '10.1in WXGA (Tablet)' 'Nexus 10' pixel_c 2>/dev/null || true)"
if [[ -z "$TABLET10_DEVICE" ]]; then
    echo "❌ No suitable device profile found for 10-inch tablet AVDs."
    exit 1
fi

create_avd "Pixel_5_API_36" "system-images;android-36;google_apis;x86_64" "$PIXEL5_DEVICE"
create_avd "Pixel_5_API_35" "system-images;android-35;google_apis;x86_64" "$PIXEL5_DEVICE"
create_avd "Pixel_5_API_34" "system-images;android-34;google_apis;x86_64" "$PIXEL5_DEVICE"

create_avd "Pixel_9_API_36" "system-images;android-36;google_apis;x86_64" "$PIXEL9_DEVICE"
create_avd "Pixel_9_API_35" "system-images;android-35;google_apis;x86_64" "$PIXEL9_DEVICE"
create_avd "Pixel_9_API_34" "system-images;android-34;google_apis;x86_64" "$PIXEL9_DEVICE"

create_avd "Tablet_7_API_36" "system-images;android-36;google_apis;x86_64" "$TABLET7_DEVICE"
create_avd "Tablet_7_API_35" "system-images;android-35;google_apis;x86_64" "$TABLET7_DEVICE"
create_avd "Tablet_7_API_34" "system-images;android-34;google_apis;x86_64" "$TABLET7_DEVICE"

create_avd "Tablet_10_API_36" "system-images;android-36;google_apis;x86_64" "$TABLET10_DEVICE"
create_avd "Tablet_10_API_35" "system-images;android-35;google_apis;x86_64" "$TABLET10_DEVICE"
create_avd "Tablet_10_API_34" "system-images;android-34;google_apis;x86_64" "$TABLET10_DEVICE"

declare -A avd_params=(
    ["hw.keyboard"]="yes"
    ["hw.ramSize"]="4096"
    ["hw.gpu.enabled"]="yes"
    ["hw.gpu.mode"]="auto"
)

for avd in "${DESIRED_AVDS[@]}"; do
    set_avd_config "$avd" avd_params
done

echo "==> Setting up Flutter on Android SDK..."
"$FLUTTER_DIR/bin/flutter" config --android-sdk "$ANDROID_HOME"

JAVA_17_BIN="/usr/lib/jvm/java-17-openjdk-amd64/bin/java"
if [[ -x "$JAVA_17_BIN" ]]; then
    sudo update-alternatives --install /usr/bin/java java "$JAVA_17_BIN" 1
    sudo update-alternatives --set java "$JAVA_17_BIN"
fi

echo "==> Running flutter doctor..."
"$FLUTTER_DIR/bin/flutter" doctor
flutter_doctor_exit_code=$?
if [[ $flutter_doctor_exit_code -ne 0 ]]; then
    echo "❌ flutter doctor failed with exit code $flutter_doctor_exit_code"
    exit $flutter_doctor_exit_code
fi

echo "==> Downloading more SDKs for Android, Web, Linux..."
"$FLUTTER_DIR/bin/flutter" precache --android --web --linux

echo
echo "✅ Installation complete!"
echo "Open a new terminal or run: source ~/.bashrc"
echo "📱 Managed emulators present:"
for avd in "${DESIRED_AVDS[@]}"; do
    if avd_exists "$avd"; then
        echo "   - $avd"
    fi
done

else
    # ====== UNINSTALL MODE ======
    echo ""
    echo "==> Starting uninstallation..." 

    # Remove Flutter directory
    if [[ -d "$FLUTTER_DIR" ]]; then
        echo "==> Removing Flutter installation: $FLUTTER_DIR"
        rm -rf "$FLUTTER_DIR"
        if [[ ! -d "$FLUTTER_DIR" ]]; then
            echo "✅ Flutter removed."
        else
            echo "❌ Failed to remove Flutter directory. It may be in use."
        fi
    else
        echo "ℹ️  Flutter not found at $FLUTTER_DIR"
    fi

    # Remove Android SDK directory
    if [[ -d "$ANDROID_SDK_DIR" ]]; then
        echo "==> Removing Android SDK: $ANDROID_SDK_DIR"
        rm -rf "$ANDROID_SDK_DIR"
        if [[ ! -d "$ANDROID_SDK_DIR" ]]; then
            echo "✅ Android SDK removed."
        else
            echo "❌ Failed to remove Android SDK directory. It may be in use."
        fi
    else
        echo "ℹ️  Android SDK not found at $ANDROID_SDK_DIR"
    fi

    # Remove managed AVDs
    avd_root="$HOME/.android/avd"
    if [[ -d "$avd_root" ]]; then
        echo "==> Removing managed Android Virtual Devices..."
        local_desired_avds=("Pixel_5_API_36" "Pixel_5_API_35" "Pixel_5_API_34" "Pixel_9_API_36" "Pixel_9_API_35" "Pixel_9_API_34" "Tablet_7_API_36" "Tablet_7_API_35" "Tablet_7_API_34" "Tablet_10_API_36" "Tablet_10_API_35" "Tablet_10_API_34")
        for avd in "${local_desired_avds[@]}"; do
            avd_dir="$avd_root/$avd"
            avd_ini="$avd_root/${avd}.ini"
            [[ -d "$avd_dir" ]] && rm -rf "$avd_dir" && echo "✅ Removed AVD: $avd"
            [[ -f "$avd_ini" ]] && rm -f "$avd_ini"
        done
    fi

    # Remove additional home folders and files introduced by setup (user request)
    echo "==> Removing additional home directories and files (.android, .config/flutter, .dart-tool, android-sdk-backups, .flutter)..."
    if [[ -d "$HOME/.android" ]]; then
        rm -rf "$HOME/.android" && echo "✅ Removed $HOME/.android" || echo "❌ Failed to remove $HOME/.android"
    fi
    if [[ -d "$HOME/.config/flutter" ]]; then
        rm -rf "$HOME/.config/flutter" && echo "✅ Removed $HOME/.config/flutter" || echo "❌ Failed to remove $HOME/.config/flutter"
    fi
    if [[ -d "$HOME/.dart-tool" ]]; then
        rm -rf "$HOME/.dart-tool" && echo "✅ Removed $HOME/.dart-tool" || echo "❌ Failed to remove $HOME/.dart-tool"
    fi
    if [[ -d "$HOME/android-sdk-backups" ]]; then
        rm -rf "$HOME/android-sdk-backups" && echo "✅ Removed $HOME/android-sdk-backups" || echo "❌ Failed to remove $HOME/android-sdk-backups"
    fi
    if [[ -f "$HOME/.flutter" ]]; then
        rm -f "$HOME/.flutter" && echo "✅ Removed $HOME/.flutter" || echo "❌ Failed to remove $HOME/.flutter"
    fi

    # Remove from ~/.bashrc
    echo "==> Cleaning up ~/.bashrc..."
    if [[ -f "$BASHRC" ]]; then
        sed -i '/CHROME_EXECUTABLE/d' "$BASHRC"
        sed -i '/ANDROID_HOME/d' "$BASHRC"
        sed -i '/ANDROID_SDK_ROOT/d' "$BASHRC"
        sed -i '/PATH.*flutter/d' "$BASHRC"
        sed -i '/PATH.*android/d' "$BASHRC"
        echo "✅ ~/.bashrc cleaned."
    fi

    # Remove exported variables from current session
    unset CHROME_EXECUTABLE
    unset ANDROID_HOME
    unset ANDROID_SDK_ROOT

    echo ""
    echo "✅ Uninstallation complete! Open a new terminal for changes to take effect."

fi
