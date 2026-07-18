"""render/dashboard.py — builds the self-contained cse-bench dashboard.html
(TASK-91/B-8 original build; reorganized by component/SOUL in TASK-111/S-5).

WHAT THIS DOES: reads every tools/cse-bench/output/<collector>-latest.json
this machine has produced, plus the claims register
(docs/40-initiatives/01-cse-auditability/claims.yaml), and renders ONE
static HTML file with everything embedded inline — no CDN, no fetch, no
build step. Opens correctly from file://. Small vanilla JS is used for
exactly one thing (the light/dark theme toggle); collapsible raw-JSON
blocks use native <details>/<summary>, not JS.

WHY RENDER-IN-PYTHON: Control Tower invariant #1 (the CLI computes, the
view renders) applies here too — this module does no metric computation
of its own beyond simple display-only arithmetic on numbers a collector
already produced (e.g. the ecosystem scoreboard's "tasks/week" divides
tasksdb's own monthly totals by the span of its own activity_range — the
same class of derived-display arithmetic bar_row()'s width% and
render_evals()'s coverage_display already did before this reorg). It
invents no business logic, resolution, sync, or merge decisions.

TASK-111 / S-5 (owner-directed reorg, phase-2-prd.md §2.5): the dashboard
is now organized around the owner's mental model of exactly THREE
components, each measured against its own ratified SOUL promise, plus an
ecosystem-level scoreboard (header) and a trust ledger (footer):
  - Development framework (claude-copilot & codex-copilot SOUL) — Task
    Copilot, Memory Copilot, specialized agents. Measures process
    discipline and context efficiency; explicitly never speed/quality.
  - Knowledge framework (knowledge-copilot SOUL) — accurate understanding
    for good decisions; never a stale dump, marketing narrative, or a
    home for quietly contradictory facts.
  - Integration framework (cli-copilot SOUL) — one binary, one grammar;
    client, never server; honest, hint-bearing failure.
There is no "instruction layer" section and no "voice content" component —
those were retired terms; voice-lint output now lives INSIDE the
Development/Knowledge sections as one measure among several, never a
component of its own. Parity and commit velocity move OUT of the
measurement story per the same revision: velocity is dropped entirely,
parity survives only as a small "sync plumbing" chip in the Development
section's footer.

SCHEMA TOLERANCE: four collectors this reorg depends on — bench_resume_cost
(S-1), framework_soul (S-2), knowledge_soul (S-3), and cli_soul (S-4) — were
being built by parallel agents as this module was written and had not
landed a real output file as of this writing. Their renderers below are
therefore GUESSED-SHAPE renderers (several candidate metric-key spellings
tried per value via first()/dig()), the exact same pattern the original
B-8 build used for bench_knowledge_qa/bench_voice_lint/bench_mcp_twin
before THEY landed. tasksdb, transcripts, evals, integrations, parity,
bench_knowledge_qa, bench_voice_lint, and bench_mcp_twin are all verified
against a real collect run on this machine (see each function's docstring
for which output/*-latest.json it was checked against). If a shape doesn't
match anything recognized, dispatch() degrades to a quiet "unrecognized
shape" card with the raw JSON available in a <details> — it never lets one
collector's surprise shape blank the page. A collector whose *-latest.json
file does not exist yet renders the plain "not run" placeholder.

Organized atoms-up (Brad Frost-ish, even though the output is server-
rendered HTML, not a component tree):
  - atoms: esc/fmt_*/dig/first/tile/chip/bar_row
  - molecules: monthly_trend_chart, raw_json_details, placeholder/error
    cards, soul_intro (the SOUL-promise blockquote every component section
    opens with)
  - organisms: per-collector render_* functions, render_scoreboard_section/
    render_framework_section/render_knowledge_section/
    render_integration_section/render_trust_section
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

# The collector set this dashboard reads. velocity is deliberately absent —
# TASK-111/S-5 moved commit velocity OUT of the measurement story entirely
# (parity survives only as a footer sync-plumbing chip; velocity does not
# survive at all). collectors/velocity.py still runs fine under
# `cse_bench.py collect`; this dashboard simply no longer displays it.
KNOWN_COLLECTORS = [
    "tasksdb",
    "transcripts",
    "evals",
    "bench_resume_cost",
    "framework_soul",
    "bench_knowledge_qa",
    "knowledge_soul",
    "bench_voice_lint",
    "integrations",
    "parity",
    "cli_soul",
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
    (see the guessed-shape renderers below) to a float for arithmetic-
    comparison or numeric-format use; None on anything non-numeric. Never
    raises — the caller is always free to treat the result as "field not
    usable"."""
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


def fmt_flexible_pct(value: Any, decimals: int = 1) -> str:
    """Format a ratio that might be expressed either 0..1 or already-0..100 —
    used only by the guessed-shape S-2/S-3/S-4/S-1 renderers below, where the
    real collector's scale convention is not yet observable on this machine
    (see module docstring's SCHEMA TOLERANCE note). "—" on anything
    non-numeric, same convention as fmt_pct/fmt_int."""
    num = _as_float(value)
    if num is None:
        return "—"
    if -1.0 <= num <= 1.0:
        return fmt_pct(num, decimals)
    return fmt_pct100(num, decimals)


def _weeks_between(earliest: Any, latest: Any) -> float | None:
    """Span, in weeks, between two ISO timestamps — display-only arithmetic
    for the ecosystem scoreboard's "tasks finished / week" tile (divides
    tasksdb's own activity_range span by its own monthly totals; invents no
    new data). None on anything unparsable, never raises."""
    if not earliest or not latest:
        return None
    try:
        d0 = datetime.fromisoformat(str(earliest).replace("Z", "+00:00"))
        d1 = datetime.fromisoformat(str(latest).replace("Z", "+00:00"))
        days = (d1 - d0).total_seconds() / 86400.0
        return max(days / 7.0, 1.0 / 7.0)
    except (TypeError, ValueError):
        return None


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
    non-None value. Used by the guessed-shape renderers, whose exact field
    names aren't observable yet (see module docstring)."""
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


def soul_intro(eyebrow: str, title: str, quote: str, soul_note: str, lede: str) -> str:
    """The block every component section opens with: its SOUL promise
    quoted in one sentence, the SOUL file path in small text underneath
    (soul_note), then a one-paragraph lede. Shared by all three component
    sections so the "measured against its own SOUL promise" framing is
    structurally identical for each (TASK-111/S-5)."""
    return (
        f'<span class="eyebrow">{eyebrow}</span>'
        f"<h2>{esc(title)}</h2>"
        f'<blockquote class="soulquote">“{esc(quote)}”</blockquote>'
        f'<p class="soulpath">{soul_note}</p>'
        f'<p class="prose">{lede}</p>'
    )


