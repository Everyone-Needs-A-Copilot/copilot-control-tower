#!/usr/bin/env bash
# smoke-scenarios.sh — the full SELFTEST scenario matrix (S1..S21) for both
# native binaries, driven entirely by the mock CLI
# (`src-tauri/fixtures/mock-cc`) and the SELFTEST contract:
#
#   CT_SELFTEST=1                       -> prints `SELFTEST badge=<...>
#                                           sentence=<...>`, optionally
#                                           `SELFTEST recently=<...>` (when
#                                           CT_FIXTURE is a projects fixture)
#                                           and `SELFTEST firstRun=<bool>`,
#                                           then exits 0.
#   CT_SELFTEST=1 CT_OPEN_WIZARD=1       -> prints `SELFTEST
#                                           auth=<authorized|denied|expired|
#                                           pending> signedInAs=<login|none>`
#                                           (+ `SELFTEST departments=<...>`
#                                           when CT_SELFTEST_STEP=departments,
#                                           or `SELFTEST holding=<variant>
#                                           stage=<...> result=<...> code=<...>
#                                           message=<...>` when
#                                           CT_SELFTEST_STEP=holding — the
#                                           Detect->Holding transition,
#                                           `holding-copy-spec.md`),
#                                           exit 0.
#
# Each scenario prints its own PASS/FAIL lines; the suite exits non-zero if
# any assertion failed anywhere. Pass `--only <id>` to run a single scenario
# while debugging (e.g. `--only S15`, or `--only S17` to run both S17a/S17b).
#
# RESOLVED (integration phase): the SELFTEST contract, including first-run
# persistence, is implemented in native/*.swift. First-run state is NOT
# backed by `UserDefaults`/cfprefsd, though — on this OS cfprefsd resolves
# every preferences domain (`UserDefaults.standard`, `UserDefaults(suiteName:)`,
# and the `defaults(1)` CLI's domain-name form all included) against the real
# logged-in account's home directory via `getpwuid`, ignoring a launched
# process's `$HOME` environment override entirely (confirmed empirically
# during integration: `defaults write <domain> ...` under `HOME=<scratch>`
# still lands in the real account's `~/Library/Preferences`, never the
# scratch dir). That is fundamentally incompatible with this harness's
# per-scenario scratch-`HOME` isolation (S1/S2 below), so `native/models.swift`'s
# `LocalDefaults` deliberately bypasses cfprefsd: it reads the raw `HOME`
# environment variable (which DOES reflect this harness's override) and
# reads/writes a plain plist file directly at
# `$HOME/Library/Preferences/<CT_DEFAULTS_DOMAIN>.plist`. S2 below writes to
# that SAME file path directly (via `defaults write <explicit-path>`, whose
# literal-path form -- unlike its domain-name form -- does respect an
# explicit path under a scratch `HOME`), rather than `defaults write <domain>`.
#
# Owned by Builder-4. No resolution/sync/compute logic here (invariant #1) —
# this only shells out to the build scripts, the mock CLI, `defaults`, and
# the two compiled binaries, and asserts on their stdout/exit status.
#
# Usage:
#   scripts/tests/smoke-scenarios.sh
#   scripts/tests/smoke-scenarios.sh --only S15
#   scripts/tests/smoke-scenarios.sh --skip-build   # reuse binaries already built
#
# Env overrides:
#   CT_SMOKE_SCENARIO_TIMEOUT=<secs>   per-launch timeout (default: 30)
#   CT_DEFAULTS_DOMAIN=<domain>        LocalDefaults plist basename used by S2 (see above)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

MOCK_CC="${REPO_ROOT}/src-tauri/fixtures/mock-cc"
USER_BIN="${REPO_ROOT}/.copilot/control-tower-tray/Copilot Control Tower"
ADMIN_BIN="${REPO_ROOT}/.copilot/control-tower-admin/Copilot Control Tower (Admin)"
DEFAULT_TIMEOUT="${CT_SMOKE_SCENARIO_TIMEOUT:-30}"
CT_DEFAULTS_DOMAIN="${CT_DEFAULTS_DOMAIN:-com.everyoneneedsacopilot.controltower}"
LAYERS_AVAILABLE_FIXTURE="${REPO_ROOT}/src-tauri/fixtures/layers/corpus/available.json"

