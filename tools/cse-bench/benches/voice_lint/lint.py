#!/usr/bin/env python3
"""lint.py -- deterministic voice-conformance linter (TASK-93 / B-10).

Checks a block of text against the rubric compiled in rules.yaml (banned
words per category, em-dash count, terminology-substitution violations,
sentence-rhythm violations, Flesch-Kincaid grade) and reports violation
counts per category, violations per 100 words, and the FK grade with an
in-band (6-8) check.

This is a NEGATIVE-SPACE linter: it proves the text does not contain the
things the rubric forbids. It says nothing about whether the text is
GOOD copy -- see README.md's "necessary, not sufficient" caveat.

USAGE
    lint.py <file>              # lint a file
    lint.py                     # lint stdin
    lint.py <file> --json       # machine-readable output (default: human-readable)
    lint.py <file> --rules PATH # override rules.yaml location

FLESCH-KINCAID GRADE FORMULA
    FK Grade = 0.39 * (total_words / total_sentences)
             + 11.8 * (total_syllables / total_words)
             - 15.59
    This is the standard published Flesch-Kincaid Grade Level formula
    (Kincaid et al. 1975).

SYLLABLE HEURISTIC (stdlib, no dictionary/CMU-pronouncing-lookup)
    Per word: lowercase, strip non-letters, then count VOWEL-GROUP
    transitions (a run of one or more of a/e/i/o/u/y counts as one
    syllable seed). Two orthography adjustments are applied on top of
    that raw count, matching the widely-used stdlib syllable-count
    heuristic this implementation follows:
      - a trailing silent 'e' is dropped (count -= 1), e.g. "like" ->
        raw 2 ("i", "e") -> 1.
      - a trailing "-le" preceded by a consonant gets ONE BACK, e.g.
        "table" -> raw groups "a","e" = 2, silent-e rule would drop to
        1, but "-le" is pronounced as its own syllable ("ta-ble") so it
        is restored to 2.
      - every word is floored at 1 syllable (handles "the", single-vowel
        words, and heuristic underflow to 0).
    This is an APPROXIMATION. It will misfire on some contractions,
    proper nouns, and irregular spellings -- documented here rather than
    silently trusted; it is deterministic and dependency-free, which is
    what this bench needs (identical grade for identical text, every run,
    on every machine, no NLTK/pyphen install).

YAML LOADING: prefers PyYAML (`import yaml`) when importable (confirmed
present on this machine). Falls back to a small vendored strict-subset
parser (same restricted grammar as ../../check_claims.py's own fallback:
block mappings, block sequences of scalars, flat-mapping block sequences
`- key: value` + continuation keys, flow sequences `[a, b]`, quoted/bare
scalars, and folded block scalars `>`/`>-`) -- duplicated here rather
than imported from check_claims.py so this bench stays fully
self-contained under benches/voice_lint/ per its ownership boundary (see
README.md). The fallback is a defensive path, not the primary-tested
one; PyYAML is what this bench actually runs against.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_RULES_PATH = SCRIPT_DIR / "rules.yaml"

EM_DASH = "—"

WORD_RE = re.compile(r"[A-Za-z']+")
_VOWEL_GROUP_RE = re.compile(r"[aeiouy]+")
_SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")


# ---------------------------------------------------------------------------
# YAML loading -- PyYAML if importable, else the vendored strict-subset
# fallback parser (see module docstring).
# ---------------------------------------------------------------------------


def load_yaml(text: str) -> Any:
    try:
        import yaml  # type: ignore

        return yaml.safe_load(text)
    except ImportError:
        return _fallback_load(text)


class YamlSubsetError(Exception):
    """Raised by the vendored fallback parser on YAML it can't handle."""


def _fallback_load(text: str) -> Any:
    lines = text.split("\n")
    return _SubsetParser(lines).parse_top_level()


def _strip_comment(s: str) -> str:
    in_dquote = in_squote = False
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if in_dquote:
            if c == "\\" and i + 1 < n:
                i += 2
                continue
            if c == '"':
                in_dquote = False
            i += 1
            continue
        if in_squote:
            if c == "'":
                in_squote = False
            i += 1
            continue
        if c == '"':
            in_dquote = True
            i += 1
            continue
        if c == "'":
            in_squote = True
            i += 1
            continue
        if c == "#" and (i == 0 or s[i - 1] in " \t"):
            return s[:i]
        i += 1
    return s


