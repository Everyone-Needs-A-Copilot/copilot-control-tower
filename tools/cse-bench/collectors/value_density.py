"""collectors/value_density.py — the removal-rule collector (W-6, TASK-128).

Operationalizes phase-4-outcome-program-prd.md §0.5 / §2's removal rule:
*"surface that does not move an outcome bar within its review window is a
removal candidate... nominations are mechanical; deletions are the
owner's."* This collector traces four surface types — **agent** (the 16
claude-copilot specialist agents), **cli_service_group** (the 22 CLI
Copilot registered services), **knowledge_area** (knowledge-copilot's
top-level directories), and **skill** (the 37 `.claude/skills/**/SKILL.md`
leaf skills) — to a usage-evidence signal and an outcome-bar trace, and
nominates the bottom slice per the `value_density` definition registered
in `docs/40-initiatives/01-cse-auditability/claims.yaml` BEFORE this
collector was written (V-2).

**This module never re-derives raw evidence a second way.** It JOINS
already-computed `output/<name>-latest.json` collector output
(`framework_soul` for agent usage, `evals` for agent outcome-trace,
`cli_soul` for CLI conformance, `knowledge_soul` for knowledge orphan
data) rather than re-scanning the transcript corpus or knowledge repo
itself — re-deriving the same numbers a second way would risk exactly the
definitional drift this program's own register exists to prevent (see
`framework_soul.py`'s `discipline_snapshot`, which follows the same
"cite, don't recompute" pattern). The one exception is grouping
knowledge-copilot's files by top-level directory: `knowledge_soul.py`'s
`orphan_rate` metric reports a flat file list, not a per-directory
breakdown, so this collector does a light, read-only re-listing of the
same file set purely to bucket the ALREADY-COMPUTED orphan verdict per
file — it does not recompute orphan status itself.

NOMINATION RULE (mirrors claims.yaml's `value_density.nomination_rule`
verbatim — restated here so a JSON consumer never has to cross-reference
the register to understand a `nominated: true` flag): a surface is
nominated iff its usage_evidence is a MEASURED zero (not null/
unavailable) AND its outcome_trace is anything other than a measured
`true`. A surface whose usage_evidence is null (no event ledger exists —
true for every `cli_service_group` and `skill` today) is NEVER nominated
on that basis alone: absence of instrumentation is not evidence of
non-use.

Known, deliberate honest gaps (see claims.yaml `value_density` for why):
  - `cli_service_group` usage_evidence is null for all 22 services — the
    opt-in CLI usage ledger has never been enabled on this machine
    (matches DEC-5's own finding). This collector does NOT re-litigate
    DEC-5's four already-open candidates (fireflies, reddit, metabase,
    method) — see `decisions/DEC-5-configure-or-cut-services.md`.
  - `skill` usage_evidence is null for all 37 skills — no skill-
    invocation event ledger exists anywhere in the ecosystem yet (C-3's
    hook rollout is staged to claude-copilot only).
  - `knowledge_area` outcome_trace and `skill` outcome_trace are null for
    every surface — no outcome bar is wired to individual knowledge areas
    or skills yet.
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path
from typing import Optional

from collectors.paths import resolve_copilot_root

COLLECTOR_NAME = "value_density"

CSE_BENCH_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = CSE_BENCH_ROOT / "output"

COPILOT_ROOT = resolve_copilot_root()
CLAUDE_ROOT = COPILOT_ROOT / "claude-copilot"
KNOWLEDGE_ROOT = COPILOT_ROOT / "knowledge-copilot"

AGENTS_DIR = CLAUDE_ROOT / ".claude" / "agents"
SKILLS_DIR = CLAUDE_ROOT / ".claude" / "skills"

KNOWLEDGE_EXCLUDE_DIR_NAMES = {".git", "node_modules", "storybook-static", "_archive"}

# Registered in claims.yaml (value_density.threshold) BEFORE this collector
# computed a single number: a knowledge area needs at least this many
# scope files to be nomination-eligible at all (the orphan-rate proxy is
# too noisy on a handful of files), and crosses the nomination line at a
# literal majority (>=50%) of its files unreferenced anywhere else in the
# knowledge corpus -- a natural, non-arbitrary bright line, not one fitted
# to any specific area's number.
MIN_KNOWLEDGE_AREA_FILES = 10
KNOWLEDGE_AREA_ORPHAN_NOMINATION_PCT = 50.0

REVIEW_WINDOW = (
    "the full archive-UNION-live transcript corpus available on this machine as of "
    "2026-07-13 (collectors/transcripts.py's corpus merge) for agent usage; the full "
    "knowledge-copilot corpus for the knowledge cross-reference check. No periodic "
    "cadence has been ratified yet -- see claims.yaml value_density.review_window."
)

NOMINATION_RULE = (
    "a surface is nominated iff usage_evidence is a MEASURED zero (not null) AND "
    "outcome_trace is anything other than a measured true -- see claims.yaml "
    "value_density.nomination_rule for the full registered definition"
)


def _load_latest(name: str, errors: list[dict]) -> Optional[dict]:
    path = OUTPUT_DIR / f"{name}-latest.json"
    if not path.exists():
        errors.append(
            {
                "item": f"{name}_latest",
                "path": str(path),
                "error": f"not found -- run `cse_bench.py collect --only {name}` first",
            }
        )
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append({"item": f"{name}_latest", "path": str(path), "error": f"{type(exc).__name__}: {exc}"})
        return None


# ---------------------------------------------------------------------------
# Surface 1 — agent (claude-copilot's 16 specialist agents)
# ---------------------------------------------------------------------------


def _discover_agents(errors: list[dict]) -> list[str]:
    if not AGENTS_DIR.is_dir():
        errors.append({"item": "agents_dir", "path": str(AGENTS_DIR), "error": "directory not found"})
        return []
    return sorted(p.stem for p in AGENTS_DIR.glob("*.md"))


def _surface_agents(errors: list[dict]) -> dict:
    agents = _discover_agents(errors)
    framework_soul = _load_latest("framework_soul", errors)
    evals = _load_latest("evals", errors)

    usage_by_agent: dict[str, int] = {}
    framework_soul_available = False
    if framework_soul:
        by_agent_type = framework_soul.get("metrics", {}).get("agent_frugality", {}).get("by_agent_type", {})
        if by_agent_type:
            framework_soul_available = True
            usage_by_agent = {k: v.get("n", 0) for k, v in by_agent_type.items()}

    eval_by_agent: dict[str, dict] = {}
    if evals:
        eval_by_agent = evals.get("metrics", {}).get("per_agent", {})

    per_agent: dict[str, dict] = {}
    nominations: list[dict] = []
    for agent in agents:
        if framework_soul_available:
            usage_count = usage_by_agent.get(agent, 0)
            usage_evidence = {
                "measured": True,
                "value": usage_count,
                "channel": "subagent invocation count, attributionAgent field, full review-window transcript corpus",
            }
        else:
            usage_evidence = {
                "measured": False,
                "value": None,
                "channel": "framework_soul-latest.json unavailable this run",
            }

        eval_entry = eval_by_agent.get(agent)
        if eval_entry is None or eval_entry.get("overall_pass") is None:
            outcome_trace = {"measured": False, "value": None, "detail": "no golden-set eval exists for this agent"}
        else:
            passed = bool(eval_entry.get("overall_pass"))
            outcome_trace = {
                "measured": True,
                "value": passed,
                "detail": f"golden-set eval: {eval_entry.get('passed')}/{eval_entry.get('cases')} cases, overall_pass={passed}",
            }

        nominate = usage_evidence["measured"] and usage_evidence["value"] == 0 and outcome_trace["value"] is not True
        per_agent[agent] = {
            "usage_evidence": usage_evidence,
            "outcome_trace": outcome_trace,
            "nominated": nominate,
        }
        if nominate:
            nominations.append(
                {
                    "surface": agent,
                    "surface_type": "agent",
                    "evidence": (
                        "0 subagent invocations across the full review-window transcript corpus; "
                        f"{outcome_trace['detail']}"
                    ),
                }
            )

    return {
        "per_agent": per_agent,
        "nominations": nominations,
        "n_agents_total": len(agents),
        "n_nominated": len(nominations),
        "usage_evidence_available": framework_soul_available,
    }


# ---------------------------------------------------------------------------
# Surface 2 — cli_service_group (CLI Copilot's 22 registered services)
# ---------------------------------------------------------------------------


def _surface_cli_services(errors: list[dict]) -> dict:
    cli_soul = _load_latest("cli_soul", errors)
    if not cli_soul or not cli_soul.get("metrics", {}).get("available"):
        errors.append(
            {
                "item": "cli_service_surface",
                "error": "cli_soul-latest.json unavailable or its own collector reported available=false -- "
                "the CLI service surface cannot be measured this review",
            }
        )
        return {
            "per_service": {},
            "nominations": [],
            "n_services_total": None,
            "n_nominated": 0,
            "usage_evidence_available": False,
        }

    m = cli_soul["metrics"]
    services = m.get("services", [])
    gaps_by_service: dict[str, list[dict]] = defaultdict(list)
    for g in m.get("gaps", []):
        gaps_by_service[g["service"]].append(g)

    per_service: dict[str, dict] = {}
    for svc in services:
        svc_gaps = gaps_by_service.get(svc, [])
        conformance_clean = len(svc_gaps) == 0
        per_service[svc] = {
            "usage_evidence": {
                "measured": False,
                "value": None,
                "detail": (
                    "CLI Copilot's opt-in usage ledger (COPILOT_USAGE_LOG) has never been enabled on this "
                    "machine; no per-service invocation counts exist for ANY of the 22 registered services "
                    "(matches DEC-5's own finding). This is an instrumentation gap, not a computed zero."
                ),
            },
            "outcome_trace": {
                "measured": True,
                "value": conformance_clean,
                "detail": (
                    "fully clean" if conformance_clean
                    else f"{len(svc_gaps)} SOUL-conformance gap(s): {', '.join(g['criterion'] for g in svc_gaps)}"
                ),
            },
            # usage_evidence.measured is False for every service -- never mechanically
            # nominated on usage grounds alone, per the registered nomination_rule.
            "nominated": False,
        }

    return {
        "per_service": per_service,
        "nominations": [],
        "n_services_total": len(services),
        "n_nominated": 0,
        "usage_evidence_available": False,
        "note": (
            "No CLI service group is mechanically nominated this review: usage_evidence is null "
            "(unmeasured) for all 22, and the nomination_rule never nominates on a null usage signal "
            "alone. The 4 services with an actual STRUCTURAL-ABSENCE finding (fireflies, reddit, "
            "metabase, method -- no credentials and/or no code, not a usage measurement) are already "
            "covered by DEC-5 (decisions/DEC-5-configure-or-cut-services.md); this collector defers to "
            "that memo rather than re-deriving the same finding."
        ),
    }


# ---------------------------------------------------------------------------
# Surface 3 — knowledge_area (knowledge-copilot's top-level directories)
# ---------------------------------------------------------------------------


def _iter_knowledge_areas(errors: list[dict]) -> dict[str, list[Path]]:
    if not KNOWLEDGE_ROOT.is_dir():
        errors.append({"item": "knowledge_root", "path": str(KNOWLEDGE_ROOT), "error": "not a directory / not found"})
        return {}
    areas: dict[str, list[Path]] = defaultdict(list)
    for p in KNOWLEDGE_ROOT.rglob("*.md"):
        if any(part in KNOWLEDGE_EXCLUDE_DIR_NAMES for part in p.parts):
            continue
        rel = p.relative_to(KNOWLEDGE_ROOT)
        area = rel.parts[0] if len(rel.parts) > 1 else "(root)"
        areas[area].append(rel)
    return areas


def _surface_knowledge_areas(errors: list[dict]) -> dict:
    knowledge_soul = _load_latest("knowledge_soul", errors)
    areas = _iter_knowledge_areas(errors)
    if not areas:
        return {"per_area": {}, "nominations": [], "n_areas_total": 0, "n_nominated": 0, "usage_evidence_available": False}

    orphan_files: set[str] = set()
    orphan_data_available = False
    if knowledge_soul:
        orphan_block = knowledge_soul.get("metrics", {}).get("orphan_rate", {})
        if "orphan_files" in orphan_block:
            orphan_files = set(orphan_block["orphan_files"])
            orphan_data_available = True
    if not orphan_data_available:
        errors.append(
            {
                "item": "knowledge_area_surface",
                "error": "knowledge_soul-latest.json's orphan_rate.orphan_files unavailable -- knowledge "
                "area usage evidence cannot be measured this review",
            }
        )

    per_area: dict[str, dict] = {}
    nominations: list[dict] = []
    for area, files in sorted(areas.items()):
        total = len(files)
        if not orphan_data_available:
            per_area[area] = {
                "usage_evidence": {"measured": False, "value": None, "n_files": total},
                "outcome_trace": {"measured": False, "value": None, "detail": "no outcome bar is wired to any individual knowledge area yet"},
                "nominated": False,
            }
            continue

        n_orphan = sum(1 for f in files if str(f) in orphan_files)
        orphan_pct = round(n_orphan / total * 100, 1) if total else None
        eligible = total >= MIN_KNOWLEDGE_AREA_FILES
        nominate = bool(eligible and orphan_pct is not None and orphan_pct >= KNOWLEDGE_AREA_ORPHAN_NOMINATION_PCT)

        detail = (
            f"{orphan_pct}% of this area's {total} files are referenced nowhere else in the knowledge corpus "
            "or manifest (knowledge_soul.py's orphan_rate, re-grouped by top-level directory) -- a FLOOR "
            "proxy for 'nobody uses this content', not a session-read count"
        )
        if not eligible:
            detail += f"; fewer than {MIN_KNOWLEDGE_AREA_FILES} files, excluded from nomination eligibility as too small a sample"

        per_area[area] = {
            "usage_evidence": {
                "measured": True,
                "value": orphan_pct,
                "n_files": total,
                "n_orphan_files": n_orphan,
                "eligible_for_nomination": eligible,
                "detail": detail,
            },
            "outcome_trace": {"measured": False, "value": None, "detail": "no outcome bar is wired to any individual knowledge area yet"},
            "nominated": nominate,
        }
        if nominate:
            nominations.append({"surface": area, "surface_type": "knowledge_area", "evidence": detail})

    return {
        "per_area": per_area,
        "nominations": nominations,
        "n_areas_total": len(areas),
        "n_nominated": len(nominations),
        "usage_evidence_available": orphan_data_available,
    }


# ---------------------------------------------------------------------------
# Surface 4 — skill (.claude/skills/**/SKILL.md leaf skills)
# ---------------------------------------------------------------------------


def _discover_skills(errors: list[dict]) -> list[str]:
    if not SKILLS_DIR.is_dir():
        errors.append({"item": "skills_dir", "path": str(SKILLS_DIR), "error": "directory not found"})
        return []
    return sorted(str(p.relative_to(SKILLS_DIR).parent) for p in SKILLS_DIR.rglob("SKILL.md"))


def _surface_skills(errors: list[dict]) -> dict:
    skills = _discover_skills(errors)
    per_skill: dict[str, dict] = {}
    for skill in skills:
        per_skill[skill] = {
            "usage_evidence": {
                "measured": False,
                "value": None,
                "detail": (
                    "no skill-invocation event ledger exists anywhere in the ecosystem yet (the same C-3 "
                    "hook rollout that would carry this signal is staged to claude-copilot only, per "
                    "phase-4-handoff.md TASK-103)"
                ),
            },
            "outcome_trace": {"measured": False, "value": None, "detail": "no eval or outcome bar is wired to any individual skill yet"},
            "nominated": False,
        }

    return {
        "per_skill": per_skill,
        "nominations": [],
        "n_skills_total": len(skills),
        "n_nominated": 0,
        "usage_evidence_available": False,
        "note": (
            "No skill is mechanically nominated this review: usage_evidence is null (no event ledger "
            "exists) for every skill, and the nomination_rule never nominates on a null signal alone."
        ),
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def collect() -> dict:
    """Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    errors: list[dict] = []

    agent_surface = _surface_agents(errors)
    cli_surface = _surface_cli_services(errors)
    knowledge_surface = _surface_knowledge_areas(errors)
    skill_surface = _surface_skills(errors)

    all_nominations = (
        agent_surface["nominations"]
        + cli_surface["nominations"]
        + knowledge_surface["nominations"]
        + skill_surface["nominations"]
    )

    metrics = {
        "review": {
            "review_window": REVIEW_WINDOW,
            "nomination_rule": NOMINATION_RULE,
            "definition_ref": "docs/40-initiatives/01-cse-auditability/claims.yaml -- definitions.value_density (the full pre-registered definition; this collector's own docstring/constants restate it, never redefine it)",
        },
        "surfaces": {
            "agent": agent_surface,
            "cli_service_group": cli_surface,
            "knowledge_area": knowledge_surface,
            "skill": skill_surface,
        },
        "nominations": {
            "total": len(all_nominations),
            "by_surface_type": {
                "agent": len(agent_surface["nominations"]),
                "cli_service_group": len(cli_surface["nominations"]),
                "knowledge_area": len(knowledge_surface["nominations"]),
                "skill": len(skill_surface["nominations"]),
            },
            "list": all_nominations,
        },
    }
    return {"metrics": metrics, "errors": errors}
