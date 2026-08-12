#!/usr/bin/env bash

set -euo pipefail

fixture_dir="${CT_RECONCILE_FIXTURE_DIR:?missing CT_RECONCILE_FIXTURE_DIR}"
capture_dir="${CT_RECONCILE_CAPTURE_DIR:?missing CT_RECONCILE_CAPTURE_DIR}"

[[ "${1:-}" == "reconcile" ]] || exit 64
phase="${2:-}"
case "${phase}" in
  assess|prepare|assistant-prepare|assistant-status|guide-prepare|guide-status|guide-finalize|plan|apply|verify|recover) ;;
  *) exit 64 ;;
esac

mkdir -p "${capture_dir}"
printf '%s\n' "$@" > "${capture_dir}/${phase}.argv"

request_path=""
previous=""
for argument in "$@"; do
  if [[ "${previous}" == "--request" ]]; then
    request_path="${argument}"
    break
  fi
  previous="${argument}"
done

if [[ -n "${request_path}" ]]; then
  cp "${request_path}" "${capture_dir}/${phase}.request"
  printf '%s\n' "${request_path}" > "${capture_dir}/${phase}.request-path"
  stat -f '%Lp' "${request_path}" > "${capture_dir}/${phase}.mode"
  stat -f '%u' "${request_path}" > "${capture_dir}/${phase}.uid"
fi

response="${CT_RECONCILE_RESPONSE:-${phase}}"
if [[ "${response}" == "guide-status" ]]; then
  response="guide-status-running"
elif [[ "${response}" == "guide-finalize" ]]; then
  response="guide-status-ready"
fi

if [[ "${response}" == "prepare" ]]; then
  /usr/bin/python3 - "${fixture_dir}/assess.json" <<'PY'
import json
import sys

assessment = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps({
    "schema_version": "2.0",
    "phase": "prepare",
    "result": "applied",
    "run_id": assessment["run_id"],
    "generated_at": assessment["generated_at"],
    "completed_actions": [{
        "kind": "project-checkpoint",
        "target": "/Projects/One",
        "outcome": "completed",
        "summary": "Saved current work locally.",
    }],
    "project_checkpoints": {"checkpointed": 1, "became_current": 0, "held": 0, "pushed": 0},
    "ecosystem_refresh": {"mode": "download-only", "checked": 12, "updated": 4, "current": 8, "held": 0},
    "authority": {"setup_access": "download-only", "author_capable": 4, "read_only": 7, "unknown": 1},
    "holds": [],
    "assessment": assessment,
    "summary": {
        "headline": "The routine work is done.",
        "detail": "I saved work in 1 project and downloaded 4 shared Copilot updates. Nothing was pushed.",
    },
    "next_actions": assessment["next_actions"],
}))
PY
  exit 0
fi
exit_code=0
case "${response}" in
  apply|verify|recover|assistant-status-blocked) exit_code=1 ;;
  error) exit_code=2 ;;
  schema-high) exit_code=0 ;;
  error-mismatch)
    response="error"
    exit_code=1
    ;;
  success-exit-two)
    response="assess"
    exit_code=2
    ;;
  wrong-phase)
    response="verify"
    exit_code=1
    ;;
esac

printf '%s\n' "$(<"${fixture_dir}/${response}.json")"
exit "${exit_code}"
