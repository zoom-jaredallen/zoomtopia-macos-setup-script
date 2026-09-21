#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
swiftc Sources/SetupCore/Policy.swift Sources/SetupCore/SigningIdentity.swift Tests/Fixtures/identity/main.swift -o "$ROOT/running"
"$ROOT/running" "$ROOT/ready" "$ROOT/proceed" > "$ROOT/result" 2> "$ROOT/error" &
PID=$!
for attempt in {1..100}; do
    [[ -f "$ROOT/ready" ]] && break
    sleep 0.05
done
[[ -f "$ROOT/ready" ]] || { echo 'FAIL: identity fixture did not launch'; exit 1; }
cp /usr/bin/true "$ROOT/replacement"
mv -f "$ROOT/replacement" "$ROOT/running"
touch "$ROOT/proceed"
if wait "$PID"; then
    requirement=$(cat "$ROOT/result")
    [[ -n "$requirement" ]] || exit 1
    if codesign --verify --strict -R "=$requirement" "$ROOT/running" 2>/dev/null; then
        echo 'FAIL: replaced executable supplied its own trusted identity'
        exit 1
    fi
else
    grep -q 'signature is invalid' "$ROOT/error" || { cat "$ROOT/error"; exit 1; }
fi
echo 'PASS: replacing a launched executable cannot supply the trusted snapshot identity'
