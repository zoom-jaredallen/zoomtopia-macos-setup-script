#!/bin/bash

set -uo pipefail

PAYLOAD_ROOT=""
STATUS_FILE=""
LOG_FILE="/var/log/zoomtopia-setup.log"
RESOURCES=""
MODE="full"
TOTAL=11
FAILURES=0
WARNINGS=0
ACTION_REQUIRED=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --payload) PAYLOAD_ROOT="$2"; shift 2 ;;
        --status) STATUS_FILE="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --resources) RESOURCES="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 64 ;;
    esac
done

[[ "$MODE" == full || "$MODE" == limited ]] || exit 64

if [[ $EUID -ne 0 ]]; then
    echo "This setup must run as root." >&2
    exit 77
fi

if [[ -z "$PAYLOAD_ROOT" || -z "$STATUS_FILE" || -z "$RESOURCES" ]]; then
    echo "Usage: bootstrap.sh --payload PATH --status PATH --resources PATH" >&2
    exit 64
fi

[[ ! -L "$LOG_FILE" ]] || exit 1
touch "$LOG_FILE" || exit 1
chmod 644 "$LOG_FILE" || exit 1
VERIFIER="$RESOURCES/PayloadVerifier"
export ZOOMTOPIA_VERIFIED_CATALOG="$PAYLOAD_ROOT/package-catalog.json"
[[ -x "$VERIFIER" && -d "$PAYLOAD_ROOT/Installers" ]] || exit 1
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
    local event
    event=$(printf '{"id":"%s","title":"%s","state":"%s","detail":"%s","index":%d,"total":%d}' \
        "$(json_escape "$id")" "$(json_escape "$title")" "$state" "$(json_escape "$detail")" "$index" "$TOTAL")
    "$VERIFIER" --event "$STATUS_FILE" "$event" || exit 1
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
    shift
    uid=$(/usr/bin/id -u "$user") || return 1
    /bin/launchctl asuser "$uid" /usr/bin/sudo -u "$user" "$@"
}

CONFIG_FILE="$PAYLOAD_ROOT/config/setup-config.json"
CURRENT_USER=$(console_user)
ZOOM_APP="/Applications/zoom.us.app"
[[ -d "/Applications/Zoom Workplace.app" ]] && ZOOM_APP="/Applications/Zoom Workplace.app"

install_approved_package() {
    local index="$1" id="$2" title="$3" filename="$4" decision package_path state_dir
    emit "$index" "$id" "$title" running "Comparing installed version with the verified installer"
    decision=$("$VERIFIER" --decision "$id") || {
        fail_step "$index" "$id" "$title" "Existing app identity or version needs administrator review"
        return
    }
    if [[ "$decision" == "skip" ]]; then
        emit "$index" "$id" "$title" skipped "Current or newer signed version already installed"
        return
    fi
    package_path="$PAYLOAD_ROOT/Installers/$filename"
    if [[ ! -f "$package_path" ]] || ! "$VERIFIER" --verify-package "$id" "$package_path"; then
        fail_step "$index" "$id" "$title" "Approved package unavailable or invalid; rerun preparation"
        return
    fi
    if ! /usr/sbin/installer -pkg "$package_path" -target /; then
        fail_step "$index" "$id" "$title" "Package installation failed; see the log"
        return
    fi
    decision=$("$VERIFIER" --decision "$id") || decision="invalid"
    if [[ "$decision" != "skip" ]]; then
        fail_step "$index" "$id" "$title" "Installed application did not pass identity, version, and architecture checks"
        return
    fi
    state_dir="/var/db/com.zoom.zoomtopiasetup"
    if [[ -L "$state_dir" ]] || ! mkdir -p "$state_dir" || ! chmod 700 "$state_dir"; then
        fail_step "$index" "$id" "$title" "Cannot record installation state"
    elif [[ -L "$state_dir/$id.sha256" ]] || ! /usr/bin/shasum -a 256 "$package_path" | /usr/bin/awk '{print $1}' > "$state_dir/$id.sha256"; then
        fail_step "$index" "$id" "$title" "Cannot record installation hash"
    else
        chmod 600 "$state_dir/$id.sha256"
        emit "$index" "$id" "$title" passed "Approved version installed and verified"
    fi
}

# The signed helper has already emitted preflight and payload terminal events.
install_approved_package 3 chrome "Install Google Chrome" GoogleChrome.pkg
install_approved_package 4 zoom "Install Zoom Workplace" ZoomWorkplace.pkg
[[ -d "/Applications/Zoom Workplace.app" ]] && ZOOM_APP="/Applications/Zoom Workplace.app"

if [[ "$MODE" == full ]]; then
# 5. Zoom managed configuration
emit 5 zoom-config "Configure Zoom Workplace" running "Applying managed preferences"
ZOOM_CONFIG_NAME=$(config_raw zoomConfigurationFilename us.zoom.config.plist)
ZOOM_CONFIG="$PAYLOAD_ROOT/config/$ZOOM_CONFIG_NAME"
if [[ ! -f "$ZOOM_CONFIG" ]]; then
    emit 5 zoom-config "Configure Zoom Workplace" skipped "No Zoom configuration plist supplied"