def claim_ref_note(claim_id: str, claims_by_id: dict) -> str:
    claim = claims_by_id.get(claim_id)
    if not claim:
        return ""
    return (
        f'<p class="tnote">Tracked by claim <code>{esc(claim_id)}</code> in the Trust ledger '
        f'(status: {chip(claim.get("status", "unchecked"))}).</p>'
    )


# ---------------------------------------------------------------------------
# Organisms — Development framework (claude-copilot & codex-copilot SOUL)
# ---------------------------------------------------------------------------


def render_tasksdb(envelope: dict) -> str:
    """Matches collectors/tasksdb.py's real, observed `metrics.totals` /
    `metrics.per_repo` shape (verified against a real collect run — see
    output/tasksdb-latest.json, B-4)."""
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


def render_framework_discipline(envelope: dict) -> str:
    """Discipline half of collectors/transcripts.py's `metrics.global` shape
    (verified against a real collect run — see output/transcripts-latest.json,
    B-5) — the Development framework's mechanical-enforcement measures (SOUL
    Principle 2: "Mechanical Enforcement Over Polite Advice"): delegation
    rate under BOTH registered definitions side by side (F-5's tool-share/
    event-share pair, neither authoritative alone) and protocol-declaration
    rate under both denominators. TASK-111/S-5 split this out of what used
    to be one combined "transcript adoption" card — knowledge-read fields
    moved to render_knowledge_read_coverage (Knowledge framework section)
    and model-mix/CLI-invocation-mix were dropped from this reorg's scope
    entirely, per the task's explicit card list."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")
    g = metrics.get("global", {}) if isinstance(metrics.get("global"), dict) else {}

    tool_share = first(g, "delegation_rate_tool_share.median")
    event_share = first(g, "delegation_rate_event_share.median")
    proto_loose = first(g, "protocol_declaration_rate_loose.median")
    proto_strict = first(g, "protocol_declaration_rate_strict.median")
    n_sessions = g.get("n_sessions")

    if tool_share is None and event_share is None and proto_loose is None:
        raise ValueError("no recognized delegation/protocol fields found under metrics.global")

    tiles_html = "".join(
        t
        for t in [
            tile(fmt_pct(tool_share), "delegation — tool-share (median)") if tool_share is not None else "",
            tile(fmt_pct(event_share), "delegation — event-share (median)") if event_share is not None else "",
            tile(fmt_pct(proto_loose), "protocol rate — loose (median)") if proto_loose is not None else "",
            tile(fmt_pct(proto_strict), "protocol rate — strict, first-of-turn (median)")
            if proto_strict is not None
            else "",
            tile(fmt_int(n_sessions), "sessions analyzed") if n_sessions is not None else "",
        ]
        if t
    )

    return (
        '<div class="card">'
        "<h3>Discipline — delegation &amp; protocol adherence</h3>"
        f'<p class="role">collector: <code>transcripts</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        '<p class="tnote">Delegation is always reported tool-share alongside event-share — the two disagree '
        "by an order of magnitude and neither is authoritative alone "
        "(see claim <code>delegation-rate-baseline</code> in the Trust ledger).</p>"
        f"{raw_json_details(envelope, 'Raw JSON (transcripts-latest.json)')}"
        "</div>"
    )


def render_evals(envelope: dict) -> str:
    """Matches collectors/evals.py's `metrics.agents_with_evals` /
    `metrics.agents_total` / `metrics.coverage_ratio` / `metrics.per_agent`
    shape (verified against a real collect run — see output/evals-latest.json).
    Golden-set pass-rate per agent via claude-copilot's `cc eval`
    (LocalPythonRunner — pure Python, no LLM call), the Development
    framework's only rubric-scored quality metric today."""
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
        "a golden-set eval today.</p>"
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


