#!/usr/bin/env python3
"""
check_claims.py — structural validator for
docs/40-initiatives/01-cse-auditability/claims.yaml (TASK-85 / B-2).

WHY: claims.yaml is the CSE Verification & Benchmark Program's V-2
pre-registration mechanism (see the header comment in claims.yaml and
docs/40-initiatives/01-cse-auditability/README.md, "Validation Contract
V-2"). A pre-registration register that nobody validates is a wish, not a
rule — this script is the mechanical check the initiative's own house
style demands ("a rule that isn't checked mechanically, and checked on
every commit, is not a rule").

WHAT IT VALIDATES (structural only — it does not re-run each claim's
`check` command; that stays a human/CI concern per claim):
  - `definitions` is a mapping, `claims` is a list.
  - every claim has a unique, non-empty `id`.
  - every claim has non-empty `statement`, `check`, `status`.
  - every claim's `definition_refs` (if present) is a list, and every
    entry in it resolves to a key under `definitions`.
  - `status` is one of the closed enum: passing, failing, unchecked, gated,
    retired-by-unverifiability, retired-by-ratification, retired-by-deletion.
    The three `retired-by-*` values (added 2026-07-14, closing DEC-10's
    blocked patch -- its ruling to retire `turn-definition-incompatible-
    with-april` could not actually be applied against the old 4-value enum)
    are for claims the register keeps on record but no longer scores as an
    open pass/fail: unverifiability (the check can never be re-run again,
    e.g. a lost script -- DEC-10), ratification (an owner-ratified doc
    correction supersedes what the claim was falsifying -- DEC-3), or
    scope-removed (the surface the claim was about no longer exists, e.g. a
    cut service/product). Retiring a claim never retires the underlying
    finding -- see each retired claim's own `evidence` field, which stays
    in place.
  - `last_checked` is present and looks like an ISO date (YYYY-MM-DD)
    whenever `status` != "unchecked".

YAML LOADING: prefers PyYAML (`import yaml`) when importable — the common
case on this machine. Falls back to a small, strict, hand-rolled parser
(_fallback_yaml.py-equivalent, inlined below) when PyYAML is not
available, so this script has zero hard third-party dependencies. The
fallback supports exactly the YAML subset claims.yaml actually uses: block
mappings, one flavor of block sequence (flat mappings written
`- key: value` with continuation keys), flow sequences (`[a, b]`), quoted
and bare scalars, and folded/literal block scalars (`>`, `>-`, `|`, `|-`).
It is NOT a general-purpose YAML parser — do not point it at arbitrary
YAML files.

Usage:
    tools/cse-bench/check_claims.py [PATH]   # PATH defaults to the
                                              # register's canonical location

Exit status: 0 with a one-line summary on success; 1 with every violation
listed on failure.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CLAIMS_PATH = (
    REPO_ROOT / "docs" / "40-initiatives" / "01-cse-auditability" / "claims.yaml"
)

STATUS_ENUM = {
    "passing",
    "failing",
    "unchecked",
    "gated",
    "retired-by-unverifiability",
    "retired-by-ratification",
    "retired-by-deletion",
}
_ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


# ---------------------------------------------------------------------------
# YAML loading — PyYAML if importable, else the vendored strict-subset
# fallback parser below.
# ---------------------------------------------------------------------------


def load_yaml(text: str) -> Any:
    try:
        import yaml  # type: ignore
    except ImportError:
        return _fallback_load(text)
    return yaml.safe_load(text)


class YamlSubsetError(Exception):
    """Raised by the vendored fallback parser on YAML it can't handle."""


def _fallback_load(text: str) -> Any:
    """Entry point for the vendored strict-subset loader."""
    lines = text.split("\n")
    parser = _SubsetParser(lines)
    result = parser.parse_top_level()
    return result


def _strip_comment(s: str) -> str:
    """Remove a trailing '# comment', but only an UNQUOTED one, and only
    when preceded by whitespace or at start of string (YAML's own rule for
    what counts as a comment marker)."""
    in_dquote = False
    in_squote = False
    i = 0
    n = len(s)
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
    items = [p.strip() for p in inner.split(",")]
    return [_parse_scalar(p) for p in items]


