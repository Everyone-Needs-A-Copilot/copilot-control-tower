#!/usr/bin/env bash
# Drive one exact cc executable through the Phase 9 schema-1.0 lifecycle.
# Every read and write is isolated below a fresh temporary directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIXTURE_DIR="${SCRIPT_DIR}/fixtures/reconcile-contract"
SCHEMA_PATH="${FIXTURE_DIR}/reconcile.schema.json"
REQUEST_SCHEMA_PATH="${FIXTURE_DIR}/reconcile-request.schema.json"
ASSERT_SCRIPT="${FIXTURE_DIR}/assert_reconcile_contract.py"
CC_PATH=""
VALIDATOR_PY="python3"
KEEP=false

usage() {
    cat <<'EOF'
Usage: scripts/tests/verify_vendored_cc_reconcile_contract.sh --cc-path PATH [options]

Options:
  --cc-path PATH          Exact executable to exercise (required).
  --validator-python PATH Python with jsonschema installed (default: python3).
  --keep                  Retain the disposable fixture for diagnosis.
  -h, --help              Show this help.
EOF
}

die() {
    echo "vendored-cc reconcile contract: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cc-path)
            [[ $# -ge 2 ]] || die "--cc-path requires a value"
            CC_PATH="$2"
            shift 2
            ;;
        --validator-python)
            [[ $# -ge 2 ]] || die "--validator-python requires a value"
            VALIDATOR_PY="$2"
            shift 2
            ;;
        --keep)
            KEEP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

[[ -n "${CC_PATH}" ]] || die "--cc-path is required"
case "${CC_PATH}" in
    /*) ;;
    *) CC_PATH="${REPO_ROOT}/${CC_PATH}" ;;
esac
CC_PATH="$(cd "$(dirname "${CC_PATH}")" && pwd)/$(basename "${CC_PATH}")"
[[ -x "${CC_PATH}" ]] || die "cc is missing or not executable: ${CC_PATH}"
[[ -x "${VALIDATOR_PY}" ]] || die "validator Python is not executable: ${VALIDATOR_PY}"
[[ -f "${SCHEMA_PATH}" ]] || die "copied reconcile schema is missing"
[[ -f "${REQUEST_SCHEMA_PATH}" ]] || die "copied request schema is missing"
[[ -f "${ASSERT_SCRIPT}" ]] || die "contract assertion script is missing"
for command in git shasum; do
    command -v "${command}" >/dev/null 2>&1 || die "${command} is required"
done
"${VALIDATOR_PY}" -c 'import jsonschema' >/dev/null 2>&1 ||
    die "validator Python does not provide jsonschema"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ct-cc-reconcile.XXXXXX")"
SCRATCH="$("${VALIDATOR_PY}" -c \
    'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' \
    "${SCRATCH}")"
cleanup() {
    if [[ "${KEEP}" == true ]]; then
        echo "vendored-cc reconcile contract: kept scratch at ${SCRATCH}" >&2
    else
        rm -rf "${SCRATCH}"
    fi
}
trap cleanup EXIT

HOME_DIR="${SCRATCH}/home"
MACHINE_ROOT="${SCRATCH}/machine"
PROJECTS_ROOT="${SCRATCH}/projects"
PROJECT="${PROJECTS_ROOT}/fixture-project"
SOURCE="${SCRATCH}/claude-source"
BIN_DIR="${SCRATCH}/bin"
TMP_ROOT="${SCRATCH}/tmp"
REQUEST="${SCRATCH}/request.json"
REPORTS="${SCRATCH}/reports"
LAYER_MANIFEST="${SCRATCH}/copilot.layers.yml"
mkdir -p \
    "${HOME_DIR}" "${MACHINE_ROOT}/diagnostics" "${PROJECT}" "${SOURCE}" \
    "${BIN_DIR}" "${TMP_ROOT}" "${REPORTS}"
chmod 0700 "${HOME_DIR}" "${MACHINE_ROOT}" "${TMP_ROOT}"

git -C "${PROJECT}" init -q -b main
git -C "${PROJECT}" config user.email fixture@example.invalid
git -C "${PROJECT}" config user.name "Reconciliation Fixture"

mkdir -p \
    "${SOURCE}/.claude/commands" \
    "${SOURCE}/.claude/agents/nested" \
    "${SOURCE}/plugins/codex-copilot/.codex-plugin" \
    "${SOURCE}/plugins/codex-copilot/skills/fixture" \
    "${SOURCE}/scripts"
printf '%s\n' \
    '{"framework":"5.13.3","components":{"agents":{"frameworkAgents":["fixture"]}}}' \
    > "${SOURCE}/VERSION.json"
printf '%s\n' '# protocol fixture' > "${SOURCE}/.claude/commands/protocol.md"
printf '%s\n' '# continue fixture' > "${SOURCE}/.claude/commands/continue.md"
printf '%s\n' '#!/bin/sh' 'exit 0' > "${SOURCE}/.claude/fitness-check.sh"
chmod 0755 "${SOURCE}/.claude/fitness-check.sh"
printf '%s\n' '# fixture agent' > "${SOURCE}/.claude/agents/fixture.md"
printf '%s\n' '# knowledge copilot fixture agent' > "${SOURCE}/.claude/agents/kc.md"
printf '%s\n' '# nested fixture agent' > "${SOURCE}/.claude/agents/nested/extra.md"
printf '%s\n' '# fixture skill' > \
    "${SOURCE}/plugins/codex-copilot/skills/fixture/SKILL.md"
printf '%s\n' '{"name":"codex-copilot","version":"0.6.1"}' > \
    "${SOURCE}/plugins/codex-copilot/.codex-plugin/plugin.json"
printf '%s\n' '#!/bin/sh' 'exit 0' > "${SOURCE}/scripts/copilot-gate.sh"
chmod 0755 "${SOURCE}/scripts/copilot-gate.sh"

git -C "${SOURCE}" init -q -b main
git -C "${SOURCE}" config user.email fixture@example.invalid
git -C "${SOURCE}" config user.name "Reconciliation Fixture"
git -C "${SOURCE}" add .
git -C "${SOURCE}" commit -q -m "fixture source"

cat > "${LAYER_MANIFEST}" <<EOF
version: 1
layers:
  - id: fixture-personal
    role: personal
    rank: 10
    product: claude
    source:
      repo: ${SOURCE}
      ref: main
      path: ${SOURCE}
    auth: public
    activation: always
EOF

"${VALIDATOR_PY}" - \
    "${MACHINE_ROOT}/config.json" "${SOURCE}" "${PROJECTS_ROOT}" \
    "${LAYER_MANIFEST}" <<'PY'
import json
import pathlib
import sys

path, source, projects, manifest = map(pathlib.Path, sys.argv[1:])
payload = {
    "version": 1,
    "paths": {
        "claude_copilot_root": str(source),
        "codex_copilot_root": str(source),
    },
    "projects": {"roots": [str(projects)]},
    "layers": {"manifest": str(manifest)},
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
path.chmod(0o600)
PY

"${VALIDATOR_PY}" - "${REQUEST}" "${PROJECTS_ROOT}" "${PROJECT}" <<'PY'
import json
import pathlib
import sys

path, root, project = map(pathlib.Path, sys.argv[1:])
payload = {
    "schema_version": "1.0",
    "roots": [str(root)],
    "projects": [{"path": str(project), "components": ["claude"]}],
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

cat > "${BIN_DIR}/copilot" <<'SH'
#!/bin/sh
if [ "$#" -eq 2 ] && [ "$1" = "--json" ] && [ "$2" = "layers" ]; then
    printf '%s\n' '{"services":[]}'
    exit 0
fi
if [ "${1:-}" = "--version" ]; then
    printf '%s\n' 'copilot version fixture'
    exit 0
fi
exit 2
SH
chmod 0755 "${BIN_DIR}/copilot"
for command in gh claude codex; do
    cat > "${BIN_DIR}/${command}" <<SH
#!/bin/sh
printf '%s\\n' '${command} version fixture'
SH
    chmod 0755 "${BIN_DIR}/${command}"
done
ln -s "${CC_PATH}" "${BIN_DIR}/cc"

tree_digest() {
    "${VALIDATOR_PY}" - "${PROJECT}" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
rows = []
for current, directories, files in os.walk(root, followlinks=False):
    current_path = pathlib.Path(current)
    directories[:] = sorted(name for name in directories if name != ".git")
    for name in sorted(files):
        path = current_path / name
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            rows.append([relative, "symlink", os.readlink(path)])
        else:
            rows.append([relative, "file", hashlib.sha256(path.read_bytes()).hexdigest()])
payload = json.dumps(rows, separators=(",", ":"), ensure_ascii=True)
print(hashlib.sha256(payload.encode("utf-8")).hexdigest())
PY
}

run_cc() {
    local report="$1"
    local exit_code
    shift
    set +e
    (
        cd "${SCRATCH}"
        env \
            HOME="${HOME_DIR}" \
            CC_MACHINE_ROOT="${MACHINE_ROOT}" \
            CC_GLOBAL_MEMORY_ROOT="${SCRATCH}/global-memory" \
            XDG_CACHE_HOME="${SCRATCH}/cache" \
            TMPDIR="${TMP_ROOT}" \
            PATH="${BIN_DIR}:/usr/bin:/bin:/usr/sbin:/sbin" \
            HTTP_PROXY="http://127.0.0.1:9" \
            HTTPS_PROXY="http://127.0.0.1:9" \
            ALL_PROXY="http://127.0.0.1:9" \
            NO_PROXY="localhost,127.0.0.1" \
            "${CC_PATH}" "$@" --json
    ) > "${REPORTS}/${report}.json" 2> "${REPORTS}/${report}.err"
    exit_code=$?
    set -e
    if [[ "${exit_code}" -ne 0 && "${exit_code}" -ne 1 ]]; then
        echo "vendored-cc reconcile contract: ${report} invocation failed" >&2
        sed -n '1,80p' "${REPORTS}/${report}.json" >&2
        sed -n '1,80p' "${REPORTS}/${report}.err" >&2
        exit 1
    fi
}

initial_digest="$(tree_digest)"
run_cc assess reconcile assess
[[ "$(tree_digest)" == "${initial_digest}" ]] ||
    die "read-only assessment changed the disposable project"

run_cc plan reconcile plan --request "${REQUEST}"
[[ "$(tree_digest)" == "${initial_digest}" ]] ||
    die "read-only planning changed the disposable project"
plan_id="$("${VALIDATOR_PY}" -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["plan_id"])' \
    "${REPORTS}/plan.json")"

run_cc apply reconcile apply --request "${REQUEST}" --plan-id "${plan_id}"
stable_digest="$(tree_digest)"
[[ "${stable_digest}" != "${initial_digest}" ]] ||
    die "initial apply did not install the disposable project integration"

run_cc verify reconcile verify --request "${REQUEST}"
[[ "$(tree_digest)" == "${stable_digest}" ]] ||
    die "fresh verification changed the disposable project"

run_cc repeat-plan reconcile plan --request "${REQUEST}"
[[ "$(tree_digest)" == "${stable_digest}" ]] ||
    die "repeat planning changed the disposable project"
repeat_plan_id="$("${VALIDATOR_PY}" -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["plan_id"])' \
    "${REPORTS}/repeat-plan.json")"

run_cc repeat-apply reconcile apply \
    --request "${REQUEST}" --plan-id "${repeat_plan_id}"
[[ "$(tree_digest)" == "${stable_digest}" ]] ||
    die "repeat apply changed an already integrated project"

run_cc recover reconcile recover
[[ "$(tree_digest)" == "${stable_digest}" ]] ||
    die "recovery changed a terminal disposable project"

"${VALIDATOR_PY}" "${ASSERT_SCRIPT}" \
    --schema "${SCHEMA_PATH}" \
    --request-schema "${REQUEST_SCHEMA_PATH}" \
    --request "${REQUEST}" \
    --project "${PROJECT}" \
    --machine-root "${MACHINE_ROOT}" \
    --assess "${REPORTS}/assess.json" \
    --plan "${REPORTS}/plan.json" \
    --apply "${REPORTS}/apply.json" \
    --verify "${REPORTS}/verify.json" \
    --repeat-plan "${REPORTS}/repeat-plan.json" \
    --repeat-apply "${REPORTS}/repeat-apply.json" \
    --recover "${REPORTS}/recover.json" \
    --expected-stable-digest "${stable_digest}"

echo "vendored-cc reconcile contract: PASS (${CC_PATH})"
