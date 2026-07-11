#!/usr/bin/env bash
# test_admin_bootstrap.sh — offline test harness for scripts/admin_bootstrap.sh.
#
# No bats/shunit dependency: plain bash, a fake `gh` on PATH (fixtures/bin/gh)
# that records every invocation and serves canned/stateful JSON, and hand-rolled
# assertions. Run with:
#   bash scripts/tests/test_admin_bootstrap.sh
#
# Exits non-zero if any assertion fails; prints a plain pass/fail summary.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="$REPO_ROOT/scripts/admin_bootstrap.sh"
MOCK_BIN="$SCRIPT_DIR/fixtures/bin"

if [[ ! -f "$ENGINE" ]]; then
  echo "engine not found: $ENGINE" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/admin-bootstrap-tests.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

export PATH="$MOCK_BIN:$PATH"

# Hard safety gate. This whole suite assumes every `gh` call is intercepted
# by the mock at fixtures/bin, never the real GitHub CLI: a probe or test
# that forgets this (or a PATH change upstream that reorders it) would
# otherwise fire real, live calls against github.com instead of the mock,
# read-only or not. Refuse to run a single test if that isn't true.
RESOLVED_GH="$(command -v gh || true)"
if [[ "$RESOLVED_GH" != "$MOCK_BIN/gh" ]]; then
  echo "FATAL: gh resolves to [$RESOLVED_GH], not the mock at $MOCK_BIN/gh." >&2
  echo "Refusing to run any test: this would risk real calls to github.com." >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_NAMES=()

ok() {
  PASS=$((PASS + 1))
  echo "ok - $1"
}

not_ok() {
  FAIL=$((FAIL + 1))
  FAILED_NAMES+=("$1")
  echo "not ok - $1"
  if [[ -n "${2:-}" ]]; then
    printf '%s\n' "$2" | sed 's/^/    # /'
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$desc"
  else
    not_ok "$desc" "expected [$expected]
got      [$actual]"
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$desc"
  else
    not_ok "$desc" "expected to find [$needle] in:
$haystack"
  fi
}

