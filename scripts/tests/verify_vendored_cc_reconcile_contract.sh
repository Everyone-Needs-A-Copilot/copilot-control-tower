#!/usr/bin/env bash
# Drive one exact cc executable through the Phase 9 schema-1.0 deterministic
# and bounded-assistant lifecycles.
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
ASSISTANT_PROJECT="${PROJECTS_ROOT}/customized-project"
SOURCE="${SCRATCH}/claude-source"
BIN_DIR="${SCRATCH}/bin"
TMP_ROOT="${SCRATCH}/tmp"
REQUEST="${SCRATCH}/request.json"
ASSISTANT_REQUEST="${SCRATCH}/assistant-request.json"
ASSISTANT_CAPTURE="${SCRATCH}/assistant-claude-capture.json"
REPORTS="${SCRATCH}/reports"
LAYER_MANIFEST="${SCRATCH}/copilot.layers.yml"
mkdir -p \
    "${HOME_DIR}" "${MACHINE_ROOT}/diagnostics" "${PROJECT}" \
    "${ASSISTANT_PROJECT}" "${SOURCE}" \
    "${BIN_DIR}" "${TMP_ROOT}" "${REPORTS}"
chmod 0700 "${HOME_DIR}" "${MACHINE_ROOT}" "${TMP_ROOT}"

git -C "${PROJECT}" init -q -b main
git -C "${PROJECT}" config user.email fixture@example.invalid
git -C "${PROJECT}" config user.name "Reconciliation Fixture"

git -C "${ASSISTANT_PROJECT}" init -q -b main
git -C "${ASSISTANT_PROJECT}" config user.email fixture@example.invalid
git -C "${ASSISTANT_PROJECT}" config user.name "Reconciliation Fixture"
mkdir -p \
    "${ASSISTANT_PROJECT}/.claude/agents" \
    "${ASSISTANT_PROJECT}/.claude/commands"
printf '%s\n' '# Project-owned instructions' > "${ASSISTANT_PROJECT}/CLAUDE.md"
printf '%s\n' 'project-owned agent' > \
    "${ASSISTANT_PROJECT}/.claude/agents/me.md"
printf '%s\n' 'project-owned command' > \
    "${ASSISTANT_PROJECT}/.claude/commands/project.md"
git -C "${ASSISTANT_PROJECT}" add .
git -C "${ASSISTANT_PROJECT}" commit -q -m "customized fixture"

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

"${VALIDATOR_PY}" - \
    "${ASSISTANT_REQUEST}" "${PROJECTS_ROOT}" "${ASSISTANT_PROJECT}" <<'PY'
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
for command in gh codex; do
    cat > "${BIN_DIR}/${command}" <<SH
#!/bin/sh
printf '%s\\n' '${command} version fixture'
SH
    chmod 0755 "${BIN_DIR}/${command}"
done
cat > "${BIN_DIR}/claude" <<'PY'
#!/usr/bin/env python3
"""Inert Claude CLI double for the exact-binary assistant release probe."""

import base64
import hashlib
import json
import os
import pathlib
import sys


if "--version" in sys.argv[1:]:
    print("2.1.221 (Claude Code)")
    raise SystemExit(0)

stdin = sys.stdin.buffer.read()
capture_path = pathlib.Path(os.environ["FAKE_CLAUDE_CAPTURE"])
capture_path.write_text(
    json.dumps(
        {
            "argv": sys.argv[1:],
            "cwd": os.getcwd(),
            "environment_keys": sorted(os.environ),
            "stdin_size": len(stdin),
            "stdin_sha256": hashlib.sha256(stdin).hexdigest(),
            "stdin_base64": base64.b64encode(stdin).decode("ascii"),
        },
        sort_keys=True,
        separators=(",", ":"),
    ),
    encoding="utf-8",
)
capture_path.chmod(0o600)

prompt = json.loads(stdin)
selections = []
for project in prompt["packet"]["projects"]:
    for component in project["components"]:
        selections.append({"candidate_id": component["candidate_ids"][0]})