class _SubsetParser:
    """Indentation-driven recursive-descent parser for the restricted YAML
    subset claims.yaml uses. See module docstring for exactly what's
    supported."""

    def __init__(self, lines: list[str]):
        self.lines = lines
        self.i = 0
        self.n = len(lines)

    # -- line-level helpers -------------------------------------------------

    def _peek_content_index(self) -> int | None:
        """Index of the next non-blank, non-comment-only line, or None."""
        j = self.i
        while j < self.n:
            raw = self.lines[j]
            stripped = raw.strip()
            if stripped == "" or stripped.startswith("#"):
                j += 1
                continue
            return j
        return None

    # -- top level ------------------------------------------------------

    def parse_top_level(self) -> dict:
        j = self._peek_content_index()
        if j is None:
            return {}
        self.i = j
        indent = _indent_of(self.lines[j])
        return self.parse_mapping(indent)

    # -- mapping / sequence / scalar dispatch ---------------------------

    def parse_block(self, min_indent: int) -> Any:
        """Parse whatever comes next (mapping or sequence) at an indent
        >= min_indent. Returns None if nothing qualifies (a null value)."""
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
            ind = _indent_of(line)
            if ind != indent:
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
            ind = _indent_of(line)
            if ind != indent:
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
                # Inline "- key: value" — start of a flat mapping whose
                # continuation keys are indented to align under `body`.
                key, rest = m.group(1), m.group(2).strip()
                mapping: dict[str, Any] = {key: self._parse_value(rest, key_indent=item_indent, key_line_idx=j)}
                continuation = self.parse_mapping(item_indent)
                mapping.update(continuation)
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
        while True:
            if self.i >= self.n:
                break
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
        # Drop leading/trailing blank lines from the collected block.
        while collected and collected[0] == "":
            collected.pop(0)
        while collected and collected[-1] == "":
            collected.pop()
        if folded:
            return " ".join(c for c in collected if c != "").strip()
        return "\n".join(collected)


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------


def validate(data: Any) -> list[str]:
    errors: list[str] = []

    if not isinstance(data, dict):
        return ["root of claims.yaml must be a mapping with 'definitions' and 'claims' keys"]

    definitions = data.get("definitions")
    if definitions is None:
        errors.append("missing top-level 'definitions' key")
        definitions = {}
    elif not isinstance(definitions, dict):
        errors.append("'definitions' must be a mapping")
        definitions = {}

    claims = data.get("claims")
    if claims is None:
        errors.append("missing top-level 'claims' key")
        return errors
    if not isinstance(claims, list):
        errors.append("'claims' must be a list")
        return errors
    if len(claims) == 0:
        errors.append("'claims' is empty — a register with no claims validates nothing")

    seen_ids: set[str] = set()
    for idx, claim in enumerate(claims):
        loc = f"claims[{idx}]"
        if not isinstance(claim, dict):
            errors.append(f"{loc}: not a mapping")
            continue

        cid = claim.get("id")
        if not cid or not isinstance(cid, str):
            errors.append(f"{loc}: missing or empty required field 'id'")
        else:
            loc = f"claims[id={cid}]"
            if cid in seen_ids:
                errors.append(f"{loc}: duplicate id '{cid}' — every claim id must be unique")
            seen_ids.add(cid)

        for field in ("statement", "check", "status"):
            val = claim.get(field)
            if not val or not isinstance(val, str):
                errors.append(f"{loc}: missing or empty required field '{field}'")

        refs = claim.get("definition_refs", [])
        if refs is None:
            refs = []
        if not isinstance(refs, list):
            errors.append(f"{loc}: 'definition_refs' must be a list")
        else:
            for ref in refs:
                if ref not in definitions:
                    errors.append(
                        f"{loc}: definition_ref '{ref}' does not resolve to any key under 'definitions'"
                    )

        status = claim.get("status")
        if status is not None and status not in STATUS_ENUM:
            errors.append(
                f"{loc}: status '{status}' is not in the closed enum {sorted(STATUS_ENUM)}"
            )

        last_checked = claim.get("last_checked")
        if status is not None and status != "unchecked":
            if not last_checked:
                errors.append(
                    f"{loc}: status is '{status}' but 'last_checked' is missing "
                    "(required whenever status != unchecked)"
                )
        if last_checked is not None and not _ISO_DATE_RE.match(str(last_checked)):
            errors.append(f"{loc}: last_checked '{last_checked}' is not an ISO date (YYYY-MM-DD)")

        if not claim.get("evidence"):
            errors.append(f"{loc}: missing or empty required field 'evidence'")

    return errors


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT_CLAIMS_PATH

    if not path.exists():
        print(f"check_claims.py: {path} not found", file=sys.stderr)
        return 1

    text = path.read_text()

    try:
        data = load_yaml(text)
    except Exception as exc:  # noqa: BLE001 — surface any parse failure, fallback or PyYAML
        print(f"check_claims.py: failed to parse {path}: {exc}", file=sys.stderr)
        return 1

    errors = validate(data)

    try:
        rel = path.relative_to(REPO_ROOT)
    except ValueError:
        rel = path

    if errors:
        print(f"check_claims.py: {len(errors)} violation(s) in {rel}:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    n_claims = len(data.get("claims", []))
    n_defs = len(data.get("definitions", {}))
    print(f"check_claims.py: OK — {rel}: {n_claims} claim(s), {n_defs} definition(s), 0 violations.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