assert_true() {
  local desc="$1" rc="$2" detail="${3:-}"
  if [[ "$rc" -eq 0 ]]; then
    ok "$desc"
  else
    not_ok "$desc" "$detail"
  fi
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# new_org_state NAME — prints the path to a fresh state dir for a ready,
# valid acme-co org (signed in, owner, full scopes, base perm not yet read).
# Also seeds a foundation tag (v5.13.0) satisfying the engine's default
# ^5.13.0 pin for the "codex" harness, so every existing test's foundation-pin
# check resolves to pass unless a test deliberately overrides it.
new_org_state() {
  local st="$WORKDIR/state-$1"
  rm -rf "$st"
  mkdir -p "$st/orgs/acme-co"
  echo "earladmin" > "$st/user_login"
  echo "repo, admin:org, read:org" > "$st/user_scopes"
  echo "admin" > "$st/orgs/acme-co/membership_earladmin"
  echo "admin" > "$st/orgs/acme-co/default_permission"
  mkdir -p "$st/tags/Everyone-Needs-A-Copilot"
  printf 'v5.13.0\n' > "$st/tags/Everyone-Needs-A-Copilot/codex-copilot"
  printf '%s' "$st"
}

# seed_content_bearing_repo STATE_DIR ORG REPO [ECOSYSTEM_CONTENT] — marks a
# repo as already carrying content (has commits) before the engine runs
# against it, exercising the PR path (admin-standup-contract.md §6 step 5)
# instead of the empty-repo initial-commit path. An optional fourth argument
# seeds that repo's default-branch ecosystem.yml content.
seed_content_bearing_repo() {
  local st="$1" org="$2" repo="$3" content="${4:-}"
  local repo_dir="$st/repos/$org/$repo"
  mkdir -p "$repo_dir"
  echo true > "$repo_dir/private"
  echo main > "$repo_dir/default_branch"
  touch "$repo_dir/has_commits"
  if [[ -n "$content" ]]; then
    mkdir -p "$repo_dir/refs/main"
    printf '%s' "$content" > "$repo_dir/refs/main/ecosystem.yml"
  fi
}

STORE_CONNECTED=$'store:\n  status: connected\n  type: infisical\n  endpoint: https://vault.acme-co.example\n  team_scopes:\n    - { team: accounting, scope: dept/accounting }\n    - { team: sales, scope: dept/sales }'
STORE_DEFERRED=$'store:\n  status: deferred'

# write_brief PATH STORE_BLOCK [STORE_ENDPOINT_OVERRIDE_BLOCK]
write_brief() {
  local path="$1" store_block="$2"
  cat > "$path" <<EOF
---
schema_version: "1.0"
org: acme-co
harness:
  - codex
departments:
  - accounting
  - sales
$store_block
contacts:
  admin: "Earl P."
---

# Standup brief for acme-co (test fixture)
EOF
}

# run_engine STATE_DIR LOG_PATH ARGS... — sets RUN_STDOUT, RUN_STDERR, RUN_EXIT.
run_engine() {
  local st="$1" log="$2"
  shift 2
  local out="$WORKDIR/out.$$.$RANDOM"
  local err="$WORKDIR/err.$$.$RANDOM"
  : > "$log"
  GH_MOCK_STATE_DIR="$st" GH_MOCK_LOG="$log" bash "$ENGINE" "$@" >"$out" 2>"$err"
  RUN_EXIT=$?
  RUN_STDOUT="$(cat "$out")"
  RUN_STDERR="$(cat "$err")"
}

count_calls() {
  # count_calls LOG METHOD_REGEX ENDPOINT_REGEX
  local log="$1" method_re="$2" endpoint_re="$3"
  awk -F'\t' -v m="$method_re" -v e="$endpoint_re" \
    '$1 ~ m && $2 ~ e {c++} END{print c+0}' "$log"
}

count_mutating_calls() {
  local log="$1"
  awk -F'\t' '$1=="POST" || $1=="PATCH" || $1=="PUT" {c++} END{print c+0}' "$log"
}

no_em_dash() {
  # no_em_dash TEXT — true (exit 0) if TEXT contains no em-dash (U+2014, —).
  # Operator/GitHub-facing copy uses periods/commas/colons only.
  ! printf '%s' "$1" | grep -q $'\xe2\x80\x94'
}

count_calls_with_field() {
  # count_calls_with_field LOG METHOD_REGEX ENDPOINT_REGEX FIELD_SUBSTRING —
  # like count_calls, but also requires the recorded (sorted) field list to
  # contain FIELD_SUBSTRING. Used to distinguish, e.g., a branch-scoped PUT
  # (carries "branch=copilot-standup") from a direct push to the default
  # branch (carries no such field).
  local log="$1" method_re="$2" endpoint_re="$3" field_substr="$4"
  awk -F'\t' -v m="$method_re" -v e="$endpoint_re" -v f="$field_substr" \
    '$1 ~ m && $2 ~ e && index($3, f) > 0 {c++} END{print c+0}' "$log"
}

all_results_in() {
  # all_results_in NDJSON ALLOWED_REGEX — true if every "result" value matches
  local ndjson="$1" allowed_re="$2"
  local bad
  bad="$(printf '%s\n' "$ndjson" | jq -r '.result' | grep -Ev "$allowed_re" || true)"
  [[ -z "$bad" ]]
}

# ---------------------------------------------------------------------------
# Test 1: fresh standup creates the full matrix, in contract order.
# ---------------------------------------------------------------------------

test_fresh_standup_full_matrix() {
  local st brief log
  st="$(new_org_state fresh)"
  brief="$WORKDIR/brief-fresh.md"
  write_brief "$brief" "$STORE_CONNECTED"
  log="$WORKDIR/fresh.log"

  run_engine "$st" "$log" --brief "$brief"

  assert_eq "test1: fresh standup exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local repo_count team_count grant_count base_perm_count eco_count
  repo_count="$(count_calls "$log" '^POST$' '^orgs/acme-co/repos$')"
  team_count="$(count_calls "$log" '^POST$' '^orgs/acme-co/teams$')"
  grant_count="$(count_calls "$log" '^PUT$' '^orgs/acme-co/teams/[^/]+/repos/acme-co/')"
  base_perm_count="$(count_calls "$log" '^PATCH$' '^orgs/acme-co$')"
  eco_count="$(count_calls "$log" '^PUT$' 'contents/ecosystem\.yml$')"

  assert_eq "test1: creates 9 repos (org triplet + accounting triplet + sales triplet)" "9" "$repo_count"
  assert_eq "test1: creates 2 teams (accounting, sales)" "2" "$team_count"
  assert_eq "test1: grants 6 team-repo permissions (3 per department)" "6" "$grant_count"
  assert_eq "test1: sets org base permission exactly once" "1" "$base_perm_count"
  assert_eq "test1: writes ecosystem.yml exactly once" "1" "$eco_count"

  local expected_repos=(
    "acme-co/codex-copilot" "acme-co/knowledge-copilot" "acme-co/cli-copilot"
    "acme-co/codex-copilot-accounting" "acme-co/knowledge-copilot-accounting" "acme-co/cli-copilot-accounting"
    "acme-co/codex-copilot-sales" "acme-co/knowledge-copilot-sales" "acme-co/cli-copilot-sales"
  )
  local missing="" r
  for r in "${expected_repos[@]}"; do
    if [[ "$RUN_STDOUT" != *"Created $r, private."* ]]; then
      missing="$missing $r"
    fi
  done
  assert_eq "test1: every expected repo was reported created" "" "$missing"

  # Contract order: readiness and org-base-permission first; the harness
  # repo's ecosystem.yml write and its branch protection are last (see
  # admin_bootstrap.sh's run_standup for why protection on the harness repo
  # is deferred until it actually carries content).
  local first_step last_step second_last_step
  first_step="$(printf '%s\n' "$RUN_STDOUT" | head -1 | jq -r .step)"
  last_step="$(printf '%s\n' "$RUN_STDOUT" | tail -1 | jq -r .step)"
  second_last_step="$(printf '%s\n' "$RUN_STDOUT" | tail -2 | head -1 | jq -r .step)"
  assert_eq "test1: first NDJSON step is readiness" "readiness" "$first_step"
  assert_eq "test1: ecosystem-yml step precedes the harness repo's branch protection" "ecosystem-yml" "$second_last_step"
  assert_eq "test1: last NDJSON step protects the harness repo" "branch-protection:codex-copilot" "$last_step"
}

# ---------------------------------------------------------------------------
# Test 2: a full re-run against a standing org is a pure no-op.
# ---------------------------------------------------------------------------

test_full_rerun_is_noop() {
  local st brief log1 log2
  st="$(new_org_state rerun)"
  brief="$WORKDIR/brief-rerun.md"
  write_brief "$brief" "$STORE_CONNECTED"
  log1="$WORKDIR/rerun1.log"
  log2="$WORKDIR/rerun2.log"

  run_engine "$st" "$log1" --brief "$brief"
  assert_eq "test2: setup run (fixture) exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  run_engine "$st" "$log2" --brief "$brief"
  assert_eq "test2: re-run exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  assert_true "test2: re-run emits only already-present/skipped results" \
    "$(all_results_in "$RUN_STDOUT" '^(already-present|skipped)$'; echo $?)" \
    "$(printf '%s\n' "$RUN_STDOUT" | jq -r '.result' | sort -u)"

  local mutating
  mutating="$(count_mutating_calls "$log2")"
  assert_eq "test2: re-run records zero mutating calls" "0" "$mutating"
}

# ---------------------------------------------------------------------------
# Test 3: missing admin:org scope refuses before any mutation.
# ---------------------------------------------------------------------------

test_missing_scope_refuses() {
  local st brief log
  st="$WORKDIR/state-scope"
  rm -rf "$st"
  mkdir -p "$st/orgs/acme-co"
  echo "earladmin" > "$st/user_login"
  echo "repo, read:org" > "$st/user_scopes"   # admin:org deliberately missing
  echo "admin" > "$st/orgs/acme-co/membership_earladmin"
  echo "admin" > "$st/orgs/acme-co/default_permission"

  brief="$WORKDIR/brief-scope.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log="$WORKDIR/scope.log"

  run_engine "$st" "$log" --brief "$brief"

  assert_eq "test3: missing scope exits 2" "2" "$RUN_EXIT"
  assert_contains "test3: stderr teaches the exact fix" "$RUN_STDERR" "gh auth refresh -s admin:org -s repo"

  local mutating
  mutating="$(count_mutating_calls "$log")"
  assert_eq "test3: zero mutating calls before the refusal" "0" "$mutating"
}

# ---------------------------------------------------------------------------
# Test 4: leak-scan blocks before any push.
# ---------------------------------------------------------------------------

test_leak_scan_blocks_before_push() {
  local st brief log
  st="$(new_org_state leak)"
  brief="$WORKDIR/brief-leak.md"
  cat > "$brief" <<'EOF'
---
schema_version: "1.0"
org: acme-co
harness:
  - codex
departments:
  - accounting
store:
  status: connected
  type: infisical
  endpoint: "AKIAABCDEFGHIJKLMNOP"
contacts:
  admin: "Earl P."
---

# Standup brief for acme-co (leak-scan fixture: a secret-shaped store endpoint)
EOF
  log="$WORKDIR/leak.log"

  run_engine "$st" "$log" --brief "$brief"

  assert_eq "test4: leak-scan refusal exits 2" "2" "$RUN_EXIT"
  assert_contains "test4: stdout carries a refused leak-scan step" "$RUN_STDOUT" '"step":"leak-scan","result":"refused"'
  assert_contains "test4: stderr names the refusal in plain language" "$RUN_STDERR" "secret-shaped value"

  local push_count
  push_count="$(count_calls "$log" '^PUT$' 'contents/ecosystem\.yml$')"
  assert_eq "test4: no ecosystem.yml push happened" "0" "$push_count"
}

# ---------------------------------------------------------------------------
# Test 5: --verify --json matches the schema, incl. deferred + present-undeclared rows.
# ---------------------------------------------------------------------------

test_verify_json_schema() {
  local st brief log
  st="$(new_org_state verify)"
  brief="$WORKDIR/brief-verify.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log="$WORKDIR/verify-setup.log"

  run_engine "$st" "$log" --brief "$brief"
  assert_eq "test5: setup run (fixture) exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  # Seed a department present on GitHub but absent from the brief, to exercise
  # the present-undeclared row.
  local hr_dir
  for hr_dir in knowledge-copilot-hr cli-copilot-hr codex-copilot-hr; do
    mkdir -p "$st/repos/acme-co/$hr_dir"
    echo true > "$st/repos/acme-co/$hr_dir/private"
    echo main > "$st/repos/acme-co/$hr_dir/default_branch"
  done

  local verify_log verify_out
  verify_log="$WORKDIR/verify.log"
  run_engine "$st" "$verify_log" --verify --brief "$brief" --json
  verify_out="$RUN_STDOUT"

  assert_eq "test5: --verify --json exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local is_valid_json=1
  if echo "$verify_out" | jq -e . >/dev/null 2>&1; then is_valid_json=0; fi
  assert_true "test5: output is valid JSON" "$is_valid_json" "$verify_out"

  local schema_ok=1
  if echo "$verify_out" | jq -e '
      (.schema_version | type == "string") and
      (.checks | type == "array") and
      (.checks | length > 0) and
      (all(.checks[]; has("check") and has("status") and has("detail") and has("owner") and has("fix_surface")
        and (.status as $st | ["pass","fail","unknown","deferred","present-undeclared"] | index($st) != null))) and
      (.summary.must_fix | type == "number") and
      (.summary.unknown | type == "number")
    ' >/dev/null 2>&1; then
    schema_ok=0
  fi
  assert_true "test5: every check row matches the schema and status enum" "$schema_ok" "$verify_out"

  local has_deferred=1 has_undeclared=1
  if echo "$verify_out" | jq -e '.checks[] | select(.check == "store" and .status == "deferred")' >/dev/null 2>&1; then
    has_deferred=0
  fi
  if echo "$verify_out" | jq -e '.checks[] | select(.status == "present-undeclared")' >/dev/null 2>&1; then
    has_undeclared=0
  fi
  assert_true "test5: includes a deferred store row" "$has_deferred" "$verify_out"
  assert_true "test5: includes a present-undeclared row for the undeclared hr department" "$has_undeclared" "$verify_out"

  local deferred_excluded=1
  if echo "$verify_out" | jq -e '.summary.must_fix == 0 and .summary.unknown >= 0' >/dev/null 2>&1; then
    deferred_excluded=0
  fi
  assert_true "test5: deferred and present-undeclared never count toward must_fix" "$deferred_excluded" "$verify_out"

  local verify_mutating
  verify_mutating="$(count_mutating_calls "$verify_log")"
  assert_eq "test5: --verify makes zero mutating calls" "0" "$verify_mutating"
}

# ---------------------------------------------------------------------------
# Test 6: --add-department for an existing department is a full no-op.
# ---------------------------------------------------------------------------

test_add_existing_department_is_noop() {
  local st brief log
  st="$(new_org_state add-dept)"
  brief="$WORKDIR/brief-add-dept.md"
  write_brief "$brief" "$STORE_CONNECTED"
  log="$WORKDIR/add-dept-setup.log"

  run_engine "$st" "$log" --brief "$brief"
  assert_eq "test6: setup run (fixture) exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local add_log
  add_log="$WORKDIR/add-dept.log"
  run_engine "$st" "$add_log" --add-department accounting --brief "$brief"

  assert_eq "test6: re-adding an existing department exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"
  assert_true "test6: re-adding an existing department emits only already-present/skipped" \
    "$(all_results_in "$RUN_STDOUT" '^(already-present|skipped)$'; echo $?)" \
    "$(printf '%s\n' "$RUN_STDOUT" | jq -r '.result' | sort -u)"

  local mutating
  mutating="$(count_mutating_calls "$add_log")"
  assert_eq "test6: zero mutating calls for an existing department" "0" "$mutating"
}

# ---------------------------------------------------------------------------
# Test 7: an invalid department slug refuses at preflight, zero mutating calls.
# ---------------------------------------------------------------------------

test_invalid_department_slug_refuses() {
  local st brief log
  st="$(new_org_state bad-dept-slug)"
  brief="$WORKDIR/brief-bad-dept-slug.md"
  cat > "$brief" <<'EOF'
---
schema_version: "1.0"
org: acme-co
harness:
  - codex
departments:
  - accounting
  - Human Resources
store:
  status: deferred
contacts:
  admin: "Earl P."
---

# Standup brief for acme-co (invalid department slug fixture)
EOF
  log="$WORKDIR/bad-dept-slug.log"

  run_engine "$st" "$log" --brief "$brief"

  assert_eq "test7: invalid department slug exits 2" "2" "$RUN_EXIT"
  assert_contains "test7: stderr names the offending department value" "$RUN_STDERR" 'Department name "Human Resources"'
  assert_contains "test7: stderr suggests letters, numbers, and dashes" "$RUN_STDERR" "letters, numbers, and dashes"
  assert_contains "test7: stderr never auto-slugifies, it points at the brief" "$RUN_STDERR" "update the brief"

  local mutating
  mutating="$(count_mutating_calls "$log")"
  assert_eq "test7: zero mutating calls before the refusal" "0" "$mutating"

  local total_calls
  total_calls="$(wc -l < "$log" | tr -d ' ')"
  assert_eq "test7: zero gh calls at all (refused before any network call)" "0" "$total_calls"
}

# ---------------------------------------------------------------------------
# Test 8: an invalid org slug refuses at preflight, zero mutating calls.
# ---------------------------------------------------------------------------

test_invalid_org_slug_refuses() {
  local st brief log
  st="$(new_org_state bad-org-slug)"
  brief="$WORKDIR/brief-bad-org-slug.md"
  cat > "$brief" <<'EOF'
---
schema_version: "1.0"
org: Acme Co!
harness:
  - codex
departments:
  - accounting
store:
  status: deferred
contacts:
  admin: "Earl P."
---

# Standup brief for an invalid org slug fixture
EOF
  log="$WORKDIR/bad-org-slug.log"

  run_engine "$st" "$log" --brief "$brief"

  assert_eq "test8: invalid org slug exits 2" "2" "$RUN_EXIT"
  assert_contains "test8: stderr names the rule, not a guessed transform of the value" "$RUN_STDERR" "That doesn't look like a GitHub organization name."
  assert_contains "test8: stderr says letters, numbers, and single dashes" "$RUN_STDERR" "letters, numbers, and single dashes"

  local mutating
  mutating="$(count_mutating_calls "$log")"
  assert_eq "test8: zero mutating calls before the refusal" "0" "$mutating"
}

# ---------------------------------------------------------------------------
# Test 9: an injected read failure surfaces honestly — failed in run mode,
# unknown in verify mode — never silently treated as "not set"/"doesn't exist".
# ---------------------------------------------------------------------------

test_injected_read_failure_surfaces_honestly() {
  local st brief log

  # Run mode: org-base-permission's read (orgs/acme-co) is call #5 in a
  # fresh run (login, scopes, org-exists, membership, then this read) —
  # the exact "injected call-5 failure" shape QA proved. Injecting on the
  # endpoint itself would also trip preflight's earlier, unrelated hit to
  # the same path, so this uses the call-count injection instead.
  st="$(new_org_state inject-run)"
  brief="$WORKDIR/brief-inject-run.md"
  write_brief "$brief" "$STORE_DEFERRED"
  echo "5" > "$st/inject-error-at-call"
  log="$WORKDIR/inject-run.log"

  run_engine "$st" "$log" --brief "$brief"

  assert_eq "test9: run mode exits 1 on an injected read failure" "1" "$RUN_EXIT"
  assert_contains "test9: run mode emits a failed org-base-permission step" "$RUN_STDOUT" '"step":"org-base-permission","result":"failed"'
  assert_contains "test9: run mode never silently treats it as \"not set\"" "$RUN_STDOUT" "so I won't guess"

  local mutating
  mutating="$(count_mutating_calls "$log")"
  assert_eq "test9: run mode makes zero mutating calls once the read failed" "0" "$mutating"

  # Verify mode: no preflight runs, so injecting directly on the org-base-read
  # endpoint (orgs/acme-co) unambiguously targets only that check.
  local vst vbrief vlog
  vst="$(new_org_state inject-verify)"
  echo "read" > "$vst/orgs/acme-co/default_permission"
  mkdir -p "$vst/inject-error"
  touch "$vst/inject-error/orgs__acme-co"
  vbrief="$WORKDIR/brief-inject-verify.md"
  write_brief "$vbrief" "$STORE_DEFERRED"
  vlog="$WORKDIR/inject-verify.log"

  run_engine "$vst" "$vlog" --verify --brief "$vbrief" --json

  assert_eq "test9: verify mode still exits 0 (verify never fails the process on a check-level problem)" "0" "$RUN_EXIT" "$RUN_STDERR"

  local row_status
  row_status="$(printf '%s' "$RUN_STDOUT" | jq -r '.checks[] | select(.check == "org-base-read") | .status')"
  assert_eq "test9: verify mode renders org-base-read as unknown, never pass" "unknown" "$row_status"

  local verify_mutating
  verify_mutating="$(count_mutating_calls "$vlog")"
  assert_eq "test9: verify mode makes zero mutating calls" "0" "$verify_mutating"
}

# ---------------------------------------------------------------------------
# Test 10: a content-bearing repo's first ecosystem.yml change opens a PR on
# the fixed work branch — never a direct push.
# ---------------------------------------------------------------------------

test_content_bearing_repo_opens_pr() {
  local st brief log
  st="$(new_org_state content-fresh)"
  seed_content_bearing_repo "$st" acme-co codex-copilot
  brief="$WORKDIR/brief-content-fresh.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log="$WORKDIR/content-fresh.log"

  run_engine "$st" "$log" --brief "$brief"
  assert_eq "test10: content-bearing standup exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local eco_step_result eco_step_detail
  eco_step_result="$(printf '%s\n' "$RUN_STDOUT" | jq -r 'select(.step == "ecosystem-yml") | .result')"
  eco_step_detail="$(printf '%s\n' "$RUN_STDOUT" | jq -r 'select(.step == "ecosystem-yml") | .detail')"
  assert_eq "test10: ecosystem-yml step is created (opened a PR)" "created" "$eco_step_result"
  assert_contains "test10: detail names the opened pull request" "$eco_step_detail" "Opened pull request #1"

  local branch_create_count pr_create_count branch_push_count direct_push_count
  branch_create_count="$(count_calls "$log" '^POST$' '^repos/acme-co/codex-copilot/git/refs$')"
  pr_create_count="$(count_calls "$log" '^POST$' '^repos/acme-co/codex-copilot/pulls$')"
  branch_push_count="$(count_calls_with_field "$log" '^PUT$' '^repos/acme-co/codex-copilot/contents/ecosystem\.yml$' 'branch=copilot-standup')"
  direct_push_count="$(count_calls_with_field "$log" '^PUT$' '^repos/acme-co/codex-copilot/contents/ecosystem\.yml$' 'message=Initial ecosystem.yml')"

  assert_eq "test10: creates the copilot-standup branch exactly once" "1" "$branch_create_count"
  assert_eq "test10: pushes ecosystem.yml to the branch exactly once" "1" "$branch_push_count"
  assert_eq "test10: opens exactly one pull request" "1" "$pr_create_count"
  assert_eq "test10: never a direct/initial-commit push to a content-bearing repo" "0" "$direct_push_count"
}

# ---------------------------------------------------------------------------
# Test 11: a re-run with the same desired content is idempotent — no
# duplicate branch commit, no duplicate pull request.
# ---------------------------------------------------------------------------

test_content_bearing_rerun_is_noop() {
  local st brief log1 log2
  st="$(new_org_state content-rerun)"
  seed_content_bearing_repo "$st" acme-co codex-copilot
  brief="$WORKDIR/brief-content-rerun.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log1="$WORKDIR/content-rerun1.log"
  log2="$WORKDIR/content-rerun2.log"

  run_engine "$st" "$log1" --brief "$brief"
  assert_eq "test11: first content-bearing run exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  run_engine "$st" "$log2" --brief "$brief"
  assert_eq "test11: second content-bearing run exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local eco_step_result eco_step_detail
  eco_step_result="$(printf '%s\n' "$RUN_STDOUT" | jq -r 'select(.step == "ecosystem-yml") | .result')"
  eco_step_detail="$(printf '%s\n' "$RUN_STDOUT" | jq -r 'select(.step == "ecosystem-yml") | .detail')"
  assert_eq "test11: re-run's ecosystem-yml step is already-present" "already-present" "$eco_step_result"
  assert_contains "test11: re-run's detail still names pull request #1" "$eco_step_detail" "#1"

  local branch_create_count pr_create_count branch_push_count
  branch_create_count="$(count_calls "$log2" '^POST$' '^repos/acme-co/codex-copilot/git/refs$')"
  pr_create_count="$(count_calls "$log2" '^POST$' '^repos/acme-co/codex-copilot/pulls$')"
  branch_push_count="$(count_calls_with_field "$log2" '^PUT$' '^repos/acme-co/codex-copilot/contents/ecosystem\.yml$' 'branch=copilot-standup')"

  assert_eq "test11: re-run creates no duplicate branch" "0" "$branch_create_count"
  assert_eq "test11: re-run pushes no duplicate commit" "0" "$branch_push_count"
  assert_eq "test11: re-run opens no duplicate pull request" "0" "$pr_create_count"
}

# ---------------------------------------------------------------------------
# Test 12: the leak-scan blocks a secret-shaped value before ANY push on the
# branch-push (content-bearing repo) path too, not just the initial-commit path.
# ---------------------------------------------------------------------------

test_leak_scan_blocks_branch_push() {
  local st brief log
  st="$(new_org_state content-leak)"
  seed_content_bearing_repo "$st" acme-co codex-copilot
  brief="$WORKDIR/brief-content-leak.md"
  cat > "$brief" <<'EOF'
---
schema_version: "1.0"
org: acme-co
harness:
  - codex
departments:
  - accounting
store:
  status: connected
  type: infisical
  endpoint: "AKIAABCDEFGHIJKLMNOP"
contacts:
  admin: "Earl P."
---

# Standup brief for acme-co (leak-scan-on-branch-path fixture)
EOF
  log="$WORKDIR/content-leak.log"

  run_engine "$st" "$log" --brief "$brief"

  assert_eq "test12: leak-scan refusal on the branch path exits 2" "2" "$RUN_EXIT"
  assert_contains "test12: stdout carries a refused leak-scan step" "$RUN_STDOUT" '"step":"leak-scan","result":"refused"'

  local branch_create_count pr_create_count branch_push_count
  branch_create_count="$(count_calls "$log" '^POST$' '^repos/acme-co/codex-copilot/git/refs$')"
  pr_create_count="$(count_calls "$log" '^POST$' '^repos/acme-co/codex-copilot/pulls$')"
  branch_push_count="$(count_calls "$log" '^PUT$' 'contents/ecosystem\.yml$')"

  assert_eq "test12: no branch was created" "0" "$branch_create_count"
  assert_eq "test12: no commit was pushed to any branch" "0" "$branch_push_count"
  assert_eq "test12: no pull request was opened" "0" "$pr_create_count"
}

# ---------------------------------------------------------------------------
# Test 13: --verify renders the pending-PR state honestly: fail (never pass,
# never a bare "nothing happened" fail), naming the open pull request.
# ---------------------------------------------------------------------------

test_verify_renders_pending_pr() {
  local st brief log
  st="$(new_org_state content-verify-pending)"
  seed_content_bearing_repo "$st" acme-co codex-copilot
  brief="$WORKDIR/brief-content-verify-pending.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log="$WORKDIR/content-verify-pending-setup.log"

  run_engine "$st" "$log" --brief "$brief"
  assert_eq "test13: setup run (fixture) exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local verify_log verify_out
  verify_log="$WORKDIR/content-verify-pending.log"
  run_engine "$st" "$verify_log" --verify --brief "$brief" --json
  verify_out="$RUN_STDOUT"

  assert_eq "test13: --verify --json exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local row_status row_detail row_owner
  row_status="$(printf '%s' "$verify_out" | jq -r '.checks[] | select(.check == "ecosystem-file") | .status')"
  row_detail="$(printf '%s' "$verify_out" | jq -r '.checks[] | select(.check == "ecosystem-file") | .detail')"
  row_owner="$(printf '%s' "$verify_out" | jq -r '.checks[] | select(.check == "ecosystem-file") | .owner')"

  assert_eq "test13: ecosystem-file renders fail while the PR is pending (never pass)" "fail" "$row_status"
  assert_contains "test13: detail names the pending pull request" "$row_detail" "Pull request #1"
  assert_contains "test13: detail says review and merge, not \"nothing done\"" "$row_detail" "review and merge"
  assert_eq "test13: fail is owned by Admin" "Admin" "$row_owner"

  local must_fix
  must_fix="$(printf '%s' "$verify_out" | jq -r '.summary.must_fix')"
  assert_eq "test13: the pending-PR row counts toward must_fix" "1" "$must_fix"

  local verify_mutating
  verify_mutating="$(count_mutating_calls "$verify_log")"
  assert_eq "test13: --verify makes zero mutating calls even to check for the pending PR" "0" "$verify_mutating"
}

# ---------------------------------------------------------------------------
# Test 14: the foundation-pin caret range resolves to the highest matching
# tag, excluding a higher-major tag outside the range.
# ---------------------------------------------------------------------------

test_foundation_pin_resolves_highest_matching_tag() {
  local st brief log
  st="$(new_org_state semver-highest)"
  mkdir -p "$st/tags/Everyone-Needs-A-Copilot"
  cat > "$st/tags/Everyone-Needs-A-Copilot/codex-copilot" <<'EOF'
v5.12.0
v5.13.0
5.13.2
v5.13.5
v5.13.10
v6.0.0
not-a-version
v5.13.0-rc1
EOF
  brief="$WORKDIR/brief-semver-highest.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log="$WORKDIR/semver-highest-setup.log"

  run_engine "$st" "$log" --brief "$brief"
  assert_eq "test14: setup run (fixture) exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local verify_log verify_out
  verify_log="$WORKDIR/semver-highest-verify.log"
  run_engine "$st" "$verify_log" --verify --brief "$brief" --json
  verify_out="$RUN_STDOUT"

  local row_status row_detail
  row_status="$(printf '%s' "$verify_out" | jq -r '.checks[] | select(.check == "foundation-pin") | .status')"
  row_detail="$(printf '%s' "$verify_out" | jq -r '.checks[] | select(.check == "foundation-pin") | .detail')"

  assert_eq "test14: foundation-pin resolves to pass" "pass" "$row_status"
  assert_contains "test14: detail names the highest satisfying tag, excluding the higher-major v6.0.0" "$row_detail" "v5.13.10"

  local tags_call_count paginate_recorded
  tags_call_count="$(count_calls "$verify_log" '^GET$' '^repos/Everyone-Needs-A-Copilot/codex-copilot/tags$')"
  assert_eq "test14: reads the foundation's tags exactly once" "1" "$tags_call_count"

  paginate_recorded="$(awk -F'\t' '$2 == "repos/Everyone-Needs-A-Copilot/codex-copilot/tags" {print $3}' "$verify_log")"
  assert_contains "test14: the tags read requests full pagination" "$paginate_recorded" "paginate=true"
}

# ---------------------------------------------------------------------------
# Test 15: no fixture tag satisfies the range — foundation-pin fails, owned
# by ENAC/external.
# ---------------------------------------------------------------------------

test_foundation_pin_no_match_fails() {
  local st brief log
  st="$(new_org_state semver-no-match)"
  mkdir -p "$st/tags/Everyone-Needs-A-Copilot"
  cat > "$st/tags/Everyone-Needs-A-Copilot/codex-copilot" <<'EOF'
v4.9.0
v4.10.0
v6.0.0
EOF
  brief="$WORKDIR/brief-semver-no-match.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log="$WORKDIR/semver-no-match-setup.log"

  run_engine "$st" "$log" --brief "$brief"
  assert_eq "test15: setup run (fixture) exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local verify_log verify_out
  verify_log="$WORKDIR/semver-no-match-verify.log"
  run_engine "$st" "$verify_log" --verify --brief "$brief" --json
  verify_out="$RUN_STDOUT"

  local row_status row_owner
  row_status="$(printf '%s' "$verify_out" | jq -r '.checks[] | select(.check == "foundation-pin") | .status')"
  row_owner="$(printf '%s' "$verify_out" | jq -r '.checks[] | select(.check == "foundation-pin") | .owner')"

  assert_eq "test15: no tag satisfies the range, so foundation-pin fails" "fail" "$row_status"
  assert_eq "test15: fail is owned by ENAC/external" "ENAC/external" "$row_owner"

  local must_fix
  must_fix="$(printf '%s' "$verify_out" | jq -r '.summary.must_fix')"
  assert_eq "test15: the no-match row counts toward must_fix" "1" "$must_fix"
}

# ---------------------------------------------------------------------------
# Test 16: an injected read failure on the tags endpoint renders unknown,
# never pass and never fail (fail-closed rule, §3.2).
# ---------------------------------------------------------------------------

test_foundation_pin_injected_error_unknown() {
  local st brief log
  st="$(new_org_state semver-error)"
  mkdir -p "$st/tags/Everyone-Needs-A-Copilot"
  printf 'v5.13.0\n' > "$st/tags/Everyone-Needs-A-Copilot/codex-copilot"
  mkdir -p "$st/inject-error"
  touch "$st/inject-error/repos__Everyone-Needs-A-Copilot__codex-copilot__tags"
  brief="$WORKDIR/brief-semver-error.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log="$WORKDIR/semver-error-setup.log"

  run_engine "$st" "$log" --brief "$brief"
  assert_eq "test16: setup run (fixture) exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local verify_log verify_out
  verify_log="$WORKDIR/semver-error-verify.log"
  run_engine "$st" "$verify_log" --verify --brief "$brief" --json
  verify_out="$RUN_STDOUT"

  local row_status
  row_status="$(printf '%s' "$verify_out" | jq -r '.checks[] | select(.check == "foundation-pin") | .status')"
  assert_eq "test16: an unreadable tags endpoint renders unknown, never pass or fail" "unknown" "$row_status"

  local verify_mutating
  verify_mutating="$(count_mutating_calls "$verify_log")"
  assert_eq "test16: verify still makes zero mutating calls" "0" "$verify_mutating"
}

# ---------------------------------------------------------------------------
# Test 17: pushing new content to an already-open PR's stale branch narrates
# `updated` (a real commit landed), never `already-present` — and reuses the
# existing branch/PR (no duplicate branch, no duplicate PR).
# ---------------------------------------------------------------------------

test_stale_branch_content_gets_updated_not_already_present() {
  local st brief1 brief2 log1 log2
  st="$(new_org_state content-stale-update)"
  seed_content_bearing_repo "$st" acme-co codex-copilot

  brief1="$WORKDIR/brief-stale-update-1.md"
  cat > "$brief1" <<'EOF'
---
schema_version: "1.0"
org: acme-co
harness:
  - codex
departments:
  - accounting
store:
  status: deferred
contacts:
  admin: "Earl P."
---

# Standup brief for acme-co (stale-branch-update fixture, round 1)
EOF

  brief2="$WORKDIR/brief-stale-update-2.md"
  cat > "$brief2" <<'EOF'
---
schema_version: "1.0"
org: acme-co
harness:
  - codex
departments:
  - accounting
  - sales
store:
  status: deferred
contacts:
  admin: "Earl P."
---

# Standup brief for acme-co (stale-branch-update fixture, round 2: adds sales)
EOF

  log1="$WORKDIR/content-stale-update-1.log"
  log2="$WORKDIR/content-stale-update-2.log"

  run_engine "$st" "$log1" --brief "$brief1"
  assert_eq "test17: first run (accounting only) exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local first_eco_result
  first_eco_result="$(printf '%s\n' "$RUN_STDOUT" | jq -r 'select(.step == "ecosystem-yml") | .result')"
  assert_eq "test17: first run opens the pull request (created)" "created" "$first_eco_result"

  run_engine "$st" "$log2" --brief "$brief2"
  assert_eq "test17: second run (adds sales) exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"

  local eco_step_result eco_step_detail
  eco_step_result="$(printf '%s\n' "$RUN_STDOUT" | jq -r 'select(.step == "ecosystem-yml") | .result')"
  eco_step_detail="$(printf '%s\n' "$RUN_STDOUT" | jq -r 'select(.step == "ecosystem-yml") | .detail')"
  assert_eq "test17: pushing new content to an open PR's stale branch narrates updated" "updated" "$eco_step_result"
  assert_contains "test17: updated detail names the existing pull request" "$eco_step_detail" "#1"

  local branch_push_count branch_create_count pr_create_count
  branch_push_count="$(count_calls_with_field "$log2" '^PUT$' '^repos/acme-co/codex-copilot/contents/ecosystem\.yml$' 'branch=copilot-standup')"
  branch_create_count="$(count_calls "$log2" '^POST$' '^repos/acme-co/codex-copilot/git/refs$')"
  pr_create_count="$(count_calls "$log2" '^POST$' '^repos/acme-co/codex-copilot/pulls$')"

  assert_eq "test17: exactly one new commit is pushed to the existing branch" "1" "$branch_push_count"
  assert_eq "test17: no new branch is created (it already exists)" "0" "$branch_create_count"
  assert_eq "test17: no new pull request is opened (the existing one is reused)" "0" "$pr_create_count"
}

# ---------------------------------------------------------------------------
# Test 18: no emitted string (a full run's NDJSON stream, or --verify's JSON)
# ever contains an em-dash — operator/GitHub-facing copy uses periods,
# commas, and colons only.
# ---------------------------------------------------------------------------

test_no_em_dash_in_emitted_output() {
  local st brief log
  st="$(new_org_state no-em-dash)"
  seed_content_bearing_repo "$st" acme-co codex-copilot
  brief="$WORKDIR/brief-no-em-dash.md"
  write_brief "$brief" "$STORE_CONNECTED"
  log="$WORKDIR/no-em-dash-run.log"

  run_engine "$st" "$log" --brief "$brief"
  assert_eq "test18: full run exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"
  local run_output="$RUN_STDOUT"
  assert_true "test18: full run's NDJSON stream contains no em-dash" \
    "$(no_em_dash "$run_output"; echo $?)" "$run_output"

  local verify_log verify_out
  verify_log="$WORKDIR/no-em-dash-verify.log"
  run_engine "$st" "$verify_log" --verify --brief "$brief" --json
  assert_eq "test18: --verify --json exits 0" "0" "$RUN_EXIT" "$RUN_STDERR"
  verify_out="$RUN_STDOUT"
  assert_true "test18: verify's JSON output contains no em-dash" \
    "$(no_em_dash "$verify_out"; echo $?)" "$verify_out"
}

# ---------------------------------------------------------------------------
# Test 19: a free-plan org's HTTP 403 on branch protection (private-repo
# review protection is a paid-only GitHub feature) completes the run instead
# of halting it — the step renders skipped with the canonical detail.
# ---------------------------------------------------------------------------

test_free_plan_branch_protection_403_skips_gracefully() {
  local st brief log
  st="$(new_org_state free-plan-403)"
  brief="$WORKDIR/brief-free-plan-403.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log="$WORKDIR/free-plan-403.log"

  mkdir -p "$st/inject-error"
  printf '403' > "$st/inject-error/PUT__repos__acme-co__codex-copilot__branches__main__protection"

  run_engine "$st" "$log" --brief "$brief"

  assert_eq "test19: a free-plan 403 on branch protection still completes the run" "0" "$RUN_EXIT" "$RUN_STDERR"

  local step_result step_detail
  step_result="$(printf '%s\n' "$RUN_STDOUT" | jq -r 'select(.step == "branch-protection:codex-copilot") | .result')"
  step_detail="$(printf '%s\n' "$RUN_STDOUT" | jq -r 'select(.step == "branch-protection:codex-copilot") | .detail')"

  assert_eq "test19: the protection step renders skipped, not failed" "skipped" "$step_result"
  assert_eq "test19: the skipped detail is the canonical free-plan message, verbatim" \
    "Review protection needs a paid GitHub plan for private repositories. Your spaces are set up. Upgrade the plan and run setup again to add it." \
    "$step_detail"
}

# ---------------------------------------------------------------------------
# Test 20: a NON-403 error on the same branch-protection PUT still halts the
# run — proves the 403 leniency didn't over-broaden to every failure.
# ---------------------------------------------------------------------------

test_non_403_branch_protection_error_still_fails() {
  local st brief log
  st="$(new_org_state free-plan-500)"
  brief="$WORKDIR/brief-free-plan-500.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log="$WORKDIR/free-plan-500.log"

  mkdir -p "$st/inject-error"
  touch "$st/inject-error/PUT__repos__acme-co__codex-copilot__branches__main__protection"

  run_engine "$st" "$log" --brief "$brief"

  assert_eq "test20: a non-403 branch-protection error still halts the run" "1" "$RUN_EXIT"
  assert_contains "test20: stdout carries a failed branch-protection step" "$RUN_STDOUT" '"step":"branch-protection:codex-copilot","result":"failed"'
}

# ---------------------------------------------------------------------------
# Test 21: the engine, invoked by absolute path with an absolute --brief path,
# completes correctly from a cwd entirely outside the repository. This is the
# shape Control Tower's materialized skill actually runs in: the operator's
# `claude "/admin-bootstrap ..."` session has cwd = wherever their terminal
# was (their home directory, never this repo). No earlier test in this suite
# exercised that layer; every other test's cwd is implicitly the repo tree.
# ---------------------------------------------------------------------------

test_engine_runs_cwd_independent_from_outside_repo() {
  local st brief log scratch_cwd out err rc verify_out verify_err

  st="$(new_org_state cwd-independent)"
  brief="$WORKDIR/brief-cwd-independent.md"
  write_brief "$brief" "$STORE_DEFERRED"
  log="$WORKDIR/cwd-independent-verify.log"
  : > "$log"

  scratch_cwd="$(mktemp -d "${TMPDIR:-/tmp}/admin-bootstrap-cwd-independent.XXXXXX")"

  # Sanity: the scratch cwd really is outside the repository, so a future
  # refactor can't make this pass by accident.
  case "$scratch_cwd" in
    "$REPO_ROOT"*)
      not_ok "test21: scratch cwd setup" "scratch cwd [$scratch_cwd] is inside the repo [$REPO_ROOT]"
      rm -rf "$scratch_cwd"
      return
      ;;
  esac

  out="$WORKDIR/cwd-independent.out"
  err="$WORKDIR/cwd-independent.err"
  (
    cd "$scratch_cwd" || exit 99
    # $ENGINE and $brief are both absolute (see their construction above);
    # $MOCK_BIN is already on PATH from the top of this file, so the mock
    # `gh` still resolves correctly from this unrelated cwd too.
    GH_MOCK_STATE_DIR="$st" GH_MOCK_LOG="$log" bash "$ENGINE" --verify --brief "$brief" --json
  ) >"$out" 2>"$err"
  rc=$?
  verify_out="$(cat "$out")"
  verify_err="$(cat "$err")"
  rm -rf "$scratch_cwd"

  assert_eq "test21: --verify --json exits 0 from a non-repo cwd (absolute engine + brief paths)" "0" "$rc" "$verify_err"

  local is_valid_json=1
  if echo "$verify_out" | jq -e . >/dev/null 2>&1; then is_valid_json=0; fi
  assert_true "test21: output from a non-repo cwd is still valid JSON" "$is_valid_json" "$verify_out"

  local schema_ok=1
  if echo "$verify_out" | jq -e '
      (.schema_version | type == "string") and
      (.checks | type == "array") and
      (.checks | length > 0) and
      (.summary.must_fix | type == "number") and
      (.summary.unknown | type == "number")
    ' >/dev/null 2>&1; then
    schema_ok=0
  fi
  assert_true "test21: schema still matches when run from a non-repo cwd" "$schema_ok" "$verify_out"

  local verify_mutating
  verify_mutating="$(count_mutating_calls "$log")"
  assert_eq "test21: --verify from a non-repo cwd makes zero mutating calls" "0" "$verify_mutating"
}

