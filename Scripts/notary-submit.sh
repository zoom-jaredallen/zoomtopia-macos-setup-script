#!/bin/bash
# Sourceable workflow for production notarytool calls and isolated test doubles.
submit_for_notarization() {
    local archive="$1" profile="$2" records="$3" result_code=0 submission_id status
    mkdir -p "$records" || return 1
    notary_command submit "$archive" --keychain-profile "$profile" --wait --output-format json \
        > "$records/submission.json" 2> "$records/submission.stderr" || result_code=$?
    submission_id=$(/usr/bin/plutil -extract id raw -o - "$records/submission.json" 2>/dev/null) || submission_id=''
    status=$(/usr/bin/plutil -extract status raw -o - "$records/submission.json" 2>/dev/null) || status=''
    if [[ "$submission_id" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]]; then
        printf '%s\n' "$submission_id" > "$records/submission-id.txt"
        if ! notary_command log "$submission_id" --keychain-profile "$profile" "$records/notary-log.json" \
            > "$records/log.stdout" 2> "$records/log.stderr"; then
            echo "Could not retrieve Apple's notarization log. Submission ID: $submission_id; records: $records" >&2
            return 1
        fi
        /usr/bin/plutil -extract status raw -o - "$records/notary-log.json" >/dev/null 2>&1 || {
            echo "Apple's notarization log is missing or invalid; records: $records" >&2; return 1;
        }
    else
        echo "No valid submission ID returned; inspect $records/submission.json and submission.stderr before resubmitting" >&2
        return 1
    fi
    if [[ "$result_code" -ne 0 || "$status" != Accepted ]]; then
        echo "Notarization not accepted (status: ${status:-unknown}). Records: $records" >&2
        return 1
    fi
    echo "Notarization accepted. Submission ID: $submission_id; records: $records"
}
