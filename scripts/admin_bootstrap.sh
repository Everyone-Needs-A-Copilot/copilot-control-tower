#!/usr/bin/env bash
# admin_bootstrap.sh — the deterministic engine behind the admin-bootstrap skill.
#
# Implements docs/01-architecture/admin-standup-contract.md §6 (engine script
# obligations) and §3 (the --verify --json contract). The script, never the
# model, makes every existence/idempotency decision. Every mutation is
# check-then-act (GET before POST/PATCH/PUT); nothing is ever forced, skipped
# past, or overwritten. Dependencies: gh and jq only, plus python3 (macOS
# stock) used solely to parse the brief's YAML front matter.
#
# See --help for usage.

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BRIEF_SCHEMA_VERSION="1.0"
VERIFY_SCHEMA_VERSION="1.0"
ECOSYSTEM_SCHEMA_VERSION="2.0"
FOUNDATION_REF_DEFAULT="^5.x"
DEFAULT_BRIEF_PATH="${HOME}/Library/Application Support/CopilotControlTower/standup-brief.md"

# Brief-derived state, populated by _load_brief.
ORG=""
HARNESS_LIST=()
DEPARTMENTS=()
STORE_STATUS="deferred"
STORE_TYPE=""
STORE_ENDPOINT=""
STORE_TEAM_SCOPES=()

# Verify-mode tallies.
MUST_FIX_COUNT=0
UNKNOWN_COUNT=0

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

print_help() {
  cat <<'EOF'
admin_bootstrap.sh: the deterministic engine behind the admin-bootstrap skill.

Usage:
  admin_bootstrap.sh --brief <path>
      Run the full standup from a brief. Idempotent: a re-run against a
      standing org emits only already-present/skipped and mutates nothing.

  admin_bootstrap.sh --add-department <unit> [--brief <path>]
      Add one department, safely, to a standing org. Existing units are a
      full no-op.

  admin_bootstrap.sh --verify [--brief <path>] --json
      Read-only verification against GitHub truth. Computes drift against
      the brief when one is available. Never mutates anything.

  admin_bootstrap.sh --help
      Show this help.

If --brief is omitted, the brief at the fixed path is used:
  ~/Library/Application Support/CopilotControlTower/standup-brief.md

Each mutating run emits one NDJSON line per step on stdout, in order:
  {"step": "...", "result": "created|already-present|updated|skipped|refused|failed", "detail": "..."}

Refusals print a plain instruction to stderr and exit 2. Nothing is ever
forced, bypassed, or overwritten.
EOF
}

# emit_step STEP RESULT DETAIL — one NDJSON line on stdout.
emit_step() {
  jq -nc --arg step "$1" --arg result "$2" --arg detail "$3" \
    '{step: $step, result: $result, detail: $detail}'
}

# refuse STEP DETAIL — emits a refused NDJSON line, prints the plain
# instruction to stderr, and exits 2. No mutation may happen after this.
refuse() {
  local step="$1" detail="$2"
  emit_step "$step" "refused" "$detail"
  printf '%s\n' "$detail" >&2
  exit 2
}

# fail_step STEP DETAIL — emits a failed NDJSON line, prints the detail to
# stderr, and exits 1. Prior additive steps are left intact; re-running is
# safe.
fail_step() {
  local step="$1" detail="$2"
  emit_step "$step" "failed" "$detail"
  printf '%s\n' "$detail" >&2
  exit 1
}

# _array_contains NEEDLE [ITEMS...]
_array_contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

# _join_comma [ITEMS...]
_join_comma() {
  local IFS=", "
  echo "$*"
}

# _b64_decode reads stdin, writes decoded bytes to stdout. Handles both BSD
# (macOS, -D) and GNU (-d) base64.
_b64_decode() {
  local input
  input="$(cat)"
  printf '%s' "$input" | tr -d '\n' | base64 --decode 2>/dev/null \
    || printf '%s' "$input" | tr -d '\n' | base64 -d 2>/dev/null \
    || echo ""
}

# _valid_slug VALUE — true if VALUE is a GitHub-safe slug: lowercase letters,
# digits, and single hyphens between segments (no leading/trailing/double
# hyphen). The brief is contractually a list of slugs (admin-standup-contract
# §1.3) and doubles as the verify drift baseline, so the engine never
# auto-slugifies a value it was given; it refuses instead.
_valid_slug() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