ONLY=""
SKIP_BUILD=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            if [[ $# -lt 2 ]]; then
                echo "FATAL: --only requires a scenario id (e.g. --only S15)" >&2
                exit 2
            fi
            ONLY="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        *)
            echo "FATAL: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

PASS_COUNT=0
FAIL_COUNT=0
LAST_OUTPUT=""
LAST_STATUS=0

# --- timeout helper ---------------------------------------------------
# Same portable fallback as smoke-launch.sh — see that file's header comment
# for the rationale (neither `timeout` nor `gtimeout` is guaranteed present
# on a stock macOS box; `perl` is). Duplicated here rather than factored into
# a shared lib file since this builder owns exactly these two scripts.
run_with_timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "${secs}" "$@"
        return $?
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "${secs}" "$@"
        return $?
    fi
    perl -e '
        my $secs = shift(@ARGV);
        my @cmd = @ARGV;
        my $pid = fork();
        die "fork failed: $!" unless defined $pid;
        if ($pid == 0) {
            exec(@cmd) or exit(127);
        }
        local $SIG{ALRM} = sub {
            kill("TERM", $pid);
            sleep(1);
            kill("KILL", $pid);
        };
        alarm($secs);
        waitpid($pid, 0);
        alarm(0);
        my $status = $?;
        if ($status == -1) { exit(127); }
        elsif ($status & 127) { exit(128 + ($status & 127)); }
        else { exit($status >> 8); }
    ' "${secs}" "$@"
}

# --- pass/fail bookkeeping ---------------------------------------------
pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS - $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL - $1" >&2
    if [[ -n "${2:-}" ]]; then
        printf '%s\n' "$2" | sed 's/^/    # /' >&2
    fi
}

should_run() {
    local id="$1"
    [[ -z "${ONLY}" ]] && return 0
    [[ "${id}" == "${ONLY}" ]] && return 0
    [[ "${ONLY}" == "S17" && "${id}" == S17* ]] && return 0
    return 1
}

fresh_home() {
    mktemp -d "${TMPDIR:-/tmp}/ct-smoke-scenario-home.XXXXXX"
}

# launch_selftest <binary> <timeout_secs> <home_dir> ENV=VAL ...
# Sets LAST_OUTPUT / LAST_STATUS.
launch_selftest() {
    local bin="$1" secs="$2" home="$3"; shift 3
    LAST_OUTPUT="$(run_with_timeout "${secs}" env HOME="${home}" "$@" "${bin}" 2>&1)"
    LAST_STATUS=$?
}

assert_exit_zero() {
    local desc="$1"
    if [[ "${LAST_STATUS}" -eq 0 ]]; then
        pass "${desc}: exit 0"
        return 0
    fi
    fail "${desc}: expected exit 0, got ${LAST_STATUS}" "${LAST_OUTPUT}"
    return 1
}

assert_contains() {
    local desc="$1" needle="$2"
    if grep -qF -- "${needle}" <<<"${LAST_OUTPUT}"; then
        pass "${desc}: output contains '${needle}'"
    else
        fail "${desc}: expected output to contain '${needle}'" "${LAST_OUTPUT}"
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2"
    if grep -qF -- "${needle}" <<<"${LAST_OUTPUT}"; then
        fail "${desc}: output must NOT contain '${needle}' but it did" "${LAST_OUTPUT}"
    else
        pass "${desc}: output does not contain '${needle}'"
    fi
}

# --- build gate ----------------------------------------------------------
if [[ "${SKIP_BUILD}" -eq 0 ]]; then
    echo "=== smoke-scenarios: building both binaries ==="
    if ! bash "${REPO_ROOT}/scripts/build-user.command" --build-only; then
        echo "FATAL: scripts/build-user.command --build-only did not exit 0" >&2
        exit 1
    fi
    echo "ok - scripts/build-user.command --build-only exits 0"
    if ! bash "${REPO_ROOT}/scripts/build-admin.command" --build-only; then
        echo "FATAL: scripts/build-admin.command --build-only did not exit 0" >&2
        exit 1
    fi
    echo "ok - scripts/build-admin.command --build-only exits 0"
    echo
