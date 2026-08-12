#!/usr/bin/env bash
# Focused Phase 9 release-gate regression against a local helper checkout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLAUDE_ROOT="${CT_RECONCILE_CLAUDE_ROOT:-}"
[[ -n "${CLAUDE_ROOT}" ]] || {
    echo "vendored-cc reconcile release test: set CT_RECONCILE_CLAUDE_ROOT" >&2
    exit 1
}
CC_PATH="${CT_RECONCILE_CC_PATH:-${CLAUDE_ROOT}/tools/cc/.venv/bin/cc}"
GATE="${SCRIPT_DIR}/verify_vendored_cc_reconcile_contract.sh"
FIXTURE_DIR="${SCRIPT_DIR}/fixtures/reconcile-contract"
PROBE_ASSERT="${FIXTURE_DIR}/assert_notarization_probe.py"
VALIDATOR_PY="${REPO_ROOT}/.copilot/build-cache/jsonschema-venv/bin/python3"

die() {
    echo "vendored-cc reconcile release test: $*" >&2
    exit 1
}

[[ -x "${CC_PATH}" ]] || die "local Phase 9 cc is missing: ${CC_PATH}"
[[ -x "${GATE}" ]] || die "reconcile lifecycle gate is not executable"
[[ -f "${PROBE_ASSERT}" ]] || die "notarization probe assertion is missing"

if [[ ! -x "${VALIDATOR_PY}" ]]; then
    command -v uv >/dev/null 2>&1 || die "uv is required to prepare jsonschema"
    uv venv --python 3.13 "$(dirname "$(dirname "${VALIDATOR_PY}")")" >/dev/null
    uv pip install --python "${VALIDATOR_PY}" --quiet jsonschema >/dev/null
fi

cmp -s \
    "${CLAUDE_ROOT}/tools/cc/tests/fixtures/schemas/reconcile.schema.json" \
    "${FIXTURE_DIR}/reconcile.schema.json" ||
    die "copied reconciliation report schema drifted from the helper source"
cmp -s \
    "${CLAUDE_ROOT}/tools/cc/tests/fixtures/schemas/reconcile-request.schema.json" \
    "${FIXTURE_DIR}/reconcile-request.schema.json" ||
    die "copied reconciliation request schema drifted from the helper source"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-reconcile-release-test.XXXXXX")"
cleanup() {
    rm -rf "${scratch}"
}
trap cleanup EXIT

printf '%s\n' \
    '{"finder_reconciliation_probe":"passed","finder_reconciliation_assistant_probe":"passed"}' \
    > "${scratch}/passed.json"
printf '%s\n' \
    '{"finder_reconciliation_probe":"failed","finder_reconciliation_assistant_probe":"passed"}' \
    > "${scratch}/failed-base.json"
printf '%s\n' \
    '{"finder_reconciliation_probe":"passed","finder_reconciliation_assistant_probe":"failed"}' \
    > "${scratch}/failed-assistant.json"
printf '%s\n' '{"finder_reconciliation_probe":"passed"}' \
    > "${scratch}/missing-assistant.json"
printf '%s\n' '{}' > "${scratch}/missing.json"
printf '%s\n' 'not-json' > "${scratch}/unreadable.json"

python3 "${PROBE_ASSERT}" "${scratch}/passed.json"
for evidence in failed-base failed-assistant missing-assistant missing unreadable; do
    if python3 "${PROBE_ASSERT}" "${scratch}/${evidence}.json" >/dev/null 2>&1; then
        die "${evidence} notarization evidence passed the release probe gate"
    fi
done

python3 - \
    "${REPO_ROOT}/scripts/verify-vendored-cc.sh" \
    "${REPO_ROOT}/scripts/package-user-release.program" \
    "${PROBE_ASSERT}" \
    "${GATE}" <<'PY'
import pathlib
import sys

verify = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
package = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
probe_assert = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
reconcile_gate = pathlib.Path(sys.argv[4]).read_text(encoding="utf-8")

if "finder_reconciliation_assistant_probe" not in probe_assert:
    raise SystemExit("release evidence does not require the Finder assistant probe")
for verb in ("assistant-prepare", "assistant-run", "assistant-status"):
    if verb not in reconcile_gate:
        raise SystemExit(f"exact-binary reconciliation gate omits {verb}")

probe = verify.index('/usr/bin/python3 "${RECONCILE_PROBE_ASSERT}"')
topology = verify.index('"${TOPOLOGY_FIXTURES}/assert_onboard_schema.py"')
reconcile = verify.index('"${RECONCILE_GATE}"')
if not probe < reconcile or not topology < reconcile:
    raise SystemExit("reconciliation verification weakened the existing release order")

vendored = package.index(
    'scripts/verify-vendored-cc.sh --release "${embedded_cc}"'
)
app_notary = package.index('scripts/notarize.sh app "${app_path}"')
if vendored >= app_notary:
    raise SystemExit("app notarization occurs before the vendored helper gate")
PY

"${GATE}" --cc-path "${CC_PATH}" --validator-python "${VALIDATOR_PY}"

cat > "${scratch}/cc-exit-one" <<'SH'
#!/bin/bash
set +e
"${CT_RECONCILE_REAL_CC:?}" "$@"
exit_code=$?
if [[ "${1:-}" == "reconcile" ]]; then
    case "${2:-}" in
        assess|plan|verify) exit 1 ;;
    esac
fi
exit "${exit_code}"
SH
chmod 0755 "${scratch}/cc-exit-one"
CT_RECONCILE_REAL_CC="${CC_PATH}" "${GATE}" \
    --cc-path "${scratch}/cc-exit-one" \
    --validator-python "${VALIDATOR_PY}"

echo "vendored-cc reconcile release gate test: PASS"
