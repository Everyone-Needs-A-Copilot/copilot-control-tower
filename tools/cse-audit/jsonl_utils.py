"""
jsonl_utils.py — low-level streaming helpers for Claude Code session transcripts.

Design goal: never hold more than one JSONL line (and the small amount of
per-file state a metric needs) in memory at a time. The corpus this was
written against is ~532MB across ~767 files; reading line-by-line via a file
handle iterator is streaming by construction (Python never buffers the whole
file when you `for line in fh`), so no file is ever loaded whole into memory.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Iterator, Optional


def iter_jsonl_records(path: Path) -> Iterator[dict]:
    """Yield one parsed JSON object per non-blank line. Skips malformed lines
    silently (transcripts occasionally contain a truncated final line from a
    crashed/killed session — this is expected, not an error worth surfacing
    per-line, but callers can track skip counts via `iter_jsonl_records_counted`).
    """
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def iter_jsonl_records_counted(path: Path) -> Iterator[tuple[dict, int, int]]:
    """Like iter_jsonl_records but also yields (line_no, malformed_so_far).
    Useful for diagnostics without a second pass.
    """
    malformed = 0
    line_no = 0
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line_no += 1
            stripped = line.strip()
            if not stripped:
                continue
            try:
                rec = json.loads(stripped)
            except json.JSONDecodeError:
                malformed += 1
                continue
            yield rec, line_no, malformed


def first_text_block(content) -> Optional[str]:
    """Return the text of the first *text*-type content block in an assistant
    message's `content` list, skipping `thinking` blocks (which never carry
    the visible [PROTOCOL: ...] preamble — that appears in the first block
    the user actually sees). Returns None if content is a bare string (then
    the caller should use it directly) or if no text block exists.
    """
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return None
    for block in content:
        if isinstance(block, dict) and block.get("type") == "text":
            return block.get("text", "")
    return None


def tool_use_blocks(content) -> list[dict]:
    """Return all tool_use blocks in an assistant message's content list."""
    if not isinstance(content, list):
        return []
    return [b for b in content if isinstance(b, dict) and b.get("type") == "tool_use"]


def is_real_user_turn(record: dict) -> bool:
    """Operational definition of 'a turn that would have fired Claude Code's
    UserPromptSubmit hook' — i.e. a genuine human-submitted prompt, not a
    tool_result echoed back as a synthetic `type: "user"` record and not a
    system-injected meta message (e.g. the `<local-command-caveat>` wrapper
    Claude Code inserts around local-command output).

    Reverse-engineered from `.claude/hooks/user-prompt-submit.sh`, which
    increments its turn counter once per UserPromptSubmit event — one event
    per real prompt (typed or slash command), never per tool_result.

    Inferred rule (flagged — not verified against Claude Code's own source):
      - record.type == "user"
      - record.isSidechain is not True (only main-session prompts count;
        the synthetic prompt Claude Code writes into a subagent's own
        transcript to hand it its task is not a UserPromptSubmit event)
      - record.isMeta is not True (excludes synthetic wrapper messages)
      - message.content is a non-empty string, OR a list containing at
        least one block that is NOT of type "tool_result" (an image or
        text block pasted by the human)
    """
    if record.get("type") != "user":
        return False
    if record.get("isSidechain") is True:
        return False
    if record.get("isMeta") is True:
        return False
    msg = record.get("message")
    if not isinstance(msg, dict):
        return False
    content = msg.get("content")
    if isinstance(content, str):
        return len(content.strip()) > 0
    if isinstance(content, list):
        return any(
            isinstance(b, dict) and b.get("type") != "tool_result" for b in content
        )
    return False


def model_family(model: Optional[str]) -> str:
    """Bucket a raw model string into a coarse family for the Sonnet-vs-Opus
    'model tier' claim. Anything not recognized falls into 'other' rather
    than being silently dropped, so unexpected model strings are visible in
    aggregate output instead of vanishing.
    """
    if not model:
        return "unknown"
    m = model.lower()
    if m == "<synthetic>":
        return "synthetic"  # compaction-summary placeholder, not a real call
    if "opus" in m:
        return "opus"
    if "sonnet" in m:
        return "sonnet"
    if "haiku" in m:
        return "haiku"
    return "other"
