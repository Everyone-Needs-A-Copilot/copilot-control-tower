"""
session_metrics.py — per-session metric extraction for the delegation-rate /
protocol-declaration falsification probe.

CORPUS LAYOUT (reverse-engineered by inspection, summer 2026 Claude Code CLI):

    ~/.claude/projects/<project-slug>/<sessionId>.jsonl          <- main session
    ~/.claude/projects/<project-slug>/<sessionId>/subagents/agent-<id>.jsonl  <- one
        file per Task/Agent tool invocation, containing that subagent's own
        turns. isSidechain=True in every record in these files; isSidechain
        is False (or absent) in every record of the main <sessionId>.jsonl.
    ~/.claude/projects/<project-slug>/<sessionId>/tool-results/... <- large
        tool outputs the CLI externalizes rather than inlining (not used here).

This module treats "main session file" + "its sibling subagents/*.jsonl
files" as the unit of analysis ("a session").
"""
from __future__ import annotations

import statistics
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from jsonl_utils import (
    first_text_block,
    is_real_user_turn,
    iter_jsonl_records,
    model_family,
    tool_use_blocks,
)

# Tool names that represent "delegate to a subagent" in the transcript.
# "Agent" is what this corpus actually uses (see .claude/agents manifest +
# pretool-check.sh, which checks tool_input.subagent_type on a tool named
# "Agent"). "Task" is included defensively — it is the generic Claude Code
# name for the same mechanism in other configurations/versions; it does not
# appear in this corpus but a reusable tool should not assume one repo's
# naming is universal.
AGENT_TOOL_NAMES = {"Agent", "Task"}


@dataclass
class TokenTotals:
    input_tokens: int = 0
    cache_creation_input_tokens: int = 0
    cache_read_input_tokens: int = 0
    output_tokens: int = 0
    n_messages_with_usage: int = 0

    def add(self, usage: dict) -> None:
        self.input_tokens += int(usage.get("input_tokens") or 0)
        self.cache_creation_input_tokens += int(usage.get("cache_creation_input_tokens") or 0)
        self.cache_read_input_tokens += int(usage.get("cache_read_input_tokens") or 0)
        self.output_tokens += int(usage.get("output_tokens") or 0)
        self.n_messages_with_usage += 1

    def merge(self, other: "TokenTotals") -> "TokenTotals":
        return TokenTotals(
            input_tokens=self.input_tokens + other.input_tokens,
            cache_creation_input_tokens=self.cache_creation_input_tokens + other.cache_creation_input_tokens,
            cache_read_input_tokens=self.cache_read_input_tokens + other.cache_read_input_tokens,
            output_tokens=self.output_tokens + other.output_tokens,
            n_messages_with_usage=self.n_messages_with_usage + other.n_messages_with_usage,
        )

    @property
    def total_context_tokens(self) -> int:
        """input + cache_creation + cache_read — i.e. everything billed as
        'context' for the turn, excluding output. Used for the cache-read
        share (the '~94%/~70% less context' claims are about this ratio)."""
        return self.input_tokens + self.cache_creation_input_tokens + self.cache_read_input_tokens

    @property
    def cache_read_share(self) -> Optional[float]:
        total = self.total_context_tokens
        if total == 0:
            return None
        return self.cache_read_input_tokens / total


