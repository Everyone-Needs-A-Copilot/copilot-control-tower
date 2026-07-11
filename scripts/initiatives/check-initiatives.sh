#!/usr/bin/env bash
# check-initiatives.sh — enforce the 40-initiatives documentation standard.
#
# "The gate IS the standard": every rule documented in this package's
# README has a corresponding check here. If a rule has no check here, it
# is not part of the standard — do not add prose without adding enforcement.
#
# Usage: check-initiatives.sh [--strict] [DOCS_DIR]
#   --strict   promote WARN-only rules (R10, R12) to hard failures
#   DOCS_DIR   defaults to "docs"; initiatives live at DOCS_DIR/40-initiatives
#
# Exit status: 0 if no hard failures, 1 otherwise.
# Pure bash + awk/sed. No npm, no python, no yq — must run identically in
# a Swift repo, a Python repo, or a Node repo.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-initiatives.sh
source "$SCRIPT_DIR/lib-initiatives.sh"

STRICT=0
DOCS_DIR=""
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--strict] [DOCS_DIR]"
      exit 0
      ;;
    *) DOCS_DIR="$arg" ;;
  esac
done
DOCS_DIR="${DOCS_DIR:-docs}"
INIT_DIR="$DOCS_DIR/40-initiatives"

HARD_FAILS=0
WARNINGS=0

fail() {
  echo "initiatives standard violation: $1: $2" >&2
  HARD_FAILS=$((HARD_FAILS + 1))
}

warn() {
  if [ "$STRICT" -eq 1 ]; then
    fail "$1" "$2 (warn rule promoted to hard fail by --strict)"
  else
    echo "initiatives standard warning: $1: $2" >&2
    WARNINGS=$((WARNINGS + 1))
  fi
}

# A repo that has not adopted docs/ (or 40-initiatives/) at all yet has
# nothing to check — that is not a violation, it just hasn't started. This
# matters for the pre-commit hook: a repo installs the hook before it has
# any initiatives, and every commit until the first one must still be able
# to pass. Only once DOCS_DIR exists do R8's wrong-path checks apply; only
# once DOCS_DIR/40-initiatives exists do the full per-initiative and R7
# checks apply.
if [ ! -d "$DOCS_DIR" ]; then
  echo "check-initiatives.sh: $DOCS_DIR does not exist yet; nothing to check."
  exit 0
fi

# --- R8: canonical path — the wrong locations must not exist non-empty. --
for wrong in "$DOCS_DIR/initiatives" "$DOCS_DIR/80-initiatives"; do
  if [ -d "$wrong" ]; then
    entry_count="$(find "$wrong" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$entry_count" -gt 0 ]; then
      fail "R8" "$wrong exists and is non-empty; the canonical path is $INIT_DIR"
    fi
  fi
done

if [ ! -d "$INIT_DIR" ]; then
  echo "check-initiatives.sh: $INIT_DIR does not exist yet; nothing to check."
  if [ "$HARD_FAILS" -gt 0 ]; then
    echo ""
    echo "Result: $HARD_FAILS hard failure(s), $WARNINGS warning(s)."
    exit 1
  fi
  exit 0
fi

# --- Collect initiative directories. -------------------------------------
init_dirs="$(find "$INIT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print | sort)"

# --- R9: no duplicate NN prefixes. ---------------------------------------
if [ -n "$init_dirs" ]; then
  dup_prefixes="$(
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      basename "$d" | sed -E 's/^([0-9]{2,3})-.*/\1/'
    done <<< "$init_dirs"
  )"
  dup_prefixes="$(printf '%s\n' "$dup_prefixes" | sort | uniq -d)"
  if [ -n "$dup_prefixes" ]; then
    while IFS= read -r prefix; do
      [ -z "$prefix" ] && continue
      matches="$(printf '%s\n' "$init_dirs" | xargs -n1 basename 2>/dev/null | grep -E "^${prefix}-" | tr '\n' ' ')"
      fail "R9" "duplicate initiative prefix '$prefix': $matches"
    done <<< "$dup_prefixes"
  fi
fi

