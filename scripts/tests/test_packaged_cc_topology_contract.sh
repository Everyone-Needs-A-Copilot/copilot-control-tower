#!/usr/bin/env bash
# G-6 (task 209) release gate: drive the exact PACKAGED cc binary against a
# deterministic, fully local Git fixture and assert the sixteen-row topology
# contract -- never a mock, never a live tree, never real GitHub.
#
# Usage:
#   scripts/tests/test_packaged_cc_topology_contract.sh [options]
#
# Options:
#   --cc-path PATH       Packaged `cc` binary to test. Default: build (or
#                         reuse the cache for) a FRESH helper from
#                         claude-copilot via scripts/build-fresh-vendored-cc.sh.
#   --source-cc PATH     Dev-install `cc` used as the report oracle for the
#                         source-vs-packaged diff. Default:
#                         <claude-root>/tools/cc/.venv/bin/cc.
#   --claude-root PATH   claude-copilot checkout. Default:
#                         /Volumes/Dev/Sites/COPILOT/claude-copilot (or
#                         $CT_TOPOLOGY_CLAUDE_ROOT).
#   --keep                Do not delete the scratch directory on exit; its
#                         path is printed for post-mortem inspection.
#   -h, --help            Show this help.
#
# Demonstrating the old-binary-fails / new-binary-passes contract required by
# task 209:
#
#   # OLD vendored helper (release/*, schema 1.0, no ancestry proof) -- FAILS:
#   scripts/tests/test_packaged_cc_topology_contract.sh \
#     --cc-path packaging/cc/cc
#
#   # FRESH helper built from claude-copilot -- PASSES (this is the default):
#   scripts/tests/test_packaged_cc_topology_contract.sh
#
# What this gate proves, entirely offline against bare "remote" repos plus
# visible checkouts under a throwaway temp directory:
#   1. `cc onboard --org ... --json` (read-only plan mode, no --apply)
#      reports exactly sixteen topology rows -- four components (knowledge,
#      cli, claude, codex) x four layers (personal, department, organization,
#      foundation) -- with the correct repository name and visible local path
#      per row.
#   2. Each row's action/sync_state matches the Git history state this gate
#      deliberately constructed for it: only `fast-forwardable` -> repair;
#      `exact` -> reuse/current; every other state (dirty, ahead-only,
#      divergent-identical-tree, divergent-different-content, wrong-origin,
#      unreadable) -> review.
#   3. The emitted report validates against the canonical schema
#      (docs/01-architecture/schemas/onboard.schema.json, v2.0).
#   4. ZERO mutation: every checkout's `git rev-parse HEAD` and
#      `git status --porcelain`, and every bare remote's `git ls-remote`, are
#      byte-identical before and after the run.
#   5. The packaged binary's report is structurally identical to the SOURCE
#      cc (claude-copilot's tools/cc dev install) run against the exact same
#      fixture.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/onboard-topology"
SCHEMA_PATH="${REPO_ROOT}/docs/01-architecture/schemas/onboard.schema.json"

CLAUDE_ROOT="${CT_TOPOLOGY_CLAUDE_ROOT:-/Volumes/Dev/Sites/COPILOT/claude-copilot}"
CC_PATH=""
SOURCE_CC=""
KEEP=false