@dataclass
class SessionMetrics:
    session_id: str
    project_slug: str
    main_path: Path
    cwd: Optional[str] = None
    start_ts: Optional[str] = None
    end_ts: Optional[str] = None
    version: Optional[str] = None

    n_user_turns: int = 0                    # hook-equivalent "turns"
    n_main_assistant_msgs: int = 0
    n_main_tool_calls: int = 0
    n_agent_delegations: int = 0             # Agent/Task tool_use calls issued by main session
    delegated_agent_types: Counter = field(default_factory=Counter)

    n_protocol_declared_all: int = 0         # every main-session assistant msg counted
    n_protocol_declared_first_of_turn: int = 0
    n_first_of_turn_msgs: int = 0

    main_model_msgs: Counter = field(default_factory=Counter)   # family -> count
    main_tokens: TokenTotals = field(default_factory=TokenTotals)

    n_subagent_files: int = 0
    n_subagent_assistant_msgs: int = 0
    n_subagent_tool_calls: int = 0
    subagent_model_msgs: Counter = field(default_factory=Counter)
    subagent_tokens: TokenTotals = field(default_factory=TokenTotals)

    malformed_lines: int = 0

    # ---- derived metrics -------------------------------------------------

    @property
    def total_tool_calls(self) -> int:
        return self.n_main_tool_calls + self.n_subagent_tool_calls

    @property
    def delegation_rate_toolshare(self) -> Optional[float]:
        """Primary reverse-engineered definition of the April diagnostic's
        'delegation rate'. See PROBE_DEFINITIONS.md for the reasoning.

        sidechain (subagent-executed) tool calls / all tool calls (main +
        subagent) in the session. This is what "the main session did 94% of
        all tool calls itself" most naturally operationalizes: a tool call
        is either executed directly by the orchestrator or inside a
        delegated subagent context, and isSidechain / file-location is an
        unambiguous ground-truth signal for which.
        """
        total = self.total_tool_calls
        if total == 0:
            return None
        return self.n_subagent_tool_calls / total

    @property
    def delegation_rate_eventshare(self) -> Optional[float]:
        """Alternative definition: of the main session's own tool-call
        decisions, what fraction were 'call an agent' rather than 'do it
        myself'. Denominator is main-session tool calls only (Agent calls
        included, since choosing to delegate IS one of the main session's
        tool-call choices)."""
        if self.n_main_tool_calls == 0:
            return None
        return self.n_agent_delegations / self.n_main_tool_calls

    @property
    def protocol_declaration_rate_all(self) -> Optional[float]:
        if self.n_main_assistant_msgs == 0:
            return None
        return self.n_protocol_declared_all / self.n_main_assistant_msgs

    @property
    def protocol_declaration_rate_first_of_turn(self) -> Optional[float]:
        if self.n_first_of_turn_msgs == 0:
            return None
        return self.n_protocol_declared_first_of_turn / self.n_first_of_turn_msgs

    @property
    def turns(self) -> int:
        return self.n_user_turns

    def model_share(self, scope: str = "combined") -> dict:
        """Return {family: fraction} of assistant messages by model family.
        scope: 'main', 'sub', or 'combined'."""
        if scope == "main":
            counts = self.main_model_msgs
        elif scope == "sub":
            counts = self.subagent_model_msgs
        else:
            counts = self.main_model_msgs + self.subagent_model_msgs
        total = sum(counts.values())
        if total == 0:
            return {}
        return {k: v / total for k, v in counts.items()}


def _process_assistant_record(
    rec: dict,
    real_user_uuids: set,
    model_msgs: Counter,
    tokens: TokenTotals,
) -> tuple[int, int, bool, bool, str, str]:
    """Shared logic for both main-session and subagent assistant records.
    Returns (n_tool_calls, n_agent_calls, protocol_declared, is_first_of_turn,
    first_agent_type_delegated_to_or_empty, model_family).
    """
    msg = rec.get("message") or {}
    content = msg.get("content")
    model = model_family(msg.get("model"))
    if model not in ("synthetic", "unknown"):
        model_msgs[model] += 1
    usage = msg.get("usage")
    if isinstance(usage, dict):
        tokens.add(usage)

    blocks = tool_use_blocks(content)
    n_tool_calls = len(blocks)
    agent_blocks = [b for b in blocks if b.get("name") in AGENT_TOOL_NAMES]
    n_agent_calls = len(agent_blocks)
    agent_type = ""
    if agent_blocks:
        agent_type = str((agent_blocks[0].get("input") or {}).get("subagent_type") or "")

    text = first_text_block(content) or ""
    protocol_declared = text.lstrip().startswith("[PROTOCOL")

    is_first_of_turn = rec.get("parentUuid") in real_user_uuids

    return n_tool_calls, n_agent_calls, protocol_declared, is_first_of_turn, agent_type, model