def render_bench_resume_cost(envelope: dict) -> str:
    """Matches benches/resume_cost's real, observed `metrics.results.headline`
    / `metrics.run_params` shape (verified against a real collect run —
    landed mid-work, S-1/TASK-107 — see output/bench_resume_cost-latest.json).
    A single fixture project, headless-claude probed with vs. without an
    injected state block, `run_params.reps` repetitions per arm — measures
    the Development framework's SOUL Job statement directly: tokens and
    correctness resuming real work with vs. without Memory/Task state.
    `first()` fallback candidates from this renderer's original pre-landing
    guess are kept after the real paths in case the shape changes later;
    an unrecognized shape still degrades to the unexpected-shape card via
    dispatch(), never a crash or an invented number."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")
    headline = dig(metrics, "results", "headline", default={}) or {}

    tokens_with = first(headline, "mean_total_tokens_with", "tokens_with")
    tokens_without = first(headline, "mean_total_tokens_without", "tokens_without")
    token_delta = first(headline, "token_delta_with_minus_without", "token_delta")
    correctness_with = first(headline, "correctness_with")
    correctness_without = first(headline, "correctness_without")
    correctness_delta = first(headline, "correctness_delta")
    reps = first(metrics, "run_params.reps", "n_tasks", "bank.size")

    if tokens_with is None and tokens_without is None and correctness_with is None and reps is None:
        raise ValueError("no recognized bench_resume_cost fields found under metrics")

    delta_f = _as_float(token_delta)
    tiles_html = "".join(
        t
        for t in [
            tile(fmt_int(tokens_with), "mean tokens to resume — WITH Memory/Task state", "ok")
            if tokens_with is not None
            else "",
            tile(fmt_int(tokens_without), "mean tokens to resume — WITHOUT state")
            if tokens_without is not None
            else "",
            tile(
                fmt_signed(token_delta, decimals=0, suffix=" tok"),
                "token delta, with − without (SOUL's 'rebuilding context' cost)",
                "hot" if (delta_f or 0) > 0 else "ok",
            )
            if token_delta is not None
            else "",
            tile(fmt_flexible_pct(correctness_with), "correctness — WITH state", "ok")
            if correctness_with is not None
            else "",
            tile(fmt_flexible_pct(correctness_without), "correctness — WITHOUT state")
            if correctness_without is not None
            else "",
            tile(fmt_signed(correctness_delta, decimals=2), "correctness delta, with − without")
            if correctness_delta is not None
            else "",
            tile(fmt_int(reps), "reps per arm") if reps is not None else "",
        ]
        if t
    )

    return (
        '<div class="card">'
        "<h3>S-1 · Resume-cost bench</h3>"
        f'<p class="role">collector: <code>bench_resume_cost</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        "<p class=\"tnote\">Measures the SOUL's own Job statement directly: resuming disciplined work "
        "without burning the token budget rebuilding context. A positive token delta means the injected "
        "state cost more tokens than the bare-resume arm's own tool-call exploration/hedging — read "
        "alongside the correctness delta, not alone.</p>"
        f"{raw_json_details(envelope, 'Raw JSON (bench_resume_cost-latest.json)')}"
        "</div>"
    )


def render_framework_soul(envelope: dict) -> str:
    """Matches collectors/framework_soul.py's real, observed
    `metrics.externalization_ratio` / `metrics.agent_frugality` /
    `metrics.qa_gate_adherence` / `metrics.main_session_token_trend.weekly`
    shape (verified against a real collect run — landed mid-work,
    S-2/TASK-108 — see output/framework_soul-latest.json). Checks the
    SOUL's own "~94% less context for externalized work products" claim
    per its own Gate 3 honesty test (measure it or strike it — the
    collector's own `verdict`/`verdict_band` fields ARE that measure-or-
    strike judgment, rendered verbatim, not recomputed here), agent
    return-size frugality against the SOUL's ~100-token target, the
    ARTIFACT-marker QA-gate adherence rate the SubagentStop hook itself
    enforces, and a weekly main-session token trend blended from two
    differently-shaped sources (recent weeks from live transcripts,
    older weeks backfilled from stats-cache.json where transcript
    retention has already rolled off — the collector's own `source` field
    per week is preserved in the raw JSON). `first()` fallback candidates
    from this renderer's original pre-landing guesses are kept after the
    real paths in case the shape changes later."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")

    ext = metrics.get("externalization_ratio", {}) if isinstance(metrics.get("externalization_ratio"), dict) else {}
    savings_median = first(ext, "savings_ratio_median", "externalization.ratio")
    savings_mean = first(ext, "savings_ratio_mean")
    ext_verdict = first(ext, "verdict", "externalization_verdict")
    ext_claim = first(ext, "claim")

    frugality = metrics.get("agent_frugality", {}) if isinstance(metrics.get("agent_frugality"), dict) else {}
    frugality_median = first(frugality, "median", "agent_frugality.mean_return_tokens")
    frugality_pct_over = first(frugality, "pct_over_threshold")
    frugality_threshold = first(frugality, "threshold_tokens", default=100)

    qa_gate = metrics.get("qa_gate_adherence", {}) if isinstance(metrics.get("qa_gate_adherence"), dict) else {}
    qa_gate_rate = first(qa_gate, "artifact_marker_rate", "qa_gate_adherence_pct")
    qa_gate_n = first(qa_gate, "n_qa_returns")

    weekly = dig(metrics, "main_session_token_trend", "weekly", default=None)

    if savings_median is None and frugality_median is None and qa_gate_rate is None and not isinstance(weekly, dict):
        raise ValueError("no recognized framework_soul fields found under metrics")

    frugality_f = _as_float(frugality_median)
    tiles_html = "".join(
        t
        for t in [
            tile(
                fmt_pct(savings_median),
                "externalization savings ratio, median (checks the SOUL's own “~94%” claim)",
                "hot" if (_as_float(savings_median) or 0) <= 0 else "ok",
            )
            if savings_median is not None
            else "",
            tile(fmt_pct(savings_mean), "externalization savings ratio, mean") if savings_mean is not None else "",
            tile(
                fmt_int(frugality_median),
                "agent return size, median tokens (SOUL target ~100)",
                "hot" if frugality_f and frugality_f > frugality_threshold else "",
            )
            if frugality_median is not None
            else "",
            tile(fmt_pct100(frugality_pct_over), f"agent returns over the {fmt_int(frugality_threshold)}-token threshold")
            if frugality_pct_over is not None
            else "",
            tile(fmt_pct(qa_gate_rate), "QA-gate / ARTIFACT-marker adherence", "ok" if (_as_float(qa_gate_rate) or 0) >= 0.8 else "hot")
            if qa_gate_rate is not None
            else "",
            tile(fmt_int(qa_gate_n), "QA returns sampled") if qa_gate_n is not None else "",
        ]
        if t
    )

    verdict_html = ""
    if ext_verdict:
        claim_line = f' Claim checked: <em>{esc(ext_claim)}</em>.' if ext_claim else ""
        verdict_html = (
            f'<p class="tnote">S-2\'s verdict on the SOUL\'s own claim: <strong>{esc(ext_verdict)}</strong>.'
            f"{claim_line}</p>"
        )

    trend_html = ""
    if isinstance(weekly, dict) and weekly:
        vals: dict[str, float] = {}
        for week, wv in weekly.items():
            if not isinstance(wv, dict):
                continue
            total = first(wv, "input_plus_output_total", "total_tokens_all_models")
            total_f = _as_float(total)
            if total_f is not None:
                vals[week] = total_f
        if vals:
            max_v = max(vals.values()) or 1.0
            rows = "".join(bar_row(k, v, max_v, display=fmt_int(v)) for k, v in sorted(vals.items()))
            trend_html = (
                '<h4 class="subhead">Main-session token trend, by ISO week</h4>'
                f'<div class="bars">{rows}</div>'
                '<p class="tnote">Recent weeks are input+output tokens from live transcripts; older weeks '
                "(beyond transcript retention) are backfilled from stats-cache.json's coarser "
                "all-model daily totals — see the raw JSON's per-week <code>source</code> field.</p>"
            )

    return (
        '<div class="card">'
        "<h3>S-2 · Framework-SOUL collector</h3>"
        f'<p class="role">collector: <code>framework_soul</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        f"{verdict_html}{trend_html}"
        f"{raw_json_details(envelope, 'Raw JSON (framework_soul-latest.json)')}"
        "</div>"
    )


def parity_footer_chip(envelope: Any) -> str:
    """Small footer chip, not a card — Codex/Claude parity is demoted to
    "sync plumbing" per TASK-111/S-5 (same framework, two harnesses; the
    Claude↔Codex comparison itself is dropped as a measurement). Never
    raises. Matches collectors/parity.py's real `metrics.upstream_check`
    shape (verified — see output/parity-latest.json, B-6)."""
    if envelope is None:
        return '<span class="chip neutral">NOT RUN</span>'
    if isinstance(envelope, dict) and "__parse_error__" in envelope:
        return '<span class="chip warn">PARSE ERROR</span>'
    try:
        metrics = envelope.get("metrics", {})
        status = first(metrics, "upstream_check.status", "status")
        if status == "pass":
            return '<span class="chip good">PASS</span>'
        if status == "fail":
            return '<span class="chip crit">DRIFT</span>'
        return '<span class="chip neutral">UNKNOWN</span>'
    except Exception:  # noqa: BLE001 - a footer chip must never break the page
        return '<span class="chip warn">UNREADABLE</span>'


# ---------------------------------------------------------------------------
# Organisms — Knowledge framework (knowledge-copilot SOUL)
# ---------------------------------------------------------------------------


