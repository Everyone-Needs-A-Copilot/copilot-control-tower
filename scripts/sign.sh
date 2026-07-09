#!/bin/bash
# M4 Stream-D / S7 — Developer ID codesign, inside-out, hardened runtime.
#
# SCRIPT + CONFIG ONLY. NOT executed by this session — real Developer ID
# signing needs the owner's Apple Developer ID Application certificate,
# which this repo does not hold and CI verification cannot fabricate.
# `bash -n` syntax-checked; no `codesign` invocation is run against a real
# bundle here.
#
# ## Reads identity from the environment — never hardcoded (invariant #4)
#
#   CT_SIGN_IDENTITY   Required. The Developer ID Application identity string
#                      or SHA-1 hash codesign should sign with, e.g.
#                      "Developer ID Application: Everyone Needs a Copilot (TEAMID)".
#                      Sourced from a CI secret / the signer's local
#                      keychain — never a literal in this file or in
#                      tauri.conf.json.
#   CT_ENTITLEMENTS    Optional. Defaults to
#                      packaging/entitlements/controltower.entitlements.plist
#                      (this repo's locked-down, exception-free entitlements
#                      — see that file's own comment).
#
# ## Inside-out signing order
#
# Hardened-runtime Developer ID signing must sign the deepest
# frameworks/dylibs/helper executables first, then the outer .app bundle
# last — codesign validates a bundle's *existing* nested signatures when
# signing the parent, so signing outer-to-inner would sign over unsigned (or
# differently-signed) nested content. `find ... -exec codesign` below walks
# frameworks/dylibs before the final top-level `codesign` call on the .app
# itself.
#
# ## Re-signing in place with --force
#
# `tauri build` (tauri.conf sets the signing identity) already signs the app
# during bundling, so this script receives an already-signed bundle. It
# re-signs with `--force` to apply the hardened runtime and this repo's
# locked-down entitlements as the signature that actually ships. Signing is
# deliberately centralized here so the entitlements and runtime options are
# the reviewed ones; `--force` here means "replace the build-time signature
# with the release signature," not "skip verification" (the two banned flags,
# --skip-verify and the trust-weakening --force-in-place variants, remain
# absent; codesign --force only overwrites the existing signature).
#
# Usage: sign.sh "/path/to/Copilot Control Tower.app"

set -euo pipefail

APP_PATH="${1:?usage: sign.sh /path/to/Copilot Control Tower.app}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTITLEMENTS="${CT_ENTITLEMENTS:-${SCRIPT_DIR}/../packaging/entitlements/controltower.entitlements.plist}"

if [[ -z "${CT_SIGN_IDENTITY:-}" ]]; then
    echo "error: CT_SIGN_IDENTITY is not set (Developer ID Application identity)." >&2
    echo "       Never hardcode it here — export it from a CI secret / local keychain." >&2
    exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
    echo "error: app bundle not found at ${APP_PATH}" >&2
    exit 1
fi

if [[ ! -f "${ENTITLEMENTS}" ]]; then
    echo "error: entitlements file not found at ${ENTITLEMENTS}" >&2
    exit 1
fi

echo "signing (inside-out) with identity: ${CT_SIGN_IDENTITY}"

# Deepest first: nested frameworks, dylibs, and any embedded executables
# (including the vendored `cc` — see S8/verify-vendored-cc.sh for why `cc`
# itself is verified, never re-signed by us; this loop's globs intentionally
# exclude it. If `cc`'s own path ever needs touching that is a signing-
# authority change, not a glob tweak).
#
# Guard on the directory existing: a Tauri/wry app that bundles no frameworks
# (it uses the system WebKit) has no Contents/Frameworks, and running `find`
# against a missing path exits non-zero, which under `set -euo pipefail` would
# abort the whole script *before* the outer .app is signed.
if [[ -d "${APP_PATH}/Contents/Frameworks" ]]; then
    find "${APP_PATH}/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.framework" \) -print0 |
        while IFS= read -r -d '' item; do
            codesign --sign "${CT_SIGN_IDENTITY}" \
                --options runtime \
                --timestamp \
                --entitlements "${ENTITLEMENTS}" \
                "${item}"
        done
fi

# The outer .app last — codesign checks existing nested signatures when
# signing the parent, so this must come after every nested item above.
# Sign only the top-level bundle (no --deep): the nested items above are
# already signed, and codesign signs shallow by default when --deep is omitted.
# (`--deep=false` is not valid codesign syntax — --deep takes no argument.)
codesign --sign "${CT_SIGN_IDENTITY}" \
    --options runtime \
    --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --force \
    "${APP_PATH}"

codesign --verify --strict --deep --verbose=2 "${APP_PATH}"

echo "signed: ${APP_PATH}"
