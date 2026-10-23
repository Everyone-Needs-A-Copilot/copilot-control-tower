#!/bin/bash
# Fail-closed release verification (v0.6.10 regression).
#
# v0.6.10's install-artifact verifier did not parse under the macOS system bash
# (3.2), yet release-local.sh printed "ready" and exited 0: bash 3.2 reports the
# syntax error, runs the script's EXIT trap, and lets the trap's status (0)
# replace the failure. This suite proves (1) every release script parses under
# /bin/bash, (2) the parse checker and the affirmative install-artifact gate
# reject every non-passing verifier, with negative and positive controls.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CHECK="${ROOT}/scripts/check-release-script-syntax.sh"
GATE="${ROOT}/scripts/release-gate-install-artifact.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-release-fail-closed.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')" == "3" ]] ||
    echo "note: /bin/bash is not 3.2 on this host; parse checks use whatever /bin/bash is"

# --- 1. every release script parses under /bin/bash -----------------------
"${CHECK}" "${ROOT}" || fail "a release script does not parse under /bin/bash"
/bin/bash -n "${ROOT}/scripts/verify-user-install-artifact.sh" || fail "install-artifact verifier does not parse"
for script in release-local.sh release-gate-install-artifact.sh check-release-script-syntax.sh \
        verify-user-install-artifact.sh verify-user-automation.sh sign.sh notarize.sh; do
    /bin/bash -n "${ROOT}/scripts/${script}" || fail "${script} does not parse under /bin/bash"
done
echo "PASS: every release script parses under /bin/bash"

# The exact v0.6.10 construct: a binary operator followed by a newline in [[ ]].
# Negative control: this must be rejected (when /bin/bash is 3.2).
mkdir -p "${scratch}/root/scripts"
printf '#!/bin/bash\n[[ "a" ==\n"a" ]]\n' > "${scratch}/root/scripts/broken.sh"
if /bin/bash -n "${scratch}/root/scripts/broken.sh" 2>/dev/null; then
    echo "note: this /bin/bash accepts the multi-line [[ construct; skipping the 3.2-only rejection control"
else
    status=0; "${CHECK}" "${scratch}/root" 2>/dev/null || status=$?
    [[ "${status}" -eq 1 ]] || fail "syntax checker did not reject an unparseable script (status ${status})"
    echo "PASS: syntax checker rejects the v0.6.10 construct"
fi
# Fail closed when there is nothing to check, and on a missing root.
mkdir -p "${scratch}/empty/scripts"
status=0; "${CHECK}" "${scratch}/empty" 2>/dev/null || status=$?
[[ "${status}" -ne 0 ]] || fail "syntax checker passed with no scripts to check"
status=0; "${CHECK}" "${scratch}/does-not-exist" 2>/dev/null || status=$?
[[ "${status}" -ne 0 ]] || fail "syntax checker passed for a missing root"
echo "PASS: syntax checker fails closed on an empty or missing root"

# --- 2. the affirmative install-artifact gate -----------------------------
PASS_LINE="install-artifact verification: PASS version=2.0.0 build=9 cc=1.2.3"
gate() { "${GATE}" --verifier "$1" --release-dir "${scratch}" --version 2.0.0 --build 9 --cc 1.2.3; }
make_verifier() { # name, body
    printf '#!/bin/bash\nset -euo pipefail\n%s\n' "$2" > "${scratch}/$1"
    chmod +x "${scratch}/$1"
}
expect_gate_failure() {
    local label="$1" file="$2" status=0 output
    output="$(gate "${scratch}/${file}" 2>&1)" || status=$?
    [[ "${status}" -ne 0 ]] || fail "${label}: gate accepted it: ${output}"
    grep -Fq "install-artifact gate: PASS" <<<"${output}" && fail "${label}: gate printed PASS"
    echo "PASS: gate rejects ${label}"
}

make_verifier good.sh "echo '${PASS_LINE}'"
output="$(gate "${scratch}/good.sh" 2>&1)" || fail "gate rejected a passing verifier: ${output}"
grep -Fq "install-artifact gate: PASS" <<<"${output}" || fail "gate did not affirm a passing verifier"
echo "PASS: gate accepts a verifier that exits 0 and prints its exact PASS line"

make_verifier no-marker.sh "echo 'verified'"
expect_gate_failure "a verifier that exits 0 without the PASS line" no-marker.sh

make_verifier empty.sh ":"
expect_gate_failure "a verifier that prints nothing" empty.sh

make_verifier wrong-version.sh "echo 'install-artifact verification: PASS version=2.0.1 build=9 cc=1.2.3'"
expect_gate_failure "a PASS line for the wrong version" wrong-version.sh

make_verifier wrong-build.sh "echo 'install-artifact verification: PASS version=2.0.0 build=8 cc=1.2.3'"
expect_gate_failure "a PASS line for the wrong build" wrong-build.sh

make_verifier prefix.sh "echo 'x ${PASS_LINE}'"
expect_gate_failure "a PASS line embedded in other text" prefix.sh

make_verifier fails-after-pass.sh "echo '${PASS_LINE}'; exit 4"
expect_gate_failure "a verifier that prints PASS and then exits non-zero" fails-after-pass.sh

make_verifier fails.sh "echo boom >&2; exit 2"
expect_gate_failure "a verifier that exits non-zero" fails.sh

# The v0.6.10 failure: unparseable verifier with an EXIT trap. The verifier
# itself may report success on bash 3.2; the gate must still refuse it.
printf '#!/bin/bash\nset -euo pipefail\ntrap "true" EXIT\necho "%s"\n[[ "a" ==\n"a" ]] || exit 1\n' "${PASS_LINE}" > "${scratch}/unparseable.sh"
chmod +x "${scratch}/unparseable.sh"
if /bin/bash -n "${scratch}/unparseable.sh" 2>/dev/null; then
    echo "note: this /bin/bash accepts the multi-line [[ construct; skipping the unparseable-verifier control"
else
    expect_gate_failure "an unparseable verifier even when it printed PASS and exits 0" unparseable.sh
fi

status=0; "${GATE}" --verifier "${scratch}/missing.sh" --release-dir "${scratch}" --version 2.0.0 --build 9 --cc 1.2.3 >/dev/null 2>&1 || status=$?
[[ "${status}" -ne 0 ]] || fail "gate accepted a missing verifier"
status=0; "${GATE}" --verifier "${scratch}/good.sh" >/dev/null 2>&1 || status=$?
[[ "${status}" -ne 0 ]] || fail "gate accepted missing arguments"
echo "PASS: gate rejects a missing verifier and missing arguments"

echo "release fail-closed test: PASS"
