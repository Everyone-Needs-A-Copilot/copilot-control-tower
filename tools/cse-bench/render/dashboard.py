"""render/dashboard.py — builds the self-contained cse-bench dashboard.html
(TASK-91 / B-8, PRD-9 P1).

WHAT THIS DOES: reads every tools/cse-bench/output/<collector>-latest.json
this machine has produced, plus the claims register
(docs/40-initiatives/01-cse-auditability/claims.yaml), and renders ONE
static HTML file with everything embedded inline — no CDN, no fetch, no
build step. Opens correctly from file://. Small vanilla JS is used for
exactly one thing (the light/dark theme toggle); collapsible raw-JSON
blocks use native <details>/<summary>, not JS.

WHY RENDER-IN-PYTHON: Control Tower invariant #1 (the CLI computes, the
view renders) applies here too — this module does no metric computation
of its own. Every number it prints was already computed by a collector or
already lives in claims.yaml; this file's only job is formatting.

SCHEMA TOLERANCE: collectors/transcripts.py, velocity.py, parity.py, and
integrations.py (B-5/B-6) landed concurrently while this module was being
written and are owned elsewhere — this module never imports or duplicates
their logic, only reads their JSON output. Every renderer below is
therefore written against the real, observed `metrics` shape of a live
`collect` run (see each render_*()'s docstring for the output/*-latest.json
file it was verified against), with `first()`/dig() fallback candidates
kept for resilience if that shape changes later. If a shape doesn't match
anything recognized, dispatch() degrades to a quiet "unrecognized shape"
card with the raw JSON available in a <details> — it never lets one
collector's surprise shape blank the page. A collector whose *-latest.json
file does not exist yet renders the plain "not run" placeholder the task
calls for. The Efficacy panel's bench_knowledge_qa/bench_voice_lint/
bench_mcp_twin renderers (B-9/B-10/B-11) are owned by parallel agents and
had not landed a real output file as of this writing — those three are
GUESSED-SHAPE renderers (several candidate metric-key spellings tried per
value) precisely because the schema-tolerance contract above has to hold
even before the producer exists, not just after it changes. evals
(collectors/evals.py, B-12 groundwork) and the tasksdb-trend efficacy card
are owned by this module and ARE verified against a real collect run.

Organized atoms-up (Brad Frost-ish, even though the output is server-
rendered HTML, not a component tree):
  - atoms: esc/fmt_*/tile/chip/bar_row
  - molecules: monthly_trend_chart, raw_json_details, placeholder/error cards
  - organisms: render_tasksdb/transcripts/velocity/integrations/parity,
    render_adoption_section/efficacy_section/trust_section
  - page: PAGE_CSS/PAGE_JS/build_page/render_dashboard (the public entry point)
"""
from __future__ import annotations

import html
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

RENDER_DIR = Path(__file__).resolve().parent
CSE_BENCH_DIR = RENDER_DIR.parent
REPO_ROOT = CSE_BENCH_DIR.parent.parent

DEFAULT_CLAIMS_PATH = (
    REPO_ROOT / "docs" / "40-initiatives" / "01-cse-auditability" / "claims.yaml"
)

KNOWN_COLLECTORS = [
    "tasksdb",
    "transcripts",
    "velocity",
    "integrations",
    "parity",
    "evals",
    "bench_knowledge_qa",
    "bench_voice_lint",
    "bench_mcp_twin",
]

# check_claims.py already implements "prefer PyYAML, fall back to a vendored
# strict-subset parser" (B-2). Reusing it here means this module has exactly
# one YAML-loading code path in the repo, not two — see check_claims.py's
# own module docstring for what the fallback parser supports.
try:
    import check_claims  # type: ignore  # tools/cse-bench/check_claims.py, sibling of this package
except Exception:  # pragma: no cover - defensive; see load_claims()
    check_claims = None  # type: ignore

_MISSING = object()

STATUS_CHIP = {
    "passing": ("good", "PASSING"),
    "failing": ("crit", "FAILING"),
    "unchecked": ("neutral", "UNCHECKED"),
    "gated": ("warn", "GATED"),
}


# ---------------------------------------------------------------------------
# Atoms
# ---------------------------------------------------------------------------


def esc(value: Any) -> str:
    return html.escape("" if value is None else str(value), quote=True)


def fmt_int(n: Any) -> str:
    try:
        return f"{int(n):,}"
    except (TypeError, ValueError):
        return esc(n)


def fmt_pct(frac: Any, decimals: int = 1) -> str:
    """Format a 0..1 fraction as a percentage."""
    if frac is None:
        return "—"
    try:
        return f"{float(frac) * 100:.{decimals}f}%"
    except (TypeError, ValueError):
        return "—"


def fmt_pct100(pct: Any, decimals: int = 1) -> str:
    """Format a value already expressed on a 0..100 scale (as transcripts.py's
    *_pct fields are) as a percentage. Do not multiply by 100 again."""
    if pct is None:
        return "—"
    try:
        return f"{float(pct):.{decimals}f}%"
    except (TypeError, ValueError):
        return "—"


def _as_float(value: Any) -> float | None:
    """Coerce a value pulled from an unverified/best-effort metrics shape
    (see the bench_* renderers below) to a float for arithmetic-comparison
    or numeric-format use; None on anything non-numeric. Never raises —
    the caller is always free to treat the result as "field not usable"."""
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def fmt_signed(value: Any, decimals: int = 2, suffix: str = "") -> str:
    """Format a value already known to be signed-meaningful (a delta or an
    advantage figure) with an explicit +/- sign. "—" on anything
    non-numeric, same convention as fmt_pct/fmt_int."""
    num = _as_float(value)
    if num is None:
        return "—"
    return f"{num:+.{decimals}f}{suffix}"


def dig(d: Any, *path: str, default: Any = _MISSING) -> Any:
    cur = d
    for key in path:
        if isinstance(cur, dict) and key in cur:
            cur = cur[key]
        else:
            return default
    return cur


def first(d: Any, *dotted_paths: str, default: Any = None) -> Any:
    """Try each dotted-path candidate in order; return the first present,
    non-None value. Used by the best-effort (non-tasksdb) renderers, whose
    exact field names aren't observable yet (see module docstring)."""
    for dotted in dotted_paths:
        val = dig(d, *dotted.split("."))
        if val is not _MISSING and val is not None:
            return val
    return default


def tile(value: str, label: str, cls: str = "") -> str:
    klass = f"tile {cls}".strip()
    return f'<div class="{klass}"><div class="v num">{value}</div><div class="k">{esc(label)}</div></div>'


def chip(status: str) -> str:
    cls, label = STATUS_CHIP.get(status, ("neutral", esc(status).upper() or "UNKNOWN"))
    return f'<span class="chip {cls}">{label}</span>'


def bar_row(label: str, value: float, max_value: float, display: str | None = None, color_var: str = "--good") -> str:
    display = display if display is not None else fmt_int(value)
    width = 2 if max_value <= 0 else max(2.0, round((value / max_value) * 100, 2))
    return (
        f'<div class="brow"><span class="lab">{esc(label)}</span>'
        f'<div class="track"><div class="fill" style="width:{width}%; background:var({color_var})"></div>'
        f'<span class="bval num">{esc(display)}</span></div></div>'
    )


# ---------------------------------------------------------------------------
# Molecules
# ---------------------------------------------------------------------------


def monthly_trend_chart(created: dict, completed: dict) -> str:
    months = sorted(set(created) | set(completed))
    if not months:
        return '<p class="tnote">No monthly trend data.</p>'
    max_val = max([created.get(m, 0) for m in months] + [completed.get(m, 0) for m in months] + [1])
    rows = []
    for m in months:
        c = created.get(m, 0)
        d = completed.get(m, 0)
        c_w = max(2.0, round(c / max_val * 100, 2)) if max_val else 2.0
        d_w = max(2.0, round(d / max_val * 100, 2)) if max_val else 2.0
        rows.append(
            f'<div class="trend-row"><span class="tlab">{esc(m)}</span>'
            f'<div class="trend-track">'
            f'<div class="trend-bar-wrap"><div class="trend-fill" style="width:{c_w}%; background:var(--accent)"></div>'
            f'<span class="trend-val num">{c}</span></div>'
            f'<div class="trend-bar-wrap"><div class="trend-fill" style="width:{d_w}%; background:var(--good)"></div>'
            f'<span class="trend-val num">{d}</span></div>'
            f"</div></div>"
        )
    legend = (
        '<div class="legend"><span><span class="sw" style="background:var(--accent)"></span>Created</span>'
        '<span><span class="sw" style="background:var(--good)"></span>Completed</span></div>'
    )
    return f'<div class="trend">{"".join(rows)}</div>{legend}'


