#!/bin/bash
set -euo pipefail
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_PATH="${1:-$PROJECT_ROOT/dist/Zoomtopia Setup.app}"
configuration=$(/usr/bin/plutil -extract ZoomtopiaBuildConfiguration raw -o - "$APP_PATH/Contents/Info.plist")
[[ "$configuration" == release ]] || { echo "Development builds cannot be packaged for release" >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/bin/xcrun stapler validate "$APP_PATH"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"
for binary in "$APP_PATH/Contents/MacOS/Zoomtopia Setup" "$APP_PATH/Contents/Resources/PayloadVerifier"; do
    /usr/bin/lipo "$binary" -verify_arch x86_64 arm64
done
"$APP_PATH/Contents/Resources/PayloadVerifier" --validate-resources
ZIP_PATH="$PROJECT_ROOT/dist/Zoomtopia-Setup.zip"
/bin/rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
(cd "$PROJECT_ROOT/dist" && /usr/bin/shasum -a 256 Zoomtopia-Setup.zip > SHA256SUMS)
echo "Verified release archive: $ZIP_PATH"
