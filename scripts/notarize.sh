#!/bin/bash
# M4 Stream-D / S7 — notarytool submit + staple for one .app or .dmg
# (architecture.md §7, release-and-versioning.md §2 step 2, ADR-M4-002's
# "staple is verified offline before promote").
#
# ## Reads credentials from the environment — never hardcoded (invariant #4)
#
# Two supported credential shapes (notarytool supports both); pick ONE:
#
#   CT_NOTARY_KEYCHAIN_PROFILE   A profile name previously stored via
#                                 `xcrun notarytool store-credentials` in the
#                                 signer's local keychain. Preferred for
#                                 interactive/local signing — no secret ever
#                                 touches this script or CI environment.
#
#   ...or, for CI (App Store Connect API key):
#   CT_NOTARY_KEY_ID              API key ID
#   CT_NOTARY_KEY_ISSUER          API key issuer ID
#   CT_NOTARY_KEY_PATH            path to the downloaded .p8 private key file
#                                 (mounted from a CI secret at runtime, never
#                                 committed to this repo)
#
# Usage:
#   notarize.sh app "/path/to/Copilot Control Tower.app"
#   notarize.sh dmg "/path/to/Copilot Control Tower.dmg"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-}"
ARTIFACT_PATH="${2:-}"

if [[ "${MODE}" != "app" && "${MODE}" != "dmg" ]]; then
    echo "error: first argument must be app or dmg" >&2
    exit 1
fi
if [[ -z "${ARTIFACT_PATH}" ]]; then
    echo "error: artifact path is required" >&2
    exit 1
fi

if [[ -n "${CT_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    run_notarytool() {
        "${SCRIPT_DIR}/notarytool-profile-retry.sh" \
            --profile "${CT_NOTARY_KEYCHAIN_PROFILE}" -- "$@"
    }
elif [[ -n "${CT_NOTARY_KEY_ID:-}" && -n "${CT_NOTARY_KEY_ISSUER:-}" && -n "${CT_NOTARY_KEY_PATH:-}" ]]; then
    run_notarytool() {
        xcrun notarytool "$@" \
            --key "${CT_NOTARY_KEY_PATH}" \
            --key-id "${CT_NOTARY_KEY_ID}" \
            --issuer "${CT_NOTARY_KEY_ISSUER}"
    }
else
    echo "error: no notarization credentials set." >&2
    echo "       Set CT_NOTARY_KEYCHAIN_PROFILE, or all three of" >&2
    echo "       CT_NOTARY_KEY_ID / CT_NOTARY_KEY_ISSUER / CT_NOTARY_KEY_PATH." >&2
    echo "       Never hardcode credentials in this file." >&2
    exit 1
fi

submit_path="${ARTIFACT_PATH}"
scratch=""
cleanup() {
    if [[ -n "${scratch}" ]]; then
        rm -rf "${scratch}"
    fi
}
trap cleanup EXIT

case "${MODE}" in
    app)
        if [[ ! -d "${ARTIFACT_PATH}" ]]; then
            echo "error: app bundle not found at ${ARTIFACT_PATH}" >&2
            exit 1
        fi
        command -v ditto >/dev/null 2>&1 || {
            echo "error: ditto is required but was not found" >&2
            exit 1
        }
        scratch="$(mktemp -d "${TMPDIR:-/tmp}/control-tower-app-notary.XXXXXX")"
        submit_path="${scratch}/$(basename "${ARTIFACT_PATH}").zip"
        ditto -c -k --keepParent "${ARTIFACT_PATH}" "${submit_path}"
        ;;
    dmg)
        if [[ ! -f "${ARTIFACT_PATH}" ]]; then
            echo "error: dmg not found at ${ARTIFACT_PATH}" >&2
            exit 1
        fi
        ;;
esac

echo "submitting ${ARTIFACT_PATH} for notarization (--wait)..."
run_notarytool submit "${submit_path}" --wait

# The app must be stapled before the DMG payload is assembled. Otherwise the
# copied app has no offline ticket even though the outer DMG is stapled.
echo "stapling ${ARTIFACT_PATH}..."
xcrun stapler staple "${ARTIFACT_PATH}"

echo "verifying staple offline on ${ARTIFACT_PATH}..."
xcrun stapler validate "${ARTIFACT_PATH}"

echo "notarized + stapled: ${ARTIFACT_PATH}"