# _suggest_slug VALUE FALLBACK — a display-only suggestion for a refusal
# message. Never used to name or create anything; the engine never silently
# transforms a value it was given.
_suggest_slug() {
  local s
  s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [[ -z "$s" ]]; then
    s="$2"
  fi
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# Brief parsing (python3 isolated to this one function, stdlib only)
# ---------------------------------------------------------------------------

_parse_brief_frontmatter() {
  local brief_path="$1"
  python3 - "$brief_path" <<'PYEOF'
import sys, json

def parse_scalar(s):
    s = s.strip()
    if s == "":
        return None
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    if s in ("true", "false"):
        return s == "true"
    return s

def strip_comment(line):
    in_s = in_d = False
    for i, ch in enumerate(line):
        if ch == "'" and not in_d:
            in_s = not in_s
        elif ch == '"' and not in_s:
            in_d = not in_d
        elif ch == "#" and not in_s and not in_d:
            if i == 0 or line[i - 1] == " ":
                return line[:i]
    return line

def parse_flow_mapping(s):
    s = s.strip()
    if not (s.startswith("{") and s.endswith("}")):
        return {}
    inner = s[1:-1]
    result = {}
    for part in inner.split(","):
        if ":" not in part:
            continue
        k, v = part.split(":", 1)
        result[k.strip()] = parse_scalar(v)
    return result

def indent_of(line):
    return len(line) - len(line.lstrip(" "))

def parse_list(lines, idx, indent):
    result = []
    n = len(lines)
    i = idx
    while i < n:
        raw = lines[i]
        if raw.strip() == "":
            i += 1
            continue
        cur = indent_of(raw)
        if cur != indent:
            break
        line = raw.strip()
        if not line.startswith("- "):
            break
        item = line[2:].strip()
        if item.startswith("{"):
            result.append(parse_flow_mapping(item))
        else:
            result.append(parse_scalar(item))
        i += 1
    return result, i

def parse_block(lines, idx, indent):
    result = {}
    n = len(lines)
    i = idx
    while i < n:
        raw = lines[i]
        if raw.strip() == "":
            i += 1
            continue
        cur = indent_of(raw)
        if cur < indent:
            break
        if cur > indent:
            i += 1
            continue
        line = raw.strip()
        if line.startswith("- "):
            break
        if ":" not in line:
            i += 1
            continue
        key, _, rest = line.partition(":")
        key = key.strip()
        rest = rest.strip()
        if rest == "":
            j = i + 1
            while j < n and lines[j].strip() == "":
                j += 1
            if j < n:
                next_indent = indent_of(lines[j])
                next_stripped = lines[j].strip()
            else:
                next_indent = -1
                next_stripped = ""
            if next_indent > indent and next_stripped.startswith("- "):
                value, i = parse_list(lines, j, next_indent)
            elif next_indent > indent:
                value, i = parse_block(lines, j, next_indent)
            else:
                value = None
                i = j
        else:
            value = parse_scalar(rest)
            i += 1
        result[key] = value
    return result, i

def main():
    path = sys.argv[1]
    with open(path, "r") as f:
        content = f.read()
    lines_all = content.split("\n")
    if not lines_all or lines_all[0].strip() != "---":
        print(json.dumps({"error": "no front matter"}))
        sys.exit(1)
    end = None
    for idx in range(1, len(lines_all)):
        if lines_all[idx].strip() == "---":
            end = idx
            break
    if end is None:
        print(json.dumps({"error": "unterminated front matter"}))
        sys.exit(1)
    fm_lines = [strip_comment(l).rstrip() for l in lines_all[1:end]]
    data, _ = parse_block(fm_lines, 0, 0)
    print(json.dumps(data))

main()
PYEOF
}

_load_brief() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    refuse "brief" "I couldn't find a standup brief at $path. Pass --brief <path>, or describe your organization to Claude Code first."
  fi

  local json
  if ! json="$(_parse_brief_frontmatter "$path" 2>/dev/null)" || ! echo "$json" | jq -e . >/dev/null 2>&1; then
    refuse "brief" "I couldn't read the brief at $path as valid front matter, so I won't guess."
  fi

  local schema
  schema="$(echo "$json" | jq -r '.schema_version // empty')"
  if [[ -z "$schema" ]]; then
    refuse "brief" "The brief at $path is missing schema_version, so I won't guess its shape."
  fi
  if [[ "$schema" != "$BRIEF_SCHEMA_VERSION" ]]; then
    refuse "brief" "The brief at $path is schema $schema, which this setup doesn't understand. Update setup, or update the brief."
  fi

  ORG="$(echo "$json" | jq -r '.org // empty')"
  if [[ -z "$ORG" ]]; then
    refuse "brief" "The brief at $path is missing an organization name, so I won't guess."
  fi
  if ! _valid_slug "$ORG"; then
    refuse "validate-slug" "Organization name \"$ORG\" can't be used on GitHub. Use letters, numbers, and dashes, like $(_suggest_slug "$ORG" "your-org"), and update the brief."
  fi

  HARNESS_LIST=()
  while IFS= read -r h; do
    [[ -n "$h" ]] && HARNESS_LIST+=("$h")
  done < <(echo "$json" | jq -r '.harness[]? // empty')
  if [[ "${#HARNESS_LIST[@]}" -eq 0 ]]; then
    refuse "brief" "The brief at $path names no development harness, so I won't guess which spaces to create."
  fi

  DEPARTMENTS=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && DEPARTMENTS+=("$d")
  done < <(echo "$json" | jq -r '.departments[]? // empty')

  # The brief is contractually a list of slugs (admin-standup-contract §1.3)
  # and doubles as the verify drift baseline: never auto-slugify a value it
  # was given, refuse instead, before any mutation or network call.
  local dept
  for dept in "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; do
    if ! _valid_slug "$dept"; then
      refuse "validate-slug" "Department name \"$dept\" can't be used on GitHub. Use letters, numbers, and dashes, like $(_suggest_slug "$dept" "department"), and update the brief."
    fi
  done

  STORE_STATUS="$(echo "$json" | jq -r '.store.status // "deferred"')"
  STORE_TYPE="$(echo "$json" | jq -r '.store.type // empty')"
  STORE_ENDPOINT="$(echo "$json" | jq -r '.store.endpoint // empty')"
  STORE_TEAM_SCOPES=()
  while IFS= read -r s; do
    [[ -n "$s" ]] && STORE_TEAM_SCOPES+=("$s")
  done < <(echo "$json" | jq -r '.store.team_scopes[]? | "{ team: " + .team + ", scope: " + .scope + " }"' 2>/dev/null)
}

# ---------------------------------------------------------------------------
# Naming (component-first, per admin-standup-contract §6/§7)
# ---------------------------------------------------------------------------

_org_triplet_repos() {
  local h repos=()
  for h in "${HARNESS_LIST[@]}"; do
    repos+=("${h}-copilot")
  done
  repos+=("knowledge-copilot" "cli-copilot")
  printf '%s\n' "${repos[@]}"
}

_dept_triplet_repos() {
  local unit="$1" h repos=()
  for h in "${HARNESS_LIST[@]}"; do
    repos+=("${h}-copilot-${unit}")
  done
  repos+=("knowledge-copilot-${unit}" "cli-copilot-${unit}")
  printf '%s\n' "${repos[@]}"
}

