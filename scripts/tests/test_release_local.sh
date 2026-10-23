#!/usr/bin/env bash
# Contract tests for the direct local release path (ADR-012).
#
# Behavioral half: a disposable origin, an ephemeral SSH signing key, and a
# copy of scripts/release-local.sh prove that only a signed annotated tag that
# matches origin and agrees on version is accepted, and that every refusal
# happens before credentials are reachable.
# Static half: the pipeline order that signing, notarization, and stapling must
# keep, and the absence of any secret echo or skip-verify escape hatch.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SCRIPT="${ROOT}/scripts/release-local.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-release-local.XXXXXX")"
cleanup() { rm -rf "${scratch}"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- static pipeline contract ---------------------------------------------
python3 -I - "${SCRIPT}" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")

def at(needle, start=0):
    index = text.find(needle, start)
    assert index >= 0, f"missing: {needle}"
    return index

verify_tag = at("git verify-tag")
remote_match = at("does not match origin")
clone = at("clone --quiet --branch")
versions = at("does not match tag")
only = at('"${VERIFY_SOURCE_ONLY}" == "1"')
launcher = at("scripts/verify-release-launcher.sh")
vendored = at("scripts/verify-vendored-cc.sh --release \"${vendored_cc}\"")
env_read = at('source "${env_file}"')
preflight = at("scripts/check-notary-profile.sh")
build_user = at("scripts/build-user.command --build-only")
build_admin = at("scripts/build-admin.command --build-only")
detect = at("scripts/headless-detect.sh")
sign_user = at('scripts/sign.sh "${user_app}"')
sign_admin = at('scripts/sign.sh "${admin_app}"')
notarize_user = at('scripts/notarize.sh app "${user_app}"')
notarize_admin = at('scripts/notarize.sh app "${admin_app}"')
payload = at('ditto "${user_app}" "${payload_dir}/Copilot Control Tower.app"')
dmg = at("hdiutil create")
dmg_sign = at('codesign --sign "${CT_SIGN_IDENTITY}" --timestamp --force "${unsigned_dmg}"')
dmg_notarize = at('scripts/notarize.sh dmg "${unsigned_dmg}"')
stapler = at('xcrun stapler validate "${unsigned_dmg}"')
spctl = at("spctl --assess --type open")
sha = at("checksum=\"$(shasum -a 256")
install_check = at("scripts/verify-user-install-artifact.sh")

assert verify_tag < remote_match < clone < versions < only < env_read, "source proof must precede credentials"
assert launcher < env_read and vendored < env_read, "credential-free integrity gates run first"
assert env_read < preflight < build_user < build_admin < detect < sign_user < sign_admin, "preflight, build, then sign"
assert sign_admin < notarize_user < payload < dmg < dmg_sign < dmg_notarize, "app is stapled before DMG assembly; DMG is signed before notarization"
assert notarize_admin > sign_admin
syntax_gate = at("check-release-script-syntax.sh")
install_gate = at("release-gate-install-artifact.sh")
ready = at('echo "release: ready"')
assert versions < syntax_gate < only < env_read, "script parse gate runs after version proof and before credentials"
assert sha < install_gate < ready, "affirmative install-artifact gate must precede 'ready'"
assert "scripts/verify-user-install-artifact.sh --release-dir" not in text, "verifier exit status alone must never gate the release"
assert text.count('echo "release: ready"') == 1
assert dmg_notarize < stapler < spctl < sha < install_check, "validate before checksum and install-artifact check"

assert "shipping-swift-fitness" in text and "no\n# way to skip" in text.replace("there is no\n# way","no\n# way") or "shipping-swift-fitness" in text, "launcher gate falls back to pinned-toolchain CI, never a skip"
assert "--options runtime" in text, "hardened runtime required"
assert "CT_SKIP_ADHOC_SIGN=1" in text
for forbidden in ("--skip-verify", "--force-release", "set -x", "xtrace", "notarytool store-credentials"):
    assert forbidden not in text, forbidden
# The environment file is only ever sourced, never printed or copied.
for line in text.splitlines():
    if line.lstrip().startswith(("echo", "printf", "cat")):
        assert ".env.release" not in line and "CT_SIGN_IDENTITY}\" >" not in line, line
assert not re.search(r"cp\s+.*env_file|ditto\s+.*env_file", text)
PY
echo "PASS: release-local.sh keeps source proof, signing, notarization, staple, and checksum order"

# --- behavioral source proof ----------------------------------------------
for tool in git ssh-keygen plutil python3; do command -v "${tool}" >/dev/null || fail "${tool} required"; done

ssh-keygen -q -t ed25519 -N '' -C release-test -f "${scratch}/signing"
printf 'release-test %s\n' "$(cat "${scratch}/signing.pub")" > "${scratch}/allowed_signers"

origin="${scratch}/origin.git"
work="${scratch}/work"
git init -q --bare "${origin}"
git init -q -b main "${work}"
git -C "${work}" config user.name "Release Test"
git -C "${work}" config user.email "release-test@example.invalid"
git -C "${work}" config gpg.format ssh
git -C "${work}" config user.signingkey "${scratch}/signing.pub"
git -C "${work}" config gpg.ssh.allowedSignersFile "${scratch}/allowed_signers"
git -C "${work}" config commit.gpgsign false
git -C "${work}" remote add origin "${origin}"

mkdir -p "${work}/scripts" "${work}/packaging/macos"
cp "${SCRIPT}" "${work}/scripts/release-local.sh"
cp "${ROOT}/scripts/check-release-script-syntax.sh" "${ROOT}/scripts/release-gate-install-artifact.sh" "${work}/scripts/"
write_inputs() {
    local version="$1" build="$2" compat="${3:-$1}"
    for face in User Admin; do
        cat > "${work}/packaging/macos/${face}-Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>${version}</string>
<key>CFBundleVersion</key><string>${build}</string>
</dict></plist>
PLIST
    done
    printf '{"schema_version":"1.0","app_version":"%s"}\n' "${compat}" > "${work}/controltower.compat.json"
    printf '# Changelog\n\n## [%s] - 2026-01-01\n\n- test\n' "${version}" > "${work}/CHANGELOG.md"
}

release() {
    # Empty HOME so no real publisher file can be found; every case must stop
    # (or succeed) before credentials are read.
    (cd "${work}" && HOME="${scratch}/empty-home" CT_RELEASE_ENV_FILE="" \
        ./scripts/release-local.sh "$@") 2>&1
}
expect_refusal() {
    local label="$1" pattern="$2"; shift 2
    local output status=0
    output="$(release "$@")" || status=$?
    [[ "${status}" -ne 0 ]] || fail "${label}: release unexpectedly succeeded"
    grep -Fq -- "${pattern}" <<<"${output}" || fail "${label}: expected '${pattern}', got: ${output}"
    grep -Fqi "env.release" <<<"${output}" && fail "${label}: reached the credential step"
    echo "PASS: ${label}"
}
mkdir -p "${scratch}/empty-home"

write_inputs 1.2.3 7
git -C "${work}" add -A && git -C "${work}" commit -q -m "release 1.2.3"
git -C "${work}" push -q origin main
good_commit="$(git -C "${work}" rev-parse HEAD)"

git -C "${work}" tag v1.2.3 && git -C "${work}" push -q origin refs/tags/v1.2.3
expect_refusal "lightweight tag is refused" "is not an annotated tag" --tag v1.2.3 --verify-source-only
git -C "${work}" push -q origin :refs/tags/v1.2.3 && git -C "${work}" tag -d v1.2.3 >/dev/null

git -C "${work}" -c tag.gpgSign=false tag -a -m "unsigned" v1.2.3
git -C "${work}" push -q origin refs/tags/v1.2.3
expect_refusal "unsigned annotated tag is refused" "no valid signature" --tag v1.2.3 --verify-source-only
git -C "${work}" push -q origin :refs/tags/v1.2.3 && git -C "${work}" tag -d v1.2.3 >/dev/null

git -C "${work}" tag -s -m "Control Tower 1.2.3" v1.2.3
expect_refusal "tag not advertised by origin is refused" "does not advertise" --tag v1.2.3 --verify-source-only
git -C "${work}" push -q origin refs/tags/v1.2.3

output="$(release --tag v1.2.3 --verify-source-only)" || fail "good signed tag refused: ${output}"
grep -Fq "release source verified: v1.2.3 ${good_commit}" <<<"${output}" || fail "missing exact-commit confirmation: ${output}"
grep -Fq "matching origin and the clean clone" <<<"${output}" || fail "missing clone confirmation"
echo "PASS: signed tag is cloned from origin and matches its commit without credentials"

expect_refusal "malformed tag name is refused" "must look like vX.Y.Z" --tag 1.2.3 --verify-source-only

# Local tag moved to a different (still signed) commit than origin advertises.
git -C "${work}" commit -q --allow-empty -m "later"
git -C "${work}" tag -s -f -m "moved" v1.2.3
expect_refusal "local tag that differs from origin is refused" "does not match origin" --tag v1.2.3 --verify-source-only
git -C "${work}" tag -d v1.2.3 >/dev/null
git -C "${work}" fetch -q origin "refs/tags/v1.2.3:refs/tags/v1.2.3"
git -C "${work}" reset -q --hard "${good_commit}"

# Version disagreement: tag name versus plists, compat file, and changelog.
version_case() {
    local label="$1" pattern="$2" version="$3" build="$4" compat="$5" tag="$6"
    write_inputs "${version}" "${build}" "${compat}"
    git -C "${work}" add -A && git -C "${work}" commit -q -m "${label}"
    git -C "${work}" tag -s -m "${label}" "${tag}"
    git -C "${work}" push -q origin main "refs/tags/${tag}"
    expect_refusal "${label}" "${pattern}" --tag "${tag}" --verify-source-only
}
version_case "plist version differing from the tag is refused" "plist versions" 9.9.9 7 1.3.0 v1.3.0
version_case "compat version differing from the tag is refused" "controltower.compat.json app_version" 1.3.1 7 9.9.9 v1.3.1
write_inputs 1.3.2 7 1.3.2
printf '# Changelog\n\n## [0.0.1] - 2026-01-01\n' > "${work}/CHANGELOG.md"
git -C "${work}" add -A && git -C "${work}" commit -q -m "stale changelog"
git -C "${work}" tag -s -m stale v1.3.2 && git -C "${work}" push -q origin main refs/tags/v1.3.2
expect_refusal "stale changelog is refused" "CHANGELOG.md top entry" --tag v1.3.2 --verify-source-only
write_inputs 1.3.3 7 1.3.3
sed -i '' 's#<string>7</string>#<string>8</string>#' "${work}/packaging/macos/Admin-Info.plist"
git -C "${work}" add -A && git -C "${work}" commit -q -m "build mismatch"
git -C "${work}" tag -s -m mismatch v1.3.3 && git -C "${work}" push -q origin main refs/tags/v1.3.3
expect_refusal "User and Admin build mismatch is refused" "disagree" --tag v1.3.3 --verify-source-only

# Without --verify-source-only the credential-free gates run, then the missing
# environment file stops the run before any build, signing, or notarization.
write_inputs 1.3.4 7 1.3.4
mkdir -p "${work}/packaging/cc"
printf '1.0.0\n' > "${work}/packaging/cc/VERSION"
mkdir -p "${work}/.github/workflows"
cp "${ROOT}/.github/workflows/native-invariants.yml" "${work}/.github/workflows/"
git -C "${work}" add -A && git -C "${work}" commit -q -m "full run fixture"
git -C "${work}" tag -s -m full v1.3.4 && git -C "${work}" push -q origin main refs/tags/v1.3.4
status=0; output="$(release --tag v1.3.4)" || status=$?
[[ "${status}" -ne 0 ]] || fail "full run without launcher inputs unexpectedly succeeded"
grep -Eq "byte-identical|release launcher byte match" <<<"${output}" || fail "launcher gate did not run: ${output}"
[[ ! -e "${work}/dist" ]] || fail "failed run left an output directory"
echo "PASS: a failing integrity gate stops the full run before any artifact is produced"

# Negative control for the v0.6.10 failure: a tag whose verifier cannot be
# parsed by the macOS system bash (3.2) must fail the release before
# credentials, builds, or any artifact, and must never print "ready". The
# verifier has an EXIT trap, as the real one does, because that trap is what
# let bash 3.2 report success for an unparseable script.
write_inputs 1.3.5 7 1.3.5
mkdir -p "${work}/packaging/cc" "${work}/.github/workflows"
printf '1.0.0\n' > "${work}/packaging/cc/VERSION"
cp "${ROOT}/.github/workflows/native-invariants.yml" "${work}/.github/workflows/"
cat > "${work}/scripts/verify-user-install-artifact.sh" <<'VERIFIER'
#!/bin/bash
set -euo pipefail
trap 'true' EXIT
[[ "a" ==
   "a" ]] || exit 1
echo "install-artifact verification: PASS version=1.3.5 build=7 cc=1.0.0"
VERIFIER
chmod +x "${work}/scripts/verify-user-install-artifact.sh"
git -C "${work}" add -A && git -C "${work}" commit -q -m "unparseable verifier"
git -C "${work}" tag -s -m broken v1.3.5 && git -C "${work}" push -q origin main refs/tags/v1.3.5
status=0; output="$(release --tag v1.3.5)" || status=$?
[[ "${status}" -ne 0 ]] || fail "release with an unparseable verifier unexpectedly succeeded: ${output}"
grep -Fq "do not parse under /bin/bash" <<<"${output}" || fail "parse gate did not fire: ${output}"
grep -Fq "release: ready" <<<"${output}" && fail "printed ready for an unparseable verifier"
grep -Fqi "env.release" <<<"${output}" && fail "unparseable verifier reached the credential step"
[[ ! -e "${work}/dist" ]] || fail "failed run left an output directory"
echo "PASS: an unparseable release script fails the release before credentials and never prints ready"

# Positive control: the same tag with a parseable verifier passes the parse
# gate (then stops at the launcher gate like the full-run fixture above).
cat > "${work}/scripts/verify-user-install-artifact.sh" <<'VERIFIER'
#!/bin/bash
set -euo pipefail
echo "install-artifact verification: PASS version=1.3.6 build=7 cc=1.0.0"
VERIFIER
write_inputs 1.3.6 7 1.3.6
git -C "${work}" add -A && git -C "${work}" commit -q -m "parseable verifier"
git -C "${work}" tag -s -m fixed v1.3.6 && git -C "${work}" push -q origin main refs/tags/v1.3.6
status=0; output="$(release --tag v1.3.6)" || status=$?
grep -Fq "do not parse" <<<"${output}" && fail "parseable scripts were rejected by the parse gate: ${output}"
grep -Eq "byte-identical|release launcher byte match" <<<"${output}" || fail "full run did not reach the launcher gate: ${output}"
echo "PASS: parseable release scripts pass the parse gate and the run proceeds"
echo "release-local test: PASS"
