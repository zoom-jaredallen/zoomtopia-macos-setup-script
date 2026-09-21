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

ZIP_PATH="$PROJECT_ROOT/dist/Zoomtopia-Setup-notarization.zip"
/bin/rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
/usr/bin/xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"

echo "Notarized and stapled: $APP_PATH"
"$PROJECT_ROOT/Scripts/package-release.sh" "$APP_PATH"
