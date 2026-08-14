#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="${ROOT_DIR}/scripts/foundation-snapshot-release.py"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/foundation-snapshot-test.XXXXXX")"
trap 'rm -rf "${SCRATCH}"' EXIT

REPO="${SCRATCH}/foundation"
ORIGIN="${SCRATCH}/origin.git"
KEY="${SCRATCH}/release"

# A real bare remote, so a --publish run has somewhere real to push to and
# we can independently re-verify the pushed tag's ancestry afterward --
# never taking the tool's own JSON claim as the proof.
git init --quiet --bare -b main "${ORIGIN}"

git init --quiet -b main "${REPO}"
git -C "${REPO}" config user.name "Foundation Test"
git -C "${REPO}" config user.email "foundation-test@example.invalid"
git -C "${REPO}" remote add origin "${ORIGIN}"
mkdir -p "${REPO}/.claude/agents" "${REPO}/.claude/skills/testing"
printf '%s\n' '# QA' > "${REPO}/.claude/agents/qa.md"
printf '%s\n' '# Testing' > "${REPO}/.claude/skills/testing/SKILL.md"
git -C "${REPO}" add .
git -C "${REPO}" commit --quiet -m "unsigned source"
# A second ordinary commit, so the release is cut from a real chain (count
# > 1), not the repository's very first commit -- matches what a genuine
# release-cut point looks like, not just the minimal case that happens to
# pass.
printf '%s\n' '# QA v2' > "${REPO}/.claude/agents/qa.md"
git -C "${REPO}" commit --quiet -am "second commit"
git -C "${REPO}" push --quiet origin main

ssh-keygen -q -t ed25519 -N "" -f "${KEY}"
FINGERPRINT="$(ssh-keygen -lf "${KEY}.pub" -E sha256 | awk '{print $2}')"

# ---------------------------------------------------------------------------
# 1. A GOOD cut: dry run first, then --publish, then independently re-prove
#    ancestry against the pushed remote tag with plain git plumbing -- the
#    exact commands rc.rc3 / stack.cs_ancestor run.
# ---------------------------------------------------------------------------

OUTPUT="$(
  "${TOOL}" \
    --repo "${REPO}" \
    --source HEAD \
    --branch main \
    --tag v1.0.0 \
    --product claude \
    --signing-key "${KEY}.pub" \
    --approved-fingerprint "${FINGERPRINT}"
)"

python3 - "${OUTPUT}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["schema_version"] == "1.1"
assert payload["tag"] == "v1.0.0"
assert payload["product"] == "claude"
assert payload["branch"] == "main"
assert payload["ancestry_verified"] is True
assert payload["tag_signature"] == "verified"
assert payload["release_commit"] == payload["source_commit"]
assert payload["executable_items_verified"] == 2
assert payload["published"] is False
assert payload["signer_fingerprint"].startswith("SHA256:")
PY

if git -C "${REPO}" show-ref --verify --quiet refs/tags/v1.0.0; then
  echo "FAIL: dry run changed the source repository" >&2
  exit 1
fi
if git ls-remote --tags "${ORIGIN}" refs/tags/v1.0.0 | grep -q .; then
  echo "FAIL: dry run pushed to the remote" >&2
  exit 1
fi

# Knowledge foundations use the same ancestry and signing controls while
# inventorying their executable-adjacent .claude, plugin, and script surfaces.
KNOWLEDGE_OUTPUT="$(
  "${TOOL}" \
    --repo "${REPO}" \
    --source HEAD \
    --branch main \
    --tag v1.0.1 \
    --product knowledge \
    --signing-key "${KEY}.pub" \
    --approved-fingerprint "${FINGERPRINT}"
)"

python3 - "${KNOWLEDGE_OUTPUT}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["product"] == "knowledge"
assert payload["release_commit"] == payload["source_commit"]
assert payload["executable_items_verified"] == 2
assert payload["ancestry_verified"] is True
assert payload["tag_signature"] == "verified"
assert payload["published"] is False
PY

if git -C "${REPO}" show-ref --verify --quiet refs/tags/v1.0.1; then
  echo "FAIL: Knowledge dry run changed the source repository" >&2
  exit 1
fi

"${TOOL}" \
  --repo "${REPO}" \
  --source HEAD \
  --branch main \
  --tag v1.0.0 \
  --product claude \
  --signing-key "${KEY}.pub" \
  --approved-fingerprint "${FINGERPRINT}" \
  --publish \
  >/dev/null