def raw_json_details(envelope: Any, label: str = "Raw JSON") -> str:
    raw = esc(json.dumps(envelope, indent=2, sort_keys=True))
    return f'<details class="rawjson"><summary>{esc(label)}</summary><pre><code>{raw}</code></pre></details>'


def placeholder_card(name: str, title: str, blurb: str, extra_html: str = "") -> str:
    return (
        f'<div class="card placeholder">'
        f"<h3>{esc(title)}</h3>"
        f'<p class="role">collector: <code>{esc(name)}</code></p>'
        f"<p>{esc(blurb)}</p>"
        f'<p class="tnote">collector not yet run — <code>python3 cse_bench.py collect --only {esc(name)}</code></p>'
        f"{extra_html}"
        f"</div>"
    )


def parse_error_card(name: str, title: str, error: str) -> str:
    return (
        f'<div class="card placeholder crit">'
        f"<h3>{esc(title)}</h3>"
        f'<p class="role">collector: <code>{esc(name)}</code></p>'
        f"<p><code>{esc(name)}-latest.json</code> exists but failed to parse as JSON: <code>{esc(error)}</code>. "
        f"Re-run <code>python3 cse_bench.py collect --only {esc(name)}</code>.</p>"
        f"</div>"
    )


def unexpected_shape_card(name: str, title: str, exc: Exception, envelope: Any) -> str:
    metrics = envelope.get("metrics", {}) if isinstance(envelope, dict) else {}
    keys = ", ".join(sorted(metrics.keys())) if isinstance(metrics, dict) and metrics else "(none)"
    return (
        f'<div class="card placeholder warn">'
        f"<h3>{esc(title)}</h3>"
        f'<p class="role">collector: <code>{esc(name)}</code></p>'
        f"<p>Data is present but this renderer does not yet recognize its shape "
        f"(<code>{esc(exc)}</code>). Top-level metric keys: <code>{esc(keys)}</code>.</p>"
        f"{raw_json_details(envelope)}"
        f"</div>"
    )


def dispatch(envelope: Any, name: str, renderer, title: str, blurb: str, placeholder_extra: str = "") -> str:
    if envelope is None:
        return placeholder_card(name, title, blurb, placeholder_extra)
    if isinstance(envelope, dict) and "__parse_error__" in envelope:
        return parse_error_card(name, title, envelope["__parse_error__"])
    try:
        return renderer(envelope)
    except Exception as exc:  # a surprise shape must never blank the page
        return unexpected_shape_card(name, title, exc, envelope)


# ---------------------------------------------------------------------------
# Organisms — Adoption panel collector cards
# ---------------------------------------------------------------------------


def render_tasksdb(envelope: dict) -> str:
    metrics = envelope.get("metrics", {})
    totals = metrics.get("totals", {})
    generated = envelope.get("generated_at", "?")

    tasks = totals.get("tasks", 0)
    prds = totals.get("prds", 0)
    wps = totals.get("work_products", 0)
    completion = totals.get("completion_rate")
    cancelled = totals.get("cancelled_count", 0)
    reopened = totals.get("reopened_count", 0)
    repos_found = metrics.get("repos_found", 0)
    repos_matched = metrics.get("repos_matched", 0)

    tiles_html = "".join(
        [
            tile(fmt_int(tasks), "tasks tracked"),
            tile(fmt_int(prds), "PRDs"),
            tile(fmt_int(wps), "work products"),
            tile(fmt_pct(completion), "completion rate", "ok" if (completion or 0) >= 0.5 else ""),
            tile(fmt_int(repos_found), f"repos scanned (of {fmt_int(repos_matched)} matched)"),
            tile(fmt_int(cancelled), "cancelled"),
            tile(fmt_int(reopened), "reopened (proxy)"),
        ]
    )

    by_status = totals.get("by_status", {}) or {}
    status_color = {"completed": "--good", "pending": "--neutral", "in_progress": "--warn", "cancelled": "--crit"}
    max_status = max(by_status.values()) if by_status else 1
    status_bars = "".join(
        bar_row(status, count, max_status, color_var=status_color.get(status, "--neutral"))
        for status, count in sorted(by_status.items(), key=lambda kv: -kv[1])
    )

    trend = totals.get("monthly_trend", {}) or {}
    trend_html = monthly_trend_chart(trend.get("created", {}) or {}, trend.get("completed", {}) or {})

    per_repo = metrics.get("per_repo", {}) or {}
    repo_counts = {name: dig(r, "tasks", "total", default=0) for name, r in per_repo.items()}
    repo_counts = {k: v for k, v in repo_counts.items() if v}
    max_repo = max(repo_counts.values()) if repo_counts else 1
    repo_bars = "".join(
        bar_row(name, count, max_repo) for name, count in sorted(repo_counts.items(), key=lambda kv: -kv[1])
    )

    errors = envelope.get("errors", []) or []
    err_note = (
        f'<p class="tnote">{len(errors)} repo(s) skipped due to read errors — see raw JSON.</p>' if errors else ""
    )

    activity = totals.get("activity_range", {}) or {}
    range_note = (
        f'<p class="tnote">Activity range: {esc(activity.get("earliest") or "?")} '
        f'→ {esc(activity.get("latest") or "?")}.</p>'
    )

    return (
        '<div class="card">'
        "<h3>Task Copilot throughput</h3>"
        f'<p class="role">collector: <code>tasksdb</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        '<h4 class="subhead">Tasks by status</h4>'
        f'<div class="bars">{status_bars}</div>'
        '<h4 class="subhead">Monthly trend — created vs. completed</h4>'
        f"{trend_html}"
        '<h4 class="subhead">Tasks by repo</h4>'
        f'<div class="bars">{repo_bars}</div>'
        f"{range_note}{err_note}"
        f"{raw_json_details(envelope, 'Raw JSON (tasksdb-latest.json)')}"
        "</div>"
    )


def render_transcripts(envelope: dict) -> str:
    """Matches collectors/transcripts.py's actual `metrics.global` /
    `metrics.corpus` shape (verified against a real collect run — see
    output/transcripts-latest.json). `first()` candidate paths are kept as
    a fallback in case that shape changes; an unrecognized shape still
    degrades to the quiet unexpected-shape card via dispatch(), never a
    crash.
    """
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")
    g = metrics.get("global", {}) if isinstance(metrics.get("global"), dict) else {}

    tool_share = first(g, "delegation_rate_tool_share.median", default=None)
    event_share = first(g, "delegation_rate_event_share.median", default=None)
    proto_loose = first(g, "protocol_declaration_rate_loose.median", default=None)
    proto_strict = first(g, "protocol_declaration_rate_strict.median", default=None)
    n_sessions = first(g, "n_sessions", default=None)

    knowledge_read = g.get("knowledge_read", {}) if isinstance(g.get("knowledge_read"), dict) else {}
    sessions_touching_pct = knowledge_read.get("sessions_touching_pct")
    never_read_md_pct = dig(knowledge_read, "never_read", "knowledge_md", "never_read_pct", default=None)
    never_read_all_pct = dig(knowledge_read, "never_read", "all_files", "never_read_pct", default=None)

    if tool_share is None and event_share is None and proto_loose is None and not knowledge_read:
        raise ValueError("no recognized transcript-adoption fields found under metrics.global")

    tile_parts = [
        tile(fmt_pct(tool_share), "delegation — tool-share (median)") if tool_share is not None else "",
        tile(fmt_pct(event_share), "delegation — event-share (median)") if event_share is not None else "",
        tile(fmt_pct(proto_loose), "protocol rate — loose (median)") if proto_loose is not None else "",
        tile(fmt_pct(proto_strict), "protocol rate — strict, first-of-turn (median)")
        if proto_strict is not None
        else "",
        tile(fmt_int(n_sessions), "sessions analyzed") if n_sessions is not None else "",
        tile(fmt_pct100(sessions_touching_pct), "sessions touching knowledge")
        if sessions_touching_pct is not None
        else "",
        tile(fmt_pct100(never_read_md_pct), "knowledge-md never read", "hot" if (never_read_md_pct or 0) > 50 else "")
        if never_read_md_pct is not None
        else "",
        tile(fmt_pct100(never_read_all_pct), "all-files never read", "hot" if (never_read_all_pct or 0) > 50 else "")
        if never_read_all_pct is not None
        else "",
    ]
    tiles_html = "".join(t for t in tile_parts if t)

    model_combined = dig(g, "model_mix", "combined", "share", default={}) or {}
    model_html = ""
    if isinstance(model_combined, dict) and model_combined:
        model_html = '<h4 class="subhead">Model mix (main + subagent, all messages)</h4><div class="bars">' + "".join(
            bar_row(m, v, max(model_combined.values()), display=fmt_pct(v))
            for m, v in sorted(model_combined.items(), key=lambda kv: -kv[1])
        ) + "</div>"

    cli_by_class = dig(g, "cli_invocation", "by_class", default={}) or {}
    cli_html = ""
    if isinstance(cli_by_class, dict) and cli_by_class:
        max_cli = max(cli_by_class.values())
        cli_html = '<h4 class="subhead">CLI invocation, by class</h4><div class="bars">' + "".join(
            bar_row(cls, n, max_cli) for cls, n in sorted(cli_by_class.items(), key=lambda kv: -kv[1])
        ) + "</div>"

    return (
        '<div class="card">'
        "<h3>Transcript adoption</h3>"
        f'<p class="role">collector: <code>transcripts</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        f"{model_html}{cli_html}"
        '<p class="tnote">Delegation is always reported tool-share alongside event-share — the two disagree '
        "by an order of magnitude and neither is authoritative alone "
        "(see claim <code>delegation-rate-baseline</code> in the Trust panel).</p>"
        f"{raw_json_details(envelope, 'Raw JSON (transcripts-latest.json)')}"
        "</div>"
    )


