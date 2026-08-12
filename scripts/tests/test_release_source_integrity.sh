#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/release-source-integrity.sh"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-release-source.XXXXXX")"
cleanup() { rm -rf "${scratch}"; }
trap cleanup EXIT

startup="${scratch}/startup.sh"
marker="${scratch}/startup-ran"
printf 'printf startup > %q\n' "${marker}" > "${startup}"
/usr/bin/env BASH_ENV="${startup}" ENV="${startup}" SHELLOPTS=x BASHOPTS=x \
    'BASH_FUNC_release_payload%%=() { printf function > "'"${marker}"'"; }' \
    "${ROOT}/scripts/package-user-release" --help >/dev/null
[[ ! -e "${marker}" ]]
if CT_RELEASE_STREAM=1 CT_RELEASE_LAUNCHER_PATH="${ROOT}/scripts/package-user-release" \
   CT_RELEASE_IMPLEMENTATION_PATH="${ROOT}/scripts/package-user-release.program" \
   /bin/bash "${ROOT}/scripts/package-user-release.sh" --help >/dev/null 2>&1; then
    echo "FAIL: private Bash implementation accepted direct invocation" >&2; exit 1
fi
if (printf '%s\n' "CT_RELEASE_STREAM_CHALLENGE=forged"; \
    sed -n '1,80p' "${ROOT}/scripts/package-user-release.program") | CT_RELEASE_STREAM=1 \
   CT_RELEASE_EXPECTED_CHALLENGE=forged \
   CT_RELEASE_LAUNCHER_PATH="${ROOT}/scripts/package-user-release" \
   CT_RELEASE_IMPLEMENTATION_PATH="${ROOT}/scripts/package-user-release.program" \
   /bin/bash --noprofile --norc -s >/dev/null 2>&1; then
    echo "FAIL: foreign parent/pipe spoof was accepted" >&2; exit 1
fi
echo "PASS: public launcher blocks startup injection; direct/FD/foreign-parent entry rejects"

foreign_parent="${scratch}/foreign-parent"
/usr/bin/swiftc "${ROOT}/scripts/tests/fixtures/release-launcher/foreign-parent.swift" \
    -o "${foreign_parent}"
"${foreign_parent}" "${ROOT}"

copied="${scratch}/copied/scripts"
mkdir -p "${copied}"
cp "${ROOT}/scripts/package-user-release" \
   "${ROOT}/scripts/package-user-release.swift" \
   "${ROOT}/scripts/package-user-release.program" \
   "${ROOT}/scripts/package-user-release.sha256" "${copied}/"
# Public help is intentionally harmless. A copied bootstrap may describe its
# interface, but cannot consume release authority or enter inner mode.
"${copied}/package-user-release" --help >/dev/null
if CT_SIGN_IDENTITY=sentinel "${copied}/package-user-release" \
   --source-ref main --verify-source-only >/dev/null 2>&1; then
    echo "FAIL: copied outer bootstrap accepted release authority" >&2; exit 1
fi
cp "${ROOT}/scripts/package-user-release" "${scratch}/adhoc-launcher"
/usr/bin/codesign --remove-signature "${scratch}/adhoc-launcher"
if "${scratch}/adhoc-launcher" --help >/dev/null 2>&1; then
    echo "FAIL: unsigned launcher executed" >&2; exit 1
fi
ln -s "${ROOT}/scripts/package-user-release" "${scratch}/launcher-link"
"${scratch}/launcher-link" --help >/dev/null
echo "PASS: foreign Swift cannot replay inner program; outer help carries no authority"

platform_helper="/Applications/Xcode.app/Contents/Developer/usr/libexec/git-core/git-credential-osxkeychain"
release_validate_apple_credential_helper "${platform_helper}"
helper_copy="${scratch}/git-credential-osxkeychain"
cp "${platform_helper}" "${helper_copy}"
chmod 755 "${helper_copy}"
helper_link="${scratch}/helper-link"
ln -s "${platform_helper}" "${helper_link}"
adhoc_helper="${scratch}/adhoc-helper"
printf '#!/bin/sh\nexit 0\n' > "${adhoc_helper}"
chmod 755 "${adhoc_helper}"
for candidate in "${helper_copy}" "${helper_link}" "${adhoc_helper}" /opt/homebrew/bin/gh; do
    if release_validate_platform_executable "${candidate}" >/dev/null 2>&1; then
        echo "FAIL: mutable/symlink/ad-hoc helper accepted: ${candidate}" >&2; exit 1
    fi
