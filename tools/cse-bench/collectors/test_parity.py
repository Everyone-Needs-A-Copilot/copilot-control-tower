#!/usr/bin/env python3
"""test_parity.py — regression test for collectors/parity.py's
_detect_content_flag() (found while closing t6-two-harnesses-one-behavior,
2026-07-14).

stdlib `unittest`, not pytest, matching the convention set by
benches/ladder/test_signoff_gate.py (this machine's default python3 has no
pytest importable outside the uv-managed dev extras this collector doesn't
need).

Run: python3 test_parity.py
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from collectors import parity  # noqa: E402


# A real capture of check-upstream-parity.py's --help output (2026-07-14),
# reproducing the exact shape that broke the original heuristic: the usage
# summary line lists '--json' before '--content' on one wrapped line, and
# '--update-baseline's own description mentions the word "content" too.
REAL_HELP_TEXT = """usage: check-upstream-parity.py [-h] [--upstream UPSTREAM] [--require]
                                [--json] [--content] [--update-baseline]
                                [--baseline BASELINE]

options:
  -h, --help           show this help message and exit
  --upstream UPSTREAM
  --require
  --json
  --content            Also run content-level hash parity against the
                       committed content baseline
  --update-baseline    Regenerate the content baseline manifest from the
                       current upstream checkout and exit
  --baseline BASELINE  Override the content baseline manifest path (default:
                       parity/upstream-content-hashes.json)
"""


class DetectContentFlagTests(unittest.TestCase):
    def test_real_help_text_resolves_to_content_not_json(self):
        """The regression this test exists to catch: the old regex matched
        '--json' (the first flag on the shared usage-summary line) instead
        of '--content' (the flag that actually enables content parity)."""
        flag = parity._detect_content_flag(REAL_HELP_TEXT)
        self.assertEqual(flag, "--content")

    def test_no_content_or_hash_mention_returns_none(self):
        help_text = "usage: foo.py [--bar]\n\noptions:\n  --bar   does something unrelated\n"
        self.assertIsNone(parity._detect_content_flag(help_text))

    def test_usage_summary_alone_without_options_definition_does_not_match(self):
        """A flag merely NAMED on the usage line (not defined in the
        options list) must not match on that line alone -- only a line
        that itself STARTS with the flag (an options-list definition)
        counts."""
        help_text = "usage: foo.py [--json] [--content-hash]\n\noptions:\n  --json   plain json output\n"
        self.assertIsNone(parity._detect_content_flag(help_text))

    def test_hash_keyword_also_matches(self):
        help_text = "options:\n  --hash-check          Run hash-level parity\n"
        self.assertEqual(parity._detect_content_flag(help_text), "--hash-check")


if __name__ == "__main__":
    unittest.main()