# ---------------------------------------------------------------------------
# Test 22: GitHub's real org-name rule allows uppercase (the live-org bug:
# github.com/Acme-Copilot). The org is an EXISTING GitHub identifier this
# engine must never transform, so its real, mixed-case login is used
# verbatim in every repo/team path, never lowercased.
# ---------------------------------------------------------------------------

test_org_verbatim_mixed_case_accepted() {
  local st brief log
  st="$WORKDIR/state-mixed-case-org"
  rm -rf "$st"
  mkdir -p "$st/orgs/Acme-Copilot"
  echo "earladmin" > "$st/user_login"
  echo "repo, admin:org, read:org" > "$st/user_scopes"
  echo "admin" > "$st/orgs/Acme-Copilot/membership_earladmin"
  echo "admin" > "$st/orgs/Acme-Copilot/default_permission"
  mkdir -p "$st/tags/Everyone-Needs-A-Copilot"
  printf 'v5.13.0\n' > "$st/tags/Everyone-Needs-A-Copilot/codex-copilot"

  brief="$WORKDIR/brief-mixed-case-org.md"
  cat > "$brief" <<'EOF'
---
schema_version: "1.0"
org: Acme-Copilot
harness:
  - codex
departments:
  - accounting
store:
  status: deferred
contacts:
  admin: "Earl P."
---

# Standup brief for Acme-Copilot (mixed-case org fixture)
EOF
  log="$WORKDIR/mixed-case-org.log"

  run_engine "$st" "$log" --brief "$brief"
  assert_eq "test22: a mixed-case org name (Acme-Copilot) is accepted" "0" "$RUN_EXIT" "$RUN_STDERR"

  local repo_count_verbatim repo_count_lowercased team_count_verbatim
  repo_count_verbatim="$(count_calls "$log" '^POST$' '^orgs/Acme-Copilot/repos$')"
  repo_count_lowercased="$(count_calls "$log" '^POST$' '^orgs/acme-copilot/repos$')"
  team_count_verbatim="$(count_calls "$log" '^POST$' '^orgs/Acme-Copilot/teams$')"

  assert_true "test22: at least one repo is created under the verbatim org path" \
    "$([[ "$repo_count_verbatim" -gt 0 ]]; echo $?)" "count=$repo_count_verbatim"
  assert_eq "test22: no repo is ever created under a lowercased org path" "0" "$repo_count_lowercased"
  assert_true "test22: the department team is created under the verbatim org path" \
    "$([[ "$team_count_verbatim" -gt 0 ]]; echo $?)" "count=$team_count_verbatim"
  assert_contains "test22: the created harness repo is reported under the verbatim path" "$RUN_STDOUT" "Created Acme-Copilot/codex-copilot, private."
  assert_contains "test22: the created department repo is reported under the verbatim path" "$RUN_STDOUT" "Created Acme-Copilot/codex-copilot-accounting, private."
}

