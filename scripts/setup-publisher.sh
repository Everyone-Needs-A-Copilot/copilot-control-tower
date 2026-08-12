#!/bin/bash
# One-time publisher bootstrap for local macOS release signing.
#
# This script does not create Apple certificates, export .p12 files, or write
# secrets into the repo. It assumes the publisher has already installed a
# trusted Developer ID Application certificate with its private key.

set -euo pipefail

PROFILE_NAME="ct-notary"
ENV_FILE=".env.release.local"
APPLE_ID=""
SIGN_IDENTITY=""
TEAM_ID=""
SKIP_NOTARY=0
FORCE=0

usage() {
    cat <<'EOF'
Usage: setup-publisher.sh [options]

Options:
  --apple-id EMAIL       Apple Developer Apple ID for notarytool.
  --identity STRING     Developer ID Application identity to use.
  --team-id TEAMID      Override Team ID if it cannot be parsed from identity.
  --profile NAME        notarytool keychain profile name (default: ct-notary).
  --env-file PATH       Local env file to write (default: .env.release.local).
  --skip-notary         Only write/validate the local env file.
  --replace-existing    Replace an existing env file.
  -h, --help            Show this help.

The notary password is never accepted as an argument. If --skip-notary is not
set, Apple's notarytool prompts securely for the app-specific password.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required but was not found"
}

quote_sh() {
    local value="$1"
    printf "'%s'" "$(printf "%s" "${value}" | sed "s/'/'\\\\''/g")"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apple-id)
            [[ $# -ge 2 ]] || die "--apple-id requires a value"
            APPLE_ID="$2"
            shift 2
            ;;
        --identity)
            [[ $# -ge 2 ]] || die "--identity requires a value"
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --team-id)
            [[ $# -ge 2 ]] || die "--team-id requires a value"
            TEAM_ID="$2"
            shift 2
            ;;
        --profile)
            [[ $# -ge 2 ]] || die "--profile requires a value"
            PROFILE_NAME="$2"
            shift 2
            ;;
        --env-file)
            [[ $# -ge 2 ]] || die "--env-file requires a value"
            ENV_FILE="$2"
            shift 2
            ;;
        --skip-notary)
            SKIP_NOTARY=1
            shift
            ;;
        --replace-existing)
            FORCE=1
            shift
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

require_cmd security
require_cmd xcrun
require_cmd grep
require_cmd sed
require_cmd sort

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

identities=()
while IFS= read -r identity; do
    identities+=("${identity}")
done < <(
    security find-identity -v -p codesigning |
        sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' |
        sort -u
)

if [[ -z "${SIGN_IDENTITY}" ]]; then
    case "${#identities[@]}" in
        0)
            die "no Developer ID Application identity found. Install the certificate and Developer ID - G2 intermediate first."
            ;;
        1)
            SIGN_IDENTITY="${identities[0]}"
            ;;
        *)
            echo "Developer ID Application identities found:"
            index=1
            for identity in "${identities[@]}"; do
                printf "  %d) %s\n" "${index}" "${identity}"
                index=$((index + 1))
            done
            printf "Choose identity number: "
            read -r choice
            [[ "${choice}" =~ ^[0-9]+$ ]] || die "identity choice must be a number"
            (( choice >= 1 && choice <= ${#identities[@]} )) || die "identity choice out of range"
            SIGN_IDENTITY="${identities[$((choice - 1))]}"
            ;;
    esac
fi

if [[ "${SIGN_IDENTITY}" != Developer\ ID\ Application:* ]]; then
    die "--identity must be a Developer ID Application identity"
fi

if [[ -z "${TEAM_ID}" ]]; then
    if [[ "${SIGN_IDENTITY}" =~ \(([A-Z0-9]{10})\)$ ]]; then
        TEAM_ID="${BASH_REMATCH[1]}"
    else
        die "could not parse Team ID from identity; pass --team-id TEAMID"
    fi
fi

if [[ ! "${TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
    die "Team ID should be 10 uppercase letters/digits; got: ${TEAM_ID}"
fi

echo "Using signing identity:"
echo "  ${SIGN_IDENTITY}"
echo "Using Team ID:"
echo "  ${TEAM_ID}"

if [[ "${SKIP_NOTARY}" -eq 0 ]]; then
    if [[ -z "${APPLE_ID}" ]]; then
        printf "Apple Developer Apple ID email: "
        read -r APPLE_ID
    fi
    [[ -n "${APPLE_ID}" ]] || die "Apple ID email is required unless --skip-notary is set"

    echo "Storing notarytool keychain profile '${PROFILE_NAME}'."
    echo "Use an app-specific password at Apple's secure prompt."
    xcrun notarytool store-credentials "${PROFILE_NAME}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${TEAM_ID}"
else
    echo "Skipping notarytool credential storage."
fi

if [[ -e "${ENV_FILE}" && "${FORCE}" -ne 1 ]]; then
    die "${ENV_FILE} already exists; pass --replace-existing to replace it"
fi

env_dir="$(dirname "${ENV_FILE}")"
if [[ "${env_dir}" != "." && ! -d "${env_dir}" ]]; then
    die "env file directory does not exist: ${env_dir}"
fi

tmp_file="${ENV_FILE}.tmp.$$"
umask 077
{
    echo "# Local publisher release environment. Do not commit."
    echo "# Generated by scripts/setup-publisher.sh"
    printf "export CT_SIGN_IDENTITY=%s\n" "$(quote_sh "${SIGN_IDENTITY}")"
    echo 'export APPLE_SIGNING_IDENTITY="$CT_SIGN_IDENTITY"'
    printf "export CT_NOTARY_KEYCHAIN_PROFILE=%s\n" "$(quote_sh "${PROFILE_NAME}")"
} > "${tmp_file}"
mv "${tmp_file}" "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

echo "Wrote ${ENV_FILE} with mode 600."
echo
echo "Next:"
echo "  ./scripts/package-user-release"