fi

if [[ ! -x "${MOCK_CC}" ]]; then
    echo "FATAL: mock CLI not found or not executable at ${MOCK_CC}" >&2
    exit 1
fi

# ==========================================================================
# Scenarios S1/S2 — first-run persistence
# ==========================================================================

scenario_S1() {
    local id="S1"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=healthy-clean-fleet CT_SELFTEST=1
    rm -rf "${home}"
    assert_exit_zero "${id} fresh HOME"
    assert_contains "${id} fresh HOME" "SELFTEST firstRun=true"
}

scenario_S2() {
    local id="S2"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    # Plain file write, NOT `defaults write` (in either its domain-name or
    # explicit-path form): `defaults write <domain>` ignores $HOME entirely
    # on this OS (see this script's header comment), and empirically
    # `defaults write <path>` ALSO silently no-ops (exit 0, no file written)
    # when that path sits under `$TMPDIR` (`/var/folders/.../T/...`, this
    # harness's `fresh_home()`), even though the identical form works fine
    # under a plain `/tmp/...` path — an apparent cfprefsd/TMPDIR quirk, not
    # this script's bug. Writing the plist directly with a heredoc sidesteps
    # cfprefsd altogether and lands the SAME file `LocalDefaults`
    # (native/models.swift) reads, under this scenario's own scratch HOME.
    local plist_path="${home}/Library/Preferences/${CT_DEFAULTS_DOMAIN}.plist"
    mkdir -p "${home}/Library/Preferences"
    cat > "${plist_path}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ct.hasCompletedFirstRun</key>
	<true/>
</dict>
</plist>
PLIST
    if [[ ! -s "${plist_path}" ]]; then
        fail "${id} pre-write ct.hasCompletedFirstRun=true" "failed to write ${plist_path}"
        rm -rf "${home}"
        return
    fi
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=healthy-clean-fleet CT_SELFTEST=1
    rm -rf "${home}"
    assert_exit_zero "${id} HOME with ct.hasCompletedFirstRun=true"
    assert_contains "${id} HOME with ct.hasCompletedFirstRun=true" "SELFTEST firstRun=false"
}

# ==========================================================================
# Scenarios S3..S10 — doctor fixture -> badge (+ sentence) mapping
# ==========================================================================

badge_scenario() {
    local id="$1" fixture="$2" expected_badge="$3" expected_sentence="${4:-}"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE="${fixture}" CT_SELFTEST=1
    rm -rf "${home}"
    assert_exit_zero "${id} (${fixture})"
    assert_contains "${id} (${fixture})" "SELFTEST badge=${expected_badge}"
    if [[ -n "${expected_sentence}" ]]; then
        assert_contains "${id} (${fixture})" "${expected_sentence}"
    fi
}

scenario_S3()  { badge_scenario S3  healthy-clean-fleet               none       "Everything is set up."; }
scenario_S4()  { badge_scenario S4  needs-attention-codex-dept-fail   triangle; }
scenario_S5()  { badge_scenario S5  signed-out-claude-personal        key; }
scenario_S6()  { badge_scenario S6  offline                           cloudSlash; }
scenario_S7()  { badge_scenario S7  syncing-knowledge-org             ring; }
scenario_S8()  { badge_scenario S8  exit-2                            bang       "won't guess"; }
scenario_S9()  { badge_scenario S9  not-valid-json                    bang; }
scenario_S10() { badge_scenario S10 schema-version-above-max          bang; }

# ==========================================================================
# Scenarios S11..S14 — the wizard sign-in seam (CT_OPEN_WIZARD=1)
# ==========================================================================

