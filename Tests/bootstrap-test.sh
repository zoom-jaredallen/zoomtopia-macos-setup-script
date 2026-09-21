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