print(
    json.dumps(
        {
            "type": "result",
            "subtype": "success",
            "is_error": False,
            "structured_output": {"selections": selections},
        },
        separators=(",", ":"),
    )
)
PY
chmod 0755 "${BIN_DIR}/claude"
ln -s "${CC_PATH}" "${BIN_DIR}/cc"

tree_digest() {
    local root="${1:-${PROJECT}}"
    "${VALIDATOR_PY}" - "${root}" <<'PY'
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
            CC_ASSISTANT_TEST_MODE="1" \
            FAKE_CLAUDE_CAPTURE="${ASSISTANT_CAPTURE}" \
            ASSISTANT_SECRET_CANARY="must-not-reach-child" \
            ANTHROPIC_API_KEY="assistant-api-secret-canary" \
            GITHUB_TOKEN="github-secret-canary" \
            GIT_CONFIG_GLOBAL="${SCRATCH}/secret-git-config" \
            SSH_AUTH_SOCK="${SCRATCH}/secret-agent.sock" \
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

assistant_digest="$(tree_digest "${ASSISTANT_PROJECT}")"
run_cc assistant-prepare reconcile assistant-prepare \
    --request "${ASSISTANT_REQUEST}"
[[ "$(tree_digest "${ASSISTANT_PROJECT}")" == "${assistant_digest}" ]] ||
    die "assistant preparation changed the customized disposable project"
assistant_session_id="$("${VALIDATOR_PY}" -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["session_id"])' \
    "${REPORTS}/assistant-prepare.json")"

run_cc assistant-run reconcile assistant-run \
    --session-id "${assistant_session_id}"
[[ "$(tree_digest "${ASSISTANT_PROJECT}")" == "${assistant_digest}" ]] ||
    die "bounded Claude Code assistant run changed the disposable project"

run_cc assistant-status reconcile assistant-status \
    --session-id "${assistant_session_id}"
[[ "$(tree_digest "${ASSISTANT_PROJECT}")" == "${assistant_digest}" ]] ||
    die "assistant proposal validation changed the disposable project"

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

"${VALIDATOR_PY}" - \
    "${SCHEMA_PATH}" "${REQUEST_SCHEMA_PATH}" "${ASSISTANT_REQUEST}" \
    "${ASSISTANT_PROJECT}" "${MACHINE_ROOT}" "${ASSISTANT_CAPTURE}" \
    "${REPORTS}/assistant-prepare.json" \
    "${REPORTS}/assistant-run.json" \
    "${REPORTS}/assistant-status.json" <<'PY'
import base64
import json
import pathlib
import re
import sys

from jsonschema import Draft202012Validator, FormatChecker

(
    schema_path,
    request_schema_path,
    request_path,
    project_path,
    machine_root,
    capture_path,
    prepare_path,
    run_path,
    status_path,
) = map(pathlib.Path, sys.argv[1:])


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def validate(schema, value, label):
    errors = sorted(
        Draft202012Validator(
            schema, format_checker=FormatChecker()
        ).iter_errors(value),
        key=lambda error: list(error.path),
    )
    if errors:
        rendered = "; ".join(
            f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}"
            for error in errors[:5]
        )
        raise SystemExit(f"{label} does not satisfy schema 1.0: {rendered}")


schema = load(schema_path)
request = load(request_path)
validate(load(request_schema_path), request, "assistant request")
reports = {
    "assistant-prepare": load(prepare_path),
    "assistant-run": load(run_path),
    "assistant-status": load(status_path),
}
for phase, report in reports.items():
    validate(schema, report, phase)
    if report.get("phase") != phase or report.get("result") != "ready":
        raise SystemExit(f"{phase} did not return a ready {phase} report")

