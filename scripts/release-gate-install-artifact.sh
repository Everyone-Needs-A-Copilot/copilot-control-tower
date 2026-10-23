#!/bin/bash
# Affirmative install-artifact gate for release-local.sh.
#
#   scripts/release-gate-install-artifact.sh --verifier PATH --release-dir DIR \
#       --version V --build B --cc C
#
# A zero exit from the verifier is not enough. bash 3.2 reports a syntax error
# partway through a script, runs the script's EXIT trap, and lets that trap's
# status (0) replace the failure, so an unparseable verifier can exit 0 having
# verified nothing. This gate therefore (1) parses the verifier with /bin/bash -n,
# (2) requires exit 0, and (3) requires the verifier to have printed exactly the
# PASS line for this release's version, build, and cc version.

set -euo pipefail

VERIFIER="" RELEASE_DIR="" VERSION="" BUILD="" CC_VERSION=""
die() { echo "install-artifact gate: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    [[ $# -ge 2 ]] || die "$1 requires a value"
    case "$1" in
        --verifier) VERIFIER="$2" ;;
        --release-dir) RELEASE_DIR="$2" ;;
        --version) VERSION="$2" ;;
        --build) BUILD="$2" ;;
        --cc) CC_VERSION="$2" ;;
        *) die "unknown option: $1" ;;
    esac
    shift 2
done
[[ -n "${VERIFIER}" && -n "${RELEASE_DIR}" && -n "${VERSION}" && -n "${BUILD}" && -n "${CC_VERSION}" ]] ||
    die "--verifier, --release-dir, --version, --build, and --cc are all required"
[[ -x "${VERIFIER}" ]] || die "verifier is missing or not executable: ${VERIFIER}"

/bin/bash -n "${VERIFIER}" || die "verifier does not parse under /bin/bash -n: ${VERIFIER}"

log="$(mktemp "${TMPDIR:-/tmp}/install-gate.XXXXXX")"
trap 'rm -f "${log}"' EXIT
status=0
"${VERIFIER}" --release-dir "${RELEASE_DIR}" >"${log}" 2>&1 || status=$?
cat "${log}"
[[ "${status}" -eq 0 ]] || die "verifier exited ${status}"

expected="install-artifact verification: PASS version=${VERSION} build=${BUILD} cc=${CC_VERSION}"
[[ "$(grep -cFx -- "${expected}" "${log}" || true)" -eq 1 ]] ||
    die "verifier did not affirm: ${expected}"
echo "install-artifact gate: PASS"
