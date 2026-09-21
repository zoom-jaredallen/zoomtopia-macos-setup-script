#!/bin/bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_PATH="${1:-$PROJECT_ROOT/dist/Zoomtopia Setup.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "App not found: $APP_PATH" >&2
    exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "Set NOTARY_PROFILE to a notarytool keychain profile name." >&2
    exit 1
fi

configuration=$(/usr/bin/plutil -extract ZoomtopiaBuildConfiguration raw -o - "$APP_PATH/Contents/Info.plist")
[[ "$configuration" == release ]] || { echo "Rebuild with BUILD_CONFIGURATION=release before notarization" >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
/bin/mkdir -p "$PROJECT_ROOT/dist/notarization"
RECORDS=$(/usr/bin/mktemp -d "$PROJECT_ROOT/dist/notarization/submission.XXXXXX")
/usr/bin/ditto "$APP_PATH/Contents/Info.plist" "$RECORDS/Info.plist"
/usr/bin/codesign -d --verbose=4 "$APP_PATH" > "$RECORDS/signature.txt" 2>&1
ZIP_PATH="$RECORDS/Zoomtopia-Setup-notarization.zip"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
/usr/bin/shasum -a 256 "$ZIP_PATH" > "$RECORDS/SHA256SUMS"
notary_command() { /usr/bin/xcrun notarytool "$@"; }
source "$PROJECT_ROOT/Scripts/notary-submit.sh"
echo "Notarization attempt records: $RECORDS"
submit_for_notarization "$ZIP_PATH" "$NOTARY_PROFILE" "$RECORDS"
/usr/bin/xcrun stapler staple "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"

echo "Notarized and stapled: $APP_PATH"
"$PROJECT_ROOT/Scripts/package-release.sh" "$APP_PATH"
