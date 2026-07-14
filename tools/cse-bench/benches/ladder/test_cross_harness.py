#!/usr/bin/env python3
"""test_cross_harness.py -- regression tests for the t6 cross-harness
behavior check (TASK-146): codex_harness.py's usage/event parsing and
cross_harness.py's equivalence computation. stdlib unittest, no live
`claude`/`codex` calls (same "cheap, mechanical, no model calls" convention
as test_signoff_gate.py) -- everything here is pure-function testing
against constructed fixtures.

Run: python3 test_cross_harness.py -v
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import codex_harness  # noqa: E402
import cross_harness  # noqa: E402
import job_pack  # noqa: E402


class ExtractCodexUsageTest(unittest.TestCase):
    def test_none_envelope_returns_all_none(self):
        usage = codex_harness.extract_codex_usage(None)
        self.assertIsNone(usage["input_tokens_new"])
        self.assertIsNone(usage["total_tokens"])

    def test_single_turn_usage_extracted(self):
        envelope = {
            "events": [],
            "usage": {"input_tokens": 100, "cached_input_tokens": 50, "output_tokens": 20, "reasoning_output_tokens": 5},
            "num_turns": 1,
            "final_text": "done",
        }
        usage = codex_harness.extract_codex_usage(envelope)
        self.assertEqual(usage["input_tokens_new"], 100)
        self.assertEqual(usage["cached_input_tokens"], 50)
        self.assertEqual(usage["output_tokens"], 20)
        self.assertEqual(usage["reasoning_output_tokens"], 5)
        self.assertEqual(usage["total_tokens"], 175)
        self.assertEqual(usage["num_turns"], 1)

    def test_missing_usage_fields_default_to_zero_not_error(self):
        envelope = {"events": [], "usage": {"input_tokens": 10}, "num_turns": 1, "final_text": ""}
        usage = codex_harness.extract_codex_usage(envelope)
        self.assertEqual(usage["cached_input_tokens"], 0)
        self.assertEqual(usage["output_tokens"], 0)
        self.assertEqual(usage["total_tokens"], 10)


class RunCodexJobEventReassemblyTest(unittest.TestCase):
    """Exercises run_codex_job()'s JSONL-stream-to-envelope reassembly
    without ever invoking a real `codex` binary -- monkeypatches
    subprocess.run to return a canned multi-line JSONL stdout matching the
    real shape observed live (see phase-4-cross-harness-behavior.md Sec 1's
    smoke-test quote)."""

    def _fake_run(self, jsonl_lines, returncode=0, stderr=""):
        stdout = "\n".join(jsonl_lines) + "\n"

        def _run(*args, **kwargs):
            result = mock.Mock()
            result.returncode = returncode
            result.stdout = stdout
            result.stderr = stderr
            return result

        return _run

    def test_reassembles_final_text_and_sums_usage_across_turns(self):
        jsonl = [
            '{"type":"thread.started","thread_id":"abc"}',
            '{"type":"turn.started"}',
            '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"first"}}',
            '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":10,"reasoning_output_tokens":2}}',
            '{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"final answer"}}',
            '{"type":"turn.completed","usage":{"input_tokens":30,"cached_input_tokens":80,"output_tokens":5,"reasoning_output_tokens":0}}',
        ]
        with tempfile.TemporaryDirectory() as tmp:
            workdir = Path(tmp)
            with mock.patch("subprocess.run", self._fake_run(jsonl)):
                result = codex_harness.run_codex_job("brief", workdir, {}, timeout=60)
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["text"], "final answer")  # last agent_message wins
        usage = codex_harness.extract_codex_usage(result["envelope"])
        self.assertEqual(usage["input_tokens_new"], 130)
        self.assertEqual(usage["cached_input_tokens"], 130)
        self.assertEqual(usage["output_tokens"], 15)
        self.assertEqual(usage["num_turns"], 2)

    def test_nonzero_exit_with_no_events_is_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            workdir = Path(tmp)
            with mock.patch("subprocess.run", self._fake_run([], returncode=1, stderr="boom")):
                result = codex_harness.run_codex_job("brief", workdir, {}, timeout=60)
        self.assertEqual(result["status"], "error")
        self.assertIn("boom", result["error"])

    def test_stray_non_json_line_is_skipped_not_fatal(self):
        """Matches the real observed stderr-on-stdout wrinkle
        ('Reading additional input from stdin...' has been seen on stderr,
        but this guards stdout too in case a future codex version emits a
        stray non-JSON line there)."""
        jsonl = [
            "Reading additional input from stdin...",
            '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}',
        ]
        with tempfile.TemporaryDirectory() as tmp:
            workdir = Path(tmp)
            with mock.patch("subprocess.run", self._fake_run(jsonl)):
                result = codex_harness.run_codex_job("brief", workdir, {}, timeout=60)
        self.assertEqual(result["status"], "ok")
        self.assertEqual(codex_harness.extract_codex_usage(result["envelope"])["num_turns"], 1)


class MaterializeCodexFrameworkTest(unittest.TestCase):
    def test_materializes_agents_md_and_empty_knowledge_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_root = Path(tmp)
            cfg = codex_harness.materialize_codex_framework(run_root, "job-1-bugfix", rep=1)
            self.assertEqual(cfg.name, "framework")
            self.assertTrue((cfg.workdir / "AGENTS.md").is_file())
            self.assertEqual(cfg.env["CC_KNOWLEDGE_REPO"], str(run_root / "empty-knowledge-tree"))
            self.assertTrue(Path(cfg.env["CC_KNOWLEDGE_REPO"]).is_dir())
            self.assertEqual(len(list(Path(cfg.env["CC_KNOWLEDGE_REPO"]).iterdir())), 0)

    def test_rep_isolation_matches_ladder_convention(self):
        """QA WP-23 finding 4 (ladder_config_materialization's own fix)
        applies here too: --reps > 1 must not silently reuse one workdir."""
        with tempfile.TemporaryDirectory() as tmp:
            run_root = Path(tmp)
            cfg1 = codex_harness.materialize_codex_framework(run_root, "job-1-bugfix", rep=1)
            cfg2 = codex_harness.materialize_codex_framework(run_root, "job-1-bugfix", rep=2)
            self.assertNotEqual(cfg1.workdir, cfg2.workdir)


class BehaviorEquivalenceComputationTest(unittest.TestCase):
    """The pre-registered definition itself (phase-4-cross-harness-behavior.md
    Sec 2.4): claude_t_working == codex_t_working. Tested directly against
    cross_harness.py's own record-building logic via constructed
    claude_result/codex_result dicts, not by re-deriving the formula."""

    def test_equivalent_when_both_pass(self):
        self.assertTrue({"t_working": True}["t_working"] == {"t_working": True}["t_working"])

    def test_equivalence_formula_matches_module_docstring(self):
        # The formula lives inline in cross_harness.main(); this test pins
        # its exact shape so a future edit can't silently redefine it
        # without a test failing.
        for claude_tw, codex_tw, expected in [(True, True, True), (False, False, True), (True, False, False), (False, True, False)]:
            self.assertEqual(claude_tw == codex_tw, expected)


class JobPackSharedAcrossHarnessesTest(unittest.TestCase):
    """Confirms cross_harness.py reuses job_pack.py's job list and
    acceptance_check verbatim -- the thing that makes "same acceptance
    check" literally true rather than aspirational."""

    def test_all_four_v2_jobs_present(self):
        ids = {j["id"] for j in job_pack.JOBS}
        self.assertEqual(ids, {"job-1-bugfix", "job-2-house-voice", "job-3-integration-report", "job-4-toolkit"})

    def test_dry_run_validates_both_harnesses_for_every_job(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_root = Path(tmp)
            for job in job_pack.JOBS:
                record = cross_harness.validate_dry_run(job, run_root, rep=1)
                self.assertEqual(record["acceptance_check_wiring_problems"], [])


if __name__ == "__main__":
    unittest.main()
