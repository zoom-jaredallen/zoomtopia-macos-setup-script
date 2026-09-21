#!/bin/bash
# Sourced by bootstrap; functions are isolated for non-destructive regression tests.
current_boot() { /usr/sbin/sysctl -n kern.boottime; }
software_update() { /usr/sbin/softwareupdate "$@"; }

install_macos_updates() {
    local state_dir="$1" boot previous listing
    if [[ -L "$state_dir" ]] || ! /bin/mkdir -p "$state_dir" || ! /bin/chmod 700 "$state_dir"; then
        fail_step 10 updates "Install macOS updates" "Cannot record update restart state"
        return
    fi
    boot=$(current_boot) || {
        fail_step 10 updates "Install macOS updates" "Cannot determine boot session"
        return
    }
    if [[ -L "$state_dir/updates-boot" ]]; then
        fail_step 10 updates "Install macOS updates" "Invalid update state file"
        return
    fi
    if [[ -f "$state_dir/updates-boot" ]]; then
        previous=$(cat "$state_dir/updates-boot")
        if [[ "$previous" == "$boot" ]]; then
            warn_step 10 updates "Install macOS updates" "Restart this Mac, then run setup again to verify updates"
            return
        fi
        /bin/rm -f "$state_dir/updates-boot" || {
            fail_step 10 updates "Install macOS updates" "Cannot clear previous restart state"
            return
        }
    fi
    listing=$(software_update --list 2>&1) || {
        echo "$listing"
        warn_step 10 updates "Install macOS updates" "Cannot check Apple Software Update; check the network and rerun"
        return
    }
    echo "$listing"
    if [[ "$listing" == *"No new software available."* ]]; then
        emit 10 updates "Install macOS updates" passed "No available updates; restart verification passed"
    elif [[ "$listing" == *"* Label:"* ]]; then
        # Conservatively require a reboot after any update installation. Record before
        # invoking softwareupdate so cancellation/owner-password failures cannot erase it.
        if ! printf '%s\n' "$boot" > "$state_dir/updates-boot"; then
            fail_step 10 updates "Install macOS updates" "Cannot persist restart requirement"
        elif software_update --install --all --verbose; then
            warn_step 10 updates "Install macOS updates" "Updates processed; restart this Mac and rerun setup"
        else
            warn_step 10 updates "Install macOS updates" "Updates need attention, possibly a volume-owner password; review the log, restart, and rerun"
        fi
    else
        warn_step 10 updates "Install macOS updates" "Unrecognized Software Update response; review the log and rerun"
    fi
}
