#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Load only the production helper, never the provisioning entry point.
eval "$(sed -n '/^run_as_user() {/,/^}/p' Scripts/bootstrap.sh)"
function /usr/bin/id() { printf '501\n'; }
function /bin/launchctl() { printf '<%s>\n' "$@"; }
actual=$(run_as_user student /usr/bin/defaults write 'a domain' key -bool true)
expected='<asuser>
<501>
</usr/bin/sudo>
<-u>
<student>
</usr/bin/defaults>
<write>
<a domain>
<key>
<-bool>
<true>'
[[ "$actual" == "$expected" ]] || { echo "FAIL: run_as_user forwarded incorrect arguments"; exit 1; }
echo "PASS: run_as_user drops username and preserves command arguments"

# Exercise the real installed-current branch with a fake verifier. No installer runs.
eval "$(sed -n '/^install_approved_package() {/,/^}/p' Scripts/bootstrap.sh)"
VERIFIER=test_verifier
function test_verifier() { [[ "$1" == '--decision' ]] || return 1; printf 'skip\n'; }
function emit() { printf '%s:%s\n' "$2" "$4"; }
function fail_step() { echo 'unexpected failure'; return 1; }
for app in chrome zoom; do
    actual=$(install_approved_package 3 "$app" "Check app" Missing.pkg)
    [[ "$actual" == "$app:running
$app:skipped" ]] || { echo "FAIL: current $app did not finish as skipped"; exit 1; }
done
echo 'PASS: current Chrome and Zoom skip without accessing installer or installation state'
