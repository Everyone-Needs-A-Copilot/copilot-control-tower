#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="${ROOT_DIR}/scripts/foundation-snapshot-release.py"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/foundation-snapshot-test.XXXXXX")"
trap 'rm -rf "${SCRATCH}"' EXIT

REPO="${SCRATCH}/foundation"
KEY="${SCRATCH}/release"

git init --quiet "${REPO}"
git -C "${REPO}" config user.name "Foundation Test"
git -C "${REPO}" config user.email "foundation-test@example.invalid"
git -C "${REPO}" remote add origin "${SCRATCH}/unused-origin.git"
mkdir -p "${REPO}/.claude/agents" "${REPO}/.claude/skills/testing"
printf '%s\n' '# QA' > "${REPO}/.claude/agents/qa.md"
printf '%s\n' '# Testing' > "${REPO}/.claude/skills/testing/SKILL.md"
git -C "${REPO}" add .
git -C "${REPO}" commit --quiet -m "unsigned source"

ssh-keygen -q -t ed25519 -N "" -f "${KEY}"
FINGERPRINT="$(ssh-keygen -lf "${KEY}.pub" -E sha256 | awk '{print $2}')"

OUTPUT="$(
  "${TOOL}" \
    --repo "${REPO}" \
    --source HEAD \
    --tag v1.0.0 \
    --product claude \
    --signing-key "${KEY}.pub" \
    --approved-fingerprint "${FINGERPRINT}"
)"

python3 - "${OUTPUT}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["schema_version"] == "1.0"
assert payload["tag"] == "v1.0.0"
assert payload["product"] == "claude"
assert payload["commit_signature"] == "verified"
assert payload["tag_signature"] == "verified"
assert payload["executable_items_verified"] == 2
assert payload["published"] is False
assert payload["signer_fingerprint"].startswith("SHA256:")
PY

if git -C "${REPO}" show-ref --verify --quiet refs/tags/v1.0.0; then
  echo "FAIL: dry run changed the source repository" >&2
  exit 1
fi

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
