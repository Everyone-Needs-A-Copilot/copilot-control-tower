#!/usr/bin/env python3
"""Deterministic fake used only to verify the TASK-303 harness itself."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys


ROOT = Path(os.environ["CLEAN_JOURNEY_ROOT"])
HOME = Path(os.environ["HOME"])
PROJECT = Path(os.environ["CLEAN_JOURNEY_PROJECT"])
EVIDENCE = Path(os.environ["CLEAN_JOURNEY_EVIDENCE"])


def write_json(relative: str, value: dict[str, object]) -> None:
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    action = sys.argv[1]
    if action == "inventory":
        write_json("evidence/inventory.json", {"home_empty_at_start": True, "control_tower_app_installed": False})
    elif action == "install":
        (HOME / ".claude" / "copilot").mkdir(parents=True, exist_ok=True)
        (HOME / ".claude" / "copilot" / "VERSION").write_text("fixture-v1\n", encoding="utf-8")
        write_json("evidence/install.json", {"framework": "fixture-v1", "immutable": True})
    elif action == "assemble":
        (PROJECT / ".claude").mkdir(parents=True, exist_ok=True)
        (PROJECT / ".codex").mkdir(parents=True, exist_ok=True)
        (PROJECT / "human-owned.txt").write_text("owner bytes stay fixed\n", encoding="utf-8")
        write_json("evidence/assembly.json", {"claude": True, "codex": True, "layers": ["foundation", "organization", "accounting"]})
    elif action == "problem":
        write_json("evidence/route.json", {"problem": "Explain and repair an unexplained accounting variance", "specialists": ["protocol", "accounting", "qa"]})
    elif action == "apply":
        (PROJECT / "artifact.md").write_text("# Evidence gap package\n\nDecision and evidence created from the synthetic problem.\n", encoding="utf-8")
        write_json("evidence/create.json", {"artifact": "project/artifact.md", "ownership": "project"})
    elif action == "preserve":
        (HOME / ".task-copilot").mkdir(parents=True, exist_ok=True)
        (HOME / ".task-copilot" / "state.json").write_text('{"next":"continue artifact"}\n', encoding="utf-8")
        write_json("evidence/handoff.json", {"next_action": "continue artifact", "artifact": "project/artifact.md"})
    elif action == "continue":
        state = json.loads((HOME / ".task-copilot" / "state.json").read_text(encoding="utf-8"))
        with (PROJECT / "artifact.md").open("a", encoding="utf-8") as handle:
            handle.write(f"\nResumed next action: {state['next']}.\n")
        write_json("evidence/continuation.json", {"fresh_process": True, "recovered_next_action": state["next"]})
    elif action == "update":
        (HOME / ".claude" / "copilot" / "VERSION").write_text("fixture-v2\n", encoding="utf-8")
        write_json("evidence/update.json", {"from": "fixture-v1", "to": "fixture-v2", "human_work_preserved": True})
    elif action == "failure":
        write_json("evidence/held.json", {"result": "held", "reason": "tracked-dirty", "recovery_actor": "project owner"})
        return 42
    elif action == "recovery":
        (HOME / ".claude" / "entitlement.json").write_text('{"state":"reauthorized"}\n', encoding="utf-8")
        write_json("evidence/recovery.json", {"from": "revoked", "to": "reauthorized", "mutable_ref_used": False})
    elif action == "conformance":
        write_json("evidence/conformance.json", {"s0": 0, "unexplained_could_not_run": 0, "result": "pass"})
    elif action == "leak":
        print("github_pat_123456789012345678901234567890")
    else:
        raise SystemExit(f"unknown fixture action: {action}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
