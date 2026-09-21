#!/bin/bash

set -uo pipefail

PAYLOAD_ROOT=""
STATUS_FILE=""
LOG_FILE="/var/log/zoomtopia-setup.log"
TOTAL=11
FAILURES=0
WARNINGS=0
ACTION_REQUIRED=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --payload) PAYLOAD_ROOT="$2"; shift 2 ;;
        --status) STATUS_FILE="$2"; shift 2 ;;
        --log) LOG_FILE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 64 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "This setup must run as root." >&2
    exit 77
fi

if [[ -z "$PAYLOAD_ROOT" || -z "$STATUS_FILE" ]]; then
    echo "Usage: bootstrap.sh --payload PATH --status PATH [--log PATH]" >&2
    exit 64
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
exec >> "$LOG_FILE" 2>&1

echo ""
echo "===== Zoomtopia setup started $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/}
    printf '%s' "$value"
}

emit() {
    local index="$1" id="$2" title="$3" state="$4" detail="${5:-}"
    printf '{"id":"%s","title":"%s","state":"%s","detail":"%s","index":%d,"total":%d}\n' \
        "$(json_escape "$id")" "$(json_escape "$title")" "$state" "$(json_escape "$detail")" "$index" "$TOTAL" >> "$STATUS_FILE"
    chmod 644 "$STATUS_FILE" 2>/dev/null || true
    echo "[$index/$TOTAL] $title: $state${detail:+ — $detail}"
}

fail_step() {
    emit "$1" "$2" "$3" failed "$4"
    FAILURES=$((FAILURES + 1))
}

warn_step() {
    emit "$1" "$2" "$3" warning "$4"
    WARNINGS=$((WARNINGS + 1))
}

config_raw() {
    local key="$1" default_value="${2:-}"
    local value
    value=$(/usr/bin/plutil -extract "$key" raw -o - "$CONFIG_FILE" 2>/dev/null) || value="$default_value"
    printf '%s' "$value"
}

is_true() {
    case "$1" in
        true|TRUE|True|1|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

console_user() {
    /usr/bin/stat -f '%Su' /dev/console
}

user_home() {
    /usr/bin/dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}'
}

run_as_user() {
    local user="$1" uid
    uid=$(/usr/bin/id -u "$user") || return 1
    /bin/launchctl asuser "$uid" /usr/bin/sudo -u "$user" "$@"
}

resolve_package() {
    local base="$1" arch="$2" candidate
    for candidate in \
        "$PAYLOAD_ROOT/Installers/${base}-${arch}.pkg" \
        "$PAYLOAD_ROOT/Installers/${base}.pkg"; do
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

install_package_if_changed() {
    local package_path="$1" state_name="$2" app_path="$3"
    local package_hash state_file
    package_hash=$(/usr/bin/shasum -a 256 "$package_path" | /usr/bin/awk '{print $1}') || return 1
    state_file="/var/db/com.zoom.zoomtopiasetup/${state_name}.sha256"
    mkdir -p "$(dirname "$state_file")"

    if [[ -d "$app_path" && -f "$state_file" && "$(cat "$state_file")" == "$package_hash" ]]; then
        return 10
    fi

    if is_true "$(config_raw requireSignedPackages true)"; then
        /usr/sbin/pkgutil --check-signature "$package_path" || return 1
    fi
    /usr/sbin/installer -pkg "$package_path" -target / || return 1
    [[ -d "$app_path" ]] || return 1
    printf '%s\n' "$package_hash" > "$state_file"
    chmod 600 "$state_file"
    return 0
}

CONFIG_FILE="$PAYLOAD_ROOT/config/setup-config.json"
ARCH=$(/usr/bin/uname -m)
case "$ARCH" in
    arm64) PACKAGE_ARCH="arm64" ;;
    x86_64) PACKAGE_ARCH="x86_64" ;;
    *) PACKAGE_ARCH="$ARCH" ;;
esac

# 1. Validate
emit 1 validate "Validate Mac" running "Checking architecture, user, and power"
CURRENT_USER=$(console_user)
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    fail_step 1 validate "Validate Mac" "Unsupported architecture: $ARCH"
elif [[ "$CURRENT_USER" == "root" || "$CURRENT_USER" == "loginwindow" || -z "$CURRENT_USER" ]]; then
    fail_step 1 validate "Validate Mac" "Log into the target user account before running setup"