def render_knowledge_read_coverage(envelope: dict) -> str:
    """Knowledge-read half of collectors/transcripts.py's `metrics.global`
    shape (verified against a real collect run — see
    output/transcripts-latest.json, B-5) — moved here from what used to be
    one combined "transcript adoption" card (TASK-111/S-5); the delegation/
    protocol half now lives in render_framework_discipline (Development
    framework section)."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")
    g = metrics.get("global", {}) if isinstance(metrics.get("global"), dict) else {}
    knowledge_read = g.get("knowledge_read", {}) if isinstance(g.get("knowledge_read"), dict) else {}

    sessions_touching_pct = knowledge_read.get("sessions_touching_pct")
    never_read_md_pct = dig(knowledge_read, "never_read", "knowledge_md", "never_read_pct", default=None)
    never_read_all_pct = dig(knowledge_read, "never_read", "all_files", "never_read_pct", default=None)

    if sessions_touching_pct is None and never_read_md_pct is None and never_read_all_pct is None:
        raise ValueError("no recognized knowledge_read fields found under metrics.global.knowledge_read")

    tiles_html = "".join(
        t
        for t in [
            tile(fmt_pct100(sessions_touching_pct), "sessions touching knowledge")
            if sessions_touching_pct is not None
            else "",
            tile(
                fmt_pct100(never_read_md_pct),
                "knowledge-md never read",
                "hot" if (never_read_md_pct or 0) > 50 else "",
            )
            if never_read_md_pct is not None
            else "",
            tile(
                fmt_pct100(never_read_all_pct),
                "all-files never read",
                "hot" if (never_read_all_pct or 0) > 50 else "",
            )
            if never_read_all_pct is not None
            else "",
        ]
        if t
    )

    return (
        '<div class="card">'
        "<h3>Read coverage — is the knowledge actually read?</h3>"
        f'<p class="role">collector: <code>transcripts</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        '<p class="tnote">"Never read" is meaningless without naming the denominator — both registered '
        "denominators (<code>knowledge_md</code>, <code>all_files</code>) are shown; see claim "
        "<code>knowledge-never-read-rate</code> in the Trust ledger.</p>"
        f"{raw_json_details(envelope, 'Raw JSON (transcripts-latest.json)')}"
        "</div>"
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


def render_knowledge_soul(envelope: dict) -> str:
    """Matches collectors/knowledge_soul.py's real, observed
    `metrics.registry_integrity` / `metrics.cross_link_integrity` /
    `metrics.contradictory_facts` / `metrics.orphan_rate` /
    `metrics.staleness_archive_honesty` / `metrics.voice_preservation` shape
    (verified against a real collect run — landed mid-work, S-3/TASK-109 —
    see output/knowledge_soul-latest.json). voice_preservation checks the
    knowledge repo's OWN docs (distinct from bench_voice_lint's with/
    without/rules ablation on GENERATED marketing copy — this is the
    SOUL's "prefer precise product... language over generic AI vocabulary"
    taste constraint applied to the repo's own content). `first()`
    fallback candidates from this renderer's original pre-landing guesses
    are kept after the real paths in case the shape changes later."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")

    registry = metrics.get("registry_integrity", {}) if isinstance(metrics.get("registry_integrity"), dict) else {}
    registry_headline = dig(registry, "forward_check", "headline", default=None)
    registry_uncovered = dig(registry, "reverse_check", "n_uncovered", default=None)

    cross_link = metrics.get("cross_link_integrity", {}) if isinstance(metrics.get("cross_link_integrity"), dict) else {}
    cross_link_pct = first(cross_link, "pct_resolving", "pct")
    cross_link_broken = first(cross_link, "n_broken", "broken_count")

    contradictory = metrics.get("contradictory_facts", {}) if isinstance(metrics.get("contradictory_facts"), dict) else {}
    contradictions_n = first(contradictory, "n_flagged", "count")

    orphan = metrics.get("orphan_rate", {}) if isinstance(metrics.get("orphan_rate"), dict) else {}
    orphan_pct = first(orphan, "orphan_rate_pct", "pct")
    orphan_n = first(orphan, "n_orphans")

    staleness = metrics.get("staleness_archive_honesty", {}) if isinstance(metrics.get("staleness_archive_honesty"), dict) else {}
    freshness_key_pct = dig(staleness, "frontmatter_freshness", "freshness_key_pct", default=None)
    any_frontmatter_pct = dig(staleness, "frontmatter_freshness", "any_frontmatter_pct", default=None)

    voice = metrics.get("voice_preservation", {}) if isinstance(metrics.get("voice_preservation"), dict) else {}
    own_voice = first(voice, "aggregate_violations_per_100_words", "mean_violations_per_100w")
    own_voice_n_files = first(voice, "n_files")

    if all(
        v is None
        for v in (registry_headline, cross_link_pct, contradictions_n, orphan_pct, freshness_key_pct, own_voice)
    ):
        raise ValueError("no recognized knowledge_soul fields found under metrics")

    own_voice_f = _as_float(own_voice)
    tiles_html = "".join(
        t
        for t in [
            tile(esc(registry_headline), "registry forward-check (ECOSYSTEM.md paths resolving)")
            if registry_headline is not None
            else "",
            tile(
                fmt_int(registry_uncovered),
                "top-level dirs uncovered by the registry",
                "hot" if (registry_uncovered or 0) > 0 else "",
            )
            if registry_uncovered is not None
            else "",
            tile(
                fmt_pct100(cross_link_pct),
                "cross-links resolving",
                "hot" if (_as_float(cross_link_pct) or 0) < 90 else "ok",
            )
            if cross_link_pct is not None
            else "",
            tile(fmt_int(cross_link_broken), "broken cross-links", "hot" if (cross_link_broken or 0) > 0 else "")
            if cross_link_broken is not None
            else "",
            tile(fmt_int(contradictions_n), "products with contradictory facts flagged", "hot" if (contradictions_n or 0) > 0 else "")
            if contradictions_n is not None
            else "",
            tile(fmt_pct100(orphan_pct), f"orphan rate ({fmt_int(orphan_n)} files)" if orphan_n is not None else "orphan rate")
            if orphan_pct is not None
            else "",
            tile(fmt_pct100(freshness_key_pct), "docs with a freshness key (created/last_updated/…)")
            if freshness_key_pct is not None
            else "",
            tile(fmt_pct100(any_frontmatter_pct), "docs with any frontmatter") if any_frontmatter_pct is not None else "",
            tile(
                f"{own_voice_f:.2f}/100w",
                f"own-content voice-lint violations ({fmt_int(own_voice_n_files)} files)"
                if own_voice_n_files is not None
                else "own-content voice-lint violations",
            )
            if own_voice_f is not None
            else "",
        ]
        if t
    )

    return (
        '<div class="card">'
        "<h3>S-3 · Knowledge-SOUL collector</h3>"
        f'<p class="role">collector: <code>knowledge_soul</code> · generated {esc(generated)}</p>'
        f'<div class="tiles">{tiles_html}</div>'
        "<p class=\"tnote\">Checks the SOUL's own anti-patterns directly: stale dump, marketing-only "
        "narrative, quietly contradictory facts. voice_preservation lints the repo's OWN docs — a "
        "different measure from the B-10 bench_voice_lint ablation below, which scores GENERATED copy.</p>"
        f"{raw_json_details(envelope, 'Raw JSON (knowledge_soul-latest.json)')}"
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
        '<p class="tnote"><strong>Finding: "distilled rules beat raw prose."</strong> Knowledge voice content '
        "reduces violations vs. bare prompting, but compiled rules-in-prompt outperform raw repo-as-context — "
        "the effective payload is the distilled rubric, not the prose (see claim "
        "<code>voice-conformance-deltas</code> in the Trust ledger).</p>"
        f"{raw_json_details(envelope, 'Raw JSON (bench_voice_lint-latest.json)')}"
        "</div>"
    )


