#!/usr/bin/env python3
"""blind_score.py — t_loveable blind-scoring pipeline for a live ladder
run (job pack v2, TASK-142). Stdlib only.

WHY THIS EXISTS AS A SEPARATE SCRIPT: run.py's `--judge-mode human` (the
DEC-6 §5 recommended default, see rubric.md §2) writes one worksheet per
cell and stops at `status: pending-human-score` -- `--ingest-scores` (the
human-scoring half) is documented in rubric.md §4 as "not yet built."
The FIRST live run (20260714T135253Z, TASK-125) did this pass ad hoc,
directly in-session, with no reusable tooling -- see that run's own
t_loveable_blind_scoring/README.md. This script makes the same protocol
(blind, exemplar-anchored, shuffled order, mapping opened only after
scoring -- rubric.md §2) a repeatable, auditable step instead of a
one-off manual pass, without building the (still out of scope) automated
model-judge path.

WHAT THIS SCRIPT DOES vs. WHAT A HUMAN (or the agent acting as judge, per
the same disclosed limitation as the first run -- see rubric.md §2 "Judge
mode") STILL HAS TO DO:
    1. `blind_score.py prepare <run_dir> <out_dir>` -- mechanical: reads
       every job-*__config__repN.json in run_dir, pulls each cell's
       already-built (and already scaffold-excluded, see run.py's
       FRAMEWORK_SCAFFOLD_PATHS) t_loveable.worksheet.deliverable_bundle
       and brief, strips config/job/rep identifiers, assigns a random
       12-hex blind id, shuffles the scoring order, and writes:
         - <out_dir>/<blind_id>.json (blind worksheet, no identifiers)
         - <out_dir>/_mapping_DO_NOT_OPEN_UNTIL_AFTER_SCORING.json
         - <out_dir>/_SCORING_ORDER.txt
         - <out_dir>/_scores_template.json (all scores null -- fill this in)
    2. A human (or the executing agent, DISCLOSED as not an independent
       second judge -- same limitation as the first run) reads each blind
       id in _SCORING_ORDER.txt's order and fills in
       _scores_template.json's 4 dimension scores (0-3) + rationale per
       rubric.md's exemplar anchors, WITHOUT opening the mapping file.
    3. `blind_score.py finalize <out_dir> <run_dir>` -- mechanical: joins
       the filled-in scores back to (config, job_id, rep) via the mapping,
       computes t_loveable per rubric.md §3 (all 4 dimensions >= 2), and
       writes <out_dir>/t_loveable_results.json.

Usage:
    python3 blind_score.py prepare <run_dir> <out_dir>
    # ... fill in <out_dir>/_scores_template.json ...
    python3 blind_score.py finalize <out_dir> <run_dir>
"""
from __future__ import annotations

import json
import random
import sys
from pathlib import Path

RUBRIC_DIMENSIONS = ["guided_experience", "sensible_defaults", "error_help", "polish"]


def _load_cells(run_dir: Path) -> list[dict]:
    cells = []
    for path in sorted(run_dir.glob("*__*__rep*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("status") != "ok":
            continue
        worksheet = (data.get("t_loveable") or {}).get("worksheet")
        if not worksheet:
            continue
        cells.append(
            {
                "job_id": data["job_id"],
                "config": data["config"],
                "rep": data["rep"],
                "source_file": path.name,
                "brief": worksheet["brief"],
                "deliverable_bundle": worksheet["deliverable_bundle"],
            }
        )
    return cells


def prepare(run_dir: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    cells = _load_cells(run_dir)
    if not cells:
        print(f"blind_score.py: no scoreable cells found under {run_dir}", file=sys.stderr)
        sys.exit(1)

    rng = random.Random()  # OS-seeded, not reproducible on purpose -- see rubric.md's "never inspect before scoring"
    used_ids: set[str] = set()
    mapping: dict[str, dict] = {}
    template: dict[str, dict] = {}

    for cell in cells:
        blind_id = None
        while blind_id is None or blind_id in used_ids:
            blind_id = "%012x" % rng.getrandbits(48)
        used_ids.add(blind_id)

        blind_worksheet = {
            "job_id": cell["job_id"],  # job identity is NOT blinded (rubric.md §2: "the job's brief" is shown)
            "brief": cell["brief"],
            "rubric_dimensions": RUBRIC_DIMENSIONS,
            "deliverable_bundle": cell["deliverable_bundle"],
        }
        (out_dir / f"{blind_id}.json").write_text(
            json.dumps(blind_worksheet, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        mapping[blind_id] = {
            "config": cell["config"],
            "job_id": cell["job_id"],
            "rep": cell["rep"],
            "source_file": cell["source_file"],
        }
        template[blind_id] = {dim: {"score": None, "rationale": None} for dim in RUBRIC_DIMENSIONS}

    order = list(mapping.keys())
    rng.shuffle(order)

    (out_dir / "_mapping_DO_NOT_OPEN_UNTIL_AFTER_SCORING.json").write_text(
        json.dumps(mapping, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (out_dir / "_SCORING_ORDER.txt").write_text("\n".join(order) + "\n", encoding="utf-8")
    (out_dir / "_scores_template.json").write_text(
        json.dumps(template, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"blind_score.py: prepared {len(cells)} blind worksheet(s) in {out_dir}")
    print(f"blind_score.py: fill in {out_dir / '_scores_template.json'} in the order given by _SCORING_ORDER.txt")


def finalize(out_dir: Path, run_dir: Path) -> None:
    mapping = json.loads((out_dir / "_mapping_DO_NOT_OPEN_UNTIL_AFTER_SCORING.json").read_text(encoding="utf-8"))
    scores_path = out_dir / "_scores_filled.json"
    if not scores_path.is_file():
        scores_path = out_dir / "_scores_template.json"
    scores = json.loads(scores_path.read_text(encoding="utf-8"))

    unscored = [bid for bid, dims in scores.items() if any(d["score"] is None for d in dims.values())]
    if unscored:
        print(
            f"blind_score.py: FAIL — {len(unscored)}/{len(scores)} blind id(s) still unscored: {unscored[:5]}{'...' if len(unscored) > 5 else ''}",
            file=sys.stderr,
        )
        sys.exit(1)

    results = []
    for blind_id, dims in scores.items():
        m = mapping[blind_id]
        t_loveable = all(dims[dim]["score"] >= 2 for dim in RUBRIC_DIMENSIONS)
        results.append(
            {
                "config": m["config"],
                "job_id": m["job_id"],
                "rep": m["rep"],
                "blind_id": blind_id,
                "scores": {dim: dims[dim]["score"] for dim in RUBRIC_DIMENSIONS},
                "rationales": {dim: dims[dim]["rationale"] for dim in RUBRIC_DIMENSIONS},
                "t_loveable": t_loveable,
            }
        )
    results.sort(key=lambda r: (r["job_id"], r["config"], r["rep"]))

    out_path = out_dir / "t_loveable_results.json"
    out_path.write_text(json.dumps(results, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"blind_score.py: wrote {out_path} ({len(results)} scored cell(s))")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1
    cmd = argv[0]
    if cmd == "prepare" and len(argv) == 3:
        prepare(Path(argv[1]).expanduser().resolve(), Path(argv[2]).expanduser().resolve())
        return 0
    if cmd == "finalize" and len(argv) == 3:
        finalize(Path(argv[1]).expanduser().resolve(), Path(argv[2]).expanduser().resolve())
        return 0
    print(__doc__, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