done
echo "PASS: only root-owned non-symlink Apple-signed credential helper accepted"

"${ROOT}/scripts/verify-release-launcher.sh"

# Build a fully local immutable remote for the credential-free bootstrap. The
# seam is verification-only, so it can never load publisher authority.
fixture_work="${scratch}/bootstrap-work"
fixture_remote="${scratch}/bootstrap.git"
mkdir -p "${fixture_work}/scripts"
cp "${ROOT}/scripts/package-user-release" \
   "${ROOT}/scripts/package-user-release.swift" \
   "${ROOT}/scripts/package-user-release.program" \
   "${ROOT}/scripts/package-user-release.sha256" \
   "${ROOT}/scripts/verify-release-launcher.sh" "${fixture_work}/scripts/"
chmod 755 "${fixture_work}/scripts/package-user-release" \
    "${fixture_work}/scripts/verify-release-launcher.sh"
git -C "${fixture_work}" init -q -b main
git -C "${fixture_work}" config user.name fixture
git -C "${fixture_work}" config user.email fixture@example.invalid
git -C "${fixture_work}" add scripts
git -C "${fixture_work}" commit -qm fixture
git clone -q --bare "${fixture_work}" "${fixture_remote}"

bootstrap_output="$(CT_RELEASE_BOOTSTRAP_TEST_REMOTE="file://${fixture_remote}" \
    "${ROOT}/scripts/package-user-release" --source-ref main --verify-source-only)"
[[ "${bootstrap_output}" == release\ bootstrap\ source\ verified:* ]]

# A malicious dirty working-tree program and self-consistent adjacent manifest
# are irrelevant: the outer bootstrap never reads them. Release authority is
# rejected before clone, and only the program committed in the detached fixture
# can become the inner implementation.
attack_root="${scratch}/attack"
mkdir -p "${attack_root}/scripts"
cp "${ROOT}/scripts/package-user-release" \
   "${ROOT}/scripts/package-user-release.swift" \
   "${ROOT}/scripts/package-user-release.program" \
   "${ROOT}/scripts/package-user-release.sha256" "${attack_root}/scripts/"
authority_marker="${scratch}/authority-observed"
{
    printf 'printf "seen:%%s" "${CT_SIGN_IDENTITY:-missing}" > %q\n' "${authority_marker}"
    cat "${ROOT}/scripts/package-user-release.program"
} > "${attack_root}/scripts/package-user-release.program"
{
    shasum -a 256 "${attack_root}/scripts/package-user-release"
    shasum -a 256 "${attack_root}/scripts/package-user-release.swift"
    shasum -a 256 "${attack_root}/scripts/package-user-release.program"
} | sed 's#  .*/scripts/#  #' > "${attack_root}/scripts/package-user-release.sha256"
if CT_SIGN_IDENTITY=SECURITY_SENTINEL \
   CT_RELEASE_BOOTSTRAP_TEST_REMOTE="file://${fixture_remote}" \
   "${attack_root}/scripts/package-user-release" --source-ref main \
   --verify-source-only >/dev/null 2>&1; then
    echo "FAIL: credential-free bootstrap accepted signing authority" >&2; exit 1
fi
[[ ! -e "${authority_marker}" ]]
CT_RELEASE_BOOTSTRAP_TEST_REMOTE="file://${fixture_remote}" \
    "${attack_root}/scripts/package-user-release" --source-ref main \
    --verify-source-only >/dev/null
[[ ! -e "${authority_marker}" ]]
echo "PASS: immutable bootstrap ignores dirty program/manifest and observes no authority"