project = str(project_path.resolve())
root = str(project_path.parent.resolve())
expected_request = {
    "schema_version": "1.0",
    "roots": [root],
    "projects": [{"path": project, "components": ["claude"]}],
}
if request != expected_request:
    raise SystemExit("assistant request is not the exact customized fixture selection")

session_id = reports["assistant-prepare"].get("session_id")
if not isinstance(session_id, str) or not re.fullmatch(
    r"session_[0-9a-f]{32}", session_id
):
    raise SystemExit("assistant prepare did not issue an opaque session id")
for report in reports.values():
    if report.get("session_id") != session_id:
        raise SystemExit("assistant lifecycle changed session identity")
    if report.get("selected_projects") != [project]:
        raise SystemExit("assistant lifecycle changed the selected project batch")
proposal_id = reports["assistant-status"].get("proposal_id")
if not isinstance(proposal_id, str) or not re.fullmatch(
    r"proposal_[0-9a-f]{32}", proposal_id
):
    raise SystemExit("assistant status did not issue an opaque proposal id")

capture = load(capture_path)
expected_arguments = [
    "--safe-mode",
    "--tools",
    "",
    "--permission-mode",
    "plan",
    "--strict-mcp-config",
    "--disable-slash-commands",
    "--no-session-persistence",
    "--no-chrome",
    "--print",
    "--input-format",
    "text",
    "--output-format",
    "json",
    "--json-schema",
]
arguments = capture.get("argv")
if not isinstance(arguments, list) or arguments[:-1] != expected_arguments:
    raise SystemExit("assistant run did not use the protected Claude Code arguments")
if project in json.dumps(arguments):
    raise SystemExit("assistant run leaked the project path through Claude arguments")

expected_work = (
    machine_root.resolve()
    / "diagnostics"
    / "reconciliation"
    / "assistant"
    / "sessions"
    / session_id
    / "work"
)
if pathlib.Path(capture.get("cwd", "")).resolve() != expected_work:
    raise SystemExit("assistant run did not use its private machine-state workspace")

environment_keys = set(capture.get("environment_keys") or [])
if {
    "ASSISTANT_SECRET_CANARY",
    "ANTHROPIC_API_KEY",
    "GITHUB_TOKEN",
    "GIT_CONFIG_GLOBAL",
    "SSH_AUTH_SOCK",
} & environment_keys:
    raise SystemExit("assistant run forwarded a secret-bearing environment variable")

prompt = base64.b64decode(capture["stdin_base64"], validate=True)
if len(prompt) != capture.get("stdin_size"):
    raise SystemExit("assistant capture recorded an inconsistent prompt size")
prompt_value = json.loads(prompt)
prompt_rendered = json.dumps(prompt_value, sort_keys=True)
for forbidden in (
    project,
    project_path.name,
    "Project-owned instructions",
    "project-owned agent",
    "project-owned command",
    "claude-source",
):
    if forbidden in prompt_rendered:
        raise SystemExit("assistant run leaked project-authored context to Claude")
packet = prompt_value.get("packet") or {}
if packet.get("task") != "select-bounded-project-reconciliation-candidates":
    raise SystemExit("assistant run did not send the bounded selection task")
if packet.get("rules") != {
    "select_exactly_one_candidate_per_component": True,
    "author_commands_paths_content_patches_operations": False,
}:
    raise SystemExit("assistant run weakened the bounded selection rules")

output_schema = json.loads(arguments[-1])
selections = output_schema.get("properties", {}).get("selections", {})
item_schema = selections.get("items", {})
if (
    output_schema.get("additionalProperties") is not False
    or item_schema.get("additionalProperties") is not False
    or item_schema.get("required") != ["candidate_id"]
    or set(item_schema.get("properties", {})) != {"candidate_id"}
):
    raise SystemExit("assistant run did not constrain Claude to candidate ids")

print(
    "reconcile schema 1.0 assistant lifecycle PASS: "
    "assistant-prepare -> assistant-run -> assistant-status"
)
PY

echo "vendored-cc reconcile contract: PASS (${CC_PATH})"
