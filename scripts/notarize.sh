#!/bin/bash
# M4 Stream-D / S7 — notarytool submit + staple, both .app and .dmg
# (architecture.md §7, release-and-versioning.md §2 step 2, ADR-M4-002's
# "staple is verified offline before promote").
#
# SCRIPT + CONFIG ONLY. NOT executed by this session — real notarization
# needs the owner's App Store Connect API key or Apple ID + app-specific
# password, which this repo does not hold. `bash -n` syntax-checked only.
#
# ## Reads credentials from the environment — never hardcoded (invariant #4)
#
# Two supported credential shapes (notarytool supports both); pick ONE:
#
#   CT_NOTARY_KEYCHAIN_PROFILE   A profile name previously stored via
#                                 `xcrun notarytool store-credentials` in the
#                                 signer's local keychain. Preferred for
#                                 interactive/local signing — no secret ever
#                                 touches this script or CI environment.
#
#   ...or, for CI (App Store Connect API key):
#   CT_NOTARY_KEY_ID              API key ID
#   CT_NOTARY_KEY_ISSUER          API key issuer ID
#   CT_NOTARY_KEY_PATH            path to the downloaded .p8 private key file
#                                 (mounted from a CI secret at runtime, never
#                                 committed to this repo)
#
# Usage: notarize.sh "/path/to/Copilot Control Tower.app" "/path/to/Copilot Control Tower.dmg"

set -euo pipefail

APP_PATH="${1:?usage: notarize.sh /path/to/App.app /path/to/App.dmg}"
DMG_PATH="${2:?usage: notarize.sh /path/to/App.app /path/to/App.dmg}"

notary_auth_args=()
if [[ -n "${CT_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    notary_auth_args=(--keychain-profile "${CT_NOTARY_KEYCHAIN_PROFILE}")
elif [[ -n "${CT_NOTARY_KEY_ID:-}" && -n "${CT_NOTARY_KEY_ISSUER:-}" && -n "${CT_NOTARY_KEY_PATH:-}" ]]; then
    notary_auth_args=(--key "${CT_NOTARY_KEY_PATH}" --key-id "${CT_NOTARY_KEY_ID}" --issuer "${CT_NOTARY_KEY_ISSUER}")
else
    echo "error: no notarization credentials set." >&2
    echo "       Set CT_NOTARY_KEYCHAIN_PROFILE, or all three of" >&2
    echo "       CT_NOTARY_KEY_ID / CT_NOTARY_KEY_ISSUER / CT_NOTARY_KEY_PATH." >&2
    echo "       Never hardcode credentials in this file." >&2
    exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
    echo "error: app bundle not found at ${APP_PATH}" >&2
    exit 1
fi
if [[ ! -f "${DMG_PATH}" ]]; then
    echo "error: dmg not found at ${DMG_PATH}" >&2
    exit 1
fi

echo "submitting ${DMG_PATH} for notarization (--wait)..."
xcrun notarytool submit "${DMG_PATH}" "${notary_auth_args[@]}" --wait

# Staple BOTH the .app (for a direct, un-DMG'd copy — e.g. what the updater
# downloads and stages) and the .dmg (for the manual-download path) — this
# is what lets the watchdog verify the staged bundle is stapled OFFLINE
# before promoting (ADR-M4-002, release-and-versioning.md §2 step 4): no
# dependency on reaching Apple's notarization CDN at swap time, which is
# what makes an air-gapped/proxy fleet on an internal mirror safe to
# auto-update.
echo "stapling ${APP_PATH}..."
xcrun stapler staple "${APP_PATH}"

echo "stapling ${DMG_PATH}..."
xcrun stapler staple "${DMG_PATH}"

echo "verifying staple offline on ${APP_PATH}..."
xcrun stapler validate "${APP_PATH}"

echo "notarized + stapled: ${APP_PATH}, ${DMG_PATH}"