def render_velocity(envelope: dict) -> str:
    """Matches collectors/velocity.py's actual `metrics.per_repo` /
    `metrics.totals` shape (verified against a real collect run — see
    output/velocity-latest.json)."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")

    per_repo = metrics.get("per_repo")
    by_repo = None
    if isinstance(per_repo, dict) and per_repo:
        by_repo = {repo: dig(entry, "commits_90d", default=0) for repo, entry in per_repo.items()}
    if not by_repo:
        # Fallback for a flatter shape, should this collector's output change.
        flat = first(metrics, "commits_90d", "by_repo", "velocity_by_repo")
        by_repo = flat if isinstance(flat, dict) and flat else None
    if not by_repo:
        raise ValueError("no recognized per-repo commit-velocity mapping found")

    totals = metrics.get("totals", {}) if isinstance(metrics.get("totals"), dict) else {}
    window_days = metrics.get("window_days")
    dirty_repos = set(totals.get("dirty_repos", []) or [])

    tiles_html = "".join(
        t
        for t in [
            tile(fmt_int(totals.get("commits_90d", sum(by_repo.values()))), f"commits / {fmt_int(window_days or 90)}d"),
            tile(fmt_int(len(by_repo)), "repos scanned"),
            tile(fmt_int(totals.get("dirty_repo_count", len(dirty_repos))), "dirty working trees"),
        ]
        if t
    )

    max_v = max(by_repo.values()) if by_repo else 1
    bars = "".join(
        bar_row(f"{repo}{' *' if repo in dirty_repos else ''}", n, max_v)
        for repo, n in sorted(by_repo.items(), key=lambda kv: -kv[1])
    )
    dirty_note = (
        '<p class="tnote">* dirty working tree (uncommitted changes) at collection time.</p>' if dirty_repos else ""
    )

    return (
        '<div class="card">'
        "<h3>Commit velocity</h3>"
        f'<p class="role">collector: <code>velocity</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        f'<h4 class="subhead">Commits, last {fmt_int(window_days or 90)} days</h4>'
        f'<div class="bars">{bars}</div>{dirty_note}'
        f"{raw_json_details(envelope, 'Raw JSON (velocity-latest.json)')}"
        "</div>"
    )


def _coerce_healthy(v: Any) -> bool | None:
    if isinstance(v, bool):
        return v
    if isinstance(v, str):
        return v.strip().lower() in ("healthy", "true", "ok", "up")
    if isinstance(v, dict):
        return _coerce_healthy(v.get("healthy", v.get("status")))
    return None


def _extract_services(metrics: dict) -> list[dict] | None:
    for key in ("services", "by_service", "checks", "health"):
        val = metrics.get(key)
        if isinstance(val, dict) and val:
            return [{"name": k, "healthy": _coerce_healthy(v)} for k, v in val.items()]
        if isinstance(val, list) and val:
            out = []
            for item in val:
                if isinstance(item, dict):
                    name = item.get("name") or item.get("service") or item.get("id") or "unknown"
                    out.append({"name": name, "healthy": _coerce_healthy(item.get("healthy", item.get("status")))})
            if out:
                return out
    return None


def render_integrations(envelope: dict) -> str:
    """Matches collectors/integrations.py's actual `metrics.services` /
    `metrics.healthy_count` / `metrics.total_services` shape (verified
    against a real collect run — see output/integrations-latest.json).
    Prefers the collector's own healthy_count/total_services fields over
    recomputing from the services list (render, don't compute — CT
    invariant #1) and falls back to a computed count only if those fields
    are absent."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")
    services = _extract_services(metrics)
    if services is None:
        raise ValueError("no recognized per-service health mapping found")

    total = metrics.get("total_services")
    healthy = metrics.get("healthy_count")
    if not isinstance(total, int):
        total = len(services)
    if not isinstance(healthy, int):
        healthy = sum(1 for s in services if s["healthy"] is True)
    gauge = bar_row("Live integrations", healthy, max(total, 1), display=f"{healthy}/{total}", color_var="--good")
    chips = "".join(
        f'<span class="chip {"good" if s["healthy"] is True else ("crit" if s["healthy"] is False else "neutral")}">'
        f'{esc(s["name"])}</span>'
        for s in sorted(services, key=lambda s: s["name"])
    )
    cli_version = metrics.get("cli_version")
    version_note = f'<p class="tnote">{esc(cli_version)}</p>' if cli_version else ""

    return (
        '<div class="card">'
        "<h3>Integration health</h3>"
        f'<p class="role">collector: <code>integrations</code> · generated {esc(generated)}</p>'
        f'<div class="bars">{gauge}</div>'
        f"{version_note}"
        f'<div class="svc-chips">{chips}</div>'
        f"{raw_json_details(envelope, 'Raw JSON (integrations-latest.json)')}"
        "</div>"
    )


