#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/notary-submit.sh
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
submission=12345678-1234-1234-1234-123456789abc
notary_command() {
    if [[ "$1" == submit ]]; then
        case "$scenario" in
            malformed) echo 'broken response'; return 1 ;;
            missing) echo '{"status":"Accepted"}'; return 0 ;;
            rejected) printf '{"id":"%s","status":"Invalid"}\n' "$submission"; return 0 ;;
            *) printf '{"id":"%s","status":"Accepted"}\n' "$submission" ;;
        esac
        [[ "$scenario" != submit_error ]]
    else
        [[ "$1" == log && "$2" == "$submission" && "$3" == --keychain-profile && "$4" == test-profile ]]
        [[ "$scenario" != log_error ]] || return 1
        if [[ "$scenario" == bad_log ]]; then echo broken > "$5"; else echo '{"status":"Accepted","issues":null}' > "$5"; fi
    fi
}
for scenario in accepted rejected submit_error malformed missing log_error bad_log; do
    records="$scratch/$scenario"
    if submit_for_notarization unused.zip test-profile "$records" > "$scratch/output" 2>&1; then
        [[ "$scenario" == accepted ]] || { cat "$scratch/output"; exit 1; }
    else
        [[ "$scenario" != accepted ]] || { cat "$scratch/output"; exit 1; }
    fi
    [[ -f "$records/submission.json" && -f "$records/submission.stderr" ]]
    case "$scenario" in
        malformed|missing) [[ ! -f "$records/submission-id.txt" ]] ;;
        *) [[ "$(cat "$records/submission-id.txt")" == "$submission" ]] ;;
    esac
    case "$scenario" in accepted|rejected|submit_error) [[ -s "$records/notary-log.json" ]] ;; esac
done
for invalid in 'BUILD_CONFIGURATION=invalid' 'APP_BUILD=0' 'APP_BUILD=10000' 'APP_BUILD=abc' 'DEVELOPER_ID_APPLICATION=test' ; do
    if env -u APP_BUILD -u DEVELOPER_ID_APPLICATION -u BUILD_CONFIGURATION "$invalid" /bin/bash Scripts/build-app.sh > "$scratch/build" 2>&1; then exit 1; else [[ $? == 64 ]]; fi
done
if env DEVELOPER_ID_APPLICATION=test APP_BUILD=2 BUILD_CONFIGURATION=development /bin/bash Scripts/build-app.sh > "$scratch/build" 2>&1; then exit 1; else [[ $? == 64 ]]; fi
mkdir -p "$scratch/Development.app/Contents"
printf '%s\n' '{"ZoomtopiaBuildConfiguration":"development"}' > "$scratch/Development.app/Contents/Info.plist"
if NOTARY_PROFILE=test-profile /bin/bash Scripts/notarize-app.sh "$scratch/Development.app" > "$scratch/refusal" 2>&1; then exit 1; fi
rg -q 'Rebuild with BUILD_CONFIGURATION=release' "$scratch/refusal"
if /bin/bash Scripts/package-release.sh "$scratch/Development.app" > "$scratch/refusal" 2>&1; then exit 1; fi
rg -q 'Development builds cannot be packaged' "$scratch/refusal"
echo 'Notarization retention and build-policy tests passed' 
