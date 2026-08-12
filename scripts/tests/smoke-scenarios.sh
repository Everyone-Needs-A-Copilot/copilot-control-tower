#!/usr/bin/env bash
# smoke-scenarios.sh — the full SELFTEST scenario matrix (S1..S41) for both
# native binaries, driven entirely by the mock CLI
# (`src-tauri/fixtures/mock-cc`) and the SELFTEST contract:
#
#   CT_SELFTEST=1                       -> prints `SELFTEST badge=<...>
#                                           sentence=<...>`, optionally
#                                           `SELFTEST recently=<...>` (when
#                                           CT_FIXTURE is a projects fixture),
#                                           always `SELFTEST
#                                           permissionNeeded=<bool>
#                                           connectionOffer=<bool>` (Region
#                                           6's `permission-needed` prompt /
#                                           `connection-offer` notice,
#                                           `control-tower-copy-deck.md`
#                                           §1.8 — both derived live from the
#                                           SAME read-only `ecosystemOnboardPlan`
#                                           this hook's own `refresh()` call
#                                           makes), and `SELFTEST
#                                           firstRun=<bool>`, then exits 0.
#   CT_SELFTEST=1 CT_OPEN_WIZARD=1       -> prints `SELFTEST
#                                           auth=<authorized|denied|expired|
#                                           pending> signedInAs=<login|none>`
#                                           (+ `SELFTEST departments=<...>`
#                                           when CT_SELFTEST_STEP=departments,
#                                           or, when CT_SELFTEST_STEP=connections
#                                           (task 221 bridge stage C, step 6
#                                           "Your connections"): `SELFTEST
#                                           connectionsResult=<ok|
#                                           copilot-unavailable|
#                                           org-config-unavailable|unknown>
#                                           connections=<id>:<secret_state>,...`
#                                           on a successful decode, or exit 1
#                                           with `SELFTEST
#                                           connections=error(...)
#                                           missingVerb=<bool>` on a CLI-call
#                                           failure (an installed `cc` build
#                                           that predates the verb sets
#                                           missingVerb=true);
#                                           or, when CT_SELFTEST_STEP=holding
#                                           (the Detect->Holding transition
#                                           AND the "One question first"
#                                           offer, `control-tower-copy-deck.md`
#                                           §2.9/§2.2.1): `SELFTEST
#                                           askItems=<id>:<scope>,...
#                                           reviewItems=<...>`, `SELFTEST
#                                           componentIds=<...>`, then either
#                                           `SELFTEST holding=none
#                                           result=<...>` or `SELFTEST
#                                           holding=<variant> stage=<...>
#                                           result=<...> code=<...>
#                                           message=<...>`; or, when
#                                           CT_SELFTEST_STEP=completion-rule,
#                                           `SELFTEST completionRule
#                                           full=<bool> missingStage=<bool>
#                                           blockedStage=<bool>
#                                           blockedResult=<bool>
#                                           claudeOnlyNoCodex=<bool>`; or, when
#                                           CT_SELFTEST_STEP=org-question (the
#                                           organization question,
#                                           `control-tower-copy-deck.md`
#                                           §2.1.1/Appendix E): `SELFTEST
#                                           orgNormalize=<pass,...>` and
#                                           `SELFTEST orgValidate=<pass,...>`
#                                           (the pure paste-normalization/
#                                           validation examples), then
#                                           `SELFTEST orgPhase=<...>` for
#                                           where a real WizardModel landed
#                                           right after `getStarted()`, then
#                                           (only if it landed on the
#                                           organization screen) `SELFTEST
#                                           orgSubmitResult=<...>` for where
#                                           typing "Acme-Co" and submitting
#                                           landed, then (only on a
#                                           `no-company-app` hold) `SELFTEST
#                                           orgUseADifferentOrg phase=<...>
#                                           field=<...>`; or, when
#                                           CT_SELFTEST_STEP=auth-reuse,
#                                           `SELFTEST authReuse=<reused|
#                                           deviceFlow|holding>`), exit 0.
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

