#!/usr/bin/env bash
# lib-initiatives.sh — shared frontmatter parsing for the 40-initiatives
# documentation standard. Sourced by check-initiatives.sh and
# gen-initiatives-index.sh. Pure bash + awk/sed, no external tools.
#
# This file is not meant to be executed directly.

# has_frontmatter FILE
# True (0) if FILE opens with a YAML frontmatter block: first line is
# exactly "---" and a later line closes it with another "---".
has_frontmatter() {
  local file="$1"
  local first_line
  first_line="$(head -n1 "$file" 2>/dev/null || true)"
  if [ "$first_line" != "---" ]; then
    return 1
  fi
  awk 'NR>1 && /^---[ \t]*$/ { found=1; exit } END { exit !found }' "$file"
}

# read_frontmatter_field FILE KEY
# Prints the trimmed value of a top-level ("KEY: value") frontmatter key.
# Indented (nested) keys are ignored on purpose — only top-level keys are
# part of the enforced contract. Prints nothing if the key is absent, the
# file has no frontmatter, or the value is empty.
read_frontmatter_field() {
  local file="$1" key="$2"
  awk -v key="$key" '
    BEGIN { in_fm = 0; dashes = 0 }
    /^---[ \t]*$/ {
      dashes++
      if (dashes == 1) { in_fm = 1; next }
      else { exit }
    }
    in_fm && $0 ~ "^" key ":" {
      line = $0
      sub("^" key ":[ \t]*", "", line)
      sub(/[ \t]+#.*$/, "", line)
      gsub(/^"|"$/, "", line)
      gsub(/^'"'"'|'"'"'$/, "", line)
      sub(/[ \t]+$/, "", line)
      print line
      exit
    }
  ' "$file" 2>/dev/null
}

# is_valid_initiative_status STATUS
# True (0) if STATUS is a member of the closed status enum.
is_valid_initiative_status() {
  case "$1" in
    proposed|discovery|planned|active|blocked|complete|absorbed|abandoned)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# is_null_value VALUE
# True (0) if VALUE is empty or the literal YAML null ("null"/"~"), matched
# case-insensitively.
is_null_value() {
  local value lower
  value="$1"
  if [ -z "$value" ]; then
    return 0
  fi
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    null|~) return 0 ;;
    *) return 1 ;;
  esac
}

# escape_md_pipes VALUE
# Escapes "|" so a value is safe to place inside a markdown table cell.
escape_md_pipes() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}