# Independent re-verification against the real pushed remote -- not the
# tool's own report. These are exactly rc.rc3 / stack.cs_ancestor's two
# assertions.
REMOTE_TAG_COMMIT="$(git -C "${REPO}" ls-remote --tags "${ORIGIN}" 'refs/tags/v1.0.0^{}' | awk '{print $1}')"
if [ -z "${REMOTE_TAG_COMMIT}" ]; then
  echo "FAIL: v1.0.0 was not published to the remote" >&2
  exit 1
fi
git -C "${REPO}" fetch --quiet origin "refs/tags/v1.0.0:refs/tags/v1.0.0-check"
COUNT="$(git -C "${REPO}" rev-list --count refs/tags/v1.0.0-check)"
if [ "${COUNT}" -le 1 ]; then
  echo "FAIL: v1.0.0 is a root commit (rev-list --count=${COUNT}) -- reproduces RC-3" >&2
  exit 1
fi
if ! git -C "${REPO}" merge-base --is-ancestor refs/tags/v1.0.0-check origin/main; then
  echo "FAIL: v1.0.0 is not an ancestor of origin/main -- reproduces RC-3" >&2
  exit 1
fi
echo "good cut proof: v1.0.0 rev-list --count=${COUNT}, is an ancestor of origin/main"

# ---------------------------------------------------------------------------
# 2. A BAD cut must be refused, unconditionally, before any tag is written
#    -- even without --publish. Reproduces RC-3's exact defect (a parentless
#    commit unreachable from the branch) using the identical technique the
#    conformance harness's FleetFactory fixture uses
#    (`tools/cc/tests/conformance/conftest.py::git_orphan_tag` in
#    claude-copilot: `git commit-tree` against no parent), then points
#    --source at it.
# ---------------------------------------------------------------------------

ORPHAN_TREE="$(git -C "${REPO}" rev-parse HEAD^{tree})"
ORPHAN_COMMIT="$(git -C "${REPO}" commit-tree "${ORPHAN_TREE}" -m "orphan snapshot, unreachable from main")"

if "${TOOL}" \
  --repo "${REPO}" \
  --source "${ORPHAN_COMMIT}" \
  --branch main \
  --tag v9.9.9 \
  --product claude \
  --signing-key "${KEY}.pub" \
  --approved-fingerprint "${FINGERPRINT}" \
  >"${SCRATCH}/orphan.out" 2>"${SCRATCH}/orphan.err"; then
  echo "FAIL: an orphan, non-ancestor commit was accepted as a release" >&2
  exit 1
fi
python3 - "${SCRATCH}/orphan.err" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert payload["error"]["code"] == "foundation-release-refused"
assert "not an ancestor" in payload["error"]["message"]
assert "RC-3" in payload["error"]["message"]
PY
if git -C "${REPO}" show-ref --verify --quiet refs/tags/v9.9.9; then
  echo "FAIL: the refused bad cut still left a local tag behind" >&2
  exit 1
fi
if git ls-remote --tags "${ORIGIN}" refs/tags/v9.9.9 | grep -q .; then
  echo "FAIL: the refused bad cut still reached the remote" >&2
  exit 1
fi
echo "bad cut proof: orphan/non-ancestor source was refused before any tag was written"

# ---------------------------------------------------------------------------
# 3. Existing guard-rail regressions: mismatched fingerprint, dirty tree.
# ---------------------------------------------------------------------------

if "${TOOL}" \
  --repo "${REPO}" \
  --tag v1.0.1 \
  --product claude \
  --signing-key "${KEY}.pub" \
  --approved-fingerprint "SHA256:not-the-approved-key" \
  >"${SCRATCH}/fingerprint.out" 2>"${SCRATCH}/fingerprint.err"; then
  echo "FAIL: mismatched approved fingerprint was accepted" >&2
  exit 1
fi
python3 - "${SCRATCH}/fingerprint.err" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert payload["error"]["code"] == "foundation-release-refused"
assert "approved-fingerprint" in payload["error"]["message"]
PY

printf '%s\n' 'dirty' > "${REPO}/uncommitted.txt"
if "${TOOL}" \
  --repo "${REPO}" \
  --tag v1.0.1 \
  --product claude \
  --signing-key "${KEY}.pub" \
  --approved-fingerprint "${FINGERPRINT}" \
  >"${SCRATCH}/dirty.out" 2>"${SCRATCH}/dirty.err"; then
  echo "FAIL: dirty source repository was accepted" >&2
  exit 1
fi
python3 - "${SCRATCH}/dirty.err" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert payload["error"]["code"] == "foundation-release-refused"
assert "dirty" in payload["error"]["message"]
PY

echo "foundation snapshot release tests: PASS"