# A genuine `CliClient` call failure inside a SELFTEST step (e.g. task 221's
# `CT_SELFTEST_STEP=connections`, verb-unavailable) exits the harness process
# with 1, same convention `WizardSelftest`'s departments step already uses —
# `assert_exit_zero` above only covers the (so far exclusively exercised)
# always-succeeds steps.
assert_exit_status() {
    local desc="$1" expected="$2"
    if [[ "${LAST_STATUS}" -eq "${expected}" ]]; then
        pass "${desc}: exit ${expected}"
        return 0
    fi
    fail "${desc}: expected exit ${expected}, got ${LAST_STATUS}" "${LAST_OUTPUT}"
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
    assert_contains "${id} (CT_AUTH_SCENARIO=${auth_scenario_name})" "SELFTEST ui=headless"
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
# Scenarios S18..S23 — the wizard's Detect->Holding transition and "One
# question first" offer (`control-tower-copy-deck.md` §2.9/§2.2.1),
# CT_SELFTEST_STEP=holding / CT_SELFTEST_STEP=completion-rule
# ==========================================================================
#
# Drives `CliClient.shared.ecosystemOnboardPlan(...)` directly (same as the
# S11-S15 auth/departments scenarios above drive their own CLI seam) and
# asserts on `WizardSelftest`'s printed lines, built from the SAME pure
# classifiers (`WizardModel.personalOnboardQuestion(from:)`,
# `WizardModel.componentId(fromPersonalInventoryId:)`,
# `WizardModel.holdingInfo(forBlockedOnboard:origin:)` /
# `holdingInfo(for:origin:)`) the real wizard uses. At minimum this
# distinguishes H3 from H4 from H7 (the same `device-ssh` gate,
# discriminated only by the CLI's own `config`/`key`/`registration`
# tokens — never by prose) and proves an `.exit2` failure's bound
# `code`/`message` actually reach the line (S20), not the "unknown"/dropped
# fallback every OTHER exit-2 fixture in this suite would produce. S21
# additionally asserts on the `SELFTEST supportLines=...` line —
# `HoldingInfo.supportLines(_:)`'s own real output — proving a CLI-emitted
# EMPTY STRING (not omitted, not "unknown") is dropped from the support
# block instead of rendering a dangling bare label.

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

# S18 — REWRITTEN. This used to assert that a `device-ssh` block was
# H4-and-correct for EVERY held cause, including the exact case this whole
# change fixes: an existing, WORKING, same-account SSH connection dead-ended
# setup instead of being offered as something to build on. That assertion
# was itself the bug, wearing a green checkmark ("invariant #3 working" was
# the wrong reading — see the task's own note). It now asserts the adopt
# OFFER renders instead: `device-ssh-adoptable` comes back
# `result: "changes-required"` (NEVER `"blocked"`), so `holding=none` is the
# right answer here, and the load-bearing assertions are on the ask-row
# line: a `device-ssh:machine` row must be present (Bug 1 — the dropped
# `scope == "machine"` filter used to drop this row silently) AND the
# consent-token mapping must round-trip `device-ssh` -> `ssh` (Bug 2 — the
# single highest-risk line in the whole change, because it fails silently).
scenario_S18() {
    holding_scenario S18 device-ssh-adoptable \
        "holding=none result=changes-required" \
        "SELFTEST askItems=device-ssh:machine reviewItems=none" \
        "SELFTEST componentIds=ssh,claude,codex,nil"
}

# S19 — H3: the SAME gate (`device-ssh`) blocked, but NOT classified as
# held-for-you — the default fault variant, distinguished from S18b below
# purely by the CLI's own `config`/`key` tokens on an otherwise
# identically-shaped report. Task 210/G-7 + task 211/G-4b: this fixture's
# own `completed_actions` ledger is deliberately EMPTY, so this also proves
# `retryable` stays `true` and the ORIGINAL clean-stop intro (the honest
# claim, when nothing really did change) still renders unmodified.
scenario_S19() {
    holding_scenario S19 blocked-device-ssh-fault \
        "holding=fault" \
        "stage=device-ssh" \
        "retryable=true completedActions=0" \
        "SELFTEST introLine=I couldn't give this Mac its own key, so I stopped. Nothing that was already here was changed."
}

# S18b — the genuinely-held case `Not now`/S18's dead end used to conflate
# with S19's fault: `config == "held"` (a real difference the CLI positively
# verified, e.g. a different GitHub login on the existing connection — one
# of the four causes the copy spec names: different login, wrong host, no
# repo access, malformed config; every one of those maps through this SAME
# `config == "held"` classifier, so this one fixture stands in for all
# four). This is the case that MUST still block — `held` stays the default
# whenever adoption isn't positively proven.
scenario_S18b() {
    holding_scenario S18b blocked-device-ssh-held \
        "holding=yours" \
        "stage=device-ssh" \
        "message=This Mac's existing GitHub connection signs in as a different account (other-account), so I left it exactly as it is."
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

# S21 — the support block's empty-value guard (§2.9.1: "Never print
# `unknown`, `nil`, `n/a`, or an empty value... A missing line is honest;
# a fabricated one is not."). The CLI's exit-2 envelope here carries
# `code`/`message` as PRESENT BUT EMPTY strings (not omitted, not
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

# S22 — H7: `registration == "not-permitted"` on the SAME `device-ssh` gate
# S18b/S19 exercise, discriminated purely by that one CLI-emitted token,
# checked BEFORE the `config == "held"` branch (Appendix D.2's own gate
# table order).
scenario_S22() {
    holding_scenario S22 device-ssh-not-permitted \
        "holding=needsPermission" \
        "stage=device-ssh" \
        "message=Your GitHub sign-in doesn't include permission to add this Mac's key."
}

# S23 — the completion rule (copy spec §2.10) as a pure predicate: five
# constructed cases, one per condition it must catch, PLUS the
# `codex-plugin`-excluded-when-declined case this implementation report
# flags as an extension beyond the spec's literal condition 3 (a fully
# successful claude-only run must still pass). This is the boolean every
# terminal confirmation (`Everything checks out.` / H4's `Keep what I have`)
# is gated on — proving it directly is the load-bearing test for "§2.10
# renders instead of a resolved-sounding confirmation", since no mechanism
# in this suite asserts against a rendered SwiftUI tree.
scenario_S23() {
    local id="S23"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=completion-rule
    rm -rf "${home}"
    assert_exit_zero "${id} (CT_SELFTEST_STEP=completion-rule)"
    assert_contains "${id}" "SELFTEST completionRule full=true missingStage=false blockedStage=false optionalDeferred=true requiredDeferred=false deferredNotYet=1 blockedResult=false claudeOnlyNoCodex=true"
}

# ==========================================================================
# Scenarios S24..S26 — Region 6's `permission-needed` prompt
# (`TrayModel.permissionNeededPending`, `control-tower-tray.swift`), driven
# through the SAME live, end-to-end `refresh()` path `badge_scenario` above
# already exercises (never an offline decode-only stub): the plain
# (non-wizard) CT_SELFTEST=1 hook calls `controller.model.refresh()` for
# real against the mock CLI, which now also prints the tray's own
# `permissionNeeded=`/`connectionOffer=` state, both derived from the SAME
# `device-ssh` stage the wizard's H7 gate (S22 above) and `connection-offer`
# notice already read — discriminated purely by the CLI's own
# `registration`/`config` enum tokens, never by prose.
# ==========================================================================

connection_prompt_scenario() {
    local id="$1" fixture="$2" expected_permission_needed="$3" expected_connection_offer="$4"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE="${fixture}" CT_SELFTEST=1
    rm -rf "${home}"
    assert_exit_zero "${id} (CT_FIXTURE=${fixture})"
    assert_contains "${id} (CT_FIXTURE=${fixture})" \
        "SELFTEST permissionNeeded=${expected_permission_needed} connectionOffer=${expected_connection_offer}"
}

# S24 — the prompt appears exactly when the CLI's own `registration` token
# reads `not-permitted` on the `device-ssh` stage (the SAME `device-ssh-not-permitted`
# fixture S22 uses for the wizard's own H7 screen).
scenario_S24() { connection_prompt_scenario S24 device-ssh-not-permitted true false; }

# S25 — the sibling case (`connection-offer`, already live): proves the two
# are mutually exclusive on this same stage, never both true at once, using
# the SAME `device-ssh-adoptable` fixture S18 uses for the wizard's own
# question screen.
scenario_S25() { connection_prompt_scenario S25 device-ssh-adoptable false true; }

# S26 — neither renders on a plan whose `device-ssh` stage carries neither
# carved-out token at all (`mock-cc`'s un-fixtured default `onboard` body,
# returned for any OTHER $CT_FIXTURE) — the "does not appear otherwise"
# half of the task this closes.
scenario_S26() { connection_prompt_scenario S26 healthy-clean-fleet false false; }

# ==========================================================================
# Scenarios S27..S29 — H6-vs-H7 asserts the right owner
# (`control-tower-copy-deck.md` §2.9/§2.9's H6 vs H7, `LocalAdminSignal`,
# `native/models.swift`/`native/wizard.swift`), the SAME `no-company-app`
# exit-2 code the real-world trigger names verbatim ("Your organization
# hasn't finished setting up sign-in yet"). `holding_scenario` (S18-S23
# above) always launches against a completely fresh, empty scratch `HOME`,
# so it can't seed a standup brief into it first — these three scenarios
# reimplement just enough of it to plant (or withhold) that file before
# launch. Proves the discriminator BOTH ways (S27: absent stays H6, never
# H7; S28: present-and-readable flips to H7, never H6) plus the honest
# fallback (S29: present but unreadable stays H6 too — never fabricate a
# fix from a half-answer) — a false positive on either side would tell a
# plain end user they're the admin, which is its own lie.
# ==========================================================================

# S27 — the real-world trigger's own end-user lane: no admin brief on this
# Mac at all, so `LocalAdminSignal.standupBriefExists` reads false and this
# stays the ordinary H6, never H7.
scenario_S27() {
    local id="S27"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=exit2-no-company-app CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=holding
    rm -rf "${home}"
    assert_exit_zero "${id} (no admin brief on this Mac)"
    assert_contains "${id} (no admin brief on this Mac)" "holding=waitingOnOrg"
    assert_contains "${id} (no admin brief on this Mac)" "code=no-company-app"
    assert_contains "${id} (no admin brief on this Mac)" "selfServeCommand=none"
    assert_not_contains "${id} (no admin brief on this Mac)" "holding=needsPermission"
}

# S28 — this Mac's own admin standup already ran here: both the brief and
# its non-secret JSON twin (`AdminPaths.briefPath`/`briefJSONPath`'s exact
# path) are present, and the JSON names the org's GitHub App client id — so
# this flips to H7, with the EXACT command read back verbatim, never a
# placeholder.
scenario_S28() {
    local id="S28"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    mkdir -p "${home}/Library/Application Support/CopilotControlTower"
    printf '%s\n' '# Fixture-only standup brief (S28). Presence alone is the signal this scenario exercises.' \
        > "${home}/Library/Application Support/CopilotControlTower/standup-brief.md"
    printf '%s\n' '{"schema_version":"1.0","org":"acme-co","github_app":{"client_id":"Iv1.a1b2c3d4e5f6a7b8"}}' \
        > "${home}/Library/Application Support/CopilotControlTower/standup-brief.json"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=exit2-no-company-app CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=holding
    rm -rf "${home}"
    assert_exit_zero "${id} (admin brief present, client id known)"
    assert_contains "${id} (admin brief present, client id known)" "holding=needsPermission"
    assert_contains "${id} (admin brief present, client id known)" "selfServeCommand=cc config set github_app.client_id Iv1.a1b2c3d4e5f6a7b8"
    assert_not_contains "${id} (admin brief present, client id known)" "holding=waitingOnOrg"
}

# S29 — the honest edge case: the brief exists (this Mac's admin standup DID
# run here) but its JSON twin carries no readable client id. Never fabricate
# a command from a half-answer — this must stay the ordinary H6, not a
# broken/placeholder H7.
scenario_S29() {
    local id="S29"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    mkdir -p "${home}/Library/Application Support/CopilotControlTower"
    printf '%s\n' '# Fixture-only standup brief (S29), incomplete on purpose.' \
        > "${home}/Library/Application Support/CopilotControlTower/standup-brief.md"
    printf '%s\n' '{"schema_version":"1.0","org":"acme-co"}' \
        > "${home}/Library/Application Support/CopilotControlTower/standup-brief.json"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=exit2-no-company-app CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=holding
    rm -rf "${home}"
    assert_exit_zero "${id} (admin brief present, client id NOT known)"
    assert_contains "${id} (admin brief present, client id NOT known)" "holding=waitingOnOrg"
    assert_contains "${id} (admin brief present, client id NOT known)" "selfServeCommand=none"
    assert_not_contains "${id} (admin brief present, client id NOT known)" "holding=needsPermission"
}

# ==========================================================================
# Scenarios S30..S37 — the organization question (`org-required` routing,
# `docs/03-design/control-tower-copy-deck.md` §2.1.1/Appendix E,
# `native/wizard.swift`'s `WizardModel.handleOrgRequired`/
# `handleConnectGitHubError`/`useADifferentOrganization`).
#
# `CT_SELFTEST_STEP=org-question` drives a REAL `WizardModel` instance
# through its own real entry points (`getStarted()`,
# `continueToSignInFromOrgQuestion()`, `useADifferentOrganization()`)
# against `mock-cc`'s four `org-required-then-*` auth scenarios — never a
# bespoke, potentially-drifted second reading of the routing table. S37
# is the "not vacuous the other way" proof (S27-S29's own discipline,
# applied here): an ordinary `authorized` scenario, where the CLI never
# asks for an organization at all, must never show this screen either.
# ==========================================================================

scenario_S30() {
    # Fresh Mac, no standup brief: asks first (empty field, first intro
    # variant), then a typed name that resolves reaches Connect GitHub's
    # ordinary code card — the whole "ask, then sign in" happy path.
    local id="S30"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_AUTH_SCENARIO=org-required-then-authorized CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=org-question
    rm -rf "${home}"
    assert_exit_zero "${id} (org-required-then-authorized)"
    assert_contains "${id}" "SELFTEST orgNormalize=pass,pass,pass,pass"
    assert_contains "${id}" "SELFTEST orgValidate=pass,pass,pass,pass"
    assert_contains "${id}" "SELFTEST orgPhase=orgQuestion prefill=none introNamesStandup=false"
    assert_contains "${id}" "SELFTEST orgSubmitResult=connectGitHub"
}

scenario_S31() {
    # `org-not-found`: stays on the screen, keeping what was typed, with the
    # under-field message naming it.
    local id="S31"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_AUTH_SCENARIO=org-required-then-not-found CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=org-question
    rm -rf "${home}"
    assert_exit_zero "${id} (org-required-then-not-found)"
    assert_contains "${id}" "SELFTEST orgSubmitResult=orgQuestion"
    assert_contains "${id}" "orgNotFoundMessage=I couldn't find Acme-Co on GitHub."
}

scenario_S32() {
    # `no-company-app`: lands on H6 carrying the value that led there
    # (`orgNameForReturn`), and `Use a different organization` returns to
    # the field populated with it — the escape from H6 this whole thing
    # exists to close (copy spec §5).
    local id="S32"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_AUTH_SCENARIO=org-required-then-no-company-app CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=org-question
    rm -rf "${home}"
    assert_exit_zero "${id} (org-required-then-no-company-app)"
    assert_contains "${id}" "SELFTEST orgSubmitResult=holding variant=waitingOnOrg orgNameForReturn=Acme-Co"
    assert_contains "${id}" "SELFTEST orgUseADifferentOrg phase=orgQuestion field=Acme-Co"
}

scenario_S33() {
    # `network-unavailable`: H5, offline — never told the fabricated
    # "hasn't finished setting up sign-in yet", and carries no return value
    # (H5 never offers `Use a different organization`).
    local id="S33"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_AUTH_SCENARIO=org-required-then-network-unavailable CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=org-question
    rm -rf "${home}"
    assert_exit_zero "${id} (org-required-then-network-unavailable)"
    assert_contains "${id}" "SELFTEST orgSubmitResult=holding variant=waitingOffline orgNameForReturn=none"
}

# S34/S35 — the admin's own Mac: a standup brief carrying `org` is tried
# SILENTLY (§5). S34 is the success case (no screen ever appears); S35 is
# the honest failure fallback (the screen appears, prefilled, naming where
# the value came from).
seed_standup_org_brief() {
    local home="$1" org="$2"
    mkdir -p "${home}/Library/Application Support/CopilotControlTower"
    printf '%s\n' "{\"org\":\"${org}\",\"github_app\":{\"client_id\":\"Iv1.a1b2c3d4e5f6a7b8\"}}" \
        > "${home}/Library/Application Support/CopilotControlTower/standup-brief.json"
}

scenario_S34() {
    local id="S34"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    seed_standup_org_brief "${home}" "Acme-Co"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_AUTH_SCENARIO=org-required-then-authorized CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=org-question
    rm -rf "${home}"
    assert_exit_zero "${id} (standup brief org resolves)"
    assert_contains "${id}" "SELFTEST orgPhase=connectGitHub"
    assert_not_contains "${id}" "orgPhase=orgQuestion"
}

scenario_S35() {
    local id="S35"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    seed_standup_org_brief "${home}" "Acme-Co"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_AUTH_SCENARIO=org-required-then-not-found CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=org-question
    rm -rf "${home}"
    assert_exit_zero "${id} (standup brief org fails silently, screen explains why)"
    assert_contains "${id}" "SELFTEST orgPhase=orgQuestion prefill=Acme-Co introNamesStandup=true"
}

scenario_S36() {
    # The pointer could not be written to this Mac: H2 with the existing
    # environment-error intro, verbatim (copy spec §2.1.1's own row) — never
    # silently claimed as a success.
    local id="S36"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_CONFIG_SET_FAILS=1 CT_AUTH_SCENARIO=org-required-then-authorized CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=org-question
    rm -rf "${home}"
    assert_exit_zero "${id} (cc config set fails)"
    assert_contains "${id}" "SELFTEST orgSubmitResult=holding variant=unreadable orgNameForReturn=none"
}

scenario_S37() {
    # Not vacuous the other way (S27-S29's own discipline): an ordinary
    # `authorized` scenario, where the CLI never asks for an organization at
    # all, must never show this screen either.
    local id="S37"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_AUTH_SCENARIO=authorized CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=org-question
    rm -rf "${home}"
    assert_exit_zero "${id} (CT_AUTH_SCENARIO=authorized, org never required)"
    assert_contains "${id}" "SELFTEST orgPhase=detect"
    assert_not_contains "${id}" "orgPhase=orgQuestion"
}

# ==========================================================================
# Scenarios S38..S41 — reuse the existing GitHub authorization
#
# These drive the REAL Welcome -> GitHub transition and pair its state with
# the mock CLI's exact argv audit trail. This catches both behavioral halves:
# an authorized Keychain-backed session skips `auth login`; a genuinely
# signed-out session still gets a device code. Unreadable status results hold
# fail-closed and must never be mistaken for signed-out.
# ==========================================================================

auth_reuse_scenario() {
    local id="$1" auth_scenario="$2" expected_state="$3"
    local home invocation_log
    home="$(fresh_home)"
    invocation_log="$(mktemp "${TMPDIR:-/tmp}/ct-auth-reuse-log.XXXXXX")"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_AUTH_SCENARIO="${auth_scenario}" \
        CT_MOCK_INVOCATION_LOG="${invocation_log}" \
        CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=auth-reuse
    LAST_OUTPUT="${LAST_OUTPUT}"$'\n'"SELFTEST invocationLog:"$'\n'"$(<"${invocation_log}")"
    rm -rf "${home}"
    rm -f "${invocation_log}"

    assert_exit_zero "${id} (${auth_scenario})"
    assert_contains "${id} (${auth_scenario})" "SELFTEST authReuse=${expected_state}"
    assert_contains "${id} (${auth_scenario})" "auth status --json"
}

scenario_S38() {
    should_run S38 || return 0
    auth_reuse_scenario S38 authorized reused
    assert_not_contains "S38 (authorized)" "auth login"
}

scenario_S39() {
    should_run S39 || return 0
    auth_reuse_scenario S39 pending deviceFlow
    assert_contains "S39 (signed-out)" "auth login --json"
}

scenario_S40() {
    should_run S40 || return 0
    auth_reuse_scenario S40 exit-2 holding
    assert_not_contains "S40 (status exit-2)" "auth login"
}

scenario_S41() {
    should_run S41 || return 0
    auth_reuse_scenario S41 status-not-valid-json holding
    assert_not_contains "S41 (malformed status)" "auth login"
}

# ==========================================================================
# Scenarios S42/S43 — task 210 (G-7): `Try again` renders ONLY when the CLI
# marks the block retryable; task 211 (G-4b): a "nothing changed" claim
# renders ONLY when this run's own `completed_actions` ledger is empty.
# Both derive strictly from the mock's own JSON (`resume.safe_to_rerun`,
# `result`, and per-row `action`/`sync_state`) via the SAME
# `WizardModel.holdingInfo(forBlockedOnboard:)` classifier S18-S23 already
# exercise — never string-matched, never a second UI-only reading.
# ==========================================================================

# S42 — the closed Git-history classifier (claude-copilot task 204) blocks
# on a `review`-action topology row (`codex-copilot-private` is `ahead`:
# local commits GitHub doesn't have). This is the exact shape `Try again`
# used to render for even though retrying can never change it — a Git
# problem, not a setup problem. Proves: `retryable=false` (so `h3View`
# never renders `Try again` for this block), the intro names the specific
# repository and its state instead of a generic "couldn't confirm this
# part of setup" line, and the non-empty ledger this run already completed
# (a created repo, a generated+registered SSH key) reaches the classifier.
scenario_S42() {
    holding_scenario S42 visible-repositories-review-blocked \
        "holding=fault" \
        "stage=visible-repositories" \
        "retryable=false completedActions=3" \
        "SELFTEST introLine=codex-copilot-private has local work the pinned version doesn't include. Resolve it in Git, then run setup again."
}

# S43 — the SAME H3 device-ssh fault S19 exercises, but THIS run's ledger
# is non-empty (a personal repository was already created before the
# block). Proves the honest replacement intro renders instead of the false
# "Nothing that was already here was changed." claim, while `retryable`
# stays `true` (an ordinary transient stage fault, unlike S42's Git-history
# block, is still worth another try).
scenario_S43() {
    holding_scenario S43 blocked-device-ssh-fault-with-ledger \
        "holding=fault" \
        "stage=device-ssh" \
        "retryable=true completedActions=1" \
        "SELFTEST introLine=I couldn't give this Mac its own key, so I stopped there."
}

# ==========================================================================
# Scenarios S44/S45 — task 221 bridge stage C: step 6 "Your connections"
# read data path (`connections()`), independent of Holding's own
# classifiers above. S44 proves a normal decode reaches the render layer
# (per-row `secret_state`, `needs-connect` naming its missing credentials).
# S45 proves the verb-unavailable degrade path (an installed `cc` build that
# predates this verb, e.g. the bundled 0.3.2 app's real `cc 2.1.2` helper —
# task 221's WP-388 trace) is classified honestly as a missing verb rather
# than silently swallowed or confused with a generic failure.
# ==========================================================================

scenario_S44() {
    local id="S44"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=ready-and-needs-connect CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=connections
    rm -rf "${home}"
    assert_exit_zero "${id} connections"
    assert_contains "${id} connections" "SELFTEST connectionsResult=ok"
    assert_contains "${id} connections" "git:ready"
    assert_contains "${id} connections" "infisical:needs-connect"
}

# `mock-cc CT_FIXTURE=verb-unavailable` reproduces the bundled helper's exact
# observed shape (exit 2, no readable body — src-tauri/fixtures/connections/README.md).
scenario_S45() {
    local id="S45"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=verb-unavailable CT_OPEN_WIZARD=1 CT_SELFTEST=1 CT_SELFTEST_STEP=connections
    rm -rf "${home}"
    assert_exit_status "${id} connections (verb-unavailable)" 1
    assert_contains "${id} connections (verb-unavailable)" "SELFTEST connections=error("
    assert_contains "${id} connections (verb-unavailable)" "missingVerb=true"
}

# ==========================================================================
# Scenarios S46/S47/S48 — task 222: the Connect sheet's CLI seam
# (`connect.schema.json`). S46 proves `--check` is genuinely read-only and
# decodes. S47 proves the whole write path end to end AND that the value only
# ever travelled on stdin — `mock-cc connect` compares every supplied value
# against its own argv and environment and exits 2 with a FATAL line if it
# finds one there, so a regression that starts passing a credential as an
# argument fails this scenario rather than shipping. S48 proves a partial
# failure stays honest: the envelope is still `ok`, and it is the ROW that
# reports the connection is not ready.
# ==========================================================================

scenario_S46() {
    local id="S46"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=ready-and-needs-connect CT_OPEN_WIZARD=1 CT_SELFTEST=1 \
        CT_SELFTEST_STEP=connect CT_SELFTEST_SERVICE=infisical
    rm -rf "${home}"
    assert_exit_zero "${id} connect --check"
    assert_contains "${id} connect --check" "connectResult=ok mode=check"
    assert_contains "${id} connect --check" "service=needs-connect"
    assert_contains "${id} connect --check" "credentials="
}

scenario_S47() {
    local id="S47"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=ready-and-needs-connect CT_OPEN_WIZARD=1 CT_SELFTEST=1 \
        CT_SELFTEST_STEP=connect CT_SELFTEST_SERVICE=infisical \
        CT_SELFTEST_CONNECT_VALUES='{"INFISICAL_CLIENT_ID":"fixture-id","INFISICAL_CLIENT_SECRET":"fixture-secret"}'
    rm -rf "${home}"
    assert_exit_zero "${id} connect (stdin write)"
    assert_contains "${id} connect (stdin write)" "connectResult=ok mode=connect"
    assert_contains "${id} connect (stdin write)" "service=ready"
    assert_contains "${id} connect (stdin write)" "INFISICAL_CLIENT_ID:stored"
    assert_contains "${id} connect (stdin write)" "INFISICAL_CLIENT_SECRET:stored"
    # The value itself must appear nowhere in anything this run printed.
    if [[ "${LAST_OUTPUT}" == *"fixture-secret"* ]]; then
        fail "${id} connect never echoes a value" "${LAST_OUTPUT}"
    else
        pass "${id} connect never echoes a value"
    fi
}

scenario_S48() {
    local id="S48"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=ready-and-needs-connect CT_OPEN_WIZARD=1 CT_SELFTEST=1 \
        CT_SELFTEST_STEP=connect CT_SELFTEST_SERVICE=infisical \
        CT_SELFTEST_CONNECT_VALUES='{"INFISICAL_CLIENT_ID":"fixture-id","INFISICAL_CLIENT_SECRET":"MOCK-KEYCHAIN-REFUSES"}'
    rm -rf "${home}"
    assert_exit_zero "${id} connect (partial failure)"
    assert_contains "${id} connect (partial failure)" "connectResult=ok mode=connect"
    assert_contains "${id} connect (partial failure)" "service=needs-connect"
    assert_contains "${id} connect (partial failure)" "INFISICAL_CLIENT_SECRET:failed"
}

scenario_S49() {
    local id="S49"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=verb-unavailable CT_OPEN_WIZARD=1 CT_SELFTEST=1 \
        CT_SELFTEST_STEP=connect CT_SELFTEST_SERVICE=infisical \
        CT_SELFTEST_CONNECT_VALUES='{"INFISICAL_CLIENT_ID":"fixture-id","INFISICAL_CLIENT_SECRET":"fixture-secret"}'
    rm -rf "${home}"
    # Every RELEASED build before this one bundles a helper with no `connect`
    # verb at all, so this is the state the first person to press the button
    # would actually hit if they had not updated. It must classify as a
    # too-old helper (which is what makes the sheet add the update hint),
    # never as a generic failure -- and it must still not echo the value.
    assert_exit_status "${id} connect (verb-unavailable)" 1
    assert_contains "${id} connect (verb-unavailable)" "connect=error("
    assert_contains "${id} connect (verb-unavailable)" "missingVerb=true"
    if [[ "${LAST_OUTPUT}" == *"fixture-secret"* ]]; then
        fail "${id} connect never echoes a value on failure" "${LAST_OUTPUT}"
    else
        pass "${id} connect never echoes a value on failure"
    fi
}

# S50 — `connect.schema.json`'s `invalid-input` result (task 222 P1-8). A
# malformed `CT_SELFTEST_CONNECT_VALUES` (not JSON at all) fails the harness's
# own `[String: String]` decode attempt, so it takes
# `CliClient.rawConnectForSelftest` instead of the ordinary typed
# `connect(values:)` — the one path that can send something other than a
# well-formed `{"NAME":"value"}` object on stdin, proving the app renders
# `invalid-input` rather than treating it as an ordinary CLI-unreadable
# failure. Still must never echo the bogus payload back.
scenario_S50() {
    local id="S50"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_FIXTURE=ready-and-needs-connect CT_OPEN_WIZARD=1 CT_SELFTEST=1 \
        CT_SELFTEST_STEP=connect CT_SELFTEST_SERVICE=infisical \
        CT_SELFTEST_CONNECT_VALUES='not-json-at-all'
    rm -rf "${home}"
    assert_exit_zero "${id} connect (invalid-input)"
    assert_contains "${id} connect (invalid-input)" "connectResult=invalid-input mode=connect"
    assert_contains "${id} connect (invalid-input)" "INFISICAL_CLIENT_ID:failed"
    if [[ "${LAST_OUTPUT}" == *"not-json-at-all"* ]]; then
        fail "${id} connect never echoes the malformed payload" "${LAST_OUTPUT}"
    else
        pass "${id} connect never echoes the malformed payload"
    fi
}

# S51 — Verify's support report preserves the typed check/update/check
# sequence while dropping every private sentinel carried by otherwise-valid
# DTO fields. The same selftest writes the report through the production
# no-follow store, proves 0600/0700 modes, and exercises retention at 20.
scenario_S51() {
    local id="S51"
    should_run "${id}" || return 0
    local home; home="$(fresh_home)"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_OPEN_WIZARD=1 CT_SELFTEST=1 \
        CT_SELFTEST_STEP=verify-support
    rm -rf "${home}"
    assert_exit_zero "${id} verify support report"
    assert_contains "${id} verify support report" \
        "verifySupport=saved privacySafe=true savedInitially=true fileMode=600 directoryMode=700 retained=20 scopeSafe=true"
    assert_contains "${id} verify support report" "Initial check|Result: update available"
    assert_contains "${id} verify support report" "Update attempt|Result: applied"
    assert_contains "${id} verify support report" "Changed: 1 · Held: 1 · Blocked: 1"
    assert_contains "${id} verify support report" "Fresh check|Result: update available"
    assert_contains "${id} verify support report" "Report format: not reported"
    assert_contains "${id} verify support report" \
        "Needs attention: Claude Copilot · Core setup · needs review"
    assert_contains "${id} future role stays neutral" \
        "Needs attention: Codex Copilot · Setup scope not recognized · needs review"
    assert_contains "${id} missing role stays neutral" \
        "Needs attention: CLI Copilot · Setup scope not recognized · needs attention"
    assert_not_contains "${id} future role is never personal" "Codex Copilot · This Mac"
    assert_not_contains "${id} missing role is never personal" "CLI Copilot · This Mac"
    assert_not_contains "${id} verify support report" "sentinel-private"
    assert_not_contains "${id} verify support report" "sentinel-secret-value"
    assert_not_contains "${id} verify support report" "/Users/"
}

# S52 — a symlink at the app-owned diagnostic leaf is a hard write refusal.
# The redacted in-memory report remains available for Copy, and the linked
# directory receives no file.
scenario_S52() {
    local id="S52"
    should_run "${id}" || return 0
    local home outside
    home="$(fresh_home)"
    outside="${home}/outside-diagnostics"
    mkdir -p "${home}/.claude/cc/diagnostics" "${outside}"
    chmod 700 "${home}/.claude/cc/diagnostics" "${outside}"
    ln -s "${outside}" "${home}/.claude/cc/diagnostics/control-tower"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_OPEN_WIZARD=1 CT_SELFTEST=1 \
        CT_SELFTEST_STEP=verify-support
    assert_exit_zero "${id} symlink refusal"
    assert_contains "${id} symlink refusal" \
        "verifySupport=copy-only privacySafe=true savedInitially=false fileMode=none directoryMode=none retained=0 scopeSafe=true"
    if find "${outside}" -mindepth 1 -print -quit | grep -q .; then
        fail "${id} symlink target stays empty" "unexpected file below ${outside}"
    else
        pass "${id} symlink target stays empty"
    fi
    rm -rf "${home}"
}

# S53 — an otherwise real diagnostic directory that another account could
# write is also outside the app's trust boundary. It receives no report and
# the same copy-only fallback remains available.
scenario_S53() {
    local id="S53"
    should_run "${id}" || return 0
    local home directory
    home="$(fresh_home)"
    directory="${home}/.claude/cc/diagnostics/control-tower"
    mkdir -p "${directory}"
    chmod 770 "${directory}"
    launch_selftest "${USER_BIN}" "${DEFAULT_TIMEOUT}" "${home}" \
        CT_CLI_PATH="${MOCK_CC}" CT_OPEN_WIZARD=1 CT_SELFTEST=1 \
        CT_SELFTEST_STEP=verify-support
    assert_exit_zero "${id} writable-boundary refusal"
    assert_contains "${id} writable-boundary refusal" \
        "verifySupport=copy-only privacySafe=true savedInitially=false fileMode=none directoryMode=none retained=0 scopeSafe=true"
    if find "${directory}" -mindepth 1 -print -quit | grep -q .; then
        fail "${id} writable boundary stays empty" "unexpected file below ${directory}"
    else
        pass "${id} writable boundary stays empty"
    fi
    rm -rf "${home}"
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
    # Construct the exact Admin window and hosting controller without ordering
    # it onscreen. This keeps the crash regression while preventing the full
    # suite from stealing focus or flashing a window on the publisher's Mac.
    local output status
    output="$(run_with_timeout 3 env \
        HOME="${home}" \
        CT_CLI_PATH="${MOCK_CC}" \
        CT_ADMIN_WINDOW_SELFTEST=1 \
        "${ADMIN_BIN}" 2>&1)"
    status=$?
    rm -rf "${home}"

    if [[ "${status}" -eq 0 && "${output}" == *"ADMIN_WINDOW_SELFTEST built=true visible=false"* ]]; then
        pass "${id} admin window builds without becoming visible"
    else
        fail "${id} admin window must build headlessly" "exit=${status}; output: ${output}"
    fi
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
scenario_S18b
scenario_S19
scenario_S20
scenario_S21
scenario_S22
scenario_S23
scenario_S24
scenario_S25
scenario_S26
scenario_S27
scenario_S28
scenario_S29
scenario_S30
scenario_S31
scenario_S32
scenario_S33
scenario_S34
scenario_S35
scenario_S36
scenario_S37
scenario_S38
scenario_S39
scenario_S40
scenario_S41
scenario_S42
scenario_S43
scenario_S44
scenario_S45
scenario_S46
scenario_S47
scenario_S48
scenario_S49
scenario_S50
scenario_S51
scenario_S52
scenario_S53

echo
echo "=== smoke-scenarios: ${PASS_COUNT} passed, ${FAIL_COUNT} failed ==="
if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    echo "smoke-scenarios.sh: FAIL"
    exit 1
fi

echo "smoke-scenarios.sh: PASS"
exit 0
