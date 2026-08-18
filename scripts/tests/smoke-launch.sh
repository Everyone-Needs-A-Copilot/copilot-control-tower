#!/usr/bin/env bash
# smoke-launch.sh — the launch-crash regression gate for BOTH native binaries.
#
# Builds the User app (`scripts/build-user.command`) and the Admin app
# (`scripts/build-admin.command`), then launches each bundle executable under `CT_SELFTEST=1`
# against the mock CLI (`scripts/tests/fixtures/mock-cc`) with a healthy fixture,
# asserting:
#   1. the process exits status 0 — NOT killed by a signal. This is the
#      regression gate for the SwiftUI AttributeGraph launch-time abort
#      (see repo memory: "Publisher Setup SwiftUI init crash" — the same
#      class of crash can happen here if a model does `Process`/CLI work
#      inside SwiftUI's `init()` instead of `.task` + a background queue).
#   2. a `SELFTEST badge=...` line appears in stdout — proving the SELFTEST
#      short-circuit actually ran (and exited) rather than the process just
#      happening to exit 0 for an unrelated reason (e.g. an immediate crash
#      inside argument parsing before the CLI is even consulted, or an early
#      return that never reaches the mock `cc` at all).
#
# This is NOT the full scenario matrix — see `smoke-scenarios.sh` for that.
# This script only proves both binaries launch, run the SELFTEST path, and
# come back cleanly under one fixture; it is meant to be cheap enough to run
# on every integration-phase change.
#
# Owned by Builder-4 (native-rebuild parallel-build session). Do not add
# resolution/sync/compute logic here (invariant #1) — this only shells out to
# the build scripts and the two compiled binaries and asserts on their
# process exit status + stdout, exactly like every other smoke script in this
# directory.
#
# Usage:
#   scripts/tests/smoke-launch.sh
#
# Env overrides:
#   CT_SMOKE_LAUNCH_TIMEOUT=<secs>   per-binary launch timeout (default: 20)
#
# Exits non-zero if either build fails, or either binary fails either
# assertion above.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

MOCK_CC="${REPO_ROOT}/scripts/tests/fixtures/mock-cc"
USER_BIN="${REPO_ROOT}/build/Copilot Control Tower.app/Contents/MacOS/Copilot Control Tower"
ADMIN_BIN="${REPO_ROOT}/build/Copilot Control Tower Admin.app/Contents/MacOS/Copilot Control Tower Admin"
LAUNCH_TIMEOUT_SECS="${CT_SMOKE_LAUNCH_TIMEOUT:-20}"

FAILS=0

# --- timeout helper -------------------------------------------------------
# Neither `timeout` nor `gtimeout` (coreutils) is guaranteed present on a
# stock macOS box (this machine has neither as of this writing — verified
# during authoring). `perl` is guaranteed present on every macOS install, so
# it's the portable fallback: fork the real command, arm an alarm, SIGTERM
# then SIGKILL on expiry, and translate the child's wait status into a shell
# exit code using the normal `128 + signum` convention (matches how bash
# itself reports a signal-killed foreground job, and how GNU `timeout`
# reports it too) so callers can tell "clean exit" from "killed by a
# signal" without re-deriving the arithmetic themselves.
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

echo "=== smoke-launch: building both binaries ==="
if ! bash "${REPO_ROOT}/scripts/build-user.command" --build-only; then
    echo "FAIL: scripts/build-user.command --build-only did not exit 0" >&2
    exit 1
fi
echo "ok - scripts/build-user.command --build-only exits 0"

if ! bash "${REPO_ROOT}/scripts/build-admin.command" --build-only; then
    echo "FAIL: scripts/build-admin.command --build-only did not exit 0" >&2
    exit 1
fi
echo "ok - scripts/build-admin.command --build-only exits 0"
echo

if [[ ! -x "${MOCK_CC}" ]]; then
    echo "FATAL: mock CLI not found or not executable at ${MOCK_CC}" >&2
    exit 1
fi

check_launch() {
    local label="$1" bin="$2"

    if [[ ! -x "${bin}" ]]; then
        echo "FAIL [${label}]: binary not found or not executable at: ${bin}" >&2
        FAILS=$((FAILS + 1))
        return
    fi

    local scratch_home
    scratch_home="$(mktemp -d "${TMPDIR:-/tmp}/ct-smoke-launch-home.XXXXXX")"

    local output status
    output="$(run_with_timeout "${LAUNCH_TIMEOUT_SECS}" env \
        HOME="${scratch_home}" \
        CT_CLI_PATH="${MOCK_CC}" \
        CT_FIXTURE=healthy-clean-fleet \
        CT_SELFTEST=1 \
        "${bin}" 2>&1)"
    status=$?
    rm -rf "${scratch_home}"

    if [[ "${status}" -ne 0 ]]; then
        if [[ "${status}" -ge 128 ]]; then
            echo "FAIL [${label}]: killed by signal $((status - 128)) (possible crash — e.g. the SwiftUI AttributeGraph launch-time abort class of bug), not a clean exit 0" >&2
        else
            echo "FAIL [${label}]: exit status ${status}, expected 0" >&2
        fi
        echo "  --- captured stdout+stderr ---" >&2
        printf '%s\n' "${output}" | sed 's/^/    /' >&2
        FAILS=$((FAILS + 1))
        return
    fi

    if ! grep -q '^SELFTEST badge=' <<<"${output}"; then
        echo "FAIL [${label}]: exited 0 but no 'SELFTEST badge=...' line appeared in stdout" >&2
        echo "  --- captured stdout+stderr ---" >&2
        printf '%s\n' "${output}" | sed 's/^/    /' >&2
        FAILS=$((FAILS + 1))
        return
    fi

    local badge_line
    badge_line="$(grep '^SELFTEST badge=' <<<"${output}" | head -1)"
    echo "PASS [${label}]: exit 0, ${badge_line}"
}

echo "=== smoke-launch: launching each binary under CT_SELFTEST=1 (fixture: healthy-clean-fleet) ==="
check_launch "user"  "${USER_BIN}"
check_launch "admin" "${ADMIN_BIN}"
echo

if [[ "${FAILS}" -gt 0 ]]; then
    echo "smoke-launch.sh: FAIL (${FAILS} binary check(s) failed)"
    exit 1
fi

echo "smoke-launch.sh: PASS"
exit 0