def render_parity(envelope: dict) -> str:
    """Matches collectors/parity.py's actual `metrics.upstream_check` /
    `metrics.versions` / `metrics.content_check` shape (verified against a
    real collect run — see output/parity-latest.json)."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")

    status = first(metrics, "upstream_check.status", "status")
    if status is None:
        raise ValueError("no recognized parity fields found under metrics.upstream_check")

    status_cls = {"pass": "ok", "fail": "hot"}.get(status, "")
    baseline = dig(metrics, "versions", "baseline", default={}) or {}
    claude = dig(metrics, "versions", "claude_copilot", default={}) or {}
    mismatches = dig(metrics, "upstream_check", "mismatches", default={}) or {}
    content_available = dig(metrics, "content_check", "available", default=False)

    tiles_html = "".join(
        [
            tile(esc(status).upper(), "upstream_check.status", status_cls),
            tile(esc(baseline.get("frameworkVersion", "?")), "framework (baseline)"),
            tile(esc(claude.get("framework", "?")), "framework (claude-copilot live)"),
            tile(esc(claude.get("agents_version", "?")), "agents version"),
            tile(esc(claude.get("commands_version", "?")), "commands version"),
            tile(
                "BUILT" if content_available else "NOT BUILT",
                "content-hash parity (C-4)",
                "" if content_available else "neutral",
            ),
        ]
    )

    mismatch_html = ""
    if mismatches:
        rows = "".join(
            f"<li><code>{esc(k)}</code>: adopted <code>{esc(v.get('adopted'))}</code> vs upstream "
            f"<code>{esc(v.get('upstream'))}</code></li>"
            for k, v in mismatches.items()
            if isinstance(v, dict)
        )
        mismatch_html = f'<h4 class="subhead">Mismatches</h4><ul>{rows}</ul>'

    return (
        '<div class="card">'
        "<h3>Codex/Claude parity</h3>"
        f'<p class="role">collector: <code>parity</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        f"{mismatch_html}"
        f"{raw_json_details(envelope, 'Raw JSON (parity-latest.json)')}"
        "</div>"
    )


def render_adoption_section(outputs: dict) -> str:
    blocks = [
        dispatch(
            outputs.get("tasksdb"),
            "tasksdb",
            render_tasksdb,
            "Task Copilot throughput",
            "Per-repo task/PRD/work-product counts, completion rate, and monthly trend from every "
            "*/.copilot/tasks.db store on this machine.",
        ),
        dispatch(
            outputs.get("transcripts"),
            "transcripts",
            render_transcripts,
            "Transcript adoption",
            "Delegation rate (tool-share and event-share side by side), protocol-declaration rate, model mix, "
            "and knowledge read-coverage mined from ~/.claude/projects and ~/.codex/sessions.",
        ),
        dispatch(
            outputs.get("velocity"),
            "velocity",
            render_velocity,
            "Commit velocity",
            "Commits per 90 days, per repo — the maintenance-health signal alongside adoption.",
        ),
        dispatch(
            outputs.get("integrations"),
            "integrations",
            render_integrations,
            "Integration health",
            "Live-integration count from copilot health --json, plus a status chip per service.",
        ),
        dispatch(
            outputs.get("parity"),
            "parity",
            render_parity,
            "Codex/Claude parity",
            "Version-tuple parity today; content-hash parity once C-4 lands — between claude-copilot and "
            "its codex-copilot mirror.",
        ),
    ]
    return (
        '<section id="adoption">'
        '<span class="eyebrow">Panel 1 · Adoption</span>'
        "<h2>Is it used?</h2>"
        '<p class="prose">Everything in this panel is measured today, from data already on disk — task '
        "throughput, delegation/protocol adoption, commit velocity, and integration health. No efficacy claims "
        'here; see Panel 2 for what "helps" would even mean.</p>'
        f'<div class="cards">{"".join(blocks)}</div>'
        "</section>"
    )


# ---------------------------------------------------------------------------
# Organisms — Efficacy panel (B-9/B-10/B-11 benches + B-12 evals; each card
# is LIVE the moment its collector has written output/<name>-latest.json,
# and an honest "not yet run" placeholder until then — same dispatch()
# contract the Adoption panel uses, see module docstring's SCHEMA TOLERANCE
# note. bench_knowledge_qa / bench_voice_lint / bench_mcp_twin are owned by
# parallel agents and had not landed as of this module's writing, so their
# renderers are deliberately best-effort: several candidate metric-key
# names are tried via first()/dig(), and an unrecognized shape degrades to
# the raw-JSON unexpected-shape card via dispatch() rather than inventing a
# number. evals (collectors/evals.py) and the tasksdb trend card below are
# both owned by this module and verified against a real collect run.
# ---------------------------------------------------------------------------


def claim_ref_note(claim_id: str, claims_by_id: dict) -> str:
    claim = claims_by_id.get(claim_id)
    if not claim:
        return ""
    return (
        f'<p class="tnote">Tracked by claim <code>{esc(claim_id)}</code> in the Trust panel '
        f'(status: {chip(claim.get("status", "unchecked"))}).</p>'
    )


def render_bench_knowledge_qa(envelope: dict) -> str:
    """Matches collectors/bench_knowledge_qa.py's real, observed
    `metrics.results.headline` / `metrics.bank` shape (verified against a
    real collect run — see output/bench_knowledge_qa-latest.json, B-9).
    `first()` fallback candidates from this renderer's original
    pre-landing guesses are kept after the real paths in case the shape
    changes later; an unrecognized shape still degrades to the
    unexpected-shape card via dispatch(), never a crash or an invented
    number."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")

    acc_with = first(
        metrics,
        "results.headline.accuracy_with",
        "accuracy_with",
        "accuracy_with_knowledge",
        "arms.with_knowledge.accuracy",
        "with_knowledge.accuracy",
    )
    acc_without = first(
        metrics,
        "results.headline.accuracy_without",
        "accuracy_without",
        "accuracy_without_knowledge",
        "arms.without_knowledge.accuracy",
        "without_knowledge.accuracy",
        "arms.empty_tree.accuracy",
        "empty_tree.accuracy",
    )
    delta = first(metrics, "results.headline.delta", "delta", "accuracy_delta", "delta_accuracy")
    unknown_with = first(
        metrics,
        "results.headline.unknown_rate_with",
        "unknown_rate_with",
        "arms.with_knowledge.unknown_rate",
        "with_knowledge.unknown_rate",
    )
    unknown_without = first(
        metrics,
        "results.headline.unknown_rate_without",
        "unknown_rate_without",
        "arms.without_knowledge.unknown_rate",
        "without_knowledge.unknown_rate",
        "arms.empty_tree.unknown_rate",
    )
    bank_size = first(metrics, "bank.size", "bank_size", "question_bank_size", "n_questions", "questions.total")

    if acc_with is None and acc_without is None and bank_size is None:
        raise ValueError("no recognized bench_knowledge_qa fields found under metrics")

    delta_f = _as_float(delta)
    tiles_html = "".join(
        t
        for t in [
            tile(fmt_pct(acc_with), "accuracy — with knowledge", "ok") if acc_with is not None else "",
            tile(fmt_pct(acc_without), "accuracy — without knowledge") if acc_without is not None else "",
            tile(fmt_pct(delta), "delta (with − without)", "ok" if (delta_f or 0) > 0 else "")
            if delta is not None
            else "",
            tile(fmt_pct(unknown_with), "UNKNOWN rate — with knowledge") if unknown_with is not None else "",
            tile(fmt_pct(unknown_without), "UNKNOWN rate — without knowledge") if unknown_without is not None else "",
            tile(fmt_int(bank_size), "question bank size") if bank_size is not None else "",
        ]
        if t
    )

    return (
        '<div class="card">'
        "<h3>B-9 · Private-fact Q&amp;A bench</h3>"
        f'<p class="role">collector: <code>bench_knowledge_qa</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        f"{raw_json_details(envelope, 'Raw JSON (bench_knowledge_qa-latest.json)')}"
        "</div>"
    )