# ---------------------------------------------------------------------------
# GitHub check-then-act primitives
# ---------------------------------------------------------------------------

# _gh_read ENDPOINT JQ_EXPR — the single honest read primitive. A plain
# `cmd 2>/dev/null || echo "fallback"` cannot tell "confirmed absent" from
# "the read itself failed" (network, auth, rate limit, 5xx); collapsing them
# lets a genuine failure hide behind an idempotent write that happens to
# succeed anyway, reporting a false "updated"/"already-present" instead of
# ever surfacing the failure. This never guesses: it distinguishes the two.
#
# Sets:
#   _GH_READ_STATUS = "ok" | "not-found" | "error"
#   _GH_READ_VALUE  = the --jq-filtered value, only meaningful when "ok"
# Returns 0 on "ok", 1 otherwise.
_gh_read() {
  local endpoint="$1" jq_expr="${2:-.}" err_file out rc
  err_file="$(mktemp)"
  if out="$(gh api "$endpoint" --jq "$jq_expr" 2>"$err_file")"; then
    _GH_READ_STATUS="ok"
    _GH_READ_VALUE="$out"
    rc=0
  else
    if grep -qi 'HTTP 404' "$err_file" 2>/dev/null; then
      _GH_READ_STATUS="not-found"
    else
      _GH_READ_STATUS="error"
    fi
    _GH_READ_VALUE=""
    rc=1
  fi
  rm -f "$err_file"
  return $rc
}

_preflight() {
  local org="$1" login scope_header role

  if ! login="$(gh api user --jq .login 2>/dev/null)" || [[ -z "$login" ]]; then
    refuse "readiness" "You're not signed in to GitHub's command-line tool yet. Run: gh auth login"
  fi

  scope_header="$(gh api -i user 2>/dev/null | grep -i '^x-oauth-scopes:' || true)"
  if [[ "$scope_header" != *"repo"* || "$scope_header" != *"admin:org"* ]]; then
    refuse "readiness" "Your GitHub sign-in is missing the access setup needs. Run: gh auth refresh -s admin:org -s repo"
  fi

  if ! gh api "orgs/$org" >/dev/null 2>&1; then
    refuse "readiness" "$org doesn't exist on GitHub yet. Creating an organization needs billing and a person, so create it at github.com first, then run this again."
  fi

  if _gh_read "orgs/$org/memberships/$login" '.role // empty'; then
    role="$_GH_READ_VALUE"
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    role=""
  else
    refuse "readiness" "I couldn't check whether your GitHub account is an owner of $org, so I won't guess. Check your connection and try again."
  fi
  if [[ "$role" != "admin" ]]; then
    refuse "readiness" "Your GitHub account isn't an owner of $org, so it can't create its spaces. Ask an owner to run this, or to make you one."
  fi

  emit_step "readiness" "already-present" "Signed in as $login, an owner of $org, with the access setup needs."
}

_ensure_org_base_permission() {
  local org="$1" current
  # By this point _preflight has already confirmed the org exists, so any
  # failure to read it here (not just an absent value) is a genuine error,
  # never a legitimate "not set yet" — see _gh_read.
  if _gh_read "orgs/$org" '.default_repository_permission // empty'; then
    current="$_GH_READ_VALUE"
  else
    fail_step "org-base-permission" "Could not read $org's default access level, so I won't guess. It's safe to run this again."
  fi
  if [[ "$current" == "read" ]]; then
    emit_step "org-base-permission" "already-present" "$org already defaults new members to read."
    return
  fi
  if gh api -X PATCH "orgs/$org" -f default_repository_permission=read >/dev/null 2>&1; then
    emit_step "org-base-permission" "updated" "Set $org's default access to read."
  else
    fail_step "org-base-permission" "Could not set $org's default access to read."
  fi
}

_ensure_repo() {
  local org="$1" reponame="$2" step="$3"
  if gh api "repos/$org/$reponame" >/dev/null 2>&1; then
    emit_step "$step" "already-present" "$org/$reponame already exists."
    return
  fi
  if gh api -X POST "orgs/$org/repos" -f name="$reponame" -F private=true >/dev/null 2>&1; then
    emit_step "$step" "created" "Created $org/$reponame, private."
  else
    fail_step "$step" "Could not create $org/$reponame."
  fi
}

_ensure_branch_protection() {
  local org="$1" reponame="$2" step="$3" default_branch existing

  # This repo was already created/confirmed earlier in this same run, so it
  # should always be readable here; any failure is a genuine error, never a
  # legitimate "no content yet" (that's the empty-default_branch case below).
  if _gh_read "repos/$org/$reponame" '.default_branch // empty'; then
    default_branch="$_GH_READ_VALUE"
  else
    fail_step "$step" "Could not read $org/$reponame, so I won't guess whether it needs branch protection. It's safe to run this again."
  fi
  if [[ -z "$default_branch" ]]; then
    emit_step "$step" "skipped" "$org/$reponame has no content yet, nothing to protect."
    return
  fi

  # A repo with no commits yet has no branch, so a 404 here is a legitimate,
  # expected "nothing to protect" (not an error).
  if _gh_read "repos/$org/$reponame/branches/$default_branch" '.name // empty'; then
    :
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    emit_step "$step" "skipped" "$org/$reponame has no commits yet, nothing to protect."
    return
  else
    fail_step "$step" "Could not check whether $org/$reponame has any commits yet, so I won't guess. It's safe to run this again."
  fi

  # No protection configured yet is also a legitimate, expected 404.
  if _gh_read "repos/$org/$reponame/branches/$default_branch/protection" '.required_pull_request_reviews // empty'; then
    existing="$_GH_READ_VALUE"
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    existing=""
  else
    fail_step "$step" "Could not check branch protection on $org/$reponame, so I won't guess. It's safe to run this again."
  fi
  if [[ -n "$existing" ]]; then
    emit_step "$step" "already-present" "$org/$reponame already requires review before merge."
    return
  fi

  if echo '{"required_pull_request_reviews":{"required_approving_review_count":1},"enforce_admins":true,"required_status_checks":null,"restrictions":null}' \
    | gh api -X PUT "repos/$org/$reponame/branches/$default_branch/protection" --input - >/dev/null 2>&1; then
    emit_step "$step" "updated" "Set $org/$reponame to require review before merge."
  else
    fail_step "$step" "Could not set branch protection on $org/$reponame."
  fi
}

