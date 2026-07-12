#!/usr/bin/env bash
# install-claims-hook.sh — install/update a pre-commit hook block that runs
# check_claims.py (the claims.yaml structural validator, TASK-85 / B-2).
#
# Mirrors scripts/initiatives/install-initiatives-hook.sh's pattern (the
# shared-docs 07-initiative-package/bin/ house style): idempotent, and
# CHAINS onto whatever is already in the pre-commit hook rather than
# clobbering it. This script only ever touches the block between its own
# BEGIN/END markers — the initiatives-standard hook block (or any other
# pre-existing content) is left byte-for-byte untouched.
#
# Usage: tools/cse-bench/install-claims-hook.sh
#   Run from inside this repo (or any subdirectory of it). Honors
#   core.hooksPath if set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER_ABS="$SCRIPT_DIR/check_claims.py"

if [ ! -f "$CHECKER_ABS" ]; then
  echo "install-claims-hook.sh: check_claims.py not found next to this script ($SCRIPT_DIR)" >&2
  exit 1
fi

if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "install-claims-hook.sh: not inside a git repository (run this from within the target repo)" >&2
  exit 1
fi

HOOKS_PATH_CONFIG="$(git -C "$REPO_ROOT" config --get core.hooksPath || true)"
if [ -z "$HOOKS_PATH_CONFIG" ]; then
  HOOKS_DIR="$REPO_ROOT/.git/hooks"
else
  case "$HOOKS_PATH_CONFIG" in
    /*) HOOKS_DIR="$HOOKS_PATH_CONFIG" ;;
    *)  HOOKS_DIR="$REPO_ROOT/$HOOKS_PATH_CONFIG" ;;
  esac
fi

mkdir -p "$HOOKS_DIR"
HOOK_FILE="$HOOKS_DIR/pre-commit"

case "$CHECKER_ABS" in
  "$REPO_ROOT"/*)
    CHECKER_REL="${CHECKER_ABS#"$REPO_ROOT"/}"
    ;;
  *)
    echo "install-claims-hook.sh: check_claims.py ($CHECKER_ABS) is outside the target repo ($REPO_ROOT)" >&2
    exit 1
    ;;
esac

BEGIN_MARKER="# BEGIN cse-claims-register hook (managed by tools/cse-bench/install-claims-hook.sh — do not hand-edit this block)"
END_MARKER="# END cse-claims-register hook"

HOOK_BLOCK="$BEGIN_MARKER
_cse_claims_checker=\"\$(git rev-parse --show-toplevel)/$CHECKER_REL\"
_cse_claims_register=\"\$(git rev-parse --show-toplevel)/docs/40-initiatives/01-cse-auditability/claims.yaml\"
if [ ! -f \"\$_cse_claims_register\" ]; then
  : # register does not exist yet in this repo; nothing to check.
elif [ -x \"\$_cse_claims_checker\" ]; then
  \"\$_cse_claims_checker\" || exit 1
else
  python3 \"\$_cse_claims_checker\" || exit 1
fi
$END_MARKER"

if [ -f "$HOOK_FILE" ] && grep -qF "$BEGIN_MARKER" "$HOOK_FILE"; then
  # Replace the existing managed block in place (same head/tail technique
  # install-initiatives-hook.sh uses — macOS's built-in awk rejects
  # embedded newlines in -v assignments).
  BEGIN_LINE="$(grep -nF "$BEGIN_MARKER" "$HOOK_FILE" | head -1 | cut -d: -f1)"
  END_LINE="$(grep -nF "$END_MARKER" "$HOOK_FILE" | head -1 | cut -d: -f1)"
  TMP_HOOK="$(mktemp "${TMPDIR:-/tmp}/pre-commit.XXXXXX")"
  if [ "$BEGIN_LINE" -gt 1 ]; then
    head -n "$((BEGIN_LINE - 1))" "$HOOK_FILE" > "$TMP_HOOK"
  else
    : > "$TMP_HOOK"
  fi
  printf '%s\n' "$HOOK_BLOCK" >> "$TMP_HOOK"
  tail -n "+$((END_LINE + 1))" "$HOOK_FILE" >> "$TMP_HOOK"
  mv "$TMP_HOOK" "$HOOK_FILE"
  ACTION="updated the existing managed block in"
elif [ -f "$HOOK_FILE" ]; then
  printf '\n%s\n' "$HOOK_BLOCK" >> "$HOOK_FILE"
  ACTION="appended a managed block to (chained onto) the existing"
else
  {
    printf '#!/usr/bin/env bash\nset -e\n\n%s\n' "$HOOK_BLOCK"
  } > "$HOOK_FILE"
  ACTION="created a new"
fi
chmod +x "$HOOK_FILE"

echo "install-claims-hook.sh: $ACTION pre-commit hook at $HOOK_FILE"
echo "install-claims-hook.sh: checker=$CHECKER_REL hooks-dir=$HOOKS_DIR"
