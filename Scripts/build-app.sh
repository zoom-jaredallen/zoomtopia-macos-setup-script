#!/bin/bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_ROOT"

APP_DIR="$PROJECT_ROOT/dist/Zoomtopia Setup.app"
CONTENTS="$APP_DIR/Contents"
APP_VERSION="${APP_VERSION:-1.2.0}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
APP_BUILD="${APP_BUILD:-}"
case "$BUILD_CONFIGURATION" in
    release|development) ;;
    *) echo "BUILD_CONFIGURATION must be release or development" >&2; exit 64 ;;
esac
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    [[ "$BUILD_CONFIGURATION" == release ]] || { echo "Developer ID builds must use release configuration" >&2; exit 64; }
    [[ -n "$APP_BUILD" ]] || { echo "Set APP_BUILD to a new build number before distribution signing" >&2; exit 64; }
fi
APP_BUILD="${APP_BUILD:-1}"
[[ "$APP_BUILD" =~ ^[1-9][0-9]{0,3}$ ]] || { echo "APP_BUILD must be an integer from 1 to 9999" >&2; exit 64; }
# Always pass a define so Bash 3.2 nounset never expands an empty array.
SWIFT_FLAGS=(-D ZOOMTOPIA_RELEASE)
[[ "$BUILD_CONFIGURATION" != development ]] || SWIFT_FLAGS=(-D ZOOMTOPIA_DEVELOPMENT)
BUILD_DIR=$(mktemp -d)
trap '/bin/rm -rf "$BUILD_DIR"' EXIT

echo "Compiling Apple Silicon binary..."
/usr/bin/swiftc "${SWIFT_FLAGS[@]}" -O -target arm64-apple-macosx13.0 \
    "$PROJECT_ROOT"/Sources/SetupCore/*.swift "$PROJECT_ROOT"/Sources/ZoomtopiaSetupApp/*.swift \
    -o "$BUILD_DIR/ZoomtopiaSetup-arm64"

echo "Compiling Intel binary..."
/usr/bin/swiftc "${SWIFT_FLAGS[@]}" -O -target x86_64-apple-macosx13.0 \
    "$PROJECT_ROOT"/Sources/SetupCore/*.swift "$PROJECT_ROOT"/Sources/ZoomtopiaSetupApp/*.swift \
    -o "$BUILD_DIR/ZoomtopiaSetup-x86_64"

/usr/bin/lipo -create \
    "$BUILD_DIR/ZoomtopiaSetup-arm64" \
    "$BUILD_DIR/ZoomtopiaSetup-x86_64" \
    -output "$BUILD_DIR/Zoomtopia Setup"

for arch in arm64 x86_64; do
    /usr/bin/swiftc "${SWIFT_FLAGS[@]}" -O -target "$arch-apple-macosx13.0" \
        "$PROJECT_ROOT"/Sources/SetupCore/*.swift "$PROJECT_ROOT"/Sources/PayloadVerifier/main.swift \
        -o "$BUILD_DIR/Verifier-$arch"
done
/usr/bin/lipo -create "$BUILD_DIR/Verifier-arm64" "$BUILD_DIR/Verifier-x86_64" -output "$BUILD_DIR/PayloadVerifier"

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
/usr/bin/ditto "$BUILD_DIR/Zoomtopia Setup" "$CONTENTS/MacOS/Zoomtopia Setup"
/usr/bin/ditto "$PROJECT_ROOT/Scripts/bootstrap.sh" "$CONTENTS/Resources/bootstrap.sh"
/usr/bin/ditto "$PROJECT_ROOT/Scripts/update-policy.sh" "$CONTENTS/Resources/update-policy.sh"
/usr/bin/ditto "$PROJECT_ROOT/AppResources/zoomtopia-wordmark.png" "$CONTENTS/Resources/zoomtopia-wordmark.png"
/usr/bin/ditto "$BUILD_DIR/PayloadVerifier" "$CONTENTS/Resources/PayloadVerifier"
/usr/bin/ditto "$PROJECT_ROOT/AppResources/package-catalog.json" "$CONTENTS/Resources/package-catalog.json"
/bin/mkdir -p "$CONTENTS/Resources/Payload/assets" "$CONTENTS/Resources/Payload/config"
for image in "$PROJECT_ROOT"/ZoomtopiaPayload/assets/*.jpg; do
    /usr/bin/ditto "$image" "$CONTENTS/Resources/Payload/assets/$(basename "$image")"
done
for config in setup-config.json us.zoom.config.plist; do
    /usr/bin/ditto "$PROJECT_ROOT/ZoomtopiaPayload/config/$config" "$CONTENTS/Resources/Payload/config/$config"
done
if [[ -f "$PROJECT_ROOT/ZoomtopiaPayload/config/ZoomPrivacy.mobileconfig" ]]; then
    /usr/bin/ditto "$PROJECT_ROOT/ZoomtopiaPayload/config/ZoomPrivacy.mobileconfig" "$CONTENTS/Resources/Payload/config/ZoomPrivacy.mobileconfig"
fi
/usr/bin/swift "$PROJECT_ROOT/Scripts/resource-manifest.swift" "$CONTENTS/Resources/Payload" "$CONTENTS/Resources/resource-manifest.json"
/bin/chmod 755 "$CONTENTS/MacOS/Zoomtopia Setup" "$CONTENTS/Resources/bootstrap.sh" "$CONTENTS/Resources/PayloadVerifier"
"$CONTENTS/Resources/PayloadVerifier" --validate-resources

/usr/bin/plutil -create xml1 "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "com.zoom.zoomtopiasetup" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "Zoomtopia Setup" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "Zoomtopia Setup" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string "Zoomtopia Setup" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "$APP_BUILD" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert ZoomtopiaBuildConfiguration -string "$BUILD_CONFIGURATION" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "13.0" "$CONTENTS/Info.plist"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$CONTENTS/Info.plist"
/usr/bin/plutil -insert NSPrincipalClass -string "NSApplication" "$CONTENTS/Info.plist"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    /usr/bin/codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$CONTENTS/Resources/PayloadVerifier"
    /usr/bin/codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_DIR"
else
    /usr/bin/codesign --force --sign - "$CONTENTS/Resources/PayloadVerifier"
    /usr/bin/codesign --force --sign - "$APP_DIR"
    echo "Built with ad-hoc signing. Set DEVELOPER_ID_APPLICATION to create a distributable signed app."
fi

/usr/bin/codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