auth_scenario() {
    local id="$1" auth_scenario_name="$2" expected_status="$3" expected_signed_in_as="${4:-}"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_AUTH_SCENARIO="${auth_scenario_name}" CT_OPEN_WIZARD=1 CT_SELFTEST=1
    rm -rf "${home}"
    assert_exit_zero "${id} (CT_AUTH_SCENARIO=${auth_scenario_name})"
    assert_contains "${id} (CT_AUTH_SCENARIO=${auth_scenario_name})" "SELFTEST auth=${expected_status}"
    if [[ -n "${expected_signed_in_as}" ]]; then
        assert_contains "${id} (CT_AUTH_SCENARIO=${auth_scenario_name})" "signedInAs=${expected_signed_in_as}"
    fi
}

scenario_S11() { auth_scenario S11 authorized authorized octocat; }
# S12: `pending` is the still-polling/interim state, not a failure — the
# SELFTEST contract requires the app's OWN polling to be bounded so the
# process still exits 0 (see contract note above); this scenario's job is
# to prove that bound exists, not to wait forever itself, hence the
# unchanged DEFAULT_TIMEOUT safety net rather than a longer one.
scenario_S12() { auth_scenario S12 pending pending; }
scenario_S13() { auth_scenario S13 denied denied; }

scenario_S14() {
    local id="S14"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_AUTH_SCENARIO=authorized-leaked-field-adversarial CT_OPEN_WIZARD=1 CT_SELFTEST=1
    rm -rf "${home}"
    assert_exit_zero "${id} (CT_AUTH_SCENARIO=authorized-leaked-field-adversarial)"
    assert_contains "${id} (CT_AUTH_SCENARIO=authorized-leaked-field-adversarial)" "SELFTEST auth=authorized"
    # No-secret gate (invariant #6 / fitness fn 2): the mock deliberately
    # leaks an `access_token` field on this ONE adversarial scenario; the
    # app's own stdout must never echo it or anything token-shaped back out.
    assert_not_contains "${id} no-secret gate" "access_token"
    assert_not_contains "${id} no-secret gate" "ghu_"
}

# ==========================================================================
# Scenario S15 — the managed/company departments step
# ==========================================================================

scenario_S15() {
    local id="S15"
    should_run "${id}" || return 0

    if [[ ! -f "${LAYERS_AVAILABLE_FIXTURE}" ]]; then
        fail "${id} departments" "fixture not found: ${LAYERS_AVAILABLE_FIXTURE}"
        return
    fi
    # Extract the first layer's `"id"` value without depending on jq/python3
    # being installed — the fixture corpus format is simple enough for a
    # single grep+sed pass (see src-tauri/fixtures/layers/README.md).
    local dept_id
    dept_id="$(grep -m1 '"id"' "${LAYERS_AVAILABLE_FIXTURE}" | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
    if [[ -z "${dept_id}" ]]; then
        fail "${id} departments" "could not extract a layer id from ${LAYERS_AVAILABLE_FIXTURE}"
        return
    fi

    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=available CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=departments
    rm -rf "${home}"
    assert_exit_zero "${id} departments (fixture layer id: ${dept_id})"
    assert_contains "${id} departments" "SELFTEST departments="
    assert_contains "${id} departments" "${dept_id}"
    # NOTE: the task spec also asks for "an available state" on this line;
    # no literal token for that state was specified anywhere in the SELFTEST
    # contract text, the layers.schema.json corpus, or render-state.swift as
    # of authoring, so this only asserts on the fixture's real id (per
    # available.json: entitled:true, joined:false) rather than guessing a
    # state-name string that might not match what the app actually emits.
}

# ==========================================================================
# Scenario S16 — the fan-out "recently updated" headline
# ==========================================================================

scenario_S16() {
    local id="S16"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=12-of-14-updated CT_SELFTEST=1
    rm -rf "${home}"
    assert_exit_zero "${id} (CT_FIXTURE=12-of-14-updated)"

    local recently_line
    recently_line="$(grep '^SELFTEST recently=' <<<"${LAST_OUTPUT}" || true)"
    if [[ -z "${recently_line}" ]]; then
        fail "${id} recently= line present" "no 'SELFTEST recently=' line found" && return
    fi
    pass "${id} recently= line present: ${recently_line}"
    if grep -qF "12" <<<"${recently_line}"; then
        pass "${id} recently= line contains '12'"
    else
        fail "${id} recently= line contains '12'" "${recently_line}"
    fi
}

