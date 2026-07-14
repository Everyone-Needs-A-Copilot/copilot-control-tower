#!/usr/bin/env bash
# install-claim-sweep-hook.sh — install/update a pre-commit hook block that
# runs claim_sweep.py --check (the CSE-wide claim sweep, TASK-137,
# t2-no-claim-outlives-its-check).
#
# Mirrors tools/cse-bench/install-claims-hook.sh's pattern (itself modeled
# on knowledge-copilot's scripts/install-crosslinks-hook.sh): idempotent,
# and CHAINS onto whatever is already in the pre-commit hook rather than
# clobbering it. This script only ever touches the block between its own
# BEGIN/END markers.
#
# UNLIKE install-claims-hook.sh, this installer is meant to be run from
# ANY of the CSE repos claim_sweep.py's SCAN_TARGETS covers, not just this
# one — the checker (claim_sweep.py) always lives in copilot-control-tower,
# but the pre-commit hook it enforces belongs to whichever repo's OWN docs
# it is guarding, matching the task's requirement to enforce "in the repos
# whose docs the sweep covers, following each repo's existing pre-commit
# conventions." The TARGET repo is whatever repo you run this script FROM
# (or --target-repo PATH); the CHECKER path is always resolved relative to
# this script's own location (this file, inside copilot-control-tower).
#
# Usage:
#   cd copilot-control-tower && tools/cse-bench/install-claim-sweep-hook.sh
#     # installs into copilot-control-tower's own pre-commit hook
#   cd knowledge-copilot && /path/to/copilot-control-tower/tools/cse-bench/install-claim-sweep-hook.sh
#     # installs into knowledge-copilot's pre-commit hook, scoped to
#     # `--repo knowledge-copilot` (the target repo's own basename)
#   tools/cse-bench/install-claim-sweep-hook.sh --target-repo /path/to/repo
#     # explicit target, instead of relying on CWD

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER_ABS="$SCRIPT_DIR/claim_sweep.py"

if [ ! -f "$CHECKER_ABS" ]; then
  echo "install-claim-sweep-hook.sh: claim_sweep.py not found next to this script ($SCRIPT_DIR)" >&2
  exit 1
fi

TARGET_REPO_ARG=""
if [ "${1:-}" = "--target-repo" ]; then
  TARGET_REPO_ARG="${2:-}"
  if [ -z "$TARGET_REPO_ARG" ]; then
    echo "install-claim-sweep-hook.sh: --target-repo requires a path" >&2
    exit 1
  fi
fi

if [ -n "$TARGET_REPO_ARG" ]; then
  if ! REPO_ROOT="$(git -C "$TARGET_REPO_ARG" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "install-claim-sweep-hook.sh: $TARGET_REPO_ARG is not inside a git repository" >&2
    exit 1
  fi
else
  if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    echo "install-claim-sweep-hook.sh: not inside a git repository (run this from within the target repo, or pass --target-repo PATH)" >&2
    exit 1
  fi
fi

TARGET_REPO_NAME="$(basename "$REPO_ROOT")"

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

BEGIN_MARKER="# BEGIN cse-claim-sweep hook (managed by copilot-control-tower/tools/cse-bench/install-claim-sweep-hook.sh — do not hand-edit this block)"
END_MARKER="# END cse-claim-sweep hook"

HOOK_BLOCK="$BEGIN_MARKER
if [ -f \"$CHECKER_ABS\" ]; then
  python3 \"$CHECKER_ABS\" --repo $TARGET_REPO_NAME --check || exit 1
else
  : # copilot-control-tower (and this checker) not present on this checkout; nothing to check.
fi
$END_MARKER"

if [ -f "$HOOK_FILE" ] && grep -qF "$BEGIN_MARKER" "$HOOK_FILE"; then
  # Replace the existing managed block in place (same head/tail technique
  # install-claims-hook.sh uses — macOS's built-in awk rejects embedded
  # newlines in -v assignments).
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

echo "install-claim-sweep-hook.sh: $ACTION pre-commit hook at $HOOK_FILE"
echo "install-claim-sweep-hook.sh: target-repo=$TARGET_REPO_NAME checker=$CHECKER_ABS hooks-dir=$HOOKS_DIR"
