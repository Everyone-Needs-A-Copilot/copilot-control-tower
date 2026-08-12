#!/usr/bin/env python3
"""Deterministic semantic negatives for the fleet-census approval gate."""

from __future__ import annotations

import copy
import importlib.util
import json
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {filename}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


validator = load_module("fleet_census_validator", "validate-fleet-census.py")
collector = load_module("fleet_census_collector", "collect-fleet-census.py")


class FleetCensusSemanticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = json.loads(
            (ROOT / "fleet-census.schema.json").read_text(encoding="utf-8")
        )
        cls.report = json.loads(
            (ROOT / "provisional-fleet-census-2026-08-12.json").read_text(
                encoding="utf-8"
            )
        )

    def errors(self, report: dict) -> list[str]:
        return validator.validate(report, self.schema)

    def refresh_identity(self, report: dict) -> None:
        report["census_id"] = validator.census_identity(report)

    def candidate_row(self, report: dict) -> dict:
        return next(
            item
            for item in report["repositories"]
            if item["proposed_operation"]["kind"] == "refresh-after-dependencies"
        )

    def exact_plan(self, row: dict, target: str) -> dict:
        plan = {
            "plan_id": "plan_" + "a" * 32,
            "plan_fingerprint": "sha256:" + "b" * 64,
            "target_paths": [target],
            "binding_id": "",
        }
        plan["binding_id"] = validator.operation_binding(row["repo_identity"], plan)
        return plan

    def test_provisional_report_is_semantically_valid_and_zero_authority(self) -> None:
        self.assertEqual(self.errors(copy.deepcopy(self.report)), [])
        self.assertEqual(len(self.report["repositories"]), 75)
        self.assertEqual(self.report["summary"]["authorized_mutations"], 0)

    def test_duplicate_path_and_identity_are_rejected(self) -> None:
        report = copy.deepcopy(self.report)
        report["repositories"].append(copy.deepcopy(report["repositories"][0]))
        report["repositories"].sort(key=lambda row: row["repo_path"])
        report["summary"]["total"] += 1
        report["summary"]["excluded"] += 1
        self.refresh_identity(report)
        errors = self.errors(report)
        self.assertTrue(any("duplicate repository path" in item for item in errors))
        self.assertTrue(any("duplicate repository identity" in item for item in errors))

    def test_provisional_approval_or_eligibility_is_rejected(self) -> None:
        report = copy.deepcopy(self.report)
        report["approval"]["status"] = "approved"
        report["approval"]["requested_at"] = report["observed_at"]
        report["approval"]["approved_census_id"] = report["census_id"]
        report["repositories"][20]["approval_status"] = "approved"
        report["repositories"][20]["eligible"] = True
        errors = self.errors(report)
        self.assertTrue(any("provisional" in item.lower() for item in errors))
        self.assertTrue(any("mutation authority" in item for item in errors))

    def test_unbound_plan_target_is_rejected_even_with_valid_binding_hash(self) -> None:
        report = copy.deepcopy(self.report)
        report["status"] = "approval-ready"
        for dependency in report["dependencies"]:
            dependency["status"] = "completed"
        row = self.candidate_row(report)
        plan = self.exact_plan(row, "/Volumes/Dev/outside-target")
        row["proposed_operation"] = {"kind": "canonical-reconcile", "plan": plan}
        self.refresh_identity(report)
        errors = self.errors(report)
        self.assertTrue(any("unbound target" in item for item in errors), errors)

    def test_wrong_repository_identity_and_operation_binding_are_rejected(self) -> None:
        report = copy.deepcopy(self.report)
        report["repositories"][0]["repo_identity"] = "sha256:" + "0" * 64
        self.refresh_identity(report)
        self.assertTrue(
            any("does not bind exact path" in item for item in self.errors(report))
        )

    def test_machine_identity_or_token_fields_are_rejected(self) -> None:
        report = copy.deepcopy(self.report)
        report["sources"]["entitlement"]["login"] = "local-person"
        report["sources"]["entitlement"]["token"] = "ghp_fixture"
        report["sources"]["entitlement"]["path"] = "/Users/local-person/state.json"
        self.refresh_identity(report)
        errors = self.errors(report)
        self.assertTrue(any("prohibited identity/secret field" in item for item in errors))
        self.assertTrue(any("machine identity" in item for item in errors))

    def test_row_authority_requires_matching_global_owner_approval(self) -> None:
        report = copy.deepcopy(self.report)
        report["status"] = "approval-ready"
        for dependency in report["dependencies"]:
            dependency["status"] = "completed"
        row = self.candidate_row(report)
        target = row["repo_path"] + "/.claude/settings.json"
        row["proposed_operation"] = {
            "kind": "canonical-reconcile",
            "plan": self.exact_plan(row, target),
        }
        row["approval_status"] = "approved"
        row["eligible"] = True
        report["summary"]["approved"] = 1
        report["summary"]["authorized_mutations"] = 1
        self.refresh_identity(report)
        errors = self.errors(report)
        self.assertTrue(
            any("row authority requires global owner approval" in item for item in errors),
            errors,
        )

    def test_dot_segment_target_escape_is_rejected_before_containment(self) -> None:
        report = copy.deepcopy(self.report)
        report["status"] = "approval-ready"
        for dependency in report["dependencies"]:
            dependency["status"] = "completed"
        row = self.candidate_row(report)
        target = row["repo_path"] + "/../outside-target"
        row["proposed_operation"] = {
            "kind": "canonical-reconcile",
            "plan": self.exact_plan(row, target),
        }
        self.refresh_identity(report)
        errors = self.errors(report)
        self.assertTrue(any("invalid target" in item for item in errors), errors)

    def test_missing_task_297_dependency_fails_closed(self) -> None:
        report = copy.deepcopy(self.report)
        report["status"] = "approval-ready"
        report["dependencies"] = [
            dependency
            for dependency in report["dependencies"]
            if dependency["task"] != "TASK-297"
        ]
        for dependency in report["dependencies"]:
            dependency["status"] = "completed"
        self.refresh_identity(report)
        errors = self.errors(report)
        self.assertTrue(any("exact TASK-281/TASK-295/TASK-297" in item for item in errors))

    def test_task_297_required_flag_cannot_bypass_completion(self) -> None:
        report = copy.deepcopy(self.report)
        report["status"] = "approval-ready"
        for dependency in report["dependencies"]:
            dependency["status"] = "completed"
            if dependency["task"] == "TASK-297":
                dependency["status"] = "in_progress"
                dependency["required_for_approval"] = False
        self.refresh_identity(report)
        errors = self.errors(report)
        self.assertTrue(
            any("cannot be downgraded" in item for item in errors), errors
        )
        self.assertTrue(
            any("approval-ready requires completed dependencies" in item for item in errors),
            errors,
        )

    def test_identity_scan_covers_all_persisted_string_locations(self) -> None:
        def reason(report: dict) -> None:
            report["repositories"][0]["reason"] = "/Users/local-person/private"

        def exclusion_reason(report: dict) -> None:
            report["repositories"][0]["exclusions"][0]["reason"] = (
                "login=local-person"
            )

        def layer_id(report: dict) -> None:
            row = self.candidate_row(report)
            row["entitlement"]["evidence"] = [
                {
                    "product_family": "claude",
                    "layer_id": "/home/local-person/protected-layer",
                    "tier_role": "organization",
                    "state": "entitled",
                    "revision": 1,
                    "binding_receipt": "sha256:" + "c" * 64,
                }
            ]

        def plan_target(report: dict) -> None:
            row = self.candidate_row(report)
            row["proposed_operation"] = {
                "kind": "canonical-reconcile",
                "plan": self.exact_plan(row, "/Users/local-person/target"),
            }

        for mutate in (reason, exclusion_reason, layer_id, plan_target):
            with self.subTest(location=mutate.__name__):
                report = copy.deepcopy(self.report)
                mutate(report)
                self.refresh_identity(report)
                errors = self.errors(report)
                self.assertTrue(
                    any("identity or credential-like" in item for item in errors),
                    errors,
                )

    def test_entitlement_evidence_is_filtered_per_repository_family(self) -> None:
        records = {
            "claude-organization": {
                "product": "claude",
                "repo": "org/claude-private",
                "state": "entitled",
                "revision": 4,
            },
            "codex-organization": {
                "product": "codex",
                "repo": "org/codex-private",
                "state": "revoked",
                "revision": 9,
            },
        }
        observed = datetime(2026, 8, 12, tzinfo=timezone.utc)
        claude = collector.entitlement_for_repository(
            families=["claude"],
            records=records,
            dependency_pending=False,
            observed_at=observed,
        )
        codex = collector.entitlement_for_repository(
            families=["codex"],
            records=records,
            dependency_pending=False,
            observed_at=observed,
        )
        self.assertEqual(claude["state"], "entitled")
        self.assertEqual([item["layer_id"] for item in claude["evidence"]], ["claude-organization"])
        self.assertEqual(codex["state"], "revoked")
        self.assertEqual([item["layer_id"] for item in codex["evidence"]], ["codex-organization"])
        rendered = json.dumps({"claude": claude, "codex": codex})
        self.assertNotIn("private", rendered)


if __name__ == "__main__":
    unittest.main()