_ensure_team() {
  local org="$1" unit="$2" step="$3"
  if gh api "orgs/$org/teams/$unit" >/dev/null 2>&1; then
    emit_step "$step" "already-present" "The $unit team already exists."
    return
  fi
  if gh api -X POST "orgs/$org/teams" -f name="$unit" -f privacy=closed >/dev/null 2>&1; then
    emit_step "$step" "created" "Created the $unit team."
  else
    fail_step "$step" "Could not create the $unit team."
  fi
}

_ensure_team_grant() {
  local org="$1" unit="$2" reponame="$3" step="$4" current
  # No grant yet is a legitimate, expected 404 (that's exactly what this
  # check exists to detect); any other failure is a genuine error.
  if _gh_read "orgs/$org/teams/$unit/repos/$org/$reponame" '.permissions.push // false'; then
    current="$_GH_READ_VALUE"
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    current="false"
  else
    fail_step "$step" "Could not check whether the $unit team can already reach $org/$reponame, so I won't guess. It's safe to run this again."
  fi
  if [[ "$current" == "true" ]]; then
    emit_step "$step" "already-present" "The $unit team can already reach $org/$reponame."
    return
  fi
  if gh api -X PUT "orgs/$org/teams/$unit/repos/$org/$reponame" -f permission=push >/dev/null 2>&1; then
    emit_step "$step" "updated" "Gave the $unit team access to $org/$reponame."
  else
    fail_step "$step" "Could not grant the $unit team access to $org/$reponame."
  fi
}

# _repo_exists_private ORG REPO — true (exit 0) if the repo exists and is
# private. Sets _REPO_CHECK_STATUS to "checked" (a definite answer, whether
# true or false) or "error" (the read itself failed; callers must never
# count this as a confirmed miss — it renders "unknown", not "fail").
_repo_exists_private() {
  local org="$1" repo="$2"
  if _gh_read "repos/$org/$repo" '.private // false'; then
    _REPO_CHECK_STATUS="checked"
    [[ "$_GH_READ_VALUE" == "true" ]]
    return
  fi
  if [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    _REPO_CHECK_STATUS="checked"
    return 1
  fi
  _REPO_CHECK_STATUS="error"
  return 1
}

# _team_can_reach ORG UNIT REPO — true (exit 0) if the team already has
# push access. Sets _TEAM_CHECK_STATUS to "checked" or "error", same
# contract as _REPO_CHECK_STATUS above.
_team_can_reach() {
  local org="$1" unit="$2" repo="$3"
  if _gh_read "orgs/$org/teams/$unit/repos/$org/$repo" '.permissions.push // false'; then
    _TEAM_CHECK_STATUS="checked"
    [[ "$_GH_READ_VALUE" == "true" ]]
    return
  fi
  if [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    _TEAM_CHECK_STATUS="checked"
    return 1
  fi
  _TEAM_CHECK_STATUS="error"
  return 1
}

# ---------------------------------------------------------------------------
# ecosystem.yml — additive read/render/merge (v-next, schema 2.0)
# ---------------------------------------------------------------------------

# Reader state, set by _read_ecosystem_state.
_STATE_HARNESS=()
_STATE_DEPT_UNITS=()
_STATE_STORE_STATUS=""
_STATE_STORE_TYPE=""
_STATE_STORE_ENDPOINT=""
_STATE_STORE_SCOPES=()

_read_ecosystem_state() {
  local content="$1"
  _STATE_HARNESS=()
  _STATE_DEPT_UNITS=()
  _STATE_STORE_STATUS=""
  _STATE_STORE_TYPE=""
  _STATE_STORE_ENDPOINT=""
  _STATE_STORE_SCOPES=()

  local section="" line trimmed
  while IFS= read -r line; do
    case "$line" in
      "harness:") section="harness"; continue ;;
      "components:") section="components"; continue ;;
      "departments:") section="departments"; continue ;;
      "store:") section="store"; continue ;;
      "foundation:") section="foundation"; continue ;;
      "schema_version:"*|"org:"*) section=""; continue ;;
    esac
    case "$line" in
      "  - "*)
        trimmed="${line#  - }"
        if [[ "$section" == "harness" ]]; then
          _STATE_HARNESS+=("$trimmed")
        elif [[ "$section" == "departments" ]]; then
          if [[ "$trimmed" == unit:* ]]; then
            trimmed="${trimmed#unit:}"
            trimmed="${trimmed# }"
            _STATE_DEPT_UNITS+=("$trimmed")
          fi
        fi
        ;;
      "    - "*)
        trimmed="${line#    - }"
        if [[ "$section" == "store" && "$trimmed" == "{"* ]]; then
          _STATE_STORE_SCOPES+=("$trimmed")
        fi
        ;;
      "  status: "*)
        [[ "$section" == "store" ]] && _STATE_STORE_STATUS="${line#  status: }"
        ;;
      "  type: "*)
        [[ "$section" == "store" ]] && _STATE_STORE_TYPE="${line#  type: }"
        ;;
      "  endpoint: "*)
        [[ "$section" == "store" ]] && _STATE_STORE_ENDPOINT="${line#  endpoint: }"
        ;;
    esac
  done <<< "$content"
}