# --- Per-initiative checks (R1-R6, R10-R12). -----------------------------
if [ -n "$init_dirs" ]; then
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    name="$(basename "$dir")"
    readme="$dir/README.md"

    # R1: folder name shape.
    if ! [[ "$name" =~ ^[0-9]{2,3}-[a-z0-9-]+$ ]]; then
      fail "R1" "$dir does not match ^[0-9]{2,3}-[a-z0-9-]+\$"
    fi

    # R2: README.md must exist.
    if [ ! -f "$readme" ]; then
      fail "R2" "$dir is missing README.md"
    else
      # R3: frontmatter with required keys.
      if ! has_frontmatter "$readme"; then
        fail "R3" "$readme has no YAML frontmatter (--- ... ---) block"
      else
        missing_keys=""
        for key in initiative title status owner created; do
          val="$(read_frontmatter_field "$readme" "$key")"
          if [ -z "$val" ]; then
            missing_keys="$missing_keys $key"
          fi
        done
        if [ -n "$missing_keys" ]; then
          fail "R3" "$readme frontmatter missing or empty required key(s):$missing_keys"
        fi

        status_val="$(read_frontmatter_field "$readme" status)"
        init_val="$(read_frontmatter_field "$readme" initiative)"
        superseded_val="$(read_frontmatter_field "$readme" superseded_by)"

        # R4: status must be in the closed enum.
        if [ -n "$status_val" ] && ! is_valid_initiative_status "$status_val"; then
          fail "R4" "$readme has status '$status_val', which is not in the closed enum (proposed|discovery|planned|active|blocked|complete|absorbed|abandoned)"
        fi

        # R5: initiative: value must equal the directory name.
        if [ -n "$init_val" ] && [ "$init_val" != "$name" ]; then
          fail "R5" "$readme frontmatter 'initiative: $init_val' does not match directory name '$name'"
        fi

        # R6: status: absorbed requires non-null superseded_by.
        if [ "$status_val" = "absorbed" ] && is_null_value "$superseded_val"; then
          fail "R6" "$readme has status: absorbed but superseded_by is null/missing"
        fi
      fi
    fi

    # R10 (warn): loose .md files at the initiative root other than README.md.
    loose_files="$(find "$dir" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' 2>/dev/null || true)"
    if [ -n "$loose_files" ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        warn "R10" "$f (loose file at initiative root; move it under phases/, decisions/, or retrospectives/)"
      done <<< "$loose_files"
    fi

    # R11: decisions/, phases/, retrospectives/ must not exist while empty —
    # and a directory holding only git/OS placeholder files (.gitkeep,
    # .keep, .gitignore, .DS_Store) is empty for this rule's purposes. A
    # .gitkeep-only directory exists for no reason other than to hold an
    # empty folder open in git; it IS the empty-ceremony-directory defect
    # this rule exists to ban, not an exception to it.
    for sub in decisions phases retrospectives; do
      subdir="$dir/$sub"
      if [ -d "$subdir" ]; then
        content_count="$(find "$subdir" -mindepth 1 \
          ! -name '.DS_Store' ! -name '.gitkeep' ! -name '.keep' ! -name '.gitignore' \
          2>/dev/null | wc -l | tr -d ' ')"
        if [ "$content_count" -eq 0 ]; then
          total_count="$(find "$subdir" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
          if [ "$total_count" -gt 0 ]; then
            placeholder_names="$(find "$subdir" -mindepth 1 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//;s/,/, /g')"
            fail "R11" "$subdir contains only placeholder files ($placeholder_names); delete the directory — decisions/, phases/, and retrospectives/ are created lazily on first real file"
          else
            fail "R11" "$subdir is an empty ceremony directory; delete it (created lazily on first real file)"
          fi
        fi
      fi
    done

    # R12 (warn): files in phases/ not matching phase-N-*.md.
    phases_dir="$dir/phases"
    if [ -d "$phases_dir" ]; then
      phase_files="$(find "$phases_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null || true)"
      if [ -n "$phase_files" ]; then
        while IFS= read -r f; do
          [ -z "$f" ] && continue
          base="$(basename "$f")"
          if ! [[ "$base" =~ ^phase-[0-9]+-.*\.md$ ]]; then
            warn "R12" "$f does not match phase-N-*.md"
          fi
        done <<< "$phase_files"
      fi
    fi
  done <<< "$init_dirs"
fi

# --- R7: the generated index must match the checked-in index. -----------
GEN_SCRIPT="$SCRIPT_DIR/gen-initiatives-index.sh"
if [ ! -f "$GEN_SCRIPT" ]; then
  fail "R7" "gen-initiatives-index.sh not found next to check-initiatives.sh; cannot verify index freshness"
else
  index_file="$INIT_DIR/README.md"
  tmp_index="$(mktemp "${TMPDIR:-/tmp}/initiatives-index.XXXXXX")"
  trap 'rm -f "$tmp_index"' EXIT
  if "$GEN_SCRIPT" "$DOCS_DIR" "$tmp_index" 2>/dev/null; then
    if [ ! -f "$index_file" ]; then
      fail "R7" "$index_file does not exist; run gen-initiatives-index.sh $DOCS_DIR"
    elif ! diff -q "$index_file" "$tmp_index" >/dev/null 2>&1; then
      fail "R7" "$index_file is stale; run gen-initiatives-index.sh $DOCS_DIR to regenerate (diff: $(diff "$index_file" "$tmp_index" | head -6 | tr '\n' ' '))"
    fi
  else
    fail "R7" "gen-initiatives-index.sh failed to run against $DOCS_DIR"
  fi
fi

echo ""
if [ "$HARD_FAILS" -gt 0 ]; then
  echo "Result: $HARD_FAILS hard failure(s), $WARNINGS warning(s)."
  exit 1
else
  echo "Result: 0 hard failures, $WARNINGS warning(s)."
  exit 0
fi