# ---------------------------------------------------------------------------
# Organisms — Integration framework (cli-copilot SOUL)
# ---------------------------------------------------------------------------


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
    """Matches collectors/integrations.py's real `metrics.services` /
    `metrics.healthy_count` / `metrics.total_services` shape (verified
    against a real collect run — see output/integrations-latest.json, B-6).
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
        "<h3>Live integration health</h3>"
        f'<p class="role">collector: <code>integrations</code> · generated {esc(generated)}</p>'
        f'<div class="bars">{gauge}</div>'
        f"{version_note}"
        f'<div class="svc-chips">{chips}</div>'
        f"{raw_json_details(envelope, 'Raw JSON (integrations-latest.json)')}"
        "</div>"
    )


def _coerce_pass(v: Any) -> bool | None:
    if isinstance(v, bool):
        return v
    if isinstance(v, str):
        s = v.strip().lower()
        if s in ("pass", "passing", "true", "ok", "conformant"):
            return True
        if s in ("fail", "failing", "false", "non-conformant", "nonconformant"):
            return False
        return None
    if isinstance(v, dict):
        return _coerce_pass(first(v, "pass", "overall_pass", "conformant", "ok", "status"))
    return None


def _extract_scorecard(metrics: dict) -> list[dict] | None:
    for key in ("services", "per_service", "scorecard", "conformance"):
        val = metrics.get(key)
        if isinstance(val, dict) and val:
            return [{"name": k, "pass": _coerce_pass(v)} for k, v in val.items()]
        if isinstance(val, list) and val:
            out = []
            for item in val:
                if isinstance(item, dict):
                    name = item.get("name") or item.get("service") or item.get("id") or "unknown"
                    out.append({"name": name, "pass": _coerce_pass(item)})
            if out:
                return out
    return None


def render_cli_soul(envelope: dict) -> str:
    """Matches cli-copilot's S-4 conformance scorecard's real, observed
    `metrics.scorecard` (service → criterion → {status, reason}) /
    `metrics.totals_by_service` / `metrics.totals_by_criterion` /
    `metrics.gaps` / `metrics.suite_green` shape (verified against a real
    collect run — landed mid-work, S-4/TASK-110, in the OTHER repo
    (cli-copilot) and read here only as output/cli_soul-latest.json; this
    module never imports or duplicates its logic). Each service is
    checked against every one of `metrics.criteria` (the SOUL's own
    mechanical non-negotiables: health_registered, copilot_error_hierarchy,
    lazy_import, config_documented, docs_entry, test_file_exists); a
    non-"passed" criterion is "xfail" (a documented, tracked gap — `gaps`
    carries the reason) rather than a silent break, so per-service chips
    are colored good (0 gaps) / warn (tracked gaps), never crit, unless a
    future run reports an untracked failure. No utilization-ledger or
    portability-test field exists in this shape as landed — this
    renderer's original pre-landing guesses for those two are kept as a
    harmless no-op fallback (see the util_status/portability_pass lookups)
    in case a later S-4 revision adds them."""
    metrics = envelope.get("metrics", {})
    generated = envelope.get("generated_at", "?")

    scorecard = metrics.get("scorecard", {}) if isinstance(metrics.get("scorecard"), dict) else {}
    totals_by_service = metrics.get("totals_by_service", {}) if isinstance(metrics.get("totals_by_service"), dict) else {}
    totals = metrics.get("totals", {}) if isinstance(metrics.get("totals"), dict) else {}
    suite_green = metrics.get("suite_green")
    gaps = metrics.get("gaps") if isinstance(metrics.get("gaps"), list) else []
    criteria = metrics.get("criteria") if isinstance(metrics.get("criteria"), list) else []

    # Fallback for a hypothetical future flatter shape, plus this
    # renderer's original pre-landing guesses (harmless no-ops today).
    fallback_services = _extract_scorecard(metrics) if not scorecard else None
    utilization_status = first(
        metrics, "utilization_ledger.status", "usage_ledger.status",
        "utilization_ledger.enabled", "usage_ledger.enabled",
    )
    portability_pass = first(metrics, "portability_test.pass", "portability.pass", "portability_pass")

    if not scorecard and fallback_services is None and utilization_status is None and portability_pass is None:
        raise ValueError("no recognized cli_soul scorecard/ledger/portability fields found under metrics")

    n_services = len(scorecard) or len(fallback_services or [])
    n_conformant = sum(1 for s in totals_by_service.values() if isinstance(s, dict) and s.get("gap", 0) == 0)
    total_suite = sum(v for v in totals.values() if isinstance(v, int)) if totals else None
    total_passed = totals.get("passed") if totals.get("passed") is not None else None

    util_display = (
        esc(utilization_status).upper()
        if isinstance(utilization_status, str)
        else ("ON" if utilization_status is True else ("OFF" if utilization_status is False else None))
    )
    tiles_html = "".join(
        t
        for t in [
            tile(
                f"{n_conformant}/{n_services}",
                "services with zero SOUL-conformance gaps",
                "ok" if n_services and n_conformant == n_services else "",
            )
            if n_services
            else "",
            tile(fmt_int(total_passed), f"conformance-suite checks passing (of {fmt_int(total_suite)})", "ok")
            if total_passed is not None and total_suite
            else "",
            tile(fmt_int(len(gaps)), "tracked gaps (xfail, not crashes)", "" if gaps else "ok") if criteria else "",
            tile(
                "PASS" if suite_green is True else ("FAIL" if suite_green is False else "—"),
                "cli-copilot conformance suite",
                "ok" if suite_green is True else ("hot" if suite_green is False else ""),
            )
            if suite_green is not None
            else "",
            tile(
                "PASS" if portability_pass is True else ("FAIL" if portability_pass is False else "—"),
                "portability test (.env-only, byte-identical binary)",
                "ok" if portability_pass is True else ("hot" if portability_pass is False else ""),
            )
            if portability_pass is not None
            else "",
            tile(util_display, "utilization ledger status (C-1, opt-in)") if util_display is not None else "",
        ]
        if t
    )

    chips_html = ""
    if scorecard:
        chips_html = "".join(
            f'<span class="chip {"good" if totals_by_service.get(name, {}).get("gap", 0) == 0 else "warn"}">'
            f'{esc(name)} ({fmt_int(totals_by_service.get(name, {}).get("pass"))}/'
            f'{fmt_int(len(scorecard.get(name, {})))})</span>'
            for name in sorted(scorecard)
        )
    elif fallback_services:
        chips_html = "".join(
            f'<span class="chip {"good" if s["pass"] is True else ("crit" if s["pass"] is False else "neutral")}">'
            f'{esc(s["name"])}</span>'
            for s in sorted(fallback_services, key=lambda s: s["name"])
        )
    chips_block = (
        f'<h4 class="subhead">Per-service conformance ({fmt_int(len(criteria))} criteria each)</h4>'
        f'<div class="svc-chips">{chips_html}</div>'
        if chips_html
        else ""
    )

    return (
        '<div class="card">'
        "<h3>S-4 · CLI conformance scorecard</h3>"
        f'<p class="role">collector: <code>cli_soul</code> · generated {esc(generated)} · owning repo cli-copilot</p>'
        f'<div class="tiles">{tiles_html}</div>'
        f"{chips_block}"
        "<p class=\"tnote\">Criteria are the SOUL's own mechanical non-negotiables (health(), CopilotError+hint, "
        "lazy import, .env-only config documented, docs entry, test file present) — a chip's gap count is a "
        "documented, tracked xfail (<code>tests/test_soul_conformance.py</code>), not a silent break. This is a "
        "separate suite from the full pytest run the Trust ledger's "
        "<code>cli-copilot-test-suite-verified</code> claim tracks.</p>"
        f"{raw_json_details(envelope, 'Raw JSON (cli_soul-latest.json)')}"
        "</div>"
    )


def render_bench_mcp_twin(envelope: dict) -> str:
    """Matches collectors/bench_mcp_twin.py's real, observed
    `metrics.twins.<name>.net_advantage_tokens.{conservative_using_probe_everything_grammar_cost,
    optimistic_using_prose_grammar_cost}` / `metrics.f17_caveats` shape
    (verified against a real collect run — see
    output/bench_mcp_twin-latest.json, B-11, F-17). REFRAMED per
    TASK-111/S-5 (phase-2-prd.md §2.5): this bench checked an overview-DOC
    claim, not a SOUL claim — cli-copilot's SOUL never promises a token
    advantage over MCP twins, so a negative result here is a doc-claim
    correction (feeds B-17: reword/delete the doc claim), not a product
    verdict. Each twin reports TWO net-advantage variants (conservative/
    optimistic grammar-cost basis) — the collector's own
    `net_advantage_tokens` definition deliberately does not pick one, so
    this renderer shows both."""
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

    return (
        '<div class="card">'
        "<h3>MCP-twin — doc-claim check</h3>"
        f'<p class="role">collector: <code>bench_mcp_twin</code> · generated {esc(generated)}</p>'
        '<p class="tnote"><strong>Reframed (TASK-111/S-5):</strong> doc-claim check — token advantage requires '
        "shipping usage prose up front; the doc claim is reworded, not the product verdict. cli-copilot's SOUL "
        "never promised a token advantage over MCP twins, so a negative result here is not a SOUL failure "
        "(see claim <code>cli-mcp-net-token-advantage</code> and B-17 in the Trust ledger).</p>"
        '<h4 class="subhead">Net advantage, tokens (CLI vs. live MCP twin) — conservative vs. optimistic '
        "grammar-cost basis</h4>"
        f'<div class="bars">{bars}</div>'
        f"{raw_json_details(envelope, 'Raw JSON (bench_mcp_twin-latest.json)')}"
        "</div>"
    )


# ---------------------------------------------------------------------------
# Organisms — page sections
# ---------------------------------------------------------------------------


def render_scoreboard_section(outputs: dict) -> str:
    """Ecosystem-level scoreboard, header section (TASK-111/S-5). Per
    phase-2-prd.md §2.5, "more work done, faster" is an ecosystem-level
    claim that lives HERE — never inside a single component's section —
    and cannot be quoted until the ladder test (B-13/B-14) produces data.
    Tile values below are simple display-only arithmetic on numbers
    tasksdb/transcripts/framework_soul already computed (see module
    docstring); a tile whose inputs aren't available renders "—" with an
    explanatory note rather than an invented number."""
    tasksdb_env = outputs.get("tasksdb")
    tasksdb_ok = isinstance(tasksdb_env, dict) and isinstance(tasksdb_env.get("metrics"), dict)

    tiles = []
    notes: list[str] = []

    completed = None
    tasks_total = None
    reopened = None
    if tasksdb_ok:
        totals = dig(tasksdb_env, "metrics", "totals", default={}) or {}
        tasks_total = totals.get("tasks")
        completed = dig(totals, "by_status", "completed", default=None)
        reopened = totals.get("reopened_count")
        activity = totals.get("activity_range") or {}
        weeks = _weeks_between(activity.get("earliest"), activity.get("latest"))
        if completed is not None and weeks:
            tiles.append(tile(f"{completed / weeks:.1f}", "tasks finished / week (approx, whole-corpus average)"))
        else:
            tiles.append(tile("—", "tasks finished / week"))
            notes.append("tasks finished/week: tasksdb has completion counts but no usable activity_range span.")
    else:
        tiles.append(tile("—", "tasks finished / week"))
        notes.append("tasks finished/week: tasksdb collector not yet run.")

    if reopened is not None and tasks_total:
        tiles.append(
            tile(f"{reopened / tasks_total * 100:.1f}%", "rework rate (reopened-count proxy)", "hot" if reopened else "")
        )
    else:
        tiles.append(tile("—", "rework rate"))

    tiles.append(tile("not computable", "days start → done", "neutral"))
    notes.append(
        "days start → done: not computable from any landed collector — tasksdb has no completed_at column "
        "(only created_at/updated_at, truncated to month for the monthly trend), so true per-task cycle time "
        "cannot be derived; see the tasksdb collector's own reopened_count caveat for the same limitation class."
    )

    tokens_total_f = None
    framework_soul_env = outputs.get("framework_soul")
    if isinstance(framework_soul_env, dict) and isinstance(framework_soul_env.get("metrics"), dict):
        # Real shape (S-2, landed mid-work): main_session_token_trend.weekly is
        # a per-ISO-week dict blended from two sources (see
        # render_framework_soul's docstring) — sum whichever total field each
        # week carries. first() candidates from this tile's original
        # pre-landing guess are tried first, in case a future shape adds a
        # ready-made total.
        tokens_total_f = _as_float(
            first(
                framework_soul_env["metrics"],
                "token_totals.main_session", "main_session_tokens.total", "token_trend.total",
            )
        )
        if tokens_total_f is None:
            weekly = dig(framework_soul_env, "metrics", "main_session_token_trend", "weekly", default=None)
            if isinstance(weekly, dict) and weekly:
                weekly_vals = [
                    _as_float(first(wv, "input_plus_output_total", "total_tokens_all_models"))
                    for wv in weekly.values()
                    if isinstance(wv, dict)
                ]
                weekly_vals = [v for v in weekly_vals if v is not None]
                if weekly_vals:
                    tokens_total_f = sum(weekly_vals)

    if tokens_total_f is not None and completed:
        tiles.append(tile(fmt_int(round(tokens_total_f / completed)), "tokens / task (approx, main-session, whole corpus)"))
    else:
        tiles.append(tile("—", "tokens / task (approx)"))
        notes.append(
            "tokens/task: framework_soul's main-session token trend and/or tasksdb's completed-task count "
            "are not both available yet — this tile activates once both land."
        )

    notes_html = "".join(f'<p class="tnote">{esc(n)}</p>' for n in notes)

    ladder_card = (
        '<div class="card placeholder">'
        "<h3>Ladder test — ecosystem-level speed/quality proof</h3>"
        '<p class="role">scope: ecosystem, not a single component</p>'
        "<p>“More work done, faster” is an ecosystem-level claim, never a single component's — per "
        "the 2026-07-12 SOUL-alignment revision it cannot be quoted until the layered-ablation ladder (B-13) "
        "and the external pilot (B-14) produce data. Tracked by claim "
        "<code>t8-value-transfers-beyond-author</code> in the Trust ledger.</p>"
        '<p class="tnote">ladder test: not yet run — pending B-13 (layered ablation harness) and B-14 '
        "(external pilot protocol), phase-2-prd.md P3.</p>"
        "</div>"
    )

    return (
        '<section id="scoreboard">'
        '<span class="eyebrow">Ecosystem scoreboard</span>'
        "<h2>Is the work moving?</h2>"
        '<div class="callout warn"><strong>All numbers on this page are single-author data (T8 open).</strong> '
        "No number here has been reproduced by anyone other than this machine's own owner running these "
        "collectors against their own history.</div>"
        f'<div class="tiles">{"".join(tiles)}</div>'
        f"{notes_html}"
        f'<div class="cards">{ladder_card}</div>'
        "</section>"
    )


def render_framework_section(outputs: dict, claims_by_id: dict) -> str:
    cards = [
        dispatch(
            outputs.get("bench_resume_cost"),
            "bench_resume_cost",
            render_bench_resume_cost,
            "S-1 · Resume-cost bench",
            "Tokens and correctness resuming real work with vs. without Memory/Task state, via headless "
            "claude — the framework's core Job statement, measured directly.",
        ),
        dispatch(
            outputs.get("framework_soul"),
            "framework_soul",
            render_framework_soul,
            "S-2 · Framework-SOUL collector",
            "Externalization ratio (checks the SOUL's own '~94% less context' claim), agent return-size "
            "frugality (~100-token target), main-session token trend, and QA-gate/ARTIFACT-marker adherence.",
        ),
        dispatch(
            outputs.get("transcripts"),
            "transcripts",
            render_framework_discipline,
            "Discipline — delegation & protocol adherence",
            "Delegation rate under both registered definitions, protocol-declaration rate under both "
            "denominators — the mechanical-enforcement half of SOUL Principle 2.",
        ),
        dispatch(
            outputs.get("evals"),
            "evals",
            render_evals,
            "Golden-set eval coverage",
            "cc eval golden-set pass-rate per agent (LocalPythonRunner, deterministic, no LLM call).",
            claim_ref_note("agent-eval-coverage", claims_by_id),
        ),
        dispatch(
            outputs.get("tasksdb"),
            "tasksdb",
            render_tasksdb,
            "Task Copilot throughput",
            "Per-repo task/PRD/work-product counts, completion rate, and monthly trend from every "
            "*/.copilot/tasks.db store on this machine.",
        ),
    ]
    footer = (
        '<p class="foot-chip-row"><span class="tnote">Sync plumbing (Codex parity — demoted from a headline '
        "metric per the SOUL-alignment revision; same framework, two harnesses, so the Claude↔Codex "
        f"comparison itself is dropped as a measurement):</span> {parity_footer_chip(outputs.get('parity'))}</p>"
    )
    return (
        '<section id="framework">'
        + soul_intro(
            eyebrow="Component 1 of 3 · claude-copilot &amp; codex-copilot",
            title="Development framework",
            quote=(
                "they want to keep their decisions, process, and context from evaporating every time a "
                "session ends — without burning their token budget rebuilding it, so they can do "
                "disciplined, resumable, inspectable work instead of starting from zero every morning"
            ),
            soul_note=(
                'SOUL: <code>/Volumes/Dev/Sites/COPILOT/claude-copilot/SOUL.md</code> — explicitly does '
                "NOT claim speed or output quality (Gate 3: Honesty Test, Principle 4)."
            ),
            lede=(
                "Contains Task Copilot, Memory Copilot, and the specialized-agent roster. Measured against "
                "its own promise — process discipline and context efficiency — never against speed or "
                "software quality, which this SOUL explicitly refuses to claim."
            ),
        )
        + f'<div class="cards">{"".join(cards)}</div>'
        + footer
        + "</section>"
    )


def render_knowledge_section(outputs: dict, claims_by_id: dict) -> str:
    cards = [
        dispatch(
            outputs.get("bench_knowledge_qa"),
            "bench_knowledge_qa",
            render_bench_knowledge_qa,
            "B-9 · Private-fact Q&A bench",
            "Closed-book questions generated from product dossiers, scored with-knowledge vs. an empty "
            "tree — a contamination-immune ablation.",
            claim_ref_note("knowledge-factual-accuracy-delta", claims_by_id),
        ),
        dispatch(
            outputs.get("knowledge_soul"),
            "knowledge_soul",
            render_knowledge_soul,
            "S-3 · Knowledge-SOUL collector",
            "Registry & cross-link integrity, contradictory-facts detection, staleness/archive honesty, "
            "orphan rate, and voice-lint of the repo's own company content.",
        ),
        dispatch(
            outputs.get("transcripts"),
            "transcripts",
            render_knowledge_read_coverage,
            "Read coverage",
            "Is the knowledge that exists actually read? Both registered never-read denominators, mined "
            "from ~/.claude/projects and ~/.codex/sessions.",
        ),
        dispatch(
            outputs.get("bench_voice_lint"),
            "bench_voice_lint",
            render_bench_voice_lint,
            "B-10 · Voice-conformance bench",
            "Deterministic linter compiled from the tone-of-voice rubric, scored across bare / "
            "rules-in-prompt / knowledge-repo arms.",
            claim_ref_note("voice-conformance-deltas", claims_by_id),
        ),
    ]
    return (
        '<section id="knowledge">'
        + soul_intro(
            eyebrow="Component 2 of 3 · knowledge-copilot",
            title="Knowledge framework",
            quote=(
                "Help humans and agents understand the company, its methodologies, and its product "
                "ecosystem accurately enough to make good build, integrate, extend, and operating decisions"
            ),
            soul_note=(
                'SOUL: <code>/Volumes/Dev/Sites/COPILOT/knowledge-copilot-internal/SOUL.md</code> — must never '
                "become a stale content dump, a marketing-only narrative, or a place where contradictory "
                "product facts quietly coexist."
            ),
            lede="Measured against accurate understanding for good decisions — never against volume or polish.",
        )
        + f'<div class="cards">{"".join(cards)}</div>'
        + "</section>"
    )


def render_integration_section(outputs: dict, claims_by_id: dict) -> str:
    cards = [
        dispatch(
            outputs.get("cli_soul"),
            "cli_soul",
            render_cli_soul,
            "S-4 · CLI conformance scorecard",
            "Mechanical check of the SOUL quality bar per service (health(), --json cleanliness, "
            "CopilotError+hint, lazy instantiation, .env-only config) plus a portability test.",
        ),
        dispatch(
            outputs.get("integrations"),
            "integrations",
            render_integrations,
            "Live integration health",
            "Live-integration count from copilot health --json, plus a status chip per service.",
        ),
        dispatch(
            outputs.get("bench_mcp_twin"),
            "bench_mcp_twin",
            render_bench_mcp_twin,
            "MCP-twin — doc-claim check",
            "copilot crm / db against their live MCP twins — reframed as a doc-claim check per the "
            "SOUL-alignment revision, not a product verdict.",
            claim_ref_note("cli-mcp-net-token-advantage", claims_by_id),
        ),
    ]
    return (
        '<section id="integration">'
        + soul_intro(
            eyebrow="Component 3 of 3 · cli-copilot",
            title="Integration framework",
            quote=(
                "One binary that gives every Copilot project and agent a single, consistent, scriptable "
                "way to operate ~20 external services from the terminal — a uniform façade, never the "
                "services themselves"
            ),
            soul_note=(
                'SOUL: <code>/Volumes/Dev/Sites/COPILOT/cli-copilot-internal/SOUL.md</code> — one binary, one '
                "grammar; client, never server; honest, hint-bearing failure."
            ),
            lede="Measured against uniformity and honest failure per service — never against how many services exist.",
        )
        + f'<div class="cards">{"".join(cards)}</div>'
        + "</section>"
    )


# ---------------------------------------------------------------------------
# Organisms — Trust ledger (claims register, rendered live)
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
            '<span class="eyebrow">Trust ledger</span>'
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
        '<span class="eyebrow">Trust ledger</span>'
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
# system exactly (same CVD-validated palette, same type system) — unchanged
# by TASK-111/S-5, per that task's explicit instruction to keep the token
# system exactly as it passed CVD validation. Only the dashboard-specific
# additions at the bottom (subhead, trend chart, service chips, placeholder
# cards, raw-json details, jump nav, theme toggle, soul-quote blockquote,
# footer chip row) are new/extended.
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

  /* --- TASK-111/S-5 additions: SOUL-quote intro + footer sync chip ------ */

  blockquote.soulquote {
    margin:14px 0 4px; padding:14px 18px; border-left:3px solid var(--accent);
    background:var(--raised); border-radius:0 8px 8px 0; font-style:italic;
    color:var(--ink); font-size:1.02rem; box-shadow:var(--shadow);
  }
  p.soulpath { font-size:.8rem; color:var(--muted); margin:4px 0 18px; }
  p.soulpath code { font-size:.82em; }

  .foot-chip-row { margin-top:20px; }
  .foot-chip-row .chip { margin-left:8px; vertical-align:middle; }

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
    scoreboard_html: str,
    framework_html: str,
    knowledge_html: str,
    integration_html: str,
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
  <p class="meta">Development / Knowledge / Integration frameworks, each measured against its own ratified SOUL
     promise, plus an ecosystem scoreboard and a trust ledger — rendered from whatever collector output and
     claims-register state exist on this machine right now. This page computes nothing beyond simple
     display-only arithmetic on numbers a collector already produced (e.g. "tasks/week" divides tasksdb's own
     monthly totals by its own activity span); every number here was written by a
     <code>cse_bench.py collect</code> run or already lives in <code>claims.yaml</code> (Control Tower invariant
     #1: the CLI/collectors compute, the view renders).</p>
  <div class="runline">GENERATED {generated_at} · {present_count}/{total_count} COLLECTORS PRESENT ({present_list})</div>
  <nav class="jumpnav" aria-label="Dashboard sections">
    <a href="#scoreboard">Scoreboard</a>
    <a href="#framework">Development framework</a>
    <a href="#knowledge">Knowledge framework</a>
    <a href="#integration">Integration framework</a>
    <a href="#trust">Trust ledger</a>
  </nav>
  <button id="theme-toggle" type="button">Dark mode</button>
</header>

{scoreboard_html}
{framework_html}
{knowledge_html}
{integration_html}
{trust_html}

<footer class="foot">
  <p><strong>Source.</strong> <code>tools/cse-bench/output/*-latest.json</code> (gitignored, regenerated by
     <code>python3 cse_bench.py collect</code>) and
     <code>docs/40-initiatives/01-cse-auditability/claims.yaml</code> (git-committed, the pre-registration
     record). Refresh with <code>python3 cse_bench.py collect &amp;&amp; python3 cse_bench.py render</code>.</p>
  <p>Rendered by <code>tools/cse-bench/render/dashboard.py</code> — original build TASK-91/B-8, reorganized by
     component/SOUL in TASK-111/S-5 · Copilot Control Tower repo.</p>
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

    scoreboard_html = safe_section(render_scoreboard_section, outputs)
    framework_html = safe_section(render_framework_section, outputs, claims_by_id)
    knowledge_html = safe_section(render_knowledge_section, outputs, claims_by_id)
    integration_html = safe_section(render_integration_section, outputs, claims_by_id)
    trust_html = safe_section(render_trust_section, claims_data, claims_error)

    return build_page(
        generated_at=esc(generated_at),
        present_count=len(present),
        total_count=len(KNOWN_COLLECTORS),
        present_list=esc(", ".join(present) if present else "none yet"),
        scoreboard_html=scoreboard_html,
        framework_html=framework_html,
        knowledge_html=knowledge_html,
        integration_html=integration_html,
        trust_html=trust_html,
    )
