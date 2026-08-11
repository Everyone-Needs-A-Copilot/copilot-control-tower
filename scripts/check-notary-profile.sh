#!/bin/bash
# Verify that a previously stored notarytool profile is usable without
# confusing one Keychain lookup failure with proof that setup never happened.

set -euo pipefail

PROFILE=""
EVIDENCE=""
ATTEMPTS="${CT_NOTARY_PREFLIGHT_ATTEMPTS:-3}"
RETRY_DELAY="${CT_NOTARY_PREFLIGHT_RETRY_DELAY:-1}"

usage() {
    cat <<'EOF'
Usage: scripts/check-notary-profile.sh --profile NAME [--evidence FILE]

Checks a saved notarytool Keychain profile without exposing its credentials.
Transient failures are retried. If accepted notarization evidence already
exists, a failed live lookup is reported as an access problem rather than as
proof that the profile was never provisioned.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            [[ $# -ge 2 ]] || die "--profile requires a value"
            PROFILE="$2"
            shift 2
            ;;
        --evidence)
            [[ $# -ge 2 ]] || die "--evidence requires a value"
            EVIDENCE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

[[ -n "${PROFILE}" ]] || die "--profile is required"
[[ "${ATTEMPTS}" =~ ^[1-9][0-9]*$ ]] ||
    die "CT_NOTARY_PREFLIGHT_ATTEMPTS must be a positive integer"
[[ "${RETRY_DELAY}" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
    die "CT_NOTARY_PREFLIGHT_RETRY_DELAY must be a non-negative number"
command -v xcrun >/dev/null 2>&1 || die "xcrun is required but was not found"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-notary-preflight.XXXXXX")"
chmod 700 "${scratch}"
cleanup() {
    rm -rf "${scratch}"
}
trap cleanup EXIT

stdout_path="${scratch}/stdout"
stderr_path="${scratch}/stderr"
attempt=1
while (( attempt <= ATTEMPTS )); do
    if xcrun notarytool history \
        --keychain-profile "${PROFILE}" \
        --output-format json \
        --no-progress \
        >"${stdout_path}" 2>"${stderr_path}"; then
        echo "release: notarization profile '${PROFILE}' is available"
        exit 0
    fi

    if (( attempt < ATTEMPTS )); then
        echo "release: notarization profile check failed (attempt ${attempt}/${ATTEMPTS}); retrying" >&2
        if [[ "${RETRY_DELAY}" != "0" ]]; then
            sleep "${RETRY_DELAY}"
        fi
    fi
    attempt=$((attempt + 1))
done

was_previously_accepted=false
if [[ -n "${EVIDENCE}" && -f "${EVIDENCE}" ]] &&
   grep -Eq '"notarization_status"[[:space:]]*:[[:space:]]*"Accepted"' "${EVIDENCE}"; then
    was_previously_accepted=true
fi

keychain_item_unavailable=false
if grep -Eqi \
    'No Keychain password item found|specified item could not be found in the keychain' \
    "${stderr_path}"; then
    keychain_item_unavailable=true
fi

if [[ "${was_previously_accepted}" == "true" ]]; then
    echo "error: notarization profile '${PROFILE}' was provisioned previously, but notarytool could not access it after ${ATTEMPTS} attempts." >&2
    echo "       Existing accepted notarization evidence proves this is not sufficient reason to recreate the profile." >&2
elif [[ "${keychain_item_unavailable}" == "true" ]]; then
    echo "error: notarization profile '${PROFILE}' is unavailable after ${ATTEMPTS} attempts; it may be inaccessible or absent." >&2
else
    echo "error: Apple notarization readiness could not be verified after ${ATTEMPTS} attempts." >&2
fi

if [[ -s "${stderr_path}" ]]; then
    diagnostic="$(tr '\r\n' '  ' < "${stderr_path}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    [[ -n "${diagnostic}" ]] &&
        echo "       notarytool: ${diagnostic}" >&2
fi
exit 1
