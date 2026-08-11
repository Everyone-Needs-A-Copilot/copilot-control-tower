#!/usr/bin/env bash
# Finding A regression gate (`tc wp get 525`, security review WP-525):
# CliLocator.locate() used to honor CT_CLI_PATH with nothing stronger than
# "is this file executable", in every build including the shipped, notarized
# release — a local attacker able to set the app's process environment
# (e.g. `launchctl setenv CT_CLI_PATH ...`) could redirect every `cc`
# invocation the app makes to an arbitrary unverified binary. That
# contradicts CLAUDE.md invariant #4 ("nothing security-critical comes from
# user-editable local config").
#
# This proves the fix using the exact production verification code
# (`ProductionTrustAnchor`/`CliLocator.locate()` in native/cli-client.swift),
# not a re-implementation of it, against fixtures signed for real: an
# ad-hoc-signed "self" (what every dev/test build in this repo already is)
# and a REAL Developer-ID-signed "self" (what the notarized release is),
# each combined with an unsigned override candidate and a genuinely
# re-signed one.
#
# Requires this machine's Developer ID Application signing identity (see
# CLAUDE.md's credentials doctrine — a standing, owner-provisioned
# credential; scripts/sign.sh's own header notes real Developer ID signing
# "needs the owner's Apple Developer ID Application certificate, which this
# repo does not hold and CI verification cannot fabricate"). On a machine
# without that identity this test SKIPS rather than fails, matching the
# same convention scripts/package-user-release.sh and scripts/sign.sh
# already use for the identity itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIXTURE_DIR="${SCRIPT_DIR}/fixtures/cli-locator-trust"

SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null |
        awk -F'"' '/Developer ID Application/ { print $2; exit }'
)"
if [[ -z "${SIGN_IDENTITY}" ]]; then
    echo "skip: no Developer ID Application signing identity on this machine" >&2
    echo "      (owner-provisioned credential; see CLAUDE.md credentials doctrine)" >&2
    exit 0
fi

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ct-cli-locator-trust.XXXXXX")"
trap 'rm -rf "${BUILD_DIR}"' EXIT

cat > "${BUILD_DIR}/dummy.c" <<'EOF'
int main(void) { return 0; }
EOF
/usr/bin/cc -o "${BUILD_DIR}/dummy" "${BUILD_DIR}/dummy.c"

# Four fixtures, all built from the same trivial Mach-O so only the SIGNATURE
# differs: the "self" this process is pretending to be (production-signed vs.
# ad-hoc, i.e. every real dev/test build), and the CT_CLI_PATH override
# candidate (unverified vs. genuinely re-signed by the same identity).
production_signed_self="${BUILD_DIR}/production-signed-self"
adhoc_signed_self="${BUILD_DIR}/adhoc-signed-self"
unverified_override="${BUILD_DIR}/unverified-override"
trusted_override="${BUILD_DIR}/trusted-override"
bundled_dir="${BUILD_DIR}/bundled"
mkdir -p "${bundled_dir}"

cp "${BUILD_DIR}/dummy" "${production_signed_self}"
codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${production_signed_self}" >/dev/null 2>&1

cp "${BUILD_DIR}/dummy" "${adhoc_signed_self}"
codesign --force --sign - "${adhoc_signed_self}" >/dev/null 2>&1

cp "${BUILD_DIR}/dummy" "${unverified_override}"
codesign --remove-signature "${unverified_override}" >/dev/null 2>&1 || true

cp "${BUILD_DIR}/dummy" "${trusted_override}"
codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${trusted_override}" >/dev/null 2>&1

# What CliLocator falls back to when it refuses the override — a stand-in
# for the app's own bundled, checksum-pinned Contents/Resources/cc.
cp "${BUILD_DIR}/dummy" "${bundled_dir}/cc"
codesign --remove-signature "${bundled_dir}/cc" >/dev/null 2>&1 || true

CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc \
    "${ROOT_DIR}/native/cli-dtos.swift" \
    "${ROOT_DIR}/native/cli-client.swift" \
    "${FIXTURE_DIR}/main.swift" \
    -o "${BUILD_DIR}/cli-locator-trust"

output="$(
    "${BUILD_DIR}/cli-locator-trust" \
        "${production_signed_self}" \
        "${adhoc_signed_self}" \
        "${bundled_dir}" \
        "${unverified_override}" \
        "${trusted_override}"
)"
echo "${output}"

if [[ "${output}" != *"cli-locator trust boundary: ALL ASSERTIONS PASSED"* ]]; then
    echo "cli locator trust boundary gate: FAIL" >&2
    exit 1
fi

echo "cli locator trust boundary gate: PASS"