def _indent_of(line: str) -> int:
    if "\t" in line[: len(line) - len(line.lstrip(" "))]:
        raise YamlSubsetError("tabs are not supported for indentation")
    return len(line) - len(line.lstrip(" "))


_KEY_RE = re.compile(r'^([A-Za-z_][\w-]*):\s*(.*)$')


def _parse_scalar(tok: str) -> Any:
    tok = tok.strip()
    if tok == "":
        return None
    if tok in ("null", "~", "Null", "NULL"):
        return None
    if tok in ("true", "True", "TRUE"):
        return True
    if tok in ("false", "False", "FALSE"):
        return False
    if len(tok) >= 2 and tok.startswith('"') and tok.endswith('"'):
        inner = tok[1:-1]
        return inner.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
    if len(tok) >= 2 and tok.startswith("'") and tok.endswith("'"):
        return tok[1:-1].replace("''", "'")
    if re.fullmatch(r"-?\d+", tok):
        return int(tok)
    if re.fullmatch(r"-?\d+\.\d+", tok):
        return float(tok)
    return tok


def _parse_flow_sequence(tok: str) -> list:
    tok = tok.strip()
    if not (tok.startswith("[") and tok.endswith("]")):
        raise YamlSubsetError(f"expected a flow sequence like [a, b]; got: {tok!r}")
    inner = tok[1:-1].strip()
    if inner == "":
        return []
    return [_parse_scalar(p.strip()) for p in inner.split(",")]


class _SubsetParser:
    def __init__(self, lines: list[str]):
        self.lines = lines
        self.i = 0
        self.n = len(lines)

    def _peek_content_index(self) -> int | None:
        j = self.i
        while j < self.n:
            stripped = self.lines[j].strip()
            if stripped == "" or stripped.startswith("#"):
                j += 1
                continue
            return j
        return None

    def parse_top_level(self) -> dict:
        j = self._peek_content_index()
        if j is None:
            return {}
        self.i = j
        return self.parse_mapping(_indent_of(self.lines[j]))

    def parse_block(self, min_indent: int) -> Any:
        j = self._peek_content_index()
        if j is None:
            return None
        self.i = j
        indent = _indent_of(self.lines[j])
        if indent < min_indent:
            return None
        content = _strip_comment(self.lines[j]).strip()
        if content.startswith("- ") or content == "-":
            return self.parse_sequence(indent)
        return self.parse_mapping(indent)

    def parse_mapping(self, indent: int) -> dict:
        result: dict[str, Any] = {}
        while True:
            j = self._peek_content_index()
            if j is None:
                break
            line = self.lines[j]
            if _indent_of(line) != indent:
                break
            content = _strip_comment(line).strip()
            if content.startswith("- "):
                break
            m = _KEY_RE.match(content)
            if not m:
                raise YamlSubsetError(f"line {j + 1}: expected 'key: value', got: {content!r}")
            key, rest = m.group(1), m.group(2).strip()
            self.i = j + 1
            result[key] = self._parse_value(rest, key_indent=indent, key_line_idx=j)
        return result

    def parse_sequence(self, indent: int) -> list:
        items: list[Any] = []
        while True:
            j = self._peek_content_index()
            if j is None:
                break
            line = self.lines[j]
            if _indent_of(line) != indent:
                break
            content = _strip_comment(line).strip()
            if not (content.startswith("- ") or content == "-"):
                break
            self.i = j + 1
            body = content[1:].lstrip() if content != "-" else ""
            dash_col = len(line) - len(line.lstrip(" "))
            item_indent = dash_col + (len(content) - len(content[1:].lstrip()))
            if body == "":
                items.append(self.parse_block(indent + 1))
                continue
            m = _KEY_RE.match(body)
            if m:
                key, rest = m.group(1), m.group(2).strip()
                mapping: dict[str, Any] = {key: self._parse_value(rest, key_indent=item_indent, key_line_idx=j)}
                mapping.update(self.parse_mapping(item_indent))
                items.append(mapping)
            else:
                items.append(_parse_scalar(body))
        return items

    def _parse_value(self, rest: str, key_indent: int, key_line_idx: int) -> Any:
        if rest == "":
            return self.parse_block(key_indent + 1)
        if rest.startswith("["):
            return _parse_flow_sequence(rest)
        if rest in (">", ">-", "|", "|-"):
            return self._parse_block_scalar(rest, key_indent, key_line_idx)
        return _parse_scalar(rest)

    def _parse_block_scalar(self, indicator: str, key_indent: int, key_line_idx: int) -> str:
        folded = indicator.startswith(">")
        collected: list[str] = []
        while self.i < self.n:
            raw = self.lines[self.i]
            if raw.strip() == "":
                collected.append("")
                self.i += 1
                continue
            ind = _indent_of(raw)
            if ind <= key_indent:
                break
            collected.append(raw[ind:].rstrip())
            self.i += 1
        while collected and collected[0] == "":
            collected.pop(0)
        while collected and collected[-1] == "":
            collected.pop()
        if folded:
            return " ".join(c for c in collected if c != "").strip()
        return "\n".join(collected)


