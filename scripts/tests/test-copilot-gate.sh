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
    10: {
        "id": 10,
        "task_id": 1,
        "type": "test",
        "title": "Historical QA approval",
        "content": old_content,
        "guard": "title=clean;content=clean",
    },
    20: {
        "id": 20,
        "task_id": 1,
        "type": "test",
        "title": "Current QA approval",
        "content": current_content,
        "guard": "title=clean;content=clean",
    },
}
if scenario not in {"legacy", "legacy-contradictory"}:
    metadata.update(
        {
            "implementationWorkProductId": 100,
            "implementationCommit": implementation_commit,
            "implementationTree": implementation_tree,
            "qaWorkProductId": 20,
            "qaWorkProductTitle": "Current QA approval",
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
elif scenario == "wrong-task":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], task_id=2)
elif scenario == "wrong-type":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], type="code")
elif scenario == "wrong-title":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], title="Unrelated test evidence")
elif scenario == "wrong-returned-id":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], id=21)
elif scenario == "missing-title-binding":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    metadata.pop("qaWorkProductTitle")
elif scenario == "dirty-guard":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], guard="title=modified;content=clean")
elif scenario == "missing-guard":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20].pop("guard")
elif scenario == "missing-artifact":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], content=current_content.replace("ARTIFACT:", "Evidence:"))
elif scenario == "rejected-verdict":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], content=current_content.replace("VERDICT: APPROVED-WITH-MINOR-FIXES", "VERDICT: REJECTED"))
elif scenario == "approved-then-rejected":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], content=current_content + "VERDICT: REJECTED\n")
elif scenario == "rejected-then-approved":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], content="VERDICT: REJECTED\n" + current_content)
elif scenario == "duplicate-approved":
    metadata.update({"qaStatus": "approved", "qaVerdict": "APPROVED"})
    wps[20] = dict(wps[20], content=current_content + "VERDICT: APPROVED\n")
elif scenario == "legacy-contradictory":
    wps[10] = dict(wps[10], content=old_content + "VERDICT: REJECTED\n")
    wps[20] = dict(wps[20], content=current_content + "VERDICT: REJECTED\n")
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
run_case wrong-task 1
run_case wrong-type 1
run_case wrong-title 1
run_case wrong-returned-id 1
run_case missing-title-binding 1
run_case dirty-guard 1
run_case missing-guard 1
run_case missing-artifact 1
run_case rejected-verdict 1
run_case approved-then-rejected 1
run_case rejected-then-approved 1
run_case duplicate-approved 1
run_case old-indexed 1
run_case legacy-contradictory 1

printf 'Results: %s passed, %s failed\n' "${passed}" "${failed}"
[[ "${failed}" == 0 ]]
