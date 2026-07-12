#!/usr/bin/env python3
"""
run_probe.py — falsification probe for the claude-copilot "hooks closed the
delegation-rate gap" claim (docs/10-architecture/04-framework-restructure-2026-04.md).

Orchestrates:
  1. corpus_scan  — per-session metrics from ~/.claude/projects/**/*.jsonl
  2. stats_cache_analysis — long-horizon daily trend from ~/.claude/stats-cache.json
  3. framework_registry — which projects actually have the mechanical hooks wired up

...and prints a single console report with medians/IQR, weekly tables, the
hooks-active vs hooks-inactive natural-control-group comparison, and an
explicit threats-to-validity section.

Usage:
    python3 run_probe.py [--projects-dir DIR] [--stats-cache PATH] [--out DIR]

Re-runnable, side-effect-free except for writing CSV/JSON artifacts to --out.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path

from framework_registry import classify_projects
from session_metrics import compute_session_metrics, median_iqr
from corpus_scan import find_main_session_files
import stats_cache_analysis as sca

HOOK_SHIP_DATE = date(2026, 4, 22)  # confirmed via git log, see report header

# Claude Code's own built-in generic subagent types. Delegating to these
# requires NO framework installation at all (no .claude/agents, no roster) —
# they are available in every project. Counting them as "delegation" credits
# the framework for behavior it did not cause. Rule 4 of the framework's own
# protocol-injection.md explicitly forbids using them ("NEVER use generic
# agents: Explore, Plan, general-purpose") but the Hook Enforcement Model
# table (restructure doc line ~332) marks this guardrail Advisory both
# before AND after the restructure — it was never made mechanical.
GENERIC_AGENT_TYPES = {"general-purpose", "explore", "plan"}


def parse_ts(ts: str) -> datetime:
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def fmt_pct(x):
    return "n/a" if x is None else f"{x * 100:.1f}%"


def fmt_num(x, nd=1):
    return "n/a" if x is None else f"{x:.{nd}f}"


def load_corpus(projects_dir: Path):
    main_files = find_main_session_files(projects_dir)
    sessions = []
    for f in main_files:
        try:
            sessions.append(compute_session_metrics(f))
        except Exception as e:  # noqa: BLE001
            print(f"[warn] {f}: {e}", file=sys.stderr)
    return sessions


def print_header(title: str):
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


def report_corpus_date_range(sessions):
    print_header("0. CORPUS COVERAGE")
    ts = [s.start_ts for s in sessions if s.start_ts]
    if not ts:
        print("No timestamped sessions found.")
        return None, None
    ts_sorted = sorted(ts)
    earliest = parse_ts(ts_sorted[0])
    latest = parse_ts(ts_sorted[-1])
    print(f"Main session files: {len(sessions)}")
    print(f"Earliest session start: {earliest.isoformat()}")
    print(f"Latest session start:   {latest.isoformat()}")
    print(f"Hook-ship date (from git log, see below): {HOOK_SHIP_DATE.isoformat()}")
    if earliest.date() > HOOK_SHIP_DATE:
        gap_days = (earliest.date() - HOOK_SHIP_DATE).days
        print(
            f"\n*** NO PRE-INTERVENTION RAW TRANSCRIPTS EXIST ON DISK ***\n"
            f"Earliest surviving session is {gap_days} days AFTER the hook-ship date.\n"
            f"An interrupted-time-series comparison of delegation rate / protocol-\n"
            f"declaration rate using raw transcripts is IMPOSSIBLE from this corpus.\n"
            f"(Likely cause: local session-transcript retention/cleanup — the CLI or\n"
            f"the user's own housekeeping does not keep JSONL transcripts indefinitely.)"
        )
    return earliest, latest


def report_delegation_and_protocol(sessions):
    print_header("1-2. DELEGATION RATE & PROTOCOL-DECLARATION RATE (post-hook period only)")
    tool_share = [s.delegation_rate_toolshare for s in sessions if s.delegation_rate_toolshare is not None]
    event_share = [s.delegation_rate_eventshare for s in sessions if s.delegation_rate_eventshare is not None]
    proto_all = [s.protocol_declaration_rate_all for s in sessions if s.protocol_declaration_rate_all is not None]
    proto_first = [s.protocol_declaration_rate_first_of_turn for s in sessions if s.protocol_declaration_rate_first_of_turn is not None]

    def show(name, vals):
        m = median_iqr(vals)
        print(f"{name}: n={m['n']} median={fmt_pct(m['median'])} "
              f"IQR=[{fmt_pct(m['q1'])}, {fmt_pct(m['q3'])}] mean={fmt_pct(m['mean'])}")

    show("Delegation rate (tool-share, primary defn)", tool_share)
    show("Delegation rate (event-share, alt defn)", event_share)
    show("Protocol declaration rate (all main-session turns)", proto_all)
    show("Protocol declaration rate (first assistant msg per user turn)", proto_first)

    print(f"\nApril diagnostic reference values: delegation rate 6%, protocol rate 3.5%")
    print("These CANNOT be recomputed for the pre-hook period (no raw transcripts).")
    print("The values above describe ONLY sessions from the post-hook period on this machine.")


def report_turns_and_model_mix(sessions):
    print_header("3-4. TURNS/SESSION & MODEL MIX (post-hook period only, raw corpus)")
    turns = [s.turns for s in sessions]
    m = median_iqr([float(t) for t in turns])
    print(f"Turns/session (hook-equivalent 'real user prompt' count): n={m['n']} "
          f"median={fmt_num(m['median'])} IQR=[{fmt_num(m['q1'])}, {fmt_num(m['q3'])}] mean={fmt_num(m['mean'])}")
    print("April diagnostic reference: 671 turns/session (pre-hook, untestable here for comparison)")

    fam_totals_main = defaultdict(int)
    fam_totals_combined = defaultdict(int)
    for s in sessions:
        for fam, cnt in s.main_model_msgs.items():
            fam_totals_main[fam] += cnt
        for fam, cnt in (s.main_model_msgs + s.subagent_model_msgs).items():
            fam_totals_combined[fam] += cnt

    def show_mix(name, totals):
        total = sum(totals.values())
        if total == 0:
            print(f"{name}: no data")
            return
        parts = ", ".join(f"{k}={v/total*100:.1f}%" for k, v in sorted(totals.items(), key=lambda kv: -kv[1]))
        print(f"{name} (n={total} assistant msgs): {parts}")

    show_mix("Model family share — MAIN SESSION ONLY", fam_totals_main)
    show_mix("Model family share — MAIN + SUBAGENT COMBINED", fam_totals_combined)
    print('Claim under test (line 172/282 of restructure doc): "Sonnet for ~94% of work"')


def report_tokens(sessions):
    print_header("5. TOKEN USAGE (main session, post-hook period)")
    cache_shares = [s.main_tokens.cache_read_share for s in sessions if s.main_tokens.cache_read_share is not None]
    m = median_iqr(cache_shares)
    print(f"Cache-read share of context tokens (main session): n={m['n']} "
          f"median={fmt_pct(m['median'])} IQR=[{fmt_pct(m['q1'])}, {fmt_pct(m['q3'])}]")

    per_turn = []
    for s in sessions:
        if s.turns > 0:
            per_turn.append(s.main_tokens.total_context_tokens / s.turns)
    m2 = median_iqr(per_turn)
    print(f"Context tokens per turn (main session): n={m2['n']} median={fmt_num(m2['median'],0)} "
          f"IQR=[{fmt_num(m2['q1'],0)}, {fmt_num(m2['q3'],0)}]")
    print('Claims under test: "~94% less context" / "~70% less context" (restructure doc framing).')
    print("No pre-hook baseline exists to compare against — this section is descriptive only.")


def report_weekly(sessions):
    print_header("6. WEEKLY TREND, post-hook raw corpus (delegation rate + protocol rate)")
    buckets = defaultdict(list)
    for s in sessions:
        if not s.start_ts:
            continue
        d = parse_ts(s.start_ts).date()
        key = d.isocalendar()[:2]
        buckets[key].append(s)
    print(f"{'ISO week':10} {'n':>4} {'turns/sess':>11} {'deleg.rate':>11} {'protocol%':>10}")
    for key in sorted(buckets):
        rows = buckets[key]
        turns_m = median_iqr([float(s.turns) for s in rows])
        dr = median_iqr([s.delegation_rate_toolshare for s in rows if s.delegation_rate_toolshare is not None])
        pr = median_iqr([s.protocol_declaration_rate_all for s in rows if s.protocol_declaration_rate_all is not None])
        print(f"{key[0]}-W{key[1]:02d}   {len(rows):>4} {fmt_num(turns_m['median']):>11} "
              f"{fmt_pct(dr['median']):>11} {fmt_pct(pr['median']):>10}")
    print("\nNo step-change is attributable to the intervention here: this entire window")
    print("is post-hook. Any trend visible is drift WITHIN the post period, not a")
    print("pre/post comparison.")


def report_stats_cache(stats_cache_path: Path):
    print_header("7. LONG-HORIZON TREND (stats-cache.json, spans the April 22 cutover)")
    if not stats_cache_path.is_file():
        print(f"stats-cache.json not found at {stats_cache_path} — skipping.")
        return
    rows = sca.load(stats_cache_path)
    pre, post = sca.segment_pre_post(rows, HOOK_SHIP_DATE)
    pre_sum = sca.summarize(pre, "pre-hook (Jan21-Apr21)")
    post_sum = sca.summarize(post, "post-hook (Apr22-Jul09)")

    for s in (pre_sum, post_sum):
        print(f"\n{s['label']}: {s['n_days']} days, {s['total_sessions']} session-days, "
              f"{s['total_messages']} messages, {s['total_tool_calls']} tool calls")
        mps, tps, ss = s["messages_per_session"], s["tool_calls_per_session"], s["sonnet_token_share"]
        print(f"  messages/session-day:   median={fmt_num(mps.get('median'))} mean={fmt_num(mps.get('mean'))} (n={mps['n']} days)")
        print(f"  tool-calls/session-day: median={fmt_num(tps.get('median'))} mean={fmt_num(tps.get('mean'))} (n={tps['n']} days)")
        print(f"  Sonnet token share:     median={fmt_pct(ss.get('median'))} mean={fmt_pct(ss.get('mean'))} (n={ss['n']} days)")

    print("\nCAVEAT: sessionCount is daily-*active*-session count, not sessions-started;")
    print("multi-day sessions are counted once per active day, biasing messages/session")
    print("and tool-calls/session downward on both sides of the cutover (see module docstring).")
    print("This is the only artifact that actually straddles the intervention date — treat")
    print("its 'messages/session' trend as the closest available (imperfect) proxy for the")
    print("671-turns/session claim, NOT as a recomputation of the same metric.")


def report_hooks_natural_control(sessions):
    print_header("8. NATURAL CONTROL GROUP: mechanical-hooks-active vs hooks-inactive projects")
    cwds = {s.cwd for s in sessions if s.cwd}
    fw_map = classify_projects(cwds)

    active_sessions = [s for s in sessions if s.cwd and fw_map.get(s.cwd) and fw_map[s.cwd].mechanical_hooks_registered]
    agents_only_sessions = [
        s for s in sessions if s.cwd and fw_map.get(s.cwd)
        and fw_map[s.cwd].agents_present and not fw_map[s.cwd].mechanical_hooks_registered
    ]
    no_framework_sessions = [
        s for s in sessions if s.cwd and fw_map.get(s.cwd) and not fw_map[s.cwd].agents_present
    ]

    print(f"Projects with mechanical hooks REGISTERED in .claude/settings.json (PreToolUse -> pretool-check.sh):")
    for cwd, st in fw_map.items():
        if st.mechanical_hooks_registered:
            covers = "Bash+Read+Edit" if st.hook_matcher_covers_read_edit else "Bash ONLY"
            print(f"  - {cwd}  (matcher covers: {covers})")
    n_active_projects = sum(1 for st in fw_map.values() if st.mechanical_hooks_registered)
    if n_active_projects == 0:
        print("  (none)")

    print(f"\nAgents-present-but-NO-mechanical-hooks projects: "
          f"{sum(1 for st in fw_map.values() if st.agents_present and not st.mechanical_hooks_registered)}")
    print(f"No-framework-at-all projects: {sum(1 for st in fw_map.values() if not st.agents_present)}")

    def show_group(name, group):
        dr = median_iqr([s.delegation_rate_toolshare for s in group if s.delegation_rate_toolshare is not None])
        pr = median_iqr([s.protocol_declaration_rate_all for s in group if s.protocol_declaration_rate_all is not None])
        print(f"\n{name}: n_sessions={len(group)}")
        print(f"  delegation rate: median={fmt_pct(dr['median'])} IQR=[{fmt_pct(dr['q1'])},{fmt_pct(dr['q3'])}] (n={dr['n']})")
        print(f"  protocol rate:   median={fmt_pct(pr['median'])} IQR=[{fmt_pct(pr['q1'])},{fmt_pct(pr['q3'])}] (n={pr['n']})")

    show_group("HOOKS-ACTIVE sessions (mechanical enforcement wired up)", active_sessions)
    show_group("AGENTS-ONLY sessions (framework agents present, hooks NOT wired up)", agents_only_sessions)
    show_group("NO-FRAMEWORK sessions (no .claude/agents at all)", no_framework_sessions)

    print("\nThis is a CROSS-SECTIONAL comparison within the same post-hook-ship-date")
    print("period (all sessions in this corpus start after 2026-06-09) — it is not a")
    print("before/after comparison. It substitutes for the missing temporal control.")
    print("Composition caveat: the hooks-active group is entirely claude-copilot's own")
    print("dev repo (meta-work building the framework) — a different task mix than the")
    print("product repos in the other two groups. Do not read a causal hook effect into")
    print("this without controlling for that confound.")


def report_generic_vs_named_delegation(sessions):
    print_header("9. SPECIALIST vs GENERIC delegation (is 'delegation' crediting the framework fairly?)")
    cwds = {s.cwd for s in sessions if s.cwd}
    fw_map = classify_projects(cwds)

    def group_of(s):
        st = fw_map.get(s.cwd) if s.cwd else None
        if not st:
            return "unknown"
        if st.mechanical_hooks_registered:
            return "hooks-active"
        if st.agents_present:
            return "agents-only"
        return "no-framework"

    groups = defaultdict(lambda: {"named": 0, "generic": 0, "sessions_delegating": 0, "sessions_total": 0})
    for s in sessions:
        g = groups[group_of(s)]
        g["sessions_total"] += 1
        if s.n_agent_delegations > 0:
            g["sessions_delegating"] += 1
        for atype, cnt in s.delegated_agent_types.items():
            if atype.lower() in GENERIC_AGENT_TYPES:
                g["generic"] += cnt
            else:
                g["named"] += cnt

    print(f"{'group':16} {'n_sessions':>10} {'delegating>=1':>14} {'named calls':>12} {'generic calls':>14} {'named share':>12}")
    for gname, g in sorted(groups.items()):
        total = g["named"] + g["generic"]
        share = f"{g['named']/total*100:.1f}%" if total else "n/a"
        print(f"{gname:16} {g['sessions_total']:>10} {g['sessions_delegating']:>14} {g['named']:>12} {g['generic']:>14} {share:>12}")

    print("\nInterpretation: a 'no-framework' project has zero named specialists to route to by")
    print("construction, yet still shows delegation-tool-call volume in section 8 — that volume")
    print("is Claude Code's built-in Explore/general-purpose agents, not framework routing. Any")
    print("delegation-rate number that doesn't separate this out (including the primary metric in")
    print("section 1-2, which does NOT separate it) overstates what the FRAMEWORK specifically")
    print("caused, in favor of the framework, by construction.")


def write_csv_and_json(sessions, out_dir: Path):
    from corpus_scan import row_from_metrics, FIELDNAMES
    cwds = {s.cwd for s in sessions if s.cwd}
    fw_map = classify_projects(cwds)
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "session_metrics.csv").open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDNAMES)
        w.writeheader()
        for s in sessions:
            w.writerow(row_from_metrics(s, fw_map.get(s.cwd) if s.cwd else None))
    with (out_dir / "framework_registry.json").open("w") as fh:
        json.dump({cwd: vars(st) for cwd, st in fw_map.items()}, fh, indent=2, default=str)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--projects-dir", default=str(Path.home() / ".claude" / "projects"))
    ap.add_argument("--stats-cache", default=str(Path.home() / ".claude" / "stats-cache.json"))
    ap.add_argument("--out", default=str(Path(__file__).parent / "output"))
    args = ap.parse_args()

    projects_dir = Path(args.projects_dir)
    out_dir = Path(args.out)

    print(f"Loading corpus from {projects_dir} ...", file=sys.stderr)
    sessions = load_corpus(projects_dir)
    print(f"Loaded {len(sessions)} sessions.", file=sys.stderr)

    report_corpus_date_range(sessions)
    report_delegation_and_protocol(sessions)
    report_turns_and_model_mix(sessions)
    report_tokens(sessions)
    report_weekly(sessions)
    report_stats_cache(Path(args.stats_cache))
    report_hooks_natural_control(sessions)
    report_generic_vs_named_delegation(sessions)

    write_csv_and_json(sessions, out_dir)
    print(f"\nArtifacts written to {out_dir}", file=sys.stderr)


if __name__ == "__main__":
    main()