# Merge working state, set by _write_ecosystem_yml before rendering.
MERGE_HARNESS=()
MERGE_COMPONENTS=()
MERGE_DEPTS=()
MERGE_STORE_STATUS="deferred"
MERGE_STORE_TYPE=""
MERGE_STORE_ENDPOINT=""
MERGE_STORE_SCOPES=()

_render_ecosystem_yml() {
  local org="$1" h c u s
  printf 'schema_version: "%s"\n' "$ECOSYSTEM_SCHEMA_VERSION"
  printf 'org: %s\n' "$org"
  printf 'harness:\n'
  for h in "${MERGE_HARNESS[@]}"; do
    printf '  - %s\n' "$h"
  done
  printf 'components:\n'
  for c in "${MERGE_COMPONENTS[@]}"; do
    printf '  - %s\n' "$c"
  done
  printf 'departments:\n'
  for u in "${MERGE_DEPTS[@]+"${MERGE_DEPTS[@]}"}"; do
    printf '  - unit: %s\n' "$u"
    printf '    topology: separate\n'
  done
  printf 'store:\n'
  if [[ "$MERGE_STORE_STATUS" == "connected" ]]; then
    printf '  status: connected\n'
    printf '  type: %s\n' "$MERGE_STORE_TYPE"
    printf '  endpoint: %s\n' "$MERGE_STORE_ENDPOINT"
    printf '  team_scopes:\n'
    for s in "${MERGE_STORE_SCOPES[@]+"${MERGE_STORE_SCOPES[@]}"}"; do
      printf '    - %s\n' "$s"
    done
  else
    printf '  status: deferred\n'
  fi
  printf 'foundation:\n'
  printf '  ref: "%s"\n' "$FOUNDATION_REF_DEFAULT"
}

_leak_scan() {
  local content="$1"
  if echo "$content" | grep -Eq 'BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY'; then
    return 1
  fi
  if echo "$content" | grep -Eq '(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_)[A-Za-z0-9_]{10,}'; then
    return 1
  fi
  if echo "$content" | grep -Eq 'AKIA[0-9A-Z]{16}'; then
    return 1
  fi
  if echo "$content" | grep -Eq 'xox[baprs]-[A-Za-z0-9-]{10,}'; then
    return 1
  fi
  if echo "$content" | grep -Eiq '(secret|password|private_key|api_key)[A-Za-z0-9_.-]*[[:space:]]*[:=][[:space:]]*[A-Za-z0-9/+_.=-]{12,}'; then
    return 1
  fi
  if echo "$content" | grep -Eq ': [A-Za-z0-9+/]{40,}={0,2}[[:space:]]*$'; then
    return 1
  fi
  return 0
}

_write_ecosystem_yml() {
  local org="$1"
  local target_repo="${HARNESS_LIST[0]}-copilot"
  local step="ecosystem-yml"
  local get_out="" sha="" existing_b64="" existing_content=""

  if get_out="$(gh api "repos/$org/$target_repo/contents/ecosystem.yml" 2>/dev/null)"; then
    sha="$(echo "$get_out" | jq -r '.sha')"
    existing_b64="$(echo "$get_out" | jq -r '.content')"
    existing_content="$(printf '%s' "$existing_b64" | _b64_decode)"
  fi

  MERGE_HARNESS=()
  MERGE_DEPTS=()
  MERGE_STORE_STATUS="$STORE_STATUS"
  MERGE_STORE_TYPE="$STORE_TYPE"
  MERGE_STORE_ENDPOINT="$STORE_ENDPOINT"
  MERGE_STORE_SCOPES=("${STORE_TEAM_SCOPES[@]+"${STORE_TEAM_SCOPES[@]}"}")

  if [[ -n "$existing_content" ]]; then
    _read_ecosystem_state "$existing_content"
    MERGE_HARNESS=("${_STATE_HARNESS[@]+"${_STATE_HARNESS[@]}"}")
    MERGE_DEPTS=("${_STATE_DEPT_UNITS[@]+"${_STATE_DEPT_UNITS[@]}"}")
    if [[ "$_STATE_STORE_STATUS" == "connected" ]]; then
      MERGE_STORE_STATUS="connected"
      MERGE_STORE_TYPE="$_STATE_STORE_TYPE"
      MERGE_STORE_ENDPOINT="$_STATE_STORE_ENDPOINT"
      MERGE_STORE_SCOPES=("${_STATE_STORE_SCOPES[@]+"${_STATE_STORE_SCOPES[@]}"}")
    fi
  fi

  local h u
  for h in "${HARNESS_LIST[@]}"; do
    if ! _array_contains "$h" "${MERGE_HARNESS[@]+"${MERGE_HARNESS[@]}"}"; then
      MERGE_HARNESS+=("$h")
    fi
  done
  for u in "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; do
    if ! _array_contains "$u" "${MERGE_DEPTS[@]+"${MERGE_DEPTS[@]}"}"; then
      MERGE_DEPTS+=("$u")
    fi
  done

  MERGE_COMPONENTS=("knowledge" "cli")
  for h in "${MERGE_HARNESS[@]}"; do
    MERGE_COMPONENTS+=("$h")
  done

  local new_content
  new_content="$(_render_ecosystem_yml "$org")"

  if [[ -n "$existing_content" && "$new_content" == "$existing_content" ]]; then
    emit_step "$step" "already-present" "$org/$target_repo already carries this ecosystem.yml."
    return
  fi

  if ! _leak_scan "$new_content"; then
    refuse "leak-scan" "ecosystem.yml would have carried a secret-shaped value, so I stopped before pushing anything. Remove the secret and use a store reference instead."
  fi

  local encoded
  encoded="$(printf '%s' "$new_content" | base64 | tr -d '\n')"

  if [[ -z "$existing_content" ]]; then
    if gh api -X PUT "repos/$org/$target_repo/contents/ecosystem.yml" -f message="Initial ecosystem.yml" -f content="$encoded" >/dev/null 2>&1; then
      emit_step "$step" "created" "Wrote the initial ecosystem.yml to $org/$target_repo."
    else
      fail_step "$step" "Could not write ecosystem.yml to $org/$target_repo."
    fi
  else
    if gh api -X PUT "repos/$org/$target_repo/contents/ecosystem.yml" -f message="Update ecosystem.yml" -f content="$encoded" -f sha="$sha" >/dev/null 2>&1; then
      emit_step "$step" "updated" "Added new entries to $org/$target_repo's ecosystem.yml."
    else
      fail_step "$step" "Could not update ecosystem.yml in $org/$target_repo."
    fi
  fi
}

