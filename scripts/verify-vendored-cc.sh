#!/bin/bash
# M4 Stream-D / S8 — verify-not-resign gate for the vendored `cc` binary
# (ADR-M4-005, memory `m4-distribution-decisions`, fixes B-C4/A-C2/B-H1/B-M5).
#
# Control Tower is a single owner of the vendored CLI but never a second
# signing authority: this script VERIFIES the artifact `claude-copilot` CI
# already signed/notarized (codesign + spctl), and separately checks it
# against a pinned checksum — it never calls `codesign --sign` on `cc`
# itself. Two independent signing authorities on one artifact is exactly
# the lockstep-deadlock ADR-M4-005 rejects.
#
# SCRIPT ONLY, NOT executed by this session against a real signed artifact
# — there is no real signed `cc` yet (D-3, owner-gated cross-repo push).
# Against today's placeholder (`packaging/cc/cc`, a plain shell script, not
# a Mach-O binary), the codesign/spctl checks are skipped with a loud
# warning and only the checksum gate runs — see `is_placeholder` below.
# `bash -n` syntax-checked; the checksum comparison against the checked-in
# placeholder IS run (in-repo, no live-system Gatekeeper calls) as part of
# this session's verification.
#
# Usage: verify-vendored-cc.sh /path/to/Contents/Resources/cc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PINNED_SHA_FILE="${REPO_ROOT}/packaging/cc/PINNED_SHA256"

CC_PATH="${1:?usage: verify-vendored-cc.sh /path/to/Contents/Resources/cc}"

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
    echo "verifying Developer ID / notarization chain (never re-signing)..."
    codesign --verify --deep --strict --verbose=2 "${CC_PATH}"
    spctl --assess --type execute --verbose=4 "${CC_PATH}"
    echo "vendored cc verified (verify-not-resign): ${CC_PATH}"
else
    echo "warning: ${CC_PATH} is not a Mach-O binary (placeholder stub) —" >&2
    echo "         skipping codesign/spctl checks; checksum gate is the only" >&2
    echo "         check that applies until the real signed artifact (D-3)" >&2
    echo "         lands. This warning must disappear once the real cc ships;" >&2
    echo "         if it is still printing in a release build, block release." >&2
fi