# ==========================================================================
# Scenarios S18..S21 — the wizard's Detect->Holding transition
# (`holding-copy-spec.md`), CT_SELFTEST_STEP=holding
# ==========================================================================
#
# Drives `CliClient.shared.ecosystemOnboardPlan(...)` directly (same as the
# S11-S15 auth/departments scenarios above drive their own CLI seam) and
# asserts on `WizardSelftest`'s `SELFTEST holding=...` line, built from the
# SAME pure classifiers (`WizardModel.holdingInfo(forBlockedOnboard:origin:)`
# / `holdingInfo(for:origin:)`) the real wizard uses. At minimum this
# distinguishes H3 from H4 (the same `device-ssh` gate, discriminated only
# by the CLI's own `config`/`key` tokens — never by prose) and proves an
# `.exit2` failure's bound `code`/`message` actually reach the line (S20),
# not the "unknown"/dropped fallback every OTHER exit-2 fixture in this
# suite would produce. S21 additionally asserts on the `SELFTEST
# supportLines=...` line — `HoldingInfo.supportLines(_:)`'s own real
# output — proving a CLI-emitted EMPTY STRING (not omitted, not "unknown")
# is dropped from the support block instead of rendering a dangling bare
# label.

holding_scenario() {
    local id="$1" fixture="$2"; shift 2
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE="${fixture}" CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=holding
    rm -rf "${home}"
    assert_exit_zero "${id} (CT_FIXTURE=${fixture})"
    local assertion
    for assertion in "$@"; do
        assert_contains "${id} (CT_FIXTURE=${fixture})" "${assertion}"
    done
}

# S18 — H4: `device-ssh` blocked AND `config == "held"` (invariant #3
# working, the live-verified defect case this whole change fixes: an
# existing user-managed SSH alias is left alone, never overwritten).
scenario_S18() {
    holding_scenario S18 blocked-device-ssh-held \
        "holding=yours" \
        "stage=device-ssh" \
        "message=An existing GitHub SSH alias is user-managed; setup did not replace it."
}

# S19 — H3: the SAME gate (`device-ssh`) blocked, but NOT classified as
# held-for-you — the default fault variant, distinguished from S18 purely by
# the CLI's own `config`/`key` tokens on an otherwise identically-shaped
# report.
scenario_S19() {
    holding_scenario S19 blocked-device-ssh-fault \
        "holding=fault" \
        "stage=device-ssh"
}

# S20 — H6 via a genuine `.exit2(code:message:)`: proves the code/message
# CliClient decodes from the CLI's own error envelope are bound and reach
# the Holding support block, closing the exact defect named in the task
# (`.exit2`'s associated values computed and thrown away).
scenario_S20() {
    holding_scenario S20 exit2-onboard-unavailable \
        "holding=waitingOnOrg" \
        "code=onboard-unavailable" \
        "message=Could not reach GitHub to read the organization setup."
}

# S21 — the support block's empty-value guard (`holding-copy-spec.md` §5:
# "Never print `unknown`, `nil`, `n/a`, or an empty value... A missing line
# is honest; a fabricated one is not."). The CLI's exit-2 envelope here
# carries `code`/`message` as PRESENT BUT EMPTY strings (not omitted, not
# "unknown" — `CliClient`'s `ErrorEnvelope.code`/`.message` are plain
# non-optional `String`s, so `""` decodes straight through). Uses
# `assert_not_contains`, unlike S18-S20, and asserts against the
# `SELFTEST supportLines=` line (`WizardSelftest.printHoldingSelftestLine`),
# which is the ONLY SELFTEST line that actually calls
# `HoldingInfo.supportLines(_:)` — the function the real "Details for
# support" disclosure renders from, and the one this scenario is proving:
# omit the line entirely rather than print a dangling bare label like
# `Message: ` with nothing after it.
scenario_S21() {
    local id="S21" fixture="exit2-empty-fields"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE="${fixture}" CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=holding
    rm -rf "${home}"
    assert_exit_zero "${id} (CT_FIXTURE=${fixture})"
    assert_contains "${id} (CT_FIXTURE=${fixture})" "holding=unreadable"
    assert_contains "${id} (CT_FIXTURE=${fixture})" "SELFTEST supportLines="
    assert_contains "${id} (CT_FIXTURE=${fixture})" "Recorded:"
    assert_not_contains "${id} (CT_FIXTURE=${fixture})" "Code:"
    assert_not_contains "${id} (CT_FIXTURE=${fixture})" "Message:"
}

