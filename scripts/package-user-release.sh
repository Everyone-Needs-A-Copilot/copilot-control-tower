#!/bin/bash
# Build the native User app from an exact pushed ref, Developer-ID sign it,
# create a DMG, notarize/staple both artifacts, Gatekeeper-assess them, and
# emit checksum/provenance metadata.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_REF=""
OUTPUT_DIR=""

usage() {
    cat <<'EOF'
Usage: scripts/package-user-release.sh [options]

Options:
  --source-ref REF   Remote branch or tag to clone. Defaults to the current branch.
  --output-dir PATH  Final artifact directory. Defaults to dist/user-release.
  -h, --help         Show this help.

The default entrypoint requires local HEAD to equal origin/REF, then builds
from a temporary clone of that pushed ref. CT_RELEASE_CHECKOUT=1 is reserved
for the already-isolated checkout used internally and by tag CI.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required but was not found"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-ref)
            [[ $# -ge 2 ]] || die "--source-ref requires a value"
            SOURCE_REF="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || die "--output-dir requires a value"
            OUTPUT_DIR="$2"
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

require_cmd codesign
require_cmd ditto
require_cmd git
require_cmd hdiutil
require_cmd plutil
require_cmd shasum
require_cmd spctl
require_cmd xcrun

if [[ -z "${CT_SIGN_IDENTITY:-}" ]]; then
    die "CT_SIGN_IDENTITY is not set; source .env.release.local first"
fi
if [[ -z "${CT_NOTARY_KEYCHAIN_PROFILE:-}" &&
      ( -z "${CT_NOTARY_KEY_ID:-}" ||
        -z "${CT_NOTARY_KEY_ISSUER:-}" ||
        -z "${CT_NOTARY_KEY_PATH:-}" ) ]]; then
    die "notarization credentials are not configured"
fi

if [[ "${CT_RELEASE_CHECKOUT:-0}" != "1" ]]; then
    cd "${REPO_ROOT}"
    [[ -n "${SOURCE_REF}" ]] || SOURCE_REF="$(git branch --show-current)"
    [[ -n "${SOURCE_REF}" ]] || die "--source-ref is required from a detached HEAD"

    local_commit="$(git rev-parse HEAD)"
    remote_url="$(git remote get-url origin)"
    remote_commit="$(
        git ls-remote --exit-code "${remote_url}" \
            "refs/heads/${SOURCE_REF}" "refs/tags/${SOURCE_REF}^{}" "refs/tags/${SOURCE_REF}" |
            awk '
                NR == 1 { first = $1 }
                $2 ~ /\^\{\}$/ { peeled = $1 }
                END { print peeled ? peeled : first }
            '
    )"
    [[ -n "${remote_commit}" ]] || die "origin does not advertise ${SOURCE_REF}"
    [[ "${local_commit}" == "${remote_commit}" ]] ||
        die "local HEAD ${local_commit} is not the pushed ${SOURCE_REF} commit ${remote_commit}"

    [[ -n "${OUTPUT_DIR}" ]] || OUTPUT_DIR="${REPO_ROOT}/dist/user-release"
    case "${OUTPUT_DIR}" in
        /*) ;;
        *) OUTPUT_DIR="${REPO_ROOT}/${OUTPUT_DIR}" ;;
    esac
    [[ ! -e "${OUTPUT_DIR}" ]] ||
        die "output directory already exists: ${OUTPUT_DIR}"

    scratch="$(mktemp -d "${TMPDIR:-/tmp}/control-tower-release.XXXXXX")"
    cleanup() {
        rm -rf "${scratch}"
    }
    trap cleanup EXIT

    checkout="${scratch}/checkout"
    git clone --quiet --branch "${SOURCE_REF}" --single-branch "${remote_url}" "${checkout}"
    cloned_commit="$(git -C "${checkout}" rev-parse HEAD)"
    [[ "${cloned_commit}" == "${local_commit}" ]] ||
        die "cloned source changed during release preparation"

    CT_RELEASE_CHECKOUT=1 \
        "${checkout}/scripts/package-user-release.sh" \
        --output-dir "${OUTPUT_DIR}"
    exit 0
fi

cd "${REPO_ROOT}"
source_commit="$(git rev-parse HEAD)"
[[ -n "${OUTPUT_DIR}" ]] || OUTPUT_DIR="${REPO_ROOT}/dist/user-release"
case "${OUTPUT_DIR}" in
    /*) ;;
    *) OUTPUT_DIR="${REPO_ROOT}/${OUTPUT_DIR}" ;;
esac
[[ ! -e "${OUTPUT_DIR}" ]] || die "output directory already exists: ${OUTPUT_DIR}"

app_path="${REPO_ROOT}/build/Copilot Control Tower.app"
plist_path="${app_path}/Contents/Info.plist"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/control-tower-dmg.XXXXXX")"
payload_dir="${stage_dir}/payload"
cleanup_stage() {
    rm -rf "${stage_dir}"
}
trap cleanup_stage EXIT

echo "release: building native User app from ${source_commit}"
vendored_cc="${REPO_ROOT}/packaging/cc/cc"
vendored_cc_version="$(<"${REPO_ROOT}/packaging/cc/VERSION")"
vendored_cc_sha="$(shasum -a 256 "${vendored_cc}" | awk '{print $1}')"
CT_FORCE_REBUILD=1 CT_SKIP_ADHOC_SIGN=1 CT_VENDORED_CC_PATH="${vendored_cc}" \
    bash scripts/build-user.command --build-only >/dev/null

echo "release: applying Developer ID signature"
scripts/sign.sh "${app_path}"
embedded_cc="${app_path}/Contents/Resources/cc"
embedded_cc_sha="$(shasum -a 256 "${embedded_cc}" | awk '{print $1}')"
[[ "${embedded_cc_sha}" == "${vendored_cc_sha}" ]] ||
    die "embedded cc changed while building the app"
scripts/verify-vendored-cc.sh --release "${embedded_cc}"

version="$(plutil -extract CFBundleShortVersionString raw "${plist_path}")"
build_number="$(plutil -extract CFBundleVersion raw "${plist_path}")"
architecture="$(uname -m)"
artifact_base="Copilot-Control-Tower_${version}_${architecture}"
unsigned_dmg="${stage_dir}/${artifact_base}.dmg"

mkdir -p "${payload_dir}"
ditto "${app_path}" "${payload_dir}/Copilot Control Tower.app"
ln -s /Applications "${payload_dir}/Applications"

echo "release: creating drag-install DMG"
hdiutil create \
    -quiet \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -srcfolder "${payload_dir}" \
    -volname "Copilot Control Tower" \
    "${unsigned_dmg}"

codesign --sign "${CT_SIGN_IDENTITY}" --timestamp --force "${unsigned_dmg}"

echo "release: notarizing and stapling"
scripts/notarize.sh "${app_path}" "${unsigned_dmg}"

xcrun stapler validate "${app_path}"
xcrun stapler validate "${unsigned_dmg}"
codesign --verify --strict --deep --verbose=2 "${app_path}"
spctl --assess --type execute --verbose=4 "${app_path}"
spctl --assess --type open --context context:primary-signature --verbose=4 \
    "${unsigned_dmg}"

mkdir -p "${OUTPUT_DIR}"
final_app="${OUTPUT_DIR}/Copilot Control Tower.app"
final_dmg="${OUTPUT_DIR}/${artifact_base}.dmg"
ditto "${app_path}" "${final_app}"
ditto "${unsigned_dmg}" "${final_dmg}"
ditto "${REPO_ROOT}/controltower.compat.json" \
    "${OUTPUT_DIR}/controltower.compat.json"
ditto "${REPO_ROOT}/packaging/cc/NOTARIZATION.json" \
    "${OUTPUT_DIR}/cc-notarization.json"

checksum="$(shasum -a 256 "${final_dmg}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "$(basename "${final_dmg}")" \
    > "${final_dmg}.sha256"

cat > "${OUTPUT_DIR}/release-metadata.json" <<EOF
{
  "schema_version": "1.0",
  "source_commit": "${source_commit}",
  "bundle_identifier": "com.everyoneneedsacopilot.controltower",
  "version": "${version}",
  "build_number": "${build_number}",
  "architecture": "${architecture}",
  "vendored_cc_version": "${vendored_cc_version}",
  "vendored_cc_sha256": "${vendored_cc_sha}",
  "developer_id_identity": "${CT_SIGN_IDENTITY}",
  "notarized": true,
  "stapled": true,
  "gatekeeper_verified": true,
  "dmg_sha256": "${checksum}",
  "dmg": "$(basename "${final_dmg}")"
}
EOF

echo "release: ready"
echo "  app: ${final_app}"
echo "  dmg: ${final_dmg}"
echo "  sha256: ${checksum}"