canonical="${RELEASE_CANONICAL_REMOTE}"
main_resolved="$(release_resolve_remote_ref "${canonical}" main)"
IFS=$'\t' read -r main_ref main_commit <<< "${main_resolved}"
[[ "${main_ref}" == "refs/heads/main" ]]
[[ "${main_commit}" == "$(git -C "${ROOT}" rev-parse origin/main)" ]]

# v0.6.9 is an annotated publisher tag in the canonical repository. The
# trusted resolver must record its peeled commit, not the tag object.
tag_resolved="$(release_resolve_remote_ref "${canonical}" v0.6.9)"
IFS=$'\t' read -r tag_ref tag_commit <<< "${tag_resolved}"
[[ "${tag_ref}" == "refs/tags/v0.6.9" ]]
[[ "${tag_commit}" == "8e85240715d01a4403dbca6a3ebc896bf614d20e" ]]

checkout="${scratch}/checkout"
release_trusted_git clone --quiet --no-checkout "${canonical}" "${checkout}"
git -C "${checkout}" checkout -q --detach "${main_commit}"
main_tree="$(git -C "${checkout}" rev-parse 'HEAD^{tree}')"
release_verify_checkout "${checkout}" "${canonical}" "${main_ref}" \
    "${main_commit}" "${main_tree}"
git -C "${checkout}" checkout -q --detach "${tag_commit}"
tag_tree="$(git -C "${checkout}" rev-parse 'HEAD^{tree}')"
release_verify_checkout "${checkout}" "${canonical}" "${tag_ref}" \
    "${tag_commit}" "${tag_tree}"
echo "PASS: canonical detached branch and peeled annotated tag"

git -C "${checkout}" checkout -q --detach "${main_commit}"
printf 'dirty\n' >> "${checkout}/README.md"
if release_verify_checkout "${checkout}" "${canonical}" "${main_ref}" \
    "${main_commit}" "${main_tree}" >/dev/null 2>&1; then
    echo "FAIL: dirty verified checkout was accepted" >&2; exit 1
fi
git -C "${checkout}" restore README.md
printf 'untracked\n' > "${checkout}/qa-untracked"
if release_verify_checkout "${checkout}" "${canonical}" "${main_ref}" \
    "${main_commit}" "${main_tree}" >/dev/null 2>&1; then
    echo "FAIL: untracked verified checkout was accepted" >&2; exit 1
fi
mv "${checkout}/qa-untracked" "${scratch}/qa-untracked"
ln -s "${scratch}/qa-untracked" "${checkout}/qa-symlink"
if release_verify_checkout "${checkout}" "${canonical}" "${main_ref}" \
    "${main_commit}" "${main_tree}" >/dev/null 2>&1; then
    echo "FAIL: untracked symlink was accepted" >&2; exit 1
fi
mv "${checkout}/qa-symlink" "${scratch}/qa-symlink"

git -C "${checkout}" switch -q -c attached-test
if release_verify_checkout "${checkout}" "${canonical}" "${main_ref}" \
    "${main_commit}" "${main_tree}" >/dev/null 2>&1; then
    echo "FAIL: attached verified checkout was accepted" >&2; exit 1
fi
git -C "${checkout}" switch -q --detach "${main_commit}"
if release_verify_checkout "${checkout}" "${canonical}" "${main_ref}" \
    "${main_commit}" 0000000000000000000000000000000000000000 >/dev/null 2>&1; then
    echo "FAIL: tree mismatch was accepted" >&2; exit 1
fi
git -C "${checkout}" update-index --add --cacheinfo \
    "160000,${main_commit},qa-submodule"
if release_verify_checkout "${checkout}" "${canonical}" "${main_ref}" \
    "${main_commit}" "${main_tree}" >/dev/null 2>&1; then
    echo "FAIL: staged gitlink/submodule was accepted" >&2; exit 1
fi
git -C "${checkout}" update-index --force-remove qa-submodule

old_commit="$(git -C "${checkout}" rev-parse "${main_commit}^")"
git -C "${checkout}" checkout -q --detach "${old_commit}"
old_tree="$(git -C "${checkout}" rev-parse 'HEAD^{tree}')"
if release_verify_checkout "${checkout}" "${canonical}" "${main_ref}" \
    "${old_commit}" "${old_tree}" >/dev/null 2>&1; then
    echo "FAIL: moved branch expectation was accepted" >&2; exit 1
