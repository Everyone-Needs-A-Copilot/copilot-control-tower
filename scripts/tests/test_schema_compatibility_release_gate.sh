#!/usr/bin/env bash
# Artifact-level regression gate for the aggregate layer-manifest migration.
#
# The incident crossed three independently released consumers. This gate uses
# the exact old and repaired public CLI commits plus the exact vendored cc
# binary; source-only unit tests are not accepted as release evidence.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CC_PATH="${REPO_ROOT}/packaging/cc/cc"
CLI_FIXTURES="${REPO_ROOT}/packaging/compat/cli"
CLI_N_MINUS_1="${CLI_FIXTURES}/copilot_cli-1.4.5-py3-none-any.whl"
CLI_N="${CLI_FIXTURES}/copilot_cli-1.4.6-py3-none-any.whl"

die() {
    echo "schema compatibility gate: $*" >&2
    exit 1
}

for command in python3; do
    command -v "${command}" >/dev/null 2>&1 ||
        die "${command} is required"
done
[[ -x "${CC_PATH}" ]] || die "vendored cc is missing or not executable"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-schema-compat.XXXXXX")"
cleanup() {
    rm -rf "${scratch}"
}
trap cleanup EXIT

install_reader() {
    local wheel="$1"
    local destination="$2"
    local expected_sha="$3"
    local expected_version="$4"

    python3 - "${wheel}" "${expected_sha}" <<'PY'
import hashlib
import pathlib
import sys

wheel = pathlib.Path(sys.argv[1])
expected = sys.argv[2]
actual = hashlib.sha256(wheel.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(
        f"reader fixture checksum mismatch for {wheel.name}: {actual}"
    )
PY
    python3 -m venv "${destination}"
    "${destination}/bin/pip" install --quiet "${wheel}"
    [[ "$("${destination}/bin/python" -c \
        'from importlib.metadata import version; print(version("copilot-cli"))')" == \
        "${expected_version}" ]] ||
        die "reader fixture did not install copilot-cli ${expected_version}"
}

install_reader \
    "${CLI_N_MINUS_1}" \
    "${scratch}/reader-n-minus-1" \
    "8d53a40a72c9756aada08386da729fc944859220550d56db7c3a43c149e1c016" \
    "1.4.5"
install_reader \
    "${CLI_N}" \
    "${scratch}/reader-n" \
    "519ad30701aadd0d1587d076178b849f45a9d9c4525019a4af86670d5004cf20" \
    "1.4.6"

fixture_python="${scratch}/fixture-python"
mkdir -p "${fixture_python}/compat_fixture"
cat >"${fixture_python}/compat_fixture/__init__.py" <<'PY'
"""Release-gate-only CLI overlay fixture."""
PY
cat >"${fixture_python}/compat_fixture/commands.py" <<'PY'
import typer

app = typer.Typer(help="Compatibility fixture.")
PY

mirrors="${scratch}/copilot-home"
overlay_root="${mirrors}/mirrors/cli/cli-organization"
mkdir -p "${overlay_root}"
cat >"${overlay_root}/cli.overlay.yml" <<'YAML'
version: 1
provides:
  - service: discord
    module: compat_fixture.commands
    help: Compatibility fixture.
YAML

write_manifest() {
    local path="$1"
    local declarations="$2"
    cat >"${path}" <<YAML
version: 1
org: Acme
layers:
  - id: cli-organization
    role: organization
    rank: 30
${declarations}
    source:
      repo: file://${overlay_root}
      ref: main
    auth: work
    activation: always
YAML
}

legacy="${scratch}/legacy.yml"
canonical="${scratch}/canonical.yml"
dual="${scratch}/dual.yml"
conflict="${scratch}/conflict.yml"
write_manifest "${legacy}" "    component: cli"
write_manifest "${canonical}" "    product: cli"
write_manifest "${dual}" $'    product: cli\n    component: cli'
write_manifest "${conflict}" $'    product: codex\n    component: cli'

assert_cli_capability() {
    local reader="$1"
    local manifest="$2"
    local expectation="$3"
    local payload="${scratch}/$(basename "${reader}")-$(basename "${manifest}").json"

    env \
        COPILOT_LAYERS_FILE="${manifest}" \
        COPILOT_MIRRORS_ROOT="${mirrors}" \
        PYTHONPATH="${fixture_python}" \
        "${reader}/bin/copilot" --json layers >"${payload}"
    python3 - "${payload}" "${expectation}" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
expectation = sys.argv[2]
ids = [layer.get("id") for layer in payload.get("chain", [])]
services = {
    service.get("name"): (service.get("tier"), service.get("mode"))
    for service in payload.get("services", [])
}
if expectation == "preserved":
    if ids != ["cli-organization"]:
        raise SystemExit(f"CLI chain changed: {ids!r}")
    if services.get("discord") != ("cli-organization", "provides"):
        raise SystemExit(
            f"Discord capability was lost or downgraded: {services.get('discord')!r}"
        )
elif ids or "discord" in services:
    raise SystemExit(
        "legacy reader unexpectedly accepted canonical-only product syntax"
    )
PY
}

old_reader="${scratch}/reader-n-minus-1"
new_reader="${scratch}/reader-n"

# Reader-first rollout contract:
# - legacy syntax is safe before and after the reader patch;
# - canonical-only syntax is unsafe on N-1 and safe on N;
# - matching dual syntax is safe during a bridge period.
assert_cli_capability "${old_reader}" "${legacy}" preserved
assert_cli_capability "${new_reader}" "${legacy}" preserved
assert_cli_capability "${old_reader}" "${canonical}" unsupported
assert_cli_capability "${new_reader}" "${canonical}" preserved
assert_cli_capability "${old_reader}" "${dual}" preserved
assert_cli_capability "${new_reader}" "${dual}" preserved

if env \
    COPILOT_LAYERS_FILE="${conflict}" \
    COPILOT_MIRRORS_ROOT="${mirrors}" \
    PYTHONPATH="${fixture_python}" \
    "${new_reader}/bin/copilot" --json layers >/dev/null 2>&1; then
    die "repaired CLI accepted conflicting product/component declarations"
fi

assert_cc_reader() {
    local manifest="$1"
    local expectation="$2"
    local payload="${scratch}/cc-$(basename "${manifest}").json"
    local exit_code

    set +e
    (
        cd "${scratch}"
        env \
            HOME="${scratch}/home" \
            CC_MACHINE_ROOT="${scratch}/cc-machine" \
            CC_LAYERS_MANIFEST="${manifest}" \
            CC_PATHS_MIRRORS_ROOT="${mirrors}/mirrors" \
            "${CC_PATH}" doctor --json >"${payload}"
    )
    exit_code=$?
    set -e

    if [[ "${expectation}" == "accepted" ]]; then
        [[ "${exit_code}" -eq 0 || "${exit_code}" -eq 1 ]] ||
            die "vendored cc rejected $(basename "${manifest}") with ${exit_code}"
        python3 - "${payload}" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("schema_version") != "1.0" or payload.get("error") is not None:
    raise SystemExit(f"vendored cc returned an invalid report: {payload!r}")
PY
    elif [[ "${exit_code}" -ne 1 ]]; then
        die "vendored cc did not report an unhealthy conflict (exit ${exit_code})"
    else
        python3 - "${payload}" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
checks = {
    check.get("id"): check
    for check in payload.get("checkers", [])
}
manifest_check = checks.get("ecosystem-layer-manifest", {})
if payload.get("status") == "healthy":
    raise SystemExit("vendored cc reported a conflicting manifest as healthy")
if manifest_check.get("severity") != "fail":
    raise SystemExit(
        "vendored cc did not fail the ecosystem-layer-manifest check: "
        f"{manifest_check!r}"
    )
if "disagrees" not in manifest_check.get("detail", ""):
    raise SystemExit(
        "vendored cc did not identify the product/component conflict: "
        f"{manifest_check!r}"
    )
PY
    fi
}

assert_cc_reader "${legacy}" accepted
assert_cc_reader "${canonical}" accepted
assert_cc_reader "${dual}" accepted
assert_cc_reader "${conflict}" rejected

echo "schema compatibility release gate: PASS"
