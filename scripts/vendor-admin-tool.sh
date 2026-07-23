#!/usr/bin/env bash
# Fetch one pinned, redistributable Admin runtime tool into the ignored build
# cache, verify its SHA-256, and print the executable's absolute path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_ROOT="${REPO_ROOT}/.copilot/admin-tool-cache"
TOOL="${1:-}"
ARCH="$(uname -m)"

case "${ARCH}" in
  arm64)
    GH_ARCH="arm64"
    GH_SHA256="3677f9c27965825f9c7d50395473c134edaea4b484373ef6b25de653570a0489"
    JQ_ARCH="arm64"
    JQ_SHA256="0bbe619e663e0de2c550be2fe0d240d076799d6f8a652b70fa04aea8a8362e8a"
    ;;
  x86_64)
    GH_ARCH="amd64"
    GH_SHA256="985707e9ac60c95ed51cddd808c338b481abe69fffa77e9d6547c3750045f77e"
    JQ_ARCH="amd64"
    JQ_SHA256="4155822bbf5ea90f5c79cf254665975eb4274d426d0709770c21774de5407443"
    ;;
  *)
    echo "error: unsupported macOS architecture for Admin tools: ${ARCH}" >&2
    exit 2
    ;;
esac

verify_sha256() {
  local path="$1" expected="$2"
  local actual
  actual="$(shasum -a 256 "${path}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "error: checksum mismatch for ${path}" >&2
    exit 2
  fi
}

mkdir -p "${CACHE_ROOT}"

case "${TOOL}" in
  gh)
    VERSION="2.95.0"
    DESTINATION="${CACHE_ROOT}/gh-${VERSION}-${GH_ARCH}"
    ARCHIVE="${CACHE_ROOT}/gh-${VERSION}-${GH_ARCH}.zip"
    if [[ ! -f "${ARCHIVE}" ]]; then
      URL="https://github.com/cli/cli/releases/download/v${VERSION}/gh_${VERSION}_macOS_${GH_ARCH}.zip"
      curl --fail --location --silent --show-error "${URL}" --output "${ARCHIVE}"
    fi
    verify_sha256 "${ARCHIVE}" "${GH_SHA256}"
    TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ct-admin-gh.XXXXXX")"
    trap 'rm -rf "${TEMP_ROOT}"' EXIT
    /usr/bin/ditto -x -k "${ARCHIVE}" "${TEMP_ROOT}/expanded"
    SOURCE="${TEMP_ROOT}/expanded/gh_${VERSION}_macOS_${GH_ARCH}/bin/gh"
    [[ -x "${SOURCE}" ]] || {
      echo "error: the verified GitHub CLI archive did not contain bin/gh" >&2
      exit 2
    }
    if [[ ! -x "${DESTINATION}" ]] || ! cmp -s "${SOURCE}" "${DESTINATION}"; then
      cp "${SOURCE}" "${DESTINATION}"
      chmod 755 "${DESTINATION}"
    fi
    printf '%s\n' "${DESTINATION}"
    ;;
  jq)
    VERSION="1.7.1"
    DESTINATION="${CACHE_ROOT}/jq-${VERSION}-${JQ_ARCH}"
    if [[ ! -x "${DESTINATION}" ]]; then
      URL="https://github.com/jqlang/jq/releases/download/jq-${VERSION}/jq-macos-${JQ_ARCH}"
      curl --fail --location --silent --show-error "${URL}" --output "${DESTINATION}"
      verify_sha256 "${DESTINATION}" "${JQ_SHA256}"
      chmod 755 "${DESTINATION}"
    fi
    verify_sha256 "${DESTINATION}" "${JQ_SHA256}"
    printf '%s\n' "${DESTINATION}"
    ;;
  *)
    echo "usage: vendor-admin-tool.sh gh|jq" >&2
    exit 2
    ;;
esac