elif /usr/bin/plutil -lint "$ZOOM_CONFIG" >/dev/null; then
    if [[ ! -L /Library/Preferences/us.zoom.config.plist ]] && /usr/bin/install -o root -g wheel -m 644 "$ZOOM_CONFIG" /Library/Preferences/us.zoom.config.plist; then
        emit 5 zoom-config "Configure Zoom Workplace" passed "Installed /Library/Preferences/us.zoom.config.plist"
    else
        fail_step 5 zoom-config "Configure Zoom Workplace" "Could not install managed preferences"
    fi
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
    if [[ -L "$WALLPAPER_TARGET" ]] || ! /bin/mkdir -p "/Library/Desktop Pictures" || ! /usr/bin/install -o root -g wheel -m 644 "$WALLPAPER_SOURCE" "$WALLPAPER_TARGET"; then
        fail_step 7 wallpaper "Set Zoomtopia wallpaper" "Could not install wallpaper"
    else
        emit 7 wallpaper "Set Zoomtopia wallpaper" actionRequired "Image installed; the setup app will apply it to this user's displays"
    fi
fi

# 8. Desktop aliases (symbolic links preserve the application icon and are idempotent)
emit 8 aliases "Create desktop icons" running "Adding Chrome and Zoom to the Desktop"
DESKTOP="$(user_home "$CURRENT_USER")/Desktop"
alias_errors=0
run_as_user "$CURRENT_USER" /bin/mkdir -p "$DESKTOP" || alias_errors=$((alias_errors + 1))
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
    run_as_user "$CURRENT_USER" /bin/ln -s "$target" "$link" || alias_errors=$((alias_errors + 1))
done
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
    emit 9 privacy "Stage Zoom privacy permissions" actionRequired "Approve Camera, Microphone, and Screen Recording manually"
else
    PROFILE_DEST="$DESKTOP/$PRIVACY_PROFILE_NAME"
    # Copy as the operator with noclobber. Never replace unrelated Desktop content.
    if [[ -e "$PROFILE_DEST" || -L "$PROFILE_DEST" ]]; then
        if [[ -L "$PROFILE_DEST" ]] || ! /usr/bin/cmp -s "$PRIVACY_PROFILE" "$PROFILE_DEST"; then
            warn_step 9 privacy "Stage Zoom privacy permissions" "Existing Desktop profile preserved; remove the collision and rerun"
        else
            run_as_user "$CURRENT_USER" /usr/bin/open "$PROFILE_DEST" || true
            emit 9 privacy "Stage Zoom privacy permissions" actionRequired "Approve the profile and Zoom privacy permissions"
        fi
    else
        # Root staging is private; expose only a temporary operator-owned copy for transfer.
        PROFILE_TEMP=$(/usr/bin/mktemp "/private/tmp/zoomtopia-profile.XXXXXX")
        if [[ -n "$PROFILE_TEMP" ]] && /usr/bin/install -o "$CURRENT_USER" -g staff -m 600 "$PRIVACY_PROFILE" "$PROFILE_TEMP" && run_as_user "$CURRENT_USER" /bin/bash -c 'set -C; cat "$1" > "$2"' _ "$PROFILE_TEMP" "$PROFILE_DEST"; then
            run_as_user "$CURRENT_USER" /usr/bin/open "$PROFILE_DEST" || true
            emit 9 privacy "Stage Zoom privacy permissions" actionRequired "Approve the profile and Zoom privacy permissions"
        else
            fail_step 9 privacy "Stage Zoom privacy permissions" "Could not stage privacy profile"
        fi
        [[ -z "$PROFILE_TEMP" ]] || /bin/rm -f "$PROFILE_TEMP"
    fi
fi
ACTION_REQUIRED=1

else
    emit 5 zoom-config "Configure Zoom Workplace" skipped "Excluded from limited test"
    emit 6 trackpad "Configure trackpad" skipped "Excluded from limited test"
    emit 7 wallpaper "Set Zoomtopia wallpaper" skipped "Excluded from limited test"
    emit 8 aliases "Create desktop icons" skipped "Excluded from limited test"
    emit 9 privacy "Stage Zoom privacy permissions" actionRequired "Optional guided Zoom tests; limited mode cannot mark this Mac ready"
    ACTION_REQUIRED=1
fi

# 10. macOS updates
emit 10 updates "Check macOS updates" running "Checking Apple Software Update"
if [[ "$MODE" == limited ]] || ! is_true "$(config_raw installOSUpdates true)"; then
    emit 10 updates "Check macOS updates" skipped "Excluded by run mode or configuration"
else
    source "$RESOURCES/update-policy.sh"
    install_macos_updates /var/db/com.zoom.zoomtopiasetup
fi

# 11. Verification
emit 11 verify "Final verification" running "Checking installed applications and configuration"
verification_errors=0
"$VERIFIER" --verify-apps || verification_errors=$((verification_errors + 1))
if [[ "$MODE" == full && ! -f "${WALLPAPER_TARGET:-}" ]]; then verification_errors=$((verification_errors + 1)); fi
if [[ $verification_errors -gt 0 || $FAILURES -gt 0 ]]; then
    fail_step 11 verify "Final verification" "$FAILURES setup step(s) failed; $verification_errors required item(s) missing"
elif [[ $WARNINGS -gt 0 ]]; then
    emit 11 verify "Final verification" warning "Resolve $WARNINGS warning(s), including any restart, and rerun before marking ready"
elif [[ $ACTION_REQUIRED -gt 0 ]]; then
    emit 11 verify "Final verification" actionRequired "Automated setup passed; complete Zoom privacy approval"
else
    emit 11 verify "Final verification" passed "Mac is ready for Zoomtopia"
fi

echo "===== Zoomtopia setup finished $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
[[ $FAILURES -eq 0 ]]
