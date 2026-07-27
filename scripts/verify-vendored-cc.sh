#!/bin/bash
# M4 Stream-D / S8 — verify-not-resign gate for the vendored `cc` binary
# (ADR-M4-005, memory `m4-distribution-decisions`, fixes B-C4/A-C2/B-H1/B-M5).
#
# Control Tower is a single owner of the vendored CLI but never a second
# signing authority: this script VERIFIES the artifact `claude-copilot` CI
# already signed and accepted by Apple's notary service, and separately checks
# it against a pinned checksum — it never calls `codesign --sign` on `cc`
# itself. Standalone binaries receive notary tickets but Apple does not support
# stapling those tickets to the raw file. Offline Gatekeeper proof therefore
# occurs after cc is nested in the final stapled Control Tower app/DMG.
#
# The release gate is exercised against the exact upstream artifact pinned in
# packaging/cc/PINNED_SHA256 and its matching NOTARIZATION.json evidence.
# Development checkouts may temporarily carry a non-Mach-O placeholder while
# preparing a new upstream helper. That mode only checks the pinned checksum
# and can never pass `--release`.
#
# Usage: verify-vendored-cc.sh [--release] /path/to/Contents/Resources/cc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PINNED_SHA_FILE="${REPO_ROOT}/packaging/cc/PINNED_SHA256"
NOTARIZATION_FILE="${REPO_ROOT}/packaging/cc/NOTARIZATION.json"
COMPAT_FILE="${REPO_ROOT}/controltower.compat.json"

RELEASE_MODE=false
if [[ "${1:-}" == "--release" ]]; then
    RELEASE_MODE=true
    shift
fi
CC_PATH="${1:?usage: verify-vendored-cc.sh [--release] /path/to/Contents/Resources/cc}"
[[ $# -eq 1 ]] || {
    echo "error: usage: verify-vendored-cc.sh [--release] /path/to/Contents/Resources/cc" >&2
    exit 2
}

if [[ ! -f "${CC_PATH}" ]]; then
    echo "error: no cc at ${CC_PATH}" >&2
    exit 1
fi

if [[ ! -x "${CC_PATH}" ]]; then
    echo "error: ${CC_PATH} is not executable" >&2
    exit 1
fi

# Checksum gate — always runs, real artifact or placeholder alike. Compares
# against packaging/cc/PINNED_SHA256, which is re-pinned (not hand-edited)
# every time the vendored artifact changes (ADR-M4-005: "Reversible: re-pin
# to a new SHA").
actual_sha="$(shasum -a 256 "${CC_PATH}" | awk '{print $1}')"
pinned_sha="$(awk '{print $1}' "${PINNED_SHA_FILE}")"

if [[ "${actual_sha}" != "${pinned_sha}" ]]; then
    echo "error: checksum mismatch for ${CC_PATH}" >&2
    echo "       expected (pinned): ${pinned_sha}" >&2
    echo "       actual:            ${actual_sha}" >&2
    echo "       CI must block release on this mismatch (ADR-M4-005) — never" >&2
    echo "       proceed with an unpinned artifact." >&2
    exit 1
fi
echo "checksum OK: ${actual_sha}"

# Mach-O vs. plain script: `file` reliably distinguishes the checked-in
# shell-script placeholder from a real compiled/universal binary. codesign
# has nothing to verify on a plain script (it was never signed), so the
# Gatekeeper checks below are placeholder-conditional rather than skipped
# silently.
if file "${CC_PATH}" | grep -q "Mach-O"; then
    if $RELEASE_MODE; then
        architectures="$(lipo -archs "${CC_PATH}")"
        [[ " ${architectures} " == *" arm64 "* ]] || {
            echo "error: release cc is missing the arm64 architecture" >&2
            exit 1
        }
        [[ " ${architectures} " == *" x86_64 "* ]] || {
            echo "error: release cc is missing the x86_64 architecture" >&2
            exit 1
        }
    fi
    echo "verifying upstream Developer ID signature (never re-signing)..."
    codesign --verify --deep --strict --verbose=2 "${CC_PATH}"
    if $RELEASE_MODE; then
        [[ -f "${NOTARIZATION_FILE}" ]] || {
            echo "error: missing upstream notarization evidence: ${NOTARIZATION_FILE}" >&2
            exit 1
        }
        [[ -f "${COMPAT_FILE}" ]] || {
            echo "error: missing app/cc compatibility matrix: ${COMPAT_FILE}" >&2
            exit 1
        }
        version_output="$("${CC_PATH}" --version)"
        /usr/bin/python3 - \
            "${NOTARIZATION_FILE}" \
            "${COMPAT_FILE}" \
            "${actual_sha}" \
            "${version_output}" <<'PY'
import json
import re
import sys

notarization_path, compat_path, actual_sha, version_output = sys.argv[1:]
notarization = json.load(open(notarization_path, encoding="utf-8"))
compat = json.load(open(compat_path, encoding="utf-8"))

if notarization.get("notarization_status") != "Accepted":
    raise SystemExit("upstream notarization status is not Accepted")
if notarization.get("device_flow_https_probe") != "passed":
    raise SystemExit("upstream helper did not pass the live GitHub device-flow HTTPS probe")
if notarization.get("sha256") != actual_sha:
    raise SystemExit("notarization evidence SHA does not match vendored cc")
if sorted(notarization.get("architectures") or []) != ["arm64", "x86_64"]:
    raise SystemExit("notarization evidence does not declare universal2")

match = re.fullmatch(r"cc version (\d+)\.(\d+)\.(\d+)", version_output.strip())
if not match:
    raise SystemExit(f"vendored cc returned an invalid version: {version_output!r}")
version = tuple(map(int, match.groups()))

cc_compat = compat.get("cc") or {}

def semver(field):
    value = cc_compat.get(field)
    found = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", value or "")
    if not found:
        raise SystemExit(f"compat matrix has invalid {field}: {value!r}")
    return tuple(map(int, found.groups()))

minimum = semver("minimum_version")
maximum = semver("maximum_exclusive_version")
if not minimum <= version < maximum:
    raise SystemExit(
        f"vendored cc {version_output!r} is outside "
        f"[{minimum}, {maximum})"
    )
PY
    fi
    echo "vendored cc verified (verify-not-resign): ${CC_PATH}"
else
    if $RELEASE_MODE; then
        echo "error: release blocked: ${CC_PATH} is not the signed universal Mach-O cc artifact" >&2
        exit 1
    fi
    echo "warning: ${CC_PATH} is not a Mach-O binary (placeholder stub) —" >&2
    echo "         skipping codesign checks; checksum gate is the only" >&2
    echo "         check that applies to a development placeholder." >&2
    echo "         This warning must disappear once the real cc ships;" >&2
    echo "         if it is still printing in a release build, block release." >&2
fi
