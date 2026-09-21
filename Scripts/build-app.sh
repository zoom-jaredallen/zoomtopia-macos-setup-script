#!/bin/bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_ROOT"

APP_DIR="$PROJECT_ROOT/dist/Zoomtopia Setup.app"
CONTENTS="$APP_DIR/Contents"
DIST_PAYLOAD="$PROJECT_ROOT/dist/ZoomtopiaPayload"
BUILD_DIR=$(mktemp -d)
trap '/bin/rm -rf "$BUILD_DIR"' EXIT

echo "Compiling Apple Silicon binary..."
/usr/bin/swiftc -O -target arm64-apple-macosx13.0 \
    "$PROJECT_ROOT"/Sources/ZoomtopiaSetupApp/*.swift \
    -o "$BUILD_DIR/ZoomtopiaSetup-arm64"

echo "Compiling Intel binary..."
/usr/bin/swiftc -O -target x86_64-apple-macosx13.0 \
    "$PROJECT_ROOT"/Sources/ZoomtopiaSetupApp/*.swift \
    -o "$BUILD_DIR/ZoomtopiaSetup-x86_64"

/usr/bin/lipo -create \
    "$BUILD_DIR/ZoomtopiaSetup-arm64" \
    "$BUILD_DIR/ZoomtopiaSetup-x86_64" \
    -output "$BUILD_DIR/Zoomtopia Setup"

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
/usr/bin/ditto "$BUILD_DIR/Zoomtopia Setup" "$CONTENTS/MacOS/Zoomtopia Setup"
/usr/bin/ditto "$PROJECT_ROOT/Scripts/bootstrap.sh" "$CONTENTS/Resources/bootstrap.sh"
/usr/bin/ditto "$PROJECT_ROOT/AppResources/zoomtopia-wordmark.png" "$CONTENTS/Resources/zoomtopia-wordmark.png"
/bin/chmod 755 "$CONTENTS/MacOS/Zoomtopia Setup" "$CONTENTS/Resources/bootstrap.sh"

/usr/bin/plutil -create xml1 "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "com.zoom.zoomtopiasetup" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "Zoomtopia Setup" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "Zoomtopia Setup" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string "Zoomtopia Setup" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "1.0.0" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "1" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "13.0" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$CONTENTS/Info.plist"
/usr/bin/plutil -insert NSPrincipalClass -string "NSApplication" "$CONTENTS/Info.plist"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    /usr/bin/codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_DIR"
else
    /usr/bin/codesign --force --sign - "$APP_DIR"
    echo "Built with ad-hoc signing. Set DEVELOPER_ID_APPLICATION to create a distributable signed app."
fi

if [[ -d "$DIST_PAYLOAD" ]]; then
    /bin/rm -rf "$DIST_PAYLOAD"
fi
/usr/bin/ditto "$PROJECT_ROOT/ZoomtopiaPayload" "$DIST_PAYLOAD"

if [[ ! -f "$DIST_PAYLOAD/checksums.txt" ]]; then
    echo "Warning: add installer packages and wallpaper, then run scripts/generate-checksums.sh before deployment."
fi

echo "$APP_DIR"
