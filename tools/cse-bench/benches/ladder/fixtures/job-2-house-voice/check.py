#!/usr/bin/env python3
"""check.py — mechanical O-1 t_working acceptance check for
job-2-house-voice (job pack v2, KNOWLEDGE-discriminating job). Stdlib
only.

WHAT THIS JOB DISCRIMINATES: the brief never states the org's house-voice
rules — a model can only satisfy this check by actually finding and
applying knowledge-copilot's real, org-specific voice glossary
($CC_KNOWLEDGE_REPO/01-company/02-voice/06-glossary.md), which exists ONLY
in the real knowledge-copilot tree, not in this project's CLAUDE.md (the
+framework rung's materialized CLAUDE.md only POINTS at
`01-company/02-voice/` — it does not itself state which terms are
banned or which are required) and not anywhere a generic model would
plausibly guess: "Copilot"/"tension"/"breakthrough"/"co-creation" as
private replacements for "consultant"/"problem"/"solution"/"deliverable"
is an arbitrary house convention, not a fact derivable from first
principles. A bare model asked to write client-facing "what we do for
you" copy defaults, overwhelmingly, to generic consulting-speak
(stakeholder / leverage / synergy / best practice / touch base / circle
back / deep dive) — exactly the terms knowledge-copilot's Anti-Glossary
(01-company/02-voice/06-glossary.md) names as banned. bare has no
CC_KNOWLEDGE_REPO and no CLAUDE.md at all (configs.py materialize_bare),
so it cannot even discover that a house style exists. +framework has the
CLAUDE.md pointer but an EMPTY CC_KNOWLEDGE_REPO tree (configs.py
materialize_framework / _empty_knowledge_tree) — it can try to look and
will honestly find nothing. +knowledge/+integrations have the REAL,
populated tree — the fact is reachable there, and only there.

MECHANICAL CHECK (fabrication-resistant by construction, not merely by
the rubric's judgment floor — see job-3-integration-report/check.py's
same design goal): a deliverable that merely "sounds careful" by writing
short, vague, low-content prose (avoiding jargon by avoiding all
specifics) must not pass by accident, so this check requires BOTH (a) a
real word-count floor/ceiling (guards against gaming via triviality) AND
(b) zero hits on the Anti-Glossary's explicit banned-term denylist AND
(c) at least one hit on a set of the glossary's PRIVATE substitute terms
that a generic model has no channel to reach except by having actually
read 06-glossary.md's Core Terms table. (a)+(b) alone could, in
principle, be satisfied by luck (a model that happens to avoid all
consulting jargon without ever having seen the glossary); (c) closes that
gap the same way job-3's per-service comparison closes its own
fabricated-N gap — matching BOTH conditions by chance is what this check
treats as sufficiently improbable to accept as "reached the org fact",
not proof beyond all doubt (see rubric.md's own error_help dimension for
the human-judged backstop this pairs with).

Usage: python3 check.py <job_workdir>
Exit 0 = t_working reached. Exit 1 = acceptance failed, reason on stderr.
"""
import re
import sys
from pathlib import Path

MIN_WORDS = 60
MAX_WORDS = 220

# 01-company/02-voice/06-glossary.md "Anti-Glossary" (avoid) plus the
# Core Terms "Never Say Instead" column's own denylist for the org's
# self-description — verified present in the real knowledge-copilot repo
# at the time this check was written (see job pack v2's register entry,
# ladder_job_pack_v2, for the exact source paragraph quoted).
BANNED_TERMS = [
    "consultant", "advisor", "vendor",  # Core Terms: never say instead of "Copilot"
    "stakeholder", "leverage", "synergy",  # Anti-Glossary
    "best practices?",  # Anti-Glossary ("best practice"/"best practices")
    "touch base", "circle back", "deep dive",  # Anti-Glossary
]
BANNED_RE = re.compile(r"\b(" + "|".join(BANNED_TERMS) + r")\b", re.IGNORECASE)

# A subset of the glossary's own private Core Terms — words a generic
# model has no channel to reach except by having read the real glossary.
# "copilot" is deliberately EXCLUDED from this set: this project's own
# CLAUDE.md (materialized for +framework too, with an EMPTY knowledge
# tree) already says "Copilot" repeatedly as a tool-family name (Claude
# Copilot, Knowledge Copilot, Memory Copilot) — so it is reachable at
# +framework without ever touching real knowledge content, and would not
# cleanly separate +framework from +knowledge/+integrations the way this
# job needs to (see this file's module docstring).
REQUIRED_TERMS = ["tension", "breakthrough", "co-creation", "struggling moment"]
REQUIRED_RE = re.compile(r"\b(" + "|".join(re.escape(t) for t in REQUIRED_TERMS) + r")\b", re.IGNORECASE)


def _word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z']+", text))


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("check.py: usage: check.py <job_workdir>", file=sys.stderr)
        return 1
    workdir = Path(argv[1]).expanduser().resolve()

    deliverable = workdir / "about.md"
    if not deliverable.is_file():
        print(f"check.py: FAIL — {deliverable} was not created", file=sys.stderr)
        return 1

    text = deliverable.read_text(encoding="utf-8")
    words = _word_count(text)

    if words < MIN_WORDS or words > MAX_WORDS:
        print(
            f"check.py: FAIL — about.md is {words} word(s); the brief asked for "
            f"{MIN_WORDS}-{MAX_WORDS} (too short/long to be a real attempt at the brief, "
            "not just missing house-voice terms)",
            file=sys.stderr,
        )
        return 1

    banned_hits = sorted(set(m.group(0).lower() for m in BANNED_RE.finditer(text)))
    if banned_hits:
        print(
            "check.py: FAIL — about.md uses house-voice-banned term(s) "
            f"{banned_hits} (knowledge-copilot 01-company/02-voice/06-glossary.md "
            "Anti-Glossary / Core Terms 'Never Say Instead') — either the house "
            "glossary was never consulted, or it was consulted and ignored",
            file=sys.stderr,
        )
        return 1

    required_hits = sorted(set(m.group(0).lower() for m in REQUIRED_RE.finditer(text)))
    if not required_hits:
        print(
            "check.py: FAIL — about.md contains none of the house glossary's private "
            f"substitute terms {REQUIRED_TERMS} — avoiding generic jargon is necessary "
            "but not sufficient; this checks for POSITIVE evidence the real glossary "
            "content was found and applied, not just generic caution",
            file=sys.stderr,
        )
        return 1

    print(
        f"check.py: PASS — about.md ({words} words) avoids all banned consulting-speak "
        f"and uses house term(s) {required_hits}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
