#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
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
    echo "FAIL: inert Bash adapter accepted direct invocation" >&2; exit 1
fi
echo "PASS: compiled public launcher does not execute caller shell startup files"

"${ROOT}/scripts/verify-release-launcher.sh"

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
echo "PASS: credential-free bare-store bootstrap verifies a no-.git materialization"

# A dirty invoking checkout is data only. The bootstrap never reads its program
# or adjacent self-consistent manifest and rejects release authority before any
# remote or trusted-source operation.
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
    echo "FAIL: outer bootstrap accepted signing authority" >&2; exit 1
fi
[[ ! -e "${authority_marker}" ]]
CT_RELEASE_BOOTSTRAP_TEST_REMOTE="file://${fixture_remote}" \
    "${attack_root}/scripts/package-user-release" --source-ref main \
    --verify-source-only >/dev/null
[[ ! -e "${authority_marker}" ]]
echo "PASS: dirty program and manifest cannot observe publisher authority"

# Local repository configuration, include files, helpers, and URL rewrites are
# irrelevant because every Git process starts in the bootstrap-created private
# workspace with global/system config disabled.
evil="${scratch}/evil.git"
git init --bare -q "${evil}"
local_repo="${scratch}/local-repo"
git init -q "${local_repo}"
git -C "${local_repo}" config "url.file://${evil}.insteadOf" "file://${fixture_remote}"
helper_marker="${scratch}/helper-ran"
helper="${scratch}/helper"
printf '#!/bin/sh\nprintf ran > %q\nexit 1\n' "${helper_marker}" > "${helper}"
chmod 755 "${helper}"
git -C "${local_repo}" config credential.helper "!${helper}"
(
    cd "${local_repo}"
    CT_RELEASE_BOOTSTRAP_TEST_REMOTE="file://${fixture_remote}" \
        "${ROOT}/scripts/package-user-release" --source-ref main \
        --verify-source-only >/dev/null
)
[[ ! -e "${helper_marker}" ]]

global_config="${scratch}/global.gitconfig"
printf '[url "file://%s"]\n\tinsteadOf = file://%s\n' \
    "${evil}" "${fixture_remote}" > "${global_config}"
set +e
injected_output="$(GIT_CONFIG_GLOBAL="${global_config}" \
    CT_RELEASE_BOOTSTRAP_TEST_REMOTE="file://${fixture_remote}" \
    "${ROOT}/scripts/package-user-release" --source-ref main \
    --verify-source-only 2>&1)"
injected_rc=$?
set -e
[[ "${injected_rc}" -ne 0 && "${injected_output}" == error:\ Git\ or\ shell\ authority* ]]
[[ ! -e "${helper_marker}" ]]
echo "PASS: local and injected Git authority cannot redirect or execute trusted Git"

# Git tree links and gitlinks are refused rather than materialized into a build
# source where they could escape or introduce a second repository.
linked_work="${scratch}/linked-work"
linked_remote="${scratch}/linked.git"
cp -R "${fixture_work}" "${linked_work}"
ln -s ../outside "${linked_work}/unsafe-link"
git -C "${linked_work}" add unsafe-link
git -C "${linked_work}" commit -qm linked
git clone -q --bare "${linked_work}" "${linked_remote}"
if CT_RELEASE_BOOTSTRAP_TEST_REMOTE="file://${linked_remote}" \
   "${ROOT}/scripts/package-user-release" --source-ref main \
   --verify-source-only >/dev/null 2>&1; then
    echo "FAIL: symlink-bearing release tree was accepted" >&2; exit 1
fi
echo "PASS: symlink-bearing source tree fails closed"

set +e
bypass_output="$(CT_RELEASE_CHECKOUT=1 \
    "${ROOT}/scripts/package-user-release" --source-ref main --verify-source-only 2>&1)"
bypass_rc=$?
set -e
[[ "${bypass_rc}" -ne 0 ]]
[[ "${bypass_output}" == "error: CT_RELEASE_CHECKOUT is not a supported release authority" ]]

python3 - "${ROOT}/scripts/package-user-release.swift" \
    "${ROOT}/scripts/package-user-release.program" <<'PY'
from pathlib import Path
import sys

swift = Path(sys.argv[1]).read_text(encoding="utf-8")
program = Path(sys.argv[2]).read_text(encoding="utf-8")

assert '"init", "--bare"' in swift
assert '"ls-tree", "-rz", "--full-tree"' in swift
assert '"cat-file", "blob"' in swift
assert 'materialized source must not contain Git metadata' in swift
assert 'git clone' not in swift
assert '["-C",' not in swift
assert 'credential.helper=' in swift
assert 'protocol.file.allow=never' in swift
assert 'http.followRedirects=false' in swift

assert "release_verify_checkout" not in program
assert "release_trusted_git" not in program
assert "git -C" not in program
assert "verify_materialized_source" in program
assert program.count("verify_materialized_source") >= 4
assert 'CT_VENDORED_CC_PATH must name a regular' in program
assert '"source_ref": "${verified_source_ref}"' in program
assert '"source_commit": "${source_commit}"' in program
assert '"source_tree": "${source_tree}"' in program
PY
echo "PASS: static gate enforces bare-store/no-.git/config-null source contract"

echo "release source integrity: PASS"