def compute_session_metrics(main_path: Path) -> SessionMetrics:
    """Stream a main session file (and its sibling subagents/*.jsonl files)
    and compute all metrics in a small number of linear passes.

    Main file: single pass, maintaining a running set of uuids belonging to
    "real user turn" records so we can classify each assistant message as
    first-of-turn (parentUuid in that set) without a second pass — this
    works because JSONL records are written in causal order (a parent
    record's line always precedes its children's).
    """
    session_id = main_path.stem
    project_slug = main_path.parent.name
    sm = SessionMetrics(session_id=session_id, project_slug=project_slug, main_path=main_path)

    real_user_uuids: set = set()

    for rec in iter_jsonl_records(main_path):
        ts = rec.get("timestamp")
        if ts:
            if sm.start_ts is None:
                sm.start_ts = ts
            sm.end_ts = ts
        if sm.cwd is None and rec.get("cwd"):
            sm.cwd = rec["cwd"]
        if sm.version is None and rec.get("version"):
            sm.version = rec["version"]

        rtype = rec.get("type")
        if rtype == "user":
            if is_real_user_turn(rec):
                sm.n_user_turns += 1
                uuid = rec.get("uuid")
                if uuid:
                    real_user_uuids.add(uuid)
        elif rtype == "assistant":
            sm.n_main_assistant_msgs += 1
            (
                n_tool_calls,
                n_agent_calls,
                protocol_declared,
                is_first_of_turn,
                agent_type,
                _model,
            ) = _process_assistant_record(rec, real_user_uuids, sm.main_model_msgs, sm.main_tokens)

            sm.n_main_tool_calls += n_tool_calls
            sm.n_agent_delegations += n_agent_calls
            if agent_type:
                sm.delegated_agent_types[agent_type] += 1
            if protocol_declared:
                sm.n_protocol_declared_all += 1
            if is_first_of_turn:
                sm.n_first_of_turn_msgs += 1
                if protocol_declared:
                    sm.n_protocol_declared_first_of_turn += 1

    # Sibling subagent files: <sessionId>/subagents/agent-*.jsonl
    subagents_dir = main_path.parent / session_id / "subagents"
    if subagents_dir.is_dir():
        for sub_path in sorted(subagents_dir.glob("agent-*.jsonl")):
            sm.n_subagent_files += 1
            for rec in iter_jsonl_records(sub_path):
                if rec.get("type") != "assistant":
                    continue
                sm.n_subagent_assistant_msgs += 1
                n_tool_calls, _n_agent, _decl, _first, _atype, _model = _process_assistant_record(
                    rec, set(), sm.subagent_model_msgs, sm.subagent_tokens
                )
                sm.n_subagent_tool_calls += n_tool_calls

    return sm


# ---------------------------------------------------------------------------
# Aggregation helpers
# ---------------------------------------------------------------------------

def median_iqr(values: list[float]) -> dict:
    """Median + IQR summary for a list of (non-None) floats. Session-level
    metrics here are heavily right-skewed (a handful of very long sessions),
    so medians/IQR are reported instead of, not in addition to as an
    afterthought to, means."""
    vals = sorted(v for v in values if v is not None)
    n = len(vals)
    if n == 0:
        return {"n": 0, "median": None, "q1": None, "q3": None, "iqr": None, "mean": None}
    median = statistics.median(vals)
    mean = statistics.fmean(vals)
    if n >= 2:
        q1, q3 = statistics.quantiles(vals, n=4)[0], statistics.quantiles(vals, n=4)[2]
    else:
        q1 = q3 = vals[0]
    return {"n": n, "median": median, "q1": q1, "q3": q3, "iqr": q3 - q1, "mean": mean}