elif [[ ! -f "$CONFIG_FILE" ]]; then
    fail_step 1 validate "Validate Mac" "Missing config/setup-config.json"
elif is_true "$(config_raw requireACPower true)" && ! /usr/bin/pmset -g batt | /usr/bin/grep -q "AC Power"; then
    fail_step 1 validate "Validate Mac" "Connect the Mac to AC power and run setup again"
else
    emit 1 validate "Validate Mac" passed "$ARCH; target user $CURRENT_USER"
fi

if [[ $FAILURES -gt 0 ]]; then
    emit 2 payload "Verify USB payload" skipped "Blocked by validation failure"
    emit 3 chrome "Install Google Chrome" skipped "Blocked by validation failure"
    emit 4 zoom "Install Zoom Workplace" skipped "Blocked by validation failure"
    emit 5 zoom-config "Configure Zoom Workplace" skipped "Blocked by validation failure"
    emit 6 trackpad "Configure trackpad" skipped "Blocked by validation failure"
    emit 7 wallpaper "Set Zoomtopia wallpaper" skipped "Blocked by validation failure"
    emit 8 aliases "Create desktop icons" skipped "Blocked by validation failure"
    emit 9 privacy "Stage Zoom privacy permissions" skipped "Blocked by validation failure"
    emit 10 updates "Install macOS updates" skipped "Blocked by validation failure"
    emit 11 verify "Final verification" failed "Preflight validation failed"
    exit 1
fi

# 2. Verify payload checksums
emit 2 payload "Verify USB payload" running "Checking package integrity"
if [[ ! -f "$PAYLOAD_ROOT/checksums.txt" ]]; then
    fail_step 2 payload "Verify USB payload" "Missing checksums.txt; run scripts/generate-checksums.sh"
elif (cd "$PAYLOAD_ROOT" && /usr/bin/shasum -a 256 -c checksums.txt); then
    emit 2 payload "Verify USB payload" passed "All listed files match"
else
    fail_step 2 payload "Verify USB payload" "One or more payload files failed checksum verification"
fi

if [[ $FAILURES -gt 0 ]]; then
    emit 3 chrome "Install Google Chrome" skipped "Blocked by payload verification failure"
    emit 4 zoom "Install Zoom Workplace" skipped "Blocked by payload verification failure"
    emit 5 zoom-config "Configure Zoom Workplace" skipped "Blocked by payload verification failure"
    emit 6 trackpad "Configure trackpad" skipped "Blocked by payload verification failure"
    emit 7 wallpaper "Set Zoomtopia wallpaper" skipped "Blocked by payload verification failure"
    emit 8 aliases "Create desktop icons" skipped "Blocked by payload verification failure"
    emit 9 privacy "Stage Zoom privacy permissions" skipped "Blocked by payload verification failure"
    emit 10 updates "Install macOS updates" skipped "Blocked by payload verification failure"
    emit 11 verify "Final verification" failed "Payload integrity verification failed"
    exit 1
fi

# 3. Chrome
emit 3 chrome "Install Google Chrome" running "Selecting package for $PACKAGE_ARCH"
CHROME_PACKAGE=$(resolve_package "GoogleChrome" "$PACKAGE_ARCH") || CHROME_PACKAGE=""
if [[ -z "$CHROME_PACKAGE" ]]; then
    fail_step 3 chrome "Install Google Chrome" "No GoogleChrome-${PACKAGE_ARCH}.pkg or GoogleChrome.pkg found"