# ---------------------------------------------------------------------------
# Standup / add-department orchestration
# ---------------------------------------------------------------------------

run_standup() {
  local org="$1" repo unit harness_repo="${HARNESS_LIST[0]}-copilot"

  _preflight "$org"
  _ensure_org_base_permission "$org"

  while IFS= read -r repo; do
    _ensure_repo "$org" "$repo" "org-repo:$repo"
  done < <(_org_triplet_repos)

  # Branch protection for the org repos this engine never seeds with content
  # (they stay empty, so protection legitimately, honestly stays "skipped").
  # The harness repo is protected further down, once it actually carries
  # ecosystem.yml (a repo with no commits has no branch to protect yet; see
  # admin-agentic-setup.md §5 open decision 4, "initial commit on the empty
  # repo, enable protection after").
  for repo in "knowledge-copilot" "cli-copilot"; do
    _ensure_branch_protection "$org" "$repo" "branch-protection:$repo"
  done

  for unit in "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; do
    while IFS= read -r repo; do
      _ensure_repo "$org" "$repo" "dept-repo:$unit:$repo"
    done < <(_dept_triplet_repos "$unit")

    _ensure_team "$org" "$unit" "dept-team:$unit"

    while IFS= read -r repo; do
      _ensure_team_grant "$org" "$unit" "$repo" "dept-grant:$unit:$repo"
    done < <(_dept_triplet_repos "$unit")

    # Department repos are never seeded with content in this slice either,
    # so their protection also honestly stays "skipped" for now.
    while IFS= read -r repo; do
      _ensure_branch_protection "$org" "$repo" "branch-protection:$repo"
    done < <(_dept_triplet_repos "$unit")
  done

  _write_ecosystem_yml "$org"
  _ensure_branch_protection "$org" "$harness_repo" "branch-protection:$harness_repo"
}

run_add_department() {
  local org="$1" unit="$2" repo

  if [[ -z "$unit" ]]; then
    refuse "brief" "Give --add-department a department name."
  fi
  if ! _valid_slug "$unit"; then
    refuse "validate-slug" "Department name \"$unit\" can't be used on GitHub. Use letters, numbers, and dashes, like $(_suggest_slug "$unit" "department")."
  fi

  _preflight "$org"

  while IFS= read -r repo; do
    _ensure_repo "$org" "$repo" "dept-repo:$unit:$repo"
  done < <(_dept_triplet_repos "$unit")

  _ensure_team "$org" "$unit" "dept-team:$unit"

  while IFS= read -r repo; do
    _ensure_team_grant "$org" "$unit" "$repo" "dept-grant:$unit:$repo"
  done < <(_dept_triplet_repos "$unit")

  while IFS= read -r repo; do
    _ensure_branch_protection "$org" "$repo" "branch-protection:$repo"
  done < <(_dept_triplet_repos "$unit")

  DEPARTMENTS=("$unit")
  _write_ecosystem_yml "$org"
}

# ---------------------------------------------------------------------------
# Verify (read-only)
# ---------------------------------------------------------------------------

_check_row() {
  jq -nc --arg check "$1" --arg status "$2" --arg detail "$3" --arg owner "$4" --arg fix "$5" \
    '{check: $check, status: $status, detail: $detail, owner: $owner, fix_surface: $fix}'
}

_tally() {
  local status
  status="$(echo "$1" | jq -r '.status')"
  case "$status" in
    fail) MUST_FIX_COUNT=$((MUST_FIX_COUNT + 1)) ;;
    unknown) UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1)) ;;
  esac
}

_check_org_triplet() {
  local org="$1" missing=() unreadable=() h reponame
  for h in "${HARNESS_LIST[@]}"; do
    reponame="${h}-copilot"
    if ! _repo_exists_private "$org" "$reponame"; then
      if [[ "$_REPO_CHECK_STATUS" == "error" ]]; then unreadable+=("$org/$reponame"); else missing+=("$org/$reponame"); fi
    fi
  done
  for reponame in "knowledge-copilot" "cli-copilot"; do
    if ! _repo_exists_private "$org" "$reponame"; then
      if [[ "$_REPO_CHECK_STATUS" == "error" ]]; then unreadable+=("$org/$reponame"); else missing+=("$org/$reponame"); fi
    fi
  done
  if [[ "${#unreadable[@]}" -gt 0 ]]; then
    _check_row "org-triplet" "unknown" "I couldn't check: $(_join_comma "${unreadable[@]}"), so I won't guess." "Admin" "describe"
  elif [[ "${#missing[@]}" -eq 0 ]]; then
    _check_row "org-triplet" "pass" "Your organization's shared spaces exist, private." "" "none"
  else
    _check_row "org-triplet" "fail" "Missing or not private: $(_join_comma "${missing[@]}")." "Admin" "describe"
  fi
}

