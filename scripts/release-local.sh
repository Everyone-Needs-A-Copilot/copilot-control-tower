#!/bin/bash
# Direct local release: the publisher runs ONE command on their own Mac.
#
#   scripts/release-local.sh --tag vX.Y.Z [--output-dir PATH] [--verify-source-only]
#
# Active release path per ADR-012 (docs/40-initiatives/06-copilot-solution-
# ecosystem-outcome/decisions/adr-012-direct-local-developer-id-release.md).
# It supersedes the Publisher Bootstrap requirement, which stays in the
# repository inactive (scripts/package-user-release*, publisher-bootstrap/).
#
# This script is the tool; the exact signed tag is the source being released.
# It clones the tag from origin, proves the clone is that tag's commit, builds
# the User app and Admin bundle from that clone, signs both with the Developer
# ID Application identity (hardened runtime), assembles and signs the DMG,
# notarizes with the saved notarytool keychain profile, staples, verifies with
# stapler and spctl, and writes the SHA-256.
#
# Credentials are read from the publisher's mode-0600 .env.release.local only
# after the source proof, and are never printed, copied, or written anywhere.
# Nothing here has a skip-verify or force path (invariant 4).

set -euo pipefail
unset BASH_ENV ENV

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
EXPECTED_TEAM_ID="${CT_EXPECTED_TEAM_ID:-3SYGVX2HB8}"
TAG=""
OUTPUT_DIR=""
VERIFY_SOURCE_ONLY=0