def render_bench_voice_lint(envelope: dict) -> str:
    """Matches collectors/bench_voice_lint.py's real, observed
    `metrics.per_arm_summary.<arm>.mean_total_violations_per_100_words` /
    `metrics.headline.*_delta_total_violations_per_100_words` shape
    (verified against a real collect run — see
    output/bench_voice_lint-latest.json, B-10). Two deltas are reported by
    the collector (knowledge-vs-bare and the sharper knowledge-vs-rules-
    in-prompt "does the repo earn its keep over just pasting the
    rubric?" question); both are shown rather than collapsing to one.
    `first()` fallback candidates from this renderer's pre-landing guess
    are kept after the real paths."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")

    arm_candidates = {
        "bare": [
            "per_arm_summary.arm_bare.mean_total_violations_per_100_words",
            "arms.bare.violations_per_100w",
            "bare.violations_per_100w",
            "violations_per_100w.bare",
        ],
        "rules_in_prompt": [
            "per_arm_summary.arm_rules_in_prompt.mean_total_violations_per_100_words",
            "arms.rules_in_prompt.violations_per_100w",
            "rules_in_prompt.violations_per_100w",
            "violations_per_100w.rules_in_prompt",
        ],
        "knowledge": [
            "per_arm_summary.arm_knowledge.mean_total_violations_per_100_words",
            "arms.knowledge.violations_per_100w",
            "knowledge.violations_per_100w",
            "violations_per_100w.knowledge",
        ],
    }
    arm_values = {name: _as_float(first(metrics, *paths)) for name, paths in arm_candidates.items()}
    delta_knowledge_vs_bare = first(
        metrics, "headline.knowledge_vs_bare_delta_total_violations_per_100_words", "marginal_delta"
    )
    delta_knowledge_vs_rules = first(
        metrics,
        "headline.knowledge_vs_rules_delta_total_violations_per_100_words",
        "marginal_value_delta",
        "delta.marginal",
    )

    if all(v is None for v in arm_values.values()) and delta_knowledge_vs_bare is None and delta_knowledge_vs_rules is None:
        raise ValueError("no recognized bench_voice_lint fields found under metrics")

    present_arms = {k: v for k, v in arm_values.items() if v is not None}
    max_v = max(list(present_arms.values()) + [1.0])
    bars = "".join(
        bar_row(name.replace("_", " "), v, max_v, display=f"{v:.2f}/100w", color_var="--warn")
        for name, v in present_arms.items()
    )
    delta_tiles = "".join(
        t
        for t in [
            tile(
                fmt_signed(delta_knowledge_vs_bare, decimals=2, suffix="/100w"),
                "delta: knowledge vs. bare (negative = fewer violations)",
            )
            if delta_knowledge_vs_bare is not None
            else "",
            tile(
                fmt_signed(delta_knowledge_vs_rules, decimals=2, suffix="/100w"),
                "marginal value: knowledge vs. rules-in-prompt",
            )
            if delta_knowledge_vs_rules is not None
            else "",
        ]
        if t
    )

    return (
        '<div class="card">'
        "<h3>B-10 · Voice-conformance bench</h3>"
        f'<p class="role">collector: <code>bench_voice_lint</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{delta_tiles}</div>'
        '<h4 class="subhead">Mean violations per 100 words, by arm</h4>'
        f'<div class="bars">{bars}</div>'
        f"{raw_json_details(envelope, 'Raw JSON (bench_voice_lint-latest.json)')}"
        "</div>"
    )


def render_bench_mcp_twin(envelope: dict) -> str:
    """Matches collectors/bench_mcp_twin.py's real, observed
    `metrics.twins.<name>.net_advantage_tokens.{conservative_using_probe_everything_grammar_cost,
    optimistic_using_prose_grammar_cost}` / `metrics.f17_caveats` shape
    (verified against a real collect run — see
    output/bench_mcp_twin-latest.json, B-11, F-17). Each twin reports TWO
    net-advantage variants (conservative/optimistic grammar-cost basis) —
    the collector's own `net_advantage_tokens` definition deliberately
    does not pick one ("the task does not license picking one"), so this
    renderer shows both rather than collapsing to a single number. A flat
    per-twin numeric fallback (this renderer's pre-landing guess) is tried
    first if the nested-variant shape isn't present."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")

    raw_twins = first(metrics, "twins", "per_twin", "net_advantage_tokens")
    twin_variants: dict[str, dict[str, float]] = {}
    if isinstance(raw_twins, dict):
        for name, val in raw_twins.items():
            if not isinstance(val, dict):
                flat = _as_float(val)
                if flat is not None:
                    twin_variants[name] = {"advantage": flat}
                continue
            nat = val.get("net_advantage_tokens")
            if isinstance(nat, dict):
                variants = {}
                conservative = _as_float(nat.get("conservative_using_probe_everything_grammar_cost"))
                optimistic = _as_float(nat.get("optimistic_using_prose_grammar_cost"))
                if conservative is not None:
                    variants["conservative"] = conservative
                if optimistic is not None:
                    variants["optimistic"] = optimistic
                if variants:
                    twin_variants[name] = variants
            else:
                flat = _as_float(nat if nat is not None else val.get("advantage_tokens"))
                if flat is not None:
                    twin_variants[name] = {"advantage": flat}

    if not twin_variants:
        raise ValueError("no recognized bench_mcp_twin net-advantage-tokens fields found under metrics")

    all_values = [v for variants in twin_variants.values() for v in variants.values()]
    max_v = max(abs(v) for v in all_values) or 1.0
    bars = "".join(
        bar_row(
            f"{name} ({variant})",
            abs(v),
            max_v,
            display=f"{v:+,.0f} tok",
            color_var="--good" if v >= 0 else "--crit",
        )
        for name, variants in sorted(twin_variants.items())
        for variant, v in variants.items()
    )

    caveats = metrics.get("f17_caveats")
    if isinstance(caveats, list) and caveats:
        caveat_html = "<ul>" + "".join(f"<li>{esc(c)}</li>" for c in caveats) + "</ul>"
    else:
        single_caveat = first(metrics, "f17_caveat", "bounded_caveat", "caveat")
        caveat_html = (
            f'<p class="tnote">{esc(single_caveat)}</p>'
            if single_caveat
            else '<p class="tnote">Honestly bounded per F-17 (the deferral-threshold caveat) — see raw JSON for '
            "the collector's own bounding note if one is present.</p>"
        )

    return (
        '<div class="card">'
        "<h3>B-11 · MCP-twin bench</h3>"
        f'<p class="role">collector: <code>bench_mcp_twin</code> · generated {esc(generated)}</p>'
        '<h4 class="subhead">Net advantage, tokens (CLI vs. live MCP twin) — conservative vs. optimistic '
        "grammar-cost basis</h4>"
        f'<div class="bars">{bars}</div>'
        '<h4 class="subhead">F-17 bounded caveats</h4>'
        f"{caveat_html}"
        f"{raw_json_details(envelope, 'Raw JSON (bench_mcp_twin-latest.json)')}"
        "</div>"
    )


def render_evals(envelope: dict) -> str:
    """Matches collectors/evals.py's `metrics.agents_with_evals` /
    `metrics.agents_total` / `metrics.coverage_ratio` / `metrics.per_agent`
    shape (verified against a real collect run — see output/evals-latest.json).
    Golden-set pass-rate per agent via claude-copilot's `cc eval`
    (LocalPythonRunner — pure Python, no LLM call), the T3 program truth
    condition's only measured signal today."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")

    agents_with_evals = metrics.get("agents_with_evals")
    agents_total = metrics.get("agents_total")
    coverage_ratio = metrics.get("coverage_ratio")
    per_agent = metrics.get("per_agent")

    if not isinstance(per_agent, dict) and agents_total is None:
        raise ValueError("no recognized eval-coverage fields found under metrics")

    per_agent = per_agent if isinstance(per_agent, dict) else {}
    agents_with_evals = agents_with_evals if isinstance(agents_with_evals, list) else list(per_agent.keys())

    coverage_display = f"{fmt_int(len(agents_with_evals))} / {fmt_int(agents_total) if agents_total is not None else '?'}"
    tiles_html = "".join(
        t
        for t in [
            tile(coverage_display, "agents with a golden-set eval", "hot" if (coverage_ratio or 0) < 0.5 else ""),
            tile(fmt_pct(coverage_ratio), "eval coverage ratio") if coverage_ratio is not None else "",
        ]
        if t
    )

    bars = ""
    if per_agent:
        rows = []
        for agent, data in sorted(per_agent.items()):
            if not isinstance(data, dict):
                continue
            pass_rate = _as_float(data.get("pass_rate"))
            cases = data.get("cases")
            passed = data.get("passed")
            display = (
                f"{fmt_pct(pass_rate)} ({fmt_int(passed)}/{fmt_int(cases)})"
                if pass_rate is not None and cases is not None
                else fmt_pct(pass_rate)
            )
            rows.append(
                bar_row(
                    agent,
                    pass_rate or 0,
                    1.0,
                    display=display,
                    color_var="--good" if (pass_rate or 0) >= 0.8 else "--warn",
                )
            )
        bars = '<h4 class="subhead">Pass rate by agent</h4><div class="bars">' + "".join(rows) + "</div>"

    coverage_note = (
        f'<p class="tnote">Coverage: {fmt_int(len(agents_with_evals))} of '
        f'{fmt_int(agents_total) if agents_total is not None else "an unknown number of"} specialist agents have '
        "a golden-set eval today — the T3 program truth condition (\"every specialist agent has a passing "
        "golden-set eval\") is unmet by construction until B-12 expands the golden-set roster.</p>"
    )

    return (
        '<div class="card">'
        "<h3>Golden-set eval coverage</h3>"
        f'<p class="role">collector: <code>evals</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        f"{bars}{coverage_note}"
        f"{raw_json_details(envelope, 'Raw JSON (evals-latest.json)')}"
        "</div>"
    )


def render_tasksdb_trend_efficacy(envelope: dict) -> str:
    """Small efficacy-adjacent card: Task Copilot completion/rework trend,
    sourced from the SAME tasksdb-latest.json the Adoption panel's Task
    Copilot throughput card already reads (collectors/tasksdb.py, B-4) —
    not a new collector, and this card deliberately omits the raw-JSON
    block (already shown once, in full, on the Adoption card) to stay
    small."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")
    totals = metrics.get("totals", {}) if isinstance(metrics.get("totals"), dict) else {}

    completion_rate = totals.get("completion_rate")
    reopened = totals.get("reopened_count")
    cancelled = totals.get("cancelled_count")
    tasks = totals.get("tasks")

    if completion_rate is None and reopened is None and tasks is None:
        raise ValueError("no recognized tasksdb totals found under metrics")

    tiles_html = "".join(
        t
        for t in [
            tile(fmt_pct(completion_rate), "completion rate", "ok" if (completion_rate or 0) >= 0.5 else "")
            if completion_rate is not None
            else "",
            tile(fmt_int(reopened), "reopened (rework proxy)", "hot" if (reopened or 0) > 0 else "")
            if reopened is not None
            else "",
            tile(fmt_int(cancelled), "cancelled") if cancelled is not None else "",
            tile(fmt_int(tasks), "tasks tracked") if tasks is not None else "",
        ]
        if t
    )

    trend = totals.get("monthly_trend", {}) if isinstance(totals.get("monthly_trend"), dict) else {}
    trend_html = monthly_trend_chart(trend.get("created", {}) or {}, trend.get("completed", {}) or {})

    return (
        '<div class="card">'
        "<h3>Task throughput — completion/rework trend</h3>"
        f'<p class="role">collector: <code>tasksdb</code> · generated {esc(generated)} · same source as the '
        "Adoption panel's Task Copilot card</p>"
        f'<div class="tiles">{tiles_html}</div>'
        f"{trend_html}"
        "</div>"
    )


