#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNNER="${REPO_ROOT}/scripts/notarytool-profile-retry.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ct-notary-retry-test.XXXXXX")"
cleanup() {
    rm -rf "${SCRATCH}"
}
trap cleanup EXIT

FAKE_BIN="${SCRATCH}/bin"
mkdir -p "${FAKE_BIN}"
cat > "${FAKE_BIN}/xcrun" <<'EOF'
#!/usr/bin/env bash
set -eu
count=0
if [[ -f "${CT_TEST_COUNT_FILE}" ]]; then count="$(<"${CT_TEST_COUNT_FILE}")"; fi
count=$((count + 1))
printf '%s\n' "${count}" > "${CT_TEST_COUNT_FILE}"
case "${CT_TEST_SCENARIO}" in
    transient)
        if [[ "${count}" -eq 1 ]]; then
            echo 'Error: No Keychain password item found for profile: ct-notary' >&2
            exit 69
        fi
        echo '{"ok":true}'
        ;;
    exhausted)
        echo 'Error: The specified item could not be found in the keychain.' >&2
        exit 69
        ;;
    remote)
        echo 'Error: HTTP status code: 401. Invalid credentials.' >&2
        exit 65
        ;;
esac
EOF
chmod 755 "${FAKE_BIN}/xcrun"

run_scenario() {
    local scenario="$1"
    local attempts="$2"
    local output="${SCRATCH}/${scenario}.out"
    local count_file="${SCRATCH}/${scenario}.count"
    local status=0
    PATH="${FAKE_BIN}:${PATH}" \
        CT_TEST_SCENARIO="${scenario}" \
        CT_TEST_COUNT_FILE="${count_file}" \
        CT_NOTARY_PROFILE_ATTEMPTS="${attempts}" \
        CT_NOTARY_PROFILE_RETRY_DELAY=0 \
        "${RUNNER}" --profile ct-notary -- history >"${output}" 2>&1 || status=$?
    printf '%s %s %s\n' "${status}" "${count_file}" "${output}"
}

read -r transient_status transient_count transient_output < <(run_scenario transient 3)
[[ "${transient_status}" == "0" ]]
[[ "$(<"${transient_count}")" == "2" ]]
grep -q 'temporarily unavailable to this process' "${transient_output}"
grep -q '{"ok":true}' "${transient_output}"

read -r remote_status remote_count remote_output < <(run_scenario remote 3)
[[ "${remote_status}" == "65" ]]
[[ "$(<"${remote_count}")" == "1" ]]
grep -q 'Invalid credentials' "${remote_output}"
! grep -q 'temporarily unavailable' "${remote_output}"

read -r exhausted_status exhausted_count exhausted_output < <(run_scenario exhausted 2)
[[ "${exhausted_status}" == "69" ]]
[[ "$(<"${exhausted_count}")" == "2" ]]
grep -q 'does not prove the Data Protection Keychain item was deleted' "${exhausted_output}"
grep -q 'continue without recreating credentials' "${exhausted_output}"

echo 'notarytool profile retry: transient recovery and fail-closed classification verified'
