#!/usr/bin/env python3
"""Deterministic semantic negatives for the fleet-census approval gate."""

from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
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
preparer = load_module("fleet_census_preparer", "prepare-fleet-census.py")
approver = load_module("fleet_census_approver", "approve-fleet-census.py")


class FleetCensusSemanticTests(unittest.TestCase):
    NOW = datetime(2026, 8, 14, 17, 0, tzinfo=timezone.utc)

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
        return validator.validate(report, self.schema, now_utc=self.NOW)

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
            "expires_at": "2026-08-14T18:00:00Z",
            "target_paths": [target],
            "binding_id": "",
        }
        plan["binding_id"] = validator.operation_binding(row["repo_identity"], plan)
        return plan

    def owner_selection(self, report: dict, rows: list[dict]) -> dict:
        plan = next(
            row["proposed_operation"]["plan"]
            for row in report["repositories"]
            if row["proposed_operation"]["plan"] is not None
        )
        return {
            "census_id": report["census_id"],
            "plan": {
                "plan_id": plan["plan_id"],
                "plan_fingerprint": plan["plan_fingerprint"],
                "expires_at": plan["expires_at"],
            },
            "repositories": [
                {
                    "repo_identity": row["repo_identity"],
                    "repo_path": row["repo_path"],
                    "target_paths": list(row["proposed_operation"]["plan"]["target_paths"]),
                }
                for row in sorted(rows, key=lambda item: item["repo_path"])
            ],
        }

    def private_plan_record(
        self,
        census: dict,
        *,
        plan_id: str,
        expires_at: str,
        plan_fingerprint: str,
        plans: list[dict],
    ) -> dict:
        canonical_request = preparer.build_request(census)
        request_fingerprint = preparer.digest(canonical_request)
        helper_version = "2.12.10"
        schema_version = "2.0"
        return {
            "storage_schema_version": "1.0",
            "plan_id": plan_id,
            "state": "reviewed",
            "expires_at": expires_at,
            "created_at": "2026-08-14T16:55:00Z",
            "fresh_plan_fingerprint": plan_fingerprint,
            "plans": copy.deepcopy(plans),
            "canonical_request": canonical_request,
            "request_fingerprint": request_fingerprint,
            "helper_version": helper_version,
            "schema_version": schema_version,
            "binding_fingerprint": preparer.private_plan_binding(
                request_fingerprint,
                plan_fingerprint,
                helper_version,
                schema_version,
            ),
            "claim_token_hash": None,
            "outcome": None,
            "finished_at": None,
        }

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

    def test_exact_owner_exclusion_is_non_mutating_and_content_free(self) -> None:
        repo = Path("/Volumes/Dev/Sites/TSM/hermes")
        exclusion = collector.owner_exclusion(repo, {repo})
        self.assertEqual(
            exclusion,
            {
                "code": "owner-policy-exclusion",
                "source": "owner-policy",
                "reason": collector.OWNER_EXCLUSION_REASON,
            },
        )
        self.assertIsNone(
            collector.owner_exclusion(
                Path("/Volumes/Dev/Sites/COPILOT/example"),
                {repo},
            )
        )

    def test_nested_archive_owner_exclusion_produces_exact_synthetic_row(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT) as temporary:
            repo = Path(temporary) / "h1"
            repo.mkdir()
            subprocess.run(("git", "init", "-q", str(repo)), check=True)
            row = collector.synthetic_owner_exclusion_row(repo)
        self.assertEqual(row["repo_path"], str(repo))
        self.assertEqual(row["repo_class"], "SCRATCH-ARCHIVE")
        self.assertEqual(row["proposed_operation"], {"kind": "none", "plan": None})
        self.assertFalse(row["eligible"])
        self.assertEqual(row["exclusions"][0]["code"], "owner-policy-exclusion")

    def test_preparer_binds_mutation_and_no_change_without_selecting_exclusions(self) -> None:
        report = copy.deepcopy(self.report)
        for dependency in report["dependencies"]:
            dependency["status"] = "completed"
        candidates = [row for row in report["repositories"] if row["proposed_operation"]["kind"] == "refresh-after-dependencies"][:2]
        candidate_paths = {row["repo_path"] for row in candidates}
        for row in report["repositories"]:
            if row["proposed_operation"]["kind"] != "refresh-after-dependencies":
                continue
            if row["repo_path"] in candidate_paths:
                row["proposed_operation"] = {"kind": "canonical-reconcile", "plan": None}
            else:
                row["proposed_operation"] = {"kind": "hold", "plan": None}
                row["responsible_actor"] = "repository-owner"
                row["reason"] = "Fixture hold."
        report["census_id"] = collector.census_identity(report)
        request = preparer.build_request(report)
        self.assertEqual([item["path"] for item in request["projects"]], [row["repo_path"] for row in candidates])
        plan_id = "plan_" + "c" * 32
        expires_at = "2026-08-14T18:00:00Z"
        plans = [
            {"path": candidates[0]["repo_path"], "operations": [{"target": ".claude/settings.json"}]},
            {"path": candidates[1]["repo_path"], "operations": []},
        ]
        plan_report = {"plan_id": plan_id, "expires_at": expires_at, "plans": plans}
        plan_record = self.private_plan_record(
            report,
            plan_id=plan_id,
            expires_at=expires_at,
            plan_fingerprint="sha256:" + "d" * 64,
            plans=plans,
        )
        prepared = preparer.prepare(
            report,
            plan_report,
            plan_record,
            now_utc=self.NOW,
        )
        first = next(row for row in prepared["repositories"] if row["repo_path"] == candidates[0]["repo_path"])
        second = next(row for row in prepared["repositories"] if row["repo_path"] == candidates[1]["repo_path"])
        self.assertEqual(first["proposed_operation"]["kind"], "canonical-reconcile")
        self.assertEqual(first["proposed_operation"]["plan"]["target_paths"], [candidates[0]["repo_path"] + "/.claude/settings.json"])
        self.assertEqual(second["proposed_operation"]["kind"], "canonical-no-change")
        self.assertEqual(second["proposed_operation"]["plan"]["target_paths"], [])
        self.assertEqual(prepared["status"], "approval-ready")
        self.assertEqual(self.errors(prepared), [])

    def test_assessment_route_hold_is_removed_from_canonical_request(self) -> None:
        report = copy.deepcopy(self.report)
        candidates = [row for row in report["repositories"] if row["proposed_operation"]["kind"] == "refresh-after-dependencies"][:2]
        for row in candidates:
            row["proposed_operation"] = {"kind": "canonical-reconcile", "plan": None}
        assessment = {"projects": [{"path": candidates[0]["repo_path"], "route": "ready"}, {"path": candidates[1]["repo_path"], "route": "excluded"}]}
        routed = preparer.apply_assessment(report, assessment)
        request = preparer.build_request(routed)
        self.assertEqual([item["path"] for item in request["projects"]], [candidates[0]["repo_path"]])
        held = next(row for row in routed["repositories"] if row["repo_path"] == candidates[1]["repo_path"])
        self.assertEqual(held["proposed_operation"]["kind"], "hold")
        self.assertEqual(held["exclusions"][-1]["code"], "canonical-route-excluded")

    def test_approval_ready_plan_expiration_is_checked_against_one_captured_time(self) -> None:
        report = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        before_expiration = datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc)
        after_expiration = datetime(2026, 8, 14, 19, 13, tzinfo=timezone.utc)
        self.assertEqual(validator.validate(report, self.schema, now_utc=before_expiration), [])
        errors = validator.validate(report, self.schema, now_utc=after_expiration)
        self.assertTrue(any("canonical plan expired" in item for item in errors), errors)
        self.assertEqual(sum("canonical plan expired" in item for item in errors), report["summary"]["candidate"])

    def test_approval_ready_rows_require_one_plan_identity(self) -> None:
        report = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        planned = [row for row in report["repositories"] if row["proposed_operation"]["plan"] is not None]
        for field, value in (
            ("plan_id", "plan_" + "e" * 32),
            ("plan_fingerprint", "sha256:" + "f" * 64),
            ("expires_at", "2026-08-14T19:11:12Z"),
        ):
            with self.subTest(field=field):
                mutated = copy.deepcopy(report)
                row = next(item for item in mutated["repositories"] if item["repo_path"] == planned[0]["repo_path"])
                plan = row["proposed_operation"]["plan"]
                plan[field] = value
                plan["binding_id"] = validator.operation_binding(row["repo_identity"], plan)
                self.refresh_identity(mutated)
                errors = validator.validate(
                    mutated,
                    self.schema,
                    now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
                )
                self.assertTrue(any("one canonical plan identity" in item for item in errors), errors)

    def test_preparer_rejects_public_private_plan_or_path_disagreement(self) -> None:
        report = copy.deepcopy(self.report)
        for dependency in report["dependencies"]:
            dependency["status"] = "completed"
        candidate = self.candidate_row(report)
        candidate["proposed_operation"] = {"kind": "canonical-reconcile", "plan": None}
        for row in report["repositories"]:
            if row is not candidate and row["proposed_operation"]["kind"] == "refresh-after-dependencies":
                row["proposed_operation"] = {"kind": "hold", "plan": None}
        plan_id = "plan_" + "a" * 32
        plans = [{"path": candidate["repo_path"], "operations": [{"target": ".claude/settings.json"}]}]
        report_payload = {"plan_id": plan_id, "expires_at": "2026-08-14T18:00:00Z", "plans": plans}
        private_payload = self.private_plan_record(
            report,
            plan_id=plan_id,
            expires_at=report_payload["expires_at"],
            plan_fingerprint="sha256:" + "b" * 64,
            plans=plans,
        )
        mismatched_private = copy.deepcopy(private_payload)
        mismatched_private["plans"][0]["operations"] = []
        with self.assertRaisesRegex(ValueError, "public and private canonical plans do not match"):
            preparer.prepare(report, report_payload, mismatched_private, now_utc=self.NOW)
        duplicate_report = copy.deepcopy(report_payload)
        duplicate_report["plans"].append(copy.deepcopy(duplicate_report["plans"][0]))
        duplicate_private = copy.deepcopy(private_payload)
        duplicate_private["plans"] = copy.deepcopy(duplicate_report["plans"])
        with self.assertRaisesRegex(ValueError, "canonical plan paths do not match"):
            preparer.prepare(report, duplicate_report, duplicate_private, now_utc=self.NOW)
        invalid_binding = copy.deepcopy(private_payload)
        invalid_binding["binding_fingerprint"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(ValueError, "private canonical plan binding is invalid"):
            preparer.prepare(report, report_payload, invalid_binding, now_utc=self.NOW)

    def test_approval_ready_rejects_unresolved_or_hidden_plan_operations(self) -> None:
        baseline = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        candidate = next(row for row in baseline["repositories"] if row["proposed_operation"]["kind"] == "canonical-reconcile")
        unresolved = copy.deepcopy(baseline)
        unresolved_row = next(row for row in unresolved["repositories"] if row["repo_path"] == candidate["repo_path"])
        unresolved_row["proposed_operation"] = {"kind": "refresh-after-dependencies", "plan": None}
        self.refresh_identity(unresolved)
        errors = validator.validate(unresolved, self.schema, now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc))
        self.assertTrue(any("unresolved operation" in item for item in errors), errors)

        hidden = copy.deepcopy(baseline)
        hermes = next(row for row in hidden["repositories"] if row["repo_path"] == "/Volumes/Dev/Sites/TSM/hermes")
        hidden_plan = copy.deepcopy(candidate["proposed_operation"]["plan"])
        hidden_plan["target_paths"] = [hermes["repo_path"] + "/.claude/settings.json"]
        hidden_plan["binding_id"] = validator.operation_binding(hermes["repo_identity"], hidden_plan)
        hermes["proposed_operation"]["plan"] = hidden_plan
        self.refresh_identity(hidden)
        errors = validator.validate(hidden, self.schema, now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc))
        self.assertTrue(any("held or excluded operation carries a plan" in item for item in errors), errors)

    def test_preparer_rejects_consumed_or_expired_private_plan(self) -> None:
        report = copy.deepcopy(self.report)
        for dependency in report["dependencies"]:
            dependency["status"] = "completed"
        candidate = self.candidate_row(report)
        candidate["proposed_operation"] = {"kind": "canonical-reconcile", "plan": None}
        for row in report["repositories"]:
            if row is not candidate and row["proposed_operation"]["kind"] == "refresh-after-dependencies":
                row["proposed_operation"] = {"kind": "hold", "plan": None}
        plan_id = "plan_" + "a" * 32
        plans = [{"path": candidate["repo_path"], "operations": [{"target": ".claude/settings.json"}]}]
        plan_report = {"plan_id": plan_id, "expires_at": "2026-08-14T18:00:00Z", "plans": plans}
        plan_record = self.private_plan_record(
            report,
            plan_id=plan_id,
            expires_at=plan_report["expires_at"],
            plan_fingerprint="sha256:" + "b" * 64,
            plans=plans,
        )
        for state in ("applying", "consumed", "reverted"):
            with self.subTest(state=state):
                consumed = copy.deepcopy(plan_record)
                consumed["state"] = state
                consumed["claim_token_hash"] = "sha256:" + "c" * 64
                with self.assertRaisesRegex(ValueError, "not fresh and unclaimed"):
                    preparer.prepare(report, plan_report, consumed, now_utc=self.NOW)
        with self.assertRaisesRegex(ValueError, "expiration is invalid"):
            preparer.prepare(
                report,
                plan_report,
                plan_record,
                now_utc=datetime(2026, 8, 14, 18, 0, tzinfo=timezone.utc),
            )

    def test_current_census_has_exact_hermes_exclusions_and_safety_holds(self) -> None:
        report = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        expected_hermes = {
            "/Volumes/Dev/Sites/TSM/_archive/h1",
            "/Volumes/Dev/Sites/TSM/h2",
            "/Volumes/Dev/Sites/TSM/h3",
            "/Volumes/Dev/Sites/TSM/hermes",
        }
        owner_excluded = {
            row["repo_path"]
            for row in report["repositories"]
            if any(item["code"] == "owner-policy-exclusion" for item in row["exclusions"])
        }
        self.assertEqual(owner_excluded, expected_hermes)
        for row in report["repositories"]:
            unsafe = (
                row["workspace_state"]["git"] == "dirty"
                or row["workspace_state"]["customization"] == "detected"
                or row["workspace_state"]["ambiguity"]
            )
            if unsafe:
                self.assertIn(row["proposed_operation"]["kind"], {"none", "hold"}, row["repo_path"])

    def test_current_approval_ready_census_has_exact_zero_authority(self) -> None:
        report = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        self.assertEqual(report["approval"]["status"], "pending")
        self.assertEqual(report["summary"]["approved"], 0)
        self.assertEqual(report["summary"]["authorized_mutations"], 0)
        self.assertTrue(all(not row["eligible"] for row in report["repositories"]))
        self.assertTrue(all(row["approval_status"] == "pending" for row in report["repositories"]))

    def test_owner_decision_preserves_exact_approval_ready_census_identity(self) -> None:
        report = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        approval_ready_id = report["census_id"]
        candidate = next(row for row in report["repositories"] if row["proposed_operation"]["kind"] == "canonical-reconcile")
        for row in report["repositories"]:
            row["approval_status"] = "rejected"
        candidate["approval_status"] = "approved"
        candidate["eligible"] = True
        report["summary"]["approved"] = 1
        report["summary"]["authorized_mutations"] = 1
        report["approval"] = {
            "status": "approved",
            "responsible_actor": "product-owner",
            "requested_at": report["observed_at"],
            "approved_census_id": approval_ready_id,
        }
        self.assertEqual(validator.census_identity(report), approval_ready_id)
        self.assertEqual(
            validator.validate(
                report,
                self.schema,
                now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
            ),
            [],
        )

    def test_approval_command_authorizes_only_one_explicit_exact_selection(self) -> None:
        report = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        candidate = next(
            row
            for row in report["repositories"]
            if row["proposed_operation"]["kind"] == "canonical-reconcile"
        )
        selection = self.owner_selection(report, [candidate])
        result = approver.decide(
            report,
            selection,
            self.schema,
            census_id=report["census_id"],
            actor="product-owner",
            decision="approved",
            now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
        )
        approved = [
            row for row in result["repositories"] if row["approval_status"] == "approved"
        ]
        self.assertEqual([row["repo_identity"] for row in approved], [candidate["repo_identity"]])
        self.assertEqual(result["census_id"], report["census_id"])
        self.assertEqual(result["approval"]["approved_census_id"], report["census_id"])
        self.assertEqual(result["summary"]["approved"], 1)
        self.assertEqual(result["summary"]["authorized_mutations"], 1)
        self.assertTrue(
            all(
                not row["eligible"] and row["approval_status"] == "rejected"
                for row in result["repositories"]
                if row["proposed_operation"]["kind"] == "canonical-no-change"
            )
        )
        self.assertEqual(
            validator.validate(
                result,
                self.schema,
                now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
            ),
            [],
        )

    def test_rejection_requires_and_records_the_complete_explicit_proposal(self) -> None:
        report = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        candidates = [
            row
            for row in report["repositories"]
            if row["proposed_operation"]["kind"] == "canonical-reconcile"
        ]
        with self.assertRaisesRegex(ValueError, "complete mutation proposal"):
            approver.decide(
                report,
                self.owner_selection(report, candidates[:-1]),
                self.schema,
                census_id=report["census_id"],
                actor="product-owner",
                decision="rejected",
                now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
            )
        result = approver.decide(
            report,
            self.owner_selection(report, candidates),
            self.schema,
            census_id=report["census_id"],
            actor="product-owner",
            decision="rejected",
            now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
        )
        self.assertEqual(result["census_id"], report["census_id"])
        self.assertEqual(result["approval"]["status"], "rejected")
        self.assertIsNone(result["approval"]["approved_census_id"])
        self.assertTrue(
            all(
                row["approval_status"] == "rejected" and not row["eligible"]
                for row in result["repositories"]
            )
        )
        self.assertEqual(result["summary"]["authorized_mutations"], 0)

    def test_approval_command_rejects_stale_superseded_invalid_or_hidden_authority(self) -> None:
        baseline = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        candidate = next(
            row
            for row in baseline["repositories"]
            if row["proposed_operation"]["kind"] == "canonical-reconcile"
        )
        selection = self.owner_selection(baseline, [candidate])
        with self.assertRaisesRegex(ValueError, "expired"):
            approver.decide(
                baseline,
                selection,
                self.schema,
                census_id=baseline["census_id"],
                actor="product-owner",
                decision="approved",
                now_utc=datetime(2026, 8, 14, 19, 13, tzinfo=timezone.utc),
            )
        superseded = copy.deepcopy(baseline)
        superseded["status"] = "superseded"
        self.refresh_identity(superseded)
        superseded_selection = self.owner_selection(superseded, [candidate])
        with self.assertRaisesRegex(ValueError, "approval-ready"):
            approver.decide(
                superseded,
                superseded_selection,
                self.schema,
                census_id=superseded["census_id"],
                actor="product-owner",
                decision="approved",
                now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
            )
        invalid = copy.deepcopy(baseline)
        invalid["summary"]["candidate"] += 1
        with self.assertRaisesRegex(ValueError, "input census is invalid"):
            approver.decide(
                invalid,
                selection,
                self.schema,
                census_id=invalid["census_id"],
                actor="product-owner",
                decision="approved",
                now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
            )
        authorized = copy.deepcopy(baseline)
        authorized["approval"] = {
            "status": "approved",
            "responsible_actor": "product-owner",
            "requested_at": "2026-08-14T19:00:00Z",
            "approved_census_id": authorized["census_id"],
        }
        for row in authorized["repositories"]:
            row["approval_status"] = "rejected"
        authorized_candidate = next(
            row
            for row in authorized["repositories"]
            if row["repo_identity"] == candidate["repo_identity"]
        )
        authorized_candidate["approval_status"] = "approved"
        authorized_candidate["eligible"] = True
        authorized["summary"]["approved"] = 1
        authorized["summary"]["authorized_mutations"] = 1
        with self.assertRaisesRegex(ValueError, "hidden or prior mutation authority"):
            approver.decide(
                authorized,
                selection,
                self.schema,
                census_id=authorized["census_id"],
                actor="product-owner",
                decision="approved",
                now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
            )

    def test_approval_command_rejects_identity_plan_and_target_mismatches(self) -> None:
        report = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        candidates = [
            row
            for row in report["repositories"]
            if row["proposed_operation"]["kind"] == "canonical-reconcile"
        ]

        def assert_rejected(selection: dict, pattern: str, *, census_id: str | None = None) -> None:
            with self.assertRaisesRegex(ValueError, pattern):
                approver.decide(
                    report,
                    selection,
                    self.schema,
                    census_id=census_id or report["census_id"],
                    actor="product-owner",
                    decision="approved",
                    now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
                )

        mismatched_census = self.owner_selection(report, [candidates[0]])
        mismatched_census["census_id"] = "sha256:" + "0" * 64
        assert_rejected(mismatched_census, "selection census ID")
        assert_rejected(
            self.owner_selection(report, [candidates[0]]),
            "explicit census ID",
            census_id="sha256:" + "0" * 64,
        )
        wrong_plan = self.owner_selection(report, [candidates[0]])
        wrong_plan["plan"]["plan_id"] = "plan_" + "0" * 32
        assert_rejected(wrong_plan, "plan identity")
        wrong_binding = self.owner_selection(report, [candidates[0]])
        wrong_binding["repositories"][0]["repo_path"] = candidates[1]["repo_path"]
        assert_rejected(wrong_binding, "identity/path binding")
        missing_target = self.owner_selection(report, [candidates[0]])
        missing_target["repositories"][0]["target_paths"].pop()
        assert_rejected(missing_target, "partial, extra, reordered, or mismatched")
        extra_target = self.owner_selection(report, [candidates[0]])
        extra_target["repositories"][0]["target_paths"].append(
            candidates[0]["repo_path"] + "/unreviewed-target"
        )
        assert_rejected(extra_target, "partial, extra, reordered, or mismatched")
        duplicate_target = self.owner_selection(report, [candidates[0]])
        duplicate_target["repositories"][0]["target_paths"].append(
            duplicate_target["repositories"][0]["target_paths"][-1]
        )
        assert_rejected(duplicate_target, "duplicate")
        duplicate_row = self.owner_selection(report, [candidates[0]])
        duplicate_row["repositories"].append(copy.deepcopy(duplicate_row["repositories"][0]))
        assert_rejected(duplicate_row, "duplicate repository")
        wildcard = self.owner_selection(report, [candidates[0]])
        wildcard["repositories"][0]["repo_path"] += "/*"
        assert_rejected(wildcard, "wildcard")
        empty = self.owner_selection(report, [candidates[0]])
        empty["repositories"] = []
        assert_rejected(empty, "explicitly selected")

    def test_approval_command_rejects_held_excluded_and_hermes_rows(self) -> None:
        report = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        candidate = next(
            row
            for row in report["repositories"]
            if row["proposed_operation"]["kind"] == "canonical-reconcile"
        )
        for forbidden in (
            next(row for row in report["repositories"] if row["proposed_operation"]["kind"] == "hold"),
            next(row for row in report["repositories"] if row["proposed_operation"]["kind"] == "none"),
            next(row for row in report["repositories"] if row["repo_path"] == "/Volumes/Dev/Sites/TSM/hermes"),
        ):
            with self.subTest(repo_path=forbidden["repo_path"]):
                selection = self.owner_selection(report, [candidate])
                selection["repositories"][0] = {
                    "repo_identity": forbidden["repo_identity"],
                    "repo_path": forbidden["repo_path"],
                    "target_paths": list(candidate["proposed_operation"]["plan"]["target_paths"]),
                }
                with self.assertRaisesRegex(ValueError, "held, excluded, or Hermes"):
                    approver.decide(
                        report,
                        selection,
                        self.schema,
                        census_id=report["census_id"],
                        actor="product-owner",
                        decision="approved",
                        now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
                    )

    def test_approval_output_is_exclusive_and_never_overwrites_input(self) -> None:
        payload = {"decision": "fixture"}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            input_path = root / "input.json"
            output_path = root / "output.json"
            input_path.write_text("{}\n", encoding="utf-8")
            approver.write_exclusive(output_path, payload, input_path=input_path)
            self.assertEqual(json.loads(output_path.read_text(encoding="utf-8")), payload)
            with self.assertRaises(FileExistsError):
                approver.write_exclusive(output_path, payload, input_path=input_path)
            with self.assertRaises(FileExistsError):
                approver.write_exclusive(input_path, payload, input_path=input_path)

    def test_dirty_customized_or_ambiguous_candidate_fails_closed(self) -> None:
        baseline = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        candidate = next(row for row in baseline["repositories"] if row["proposed_operation"]["kind"] == "canonical-reconcile")
        for field, value in (
            ("git", "dirty"),
            ("customization", "detected"),
            ("ambiguity", True),
        ):
            with self.subTest(field=field):
                report = copy.deepcopy(baseline)
                row = next(item for item in report["repositories"] if item["repo_path"] == candidate["repo_path"])
                row["workspace_state"][field] = value
                if field == "git":
                    row["workspace_state"]["dirty_entry_count"] = 1
                summary_field = {
                    "git": "dirty",
                    "customization": "customized",
                    "ambiguity": "ambiguous",
                }[field]
                report["summary"][summary_field] += 1
                self.refresh_identity(report)
                errors = validator.validate(
                    report,
                    self.schema,
                    now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
                )
                self.assertTrue(any("unsafe workspace must remain held or excluded" in item for item in errors), errors)

    def test_superseded_census_cannot_regain_authority(self) -> None:
        report = json.loads((ROOT / "approval-ready-fleet-census-2026-08-14.json").read_text(encoding="utf-8"))
        report["status"] = "superseded"
        candidate = next(row for row in report["repositories"] if row["proposed_operation"]["kind"] == "canonical-reconcile")
        for row in report["repositories"]:
            row["approval_status"] = "rejected"
        candidate["approval_status"] = "approved"
        candidate["eligible"] = True
        report["summary"]["approved"] = 1
        report["summary"]["authorized_mutations"] = 1
        self.refresh_identity(report)
        report["approval"] = {
            "status": "approved",
            "responsible_actor": "product-owner",
            "requested_at": report["observed_at"],
            "approved_census_id": report["census_id"],
        }
        errors = validator.validate(
            report,
            self.schema,
            now_utc=datetime(2026, 8, 14, 19, 0, tzinfo=timezone.utc),
        )
        self.assertTrue(any("superseded census cannot carry mutation authority" in item for item in errors), errors)


if __name__ == "__main__":
    unittest.main()
