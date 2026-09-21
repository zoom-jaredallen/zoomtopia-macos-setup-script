#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/update-policy.sh
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
current_macos_major() { printf '%s\n' "$MAJOR"; }
current_boot() { echo first-boot; }
software_update() {
    printf '%s\n' "$*" >> "$ROOT/calls"
    [[ "$*" == '--list' ]] || return 99
    printf '%s\n' "$LISTING"
    return "$COMMAND_STATUS"
}
warn_step() { RESULT=warning; MESSAGE="$4"; }
fail_step() { RESULT=failed; MESSAGE="$4"; }
emit() { RESULT="$4"; MESSAGE="$5"; }
check() {
    local name="$1" expected="$2"
    RESULT=''; MESSAGE=''; ACTION_REQUIRED=0
    : > "$ROOT/calls"
    install_macos_updates "$ROOT" > "$ROOT/output"
    [[ "$RESULT" == "$expected" ]] || { echo "FAIL: $name expected $expected, got $RESULT ($MESSAGE)"; exit 1; }
    if [[ "$expected" == actionRequired ]]; then
        [[ "$ACTION_REQUIRED" == 1 && "$MESSAGE" == *'Open Software Update'* && "$MESSAGE" == *'same-major'* ]] || { echo "FAIL: $name lacks explicit handoff"; exit 1; }
        [[ "$MESSAGE" != *'Restart this Mac'* ]] || { echo "FAIL: available restart action became pending reboot"; exit 1; }
    fi
    [[ $(cat "$ROOT/calls") == '--list' || ! -s "$ROOT/calls" ]] || { echo "FAIL: $name called a mutating softwareupdate command"; exit 1; }
    echo "PASS: $name"
}
MAJOR=15; COMMAND_STATUS=0
CURRENT='* Label: macOS Sequoia 15.7.1-24G231
    Title: macOS Sequoia 15.7.1, Version: 15.7.1, Size: 2893742KiB, Recommended: YES, Action: restart,'
UPGRADE='* Label: macOS Tahoe 26.0-25A354
    Title: macOS Tahoe 26.0, Version: 26.0, Size: 12500000KiB, Recommended: YES, Action: restart,'
SAFARI='* Label: Safari26.0SequoiaAuto-26.0
    Title: Safari, Version: 26.0, Size: 180000KiB, Recommended: YES,'
LISTING="$CURRENT"; check 'same-major update requires handoff' actionRequired
LISTING="$UPGRADE"; check 'next-major upgrade alone is excluded' passed
[[ "$MESSAGE" == *'excluded'* ]] || exit 1
LISTING="$UPGRADE
$SAFARI"; check 'Safari alongside next-major upgrade still needs action' actionRequired
LISTING="$CURRENT
$UPGRADE"; check 'mixed current and next major requires handoff' actionRequired
LISTING="$SAFARI"; check 'recommended non-OS update needs action' actionRequired
LISTING='Software Update Tool

Finding available software
Software Update found the following new or updated software:
* Label: Command Line Tools for Xcode-16.4
    Title: Command Line Tools for Xcode, Version: 16.4, Size: 750000KiB, Recommended: YES,'
check 'headers and labels with spaces remain one stanza' actionRequired
LISTING='* Label: Optional Tools
    Title: Optional Tools, Version: 1.0, Size: 123KiB, Recommended: NO,'
check 'optional non-OS offer does not block readiness' passed
LISTING='* Label: incomplete recommendation
    Title: Safari, Version: 26.0, Size: 123KiB,'
check 'missing recommendation blocks readiness' warning
LISTING='Software Update Tool

Finding available software
No new software available.'; check 'clean check passes' passed
printf '%s\n' first-boot > "$ROOT/updates-boot"
printf '%s\n' retained > "$ROOT/unrelated"
check 'stale boot marker cannot imply pending reboot' passed
[[ $(cat "$ROOT/updates-boot") == first-boot && $(cat "$ROOT/unrelated") == retained ]] || exit 1
LISTING='* Label: missing metadata'; check 'incomplete stanza requires retry' warning
LISTING="$CURRENT
* Label: unknown"; check 'malformed extra stanza blocks readiness' warning
LISTING='No new software available.
* Label: contradictory'; check 'contradictory listing blocks readiness' warning
LISTING='Something unexpected'; check 'unknown output requires retry' warning
LISTING=''; check 'empty output requires retry' warning
LISTING='* Label: invalid version
    Title: macOS Sequoia, Version: unknown, Size: 12KiB, Recommended: YES,'; check 'invalid OS version blocks readiness' warning
LISTING='* Label: old system
    Title: macOS Sonoma, Version: 14.7, Size: 12KiB, Recommended: YES,'; check 'older OS offer is unexpected' warning
LISTING="$CURRENT"; COMMAND_STATUS=1; check 'failed command requires retry' warning
COMMAND_STATUS=0; MAJOR=unknown; check 'unknown installed major requires retry' warning
