#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECK="${REPO_ROOT}/scripts/check-notary-profile.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ct-notary-preflight-test.XXXXXX")"
cleanup() {
    rm -rf "${SCRATCH}"
}
trap cleanup EXIT

FAKE_BIN="${SCRATCH}/bin"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/xcrun" <<'EOF'
#!/bin/bash
set -euo pipefail

count=0
if [[ -f "${CT_TEST_COUNT_FILE}" ]]; then
    count="$(<"${CT_TEST_COUNT_FILE}")"
fi
count=$((count + 1))
printf '%s\n' "${count}" > "${CT_TEST_COUNT_FILE}"

case "${CT_TEST_SCENARIO}" in
    retry-then-pass)
        if (( count < 3 )); then
            echo "Error: Keychain interaction was temporarily unavailable" >&2
            exit 1
        fi
        printf '{"history":[]}\n'
        ;;
    item-unavailable)
        echo "Error: No Keychain password item found for profile: test-profile" >&2
        exit 1
        ;;
    service-unavailable)
        echo "Error: Apple service temporarily unavailable" >&2
        exit 1
        ;;
    *)
        echo "unexpected test scenario" >&2
        exit 2
        ;;
esac
EOF
chmod +x "${FAKE_BIN}/xcrun"

run_check() {
    local scenario="$1"
    local evidence="${2:-}"
    local count_file="${SCRATCH}/count-${scenario}"
    local output="${SCRATCH}/output-${scenario}"
    local status=0
    local args=(--profile "test-profile")
    if [[ -n "${evidence}" ]]; then
        args+=(--evidence "${evidence}")
    fi

    PATH="${FAKE_BIN}:${PATH}" \
        CT_TEST_SCENARIO="${scenario}" \
        CT_TEST_COUNT_FILE="${count_file}" \
        CT_NOTARY_PREFLIGHT_RETRY_DELAY=0 \
        "${CHECK}" "${args[@]}" >"${output}" 2>&1 || status=$?

    printf '%s\n' "${status}" > "${SCRATCH}/status-${scenario}"
    printf '%s\n' "${output}"
}

retry_output="$(run_check retry-then-pass)"
[[ "$(<"${SCRATCH}/status-retry-then-pass")" == "0" ]]
[[ "$(<"${SCRATCH}/count-retry-then-pass")" == "3" ]]
grep -q "is available" "${retry_output}"

accepted_evidence="${SCRATCH}/accepted.json"
printf '{"notarization_status":"Accepted"}\n' > "${accepted_evidence}"
accepted_output="$(run_check item-unavailable "${accepted_evidence}")"
[[ "$(<"${SCRATCH}/status-item-unavailable")" == "1" ]]
grep -q "was provisioned previously" "${accepted_output}"
grep -q "not sufficient reason to recreate" "${accepted_output}"
if grep -Eqi "profile .* (is )?missing" "${accepted_output}"; then
    echo "accepted evidence was incorrectly reported as a missing profile" >&2
    exit 1
fi

service_output="$(run_check service-unavailable)"
[[ "$(<"${SCRATCH}/status-service-unavailable")" == "1" ]]
grep -q "readiness could not be verified" "${service_output}"

echo "notary profile preflight: retry and failure classification verified"