def load_rules(path: Path) -> dict:
    return load_yaml(path.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Tokenization / readability primitives
# ---------------------------------------------------------------------------


def count_words(text: str) -> int:
    return len(WORD_RE.findall(text))


def split_sentences(text: str) -> list[str]:
    normalized = re.sub(r"\s+", " ", text).strip()
    if not normalized:
        return []
    parts = _SENTENCE_SPLIT_RE.split(normalized)
    return [p.strip() for p in parts if p.strip()]


def count_syllables(word: str) -> int:
    """Vowel-group heuristic. See module docstring for the exact rules."""
    w = re.sub(r"[^a-z]", "", word.lower())
    if not w:
        return 0
    groups = _VOWEL_GROUP_RE.findall(w)
    count = len(groups)
    if w.endswith("e") and count > 1:
        count -= 1
    if w.endswith("le") and len(w) > 2 and w[-3] not in "aeiouy":
        count += 1
    return max(count, 1)


def flesch_kincaid_grade(text: str) -> dict:
    sentences = split_sentences(text)
    words = WORD_RE.findall(text)
    n_sentences = len(sentences)
    n_words = len(words)
    n_syllables = sum(count_syllables(w) for w in words)

    if n_sentences == 0 or n_words == 0:
        return {
            "grade": None,
            "in_band_6_8": None,
            "words": n_words,
            "sentences": n_sentences,
            "syllables": n_syllables,
            "note": "not enough text to compute a grade (need >=1 sentence and >=1 word)",
        }

    grade = 0.39 * (n_words / n_sentences) + 11.8 * (n_syllables / n_words) - 15.59
    return {
        "grade": round(grade, 2),
        "in_band_6_8": 6.0 <= grade <= 8.0,
        "words": n_words,
        "sentences": n_sentences,
        "syllables": n_syllables,
    }


# ---------------------------------------------------------------------------
# Rule checks
# ---------------------------------------------------------------------------


def _phrase_regex(phrase: str) -> re.Pattern:
    words = phrase.split()
    pattern = r"\b" + r"\s+".join(re.escape(w) for w in words) + r"\b"
    return re.compile(pattern, re.IGNORECASE)


def check_banned_category(text: str, terms: list[str]) -> dict:
    hits = []
    total = 0
    for term in terms:
        n = len(_phrase_regex(term).findall(text))
        if n:
            hits.append({"term": term, "count": n})
            total += n
    hits.sort(key=lambda h: (-h["count"], h["term"]))
    return {"count": total, "hits": hits}


def check_em_dash(text: str) -> dict:
    return {"count": text.count(EM_DASH)}


def check_terminology(text: str, entries: list[dict]) -> dict:
    hits = []
    total = 0
    for entry in entries:
        avoid_terms = entry.get("avoid", [])
        entry_count = 0
        matched_terms = []
        for term in avoid_terms:
            n = len(_phrase_regex(term).findall(text))
            if n:
                entry_count += n
                matched_terms.append({"term": term, "count": n})
        if entry_count:
            hits.append(
                {
                    "avoid_terms_matched": matched_terms,
                    "use_instead": entry.get("use"),
                    "count": entry_count,
                    "source": entry.get("source"),
                }
            )
            total += entry_count
    hits.sort(key=lambda h: -h["count"])
    return {"count": total, "hits": hits}


def check_rhythm(text: str, threshold_words: int, min_consecutive: int) -> dict:
    sentences = split_sentences(text)
    lengths = [count_words(s) for s in sentences]
    runs = []
    run_start = None
    for idx, n in enumerate(lengths):
        short = n < threshold_words
        if short:
            if run_start is None:
                run_start = idx
        else:
            if run_start is not None and idx - run_start >= min_consecutive:
                runs.append(
                    {
                        "sentence_index_start": run_start,
                        "sentence_index_end": idx - 1,
                        "run_length": idx - run_start,
                    }
                )
            run_start = None
    if run_start is not None and len(lengths) - run_start >= min_consecutive:
        runs.append(
            {
                "sentence_index_start": run_start,
                "sentence_index_end": len(lengths) - 1,
                "run_length": len(lengths) - run_start,
            }
        )
    return {"count": len(runs), "runs": runs}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def lint_text(text: str, rules: dict) -> dict:
    total_words = count_words(text)

    def per_100(n: int) -> float | None:
        return round(n / total_words * 100, 3) if total_words else None

    banned = rules.get("banned_words", {})
    categories: dict[str, dict] = {}
    for cat_name, cat_rule in banned.items():
        result = check_banned_category(text, cat_rule.get("terms", []))
        result["per_100_words"] = per_100(result["count"])
        result["source"] = cat_rule.get("source")
        categories[cat_name] = result

    em_dash_result = check_em_dash(text)
    em_dash_result["per_100_words"] = per_100(em_dash_result["count"])
    em_dash_result["source"] = rules.get("em_dash_ban", {}).get("source")
    categories["em_dash"] = em_dash_result

    terminology_result = check_terminology(text, rules.get("terminology", []))
    terminology_result["per_100_words"] = per_100(terminology_result["count"])
    categories["terminology"] = terminology_result

    rhythm_rule = rules.get("rhythm", {})
    rhythm_result = check_rhythm(
        text,
        threshold_words=rhythm_rule.get("threshold_words", 5),
        min_consecutive=rhythm_rule.get("min_consecutive", 3),
    )
    rhythm_result["per_100_words"] = per_100(rhythm_result["count"])
    rhythm_result["source"] = rhythm_rule.get("source")
    categories["rhythm"] = rhythm_result

    total_violations = sum(c["count"] for c in categories.values())

    fk = flesch_kincaid_grade(text)

    return {
        "word_count": total_words,
        "sentence_count": len(split_sentences(text)),
        "categories": categories,
        "total_violations": total_violations,
        "total_violations_per_100_words": per_100(total_violations),
        "flesch_kincaid": fk,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="lint.py", description="Deterministic voice-conformance linter (TASK-93 / B-10)."
    )
    parser.add_argument(
        "input",
        nargs="?",
        default="-",
        help="Path to a text file to lint, or '-' / omitted to read stdin.",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON (default: human-readable).")
    parser.add_argument(
        "--rules", default=str(DEFAULT_RULES_PATH), help=f"Path to rules.yaml (default: {DEFAULT_RULES_PATH})."
    )
    return parser


def _human_readable(report: dict) -> str:
    lines = [
        f"words={report['word_count']} sentences={report['sentence_count']} "
        f"total_violations={report['total_violations']} "
        f"({report['total_violations_per_100_words']}/100w)",
    ]
    for name, cat in report["categories"].items():
        lines.append(f"  {name}: {cat['count']} ({cat.get('per_100_words')}/100w)")
    fk = report["flesch_kincaid"]
    lines.append(f"  flesch_kincaid_grade: {fk.get('grade')} in_band_6_8={fk.get('in_band_6_8')}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    rules_path = Path(args.rules)
    if not rules_path.exists():
        print(f"lint.py: rules file not found: {rules_path}", file=sys.stderr)
        return 1
    try:
        rules = load_rules(rules_path)
    except Exception as exc:  # noqa: BLE001 -- surface any parse failure, fallback or PyYAML
        print(f"lint.py: failed to parse {rules_path}: {exc}", file=sys.stderr)
        return 1

    if args.input == "-":
        text = sys.stdin.read()
    else:
        input_path = Path(args.input)
        if not input_path.exists():
            print(f"lint.py: input file not found: {input_path}", file=sys.stderr)
            return 1
        text = input_path.read_text(encoding="utf-8")

    report = lint_text(text, rules)

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(_human_readable(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
