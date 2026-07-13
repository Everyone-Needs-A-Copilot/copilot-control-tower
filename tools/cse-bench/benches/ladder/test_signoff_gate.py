#!/usr/bin/env python3
"""test_signoff_gate.py — regression tests for run.py's check_signoff()
(TASK-125 / W-3, QA WP-23 finding 2).

stdlib `unittest`, not pytest — this machine's default python3 has no
pytest importable (verified live, same reason job_pack.py's job pack is a
Python module rather than YAML). Each test writes a throwaway DEC-6-shaped
scratch file (never this repo's real DEC-6) and asserts check_signoff()'s
verdict against it — proving both bypasses QA found are closed, not just
that today's real DEC-6 happens not to trigger them.

Run: python3 test_signoff_gate.py
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run as ladder_run  # noqa: E402


def _write_dec6(tmp_dir: Path, header_lines: list[str], body: str = "\n## 1. Body\n\nSome body text.\n") -> Path:
    """Builds a DEC-6-shaped scratch file: an H1, then the header_lines as
    the leading blockquote (each auto-prefixed with '> ' unless already
    prefixed), then a body section. The body always contains the literal
    instruction text real DEC-6 carries ("...to read `Status: **ratified**`")
    so a passing test proves the header-only scoping still works, not that
    the body happened to be empty."""
    path = tmp_dir / "DEC-6-scratch.md"
    quoted = [line if line.startswith(">") else f"> {line}" for line in header_lines]
    text = (
        "# DEC-6 — scratch test fixture\n\n"
        + "\n".join(quoted)
        + "\n"
        + body
        + "\n## 6. Exact one-line actions\n\n"
        "- edit this file's header line to read `Status: **ratified**`\n"
    )
    path.write_text(text, encoding="utf-8")
    return path


class SignoffGateTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="signoff-gate-test-")
        self.tmp_dir = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def test_missing_file_is_not_ratified(self):
        result = ladder_run.check_signoff(self.tmp_dir / "does-not-exist.md")
        self.assertFalse(result["ratified"])
        self.assertIn("does not exist", result["detail"])

    def test_prepared_not_ratified_is_not_ratified(self):
        path = _write_dec6(self.tmp_dir, ["tc task: TASK-125 · Status: prepared, **not ratified** — owner decides."])
        result = ladder_run.check_signoff(path)
        self.assertFalse(result["ratified"])

    def test_single_ratified_line_is_ratified(self):
        path = _write_dec6(self.tmp_dir, ["tc task: TASK-125 · Status: **ratified** 2026-07-14 — owner signed off."])
        result = ladder_run.check_signoff(path)
        self.assertTrue(result["ratified"], result["detail"])

    def test_html_comment_bypass_is_blocked(self):
        """QA WP-23 finding 2(b): a ratified marker hidden in an HTML
        comment inside the header must NOT count."""
        path = _write_dec6(
            self.tmp_dir,
            [
                "tc task: TASK-125 · Status: prepared, **not ratified** — owner decides.",
                "<!-- Status: **ratified** (do not remove this comment, just testing) -->",
            ],
        )
        result = ladder_run.check_signoff(path)
        self.assertFalse(result["ratified"], result["detail"])

    def test_second_status_line_is_ambiguous_not_ratified(self):
        """QA WP-23 finding 2(a): a second, unrelated 'Status:' line in the
        header must not let a real ratified line (or a coincidentally
        ratified-looking one) slip through — the gate fails CLOSED on
        ambiguity rather than picking either line."""
        path = _write_dec6(
            self.tmp_dir,
            [
                "tc task: TASK-125 · Status: **ratified** — owner signed off.",
                "Related claim (framework-agent-frugality) · Status: failing — unrelated to this memo.",
            ],
        )
        result = ladder_run.check_signoff(path)
        self.assertFalse(result["ratified"], result["detail"])
        self.assertIn("exactly one", result["detail"])

    def test_cross_line_split_no_longer_false_positives(self):
        """Regression for the ORIGINAL bug this file replaced: the old
        regex (`Status:\\s*\\*\\*ratified\\*\\*`) let `\\s*` match a literal
        newline, so a line ending in "Status:" immediately followed by an
        unrelated line starting with "**ratified**" would have matched.
        The per-line STATUS_FIELD_RE search must not reproduce that."""
        path = _write_dec6(
            self.tmp_dir,
            [
                "tc task: TASK-125 · Some other field ends with the word Status:",
                "**ratified** is a bolded word that happens to start this unrelated line.",
            ],
        )
        result = ladder_run.check_signoff(path)
        self.assertFalse(result["ratified"], result["detail"])

    def test_body_text_never_counts_even_without_header_status(self):
        """The header's own explanatory prose (and the '## 6. Exact
        one-line actions' instruction every DEC-N memo carries, which
        literally contains 'Status: **ratified**' as instruction text) must
        never be read as a ratification when the header itself has no
        Status field at all."""
        path = _write_dec6(self.tmp_dir, ["tc task: TASK-125 · no Status field on this line at all."])
        result = ladder_run.check_signoff(path)
        self.assertFalse(result["ratified"], result["detail"])
        self.assertIn("found 0", result["detail"])


if __name__ == "__main__":
    unittest.main()