usage() {
    cat <<'EOF'
Usage: scripts/release-local.sh --tag vX.Y.Z [options]

Options:
  --tag TAG             Signed annotated release tag to build (required).
  --output-dir PATH     Final artifact directory. Defaults to dist/release-X.Y.Z.
  --verify-source-only  Prove the tag and version agreement, then stop before
                        credentials, builds, signing, or notarization.
  -h, --help            Show this help.

Run from the publisher's checkout on the publisher's Mac. The tag must exist
locally, be annotated, carry a valid signature, and peel to the same commit
that origin advertises. Credentials come from the mode-0600
.env.release.local (CT_SIGN_IDENTITY, CT_NOTARY_KEYCHAIN_PROFILE).
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
        --tag)
            [[ $# -ge 2 ]] || die "--tag requires a value"
            TAG="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || die "--output-dir requires a value"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --verify-source-only)
            VERIFY_SOURCE_ONLY=1
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

[[ -n "${TAG}" ]] || die "--tag is required"
[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--tag must look like vX.Y.Z"
VERSION="${TAG#v}"

for tool in git shasum plutil python3; do
    require_cmd "${tool}"
done

# ---------------------------------------------------------------------------
# 1. Source proof: signed annotated tag == origin's commit == cloned commit.
# ---------------------------------------------------------------------------
cd "${REPO_ROOT}"

tag_type="$(git cat-file -t "refs/tags/${TAG}" 2>/dev/null)" ||
    die "tag ${TAG} does not exist locally"
[[ "${tag_type}" == "tag" ]] || die "${TAG} is not an annotated tag"
git verify-tag "${TAG}" >/dev/null 2>&1 ||
    die "tag ${TAG} has no valid signature (git verify-tag failed)"
tag_object="$(git rev-parse "refs/tags/${TAG}")"
tag_commit="$(git rev-parse "refs/tags/${TAG}^{commit}")"

remote_url="$(git remote get-url origin)"
remote_refs="$(git ls-remote "${remote_url}" "refs/tags/${TAG}" "refs/tags/${TAG}^{}")" ||
    die "could not query origin for ${TAG}"
remote_object="$(printf '%s\n' "${remote_refs}" | awk -v ref="refs/tags/${TAG}" '$2 == ref { print $1 }')"
remote_commit="$(printf '%s\n' "${remote_refs}" | awk -v ref="refs/tags/${TAG}^{}" '$2 == ref { print $1 }')"
[[ -n "${remote_object}" && -n "${remote_commit}" ]] ||
    die "origin does not advertise annotated tag ${TAG}"
[[ "${remote_object}" == "${tag_object}" && "${remote_commit}" == "${tag_commit}" ]] ||
    die "local ${TAG} (${tag_commit}) does not match origin (${remote_commit})"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/control-tower-release.XXXXXX")"
chmod 700 "${scratch}"
cleanup() {
    rm -rf "${scratch}"
}
trap cleanup EXIT

checkout="${scratch}/checkout"
git -c advice.detachedHead=false -c core.hooksPath=/dev/null \
    clone --quiet --branch "${TAG}" --single-branch "${remote_url}" "${checkout}"
cloned_commit="$(git -C "${checkout}" rev-parse HEAD)"
cloned_tag_object="$(git -C "${checkout}" rev-parse "refs/tags/${TAG}")"
[[ "${cloned_commit}" == "${tag_commit}" && "${cloned_tag_object}" == "${tag_object}" ]] ||
    die "cloned ${TAG} changed during release preparation"
echo "release: ${TAG} is a signed tag at ${tag_commit}, matching origin and the clean clone"

assert_source_unmodified() {
    # Builds must never edit tracked source, and untracked non-ignored files
    # must not appear: the bytes signed are the bytes of the tag.
    [[ "$(git -C "${checkout}" rev-parse HEAD)" == "${tag_commit}" ]] ||
        die "checkout HEAD moved away from ${tag_commit}"
    [[ -z "$(git -C "${checkout}" status --porcelain)" ]] ||
        die "checkout no longer matches ${TAG}"
}

# ---------------------------------------------------------------------------
# 2. Version / compatibility agreement across everything that declares it.
# ---------------------------------------------------------------------------
user_plist="${checkout}/packaging/macos/User-Info.plist"
admin_plist="${checkout}/packaging/macos/Admin-Info.plist"
compat_file="${checkout}/controltower.compat.json"
changelog="${checkout}/CHANGELOG.md"
for required in "${user_plist}" "${admin_plist}" "${compat_file}" "${changelog}"; do
    [[ -f "${required}" ]] || die "missing release input in ${TAG}: ${required#${checkout}/}"
done

user_version="$(plutil -extract CFBundleShortVersionString raw "${user_plist}")"
admin_version="$(plutil -extract CFBundleShortVersionString raw "${admin_plist}")"
user_build="$(plutil -extract CFBundleVersion raw "${user_plist}")"
admin_build="$(plutil -extract CFBundleVersion raw "${admin_plist}")"
compat_version="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["app_version"])' "${compat_file}")"
changelog_version="$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' "${changelog}" | head -n 1)"

[[ "${user_version}" == "${VERSION}" && "${admin_version}" == "${VERSION}" ]] ||
    die "plist versions (${user_version}, ${admin_version}) do not match tag ${TAG}"
[[ "${user_build}" == "${admin_build}" ]] ||
    die "User build ${user_build} and Admin build ${admin_build} disagree"
[[ "${compat_version}" == "${VERSION}" ]] ||
    die "controltower.compat.json app_version ${compat_version} does not match tag ${TAG}"
[[ "${changelog_version}" == "${VERSION}" ]] ||
    die "CHANGELOG.md top entry ${changelog_version} does not match tag ${TAG}"
echo "release: version ${VERSION} build ${user_build} agrees across plists, compat file, and changelog"

# Every script the release will run must parse under the macOS system bash
# (3.2). The tool's own checker judges the tag's files, so a tag cannot weaken
# the check, and a parse error stops the release before credentials or builds.
"${SCRIPT_DIR}/check-release-script-syntax.sh" "${checkout}" ||
    die "release scripts in ${TAG} do not parse under /bin/bash (3.2); refusing to release"

if [[ "${VERIFY_SOURCE_ONLY}" == "1" ]]; then
    echo "release source verified: ${TAG} ${tag_commit}"
    exit 0
fi

# ---------------------------------------------------------------------------
# 3. Integrity gates that need no credentials.
# ---------------------------------------------------------------------------
for tool in codesign ditto hdiutil spctl xcrun security swiftc; do
    require_cmd "${tool}"
done
[[ "$(uname -s)" == "Darwin" ]] || die "release builds run on macOS only"

[[ -n "${OUTPUT_DIR}" ]] || OUTPUT_DIR="${REPO_ROOT}/dist/release-${VERSION}"
case "${OUTPUT_DIR}" in
    /*) ;;
    *) OUTPUT_DIR="${REPO_ROOT}/${OUTPUT_DIR}" ;;
esac
[[ ! -e "${OUTPUT_DIR}" ]] || die "output directory already exists: ${OUTPUT_DIR}"

cd "${checkout}"
# The committed launcher is reproducible only under the toolchain pinned in
# .github/workflows/native-invariants.yml. On that toolchain the byte match runs
# here. On any other toolchain a local compile cannot be byte-identical, so the
# same gate must already have passed in CI for this exact commit; there is no
# way to skip it.
pinned_swift="$(sed -n "s/.*grep -F 'swiftlang-\([0-9.]*\)'.*/\1/p" .github/workflows/native-invariants.yml | head -n 1)"
[[ -n "${pinned_swift}" ]] || die "could not read the pinned Swift toolchain from native-invariants.yml"
if swiftc --version 2>&1 | grep -Fq "swiftlang-${pinned_swift}"; then
    echo "release: proving the committed release launcher is byte-identical to its source"
    scripts/verify-release-launcher.sh
else
    echo "release: local Swift toolchain is not the pinned swiftlang-${pinned_swift}; requiring the pinned-toolchain CI launcher byte match for ${tag_commit}"
    ci_repo="$(printf '%s' "${remote_url}" | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')"
    ci_conclusion="$(gh api "repos/${ci_repo}/commits/${tag_commit}/check-runs" \
        --jq '[.check_runs[] | select(.name == "shipping-swift-fitness")] | map(.conclusion) | if length == 0 then "missing" else .[0] end' 2>/dev/null)" ||
        die "release launcher byte match: could not read the CI result for ${tag_commit}"
    [[ "${ci_conclusion}" == "success" ]] ||
        die "release launcher byte match: CI check shipping-swift-fitness is '${ci_conclusion}' for ${tag_commit}, not success"
    echo "release: CI shipping-swift-fitness (launcher byte match, pinned toolchain) succeeded for ${tag_commit}"
fi

vendored_cc="${checkout}/packaging/cc/cc"
vendored_cc_version="$(<"${checkout}/packaging/cc/VERSION")"
echo "release: verifying the pinned vendored cc helper and compatibility range"
scripts/verify-vendored-cc.sh --release "${vendored_cc}"
vendored_cc_sha="$(shasum -a 256 "${vendored_cc}" | awk '{print $1}')"

# ---------------------------------------------------------------------------
# 4. Credentials: read only now, only from the publisher's private file.
# ---------------------------------------------------------------------------
env_file=""
for candidate in \
    "${CT_RELEASE_ENV_FILE:-}" \
    "${REPO_ROOT}/.env.release.local" \
    "${HOME}/Library/Application Support/Copilot Control Tower Publisher/.env.release.local"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
        env_file="${candidate}"
        break
    fi
done
[[ -n "${env_file}" ]] || die "no .env.release.local found (run Publisher Setup or scripts/setup-publisher.sh)"
[[ ! -L "${env_file}" ]] || die "release environment file must not be a symlink"
[[ "$(stat -f '%u' "${env_file}")" == "$(id -u)" ]] ||
    die "release environment file is not owned by the current user"
[[ "$(stat -f '%Lp' "${env_file}")" == "600" ]] ||
    die "release environment file must have mode 600"
# The file holds only export lines for the identity and notary profile name.
# shellcheck disable=SC1090
source "${env_file}"

[[ -n "${CT_SIGN_IDENTITY:-}" ]] || die "CT_SIGN_IDENTITY is not set in the release environment file"
[[ -n "${CT_NOTARY_KEYCHAIN_PROFILE:-}" ]] ||
    die "CT_NOTARY_KEYCHAIN_PROFILE is not set in the release environment file"
case "${CT_SIGN_IDENTITY}" in
    "Developer ID Application: "*"(${EXPECTED_TEAM_ID})") ;;
    *) die "CT_SIGN_IDENTITY is not a Developer ID Application identity for team ${EXPECTED_TEAM_ID}" ;;
esac
security find-identity -v -p codesigning | grep -F -- "${CT_SIGN_IDENTITY}" >/dev/null ||
    die "the Developer ID Application identity is not usable in this Mac's keychains"
export CT_SIGN_IDENTITY CT_NOTARY_KEYCHAIN_PROFILE

echo "release: preflighting the notarization profile before any expensive work"
preflight_log="${scratch}/notary-preflight.log"
if ! scripts/check-notary-profile.sh \
        --profile "${CT_NOTARY_KEYCHAIN_PROFILE}" \
        --evidence "${checkout}/packaging/cc/NOTARIZATION.json" >"${preflight_log}" 2>&1; then
    cat "${preflight_log}" >&2
    if grep -Eqi '403|agreement' "${preflight_log}"; then
        echo "error: Apple rejected the notarization request (HTTP 403). A required Apple Developer agreement is missing or expired; only the account holder can accept it at https://developer.apple.com/account. Re-run this command afterwards." >&2
    fi
    exit 1
fi
cat "${preflight_log}"

# ---------------------------------------------------------------------------
# 5. Build from the clean checkout.
# ---------------------------------------------------------------------------
user_app="${checkout}/build/Copilot Control Tower.app"
admin_app="${checkout}/build/Copilot Control Tower Admin.app"
stage_dir="${scratch}/stage"
payload_dir="${stage_dir}/payload"
mkdir -p "${stage_dir}"

echo "release: building the User app and Admin bundle from ${tag_commit}"
CT_FORCE_REBUILD=1 CT_SKIP_ADHOC_SIGN=1 CT_VENDORED_CC_PATH="${vendored_cc}" \
    bash scripts/build-user.command --build-only >/dev/null
CT_FORCE_REBUILD=1 bash scripts/build-admin.command --build-only >/dev/null

# The headless proofs run BEFORE Developer ID signing, deliberately: the
# CT_CLI_PATH mock-cc override is honored only by a process that is not the
# production-signed article. Moving them below signing would turn an inert
# proof into a live `onboard --apply` against this Mac's real HOME.
echo "release: exercising the exact app Detect seam without UI"
scripts/headless-detect.sh --app "${user_app}" > "${stage_dir}/headless-detect.json"
echo "release: exercising the exact app Set up -> Verify orchestration without live writes"
scripts/headless-setup-transaction.sh --app "${user_app}" > "${stage_dir}/headless-setup-transaction.txt"
echo "release: proving crash-only launchd install, restart, clean-exit, and uninstall"
scripts/tests/test_native_watchdog.sh

assert_source_unmodified

# ---------------------------------------------------------------------------
# 6. Developer ID signing (hardened runtime, inside-out).
# ---------------------------------------------------------------------------
echo "release: applying Developer ID signature to the User app"
scripts/sign.sh "${user_app}"
scripts/verify-user-automation.sh "${user_app}"
embedded_cc="${user_app}/Contents/Resources/cc"
[[ "$(shasum -a 256 "${embedded_cc}" | awk '{print $1}')" == "${vendored_cc_sha}" ]] ||
    die "embedded cc changed while building the app"
echo "release: verifying helper provenance and disposable reconciliation contract"
scripts/verify-vendored-cc.sh --release "${embedded_cc}"

echo "release: applying Developer ID signature to the Admin bundle"
for tool in gh jq; do
    nested="${admin_app}/Contents/Resources/bin/${tool}"
    [[ -f "${nested}" ]] || die "Admin bundle is missing bundled ${tool}"
    codesign --sign "${CT_SIGN_IDENTITY}" --options runtime --timestamp --force "${nested}"
done
scripts/sign.sh "${admin_app}"

# ---------------------------------------------------------------------------
# 7. Notarize and staple. The app is stapled before the DMG payload is built
#    so the copied app carries its offline ticket.
# ---------------------------------------------------------------------------
echo "release: notarizing and stapling the User app before assembling the DMG"
scripts/notarize.sh app "${user_app}"
echo "release: notarizing and stapling the Admin bundle"
scripts/notarize.sh app "${admin_app}"

build_number="$(plutil -extract CFBundleVersion raw "${user_app}/Contents/Info.plist")"
built_version="$(plutil -extract CFBundleShortVersionString raw "${user_app}/Contents/Info.plist")"
[[ "${built_version}" == "${VERSION}" ]] || die "built app version ${built_version} is not ${VERSION}"
architecture="$(uname -m)"
artifact_base="Copilot-Control-Tower_${VERSION}_${architecture}"
unsigned_dmg="${stage_dir}/${artifact_base}.dmg"

mkdir -p "${payload_dir}"
ditto "${user_app}" "${payload_dir}/Copilot Control Tower.app"
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
codesign --verify --strict --verbose=2 "${unsigned_dmg}"

echo "release: notarizing and stapling the DMG"
scripts/notarize.sh dmg "${unsigned_dmg}"

# ---------------------------------------------------------------------------
# 8. Final verification, then publish artifacts into the output directory.
# ---------------------------------------------------------------------------
xcrun stapler validate "${user_app}"
xcrun stapler validate "${admin_app}"
xcrun stapler validate "${unsigned_dmg}"
codesign --verify --strict --deep --verbose=2 "${user_app}"
codesign --verify --strict --deep --verbose=2 "${admin_app}"
spctl --assess --type execute --verbose=4 "${user_app}"
spctl --assess --type execute --verbose=4 "${admin_app}"
spctl --assess --type open --context context:primary-signature --verbose=4 "${unsigned_dmg}"

assert_source_unmodified

mkdir -p "${OUTPUT_DIR}"
final_app="${OUTPUT_DIR}/Copilot Control Tower.app"
final_dmg="${OUTPUT_DIR}/${artifact_base}.dmg"
admin_zip="${OUTPUT_DIR}/Copilot-Control-Tower-Admin_${VERSION}_${architecture}.zip"
ditto "${user_app}" "${final_app}"
ditto "${unsigned_dmg}" "${final_dmg}"
ditto -c -k --keepParent "${admin_app}" "${admin_zip}"
ditto "${compat_file}" "${OUTPUT_DIR}/controltower.compat.json"
ditto "${checkout}/packaging/cc/NOTARIZATION.json" "${OUTPUT_DIR}/cc-notarization.json"

checksum="$(shasum -a 256 "${final_dmg}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "$(basename "${final_dmg}")" > "${final_dmg}.sha256"
admin_checksum="$(shasum -a 256 "${admin_zip}" | awk '{print $1}')"
printf '%s  %s\n' "${admin_checksum}" "$(basename "${admin_zip}")" > "${admin_zip}.sha256"

cat > "${OUTPUT_DIR}/release-metadata.json" <<EOF
{
  "schema_version": "1.0",
  "release_path": "direct-local-developer-id (ADR-012)",
  "source_ref": "refs/tags/${TAG}",
  "source_commit": "${tag_commit}",
  "source_tag_object": "${tag_object}",
  "bundle_identifier": "com.everyoneneedsacopilot.controltower",
  "version": "${VERSION}",
  "build_number": "${build_number}",
  "architecture": "${architecture}",
  "vendored_cc_version": "${vendored_cc_version}",
  "vendored_cc_sha256": "${vendored_cc_sha}",
  "headless_detect": "passed",
  "developer_id_identity": "${CT_SIGN_IDENTITY}",
  "notarized": true,
  "stapled": true,
  "gatekeeper_verified": true,
  "dmg_sha256": "${checksum}",
  "dmg": "$(basename "${final_dmg}")",
  "admin_zip_sha256": "${admin_checksum}",
  "admin_zip": "$(basename "${admin_zip}")"
}
EOF

echo "release: verifying the drag-installed artifact without executing from the mounted DMG"
# Fail closed: the verifier's exit status alone is not trusted. The tool's gate
# parses the verifier and requires its exact PASS line for this release.
"${SCRIPT_DIR}/release-gate-install-artifact.sh" \
    --verifier "${checkout}/scripts/verify-user-install-artifact.sh" \
    --release-dir "${OUTPUT_DIR}" \
    --version "${VERSION}" \
    --build "${build_number}" \
    --cc "${vendored_cc_version}" ||
    die "install-artifact verification did not affirmatively pass; the release is NOT ready"

echo "release: ready"
echo "  app: ${final_app}"
echo "  dmg: ${final_dmg}"
echo "  sha256: ${checksum}"
echo "  admin: ${admin_zip}"
echo "  admin sha256: ${admin_checksum}"
