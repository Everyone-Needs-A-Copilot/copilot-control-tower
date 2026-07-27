#!/usr/bin/env bash
# admin_bootstrap.sh — the deterministic engine behind the admin-bootstrap skill.
#
# Implements docs/01-architecture/admin-standup-contract.md §6 (engine script
# obligations) and §3 (the --verify --json contract). The script, never the
# model, makes every existence/idempotency decision. Every mutation is
# check-then-act (GET before POST/PATCH/PUT); nothing is ever forced, skipped
# past, or overwritten. Dependencies: gh and jq only, plus python3 (macOS
# stock) used solely to parse the brief's YAML front matter, and
# /usr/bin/curl for the bounded shared-store reachability check.
#
# See --help for usage.

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BRIEF_SCHEMA_VERSION="1.0"
VERIFY_SCHEMA_VERSION="1.0"
ECOSYSTEM_SCHEMA_VERSION="2.0"
# The pin the script applies (admin-standup-contract.md §4/§6 — Earl chooses no
# version in v1). This must be a fully-specified caret range (^MAJOR.MINOR.PATCH)
# so it can actually be resolved against real tags; the contract's own "^5.x"
# illustration is a shape example, not valid semver (an "x" minor/patch can't be
# compared), so the script picks a concrete floor here.
# Product-specific floors ratified against the published foundations. Keeping
# these separate prevents a Claude major version from being interpreted as a
# Codex version merely because both products share one ecosystem.
FOUNDATION_CLAUDE_REF="^5.8.0"
FOUNDATION_CODEX_REF="^0.6.0"
# The public GitHub org that owns every foundation component repo
# (<component>-copilot), read over anonymous HTTPS — no credential assumptions.
FOUNDATION_ORG="Everyone-Needs-A-Copilot"
# Fixed, deterministic work-branch name for content-bearing ecosystem.yml
# changes (admin-standup-contract.md §6 step 5). Never timestamped, never
# force-pushed: the same branch is reused and fast-forwarded across re-runs so
# a second run adds no duplicate commits or pull requests.
WORK_BRANCH="copilot-standup"
DEFAULT_BRIEF_PATH="${HOME}/Library/Application Support/CopilotControlTower/standup-brief.md"

# Brief-derived state, populated by _load_brief.
ORG=""
HARNESS_LIST=()
DEPARTMENTS=()
STORE_STATUS="deferred"
STORE_TYPE=""
STORE_ENDPOINT=""
STORE_WORKSPACE_ID=""
STORE_ENVIRONMENT=""
STORE_SECRET_PATH=""
STORE_TEAM_SCOPES=()
GITHUB_OAUTH_CLIENT_ID=""
ECOSYSTEM_PACKAGE_BRANCH=""

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

  admin_bootstrap.sh --plan [--brief <path>] --json
      Read-only repository inventory. Reports every organization and
      department target before setup is allowed to create anything.

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

_b64_encode() {
  base64 | tr -d '\n'
}

# _valid_slug VALUE — true if VALUE is a GitHub-safe slug: lowercase letters,
# digits, and single hyphens between segments (no leading/trailing/double
# hyphen). The brief is contractually a list of slugs (admin-standup-contract
# §1.3) and doubles as the verify drift baseline, so the engine never
# auto-slugifies a value it was given; it refuses instead.
_valid_slug() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

# _valid_org VALUE — true if VALUE is a real GitHub org/user login: GitHub's
# actual rule is ASCII letters (either case), digits, and single hyphens,
# never leading/trailing or doubled, 1-39 characters. Unlike _valid_slug,
# uppercase IS allowed here: an org is an EXISTING GitHub identifier this
# engine must never transform (only departments are slugs this engine
# itself generates, so those alone are forced lowercase). The org's real
# case is used verbatim in every gh api path and repo full-name; it is
# never lowercased.
_valid_org() {
  local v="$1"
  [[ "$v" =~ ^[A-Za-z0-9](-?[A-Za-z0-9])*$ ]] && [[ "${#v}" -le 39 ]]
}

# GitHub has issued multiple OAuth client-id prefixes. The stable public shape
# is 20 ASCII letters/digits/dots; no client secret is accepted or needed.
_valid_github_oauth_client_id() {
  [[ "$1" =~ ^[A-Za-z0-9.]{20}$ ]]
}

