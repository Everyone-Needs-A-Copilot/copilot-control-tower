#!/usr/bin/env bash
# Build an UNSIGNED, test-only `cc` helper binary from a claude-copilot
# checkout, using the same PyInstaller onefile packaging strategy as
# scripts/package-cc-macos-release.sh in that repo (tools/cc/scripts/
# cc_frozen_entry.py as the entry point, --paths tools/cc/src). This is
# deliberately lighter than the real release recipe: no pinned universal2
# Python.org toolchain download, no arm64/x86_64 lipo merge, no Developer ID
# codesign, no notarization, no device-flow/Finder-onboard network probes.
# Those steps require release secrets (signing identity, notary credentials)
# that a QA gate must never depend on. What this script preserves is the
# part that matters for a topology-contract gate: the exact onboard.py
# source at an exact commit, frozen into the same one-file executable form
# that will actually ship, so a schema/behavior regression in the frozen
# binary (as opposed to only the Python source) cannot slip through.
#
# Usage:
#   scripts/build-fresh-vendored-cc.sh \
#     [--source-root /path/to/claude-copilot] \
#     [--ref <branch-or-commit>] \
#     [--output-dir /path/to/output] \
#     [--force]
#
# Prints the absolute path to the built `cc` binary as the LAST line of
# stdout (all other progress goes to stderr), so callers can do:
#   CC_PATH="$(scripts/build-fresh-vendored-cc.sh)"
#
# The build never writes into --source-root: source is read via
# `git archive <commit>` into a private scratch directory, so a dirty or
# untracked working tree in --source-root is neither required nor touched,
# and this script never creates or modifies any file inside --source-root.
#
# Output lands under .copilot/build-cache/cc-fresh/<source-commit>/ by
# default (gitignored; never release/). Re-running with the same resolved
# commit reuses the cached artifact unless --force is given.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOURCE_ROOT="/Volumes/Dev/Sites/COPILOT/claude-copilot"
REF=""
OUTPUT_DIR=""
FORCE=false

