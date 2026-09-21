#!/bin/bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PAYLOAD_ROOT="$PROJECT_ROOT/ZoomtopiaPayload"
OUTPUT="$PAYLOAD_ROOT/checksums.txt"

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