_check_org_base_read() {
  local org="$1" current
  if _gh_read "orgs/$org" '.default_repository_permission // empty'; then
    current="$_GH_READ_VALUE"
    if [[ "$current" == "read" ]]; then
      _check_row "org-base-read" "pass" "$org defaults new members to read." "" "none"
    elif [[ -z "$current" ]]; then
      _check_row "org-base-read" "unknown" "I couldn't read $org's default access level, so I won't guess." "GitHub org owner" "external"
    else
      _check_row "org-base-read" "fail" "$org's default access is $current, not read." "GitHub org owner" "external"
    fi
  else
    _check_row "org-base-read" "unknown" "I couldn't read $org's default access level, so I won't guess." "GitHub org owner" "external"
  fi
}

_check_dept_triplet() {
  local org="$1" unit="$2" missing=() unreadable=() h reponame
  for h in "${HARNESS_LIST[@]}"; do
    reponame="${h}-copilot-${unit}"
    if ! _repo_exists_private "$org" "$reponame"; then
      if [[ "$_REPO_CHECK_STATUS" == "error" ]]; then unreadable+=("$org/$reponame"); else missing+=("$org/$reponame"); fi
    fi
  done
  for reponame in "knowledge-copilot-${unit}" "cli-copilot-${unit}"; do
    if ! _repo_exists_private "$org" "$reponame"; then
      if [[ "$_REPO_CHECK_STATUS" == "error" ]]; then unreadable+=("$org/$reponame"); else missing+=("$org/$reponame"); fi
    fi
  done
  if [[ "${#unreadable[@]}" -gt 0 ]]; then
    _check_row "dept-triplet" "unknown" "I couldn't check $unit's spaces: $(_join_comma "${unreadable[@]}"), so I won't guess." "Admin" "describe"
  elif [[ "${#missing[@]}" -eq 0 ]]; then
    _check_row "dept-triplet" "pass" "$unit's spaces exist, private." "" "none"
  else
    _check_row "dept-triplet" "fail" "$unit is missing or not private: $(_join_comma "${missing[@]}")." "Admin" "describe"
  fi
}

_check_dept_team_grant() {
  local org="$1" unit="$2" missing=() unreadable=() h repo
  if _gh_read "orgs/$org/teams/$unit" '.slug // empty'; then
    :
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    _check_row "dept-team-grant" "fail" "The $unit team doesn't exist yet." "Admin" "describe"
    return
  else
    _check_row "dept-team-grant" "unknown" "I couldn't check whether the $unit team exists, so I won't guess." "Admin" "describe"
    return
  fi
  for h in "${HARNESS_LIST[@]}"; do
    repo="${h}-copilot-${unit}"
    if ! _team_can_reach "$org" "$unit" "$repo"; then
      if [[ "$_TEAM_CHECK_STATUS" == "error" ]]; then unreadable+=("$repo"); else missing+=("$repo"); fi
    fi
  done
  for repo in "knowledge-copilot-${unit}" "cli-copilot-${unit}"; do
    if ! _team_can_reach "$org" "$unit" "$repo"; then
      if [[ "$_TEAM_CHECK_STATUS" == "error" ]]; then unreadable+=("$repo"); else missing+=("$repo"); fi
    fi
  done
  if [[ "${#unreadable[@]}" -gt 0 ]]; then
    _check_row "dept-team-grant" "unknown" "I couldn't check whether the $unit team can reach: $(_join_comma "${unreadable[@]}"), so I won't guess." "Admin" "describe"
  elif [[ "${#missing[@]}" -eq 0 ]]; then
    _check_row "dept-team-grant" "pass" "The $unit team can reach all of its spaces." "" "none"
  else
    _check_row "dept-team-grant" "fail" "The $unit team can't reach: $(_join_comma "${missing[@]}")." "Admin" "describe"
  fi
}

_check_undeclared_departments() {
  local org="$1" names unit err_file
  # --paginate is a flag _gh_read doesn't support, so this reads directly,
  # but still captures failure honestly: a scan that cannot run must never
  # silently look like "nothing extra found".
  err_file="$(mktemp)"
  if ! names="$(gh api "orgs/$org/repos" --paginate --jq '.[].name' 2>"$err_file")"; then
    rm -f "$err_file"
    _check_row "dept-triplet" "unknown" "I couldn't check GitHub for departments beyond your plan, so I won't guess." "Admin" "describe"
    return
  fi
  rm -f "$err_file"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    case "$name" in
      knowledge-copilot-*)
        unit="${name#knowledge-copilot-}"
        if ! _array_contains "$unit" "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; then
          _check_row "dept-triplet" "present-undeclared" "$org has a $unit department that isn't in your plan. Setup added it, and that's fine." "" "none"
        fi
        ;;
    esac
  done <<< "$names"
}