# ---------------------------------------------------------------------------
# Test 23: every shape GitHub's real org-name rule actually rejects still
# refuses at preflight, with zero mutating calls.
# ---------------------------------------------------------------------------

test_invalid_org_values_refuse_at_preflight() {
  local bad_orgs=("-acme" "acme-" "ac--me" "acme copilot" "acme@x" "$(printf 'a%.0s' $(seq 1 40))")
  local i=0 bad_org
  for bad_org in "${bad_orgs[@]}"; do
    i=$((i + 1))
    local st brief log
    st="$(new_org_state "bad-org-$i")"
    brief="$WORKDIR/brief-bad-org-$i.md"
    cat > "$brief" <<EOF
---
schema_version: "1.0"
org: $bad_org
harness:
  - codex
departments:
  - accounting
store:
  status: deferred
contacts:
  admin: "Earl P."
---

# Standup brief for an invalid org fixture (case $i)
EOF
    log="$WORKDIR/bad-org-$i.log"

    run_engine "$st" "$log" --brief "$brief"

    assert_eq "test23: org #$i (\"$bad_org\") is refused (exit 2)" "2" "$RUN_EXIT"
    assert_contains "test23: org #$i refusal names the rule" "$RUN_STDERR" "That doesn't look like a GitHub organization name."

    local mutating
    mutating="$(count_mutating_calls "$log")"
    assert_eq "test23: org #$i refusal makes zero mutating calls" "0" "$mutating"
  done
}

