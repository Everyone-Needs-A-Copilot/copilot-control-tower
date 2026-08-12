#!/usr/bin/env bash
# install-initiatives-hook.sh — install/update a pre-commit hook that runs
# check-initiatives.sh in a target repo.
#
# Usage: install-initiatives-hook.sh [DOCS_DIR]
#   Run from inside the target repo (or any subdirectory of it). DOCS_DIR
#   defaults to "docs" and is passed through to check-initiatives.sh at
#   hook-run time.
#
# Idempotent: re-running updates the managed block in place instead of
# duplicating it. Chains to (never clobbers) any pre-existing pre-commit
# hook content — it appends its managed block rather than overwriting the
# file. Honors core.hooksPath if the target repo has set one.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER_ABS="$SCRIPT_DIR/check-initiatives.sh"
DOCS_DIR="${1:-docs}"

if [ ! -f "$CHECKER_ABS" ]; then
  echo "install-initiatives-hook.sh: check-initiatives.sh not found next to this script ($SCRIPT_DIR)" >&2
  exit 1
fi

if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "install-initiatives-hook.sh: not inside a git repository (run this from within the target repo)" >&2
  exit 1
fi

# Resolve core.hooksPath if set; otherwise the default .git/hooks. Relative
# hooksPath values are resolved against the repo root (the convention used
# by e.g. Husky-style ".githooks" directories).
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

# Path to the checker, relative to the repo root, so the hook stays
# portable across clones/machines instead of embedding an absolute path.
case "$CHECKER_ABS" in
  "$REPO_ROOT"/*)
    CHECKER_REL="${CHECKER_ABS#"$REPO_ROOT"/}"
    ;;
  *)
    echo "install-initiatives-hook.sh: check-initiatives.sh ($CHECKER_ABS) is outside the target repo ($REPO_ROOT); copy the bin/ directory into the repo first" >&2
    exit 1
    ;;
esac

BEGIN_MARKER="# BEGIN initiatives-standard hook (managed by install-initiatives-hook.sh — do not hand-edit this block)"
END_MARKER="# END initiatives-standard hook"

HOOK_BLOCK="$BEGIN_MARKER
_initiatives_checker=\"\$(git rev-parse --show-toplevel)/$CHECKER_REL\"
if [ -x \"\$_initiatives_checker\" ]; then
  \"\$_initiatives_checker\" \"$DOCS_DIR\" || exit 1
else
  echo \"pre-commit: $CHECKER_REL not found or not executable; skipping initiatives standard check\" >&2
fi
$END_MARKER"

if [ -f "$HOOK_FILE" ] && grep -qF "$BEGIN_MARKER" "$HOOK_FILE"; then
  # Replace the existing managed block in place. Deliberately avoids
  # `awk -v var="$multiline_string"` — macOS's built-in awk (the "one true
  # awk", not gawk) rejects embedded newlines in -v assignments ("newline
  # in string"), so line numbers + head/tail is used instead.
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

echo "install-initiatives-hook.sh: $ACTION pre-commit hook at $HOOK_FILE"
echo "install-initiatives-hook.sh: checker=$CHECKER_REL docs-dir=$DOCS_DIR hooks-dir=$HOOKS_DIR"
