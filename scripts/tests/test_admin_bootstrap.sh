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
new_org_state() {
  local st="$WORKDIR/state-$1"
  rm -rf "$st"
  mkdir -p "$st/orgs/acme-co"
  echo "earladmin" > "$st/user_login"
  echo "repo, admin:org, read:org" > "$st/user_scopes"
  echo "admin" > "$st/orgs/acme-co/membership_earladmin"
  echo "admin" > "$st/orgs/acme-co/default_permission"
  printf '%s' "$st"
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
  assert_contains "test8: stderr names the offending organization value" "$RUN_STDERR" 'Organization name "Acme Co!"'
  assert_contains "test8: stderr suggests letters, numbers, and dashes" "$RUN_STDERR" "letters, numbers, and dashes"

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