_check_ecosystem_file() {
  local org="$1" target_repo="${HARNESS_LIST[0]}-copilot" info b64 content err_file
  err_file="$(mktemp)"
  if ! info="$(gh api "repos/$org/$target_repo/contents/ecosystem.yml" 2>"$err_file")"; then
    if grep -qi 'HTTP 404' "$err_file" 2>/dev/null; then
      rm -f "$err_file"
      _check_row "ecosystem-file" "fail" "$org/$target_repo has no ecosystem.yml yet." "Admin" "describe"
    else
      rm -f "$err_file"
      _check_row "ecosystem-file" "unknown" "I couldn't read $org/$target_repo's ecosystem.yml, so I won't guess." "Admin" "describe"
    fi
    return
  fi
  rm -f "$err_file"
  b64="$(echo "$info" | jq -r '.content')"
  content="$(printf '%s' "$b64" | _b64_decode)"
  if [[ -z "$content" ]]; then
    _check_row "ecosystem-file" "unknown" "I couldn't read $org/$target_repo's ecosystem.yml, so I won't guess." "Admin" "describe"
    return
  fi
  _read_ecosystem_state "$content"
  local h missing_h=() u missing_u=()
  for h in "${HARNESS_LIST[@]}"; do
    _array_contains "$h" "${_STATE_HARNESS[@]+"${_STATE_HARNESS[@]}"}" || missing_h+=("$h")
  done
  for u in "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; do
    _array_contains "$u" "${_STATE_DEPT_UNITS[@]+"${_STATE_DEPT_UNITS[@]}"}" || missing_u+=("$u")
  done
  if [[ "${#missing_h[@]}" -eq 0 && "${#missing_u[@]}" -eq 0 ]]; then
    _check_row "ecosystem-file" "pass" "$org/$target_repo's ecosystem.yml matches your plan." "" "none"
  else
    _check_row "ecosystem-file" "fail" "$org/$target_repo's ecosystem.yml is missing: $(_join_comma "${missing_h[@]+"${missing_h[@]}"}" "${missing_u[@]+"${missing_u[@]}"}")." "Admin" "describe"
  fi
}

_tcp_reachable() {
  local url="$1" scheme rest host port
  scheme="${url%%://*}"
  rest="${url#*://}"
  host="${rest%%/*}"
  if [[ "$host" == *:* ]]; then
    port="${host##*:}"
    host="${host%%:*}"
  elif [[ "$scheme" == "https" ]]; then
    port=443
  else
    port=80
  fi
  ( exec 3<>"/dev/tcp/$host/$port" ) 2>/dev/null
}

_check_store() {
  if [[ "$STORE_STATUS" == "deferred" ]]; then
    _check_row "store" "deferred" "Not connected yet. Shared integrations can't work until you connect one. You chose to do this later." "Admin" "connect-store"
    return
  fi
  if [[ -z "$STORE_ENDPOINT" ]]; then
    _check_row "store" "unknown" "I couldn't read your store's address, so I won't guess." "IT infra" "connect-store"
    return
  fi
  if _tcp_reachable "$STORE_ENDPOINT"; then
    _check_row "store" "pass" "Your shared secret store answered at $STORE_ENDPOINT." "" "none"
  else
    _check_row "store" "fail" "Your shared secret store at $STORE_ENDPOINT didn't answer." "IT infra" "connect-store"
  fi
}

_check_foundation_pin() {
  local h="${HARNESS_LIST[0]}" repo="${h}-copilot"
  if gh api "repos/Everyone-Needs-A-Copilot/${repo}" >/dev/null 2>&1; then
    _check_row "foundation-pin" "pass" "The foundation reference for $h resolves." "" "none"
  else
    _check_row "foundation-pin" "unknown" "I couldn't reach the public foundation reference for $h, so I won't guess." "ENAC/external" "external"
  fi
}

run_verify() {
  local org="$ORG"
  local checks_json="[]" row unit

  row="$(_check_org_triplet "$org")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
  row="$(_check_org_base_read "$org")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"

  for unit in "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; do
    row="$(_check_dept_triplet "$org" "$unit")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
    row="$(_check_dept_team_grant "$org" "$unit")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
  done

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"
  done < <(_check_undeclared_departments "$org")

  row="$(_check_ecosystem_file "$org")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
  row="$(_check_store)"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
  row="$(_check_foundation_pin)"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"

  jq -n --arg sv "$VERIFY_SCHEMA_VERSION" --argjson checks "$checks_json" \
        --argjson mf "$MUST_FIX_COUNT" --argjson un "$UNKNOWN_COUNT" \
    '{schema_version: $sv, checks: $checks, summary: {must_fix: $mf, unknown: $un}}'
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
  local mode="standup" brief_path="" add_dept="" json_flag=false

  if [[ $# -eq 0 ]]; then
    print_help
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        print_help
        exit 0
        ;;
      --brief)
        [[ $# -ge 2 ]] || { echo "--brief needs a path." >&2; exit 1; }
        brief_path="$2"
        shift 2
        ;;
      --add-department)
        [[ $# -ge 2 ]] || { echo "--add-department needs a department name." >&2; exit 1; }
        mode="add-department"
        add_dept="$2"
        shift 2
        ;;
      --verify)
        mode="verify"
        shift
        ;;
      --json)
        json_flag=true
        shift
        ;;
      *)
        echo "Unknown argument: $1" >&2
        print_help >&2
        exit 1
        ;;
    esac
  done

  # jq is needed before we can emit any NDJSON refusal, so check it first
  # with a plain message.
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq isn't on this Mac yet. Setup runs through it. Install it with: brew install jq" >&2
    exit 2
  fi
  if ! command -v gh >/dev/null 2>&1; then
    refuse "readiness" "GitHub's command-line tool isn't on this Mac yet. Setup runs through it. Install it with: brew install gh"
  fi

  case "$mode" in
    standup)
      [[ -n "$brief_path" ]] || brief_path="$DEFAULT_BRIEF_PATH"
      _load_brief "$brief_path"
      run_standup "$ORG"
      ;;
    add-department)
      [[ -n "$brief_path" ]] || brief_path="$DEFAULT_BRIEF_PATH"
      _load_brief "$brief_path"
      run_add_department "$ORG" "$add_dept"
      ;;
    verify)
      if ! $json_flag; then
        echo "--verify requires --json." >&2
        exit 1
      fi
      [[ -n "$brief_path" ]] || brief_path="$DEFAULT_BRIEF_PATH"
      if [[ ! -f "$brief_path" ]]; then
        echo "I couldn't find a standup brief at $brief_path, so there's nothing to verify against. Pass --brief <path>, or run the standup first." >&2
        exit 2
      fi
      _load_brief "$brief_path"
      run_verify
      ;;
  esac
}

main "$@"