_foundation_ref_for() {
  case "$1" in
    claude) printf '%s' "$FOUNDATION_CLAUDE_REF" ;;
    codex) printf '%s' "$FOUNDATION_CODEX_REF" ;;
    *) return 1 ;;
  esac
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
  # The packaged Admin app writes a machine-readable JSON twin beside the
  # human-readable Markdown brief. Prefer that path in-product so Admin has no
  # Python runtime dependency. The Markdown parser remains for source/operator
  # compatibility.
  if [[ "$brief_path" == *.json ]]; then
    jq -c . "$brief_path"
    return
  fi
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
  if ! _valid_org "$ORG"; then
    refuse "validate-slug" "That doesn't look like a GitHub organization name. Use letters, numbers, and single dashes, and update the brief."
  fi

  HARNESS_LIST=()
  while IFS= read -r h; do
    [[ -n "$h" ]] && HARNESS_LIST+=("$h")
  done < <(echo "$json" | jq -r '.harness[]? // empty')
  if [[ "${#HARNESS_LIST[@]}" -eq 0 ]]; then
    refuse "brief" "The brief at $path names no development harness, so I won't guess which spaces to create."
  fi
  local h
  for h in "${HARNESS_LIST[@]}"; do
    if [[ "$h" != "claude" && "$h" != "codex" ]]; then
      refuse "brief" "The brief names an unsupported harness, $h. Use claude, codex, or both."
    fi
  done

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
    if [[ "$dept" == "internal" ]]; then
      refuse "validate-slug" "\"internal\" is reserved for the org layer and can't be a department name. Rename that department and update the brief."
    fi
  done

  GITHUB_OAUTH_CLIENT_ID="$(echo "$json" | jq -r '.github_app.client_id // empty')"
  if [[ -z "$GITHUB_OAUTH_CLIENT_ID" ]]; then
    refuse "brief" "The brief is missing your organization's public GitHub OAuth App client ID. Add github_app.client_id; never add the client secret."
  fi
  if ! _valid_github_oauth_client_id "$GITHUB_OAUTH_CLIENT_ID"; then
    refuse "brief" "github_app.client_id doesn't look like a public GitHub OAuth client ID. Copy the 20-character Client ID from the OAuth App settings; never paste the client secret."
  fi

  STORE_STATUS="$(echo "$json" | jq -r '.store.status // "deferred"')"
  STORE_TYPE="$(echo "$json" | jq -r '.store.type // empty')"
  STORE_ENDPOINT="$(echo "$json" | jq -r '.store.endpoint // empty')"
  STORE_WORKSPACE_ID="$(echo "$json" | jq -r '.store.workspace_id // empty')"
  STORE_ENVIRONMENT="$(echo "$json" | jq -r '.store.environment // empty')"
  STORE_SECRET_PATH="$(echo "$json" | jq -r '.store.secret_path // empty')"
  if [[ "$STORE_STATUS" == "connected" && "$STORE_TYPE" == "infisical" ]]; then
    if [[ -z "$STORE_WORKSPACE_ID" || -z "$STORE_ENVIRONMENT" || "$STORE_SECRET_PATH" != /* ]]; then
      refuse "brief" "Connected Infisical setup needs store.workspace_id, store.environment, and an absolute store.secret_path such as /shared. These identifiers are not secrets."
    fi
  fi
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
    repos+=("${h}-copilot-internal")
  done
  repos+=("knowledge-copilot-internal" "cli-copilot-internal")
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
  _probe_repo "$org" "$reponame"
  case "$_REPO_PROBE_STATE" in
    existing-private)
      emit_step "$step" "already-present" "$org/$reponame already exists, private."
      return
      ;;
    conflict-public)
      refuse "$step" "$org/$reponame already exists but is public. I won't change its visibility or create over it."
      ;;
    unknown)
      refuse "$step" "I couldn't confirm whether $org/$reponame exists, so I won't guess or create it. Check GitHub access and try again."
      ;;
    missing) ;;
  esac
  if gh api -X POST "orgs/$org/repos" -f name="$reponame" -F private=true >/dev/null 2>&1; then
    emit_step "$step" "created" "Created $org/$reponame, private."
  else
    fail_step "$step" "Could not create $org/$reponame."
  fi
}

_layer_seed() {
  local product="$1" role="$2" rank="$3" owner="$4"
  printf 'schema_version: "1.0"\n'
  printf 'package:\n'
  printf '  role: %s\n' "$role"
  printf '  rank: %s\n' "$rank"
  printf '  product: %s\n' "$product"
  printf '  owner: %s\n' "$owner"
  printf 'dimensions: []\n'
}

_ensure_layer_package() {
  local org="$1" repo="$2" product="$3" role="$4" rank="$5" known_content="$6"
  local step="layer-package:$repo" content encoded branch="" info err_file
  [[ "$known_content" == "ecosystem-only" ]] && branch="$ECOSYSTEM_PACKAGE_BRANCH"
  if [[ -n "$branch" ]]; then
    err_file="$(mktemp)"
    if info="$(gh api -X GET "repos/$org/$repo/contents/copilot.layer.yml" -f ref="$branch" 2>"$err_file")"; then
      _GH_READ_STATUS="ok"
      _GH_READ_VALUE="$(echo "$info" | jq -r '.content // empty')"
    elif grep -qi 'HTTP 404' "$err_file"; then
      _GH_READ_STATUS="not-found"; _GH_READ_VALUE=""
    else
      _GH_READ_STATUS="error"; _GH_READ_VALUE=""
    fi
    rm -f "$err_file"
  else
    _gh_read "repos/$org/$repo/contents/copilot.layer.yml" '.content // empty' || true
  fi
  if [[ "$_GH_READ_STATUS" == "ok" ]]; then
    content="$(printf '%s' "$_GH_READ_VALUE" | _b64_decode)"
    if [[ "$content" == *"  role: $role"* && "$content" == *"  rank: $rank"* && "$content" == *"  product: $product"* ]]; then
      emit_step "$step" "already-present" "$org/$repo already has the expected $role layer package."
      return
    fi
    refuse "$step" "$org/$repo already has a different copilot.layer.yml. I won't reinterpret or replace it."
  fi
  if [[ "$_GH_READ_STATUS" != "not-found" ]]; then
    refuse "$step" "I couldn't confirm whether $org/$repo already has a layer package, so I won't write one. Check GitHub access and try again."
  fi

  _repo_default_branch_and_commits "$org" "$repo" "$step"
  if [[ "$_REPO_HAS_COMMITS" == "true" && "$known_content" != "ecosystem-only" ]]; then
    refuse "$step" "$org/$repo already contains unfamiliar work without a recognized layer package. I won't add or replace anything."
  fi
  if [[ "$_REPO_HAS_COMMITS" == "true" && "$known_content" == "ecosystem-only" && -z "$branch" ]]; then
    local root_names
    if ! root_names="$(gh api "repos/$org/$repo/contents" --jq '.[].name' 2>/dev/null)"; then
      refuse "$step" "I couldn't confirm the existing content in $org/$repo, so I won't add a layer package."
    fi
    if [[ "$root_names" != "ecosystem.yml" ]]; then
      refuse "$step" "$org/$repo contains work other than the known ecosystem handoff. I won't add a package directly."
    fi
  fi
  content="$(_layer_seed "$product" "$role" "$rank" "$org")"
  encoded="$(printf '%s' "$content" | _b64_encode)"
  local args=(gh api -X PUT "repos/$org/$repo/contents/copilot.layer.yml" -f message="Initialize $role Copilot layer" -f content="$encoded")
  [[ -n "$branch" ]] && args+=(-f branch="$branch")
  if "${args[@]}" >/dev/null 2>&1; then
    emit_step "$step" "created" "Initialized the $role rank-$rank package in $org/$repo."
  else
    fail_step "$step" "Could not initialize the layer package in $org/$repo. It's safe to run setup again."
  fi
}

# _probe_repo ORG REPO sets a four-state result. Only an explicit HTTP 404
# becomes "missing"; every other read failure is unknown and blocks writes.
_probe_repo() {
  local org="$1" repo="$2"
  if _gh_read "repos/$org/$repo" '.private'; then
    case "$_GH_READ_VALUE" in
      true) _REPO_PROBE_STATE="existing-private" ;;
      false) _REPO_PROBE_STATE="conflict-public" ;;
      *) _REPO_PROBE_STATE="unknown" ;;
    esac
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    _REPO_PROBE_STATE="missing"
  else
    _REPO_PROBE_STATE="unknown"
  fi
}

_repository_targets() {
  local repo unit
  while IFS= read -r repo; do printf 'org||%s\n' "$repo"; done < <(_org_triplet_repos)
  for unit in "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; do
    while IFS= read -r repo; do printf 'department|%s|%s\n' "$unit" "$repo"; done < <(_dept_triplet_repos "$unit")
  done
}

_preflight_repository_matrix() {
  local org="$1" role unit repo blocked=()
  while IFS='|' read -r role unit repo; do
    _probe_repo "$org" "$repo"
    case "$_REPO_PROBE_STATE" in
      conflict-public) blocked+=("$org/$repo is public") ;;
      unknown) blocked+=("$org/$repo is unreadable") ;;
    esac
  done < <(_repository_targets)
  if [[ "${#blocked[@]}" -gt 0 ]]; then
    refuse "repository-plan" "Repository setup is blocked: $(_join_comma "${blocked[@]}"). Nothing was created."
  fi
}

_preflight_layer_packages() {
  local org="$1" product repo unit rank expected_role first_repo="${HARNESS_LIST[0]}-copilot-internal"
  local content root_names ecosystem_present
  for product in "${HARNESS_LIST[@]}"; do
    for unit in organization ${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}; do
      if [[ "$unit" == "organization" ]]; then
        repo="${product}-copilot-internal"; rank="30"; expected_role="organization"
      else
        repo="${product}-copilot-${unit}"; rank="20"; expected_role="department"
      fi
      _probe_repo "$org" "$repo"
      case "$_REPO_PROBE_STATE" in
        existing-private) ;;
        missing) continue ;;
        conflict-public)
          refuse "repository-plan" "$org/$repo is public. Nothing was created."
          ;;
        unknown)
          refuse "repository-plan" "I couldn't inspect $org/$repo before checking its layer package. Nothing was created."
          ;;
      esac
      if _gh_read "repos/$org/$repo/contents/copilot.layer.yml" '.content // empty'; then
        content="$(printf '%s' "$_GH_READ_VALUE" | _b64_decode)"
        if [[ "$content" != *"  product: $product"* || "$content" != *"  role: $expected_role"* || "$content" != *"  rank: $rank"* ]]; then
          refuse "repository-plan" "$org/$repo has a different layer package. Nothing was created."
        fi
        continue
      elif [[ "$_GH_READ_STATUS" != "not-found" ]]; then
        refuse "repository-plan" "I couldn't inspect $org/$repo's layer package. Nothing was created."
      fi
      _repo_default_branch_and_commits "$org" "$repo" "repository-plan"
      [[ "$_REPO_HAS_COMMITS" == "true" ]] || continue
      if [[ "$repo" != "$first_repo" ]]; then
        refuse "repository-plan" "$org/$repo contains unfamiliar work without a layer package. Nothing was created."
      fi
      ecosystem_present=false
      if _gh_read "repos/$org/$repo/contents/ecosystem.yml" '.content // empty'; then
        ecosystem_present=true
      elif [[ "$_GH_READ_STATUS" != "not-found" ]]; then
        refuse "repository-plan" "I couldn't inspect $org/$repo's organization handoff. Nothing was created."
      fi
      if $ecosystem_present; then
        if ! root_names="$(gh api "repos/$org/$repo/contents" --jq '.[].name' 2>/dev/null)"; then
          refuse "repository-plan" "I couldn't inspect the existing files in $org/$repo. Nothing was created."
        fi
        if [[ "$root_names" != "ecosystem.yml" ]]; then
          refuse "repository-plan" "$org/$repo contains unfamiliar work without a layer package. Nothing was created."
        fi
      fi
    done
  done
}

run_repository_plan() {
  local org="$1" role unit repo component action visibility detail rows result
  rows="$(mktemp)"
  while IFS='|' read -r role unit repo; do
    _probe_repo "$org" "$repo"
    component="${repo%%-copilot-*}"
    action="blocked"; visibility=""; detail="GitHub could not confirm whether this repository exists."
    case "$_REPO_PROBE_STATE" in
      existing-private) action="none"; visibility="private"; detail="Existing private repository will be reused." ;;
      missing) action="create"; detail="Repository does not exist and can be created privately." ;;
      conflict-public) visibility="public"; detail="A public repository already uses this name." ;;
    esac
    jq -nc --arg component "$component" --arg role "$role" --arg unit "$unit" \
      --arg owner "$org" --arg name "$repo" --arg visibility "$visibility" \
      --arg state "$_REPO_PROBE_STATE" --arg action "$action" --arg detail "$detail" \
      '{component:$component,role:$role,unit:(if $unit=="" then null else $unit end),owner:$owner,name:$name,visibility:(if $visibility=="" then null else $visibility end),state:$state,action:$action,detail:$detail}' >> "$rows"
  done < <(_repository_targets)
  if jq -e 'select(.action=="blocked")' "$rows" >/dev/null; then result="blocked"
  elif jq -e 'select(.state=="missing")' "$rows" >/dev/null; then result="changes-required"
  else result="ready"; fi
  jq -s --arg owner "$org" --arg result "$result" '{schema_version:"1.0",scope:"organization",owner:$owner,mode:"plan",result:$result,repositories:.,summary:{existing:(map(select(.state=="existing-private"))|length),missing:(map(select(.state=="missing"))|length),created:0,blocked:(map(select(.action=="blocked"))|length)}}' "$rows"
  rm -f "$rows"
  [[ "$result" != "blocked" ]]
}

_ensure_branch_protection() {
  local org="$1" reponame="$2" step="$3" default_branch existing reviews_required admin_enforced

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
  if _gh_read "repos/$org/$reponame/branches/$default_branch/protection" \
      '{required_reviews:(.required_pull_request_reviews.required_approving_review_count // 0),enforce_admins:(.enforce_admins.enabled // false)}'; then
    existing="$_GH_READ_VALUE"
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    existing=""
  else
    fail_step "$step" "Could not check branch protection on $org/$reponame, so I won't guess. It's safe to run this again."
  fi
  if [[ -n "$existing" ]]; then
    reviews_required="$(printf '%s' "$existing" | jq -r '.required_reviews // empty')"
    admin_enforced="$(printf '%s' "$existing" | jq -r '.enforce_admins | if type == "boolean" then tostring else empty end')"
    if ! [[ "$reviews_required" =~ ^[0-9]+$ ]] \
      || [[ "$admin_enforced" != "true" && "$admin_enforced" != "false" ]]; then
      fail_step "$step" "GitHub returned unreadable branch protection for $org/$reponame, so I won't guess. It's safe to run this again."
      return
    fi
    if [[ "$reviews_required" -ge 1 ]]; then
      if [[ "$admin_enforced" == "true" ]]; then
        # A required review that also applies to administrators deadlocks a
        # solo-admin organization: GitHub does not allow an author to approve
        # their own pull request. Remove only administrator enforcement; the
        # review rule remains intact for every non-administrator.
        if gh api -X DELETE "repos/$org/$reponame/branches/$default_branch/protection/enforce_admins" >/dev/null 2>&1; then
          emit_step "$step" "updated" "Kept required review on $org/$reponame and restored administrator recovery access."
        else
          fail_step "$step" "Could not restore administrator recovery access on $org/$reponame. The review rule is unchanged."
        fi
        return
      fi
      emit_step "$step" "already-present" "$org/$reponame requires review for non-administrators and preserves administrator recovery access."
      return
    fi
  fi

  local protect_err
  protect_err="$(mktemp)"
  if echo '{"required_pull_request_reviews":{"required_approving_review_count":1},"enforce_admins":false,"required_status_checks":null,"restrictions":null}' \
    | gh api -X PUT "repos/$org/$reponame/branches/$default_branch/protection" --input - >/dev/null 2>"$protect_err"; then
    rm -f "$protect_err"
    emit_step "$step" "updated" "Set $org/$reponame to require review before merge for non-administrators."
    return
  fi

  # Detected on HTTP status alone, never on GitHub's error message text: by
  # this point preflight already confirmed the actor is an org owner with
  # admin:org + repo, so a 403 specifically on the branch-protection endpoint
  # is overwhelmingly the free-plan limitation (protection on private repos
  # is a paid-only feature), not a permissions gap of ours; matching an exact
  # message string would be brittle since GitHub rewords those over time.
  if grep -qi 'HTTP 403' "$protect_err" 2>/dev/null; then
    rm -f "$protect_err"
    emit_step "$step" "skipped" "Review protection needs a paid GitHub plan for private repositories. Your spaces are set up. Upgrade the plan and run setup again to add it."
    return
  fi

  rm -f "$protect_err"
  fail_step "$step" "Could not set branch protection on $org/$reponame."
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
  # check exists to detect); any other failure is a genuine error. GitHub's
  # successful "check team permissions for a repository" response is normally
  # HTTP 204 with no body, so an empty filtered value is positive proof here,
  # not a missing permission.
  if _gh_read "orgs/$org/teams/$unit/repos/$org/$reponame" '.permissions.push // false'; then
    case "$_GH_READ_VALUE" in
      ""|true) current="true" ;;
      false) current="false" ;;
      *)
        fail_step "$step" "GitHub returned an unreadable team permission for $org/$reponame, so I won't guess. It's safe to run this again."
        return
        ;;
    esac
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    current="false"
  else
    fail_step "$step" "Could not check whether the $unit team can already reach $org/$reponame, so I won't guess. It's safe to run this again."
    return
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
    case "$_GH_READ_VALUE" in
      # GitHub normally answers this endpoint with HTTP 204 and no body when
      # the team has access. The JSON true shape is retained for compatible
      # GitHub deployments and test fixtures.
      ""|true)
        _TEAM_CHECK_STATUS="checked"
        return 0
        ;;
      false)
        _TEAM_CHECK_STATUS="checked"
        return 1
        ;;
      *)
        _TEAM_CHECK_STATUS="error"
        return 1
        ;;
    esac
  fi
  if [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    _TEAM_CHECK_STATUS="checked"
    return 1
  fi
  _TEAM_CHECK_STATUS="error"
  return 1
}

# ---------------------------------------------------------------------------
# Semver caret-range resolution (foundation pin, admin-standup-contract.md §3/§6)
# ---------------------------------------------------------------------------
#
# Accepted tag shapes: "vX.Y.Z" or "X.Y.Z" (three numeric components, no
# pre-release/build suffix). Any other tag (a pre-release like "v5.13.0-rc1",
# a moving alias like "latest", a two-part "v5.13") is silently skipped when
# scanning for the highest match — it never crashes the scan and never counts
# as a candidate, since a caret range's contract only reasons about exact
# X.Y.Z triplets.
#
# Caret-range semantics (the npm/semver definition): ^X.Y.Z allows any version
# >= X.Y.Z that does not change the *first nonzero* component: for X > 0 that
# is <(X+1).0.0; for X == 0, Y > 0 that is <0.(Y+1).0; for X == Y == 0 that is
# <0.0.(Z+1). Every foundation pin the script applies has X > 0 in practice,
# but the zero-major cases are implemented too, for correctness.

# _parse_version_tag TAG — sets _V_MAJOR/_V_MINOR/_V_PATCH if TAG is exactly
# "vX.Y.Z" or "X.Y.Z"; returns 1 (leaving them unset) for anything else.
_parse_version_tag() {
  local raw="$1" v
  v="${raw#v}"
  if [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    _V_MAJOR="${BASH_REMATCH[1]}"
    _V_MINOR="${BASH_REMATCH[2]}"
    _V_PATCH="${BASH_REMATCH[3]}"
    return 0
  fi
  return 1
}

# _version_key MAJOR MINOR PATCH — a zero-padded, lexicographically-sortable
# key so plain bash string comparison (`<`/`>` inside [[ ]]) behaves as
# numeric comparison, without needing bc/awk for version math.
_version_key() {
  printf '%05d%05d%05d' "$1" "$2" "$3"
}

# _caret_range_bounds RANGE — parses a "^X.Y.Z" range into inclusive-min /
# exclusive-max keys (_RANGE_MIN_KEY, _RANGE_MAX_KEY). Returns 1 for anything
# that isn't a well-formed caret range over an X.Y.Z triplet.
_caret_range_bounds() {
  local range="$1" body maj min pat
  [[ "$range" == \^* ]] || return 1
  body="${range#^}"
  [[ "$body" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
  maj="${BASH_REMATCH[1]}"; min="${BASH_REMATCH[2]}"; pat="${BASH_REMATCH[3]}"
  _RANGE_MIN_KEY="$(_version_key "$maj" "$min" "$pat")"
  if [[ "$maj" != "0" ]]; then
    _RANGE_MAX_KEY="$(_version_key "$((maj + 1))" 0 0)"
  elif [[ "$min" != "0" ]]; then
    _RANGE_MAX_KEY="$(_version_key 0 "$((min + 1))" 0)"
  else
    _RANGE_MAX_KEY="$(_version_key 0 0 "$((pat + 1))")"
  fi
  return 0
}

# _resolve_foundation_pin REPO RANGE — resolves RANGE against REPO's tags in
# $FOUNDATION_ORG (anonymous HTTPS, public repo, no credential assumptions).
# Sets _RESOLVE_STATUS to one of:
#   "ok"       — _RESOLVED_TAG is the highest tag satisfying RANGE.
#   "no-match" — tags were read fine, but none satisfy RANGE.
#   "unreadable" — the tags read itself failed (network/API error); never
#                  treated as "no-match" — see the fail-closed rule (§3.2).
#   "bad-range"  — RANGE itself isn't a caret range this script understands.
_resolve_foundation_pin() {
  local repo="$1" range="$2" names name best_key="" best_tag=""

  if ! _caret_range_bounds "$range"; then
    _RESOLVE_STATUS="bad-range"
    return 1
  fi

  local err_file
  err_file="$(mktemp)"
  if ! names="$(gh api "repos/$FOUNDATION_ORG/$repo/tags" --paginate --jq '.[].name' 2>"$err_file")"; then
    rm -f "$err_file"
    _RESOLVE_STATUS="unreadable"
    return 1
  fi
  rm -f "$err_file"

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if _parse_version_tag "$name"; then
      local key
      key="$(_version_key "$_V_MAJOR" "$_V_MINOR" "$_V_PATCH")"
      if [[ "$key" > "$_RANGE_MIN_KEY" || "$key" == "$_RANGE_MIN_KEY" ]] && [[ "$key" < "$_RANGE_MAX_KEY" ]]; then
        if [[ -z "$best_key" || "$key" > "$best_key" ]]; then
          best_key="$key"
          best_tag="$name"
        fi
      fi
    fi
  done <<< "$names"

  if [[ -z "$best_tag" ]]; then
    _RESOLVE_STATUS="no-match"
    return 1
  fi
  _RESOLVE_STATUS="ok"
  _RESOLVED_TAG="$best_tag"
  return 0
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
_STATE_STORE_WORKSPACE_ID=""
_STATE_STORE_ENVIRONMENT=""
_STATE_STORE_SECRET_PATH=""
_STATE_STORE_SCOPES=()
_STATE_GITHUB_CLIENT_ID=""
_STATE_FOUNDATION_LEGACY_REF=""
_STATE_FOUNDATION_CLAUDE_REF=""
_STATE_FOUNDATION_CODEX_REF=""
_STATE_PERSONAL_OWNER=""
_STATE_PERSONAL_RANK=""
_STATE_PERSONAL_REPOSITORY_PATTERN=""

_yaml_unquote() {
  local value="$1"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value#\"}"
    value="${value%\"}"
  fi
  printf '%s' "$value"
}

_read_ecosystem_state() {
  local content="$1"
  _STATE_HARNESS=()
  _STATE_DEPT_UNITS=()
  _STATE_STORE_STATUS=""
  _STATE_STORE_TYPE=""
  _STATE_STORE_ENDPOINT=""
  _STATE_STORE_WORKSPACE_ID=""
  _STATE_STORE_ENVIRONMENT=""
  _STATE_STORE_SECRET_PATH=""
  _STATE_STORE_SCOPES=()
  _STATE_GITHUB_CLIENT_ID=""
  _STATE_FOUNDATION_LEGACY_REF=""
  _STATE_FOUNDATION_CLAUDE_REF=""
  _STATE_FOUNDATION_CODEX_REF=""
  _STATE_PERSONAL_OWNER=""
  _STATE_PERSONAL_RANK=""
  _STATE_PERSONAL_REPOSITORY_PATTERN=""

  local section="" line trimmed
  while IFS= read -r line; do
    case "$line" in
      "harness:") section="harness"; continue ;;
      "components:") section="components"; continue ;;
      "departments:") section="departments"; continue ;;
      "store:") section="store"; continue ;;
      "github_app:") section="github-app"; continue ;;
      "foundation:") section="foundation"; continue ;;
      "personal:") section="personal"; continue ;;
      "  refs:")
        [[ "$section" == "foundation" ]] && section="foundation-refs"
        continue
        ;;
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
      "  workspace_id: "*)
        [[ "$section" == "store" ]] && _STATE_STORE_WORKSPACE_ID="$(_yaml_unquote "${line#  workspace_id: }")"
        ;;
      "  environment: "*)
        [[ "$section" == "store" ]] && _STATE_STORE_ENVIRONMENT="${line#  environment: }"
        ;;
      "  secret_path: "*)
        [[ "$section" == "store" ]] && _STATE_STORE_SECRET_PATH="$(_yaml_unquote "${line#  secret_path: }")"
        ;;
      "  client_id: "*)
        [[ "$section" == "github-app" ]] && _STATE_GITHUB_CLIENT_ID="$(_yaml_unquote "${line#  client_id: }")"
        ;;
      "  ref: "*)
        [[ "$section" == "foundation" ]] && _STATE_FOUNDATION_LEGACY_REF="$(_yaml_unquote "${line#  ref: }")"
        ;;
      "    claude: "*)
        [[ "$section" == "foundation-refs" ]] && _STATE_FOUNDATION_CLAUDE_REF="$(_yaml_unquote "${line#    claude: }")"
        ;;
      "    codex: "*)
        [[ "$section" == "foundation-refs" ]] && _STATE_FOUNDATION_CODEX_REF="$(_yaml_unquote "${line#    codex: }")"
        ;;
      "  owner: "*)
        [[ "$section" == "personal" ]] && _STATE_PERSONAL_OWNER="${line#  owner: }"
        ;;
      "  rank: "*)
        [[ "$section" == "personal" ]] && _STATE_PERSONAL_RANK="${line#  rank: }"
        ;;
      "  repository_pattern: "*)
        [[ "$section" == "personal" ]] && _STATE_PERSONAL_REPOSITORY_PATTERN="$(_yaml_unquote "${line#  repository_pattern: }")"
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
MERGE_STORE_WORKSPACE_ID=""
MERGE_STORE_ENVIRONMENT=""
MERGE_STORE_SECRET_PATH=""
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
    printf '  workspace_id: "%s"\n' "$MERGE_STORE_WORKSPACE_ID"
    printf '  environment: %s\n' "$MERGE_STORE_ENVIRONMENT"
    printf '  secret_path: "%s"\n' "$MERGE_STORE_SECRET_PATH"
    printf '  team_scopes:\n'
    for s in "${MERGE_STORE_SCOPES[@]+"${MERGE_STORE_SCOPES[@]}"}"; do
      printf '    - %s\n' "$s"
    done
  else
  printf '  status: deferred\n'
  fi
  printf 'github_app:\n'
  printf '  client_id: "%s"\n' "$GITHUB_OAUTH_CLIENT_ID"
  printf 'foundation:\n'
  printf '  refs:\n'
  for h in "${MERGE_HARNESS[@]}"; do
    printf '    %s: "%s"\n' "$h" "$(_foundation_ref_for "$h")"
  done
  printf 'personal:\n'
  printf '  owner: user\n'
  printf '  rank: 10\n'
  printf '  repository_pattern: "<user>/<component>-copilot-private"\n'
}

_assert_existing_ecosystem_compatible() {
  local org="$1" target_repo="$2" content="$3" h existing_ref desired_ref
  _read_ecosystem_state "$content"
  if [[ -n "$_STATE_GITHUB_CLIENT_ID" && "$_STATE_GITHUB_CLIENT_ID" != "$GITHUB_OAUTH_CLIENT_ID" ]]; then
    refuse "ecosystem-yml" "$org/$target_repo already carries a different github_app.client_id. I won't replace organization identity config. Confirm the OAuth App and update it through review."
  fi
  if [[ -n "$_STATE_FOUNDATION_LEGACY_REF" ]]; then
    refuse "ecosystem-yml" "$org/$target_repo still uses the legacy single foundation.ref. I won't reinterpret it across Claude and Codex. Migrate it through review to product-specific foundation.refs first."
  fi
  if [[ -n "$_STATE_PERSONAL_OWNER" && "$_STATE_PERSONAL_OWNER" != "user" ]] \
    || [[ -n "$_STATE_PERSONAL_RANK" && "$_STATE_PERSONAL_RANK" != "10" ]] \
    || [[ -n "$_STATE_PERSONAL_REPOSITORY_PATTERN" && "$_STATE_PERSONAL_REPOSITORY_PATTERN" != "<user>/<component>-copilot-private" ]]; then
    refuse "ecosystem-yml" "$org/$target_repo carries a different personal handoff contract. I won't rewrite personal ownership or repository naming automatically."
  fi
  for h in "${HARNESS_LIST[@]}"; do
    desired_ref="$(_foundation_ref_for "$h")"
    case "$h" in
      claude) existing_ref="$_STATE_FOUNDATION_CLAUDE_REF" ;;
      codex) existing_ref="$_STATE_FOUNDATION_CODEX_REF" ;;
    esac
    if [[ -n "$existing_ref" && "$existing_ref" != "$desired_ref" ]]; then
      refuse "ecosystem-yml" "$org/$target_repo already pins $h to $existing_ref, not $desired_ref. I won't change a foundation pin without review."
    fi
  done
}

_preflight_ecosystem_contract() {
  local org="$1" target_repo="${HARNESS_LIST[0]}-copilot-internal" info content err_file
  err_file="$(mktemp)"
  if info="$(gh api "repos/$org/$target_repo/contents/ecosystem.yml" 2>"$err_file")"; then
    rm -f "$err_file"
    content="$(printf '%s' "$(echo "$info" | jq -r '.content')" | _b64_decode)"
    [[ -n "$content" ]] || refuse "ecosystem-yml" "I couldn't decode $org/$target_repo's existing ecosystem.yml, so I won't mutate organization setup."
    _assert_existing_ecosystem_compatible "$org" "$target_repo" "$content"
    return
  fi
  if grep -qi 'HTTP 404' "$err_file" 2>/dev/null; then
    rm -f "$err_file"
    return
  fi
  rm -f "$err_file"
  refuse "ecosystem-yml" "I couldn't read $org/$target_repo's existing ecosystem.yml, so I won't mutate organization setup."
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

_repo_default_branch_and_commits() {
  # Sets _DEFAULT_BRANCH and _REPO_HAS_COMMITS ("true"/"false"). Calls
  # fail_step (never returns) on a genuine read error — by this point in
  # either orchestration path the repo has already been confirmed to exist,
  # so a failure here is never a legitimate "doesn't exist yet".
  local org="$1" repo="$2" step="$3"
  if _gh_read "repos/$org/$repo" '.default_branch // empty'; then
    _DEFAULT_BRANCH="$_GH_READ_VALUE"
  else
    fail_step "$step" "Could not read $org/$repo, so I won't guess whether it has content yet. It's safe to run this again."
  fi
  _REPO_HAS_COMMITS="false"
  if [[ -n "$_DEFAULT_BRANCH" ]]; then
    if _gh_read "repos/$org/$repo/branches/$_DEFAULT_BRANCH" '.name // empty'; then
      _REPO_HAS_COMMITS="true"
    elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
      _REPO_HAS_COMMITS="false"
    else
      fail_step "$step" "Could not check whether $org/$repo has any commits yet, so I won't guess. It's safe to run this again."
    fi
  fi
}

# _find_pr ORG REPO BRANCH BASE — checks for an open pull request from BRANCH
# into BASE. Sets _PR_NUMBER (empty if none found; only meaningful when this
# returns 0). Returns 1 on a genuine read error (never collapsed into "none
# found" — see _gh_read's rationale).
_find_pr() {
  local org="$1" repo="$2" branch="$3" base="$4" out err_file rc
  err_file="$(mktemp)"
  if out="$(gh api -X GET "repos/$org/$repo/pulls" -f head="$org:$branch" -f base="$base" -f state=open --jq '.[0].number // empty' 2>"$err_file")"; then
    _PR_NUMBER="$out"
    rc=0
  else
    _PR_NUMBER=""
    rc=1
  fi
  rm -f "$err_file"
  return $rc
}

# _ensure_ecosystem_pr ORG REPO BASE NEW_CONTENT STEP — the content-bearing-
# repo path (admin-standup-contract.md §6 step 5): land NEW_CONTENT on the
# fixed work branch (never a direct push to BASE) and open a PR to BASE.
# Idempotent: a same-content re-run pushes no duplicate commit and opens no
# duplicate PR (never-destroy #3, applied to branches and pull requests).
_ensure_ecosystem_pr() {
  local org="$1" repo="$2" base="$3" new_content="$4" step="$5"
  local branch="$WORK_BRANCH" branch_exists="false"

  if _gh_read "repos/$org/$repo/branches/$branch" '.name // empty'; then
    branch_exists="true"
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    branch_exists="false"
  else
    fail_step "$step" "Could not check whether $org/$repo already has a $branch branch, so I won't guess. It's safe to run this again."
  fi

  if [[ "$branch_exists" == "false" ]]; then
    local base_sha
    if _gh_read "repos/$org/$repo/branches/$base" '.commit.sha // empty'; then
      base_sha="$_GH_READ_VALUE"
    else
      fail_step "$step" "Could not read $org/$repo's $base branch, so I won't guess. It's safe to run this again."
    fi
    if ! gh api -X POST "repos/$org/$repo/git/refs" -f ref="refs/heads/$branch" -f sha="$base_sha" >/dev/null 2>&1; then
      fail_step "$step" "Could not create the $branch branch on $org/$repo."
    fi
  fi

  local branch_get="" branch_sha="" branch_content="" pushed_update="false"
  if branch_get="$(gh api -X GET "repos/$org/$repo/contents/ecosystem.yml" -f ref="$branch" 2>/dev/null)"; then
    branch_sha="$(echo "$branch_get" | jq -r '.sha')"
    branch_content="$(printf '%s' "$(echo "$branch_get" | jq -r '.content')" | _b64_decode)"
  fi

  if [[ "$branch_content" != "$new_content" ]]; then
    local encoded
    encoded="$(printf '%s' "$new_content" | base64 | tr -d '\n')"
    if [[ -n "$branch_sha" ]]; then
      if ! gh api -X PUT "repos/$org/$repo/contents/ecosystem.yml" -f message="Update ecosystem.yml" -f content="$encoded" -f branch="$branch" -f sha="$branch_sha" >/dev/null 2>&1; then
        fail_step "$step" "Could not push ecosystem.yml to $org/$repo's $branch branch."
      fi
    else
      if ! gh api -X PUT "repos/$org/$repo/contents/ecosystem.yml" -f message="Update ecosystem.yml" -f content="$encoded" -f branch="$branch" >/dev/null 2>&1; then
        fail_step "$step" "Could not push ecosystem.yml to $org/$repo's $branch branch."
      fi
    fi
    pushed_update="true"
  fi

  if ! _find_pr "$org" "$repo" "$branch" "$base"; then
    fail_step "$step" "Could not check for an existing pull request on $org/$repo, so I won't guess. It's safe to run this again."
  fi

  if [[ -n "$_PR_NUMBER" ]]; then
    if [[ "$pushed_update" == "true" ]]; then
      # A real commit just landed on the branch (stale content caught up to
      # a new desired state) — narrate `updated`, not `already-present`,
      # so the stream never claims nothing happened when something did.
      emit_step "$step" "updated" "Pushed new ecosystem.yml changes to $org/$repo's open pull request (#$_PR_NUMBER). Review and merge it when ready."
    else
      emit_step "$step" "already-present" "$org/$repo already has an open pull request (#$_PR_NUMBER) updating ecosystem.yml. Review and merge it when ready."
    fi
    return
  fi

  local pr_out
  if pr_out="$(gh api -X POST "repos/$org/$repo/pulls" -f title="Update ecosystem.yml" -f head="$branch" -f base="$base" -f body="Additive ecosystem.yml changes from the admin standup. Never merged automatically: review and merge when ready." 2>/dev/null)"; then
    local pr_number
    pr_number="$(echo "$pr_out" | jq -r '.number')"
    emit_step "$step" "created" "Opened pull request #$pr_number to update $org/$repo's ecosystem.yml. Review and merge it when ready."
  else
    fail_step "$step" "Could not open a pull request to update $org/$repo's ecosystem.yml."
  fi
}

_write_ecosystem_yml() {
  local org="$1"
  local target_repo="${HARNESS_LIST[0]}-copilot-internal"
  local step="ecosystem-yml"
  local sha="" existing_content=""

  # Empty repo vs. content-bearing repo is a distinct question from "does
  # ecosystem.yml exist yet" — a repo can carry other content (a README, a
  # prior manual commit) with no ecosystem.yml at all. This is the fork the
  # contract's step 5 hinges on: an empty repo gets the initial-commit path
  # unchanged; a content-bearing repo never gets a direct push, PR or not.
  _repo_default_branch_and_commits "$org" "$target_repo" "$step"
  local default_branch="$_DEFAULT_BRANCH" repo_has_commits="$_REPO_HAS_COMMITS"
  ECOSYSTEM_PACKAGE_BRANCH=""

  local get_out
  if get_out="$(gh api "repos/$org/$target_repo/contents/ecosystem.yml" 2>/dev/null)"; then
    sha="$(echo "$get_out" | jq -r '.sha')"
    existing_content="$(printf '%s' "$(echo "$get_out" | jq -r '.content')" | _b64_decode)"
  fi

  MERGE_HARNESS=()
  MERGE_DEPTS=()
  MERGE_STORE_STATUS="$STORE_STATUS"
  MERGE_STORE_TYPE="$STORE_TYPE"
  MERGE_STORE_ENDPOINT="$STORE_ENDPOINT"
  MERGE_STORE_WORKSPACE_ID="$STORE_WORKSPACE_ID"
  MERGE_STORE_ENVIRONMENT="$STORE_ENVIRONMENT"
  MERGE_STORE_SECRET_PATH="$STORE_SECRET_PATH"
  MERGE_STORE_SCOPES=("${STORE_TEAM_SCOPES[@]+"${STORE_TEAM_SCOPES[@]}"}")

  if [[ -n "$existing_content" ]]; then
    _assert_existing_ecosystem_compatible "$org" "$target_repo" "$existing_content"
    MERGE_HARNESS=("${_STATE_HARNESS[@]+"${_STATE_HARNESS[@]}"}")
    MERGE_DEPTS=("${_STATE_DEPT_UNITS[@]+"${_STATE_DEPT_UNITS[@]}"}")
    if [[ "$_STATE_STORE_STATUS" == "connected" ]]; then
      MERGE_STORE_STATUS="connected"
      MERGE_STORE_TYPE="$_STATE_STORE_TYPE"
      MERGE_STORE_ENDPOINT="$_STATE_STORE_ENDPOINT"
      MERGE_STORE_WORKSPACE_ID="$_STATE_STORE_WORKSPACE_ID"
      MERGE_STORE_ENVIRONMENT="$_STATE_STORE_ENVIRONMENT"
      MERGE_STORE_SECRET_PATH="$_STATE_STORE_SECRET_PATH"
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

  # The leak-scan runs before ANY push — direct or branch — per the contract's
  # fail-closed rule (#6): this is the single gate both paths below share.
  if ! _leak_scan "$new_content"; then
    refuse "leak-scan" "ecosystem.yml would have carried a secret-shaped value, so I stopped before pushing anything. Remove the secret and use a store reference instead."
  fi

  if [[ "$repo_has_commits" == "false" ]]; then
    # Empty repo: unchanged initial-commit-then-protect path (there is no
    # default branch/CODEOWNERS to PR against yet; admin-agentic-setup.md §5
    # open decision 4). This never happens once the repo carries content.
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
    return
  fi

  # Content-bearing repo: never a direct push. Land the change on the fixed
  # work branch and open a PR to the default branch instead — merging is a
  # human review act this engine never performs itself.
  ECOSYSTEM_PACKAGE_BRANCH="$WORK_BRANCH"
  _ensure_ecosystem_pr "$org" "$target_repo" "$default_branch" "$new_content" "$step"
}

# ---------------------------------------------------------------------------
# The public copilot-bootstrap repo (org-question copy spec §1/Appendix E.2)
#
# Sign-in needs the organization's GitHub App client id. Today that comes
# from the PRIVATE ecosystem.yml this engine already writes above, which a
# signed-out Mac cannot read at all. `<org>/copilot-bootstrap`'s
# `bootstrap.yml` is the public mirror of exactly the two non-secret fields a
# genuinely fresh Mac needs before it has any credential: `org` and
# `github_app.client_id`. Neither is a secret — GitHub publishes an
# organization's name and a GitHub App's Client ID; only the App's client
# SECRET is sensitive, and that never reaches this file (guarded below).
# ---------------------------------------------------------------------------

_render_bootstrap_yml() {
  local org="$1" client_id="$2"
  printf 'org: "%s"\n' "$org"
  printf 'github_app:\n'
  printf '  client_id: "%s"\n' "$client_id"
}

# _ensure_public_bootstrap_repo ORG — creates (or confirms) a PUBLIC
# <org>/copilot-bootstrap repository. Public, not private: this is the one
# repository in the whole engine that MUST be public, because it exists so a
# signed-out Mac can read it with no credential at all.
_ensure_public_bootstrap_repo() {
  local org="$1" step="bootstrap-repo"
  _probe_repo "$org" "copilot-bootstrap"
  case "$_REPO_PROBE_STATE" in
    conflict-public)
      # `_probe_repo`'s "conflict-public" is every other repo's UNWANTED
      # state (they must be private); it is this one repo's WANTED state.
      emit_step "$step" "already-present" "$org/copilot-bootstrap already exists, public."
      return
      ;;
    existing-private)
      refuse "$step" "$org/copilot-bootstrap already exists but is private. It must stay public so a signed-out Mac can read it before it has any credential; I won't change its visibility myself."
      ;;
    unknown)
      refuse "$step" "I couldn't confirm whether $org/copilot-bootstrap exists, so I won't guess or create it. Check GitHub access and try again."
      ;;
    missing) ;;
  esac
  if gh api -X POST "orgs/$org/repos" -f name="copilot-bootstrap" -F private=false >/dev/null 2>&1; then
    emit_step "$step" "created" "Created $org/copilot-bootstrap, public."
  else
    fail_step "$step" "Could not create $org/copilot-bootstrap."
  fi
}

# _ensure_bootstrap_yml ORG — writes (or confirms) bootstrap.yml at the root
# of <org>/copilot-bootstrap. Unlike ecosystem.yml this file is ENTIRELY
# engine-rendered from exactly two fields and never hand-edited, so an
# update overwrites directly rather than opening a PR for review — but only
# once the existing content is confirmed to carry nothing else. That check
# is the guard: nothing but `org` and `github_app.client_id` can ever be
# written here, so this never drifts into a general-purpose config surface.
_ensure_bootstrap_yml() {
  local org="$1" step="bootstrap-yml" rendered existing_content existing_sha info err_file encoded foreign_lines

  rendered="$(_render_bootstrap_yml "$org" "$GITHUB_OAUTH_CLIENT_ID")"
  if ! _leak_scan "$rendered"; then
    refuse "leak-scan" "bootstrap.yml would have carried a secret-shaped value, so I stopped before pushing anything. This file only ever carries org and github_app.client_id."
  fi

  err_file="$(mktemp)"
  if info="$(gh api "repos/$org/copilot-bootstrap/contents/bootstrap.yml" 2>"$err_file")"; then
    rm -f "$err_file"
    existing_content="$(printf '%s' "$info" | jq -r '.content // empty' | _b64_decode)"
    existing_sha="$(printf '%s' "$info" | jq -r '.sha // empty')"
    if [[ "$existing_content" == "$rendered" ]]; then
      emit_step "$step" "already-present" "$org/copilot-bootstrap already carries the current organization name and sign-in ID."
      return
    fi
    foreign_lines="$(printf '%s\n' "$existing_content" | grep -Ev '^(org: |github_app:$|  client_id: )' || true)"
    if [[ -n "$foreign_lines" ]]; then
      refuse "$step" "$org/copilot-bootstrap's bootstrap.yml carries fields I didn't write. I won't overwrite it."
    fi
    encoded="$(printf '%s' "$rendered" | _b64_encode)"
    if gh api -X PUT "repos/$org/copilot-bootstrap/contents/bootstrap.yml" \
        -f message="Update organization name and sign-in ID" -f content="$encoded" -f sha="$existing_sha" >/dev/null 2>&1; then
      emit_step "$step" "updated" "Updated $org/copilot-bootstrap's bootstrap.yml with the current organization name and sign-in ID."
    else
      fail_step "$step" "Could not update $org/copilot-bootstrap's bootstrap.yml."
    fi
    return
  fi
  if grep -qi 'HTTP 404' "$err_file" 2>/dev/null; then
    rm -f "$err_file"
    encoded="$(printf '%s' "$rendered" | _b64_encode)"
    if gh api -X PUT "repos/$org/copilot-bootstrap/contents/bootstrap.yml" \
        -f message="Initialize organization name and sign-in ID" -f content="$encoded" >/dev/null 2>&1; then
      emit_step "$step" "created" "Wrote $org/copilot-bootstrap's bootstrap.yml with the organization name and sign-in ID."
    else
      fail_step "$step" "Could not write $org/copilot-bootstrap's bootstrap.yml."
    fi
    return
  fi
  rm -f "$err_file"
  refuse "$step" "I couldn't confirm whether $org/copilot-bootstrap already has a bootstrap.yml, so I won't write one. Check GitHub access and try again."
}

# ---------------------------------------------------------------------------
# The local sign-in pointer (org-question copy spec §5, "the better fix, one
# layer up") — setting github_app.org on THIS Mac the moment standup runs
# here means Control Tower's own `cc auth login` never returns
# `org-required` on the admin's own Mac at all, and its silent
# standup-brief retry (`WizardModel.handleOrgRequired`) becomes a recovery
# path only, for a Mac whose standup predates this step.
#
# Best-effort and NEVER fatal: unlike gh/jq/python3, `cc` is not one of this
# script's declared dependencies, and it may genuinely not be installed yet
# at the point standup runs on a given Mac. A missing or failing `cc`
# degrades to "skipped" — it must never block or fail a run that has already
# created real, wanted state on GitHub.
# ---------------------------------------------------------------------------

_ensure_local_org_pointer() {
  local org="$1" step="local-org-pointer" cc_bin current
  # Resolved via PATH (`command -v`), deliberately never a hardcoded
  # absolute path: this is the SAME seam `scripts/tests/test_admin_bootstrap.sh`
  # already uses to keep every `gh` call inside this script sandboxed to its
  # own mock rather than the real GitHub CLI, and it lets that harness mock
  # `cc` the identical way (`fixtures/bin/cc`) so this step can be tested
  # without ever touching a real Mac's real setup-helper config -- see that
  # test file's own hard safety gate for both.
  if ! cc_bin="$(command -v cc 2>/dev/null)" || [[ -z "$cc_bin" ]]; then
    emit_step "$step" "skipped" "The setup helper isn't on this Mac yet, so I didn't set its organization pointer. Control Tower will ask for it once, the first time it needs to sign in here."
    return
  fi
  # Check-then-act, same discipline as every GitHub mutation above: a
  # standing Mac whose pointer already matches is a no-op, never a repeated
  # "updated" (admin-standup-contract's own re-run promise: a re-run against
  # a standing org emits only already-present/skipped and mutates nothing).
  if current="$("$cc_bin" config get github_app.org --raw 2>/dev/null)" && [[ "$current" == "$org" ]]; then
    emit_step "$step" "already-present" "This Mac's setup helper already knows which organization it's with."
    return
  fi
  if "$cc_bin" config set github_app.org "$org" >/dev/null 2>&1; then
    emit_step "$step" "updated" "Told this Mac's setup helper which organization it's with, so it won't have to ask."
  else
    emit_step "$step" "skipped" "Couldn't set this Mac's organization pointer. Control Tower will ask for it once, the first time it needs to sign in here."
  fi
}

# ---------------------------------------------------------------------------
# Standup / add-department orchestration
# ---------------------------------------------------------------------------

run_standup() {
  local org="$1" repo unit harness_repo="${HARNESS_LIST[0]}-copilot-internal"

  _preflight "$org"
  _preflight_repository_matrix "$org"
  _preflight_ecosystem_contract "$org"
  _preflight_layer_packages "$org"
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
  for repo in "knowledge-copilot-internal" "cli-copilot-internal"; do
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

    for repo in "${HARNESS_LIST[@]}"; do
      _ensure_layer_package "$org" "${repo}-copilot-${unit}" "$repo" "department" "20" "empty-only"
    done

    while IFS= read -r repo; do
      _ensure_branch_protection "$org" "$repo" "branch-protection:$repo"
    done < <(_dept_triplet_repos "$unit")
  done

  _write_ecosystem_yml "$org"
  for repo in "${HARNESS_LIST[@]}"; do
    if [[ "${repo}-copilot-internal" == "$harness_repo" ]]; then
      _ensure_layer_package "$org" "$harness_repo" "$repo" "organization" "30" "ecosystem-only"
    else
      _ensure_layer_package "$org" "${repo}-copilot-internal" "$repo" "organization" "30" "empty-only"
    fi
    _ensure_branch_protection "$org" "${repo}-copilot-internal" "branch-protection:${repo}-copilot-internal"
  done

  # The public mirror of the two fields a signed-out Mac needs before it can
  # sign in at all (org-question copy spec §1/Appendix E.2), then this
  # Mac's own local pointer (§5, "the better fix, one layer up") — both
  # additive, both after every other real GitHub state this run creates.
  _ensure_public_bootstrap_repo "$org"
  _ensure_bootstrap_yml "$org"
  _ensure_local_org_pointer "$org"
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
  if ! _array_contains "$unit" "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; then
    DEPARTMENTS+=("$unit")
  fi
  _preflight_repository_matrix "$org"
  _preflight_ecosystem_contract "$org"
  _preflight_layer_packages "$org"

  while IFS= read -r repo; do
    _ensure_repo "$org" "$repo" "dept-repo:$unit:$repo"
  done < <(_dept_triplet_repos "$unit")

  _ensure_team "$org" "$unit" "dept-team:$unit"

  while IFS= read -r repo; do
    _ensure_team_grant "$org" "$unit" "$repo" "dept-grant:$unit:$repo"
  done < <(_dept_triplet_repos "$unit")

  for repo in "${HARNESS_LIST[@]}"; do
    _ensure_layer_package "$org" "${repo}-copilot-${unit}" "$repo" "department" "20" "empty-only"
  done

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
    reponame="${h}-copilot-internal"
    if ! _repo_exists_private "$org" "$reponame"; then
      if [[ "$_REPO_CHECK_STATUS" == "error" ]]; then unreadable+=("$org/$reponame"); else missing+=("$org/$reponame"); fi
    fi
  done
  for reponame in "knowledge-copilot-internal" "cli-copilot-internal"; do
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
        if [[ "$unit" == "internal" ]]; then
          continue
        fi
        if ! _array_contains "$unit" "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; then
          _check_row "dept-triplet" "present-undeclared" "$org has a $unit department that isn't in your plan. Setup added it, and that's fine." "" "none"
        fi
        ;;
    esac
  done <<< "$names"
}

# _check_ecosystem_drift_row ORG REPO DEFAULT_BRANCH PLAIN_DETAIL — the row
# for "the default branch's ecosystem.yml doesn't yet reflect the brief"
# (missing entirely, or drifted). Content-bearing repos land ecosystem.yml
# changes via a PR, never a direct push (admin-standup-contract.md §6 step
# 5), so this state can mean either "nothing has happened yet" or "a pull
# request is open, awaiting a human review and merge" — two very different
# things for the admin to hear.
#
# DECISION: render `fail`, never `unknown` and never `pass`, in both cases —
# justified per §3.2's own definitions: `unknown` means "the check itself
# could not run," which isn't true here (it ran and got a definite answer:
# not on the default branch); `pass` would mean "verified true on GitHub,"
# which is false (the resolver users' CLI actually reads only the default
# branch — a pending PR is not yet in effect). `fail` is still honest and
# not misleading, because the *detail* — not the status — is what carries
# "nothing done" vs. "pending review": when an open PR exists, the detail
# names it explicitly, so a red row here never reads as if no work happened.
_check_ecosystem_drift_row() {
  local org="$1" repo="$2" default_branch="$3" plain_detail="$4"
  if _find_pr "$org" "$repo" "$WORK_BRANCH" "$default_branch"; then
    if [[ -n "$_PR_NUMBER" ]]; then
      _check_row "ecosystem-file" "fail" "$plain_detail Pull request #$_PR_NUMBER is open with this change: review and merge it." "Admin" "describe"
    else
      _check_row "ecosystem-file" "fail" "$plain_detail" "Admin" "describe"
    fi
  else
    _check_row "ecosystem-file" "unknown" "$plain_detail I also couldn't check for a pending pull request, so I won't guess further." "Admin" "describe"
  fi
}

_check_ecosystem_file() {
  local org="$1" target_repo="${HARNESS_LIST[0]}-copilot-internal" info b64 content err_file default_branch

  if _gh_read "repos/$org/$target_repo" '.default_branch // empty'; then
    default_branch="$_GH_READ_VALUE"
  else
    _check_row "ecosystem-file" "unknown" "I couldn't read $org/$target_repo, so I won't guess about its ecosystem.yml." "Admin" "describe"
    return
  fi

  err_file="$(mktemp)"
  if ! info="$(gh api "repos/$org/$target_repo/contents/ecosystem.yml" 2>"$err_file")"; then
    if grep -qi 'HTTP 404' "$err_file" 2>/dev/null; then
      rm -f "$err_file"
      _check_ecosystem_drift_row "$org" "$target_repo" "$default_branch" "$org/$target_repo has no ecosystem.yml yet."
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
  local h missing_h=() u missing_u=() missing_config=() actual_ref desired_ref
  for h in "${HARNESS_LIST[@]}"; do
    _array_contains "$h" "${_STATE_HARNESS[@]+"${_STATE_HARNESS[@]}"}" || missing_h+=("$h")
  done
  for u in "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; do
    _array_contains "$u" "${_STATE_DEPT_UNITS[@]+"${_STATE_DEPT_UNITS[@]}"}" || missing_u+=("$u")
  done
  [[ "$_STATE_GITHUB_CLIENT_ID" == "$GITHUB_OAUTH_CLIENT_ID" ]] || missing_config+=("github_app.client_id")
  if [[ "$STORE_STATUS" == "connected" ]]; then
    [[ "$_STATE_STORE_WORKSPACE_ID" == "$STORE_WORKSPACE_ID" ]] || missing_config+=("store.workspace_id")
    [[ "$_STATE_STORE_ENVIRONMENT" == "$STORE_ENVIRONMENT" ]] || missing_config+=("store.environment")
    [[ "$_STATE_STORE_SECRET_PATH" == "$STORE_SECRET_PATH" ]] || missing_config+=("store.secret_path")
  fi
  if [[ "$_STATE_PERSONAL_OWNER" != "user" \
    || "$_STATE_PERSONAL_RANK" != "10" \
    || "$_STATE_PERSONAL_REPOSITORY_PATTERN" != "<user>/<component>-copilot-private" ]]; then
    missing_config+=("personal handoff")
  fi
  for h in "${HARNESS_LIST[@]}"; do
    desired_ref="$(_foundation_ref_for "$h")"
    case "$h" in
      claude) actual_ref="$_STATE_FOUNDATION_CLAUDE_REF" ;;
      codex) actual_ref="$_STATE_FOUNDATION_CODEX_REF" ;;
    esac
    [[ "$actual_ref" == "$desired_ref" ]] || missing_config+=("foundation.refs.$h")
  done
  if [[ "${#missing_h[@]}" -eq 0 && "${#missing_u[@]}" -eq 0 && "${#missing_config[@]}" -eq 0 ]]; then
    _check_row "ecosystem-file" "pass" "$org/$target_repo's ecosystem.yml matches your plan." "" "none"
  else
    _check_ecosystem_drift_row "$org" "$target_repo" "$default_branch" \
      "$org/$target_repo's ecosystem.yml is missing or differs on: $(_join_comma "${missing_h[@]+"${missing_h[@]}"}" "${missing_u[@]+"${missing_u[@]}"}" "${missing_config[@]+"${missing_config[@]}"}")."
  fi
}

_read_contract_ecosystem() {
  local org="$1" target_repo="${HARNESS_LIST[0]}-copilot-internal" info content err_file
  err_file="$(mktemp)"
  if ! info="$(gh api "repos/$org/$target_repo/contents/ecosystem.yml" 2>"$err_file")"; then
    if grep -qi 'HTTP 404' "$err_file" 2>/dev/null; then
      _CONTRACT_ECOSYSTEM_STATUS="missing"
    else
      _CONTRACT_ECOSYSTEM_STATUS="unknown"
    fi
    rm -f "$err_file"
    return 1
  fi
  rm -f "$err_file"
  content="$(printf '%s' "$(echo "$info" | jq -r '.content')" | _b64_decode)"
  if [[ -z "$content" ]]; then
    _CONTRACT_ECOSYSTEM_STATUS="unknown"
    return 1
  fi
  _read_ecosystem_state "$content"
  _CONTRACT_ECOSYSTEM_STATUS="ok"
  return 0
}

_check_github_app() {
  local org="$1"
  if ! _read_contract_ecosystem "$org"; then
    if [[ "$_CONTRACT_ECOSYSTEM_STATUS" == "missing" ]]; then
      _check_row "github-app" "fail" "ecosystem.yml does not carry the organization's public GitHub OAuth App client ID yet." "Admin" "describe"
    else
      _check_row "github-app" "unknown" "I couldn't read ecosystem.yml, so I won't guess whether the GitHub OAuth App client ID is ready." "Admin" "describe"
    fi
    return
  fi
  if _valid_github_oauth_client_id "$_STATE_GITHUB_CLIENT_ID" && [[ "$_STATE_GITHUB_CLIENT_ID" == "$GITHUB_OAUTH_CLIENT_ID" ]]; then
    _check_row "github-app" "pass" "ecosystem.yml carries the expected public GitHub OAuth App client ID." "" "none"
  elif [[ -z "$_STATE_GITHUB_CLIENT_ID" ]]; then
    _check_row "github-app" "fail" "ecosystem.yml is missing github_app.client_id." "Admin" "describe"
  else
    _check_row "github-app" "fail" "ecosystem.yml carries a malformed or different github_app.client_id. I won't treat organization identity as interchangeable." "Admin" "describe"
  fi
}

_check_personal_handoff() {
  local org="$1"
  if ! _read_contract_ecosystem "$org"; then
    if [[ "$_CONTRACT_ECOSYSTEM_STATUS" == "missing" ]]; then
      _check_row "personal-handoff" "fail" "ecosystem.yml does not carry the User Setup handoff yet." "Admin" "describe"
    else
      _check_row "personal-handoff" "unknown" "I couldn't read ecosystem.yml, so I won't guess whether the personal repository handoff is ready." "Admin" "describe"
    fi
    return
  fi
  if [[ "$_STATE_PERSONAL_OWNER" == "user" \
    && "$_STATE_PERSONAL_RANK" == "10" \
    && "$_STATE_PERSONAL_REPOSITORY_PATTERN" == "<user>/<component>-copilot-private" ]]; then
    _check_row "personal-handoff" "pass" "User Setup is delegated to the signed-in user and the private component repository pattern is present." "" "none"
  else
    _check_row "personal-handoff" "fail" "ecosystem.yml is missing or differs from the non-secret personal repository handoff contract." "Admin" "describe"
  fi
}

_check_public_bootstrap_repo() {
  local org="$1"
  _probe_repo "$org" "copilot-bootstrap"
  case "$_REPO_PROBE_STATE" in
    conflict-public)
      _check_row "bootstrap-repo" "pass" "$org/copilot-bootstrap exists and is public for signed-out discovery." "" "none"
      ;;
    existing-private)
      _check_row "bootstrap-repo" "fail" "$org/copilot-bootstrap exists but is private, so a signed-out Mac cannot read it." "Admin" "describe"
      ;;
    missing)
      _check_row "bootstrap-repo" "fail" "$org/copilot-bootstrap does not exist yet, so signed-out discovery cannot start." "Admin" "describe"
      ;;
    *)
      _check_row "bootstrap-repo" "unknown" "I couldn't read $org/copilot-bootstrap, so I won't guess whether signed-out discovery is available." "Admin" "describe"
      ;;
  esac
}

_check_bootstrap_yml() {
  local org="$1" expected content
  expected="$(_render_bootstrap_yml "$org" "$GITHUB_OAUTH_CLIENT_ID")"
  if _gh_read "repos/$org/copilot-bootstrap/contents/bootstrap.yml" '.content // empty'; then
    content="$(printf '%s' "$_GH_READ_VALUE" | _b64_decode)"
    if [[ "$content" == "$expected" ]]; then
      _check_row "bootstrap-yml" "pass" "$org/copilot-bootstrap/bootstrap.yml carries exactly the expected organization name and public sign-in ID." "" "none"
    else
      _check_row "bootstrap-yml" "fail" "$org/copilot-bootstrap/bootstrap.yml is missing, differs, or carries fields outside the two-field discovery contract." "Admin" "describe"
    fi
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    _check_row "bootstrap-yml" "fail" "$org/copilot-bootstrap has no bootstrap.yml matching the signed-out discovery contract." "Admin" "describe"
  else
    _check_row "bootstrap-yml" "unknown" "I couldn't read $org/copilot-bootstrap/bootstrap.yml, so I won't guess whether its discovery data is safe and current." "Admin" "describe"
  fi
}

_check_layer_package() {
  local org="$1" repo="$2" product="$3" role="$4" rank="$5" content
  if _gh_read "repos/$org/$repo/contents/copilot.layer.yml" '.content // empty'; then
    content="$(printf '%s' "$_GH_READ_VALUE" | _b64_decode)"
    if [[ "$content" == *"  role: $role"* && "$content" == *"  rank: $rank"* && "$content" == *"  product: $product"* ]]; then
      _check_row "layer-package:$repo" "pass" "$org/$repo has the expected $role rank-$rank package." "" "none"
    else
      _check_row "layer-package:$repo" "fail" "$org/$repo has a different or invalid layer package. It was not rewritten." "Admin" "describe"
    fi
  elif [[ "$_GH_READ_STATUS" == "not-found" ]]; then
    _check_row "layer-package:$repo" "fail" "$org/$repo has no recognized layer package yet." "Admin" "describe"
  else
    _check_row "layer-package:$repo" "unknown" "I couldn't read $org/$repo's layer package, so I won't guess." "Admin" "describe"
  fi
}

_http_reachable() {
  local url="$1"
  case "$url" in
    http://*|https://*) ;;
    *) return 1 ;;
  esac

  # macOS ships Bash 3.2 without a portable /dev/tcp implementation. Use
  # the system curl at an absolute path so LaunchServices PATH differences
  # cannot turn a healthy store into a false failure (or select a shadowed
  # binary). Any HTTP response proves the endpoint answered; curl still
  # fails closed on DNS, connection, timeout, and TLS errors.
  /usr/bin/curl \
    --silent \
    --show-error \
    --output /dev/null \
    --connect-timeout 5 \
    --max-time 10 \
    --proto '=http,https' \
    "$url"
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
  if _http_reachable "$STORE_ENDPOINT"; then
    _check_row "store" "pass" "Your shared secret store answered at $STORE_ENDPOINT." "" "none"
  else
    _check_row "store" "fail" "Your shared secret store at $STORE_ENDPOINT didn't answer." "IT infra" "connect-store"
  fi
}

_check_foundation_pin() {
  # Two separate local statements, deliberately: `local a=X b="$a-y"` in a
  # single statement evaluates every RHS against the *pre-existing* value of
  # each name, not the sibling just assigned earlier in the same statement —
  # a real bash gotcha, not sequential assignment. Chaining them here would
  # silently resolve `repo` against an empty `h`.
  local h="$1"
  local repo="${h}-copilot" range
  range="$(_foundation_ref_for "$h")"
  if _resolve_foundation_pin "$repo" "$range"; then
    _check_row "foundation-pin:$h" "pass" "The foundation reference for $h resolves to $_RESOLVED_TAG (satisfies $range)." "" "none"
    return
  fi
  case "$_RESOLVE_STATUS" in
    no-match)
      _check_row "foundation-pin:$h" "fail" "No published tag of $FOUNDATION_ORG/$repo satisfies $range." "ENAC/external" "external"
      ;;
    bad-range)
      _check_row "foundation-pin:$h" "fail" "The foundation pin \"$range\" isn't a caret range I understand." "ENAC/external" "external"
      ;;
    *)
      _check_row "foundation-pin:$h" "unknown" "I couldn't read $FOUNDATION_ORG/$repo's published tags, so I won't guess whether $range resolves." "ENAC/external" "external"
      ;;
  esac
}

run_verify() {
  local org="$ORG"
  local checks_json="[]" row unit h

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
  row="$(_check_github_app "$org")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
  row="$(_check_personal_handoff "$org")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
  row="$(_check_public_bootstrap_repo "$org")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
  row="$(_check_bootstrap_yml "$org")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
  for h in "${HARNESS_LIST[@]}"; do
    row="$(_check_layer_package "$org" "${h}-copilot-internal" "$h" "organization" "30")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
    for unit in "${DEPARTMENTS[@]+"${DEPARTMENTS[@]}"}"; do
      row="$(_check_layer_package "$org" "${h}-copilot-${unit}" "$h" "department" "20")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
    done
  done
  row="$(_check_store)"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
  for h in "${HARNESS_LIST[@]}"; do
    row="$(_check_foundation_pin "$h")"; checks_json="$(echo "$checks_json" | jq --argjson r "$row" '. + [$r]')"; _tally "$row"
  done

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
      --plan)
        mode="plan"
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
    plan)
      if ! $json_flag; then
        echo "--plan requires --json." >&2
        exit 1
      fi
      [[ -n "$brief_path" ]] || brief_path="$DEFAULT_BRIEF_PATH"
      _load_brief "$brief_path"
      run_repository_plan "$ORG"
      ;;
  esac
}

main "$@"