# ---------------------------------------------------------------------------
# Test 24: departments still enforce the strict lowercase slug rule,
# unchanged — an uppercase-only department (no other invalid character)
# still refuses, proving the org fix didn't loosen department validation.
# ---------------------------------------------------------------------------

test_department_case_only_still_refuses() {
  local st brief log
  st="$(new_org_state dept-case-only)"
  brief="$WORKDIR/brief-dept-case-only.md"
  cat > "$brief" <<'EOF'
---
schema_version: "1.0"
org: acme-co
harness:
  - codex
departments:
  - Accounting
store:
  status: deferred
contacts:
  admin: "Earl P."
---

# Standup brief for acme-co (department case-only fixture: uppercase, otherwise valid)
EOF
  log="$WORKDIR/dept-case-only.log"

  run_engine "$st" "$log" --brief "$brief"

  assert_eq "test24: an uppercase-only department (Accounting) still refuses" "2" "$RUN_EXIT"
  assert_contains "test24: stderr names the offending department value" "$RUN_STDERR" 'Department name "Accounting"'

  local mutating
  mutating="$(count_mutating_calls "$log")"
  assert_eq "test24: zero mutating calls before the refusal" "0" "$mutating"
}

# ---------------------------------------------------------------------------
# Run everything
# ---------------------------------------------------------------------------

test_fresh_standup_full_matrix
test_full_rerun_is_noop
test_missing_scope_refuses
test_leak_scan_blocks_before_push
test_verify_json_schema
test_add_existing_department_is_noop
test_invalid_department_slug_refuses
test_invalid_org_slug_refuses
test_injected_read_failure_surfaces_honestly
test_content_bearing_repo_opens_pr
test_content_bearing_rerun_is_noop
test_leak_scan_blocks_branch_push
test_verify_renders_pending_pr
test_foundation_pin_resolves_highest_matching_tag
test_foundation_pin_no_match_fails
test_foundation_pin_injected_error_unknown
test_stale_branch_content_gets_updated_not_already_present
test_no_em_dash_in_emitted_output
test_free_plan_branch_protection_403_skips_gracefully
test_non_403_branch_protection_error_still_fails
test_engine_runs_cwd_independent_from_outside_repo
test_org_verbatim_mixed_case_accepted
test_invalid_org_values_refuse_at_preflight
test_department_case_only_still_refuses

echo
echo "-----------------------------------------"
echo "admin_bootstrap tests: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  echo "Failed:"
  for name in "${FAILED_NAMES[@]}"; do
    echo "  - $name"
  done
  exit 1
fi
exit 0
