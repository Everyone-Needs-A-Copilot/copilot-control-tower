"""
corpus_scan.py — walk ~/.claude/projects, compute per-session metrics, and
write a flat CSV (one row per main session) plus a JSON sidecar with
project-level framework/hooks classification.

Usage:
    python3 corpus_scan.py [--projects-dir ~/.claude/projects] [--out DIR]

This never loads the corpus into memory at once: it globs file paths (paths
are cheap), then streams each file independently via jsonl_utils.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

from framework_registry import classify_projects
from session_metrics import compute_session_metrics

FIELDNAMES = [
    "session_id", "project_slug", "cwd", "start_ts", "end_ts", "version",
    "turns", "n_main_assistant_msgs", "n_main_tool_calls",
    "n_agent_delegations", "n_subagent_files", "n_subagent_assistant_msgs",
    "n_subagent_tool_calls", "total_tool_calls",
    "delegation_rate_toolshare", "delegation_rate_eventshare",
    "n_protocol_declared_all", "protocol_declaration_rate_all",
    "n_first_of_turn_msgs", "protocol_declaration_rate_first_of_turn",
    "main_tokens_input", "main_tokens_cache_creation", "main_tokens_cache_read",
    "main_tokens_output", "main_cache_read_share",
    "sub_tokens_input", "sub_tokens_cache_creation", "sub_tokens_cache_read",
    "sub_tokens_output",
    "main_model_share_opus", "main_model_share_sonnet", "main_model_share_haiku", "main_model_share_other",
    "combined_model_share_opus", "combined_model_share_sonnet", "combined_model_share_haiku", "combined_model_share_other",
    "delegated_agent_types",
    "agents_present", "mechanical_hooks_registered", "hook_matcher_covers_read_edit",
]


def find_main_session_files(projects_dir: Path) -> list[Path]:
    """Main session files are `<project>/<sessionId>.jsonl` — i.e. .jsonl
    files directly under a project directory, NOT under a `subagents/` or
    `tool-results/` subdirectory."""
    out = []
    for f in projects_dir.glob("*/*.jsonl"):
        out.append(f)
    return sorted(out)


def row_from_metrics(sm, fw_status) -> dict:
    main_share = sm.model_share("main")
    combined_share = sm.model_share("combined")

    def g(d, k):
        return d.get(k)

    return {
        "session_id": sm.session_id,
        "project_slug": sm.project_slug,
        "cwd": sm.cwd,
        "start_ts": sm.start_ts,
        "end_ts": sm.end_ts,
        "version": sm.version,
        "turns": sm.turns,
        "n_main_assistant_msgs": sm.n_main_assistant_msgs,
        "n_main_tool_calls": sm.n_main_tool_calls,
        "n_agent_delegations": sm.n_agent_delegations,
        "n_subagent_files": sm.n_subagent_files,
        "n_subagent_assistant_msgs": sm.n_subagent_assistant_msgs,
        "n_subagent_tool_calls": sm.n_subagent_tool_calls,
        "total_tool_calls": sm.total_tool_calls,
        "delegation_rate_toolshare": sm.delegation_rate_toolshare,
        "delegation_rate_eventshare": sm.delegation_rate_eventshare,
        "n_protocol_declared_all": sm.n_protocol_declared_all,
        "protocol_declaration_rate_all": sm.protocol_declaration_rate_all,
        "n_first_of_turn_msgs": sm.n_first_of_turn_msgs,
        "protocol_declaration_rate_first_of_turn": sm.protocol_declaration_rate_first_of_turn,
        "main_tokens_input": sm.main_tokens.input_tokens,
        "main_tokens_cache_creation": sm.main_tokens.cache_creation_input_tokens,
        "main_tokens_cache_read": sm.main_tokens.cache_read_input_tokens,
        "main_tokens_output": sm.main_tokens.output_tokens,
        "main_cache_read_share": sm.main_tokens.cache_read_share,
        "sub_tokens_input": sm.subagent_tokens.input_tokens,
        "sub_tokens_cache_creation": sm.subagent_tokens.cache_creation_input_tokens,
        "sub_tokens_cache_read": sm.subagent_tokens.cache_read_input_tokens,
        "sub_tokens_output": sm.subagent_tokens.output_tokens,
        "main_model_share_opus": g(main_share, "opus"),
        "main_model_share_sonnet": g(main_share, "sonnet"),
        "main_model_share_haiku": g(main_share, "haiku"),
        "main_model_share_other": g(main_share, "other"),
        "combined_model_share_opus": g(combined_share, "opus"),
        "combined_model_share_sonnet": g(combined_share, "sonnet"),
        "combined_model_share_haiku": g(combined_share, "haiku"),
        "combined_model_share_other": g(combined_share, "other"),
        "delegated_agent_types": json.dumps(dict(sm.delegated_agent_types)),
        "agents_present": fw_status.agents_present if fw_status else None,
        "mechanical_hooks_registered": fw_status.mechanical_hooks_registered if fw_status else None,
        "hook_matcher_covers_read_edit": fw_status.hook_matcher_covers_read_edit if fw_status else None,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--projects-dir", default=str(Path.home() / ".claude" / "projects"))
    ap.add_argument("--out", default=".")
    args = ap.parse_args()

    projects_dir = Path(args.projects_dir)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    main_files = find_main_session_files(projects_dir)
    print(f"Found {len(main_files)} main session files under {projects_dir}", file=sys.stderr)

    rows = []
    cwds: set[str] = set()
    for i, f in enumerate(main_files, 1):
        try:
            sm = compute_session_metrics(f)
        except Exception as e:  # noqa: BLE001 — one bad file must not kill the scan
            print(f"[warn] failed on {f}: {e}", file=sys.stderr)
            continue
        if sm.cwd:
            cwds.add(sm.cwd)
        rows.append(sm)
        if i % 25 == 0:
            print(f"  ...{i}/{len(main_files)}", file=sys.stderr)

    print(f"Classifying {len(cwds)} distinct project cwds for framework/hook status", file=sys.stderr)
    fw_map = classify_projects(cwds)

    out_csv = out_dir / "session_metrics.csv"
    with out_csv.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=FIELDNAMES)
        writer.writeheader()
        for sm in rows:
            fw_status = fw_map.get(sm.cwd) if sm.cwd else None
            writer.writerow(row_from_metrics(sm, fw_status))

    out_fw = out_dir / "framework_registry.json"
    with out_fw.open("w") as fh:
        json.dump(
            {cwd: vars(status) for cwd, status in fw_map.items()},
            fh, indent=2, default=str,
        )

    print(f"Wrote {len(rows)} session rows to {out_csv}", file=sys.stderr)
    print(f"Wrote framework registry ({len(fw_map)} projects) to {out_fw}", file=sys.stderr)


if __name__ == "__main__":
    main()
