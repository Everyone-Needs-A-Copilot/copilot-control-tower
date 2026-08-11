#!/bin/bash
# Verify the exact drag-install payload while never executing code from the
# mounted DMG. Running a bundled helper in-place on a disk image makes macOS
# treat the app as accessing a removable volume and can trigger repeated TCC
# prompts. Copy first, detach, then execute and assess the local copy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RELEASE_DIR=""

usage() {
    cat <<'EOF'
Usage: scripts/verify-user-install-artifact.sh --release-dir PATH

PATH must contain release-metadata.json, the named DMG, and its .sha256 file.
The DMG is mounted read-only, copied to a private temporary install directory,
and detached before any executable inside the app is run.
EOF
}

die() {
    echo "install-artifact verification: $*" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release-dir)
            [[ $# -ge 2 ]] || die "--release-dir requires a path"
            RELEASE_DIR="$2"
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

[[ -n "${RELEASE_DIR}" ]] || die "--release-dir is required"
case "${RELEASE_DIR}" in
    /*) ;;
    *) RELEASE_DIR="${REPO_ROOT}/${RELEASE_DIR}" ;;
esac
[[ -d "${RELEASE_DIR}" ]] || die "release directory not found: ${RELEASE_DIR}"

metadata="${RELEASE_DIR}/release-metadata.json"
[[ -f "${metadata}" ]] || die "release metadata not found: ${metadata}"

IFS=$'\t' read -r dmg_name expected_version expected_build expected_cc_version expected_cc_sha < <(
    /usr/bin/python3 - "${metadata}" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
values = [
    payload.get("dmg"),
    payload.get("version"),
    payload.get("build_number"),
    payload.get("vendored_cc_version"),
    payload.get("vendored_cc_sha256"),
]
if not all(isinstance(value, str) and value for value in values):
    raise SystemExit("release metadata is missing an install-verification field")
print("\t".join(values))
PY
)

[[ "${dmg_name}" == "$(basename "${dmg_name}")" && "${dmg_name}" == *.dmg ]] ||
    die "release metadata contains an unsafe DMG name"
dmg="${RELEASE_DIR}/${dmg_name}"
checksum_file="${dmg}.sha256"
[[ -f "${dmg}" && -f "${checksum_file}" ]] ||
    die "DMG or checksum sidecar is missing"

(
    cd "${RELEASE_DIR}"
    shasum -a 256 -c "$(basename "${checksum_file}")"
)

scratch="$(mktemp -d "${TMPDIR:-/tmp}/control-tower-install-verify.XXXXXX")"
mount_dir="${scratch}/mounted-dmg"
install_dir="${scratch}/Applications"
mkdir "${mount_dir}" "${install_dir}"
attached=0
cleanup() {
    if [[ "${attached}" -eq 1 ]]; then
        hdiutil detach "${mount_dir}" -quiet >/dev/null 2>&1 || true
    fi
    case "${scratch}" in
        "${TMPDIR:-/tmp}"/control-tower-install-verify.*)
            rm -rf -- "${scratch}"
            ;;
    esac
}
trap cleanup EXIT

hdiutil attach -nobrowse -readonly -mountpoint "${mount_dir}" "${dmg}" -quiet
attached=1
mounted_app="${mount_dir}/Copilot Control Tower.app"
[[ -d "${mounted_app}" ]] || die "mounted DMG does not contain the app"
installed_app="${install_dir}/Copilot Control Tower.app"
ditto "${mounted_app}" "${installed_app}"
hdiutil detach "${mount_dir}" -quiet
attached=0

# Everything executable below is now on the normal local filesystem. The DMG
# is already detached, so neither the app nor its helper can request access to
# a removable volume merely because verification launched it in place.
plist="${installed_app}/Contents/Info.plist"
helper="${installed_app}/Contents/Resources/cc"
helper_version_resource="${installed_app}/Contents/Resources/cc-version.txt"
[[ "$(plutil -extract CFBundleShortVersionString raw "${plist}")" == "${expected_version}" ]] ||
    die "installed app version does not match release metadata"
[[ "$(plutil -extract CFBundleVersion raw "${plist}")" == "${expected_build}" ]] ||
    die "installed app build does not match release metadata"
[[ "$(tr -d '\n' < "${helper_version_resource}")" == "${expected_cc_version}" ]] ||
    die "installed helper version resource does not match release metadata"
[[ "$(shasum -a 256 "${helper}" | awk '{print $1}')" == "${expected_cc_sha}" ]] ||
    die "installed helper checksum does not match release metadata"
[[ "$("${helper}" --version)" == "cc version ${expected_cc_version}" ]] ||
    die "installed helper reports an unexpected version"

codesign --verify --deep --strict --verbose=2 "${installed_app}"
xcrun stapler validate "${installed_app}"
spctl --assess --type execute --verbose=4 "${installed_app}"
xcrun stapler validate "${dmg}"
spctl --assess --type open --context context:primary-signature --verbose=4 "${dmg}"
"${SCRIPT_DIR}/verify-user-automation.sh" "${installed_app}" >/dev/null

echo "install-artifact verification: PASS version=${expected_version} build=${expected_build} cc=${expected_cc_version}"