def render_efficacy_section(outputs: dict, claims_by_id: dict) -> str:
    cards = [
        dispatch(
            outputs.get("bench_knowledge_qa"),
            "bench_knowledge_qa",
            render_bench_knowledge_qa,
            "B-9 · Private-fact Q&A bench",
            "Closed-book questions generated from product dossiers, scored with-knowledge vs. against an "
            "empty tree — a contamination-immune ablation.",
            claim_ref_note("t4-knowledge-layer-changes-output", claims_by_id),
        ),
        dispatch(
            outputs.get("bench_voice_lint"),
            "bench_voice_lint",
            render_bench_voice_lint,
            "B-10 · Voice-conformance bench",
            "Deterministic linter compiled from the existing tone-of-voice rubric (banned words, em-dash ban, "
            "AI-cliché list, terminology table, reading-level target) — no LLM judge required.",
            claim_ref_note("t4-knowledge-layer-changes-output", claims_by_id),
        ),
        dispatch(
            outputs.get("bench_mcp_twin"),
            "bench_mcp_twin",
            render_bench_mcp_twin,
            "B-11 · MCP-twin bench",
            "copilot crm / db against their live MCP twins — tokens, latency, success rate, honestly "
            "bounded per the F-17 deferral-threshold caveat.",
            claim_ref_note("t5-integration-layer-pays-its-way", claims_by_id),
        ),
        dispatch(
            outputs.get("evals"),
            "evals",
            render_evals,
            "Golden-set eval coverage",
            "cc eval golden-set pass-rate per agent (LocalPythonRunner, deterministic, no LLM call) — the "
            "instruction layer's only rubric-scored quality metric today.",
            claim_ref_note("t3-instruction-layer-changes-behavior", claims_by_id),
        ),
        dispatch(
            outputs.get("tasksdb"),
            "tasksdb",
            render_tasksdb_trend_efficacy,
            "Task throughput — completion/rework trend",
            "Completion rate and the reopened-count rework proxy, efficacy-adjacent context alongside the "
            "benches above — same source as the Adoption panel's Task Copilot card, no new collector.",
        ),
    ]
    return (
        '<section id="efficacy">'
        '<span class="eyebrow">Panel 2 · Efficacy</span>'
        "<h2>Does it help?</h2>"
        '<p class="prose">Adoption tells you the CSE is alive; only these benches (plus eval coverage) can tell '
        "you it helps. PRD-9 P2 scopes each as a deterministic, contamination-resistant delta a skeptic can "
        're-run. Each card below is LIVE the moment its collector has run at least once; until then it is an '
        'honest "not yet run" placeholder, never an invented number.</p>'
        f'<div class="cards">{"".join(cards)}</div>'
        "</section>"
    )


# ---------------------------------------------------------------------------
# Organisms — Trust panel (claims register, rendered live)
# ---------------------------------------------------------------------------


def load_claims(path: Path) -> tuple[dict | None, str | None]:
    if not path.exists():
        return None, f"{path} not found — the claims register has not been created yet."
    text = path.read_text(encoding="utf-8")
    if check_claims is None:
        return None, (
            "PyYAML is not importable and tools/cse-bench/check_claims.py could not be loaded — "
            "cannot parse claims.yaml."
        )
    try:
        data = check_claims.load_yaml(text)
    except Exception as exc:  # noqa: BLE001 - surface any parser failure, PyYAML or fallback
        return None, f"failed to parse {path}: {exc}"
    if not isinstance(data, dict):
        return None, f"{path} parsed but did not produce a mapping (got {type(data).__name__})"
    return data, None


def claim_row(c: dict) -> str:
    return (
        "<tr>"
        f'<td class="id">{esc(c.get("id", "?"))}</td>'
        f'<td>{esc(c.get("statement", ""))}</td>'
        f"<td>{chip(c.get('status', 'unchecked'))}</td>"
        f'<td><code>{esc(c.get("check", "manual"))}</code></td>'
        f'<td class="num">{esc(c.get("last_checked") or "—")}</td>'
        "</tr>"
    )


def render_trust_section(claims_data: dict | None, claims_error: str | None) -> str:
    if claims_error:
        return (
            '<section id="trust">'
            '<span class="eyebrow">Panel 3 · Trust</span>'
            "<h2>The claims register</h2>"
            f'<div class="callout crit">{esc(claims_error)}</div>'
            "</section>"
        )

    assert claims_data is not None
    definitions = claims_data.get("definitions", {}) or {}
    claims = claims_data.get("claims", []) or []
    counts = Counter(c.get("status", "unchecked") for c in claims if isinstance(c, dict))

    stat_tiles = "".join(
        [
            tile(fmt_int(len(claims)), "registered claims"),
            tile(fmt_int(len(definitions)), "operational definitions"),
            tile(fmt_int(counts.get("passing", 0)), "passing", "ok"),
            tile(fmt_int(counts.get("failing", 0)), "failing", "hot"),
            tile(fmt_int(counts.get("unchecked", 0)), "unchecked"),
            tile(fmt_int(counts.get("gated", 0)), "gated"),
        ]
    )
    rows = "".join(claim_row(c) for c in claims if isinstance(c, dict))

    return (
        '<section id="trust">'
        '<span class="eyebrow">Panel 3 · Trust</span>'
        "<h2>The claims register — live</h2>"
        '<p class="prose">Every metric this program quotes is pre-registered here before it is measured (V-2). '
        "This table renders <code>docs/40-initiatives/01-cse-auditability/claims.yaml</code> directly — the "
        "permanent antidote to F-18 (artifact without mechanism).</p>"
        '<div class="callout warn"><strong>All adoption metrics are single-author data (T8 open).</strong> '
        "No number on this page has been reproduced by anyone other than this machine's own owner running these "
        "collectors against their own history.</div>"
        f'<div class="tiles">{stat_tiles}</div>'
        '<div class="scroll"><table>'
        "<thead><tr><th>ID</th><th>Statement</th><th>Status</th><th>Check</th><th>Last checked</th></tr></thead>"
        f"<tbody>{rows}</tbody>"
        "</table></div>"
        "</section>"
    )


# ---------------------------------------------------------------------------
# Page template
# ---------------------------------------------------------------------------

