#!/usr/bin/env bash
# Install the exact Phase 6 development CLIs for a cold-machine proof.
# This is a source installer for testing, not the signed release artifact.

set -euo pipefail

CLAUDE_REPO="${ENAC_CLAUDE_REPO:-https://github.com/Everyone-Needs-A-Copilot/claude-copilot.git}"
CLAUDE_REF="3dcb5684c196d41caf5b727dba17d74dfa7c7ecd"
CLI_REPO="${ENAC_CLI_REPO:-https://github.com/Everyone-Needs-A-Copilot/cli-copilot.git}"
CLI_REF="c6e1e02fc4e0e4db3d1413ed6e369367fa7bd9fc"
INSTALL_HOME="${ENAC_INSTALL_HOME:-$HOME}"
INSTALL_ROOT="${INSTALL_HOME}/.local/share/enac/test-clis"
BIN_ROOT="${INSTALL_HOME}/.local/bin"
APPLY=false
JSON=false

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=true ;;
    --json) JSON=true ;;
    --help|-h)
      echo "usage: install-test-clis.sh [--apply] [--json]"
      exit 0
      ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

emit() {
  local result="$1" detail="$2"
  if $JSON; then
    python3 - "$result" "$detail" "$CLAUDE_REF" "$CLI_REF" <<'PY'
import json, sys
print(json.dumps({"schema_version":"1.0","result":sys.argv[1],"detail":sys.argv[2],"refs":{"cc":sys.argv[3],"copilot":sys.argv[4]}}))
PY
  else
    echo "$result: $detail"
  fi
}

for dependency in git python3; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    emit blocked "$dependency is required."
    exit 2
  fi
done

cc_target="${INSTALL_ROOT}/claude-${CLAUDE_REF}/venv/bin/cc"
copilot_target="${INSTALL_ROOT}/cli-${CLI_REF}/venv/bin/copilot"

validate_install() {
  HOME="$INSTALL_HOME" "$cc_target" --version >/dev/null 2>&1 \
    && HOME="$INSTALL_HOME" "$copilot_target" --help >/dev/null 2>&1
}

for link in "${BIN_ROOT}/cc:${cc_target}" "${BIN_ROOT}/copilot:${copilot_target}"; do
  path="${link%%:*}"
  expected="${link#*:}"
  if [[ -e "$path" || -L "$path" ]]; then
    actual="$(readlink "$path" 2>/dev/null || true)"
    if [[ "$actual" != "$expected" ]]; then
      emit blocked "$path already exists and is not this installer's managed link."
      exit 2
    fi
  fi
done

if [[ -x "$cc_target" && -x "$copilot_target" ]]; then
  if validate_install; then
    emit ready "The pinned test CLIs are already installed."
    exit 0
  fi
  emit blocked "The managed CLI files exist but do not start cleanly. Move this partial installation aside for inspection before retrying."
  exit 2
fi
if [[ -d "${INSTALL_ROOT}/claude-${CLAUDE_REF}" && ! -x "$cc_target" ]] \
  || [[ -d "${INSTALL_ROOT}/cli-${CLI_REF}" && ! -x "$copilot_target" ]]; then
  emit blocked "A partial managed installation exists. Move it aside for inspection before retrying."
  exit 2
fi
if ! $APPLY; then
  emit changes-required "The pinned test CLIs can be installed without replacing existing commands."
  exit 0
fi

mkdir -p "$INSTALL_ROOT" "$BIN_ROOT"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/enac-test-clis.XXXXXX")"
cleanup() { rm -rf "$temp_root"; }
trap cleanup EXIT

install_project() {
  local repo="$1" ref="$2" project_subpath="$3" destination="$4"
  local source="$temp_root/source-$ref"
  git clone --filter=blob:none "$repo" "$source" >/dev/null 2>&1
  git -C "$source" checkout --detach "$ref" >/dev/null 2>&1
  [[ "$(git -C "$source" rev-parse HEAD)" == "$ref" ]]
  python3 -m venv "$destination/venv"
  "$destination/venv/bin/python" -m pip install --disable-pip-version-check "$source/$project_subpath" >/dev/null
  printf '%s\n' "$repo@$ref" > "$destination/SOURCE"
}

[[ -d "${INSTALL_ROOT}/claude-${CLAUDE_REF}" ]] || install_project "$CLAUDE_REPO" "$CLAUDE_REF" "tools/cc" "${INSTALL_ROOT}/claude-${CLAUDE_REF}"
[[ -d "${INSTALL_ROOT}/cli-${CLI_REF}" ]] || install_project "$CLI_REPO" "$CLI_REF" "." "${INSTALL_ROOT}/cli-${CLI_REF}"

[[ -L "${BIN_ROOT}/cc" ]] || ln -s "$cc_target" "${BIN_ROOT}/cc"
[[ -L "${BIN_ROOT}/copilot" ]] || ln -s "$copilot_target" "${BIN_ROOT}/copilot"
if ! validate_install; then
  emit blocked "The pinned CLI install did not pass its clean-home startup check. The partial managed install was left intact for inspection."
  exit 2
fi
emit applied "Installed the pinned Phase 6 test CLIs."
