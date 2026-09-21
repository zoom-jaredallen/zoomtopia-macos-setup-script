#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/update-policy.sh
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
BOOT=first-boot
CALLS=0
current_boot() { echo "$BOOT"; }
software_update() {
    if [[ "$1" == "--list" ]]; then echo '* Label: macOS-update'; return 0; fi
    echo 'Done. Restart required.'
    CALLS=$((CALLS + 1))
}
warn_step() { RESULT=warning; }
fail_step() { RESULT=failed; }
emit() { RESULT="$4"; }
RESULT=""
install_macos_updates "$ROOT"
[[ "$RESULT" == warning && -f "$ROOT/updates-boot" ]] || { echo 'FAIL: restart was not recorded'; exit 1; }
install_macos_updates "$ROOT"
[[ "$RESULT" == warning && "$CALLS" == 1 ]] || { echo 'FAIL: same-boot rerun ignored pending restart'; exit 1; }
BOOT=second-boot
software_update() { echo 'No new software available.'; }
install_macos_updates "$ROOT"
[[ "$RESULT" == passed && ! -f "$ROOT/updates-boot" ]] || { echo 'FAIL: post-reboot clean check did not pass'; exit 1; }
echo 'PASS: update restart persists until a new boot and clean update check'