# NOTE: PAGE_CSS's :root / dark-scheme / [data-theme] token blocks and the
# .tile/.chip/.scroll-table/.cards/.bars-brow-track-fill-bval/.stack-seg-
# legend/.callout/.eyebrow/.masthead/.foot component classes are copied
# verbatim from docs/40-initiatives/01-cse-auditability/phases/
# phase-1-reaudit-report.html so this dashboard matches that report's design
# system exactly (same CVD-validated palette, same type system). Only the
# dashboard-specific additions at the bottom (subhead, trend chart, service
# chips, placeholder cards, raw-json details, jump nav, theme toggle) are new.
PAGE_CSS = """
  :root {
    --paper:#F7F8F5; --raised:#FFFFFF; --ink:#1C2733; --muted:#54626F; --faint:#8B96A3;
    --line:#DFE4E1; --accent:#058A62; --accent-ink:#04684A;
    --good:#058A62; --warn:#B45309; --crit:#B91C4B; --neutral:#64748B;
    --good-bg:rgba(5,138,98,.10); --warn-bg:rgba(180,83,9,.10); --crit-bg:rgba(185,28,75,.09);
    --neutral-bg:rgba(100,116,139,.11); --code-bg:#ECEFED;
    --shadow:0 1px 3px rgba(28,39,51,.07);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --paper:#12181F; --raised:#1A222B; --ink:#E4EAF0; --muted:#9AA6B2; --faint:#6E7A87;
      --line:#2A3440; --accent:#2CB68C; --accent-ink:#4BC9A2;
      --good:#109673; --warn:#C07E1D; --crit:#CC4B68; --neutral:#7E8CA0;
      --good-bg:rgba(16,150,115,.16); --warn-bg:rgba(192,126,29,.16); --crit-bg:rgba(204,75,104,.15);
      --neutral-bg:rgba(126,140,160,.15); --code-bg:#212B36;
      --shadow:0 1px 3px rgba(0,0,0,.3);
    }
  }
  :root[data-theme="light"] {
    --paper:#F7F8F5; --raised:#FFFFFF; --ink:#1C2733; --muted:#54626F; --faint:#8B96A3;
    --line:#DFE4E1; --accent:#058A62; --accent-ink:#04684A;
    --good:#058A62; --warn:#B45309; --crit:#B91C4B; --neutral:#64748B;
    --good-bg:rgba(5,138,98,.10); --warn-bg:rgba(180,83,9,.10); --crit-bg:rgba(185,28,75,.09);
    --neutral-bg:rgba(100,116,139,.11); --code-bg:#ECEFED;
    --shadow:0 1px 3px rgba(28,39,51,.07);
  }
  :root[data-theme="dark"] {
    --paper:#12181F; --raised:#1A222B; --ink:#E4EAF0; --muted:#9AA6B2; --faint:#6E7A87;
    --line:#2A3440; --accent:#2CB68C; --accent-ink:#4BC9A2;
    --good:#109673; --warn:#C07E1D; --crit:#CC4B68; --neutral:#7E8CA0;
    --good-bg:rgba(16,150,115,.16); --warn-bg:rgba(192,126,29,.16); --crit-bg:rgba(204,75,104,.15);
    --neutral-bg:rgba(126,140,160,.15); --code-bg:#212B36;
    --shadow:0 1px 3px rgba(0,0,0,.3);
  }

  * { box-sizing:border-box; }
  body {
    background:var(--paper); color:var(--ink);
    font:16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    margin:0; padding:0;
  }
  .wrap { max-width:1060px; margin:0 auto; padding:0 24px 96px; }
  .prose { max-width:74ch; }

  h1,h2 { font-family:"Iowan Old Style", Palatino, "Palatino Linotype", Georgia, serif; text-wrap:balance; }
  h1 { font-size:clamp(2rem,4.5vw,2.75rem); line-height:1.15; margin:.4em 0 .3em; font-weight:600; }
  h2 { font-size:1.45rem; margin:0 0 .6em; font-weight:600; }
  h3 { font-size:1.02rem; margin:0 0 2px; font-weight:650; }
  p { margin:.75em 0; }
  a { color:var(--accent-ink); }
  section { margin-top:64px; }
  strong { font-weight:650; }

  .eyebrow {
    font:600 .72rem/1 ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace;
    letter-spacing:.14em; text-transform:uppercase; color:var(--accent-ink);
    display:block; margin-bottom:14px;
  }
  .masthead { padding-top:64px; border-bottom:1px solid var(--line); padding-bottom:36px; }
  .masthead .meta { color:var(--muted); font-size:.92rem; max-width:74ch; }
  .runline { font:500 .8rem/1.7 ui-monospace,"SF Mono",Menlo,monospace; color:var(--faint); margin-top:18px; }

  code, .mono { font-family:ui-monospace,"SF Mono",SFMono-Regular,Menlo,monospace; font-size:.86em; }
  code { background:var(--code-bg); border-radius:4px; padding:.1em .35em; }
  .num { font-variant-numeric:tabular-nums; }

  .tiles { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; margin-top:16px; }
  .tile { background:var(--raised); border:1px solid var(--line); border-radius:8px; padding:14px 16px; box-shadow:var(--shadow); }
  .tile .v { font:650 1.5rem/1.1 ui-monospace,"SF Mono",Menlo,monospace; font-variant-numeric:tabular-nums; letter-spacing:-.02em; }
  .tile .k { font-size:.78rem; color:var(--muted); margin-top:6px; line-height:1.4; }
  .tile.hot .v { color:var(--crit); }
  .tile.ok .v { color:var(--good); }

  .chip {
    display:inline-block; font:650 .68rem/1 ui-monospace,"SF Mono",Menlo,monospace;
    letter-spacing:.06em; padding:.35em .55em; border-radius:4px; white-space:nowrap;
  }
  .chip.good { color:var(--good); background:var(--good-bg); border:1px solid var(--good); }
  .chip.warn { color:var(--warn); background:var(--warn-bg); border:1px solid var(--warn); }
  .chip.crit { color:var(--crit); background:var(--crit-bg); border:1px solid var(--crit); }
  .chip.neutral { color:var(--neutral); background:var(--neutral-bg); border:1px solid var(--neutral); }

  .scroll { overflow-x:auto; border:1px solid var(--line); border-radius:8px; background:var(--raised); box-shadow:var(--shadow); }
  table { border-collapse:collapse; width:100%; font-size:.88rem; }
  th { text-align:left; font:600 .72rem/1.4 ui-monospace,"SF Mono",Menlo,monospace; letter-spacing:.08em;
       text-transform:uppercase; color:var(--muted); padding:12px 14px; border-bottom:1px solid var(--line); white-space:nowrap; }
  td { padding:11px 14px; border-bottom:1px solid var(--line); vertical-align:top; }
  tr:last-child td { border-bottom:none; }
  td.id { font-family:ui-monospace,"SF Mono",Menlo,monospace; font-weight:650; white-space:nowrap; }
  .tnote { font-size:.8rem; color:var(--muted); margin-top:8px; }

  .cards { display:grid; grid-template-columns:1fr 1fr; gap:16px; margin-top:20px; }
  @media (max-width:760px){ .cards { grid-template-columns:1fr; } }
  .card { background:var(--raised); border:1px solid var(--line); border-radius:8px; padding:20px 22px; box-shadow:var(--shadow); }
  .card .role { font-size:.78rem; color:var(--muted); font-family:ui-monospace,"SF Mono",Menlo,monospace; margin-bottom:8px; }

  .bars { margin:10px 0 6px; }
  .brow { display:grid; grid-template-columns:180px 1fr; gap:12px; align-items:center; margin:8px 0; padding-right:64px; }
  @media (max-width:640px){ .brow { grid-template-columns:1fr; gap:2px; } }
  .brow .lab { font-size:.82rem; color:var(--muted); text-align:right; }
  @media (max-width:640px){ .brow .lab { text-align:left; } }
  .track { background:var(--neutral-bg); border-radius:4px; height:22px; position:relative; }
  .fill { height:100%; border-radius:4px 3px 3px 4px; background:var(--good); min-width:2px; transition:opacity .15s; }
  .fill:hover { opacity:.82; }
  .bval { position:absolute; left:calc(100% + 8px); top:50%; transform:translateY(-50%);
          font:650 .8rem/1 ui-monospace,"SF Mono",Menlo,monospace; font-variant-numeric:tabular-nums; white-space:nowrap; }

  .legend { display:flex; flex-wrap:wrap; gap:16px; font-size:.82rem; color:var(--muted); margin-top:8px; }
  .legend .sw { display:inline-block; width:11px; height:11px; border-radius:3px; margin-right:6px; vertical-align:-1px; }

  .callout { border:1px solid var(--line); border-left:4px solid var(--warn); background:var(--raised);
             border-radius:8px; padding:16px 20px; margin:20px 0; font-size:.93rem; box-shadow:var(--shadow); }
  .callout.crit { border-left-color:var(--crit); }
  .callout.good { border-left-color:var(--good); }

  .foot { margin-top:80px; border-top:1px solid var(--line); padding-top:24px; font-size:.82rem; color:var(--muted); }
  .foot code { font-size:.85em; }

  /* --- dashboard-specific additions (not in the reaudit report) --------- */

  h4.subhead {
    font:650 .74rem/1.3 ui-monospace,"SF Mono",Menlo,monospace; letter-spacing:.08em; text-transform:uppercase;
    color:var(--muted); margin:20px 0 6px;
  }

  .trend { margin:8px 0 4px; }
  .trend-row { display:grid; grid-template-columns:76px 1fr; gap:10px; align-items:center; margin:6px 0; padding-right:56px; }
  @media (max-width:640px){ .trend-row { grid-template-columns:1fr; } }
  .trend-row .tlab { font:500 .76rem/1 ui-monospace,"SF Mono",Menlo,monospace; color:var(--muted); text-align:right; }
  @media (max-width:640px){ .trend-row .tlab { text-align:left; } }
  .trend-track { display:flex; flex-direction:column; gap:3px; }
  .trend-bar-wrap { position:relative; height:14px; background:var(--neutral-bg); border-radius:3px; }
  .trend-fill { height:100%; border-radius:3px; min-width:2px; transition:opacity .15s; }
  .trend-fill:hover { opacity:.82; }
  .trend-val { position:absolute; left:calc(100% + 8px); top:50%; transform:translateY(-50%);
               font:650 .72rem/1 ui-monospace,"SF Mono",Menlo,monospace; font-variant-numeric:tabular-nums; white-space:nowrap; }

  .svc-chips { display:flex; flex-wrap:wrap; gap:8px; margin-top:12px; }

  .card.placeholder { border-style:dashed; box-shadow:none; background:transparent; }
  .card.placeholder h3 { color:var(--muted); }
  .card.placeholder p { color:var(--muted); font-size:.9rem; }
  .card.placeholder.warn { border-style:solid; border-color:var(--line); border-left:4px solid var(--warn); }
  .card.placeholder.crit { border-style:solid; border-color:var(--line); border-left:4px solid var(--crit); }

  details.rawjson { margin-top:14px; }
  details.rawjson summary {
    cursor:pointer; font:600 .76rem/1 ui-monospace,"SF Mono",Menlo,monospace; color:var(--muted); user-select:none;
  }
  details.rawjson pre {
    background:var(--code-bg); border-radius:6px; padding:12px 14px; margin-top:8px;
    max-height:340px; overflow:auto; font-size:.76rem; line-height:1.5;
  }

  nav.jumpnav { margin-top:16px; font:500 .82rem/1.6 ui-monospace,"SF Mono",Menlo,monospace; color:var(--muted); }
  nav.jumpnav a { color:var(--accent-ink); text-decoration:none; margin-right:6px; }
  nav.jumpnav a:not(:last-child)::after { content:" \\00b7"; color:var(--faint); margin-left:6px; }
  nav.jumpnav a:hover { text-decoration:underline; }

  #theme-toggle {
    font:600 .72rem/1 ui-monospace,"SF Mono",Menlo,monospace; letter-spacing:.05em; text-transform:uppercase;
    padding:.5em .8em; border-radius:6px; border:1px solid var(--line); background:var(--raised); color:var(--ink);
    cursor:pointer; margin-top:18px;
  }
  #theme-toggle:hover { border-color:var(--accent); }

  a:focus-visible, button:focus-visible, summary:focus-visible {
    outline:2px solid var(--accent); outline-offset:2px; border-radius:3px;
  }

  @media (prefers-reduced-motion: reduce) { .fill, .trend-fill { transition:none; } }
"""

