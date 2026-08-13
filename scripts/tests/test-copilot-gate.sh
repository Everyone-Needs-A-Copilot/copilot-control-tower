#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="${ROOT}/scripts/copilot-gate.sh"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "${FIXTURE_ROOT}"' EXIT

mkdir -p "${FIXTURE_ROOT}/bin"
cat > "${FIXTURE_ROOT}/bin/tc" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys


implementation_commit = "a" * 40
implementation_tree = "b" * 40
scenario = os.environ["GATE_SCENARIO"]
old_content = """Task: TASK-1 | Implementation: WP-99
**ARTIFACT: test-run | old behavior passed**
**VERDICT: APPROVED**
"""
current_content = f"""Task: TASK-1
Implementation: WP 100
Commit: `{implementation_commit}`
Tree: `{implementation_tree}`
- ARTIFACT: diff-check | current identities match
**VERDICT: APPROVED-WITH-MINOR-FIXES**
"""

metadata = {"requiresQa": True}
wps = {
    10: {"id": 10, "task_id": 1, "type": "test", "content": old_content},
    20: {"id": 20, "task_id": 1, "type": "test", "content": current_content},
}
if scenario != "legacy":
    metadata.update(
        {
            "implementationWorkProductId": 100,
            "implementationCommit": implementation_commit,
            "implementationTree": implementation_tree,
            "qaWorkProductId": 20,
        }
    )
if scenario == "pending":
    metadata.update({"qaStatus": "pending-wp100", "qaVerdict": "PENDING"})
elif scenario == "approved":
    metadata.update(
        {
            "qaStatus": "APPROVED-WP100",
            "qaVerdict": "approved-with-minor-fixes",
        }
    )
elif scenario == "wrong-binding":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], content=current_content.replace(implementation_tree, "c" * 40))
elif scenario == "old-indexed":
    metadata.update(
        {
            "qaStatus": "approved",
            "qaVerdict": "APPROVED",
            "qaWorkProductId": 10,
        }
    )

task = {"id": 1, "title": "Fixture task", "metadata": json.dumps(metadata)}
args = sys.argv[1:]
if args[:2] == ["task", "get"]:
    print(json.dumps(task))
elif args[:2] == ["task", "list"]:
    print(json.dumps([task]))
elif args[:2] == ["wp", "list"]:
    print(json.dumps(list(wps.values())))
elif args[:2] == ["wp", "get"]:
    print(json.dumps(wps[int(args[2])]))
else:
    raise SystemExit(2)
PY
chmod 0755 "${FIXTURE_ROOT}/bin/tc"

passed=0
failed=0

run_case() {
  local scenario="$1"
  local expected="$2"
  local output status
  set +e
  output="$(PATH="${FIXTURE_ROOT}/bin:${PATH}" GATE_SCENARIO="${scenario}" "${GATE}" --task 1 2>&1)"
  status=$?
  set -e
  if [[ "${status}" == "${expected}" ]]; then
    printf 'PASS: %s exit=%s\n' "${scenario}" "${status}"
    passed=$((passed + 1))
  else
    printf 'FAIL: %s expected=%s actual=%s output=%s\n' "${scenario}" "${expected}" "${status}" "${output}"
    failed=$((failed + 1))
  fi
}

run_case legacy 0
run_case pending 1
run_case approved 0
run_case wrong-binding 1
run_case old-indexed 1

printf 'Results: %s passed, %s failed\n' "${passed}" "${failed}"
[[ "${failed}" == 0 ]]