else
    install_package_if_changed "$CHROME_PACKAGE" chrome "/Applications/Google Chrome.app"
    result=$?
    if [[ $result -eq 10 ]]; then
        emit 3 chrome "Install Google Chrome" skipped "Already installed from this payload"
    elif [[ $result -eq 0 ]]; then
        version=$(/usr/bin/defaults read "/Applications/Google Chrome.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)
        emit 3 chrome "Install Google Chrome" passed "Installed${version:+ version $version}"
    else
        fail_step 3 chrome "Install Google Chrome" "Package installation failed"
    fi
fi

# 4. Zoom
emit 4 zoom "Install Zoom Workplace" running "Selecting package for $PACKAGE_ARCH"
ZOOM_PACKAGE=$(resolve_package "ZoomWorkplace" "$PACKAGE_ARCH") || ZOOM_PACKAGE=""
ZOOM_APP="/Applications/zoom.us.app"
[[ -d "/Applications/Zoom Workplace.app" ]] && ZOOM_APP="/Applications/Zoom Workplace.app"
if [[ -z "$ZOOM_PACKAGE" ]]; then
    fail_step 4 zoom "Install Zoom Workplace" "No ZoomWorkplace-${PACKAGE_ARCH}.pkg or ZoomWorkplace.pkg found"
else
    install_package_if_changed "$ZOOM_PACKAGE" zoom "$ZOOM_APP"
    result=$?
    if [[ $result -eq 10 ]]; then
        emit 4 zoom "Install Zoom Workplace" skipped "Already installed from this payload"
    elif [[ $result -eq 0 ]]; then
        [[ -d "/Applications/Zoom Workplace.app" ]] && ZOOM_APP="/Applications/Zoom Workplace.app"
        version=$(/usr/bin/defaults read "$ZOOM_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)
        emit 4 zoom "Install Zoom Workplace" passed "Installed${version:+ version $version}"
    else
        fail_step 4 zoom "Install Zoom Workplace" "Package installation failed"
    fi
fi

# 5. Zoom managed configuration
emit 5 zoom-config "Configure Zoom Workplace" running "Applying managed preferences"
ZOOM_CONFIG_NAME=$(config_raw zoomConfigurationFilename us.zoom.config.plist)
ZOOM_CONFIG="$PAYLOAD_ROOT/config/$ZOOM_CONFIG_NAME"
if [[ ! -f "$ZOOM_CONFIG" ]]; then
    emit 5 zoom-config "Configure Zoom Workplace" skipped "No Zoom configuration plist supplied"
elif /usr/bin/plutil -lint "$ZOOM_CONFIG" >/dev/null; then
    /usr/bin/install -o root -g wheel -m 644 "$ZOOM_CONFIG" /Library/Preferences/us.zoom.config.plist
    emit 5 zoom-config "Configure Zoom Workplace" passed "Installed /Library/Preferences/us.zoom.config.plist"
else
    fail_step 5 zoom-config "Configure Zoom Workplace" "The Zoom configuration plist is invalid"
fi

# 6. Trackpad
emit 6 trackpad "Configure trackpad" running "Setting bottom-right secondary click for $CURRENT_USER"
if ! is_true "$(config_raw configureTrackpad true)"; then
    emit 6 trackpad "Configure trackpad" skipped "Disabled in configuration"
else
    trackpad_ok=true
    for domain in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
        run_as_user "$CURRENT_USER" /usr/bin/defaults write "$domain" TrackpadCornerSecondaryClick -int 2 || trackpad_ok=false
        run_as_user "$CURRENT_USER" /usr/bin/defaults write "$domain" TrackpadRightClick -bool false || trackpad_ok=false
    done
    run_as_user "$CURRENT_USER" /usr/bin/defaults write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true || trackpad_ok=false
    /usr/bin/pkill -u "$(/usr/bin/id -u "$CURRENT_USER")" cfprefsd 2>/dev/null || true
    if $trackpad_ok; then
        emit 6 trackpad "Configure trackpad" passed "Bottom-right corner enabled"
    else
        warn_step 6 trackpad "Configure trackpad" "Preference could not be fully applied; log out and try again"
    fi
fi

# 7. Wallpaper
emit 7 wallpaper "Set Zoomtopia wallpaper" running "Installing desktop background"
WALLPAPER_NAME=$(config_raw wallpaperFilename wallpaper.jpg)
WALLPAPER_SOURCE="$PAYLOAD_ROOT/assets/$WALLPAPER_NAME"
WALLPAPER_TARGET="/Library/Desktop Pictures/Zoomtopia-${WALLPAPER_NAME}"
if [[ ! -f "$WALLPAPER_SOURCE" ]]; then
    fail_step 7 wallpaper "Set Zoomtopia wallpaper" "Missing assets/$WALLPAPER_NAME"
else
    /usr/bin/install -o root -g wheel -m 644 "$WALLPAPER_SOURCE" "$WALLPAPER_TARGET"
    wallpaper_script="tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$WALLPAPER_TARGET\""
    if run_as_user "$CURRENT_USER" /usr/bin/osascript -e "$wallpaper_script"; then
        emit 7 wallpaper "Set Zoomtopia wallpaper" passed "Applied to all desktops"
    else
        warn_step 7 wallpaper "Set Zoomtopia wallpaper" "Image installed, but macOS requires wallpaper approval"
    fi
fi

# 8. Desktop aliases (symbolic links preserve the application icon and are idempotent)
emit 8 aliases "Create desktop icons" running "Adding Chrome and Zoom to the Desktop"
DESKTOP="$(user_home "$CURRENT_USER")/Desktop"
alias_errors=0
mkdir -p "$DESKTOP"
for spec in "Google Chrome:/Applications/Google Chrome.app" "Zoom Workplace:$ZOOM_APP"; do
    name="${spec%%:*}"
    target="${spec#*:}"
    link="$DESKTOP/$name"
    if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
        continue
    elif [[ -e "$link" || -L "$link" ]]; then
        echo "Refusing to overwrite existing Desktop item: $link"
        alias_errors=$((alias_errors + 1))
        continue
    fi
    /bin/ln -s "$target" "$link" || alias_errors=$((alias_errors + 1))
done
/usr/sbin/chown -h "$CURRENT_USER":staff "$DESKTOP/Google Chrome" "$DESKTOP/Zoom Workplace" 2>/dev/null || true
if [[ $alias_errors -eq 0 ]]; then
    emit 8 aliases "Create desktop icons" passed "Chrome and Zoom icons are ready"
else
    warn_step 8 aliases "Create desktop icons" "An existing Desktop item was preserved; see the log"
fi

# 9. Privacy profile. macOS requires local user approval when no MDM is present.
emit 9 privacy "Stage Zoom privacy permissions" running "Preparing the user-approved profile"
PRIVACY_PROFILE_NAME=$(config_raw privacyProfileFilename ZoomPrivacy.mobileconfig)
PRIVACY_PROFILE="$PAYLOAD_ROOT/config/$PRIVACY_PROFILE_NAME"
if [[ ! -f "$PRIVACY_PROFILE" ]]; then
    warn_step 9 privacy "Stage Zoom privacy permissions" "No privacy profile supplied; approve Camera, Microphone, and Screen Recording manually"
    ACTION_REQUIRED=1
else
    PROFILE_DEST="$DESKTOP/$PRIVACY_PROFILE_NAME"
    /usr/bin/install -o "$CURRENT_USER" -g staff -m 644 "$PRIVACY_PROFILE" "$PROFILE_DEST"
    run_as_user "$CURRENT_USER" /usr/bin/open "$PROFILE_DEST" || true
    emit 9 privacy "Stage Zoom privacy permissions" actionRequired "Install the opened profile, then approve Zoom in Privacy & Security"
    ACTION_REQUIRED=1
fi

# 10. macOS updates
emit 10 updates "Install macOS updates" running "Checking Apple Software Update"
if ! is_true "$(config_raw installOSUpdates true)"; then
    emit 10 updates "Install macOS updates" skipped "Disabled in configuration"
elif /usr/sbin/softwareupdate --install --all --verbose; then
    if [[ -f /var/run/reboot-required ]]; then
        emit 10 updates "Install macOS updates" warning "Updates installed; restart required"
        WARNINGS=$((WARNINGS + 1))
    else
        emit 10 updates "Install macOS updates" passed "All available updates processed"
    fi
else
    warn_step 10 updates "Install macOS updates" "Some updates need a volume-owner password or restart; see the log"
fi

# 11. Verification
emit 11 verify "Final verification" running "Checking installed applications and configuration"
verification_errors=0
[[ -d "/Applications/Google Chrome.app" ]] || verification_errors=$((verification_errors + 1))
[[ -d "$ZOOM_APP" ]] || verification_errors=$((verification_errors + 1))
[[ -f "$WALLPAPER_TARGET" ]] || verification_errors=$((verification_errors + 1))
if [[ $verification_errors -gt 0 || $FAILURES -gt 0 ]]; then
    fail_step 11 verify "Final verification" "$FAILURES setup step(s) failed; $verification_errors required item(s) missing"
elif [[ $ACTION_REQUIRED -gt 0 ]]; then
    emit 11 verify "Final verification" actionRequired "Automated setup passed; complete Zoom privacy approval"
elif [[ $WARNINGS -gt 0 ]]; then
    emit 11 verify "Final verification" warning "Setup passed with $WARNINGS warning(s)"
else
    emit 11 verify "Final verification" passed "Mac is ready for Zoomtopia"
fi

echo "===== Zoomtopia setup finished $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
[[ $FAILURES -eq 0 ]]