PAGE_JS = """(function () {
  var root = document.documentElement;
  var btn = document.getElementById('theme-toggle');
  var stored = null;
  try { stored = window.localStorage.getItem('cse-bench-theme'); } catch (e) { stored = null; }
  if (stored === 'light' || stored === 'dark') { root.setAttribute('data-theme', stored); }

  function currentTheme() {
    var attr = root.getAttribute('data-theme');
    if (attr === 'light' || attr === 'dark') { return attr; }
    return (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
  }
  function label(theme) { return theme === 'dark' ? 'Light mode' : 'Dark mode'; }
  function apply(theme) {
    root.setAttribute('data-theme', theme);
    try { window.localStorage.setItem('cse-bench-theme', theme); } catch (e) { /* file://, ignore */ }
    if (btn) { btn.textContent = label(theme); }
  }
  if (btn) {
    btn.textContent = label(currentTheme());
    btn.addEventListener('click', function () {
      apply(currentTheme() === 'dark' ? 'light' : 'dark');
    });
  }
})();"""


def discover_outputs(out_dir: Path) -> dict[str, Any]:
    outputs: dict[str, Any] = {}
    for name in KNOWN_COLLECTORS:
        path = out_dir / f"{name}-latest.json"
        if not path.exists():
            outputs[name] = None
            continue
        try:
            outputs[name] = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001 - degrade to a parse-error card, never crash render
            outputs[name] = {"__parse_error__": str(exc)}
    return outputs


def build_page(
    generated_at: str,
    present_count: int,
    total_count: int,
    present_list: str,
    adoption_html: str,
    efficacy_html: str,
    trust_html: str,
) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CSE Benchmark — Live</title>
<style>{PAGE_CSS}</style>
</head>
<body>
<div class="wrap">

<header class="masthead">
  <span class="eyebrow">Copilot Solutioning Ecosystem · CSE Verification &amp; Benchmark Program · PRD-9</span>
  <h1>CSE Benchmark — Live</h1>
  <p class="meta">Adoption / Efficacy / Trust, rendered from whatever collector output and claims-register state
     exist on this machine right now. This page computes nothing — every number here was written by a
     <code>cse_bench.py collect</code> run or already lives in <code>claims.yaml</code> (Control Tower invariant
     #1: the CLI computes, the view renders).</p>
  <div class="runline">GENERATED {generated_at} · {present_count}/{total_count} COLLECTORS PRESENT ({present_list})</div>
  <nav class="jumpnav" aria-label="Dashboard sections">
    <a href="#adoption">Adoption</a>
    <a href="#efficacy">Efficacy</a>
    <a href="#trust">Trust</a>
  </nav>
  <button id="theme-toggle" type="button">Dark mode</button>
</header>

{adoption_html}
{efficacy_html}
{trust_html}

<footer class="foot">
  <p><strong>Source.</strong> <code>tools/cse-bench/output/*-latest.json</code> (gitignored, regenerated by
     <code>python3 cse_bench.py collect</code>) and
     <code>docs/40-initiatives/01-cse-auditability/claims.yaml</code> (git-committed, the pre-registration
     record). Refresh with <code>python3 cse_bench.py collect &amp;&amp; python3 cse_bench.py render</code>.</p>
  <p>Rendered by <code>tools/cse-bench/render/dashboard.py</code> (TASK-91 / B-8) · Copilot Control Tower
     repo.</p>
</footer>

</div>
<script>{PAGE_JS}</script>
</body>
</html>
"""


def render_dashboard(out_dir: Path, claims_path: Path | None = None) -> str:
    """Public entry point. Reads out_dir/<collector>-latest.json for every
    KNOWN_COLLECTORS entry and claims_path (default DEFAULT_CLAIMS_PATH),
    and returns the complete dashboard.html document as a string. Never
    raises for missing/malformed collector output or a missing/malformed
    claims register — those degrade to quiet in-page cards instead
    (see dispatch(), placeholder_card(), render_trust_section()).
    """
    claims_path = claims_path or DEFAULT_CLAIMS_PATH
    outputs = discover_outputs(out_dir)
    claims_data, claims_error = load_claims(claims_path)
    claims_by_id = {
        c.get("id"): c for c in (claims_data.get("claims", []) if claims_data else []) if isinstance(c, dict)
    }

    present = [name for name, val in outputs.items() if val is not None]
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def safe_section(builder, *args) -> str:
        try:
            return builder(*args)
        except Exception as exc:  # noqa: BLE001 - a rendering bug must not blank the whole page
            return f'<section><div class="callout crit">Section failed to render: {esc(exc)}</div></section>'

    adoption_html = safe_section(render_adoption_section, outputs)
    efficacy_html = safe_section(render_efficacy_section, outputs, claims_by_id)
    trust_html = safe_section(render_trust_section, claims_data, claims_error)

    return build_page(
        generated_at=esc(generated_at),
        present_count=len(present),
        total_count=len(KNOWN_COLLECTORS),
        present_list=esc(", ".join(present) if present else "none yet"),
        adoption_html=adoption_html,
        efficacy_html=efficacy_html,
        trust_html=trust_html,
    )
