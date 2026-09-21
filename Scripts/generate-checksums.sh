#!/bin/bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PAYLOAD_ROOT="$PROJECT_ROOT/ZoomtopiaPayload"
OUTPUT="$PAYLOAD_ROOT/checksums.txt"

VERIFIER="$PROJECT_ROOT/dist/Zoomtopia Setup.app/Contents/Resources/PayloadVerifier"
if [[ ! -x "$VERIFIER" ]]; then
    echo "Build the app first so packages can be checked against the approved catalog." >&2
    exit 1
fi
for spec in "chrome:GoogleChrome" "zoom:ZoomWorkplace"; do
    id="${spec%%:*}"; base="${spec#*:}"
    for package in "$PAYLOAD_ROOT/Installers/$base"*.pkg; do
        [[ -f "$package" ]] || continue
        "$VERIFIER" --verify-package "$id" "$package"
    done
done

cd "$PAYLOAD_ROOT"
FILES=()
while IFS= read -r file; do
    FILES+=("$file")
done < <(/usr/bin/find Installers assets config -type f \
    ! -name 'README.md' \
    ! -name 'PRIVACY.md' \
    ! -name '*.example' \
    ! -name '*.mobileconfig.example' \
    -print | /usr/bin/sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No payload files found." >&2
    exit 1
fi

/usr/bin/shasum -a 256 "${FILES[@]}" > "$OUTPUT"
echo "Wrote $OUTPUT with ${#FILES[@]} file(s)."
