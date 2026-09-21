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