die() {
    echo "packaged-cc topology contract: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cc-path)
            [[ $# -ge 2 ]] || die "--cc-path requires a value"
            CC_PATH="$2"; shift 2 ;;
        --source-cc)
            [[ $# -ge 2 ]] || die "--source-cc requires a value"
            SOURCE_CC="$2"; shift 2 ;;
        --claude-root)
            [[ $# -ge 2 ]] || die "--claude-root requires a value"
            CLAUDE_ROOT="$2"; shift 2 ;;
        --keep)
            KEEP=true; shift ;;
        -h|--help)
            sed -n '2,55p' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *)
            die "unknown option: $1" ;;
    esac
done

[[ -f "${SCHEMA_PATH}" ]] || die "canonical schema missing: ${SCHEMA_PATH}"

if [[ -z "${CC_PATH}" ]]; then
    echo "packaged-cc topology contract: building the fresh vendored cc..." >&2
    CC_PATH="$("${SCRIPT_DIR}/../build-fresh-vendored-cc.sh" \
        --source-root "${CLAUDE_ROOT}" \
        ${CT_TOPOLOGY_CC_REF:+--ref "${CT_TOPOLOGY_CC_REF}"})"
fi
case "${CC_PATH}" in
    /*) ;;
    *) CC_PATH="${REPO_ROOT}/${CC_PATH}" ;;
esac
[[ -x "${CC_PATH}" ]] || die "no executable cc at ${CC_PATH}"

if [[ -z "${SOURCE_CC}" ]]; then
    SOURCE_CC="${CLAUDE_ROOT}/tools/cc/.venv/bin/cc"
fi
[[ -x "${SOURCE_CC}" ]] || die \
    "no dev-install cc at ${SOURCE_CC} -- run 'cd ${CLAUDE_ROOT}/tools/cc && make dev' first"

for command in git uv shasum; do
    command -v "${command}" >/dev/null 2>&1 || die "${command} is required but was not found"
done

JSONSCHEMA_VENV="${REPO_ROOT}/.copilot/build-cache/jsonschema-venv"
if [[ ! -x "${JSONSCHEMA_VENV}/bin/python3" ]]; then
    echo "packaged-cc topology contract: preparing the schema-validation venv..." >&2
    uv venv --python 3.13 "${JSONSCHEMA_VENV}" >&2
    uv pip install --python "${JSONSCHEMA_VENV}/bin/python3" --quiet jsonschema >&2
fi
VALIDATOR_PY="${JSONSCHEMA_VENV}/bin/python3"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ct-cc-topology.XXXXXX")"
# Canonicalize away any double slash from a trailing-slash TMPDIR (common on
# macOS): Python's pathlib collapses "//" when a report's `local_path` is
# stringified, but this script's own string-built paths would not without
# this, breaking a literal comparison below for a reason that has nothing to
# do with the binary under test.
SCRATCH="$(cd "${SCRATCH}" && pwd)"
cleanup() {
    if [[ "${KEEP}" == true ]]; then
        echo "packaged-cc topology contract: kept scratch at ${SCRATCH}" >&2
    else
        rm -rf "${SCRATCH}"
    fi
}
trap cleanup EXIT

FIXTURE_ORG="fixture-org"
FIXTURE_OWNER="fixture-owner"
DEPT_UNIT="eng"
REMOTES_DIR="${SCRATCH}/fixture/remotes"
REPO_ROOT_DIR="${SCRATCH}/fixture/repo-root"
ROWS_TSV="${SCRATCH}/rows.tsv"
mkdir -p "${REMOTES_DIR}" "${REPO_ROOT_DIR}"

# HOME for the git-fixture-authoring commands below only (never used to
# invoke cc itself -- each cc invocation gets its own isolated HOME further
# down). Isolates commit authorship config from the real machine.
export HOME="${SCRATCH}/fixture-author-home"
mkdir -p "${HOME}"
git config --global user.email "fixture@example.invalid"
git config --global user.name "Fixture Author"
git config --global init.defaultBranch main

# --- the sixteen-row table: four components x four layers ------------------
# The two claude/codex `foundation` rows are the only ones using an HTTPS
# (not SSH-alias) source URL upstream -- see foundation_repo in onboard.py's
# _layer_manifest. This fixture never fakes HTTP transport (no local server,
# no /etc/hosts edit), so it deliberately assigns those two rows the
# `wrong-origin` state: a plainly mismatched origin remote, checked BEFORE
# any fetch is attempted, so no network path is needed at all for them. The
# remaining fourteen SSH-alias rows cover the other seven states, two rows
# each.
ROWS=(
    "knowledge personal exact"
    "knowledge department fast-forwardable"
    "knowledge organization dirty"
    "knowledge foundation ahead-only"
    "cli personal divergent-identical-tree"
    "cli department divergent-different-content"
    "cli organization unreadable"
    "cli foundation exact"
    "claude personal fast-forwardable"
    "claude department dirty"
    "claude organization ahead-only"
    "claude foundation wrong-origin"
    "codex personal divergent-identical-tree"
    "codex department divergent-different-content"
    "codex organization unreadable"
    "codex foundation wrong-origin"
)

: > "${ROWS_TSV}"
for row in "${ROWS[@]}"; do
    read -r component role state <<<"${row}"
    case "${role}" in
        personal)
            repo_name="${component}-copilot-private"
            url="git@github-personal:${FIXTURE_OWNER}/${repo_name}.git"
            ref="main"
            ;;
        department)
            repo_name="${component}-copilot-${DEPT_UNIT}"
            url="git@github-work:${FIXTURE_ORG}/${repo_name}.git"
            ref="main"
            ;;
        organization)
            repo_name="${component}-copilot-internal"
            url="git@github-work:${FIXTURE_ORG}/${repo_name}.git"
            ref="main"
            ;;
        foundation)
            repo_name="${component}-copilot"
            ref="1.0.0"
            if [[ "${component}" == "knowledge" || "${component}" == "cli" ]]; then
                url="git@github-work:Everyone-Needs-A-Copilot/${repo_name}.git"
            else
                url="https://github.com/Everyone-Needs-A-Copilot/${repo_name}.git"
            fi
            ;;
        *)
            die "unknown role ${role}"
            ;;
    esac

    local_path="${REPO_ROOT_DIR}/${repo_name}"
    printf '%s\t%s\t%s\t%s\t%s\n' "${component}" "${role}" "${state}" "${repo_name}" "${local_path}" >> "${ROWS_TSV}"

    if [[ "${state}" == "unreadable" ]]; then
        mkdir -p "${local_path}"
        echo "not a git repository" > "${local_path}/README.txt"
        continue
    fi

    if [[ "${state}" == "wrong-origin" ]]; then
        git init -q -b main "${local_path}"
        echo seed > "${local_path}/seed.txt"
        git -C "${local_path}" add seed.txt
        git -C "${local_path}" commit -q -m seed
        git -C "${local_path}" remote add origin "https://github.com/someone-else/unrelated-repo.git"
        continue
    fi

    git init --bare -q -b main "${REMOTES_DIR}/${repo_name}.git"
    bare="${REMOTES_DIR}/${repo_name}.git"
    work="$(mktemp -d "${SCRATCH}/work.XXXXXX")"
    git init -q -b main "${work}"
    echo seed > "${work}/seed.txt"
    git -C "${work}" add seed.txt
    git -C "${work}" commit -q -m seed
    if [[ "${role}" == foundation ]]; then
        git -C "${work}" tag "${ref}"
        git -C "${work}" push -q "${bare}" main "${ref}"
    else
        git -C "${work}" push -q "${bare}" main
    fi
    git clone -q "${bare}" "${local_path}"
    git -C "${local_path}" remote set-url origin "${url}"

    case "${state}" in
        exact)
            : # local HEAD already equals the bare tip; nothing further
            ;;
        fast-forwardable)
            echo advance >> "${work}/seed.txt"
            git -C "${work}" commit -aq -m advance
            git -C "${work}" push -q "${bare}" main
            ;;
        dirty)
            echo unstaged-change >> "${local_path}/seed.txt"
            ;;
        ahead-only)
            echo local-only >> "${local_path}/seed.txt"
            git -C "${local_path}" commit -aq -m local-only
            ;;
        divergent-identical-tree)
            git -C "${work}" commit -q --allow-empty -m remote-diverge
            git -C "${work}" push -q "${bare}" main
            git -C "${local_path}" commit -q --allow-empty -m local-diverge
            ;;
        divergent-different-content)
            echo remote-change >> "${work}/seed.txt"
            git -C "${work}" commit -aq -m remote-change
            git -C "${work}" push -q "${bare}" main
            echo local-change > "${local_path}/local-only.txt"
            git -C "${local_path}" add local-only.txt
            git -C "${local_path}" commit -aq -m local-change
            ;;
        *)
            die "unknown state ${state} for row ${component} ${role}"
            ;;
    esac
    rm -rf "${work}"
done

echo "packaged-cc topology contract: fixture built (16 rows, 8 history states) at ${SCRATCH}/fixture" >&2

# --- the handoff GitHub would otherwise serve ------------------------------
cat > "${SCRATCH}/handoff.yml" <<YAML
schema_version: "2.0"
org: ${FIXTURE_ORG}
harness:
  - claude
  - codex
components:
  - knowledge
  - cli
  - claude
  - codex
departments:
  - unit: ${DEPT_UNIT}
foundation:
  refs:
    knowledge: "1.0.0"
    cli: "1.0.0"
    claude: "1.0.0"
    codex: "1.0.0"
YAML
base64 < "${SCRATCH}/handoff.yml" | tr -d '\n' > "${SCRATCH}/handoff.b64"

FIXTURE_BIN="${SCRATCH}/bin"
mkdir -p "${FIXTURE_BIN}"
cp "${FIXTURES_DIR}/gh-stub" "${FIXTURE_BIN}/gh"
chmod +x "${FIXTURE_BIN}/gh"

# --- fingerprint: proves zero mutation across a run -------------------------
fingerprint() {
    for d in "${REPO_ROOT_DIR}"/*/; do
        name="$(basename "${d}")"
        if [[ -d "${d}.git" ]]; then
            head_sha="$(git -C "${d}" rev-parse HEAD 2>/dev/null || echo "NONE")"
            porcelain="$(git -C "${d}" status --porcelain 2>/dev/null | shasum -a 256 | awk '{print $1}')"
            echo "${name} HEAD=${head_sha} STATUS=${porcelain}"
        else
            echo "${name} NOT-A-GIT-REPO"
        fi
    done
    for b in "${REMOTES_DIR}"/*.git; do
        [[ -d "${b}" ]] || continue
        name="$(basename "${b}")"
        lsr="$(git ls-remote "${b}" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
        echo "${name} LS-REMOTE=${lsr}"
    done
}

run_cc() {
    # run_cc <cc-binary> <home-dir> <out-json>
    local binary="$1" home_dir="$2" out_json="$3"
    mkdir -p "${home_dir}"
    set +e
    env \
        HOME="${home_dir}" \
        PATH="${FIXTURE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
        GIT_SSH_COMMAND="${FIXTURES_DIR}/fake-ssh.sh" \
        FAKE_SSH_REMOTES_DIR="${REMOTES_DIR}" \
        STUB_GH_OWNER="${FIXTURE_OWNER}" \
        STUB_GH_ORG="${FIXTURE_ORG}" \
        STUB_GH_HANDOFF_B64_FILE="${SCRATCH}/handoff.b64" \
        STUB_GH_DEPARTMENT_UNIT="${DEPT_UNIT}" \
        "${binary}" onboard --org "${FIXTURE_ORG}" --products claude,codex \
            --repository-root "${REPO_ROOT_DIR}" --json \
        > "${out_json}" 2> "${out_json}.stderr"
    local exit_code=$?
    set -e
    # `onboard` exits 1 on `result: blocked`, which is the EXPECTED outcome
    # here (ssh stage blocks in a clean, identity-less scratch HOME, right
    # after topology is fully computed -- see the script header). Only a
    # genuinely empty/unparseable report is a hard failure; that is caught
    # by the JSON validation immediately below each call site.
    if [[ ! -s "${out_json}" ]]; then
        die "${binary} produced no output (exit ${exit_code}); stderr: $(cat "${out_json}.stderr")"
    fi
}

fingerprint > "${SCRATCH}/fp-before.txt"

# Both runs deliberately share ONE isolated HOME: it stays untouched either
# way (never-destroy; see the ssh-identity-blocks-first analysis in the
# header), and sharing it means every path a report embeds (e.g. the planned
# layer-manifest destination_path) is identical between the two invocations
# too, so the source-vs-packaged diff below never has to special-case a
# per-run HOME as a "volatile" field.
CC_HOME="${SCRATCH}/home"

echo "packaged-cc topology contract: running SOURCE cc (${SOURCE_CC})..." >&2
run_cc "${SOURCE_CC}" "${CC_HOME}" "${SCRATCH}/report-source.json"

echo "packaged-cc topology contract: running PACKAGED cc (${CC_PATH})..." >&2
run_cc "${CC_PATH}" "${CC_HOME}" "${SCRATCH}/report-packaged.json"

fingerprint > "${SCRATCH}/fp-after.txt"

if ! diff -u "${SCRATCH}/fp-before.txt" "${SCRATCH}/fp-after.txt" > "${SCRATCH}/fp.diff"; then
    cat "${SCRATCH}/fp.diff" >&2
    die "fixture mutated by a read-only plan run (HEAD/status/ls-remote changed) -- see diff above"
fi
echo "packaged-cc topology contract: zero mutation confirmed (HEAD/status/ls-remote unchanged)" >&2

"${VALIDATOR_PY}" "${SCRIPT_DIR}/fixtures/onboard-topology/assert_topology_report.py" \
    --schema "${SCHEMA_PATH}" \
    --rows "${ROWS_TSV}" \
    --packaged "${SCRATCH}/report-packaged.json" \
    --source "${SCRATCH}/report-source.json" \
    --repo-root "${REPO_ROOT_DIR}"

echo "packaged-cc topology contract: PASS (16/16 rows, schema 2.0, zero mutation, source==packaged) -- ${CC_PATH}"
