#!/bin/bash
# Sourced by bootstrap and the unprivileged recheck helper. No update or state writes.
software_update() { LC_ALL=C /usr/sbin/softwareupdate "$@"; }
current_macos_major() {
    local version
    version=$(/usr/bin/sw_vers -productVersion) || return 1
    printf '%s\n' "${version%%.*}"
}

# softwareupdate's human-readable output can change. Accept complete known stanzas
# and fail closed on unknown output. Labels are never executed or split into words.
classify_update_listing() {
    /usr/bin/awk -v current="$1" '
    function finish(    major,parts) {
        if (!pending) return
        if (!details) { invalid=1; return }
        count++
        if (title ~ /^macOS([[:space:]]|$)/) {
            split(version,parts,".")
            major=parts[1]+0
            if (major == current) actionable++
            else if (major > current) excluded++
            else invalid=1
        } else if (recommended == "YES") actionable++
        pending=0
    }
    {
        line=$0
        sub(/^[[:space:]]+/,"",line); sub(/[[:space:]]+$/,"",line)
        if (line == "") next
        if (line == "Software Update Tool" || line == "Finding available software" ||
            line == "Software Update found the following new or updated software:") next
        if (line == "No new software available.") { clean++; next }
        if (line ~ /^\* Label: .+/) {
            finish()
            pending=1; details=0
            next
        }
        if (line ~ /^Title: / && pending && !details) {
            # A supported metadata line has a title, numeric version, size and
            # recommendation, with an optional action. Available Action: restart
            # describes the offer; it is not evidence that a restart is pending.
            n=split(line,fields,",[[:space:]]*")
            if (n < 4 || fields[1] !~ /^Title: .+/ ||
                fields[2] !~ /^Version: [0-9]+(\.[0-9]+)*$/ ||
                fields[3] !~ /^Size: [0-9]+[[:alpha:]]+$/ ||
                fields[4] !~ /^Recommended: (YES|NO)$/) { invalid=1; next }
            for (i=5;i<=n;i++) {
                if (fields[i] != "" && fields[i] !~ /^Action: (restart|shut down|shutdown)$/) invalid=1
            }
            title=substr(fields[1],8); version=substr(fields[2],10)
            recommended=substr(fields[4],14); details=1
            next
        }
        invalid=1
    }
    END {
        finish()
        if (invalid || (clean && count) || clean > 1 || (!clean && !count)) print "unknown"
        else if (actionable) print "actionRequired"
        else if (excluded) print "excluded"
        else if (clean) print "clean"
        else print "optional"
    }'
}

# Name and positional state_dir argument retained for existing callers. Legacy
# updates-boot markers predate authenticated installation and prove no restart;
# leave all state untouched. The app tracks explicit operator restart requests.
install_macos_updates() {
    local state_dir="$1" major listing classification
    major=$(current_macos_major) || major=''
    case "$major" in
        ''|*[!0-9]*)
            warn_step 10 updates "Check macOS updates" "Cannot determine the installed macOS major version; retry the update check"
            return ;;
    esac
    if [[ "$major" -lt 11 ]]; then
        warn_step 10 updates "Check macOS updates" "Unsupported macOS version for update classification; retry on a supported Mac"
        return
    fi
    listing=$(software_update --list 2>&1) || {
        printf '%s\n' "$listing"
        warn_step 10 updates "Check macOS updates" "Cannot check Apple Software Update; check the network and retry the update check"
        return
    }
    printf '%s\n' "$listing"
    classification=$(printf '%s\n' "$listing" | classify_update_listing "$major") || classification=unknown
    case "$classification" in
        actionRequired)
            ACTION_REQUIRED=1
            emit 10 updates "Check macOS updates" actionRequired "Open Software Update; choose available same-major macOS $major updates and recommended app updates, not the offered next-major upgrade. Complete them, then recheck here."
            ;;
        excluded)
            emit 10 updates "Check macOS updates" passed "Only next-major macOS upgrades or optional updates are offered; next-major upgrades are intentionally excluded"
            ;;
        clean)
            emit 10 updates "Check macOS updates" passed "No available updates"
            ;;
        optional)
            emit 10 updates "Check macOS updates" passed "No same-major macOS or recommended app updates are available"
            ;;
        *)
            warn_step 10 updates "Check macOS updates" "Unrecognized Software Update response; review the log and retry the update check"
            ;;
    esac
}
