#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
swiftc -D STANDALONE_TESTS Sources/SetupCore/*.swift Tests/SetupCoreTests/*.swift Tests/Runner/main.swift -o .build/tests/core-tests
.build/tests/core-tests
/bin/bash Tests/bootstrap-test.sh
/bin/bash Tests/update-policy-test.sh
/bin/bash Tests/signing-swap-test.sh

swiftc -parse-as-library Sources/SetupCore/*.swift Sources/ZoomtopiaSetupApp/Wallpaper.swift Tests/WallpaperTests.swift -o .build/tests/wallpaper-tests
.build/tests/wallpaper-tests

/bin/bash Tests/notarization-test.sh
for configuration in RELEASE DEVELOPMENT; do
    swiftc -parse-as-library -D "ZOOMTOPIA_$configuration" Sources/SetupCore/*.swift Sources/ZoomtopiaSetupApp/SetupController.swift Sources/ZoomtopiaSetupApp/Wallpaper.swift Tests/PreviewTests.swift -o ".build/tests/preview-$configuration"
    env -u ZOOMTOPIA_READY_PREVIEW -u ZOOMTOPIA_PERMISSION_PREVIEW ".build/tests/preview-$configuration" --ready-preview
    env -u ZOOMTOPIA_READY_PREVIEW -u ZOOMTOPIA_PERMISSION_PREVIEW ".build/tests/preview-$configuration" --permission-preview
    ZOOMTOPIA_READY_PREVIEW=1 ".build/tests/preview-$configuration"
    env -u ZOOMTOPIA_READY_PREVIEW ZOOMTOPIA_PERMISSION_PREVIEW=1 ".build/tests/preview-$configuration"
done
