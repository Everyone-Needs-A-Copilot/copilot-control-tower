#!/usr/bin/env bash

set -euo pipefail

fixture_dir="${CT_RECONCILE_FIXTURE_DIR:?missing CT_RECONCILE_FIXTURE_DIR}"
capture_dir="${CT_RECONCILE_CAPTURE_DIR:?missing CT_RECONCILE_CAPTURE_DIR}"

[[ "${1:-}" == "reconcile" ]] || exit 64
phase="${2:-}"
case "${phase}" in
  assess|assistant-prepare|assistant-status|plan|apply|verify|recover) ;;
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