die() {
    echo "build-fresh-vendored-cc: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-root)
            [[ $# -ge 2 ]] || die "--source-root requires a value"
            SOURCE_ROOT="$2"
            shift 2
            ;;
        --ref)
            [[ $# -ge 2 ]] || die "--ref requires a value"
            REF="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || die "--output-dir requires a value"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            sed -n '2,33p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

[[ -d "${SOURCE_ROOT}/.git" ]] || die "no git checkout at --source-root ${SOURCE_ROOT}"
[[ -f "${SOURCE_ROOT}/tools/cc/pyproject.toml" ]] || die "${SOURCE_ROOT} has no tools/cc package"

if [[ -z "${REF}" ]]; then
    REF="$(git -C "${SOURCE_ROOT}" rev-parse --abbrev-ref HEAD)"
fi
commit="$(git -C "${SOURCE_ROOT}" rev-parse "${REF}")"

if [[ -z "${OUTPUT_DIR}" ]]; then
    OUTPUT_DIR="${REPO_ROOT}/.copilot/build-cache/cc-fresh/${commit}"
fi
case "${OUTPUT_DIR}" in
    /*) ;;
    *) OUTPUT_DIR="${REPO_ROOT}/${OUTPUT_DIR}" ;;
esac

artifact="${OUTPUT_DIR}/cc"
metadata="${OUTPUT_DIR}/BUILD_METADATA.json"

if [[ "${FORCE}" == false && -x "${artifact}" && -f "${metadata}" ]]; then
    cached_commit="$(/usr/bin/python3 -c \
        'import json,sys; print(json.load(open(sys.argv[1])).get("source_commit",""))' \
        "${metadata}" 2>/dev/null || true)"
    if [[ "${cached_commit}" == "${commit}" ]]; then
        echo "build-fresh-vendored-cc: cache hit for ${commit} at ${artifact}" >&2
        echo "${artifact}"
        exit 0
    fi
fi

for command in git uv shasum lipo; do
    command -v "${command}" >/dev/null 2>&1 || die "${command} is required but was not found"
done

scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-cc-fresh-build.XXXXXX")"
cleanup() {
    rm -rf "${scratch}"
}
trap cleanup EXIT

echo "build-fresh-vendored-cc: archiving tools/cc at ${commit} (never touching ${SOURCE_ROOT})" >&2
mkdir -p "${scratch}/source"
git -C "${SOURCE_ROOT}" archive "${commit}" -- tools/cc | tar -x -C "${scratch}/source"
[[ -f "${scratch}/source/tools/cc/pyproject.toml" ]] || die "git archive did not produce tools/cc"

entry_point="${scratch}/source/tools/cc/scripts/cc_frozen_entry.py"
[[ -f "${entry_point}" ]] || die "missing frozen entry point at ${commit}: tools/cc/scripts/cc_frozen_entry.py"

echo "build-fresh-vendored-cc: building an isolated venv (python 3.13, uv)" >&2
uv venv --python 3.13 "${scratch}/venv" >&2
uv pip install --python "${scratch}/venv/bin/python3" --quiet \
    "${scratch}/source/tools/cc" pyinstaller >&2

echo "build-fresh-vendored-cc: freezing cc (onefile, native arch, unsigned)" >&2
"${scratch}/venv/bin/pyinstaller" \
    --clean \
    --noconfirm \
    --onefile \
    --console \
    --name cc \
    --paths "${scratch}/source/tools/cc/src" \
    --distpath "${scratch}/pyinstaller-dist" \
    --workpath "${scratch}/pyinstaller-work" \
    --specpath "${scratch}/pyinstaller-spec" \
    "${entry_point}" >&2

built="${scratch}/pyinstaller-dist/cc"
[[ -x "${built}" ]] || die "PyInstaller did not produce ${built}"

expected_version="$(
    awk -F '"' '/^__version__ = / { print $2; exit }' \
        "${scratch}/source/tools/cc/src/cc/__init__.py"
)"
actual_version="$("${built}" --version)"
[[ "${actual_version}" == "cc version ${expected_version}" ]] ||
    die "frozen cc returned unexpected version: ${actual_version} (expected cc version ${expected_version})"

mkdir -p "${OUTPUT_DIR}"
cp "${built}" "${artifact}"
chmod 755 "${artifact}"
artifact_sha="$(shasum -a 256 "${artifact}" | awk '{print $1}')"
python_version="$("${scratch}/venv/bin/python3" --version | awk '{print $2}')"
pyinstaller_version="$("${scratch}/venv/bin/pyinstaller" --version 2>/dev/null | tail -1)"
arch="$(lipo -archs "${artifact}" 2>/dev/null || uname -m)"

cat > "${metadata}" <<EOF
{
  "schema_version": "1.0-test-build",
  "note": "UNSIGNED development build for QA gate testing only (task 209) -- never a release artifact. Built by scripts/build-fresh-vendored-cc.sh, not scripts/package-cc-macos-release.sh.",
  "product": "claude-copilot-cc",
  "version": "${expected_version}",
  "source_repo": "${SOURCE_ROOT}",
  "source_ref": "${REF}",
  "source_commit": "${commit}",
  "build_tool_commit": "$(git -C "${REPO_ROOT}" rev-parse HEAD)",
  "architectures": "${arch}",
  "python_version": "${python_version}",
  "pyinstaller_version": "${pyinstaller_version}",
  "signed": false,
  "notarized": false,
  "sha256": "${artifact_sha}"
}
EOF

echo "build-fresh-vendored-cc: ready" >&2
echo "  artifact: ${artifact}" >&2
echo "  sha256:   ${artifact_sha}" >&2
echo "  source:   ${SOURCE_ROOT}@${commit}" >&2
echo "${artifact}"