# ==========================================================================
# Scenario S17 — the User/Admin binary split
# ==========================================================================

scenario_S17a() {
    local id="S17a"
    should_run "${id}" || return 0
    if [[ ! -x "${USER_BIN}" ]]; then
        fail "${id} user binary exists" "not found/executable at ${USER_BIN}"
        return
    fi
    local hit=""
    if command -v strings >/dev/null 2>&1; then
        hit="$(strings "${USER_BIN}" | grep -F "AdminWindowController" || true)"
    elif command -v nm >/dev/null 2>&1; then
        hit="$(nm "${USER_BIN}" 2>/dev/null | grep -F "AdminWindowController" || true)"
    else
        fail "${id} user binary has no AdminWindowController reference" "neither 'strings' nor 'nm' is available on this machine"
        return
    fi
    if [[ -n "${hit}" ]]; then
        fail "${id} user binary must not reference AdminWindowController" "${hit}"
    else
        pass "${id} user binary has no AdminWindowController symbol/string"
    fi
}

scenario_S17b() {
    local id="S17b"
    should_run "${id}" || return 0
    if [[ ! -x "${ADMIN_BIN}" ]]; then
        fail "${id} admin binary exists" "not found/executable at ${ADMIN_BIN}"
        return
    fi
    local home; home="$(fresh_home)"
    # Deliberately no CT_SELFTEST here — this exercises the live Admin-window
    # open path (CT_OPEN_ADMIN=1), not the SELFTEST short-circuit, per the
    # task spec. Bounded to 3s; SIGTERM (our own timeout firing because the
    # app is still alive and well, running its event loop) is an ACCEPTED
    # outcome, not a failure — only a genuine crash signal fails this check.
    local output status
    output="$(run_with_timeout 3 env \
        HOME="${home}" \
        CT_CLI_PATH="${MOCK_CC}" \
        CT_OPEN_ADMIN=1 \
        "${ADMIN_BIN}" 2>&1)"
    status=$?
    rm -rf "${home}"

    case "${status}" in
        132|133|134|136|138|139)
            # SIGILL / SIGTRAP / SIGABRT / SIGFPE / SIGBUS / SIGSEGV
            fail "${id} admin binary (CT_OPEN_ADMIN=1) must not crash" "exit=${status} (crash signal $((status - 128))); output: ${output}"
            ;;
        *)
            pass "${id} admin binary (CT_OPEN_ADMIN=1) starts without crashing (exit=${status}; 143/137 = we stopped it after 3s because it was still running, 0 = it exited on its own)"
            ;;
    esac
}

# ==========================================================================
# Run
# ==========================================================================

echo "=== smoke-scenarios: running the SELFTEST scenario matrix ==="
if [[ -n "${ONLY}" ]]; then
    echo "(--only ${ONLY})"
fi
echo

scenario_S1
scenario_S2
scenario_S3
scenario_S4
scenario_S5
scenario_S6
scenario_S7
scenario_S8
scenario_S9
scenario_S10
scenario_S11
scenario_S12
scenario_S13
scenario_S14
scenario_S15
scenario_S16
scenario_S17a
scenario_S17b
scenario_S18
scenario_S19
scenario_S20
scenario_S21

echo
echo "=== smoke-scenarios: ${PASS_COUNT} passed, ${FAIL_COUNT} failed ==="
if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    echo "smoke-scenarios.sh: FAIL"
    exit 1
fi

echo "smoke-scenarios.sh: PASS"
exit 0