fi
echo "PASS: dirty/untracked/symlink/attached/tree/gitlink/moved-ref negatives"

evil="${scratch}/evil.git"
git init --bare -q "${evil}"
rewrite_key="url.file://${evil}.insteadOf"
rewritten="$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="${rewrite_key}" \
    GIT_CONFIG_VALUE_0="${canonical}" \
    release_resolve_remote_ref "${canonical}" main)"
[[ "${rewritten}" == "${main_resolved}" ]]

global_config="${scratch}/global.gitconfig"
system_config="${scratch}/system.gitconfig"
include_config="${scratch}/include.gitconfig"
printf '[url "file://%s"]\n\tinsteadOf = %s\n' "${evil}" "${canonical}" > "${include_config}"
printf '[include]\n\tpath = %s\n' "${include_config}" > "${global_config}"
cp "${global_config}" "${system_config}"
if HOME="${scratch}" GIT_CONFIG_GLOBAL="${global_config}" \
   "${ROOT}/scripts/package-user-release" --verify-source-only >/dev/null 2>&1; then
    echo "FAIL: injected Git config environment was accepted" >&2; exit 1
fi

local_repo="${scratch}/local-repo"
git init -q "${local_repo}"
git -C "${local_repo}" config "url.file://${evil}.insteadOf" "${canonical}"
(
    cd "${local_repo}"
    [[ -z "$(HOME="${scratch}" GIT_CONFIG_GLOBAL="${global_config}" \
        GIT_CONFIG_SYSTEM="${system_config}" \
        release_trusted_git config --get-regexp '^url\.' 2>/dev/null || true)" ]]
)
echo "PASS: process/global/system/include/local URL rewrites cannot reach trusted Git"

for bad_remote in "file://${evil}" "${evil}" "https://example.invalid/repo.git"; do
    if release_resolve_remote_ref "${bad_remote}" main >/dev/null 2>&1; then
        echo "FAIL: noncanonical transport was accepted: ${bad_remote}" >&2; exit 1
    fi
done
echo "PASS: local/file/noncanonical transports rejected"

set +e
bypass_output="$(CT_RELEASE_CHECKOUT=1 CT_SIGN_IDENTITY=dummy \
    CT_NOTARY_KEYCHAIN_PROFILE=dummy \
    "${ROOT}/scripts/package-user-release" --source-ref main --verify-source-only 2>&1)"
bypass_rc=$?
set -e
[[ "${bypass_rc}" -ne 0 ]]
[[ "${bypass_output}" == "error: CT_RELEASE_CHECKOUT is not a supported release authority" ]]

root_commit="$(git -C "${ROOT}" rev-parse HEAD)"
root_tree="$(git -C "${ROOT}" rev-parse 'HEAD^{tree}')"
set +e
inner_output="$("${ROOT}/scripts/package-user-release" --verify-source-only \
    --verified-source-ref refs/heads/main \
    --verified-source-commit "${root_commit}" \
    --verified-source-tree "${root_tree}" 2>&1)"
inner_rc=$?
set -e
[[ "${inner_rc}" -ne 0 ]]
case "${inner_output}" in
    "error: verified release checkout is not clean"|\
    "error: verified release checkout must be detached") ;;
    *) echo "FAIL: forged inner arguments reached an unexpected boundary: ${inner_output}" >&2; exit 1 ;;
esac
echo "PASS: legacy environment and forged inner authority rejected"

python3 - "${ROOT}/scripts/package-user-release.program" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert '"source_ref": "${verified_source_ref}"' in text
assert '"source_commit": "${source_commit}"' in text
assert '"source_tree": "${source_tree}"' in text
assert text.count('release_verify_checkout "${REPO_ROOT}"') >= 3
assert 'checkout --quiet --detach "${local_commit}"' in text
assert 'release_trusted_git clone --quiet --no-checkout' in text
assert 'CT_RELEASE_CHECKOUT=1 \\' not in text
PY
echo "PASS: provenance binds metadata to repeatedly verified trusted Git source"

echo "release source integrity: PASS"
