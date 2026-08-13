#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/copilot-gate.sh [--task TASK_ID]

Checks Codex Copilot QA-gate state in tc. A task that declares
metadata.requiresQa=true and indexes an implementation must have approved
primary QA metadata plus an explicitly indexed test work product. That work
product must include a passing VERDICT, an ARTIFACT marker, and references to
the current implementation work product and commit/tree identities when set.
The indexed work product title must exactly match metadata.qaWorkProductTitle,
its returned ID must exactly match metadata.qaWorkProductId, and its Task
Copilot guard must be exactly title=clean;content=clean. Evidence must contain
exactly one recognized VERDICT line; contradictory verdicts fail closed.

Legacy fallback: only a task with none of implementationWorkProductId,
implementationCommit, or implementationTree may use any passing attached test
work product. Metadata is never accepted as evidence by itself.

Accepted artifact markers:
  ARTIFACT: test-run|...
  ARTIFACT: file-check|...
  ARTIFACT: diff-check|...
  ARTIFACT: screenshot-check|...
  ARTIFACT: a11y-check|...
  ARTIFACT: design-fidelity-check|...

Accepted passing verdicts:
  VERDICT: APPROVED
  VERDICT: APPROVED-WITH-MINOR-FIXES
EOF
}

TASK_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      TASK_ID="${2:-}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v tc >/dev/null 2>&1; then
  echo "copilot-gate: tc is not installed or not on PATH" >&2
  exit 2
fi

python3 - "$TASK_ID" <<'PY'
import json
import re
import subprocess
import sys


task_id = sys.argv[1]


def run_json(cmd):
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    text = result.stdout.strip()
    return json.loads(text) if text else None


def metadata(task):
    raw = task.get("metadata")
    if not raw:
        return {}
    if isinstance(raw, dict):
        return raw
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def task_wps(tid):
    try:
        return run_json(["tc", "wp", "list", "--task", str(tid), "--json"]) or []
    except subprocess.CalledProcessError:
        return []


def full_wp(wid):
    if not wid:
        return {}, ""
    try:
        full = run_json(["tc", "wp", "get", str(wid), "--json"]) or {}
    except subprocess.CalledProcessError:
        return {}, ""
    return full, str(full.get("content") or "")


VERDICT_RE = re.compile(
    r"^\s*(?:[-*]\s*)?(?:\*\*)?VERDICT:\s*"
    r"(APPROVED-WITH-MINOR-FIXES|APPROVED|REJECTED)\b"
    r"(?:\*\*)?\s*[.!]?\s*$",
    re.IGNORECASE | re.MULTILINE,
)
ARTIFACT_RE = re.compile(
    r"^\s*(?:[-*]\s*)?(?:\*\*)?ARTIFACT:\s*"
    r"(test-run|file-check|diff-check|screenshot-check|a11y-check|design-fidelity-check)"
    r"\s*\|\s*.+?(?:\*\*)?\s*$",
    re.IGNORECASE | re.MULTILINE,
)


def approved_with_artifact(content):
    verdicts = VERDICT_RE.findall(content)
    return bool(
        len(verdicts) == 1
        and verdicts[0].casefold()
        in {"approved", "approved-with-minor-fixes"}
        and ARTIFACT_RE.search(content)
    )


def approved_primary(meta):
    status = str(meta.get("qaStatus") or "").strip().casefold()
    verdict = str(meta.get("qaVerdict") or "").strip().casefold()
    return status.startswith("approved") and verdict in {
        "approved",
        "approved-with-minor-fixes",
    }


def has_current_implementation(meta):
    return any(
        meta.get(key) not in (None, "")
        for key in (
            "implementationWorkProductId",
            "implementationCommit",
            "implementationTree",
        )
    )


def work_product_metadata(full):
    raw = full.get("metadata")
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            value = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        return value if isinstance(value, dict) else {}
    return {}


def binds_current_implementation(full, content, meta):
    evidence_meta = work_product_metadata(full)
    implementation_wp = meta.get("implementationWorkProductId")
    if implementation_wp not in (None, ""):
        value = re.escape(str(implementation_wp))
        content_bound = re.search(
            rf"(?i)\bImplementation(?:\s+work\s+product)?\s*[:=]?\s*"
            rf"(?:WP[- ]?)?{value}\b",
            content,
        )
        metadata_bound = str(evidence_meta.get("implementationWorkProductId")) == str(
            implementation_wp
        )
        if not content_bound and not metadata_bound:
            return False
    for key in ("implementationCommit", "implementationTree"):
        value = str(meta.get(key) or "").strip()
        label = "commit" if key == "implementationCommit" else "tree"
        content_bound = re.search(
            rf"(?i)\b(?:Reviewed\s+)?{label}\s*[:=]?\s*`?"
            rf"(?<![0-9a-f]){re.escape(value)}(?![0-9a-f])",
            content,
        )
        metadata_bound = str(evidence_meta.get(key)) == value
        if value and not content_bound and not metadata_bound:
            return False
    return True


def valid_test_wp(
    full,
    content,
    task_id,
    *,
    expected_id=None,
    expected_title=None,
    require_clean_guard=False,
):
    wp_task_id = full.get("task_id", full.get("task"))
    return (
        full.get("type", full.get("type_")) == "test"
        and str(wp_task_id) == str(task_id)
        and (expected_id is None or str(full.get("id")) == str(expected_id))
        and (expected_title is None or full.get("title") == expected_title)
        and (
            not require_clean_guard
            or full.get("guard") == "title=clean;content=clean"
        )
        and approved_with_artifact(content)
    )


if task_id:
    tasks = [run_json(["tc", "task", "get", task_id, "--json"])]
else:
    tasks = run_json(["tc", "task", "list", "--json"]) or []

blocked = []
checked = 0

for task in tasks:
    if not task:
        continue
    meta = metadata(task)
    requires_qa = bool(meta.get("requiresQa"))
    if not requires_qa:
        continue
    checked += 1
    verdict_ok = False
    if has_current_implementation(meta):
        qa_wp_id = meta.get("qaWorkProductId")
        qa_wp_title = meta.get("qaWorkProductTitle")
        selected_wp, content = full_wp(qa_wp_id)
        verdict_ok = (
            approved_primary(meta)
            and isinstance(qa_wp_title, str)
            and bool(qa_wp_title)
            and valid_test_wp(
                selected_wp,
                content,
                task["id"],
                expected_id=qa_wp_id,
                expected_title=qa_wp_title,
                require_clean_guard=True,
            )
            and binds_current_implementation(selected_wp, content, meta)
        )
    else:
        # Compatibility for pre-index tasks only. Once implementation identity
        # exists, historical or bounded approvals can never satisfy the gate.
        for wp in task_wps(task["id"]):
            selected_wp, content = full_wp(wp.get("id"))
            if valid_test_wp(selected_wp, content, task["id"]):
                verdict_ok = True
                break
    if not verdict_ok:
        blocked.append(f"TASK-{task['id']}: {task.get('title', '').strip()}")

if blocked:
    print("QA gate failed:")
    for item in blocked:
        print(f"- {item}")
    sys.exit(1)

print(f"QA gate passed ({checked} QA-required task(s) checked)")
PY
