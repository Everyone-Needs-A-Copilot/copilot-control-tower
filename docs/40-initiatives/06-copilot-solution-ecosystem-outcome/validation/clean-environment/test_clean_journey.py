from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest

import clean_journey


HERE = Path(__file__).resolve().parent
PLAN_PATH = HERE / "fixtures" / "fixture-plan.json"
LIVE_PLAN_PATH = HERE / "live-plan.template.json"
FIXTURE_TOOL = HERE / "fixtures" / "fixture_runtime.py"


class CleanJourneyHarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="task-303-harness-test-")
        self.root = Path(self.temporary.name) / "isolated"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def bindings(self) -> dict[str, str]:
        return {"python": sys.executable, "fixture_tool": str(FIXTURE_TOOL)}

    def load_plan(self) -> dict[str, object]:
        return json.loads(PLAN_PATH.read_text(encoding="utf-8"))

    def write_plan(self, value: dict[str, object], name: str = "plan.json") -> Path:
        path = Path(self.temporary.name) / name
        path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        return path

    def write_attack_wrapper(self, action: str, body: str) -> Path:
        path = Path(self.temporary.name) / f"{action}.py"
        source = f'''#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys
import time

if sys.argv[1] == {action!r}:
{textwrap.indent(textwrap.dedent(body).strip(), "    ")}
    raise SystemExit(0)
os.execv(sys.executable, [sys.executable, {str(FIXTURE_TOOL)!r}, *sys.argv[1:]])
'''
        path.write_text(source, encoding="utf-8")
        return path

    def plan_for_wrapper(self, wrapper: Path, *, action: str, command_index: int = -1) -> tuple[dict[str, object], dict[str, str]]:
        plan = self.load_plan()
        plan["execution_contract"]["bindings"]["fixture_tool"]["sha256"] = clean_journey.sha256_file(wrapper)
        plan["commands"][command_index]["argv"] = ["{python}", "{fixture_tool}", action]
        return plan, {"python": sys.executable, "fixture_tool": str(wrapper)}

    def test_full_fixture_journey_completes_and_verifies(self) -> None:
        result = clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=self.bindings(), resume=False)
        self.assertEqual(result["result"], "completed")
        verification = clean_journey.verify(self.root, PLAN_PATH, self.bindings())
        self.assertEqual(verification["result"], "verified")
        self.assertEqual(verification["records"], 11)
        manifest = json.loads((self.root / "evidence" / "manifest.json").read_text(encoding="utf-8"))
        self.assertFalse(manifest["control_tower_app_used"])
        self.assertEqual(manifest["environment_contract"]["shell_inline_dispatch"], "forbidden; exact interpreter-plus-script contract required")
        self.assertEqual(manifest["environment_contract"]["inline_interpreter_execution"], "forbidden")
        self.assertRegex(manifest["execution_bindings"]["python"]["sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(manifest["problem"]["id"], "accounting-evidence-gap-v1")
        expected_problem = (HERE / "fixtures" / "synthetic-problem.md").read_bytes()
        self.assertEqual(manifest["problem"]["sha256"], clean_journey.sha256_bytes(expected_problem))
        self.assertEqual((self.root / "project" / "human-owned.txt").read_text(encoding="utf-8"), "owner bytes stay fixed\n")
        self.assertIn("Resumed next action", (self.root / "project" / "artifact.md").read_text(encoding="utf-8"))

    def test_pause_and_resume_work_across_fresh_processes(self) -> None:
        base_command = [sys.executable, str(HERE / "clean_journey.py")]
        paused = subprocess.run(
            base_command + ["run", "--plan", str(PLAN_PATH), "--root", str(self.root), "--stop-after", "preserve", "--bind", f"python={sys.executable}", "--bind", f"fixture_tool={FIXTURE_TOOL}"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(paused.returncode, 0, paused.stderr)
        paused_result = json.loads(paused.stdout)
        self.assertEqual(paused_result["result"], "paused")
        resumed = subprocess.run(
            base_command + ["resume", "--plan", str(PLAN_PATH), "--root", str(self.root), "--anchor-sha256", paused_result["manifest_sha256"], "--bind", f"python={sys.executable}", "--bind", f"fixture_tool={FIXTURE_TOOL}"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertEqual(json.loads(resumed.stdout)["result"], "completed")
        record = json.loads((self.root / "evidence" / "commands" / "06-continue.json").read_text(encoding="utf-8"))
        self.assertEqual(record["result"], "pass")

    def test_resume_rejects_tampered_state(self) -> None:
        paused = clean_journey.execute(PLAN_PATH, self.root, stop_after="preserve", bindings=self.bindings(), resume=False)
        state_path = self.root / "evidence" / "state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["next_command_index"] = 0
        state_path.write_text(json.dumps(state) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(clean_journey.HarnessError, "seal mismatch"):
            clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=self.bindings(), resume=True, resume_anchor_sha256=paused["manifest_sha256"])

    def test_expected_failure_is_honest_and_does_not_mutate_project(self) -> None:
        clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=self.bindings(), resume=False)
        record = json.loads((self.root / "evidence" / "commands" / "08-honest-failure.json").read_text(encoding="utf-8"))
        self.assertEqual(record["exit_code"], 42)
        self.assertEqual(record["result"], "pass")
        self.assertEqual(record["project_tree_before_sha256"], record["project_tree_after_sha256"])
        held = json.loads((self.root / "evidence" / "held.json").read_text(encoding="utf-8"))
        self.assertEqual(held["result"], "held")
        self.assertEqual(held["recovery_actor"], "project owner")

    def test_clean_environment_drops_inherited_secret_variables(self) -> None:
        self.root.mkdir()
        env = clean_journey.clean_env(self.root)
        self.assertNotIn("GITHUB_TOKEN", env)
        self.assertNotIn("OPENAI_API_KEY", env)
        self.assertNotIn("ANTHROPIC_API_KEY", env)
        self.assertEqual(env["HOME"], str(self.root / "home"))
        self.assertEqual(env["CODEX_HOME"], str(self.root / "home" / ".codex"))

    def test_plan_rejects_application_dependency(self) -> None:
        plan = self.load_plan()
        plan["commands"][0]["argv"] = ["xcodebuild", "-project", "Control Tower.app"]
        with self.assertRaisesRegex(clean_journey.HarnessError, "app dependency"):
            clean_journey.validate_plan(plan)
        plan = self.load_plan()
        plan["commands"][0]["argv"].append("Control Tower.app")
        plan["commands"][0]["argv"].append("next-argument")
        with self.assertRaisesRegex(clean_journey.HarnessError, "app dependency"):
            clean_journey.validate_plan(plan)

    def test_pending_live_prerequisites_are_blocked(self) -> None:
        plan = json.loads(LIVE_PLAN_PATH.read_text(encoding="utf-8"))
        with self.assertRaisesRegex(clean_journey.HarnessError, "TASK-299"):
            clean_journey.validate_plan(plan)
        clean_journey.validate_plan(plan, allow_pending=True)

    def test_suspected_secret_output_is_suppressed_and_fails(self) -> None:
        plan = self.load_plan()
        leak_command = copy.deepcopy(plan["commands"][-1])
        leak_command["id"] = "secret-leak"
        leak_command["argv"] = ["{python}", "{fixture_tool}", "leak"]
        leak_command["evidence_paths"] = []
        plan["commands"][-1] = leak_command
        plan_path = self.write_plan(plan, "secret-plan.json")
        with self.assertRaisesRegex(clean_journey.HarnessError, "suspected secret"):
            clean_journey.execute(plan_path, self.root, stop_after=None, bindings=self.bindings(), resume=False)
        record = json.loads((self.root / "evidence" / "commands" / "10-secret-leak.json").read_text(encoding="utf-8"))
        self.assertEqual(record["secret_scan"], "fail-output-suppressed")
        self.assertNotIn("github_pat_", record["stdout"])

    def test_existing_unowned_or_git_directory_is_refused(self) -> None:
        self.root.mkdir()
        (self.root / "personal.txt").write_text("do not touch\n", encoding="utf-8")
        with self.assertRaisesRegex(clean_journey.HarnessError, "must be empty"):
            clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=self.bindings(), resume=False)
        other = Path(self.temporary.name) / "repo"
        (other / ".git").mkdir(parents=True)
        with self.assertRaisesRegex(clean_journey.HarnessError, "must not be a Git repository"):
            clean_journey.execute(PLAN_PATH, other, stop_after=None, bindings=self.bindings(), resume=False)

    def test_evidence_paths_cannot_escape_the_isolated_root(self) -> None:
        plan = self.load_plan()
        plan["commands"][0]["evidence_paths"] = ["../outside.json"]
        plan_path = self.write_plan(plan, "escape-plan.json")
        with self.assertRaisesRegex(clean_journey.HarnessError, "without traversal"):
            clean_journey.execute(plan_path, self.root, stop_after=None, bindings=self.bindings(), resume=False)

    def test_shell_env_and_inline_interpreter_dispatch_are_rejected(self) -> None:
        plan = self.load_plan()
        plan["commands"][0]["argv"] = ["{python}", "-c", "print('bypass')"]
        with self.assertRaisesRegex(clean_journey.HarnessError, "inline interpreter"):
            clean_journey.validate_plan(plan)
        with self.assertRaisesRegex(clean_journey.HarnessError, "interpreter family"):
            clean_journey.resolve_execution_bindings(self.load_plan(), {"python": "/bin/sh", "fixture_tool": str(FIXTURE_TOOL)})
        with self.assertRaisesRegex(clean_journey.HarnessError, "dispatcher is forbidden"):
            clean_journey.resolve_execution_bindings(self.load_plan(), {"python": "/usr/bin/env", "fixture_tool": str(FIXTURE_TOOL)})
        plan = self.load_plan()
        plan["execution_contract"]["bindings"]["python"] = {"kind": "executable", "sha256": "capture-at-run", "app_dependency_free": True, "review_evidence": "fixture attack"}
        executable_script = Path(self.temporary.name) / "unbound-shebang.py"
        executable_script.write_bytes(FIXTURE_TOOL.read_bytes())
        executable_script.chmod(0o700)
        with self.assertRaisesRegex(clean_journey.HarnessError, "must use an exact declared interpreter"):
            clean_journey.resolve_execution_bindings(plan, {"python": str(executable_script), "fixture_tool": str(FIXTURE_TOOL)})
        plan = self.load_plan()
        plan["execution_contract"]["bindings"]["python"] = {"kind": "executable", "sha256": "capture-at-run", "app_dependency_free": True, "review_evidence": "fixture attack"}
        with self.assertRaisesRegex(clean_journey.HarnessError, "is an interpreter"):
            clean_journey.resolve_execution_bindings(plan, {"python": sys.executable, "fixture_tool": str(FIXTURE_TOOL)})

    def test_plan_schema_rejects_hidden_fields_noncanonical_placeholders_and_unused_bindings(self) -> None:
        plan = self.load_plan()
        plan["commands"][0]["ignored_authority"] = True
        with self.assertRaisesRegex(clean_journey.HarnessError, "closed command fields"):
            clean_journey.validate_plan(plan)
        plan = self.load_plan()
        plan["commands"][0]["argv"].append("{python.__class__}")
        with self.assertRaisesRegex(clean_journey.HarnessError, "non-canonical placeholder"):
            clean_journey.validate_plan(plan)
        plan = self.load_plan()
        plan["execution_contract"]["bindings"]["unused"] = {"kind": "executable", "sha256": "capture-at-run", "app_dependency_free": True, "review_evidence": "fixture attack"}
        with self.assertRaisesRegex(clean_journey.HarnessError, "every trusted binding"):
            clean_journey.validate_plan(plan)

    def test_executable_hash_mismatch_and_extra_binding_are_rejected(self) -> None:
        plan = self.load_plan()
        plan["execution_contract"]["bindings"]["fixture_tool"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(clean_journey.HarnessError, "SHA-256 mismatch"):
            clean_journey.execute(self.write_plan(plan), self.root, stop_after=None, bindings=self.bindings(), resume=False)
        bindings = {**self.bindings(), "unreviewed": "/bin/echo"}
        with self.assertRaisesRegex(clean_journey.HarnessError, "match the plan exactly"):
            clean_journey.resolve_execution_bindings(self.load_plan(), bindings)

    def test_resume_rejects_changed_binding_even_when_bytes_match(self) -> None:
        paused = clean_journey.execute(PLAN_PATH, self.root, stop_after="preserve", bindings=self.bindings(), resume=False)
        copy_path = Path(self.temporary.name) / "fixture-copy.py"
        copy_path.write_bytes(FIXTURE_TOOL.read_bytes())
        changed = {"python": sys.executable, "fixture_tool": str(copy_path)}
        with self.assertRaisesRegex(clean_journey.HarnessError, "execution binding|ownership marker"):
            clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=changed, resume=True, resume_anchor_sha256=paused["manifest_sha256"])

    def test_resume_requires_the_external_paused_manifest_anchor(self) -> None:
        paused = clean_journey.execute(PLAN_PATH, self.root, stop_after="preserve", bindings=self.bindings(), resume=False)
        with self.assertRaisesRegex(clean_journey.HarnessError, "externally retained"):
            clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=self.bindings(), resume=True)
        with self.assertRaisesRegex(clean_journey.HarnessError, "external resume anchor"):
            clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=self.bindings(), resume=True, resume_anchor_sha256="0" * 64)
        result = clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=self.bindings(), resume=True, resume_anchor_sha256=paused["manifest_sha256"])
        self.assertEqual(result["result"], "completed")

    def test_resume_rejects_resealed_state_replay_and_changed_plan(self) -> None:
        paused = clean_journey.execute(PLAN_PATH, self.root, stop_after="preserve", bindings=self.bindings(), resume=False)
        state_path = self.root / "evidence" / "state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["next_command_index"] = 1
        state["previous_record_sha256"] = clean_journey.sha256_file(self.root / "evidence" / "commands" / "00-inventory.json")
        state["seal_sha256"] = clean_journey.sha256_bytes(clean_journey.canonical_json(clean_journey.state_payload(state)))
        state_path.write_text(json.dumps(state) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(clean_journey.HarnessError, "record set"):
            clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=self.bindings(), resume=True, resume_anchor_sha256=paused["manifest_sha256"])

        other_root = Path(self.temporary.name) / "other-root"
        other_paused = clean_journey.execute(PLAN_PATH, other_root, stop_after="preserve", bindings=self.bindings(), resume=False)
        changed_plan = self.load_plan()
        changed_plan["problem"]["text"] += "\nChanged after pause."
        with self.assertRaisesRegex(clean_journey.HarnessError, "ownership marker mismatch|state identity mismatch"):
            clean_journey.execute(self.write_plan(changed_plan, "changed-plan.json"), other_root, stop_after=None, bindings=self.bindings(), resume=True, resume_anchor_sha256=other_paused["manifest_sha256"])

    def test_verify_rejects_truncation_extra_records_and_manifest_or_artifact_tamper(self) -> None:
        clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=self.bindings(), resume=False)
        removed = self.root / "evidence" / "commands" / "05-preserve.json"
        original = removed.read_bytes()
        removed.unlink()
        with self.assertRaisesRegex(clean_journey.HarnessError, "record set"):
            clean_journey.verify(self.root, PLAN_PATH, self.bindings())
        removed.write_bytes(original)
        extra = self.root / "evidence" / "commands" / "99-extra.json"
        extra.write_text("{}\n", encoding="utf-8")
        with self.assertRaisesRegex(clean_journey.HarnessError, "record set"):
            clean_journey.verify(self.root, PLAN_PATH, self.bindings())
        extra.unlink()
        manifest_path = self.root / "evidence" / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["control_tower_app_used"] = True
        manifest_path.write_text(json.dumps(manifest) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(clean_journey.HarnessError, "manifest does not exactly match"):
            clean_journey.verify(self.root, PLAN_PATH, self.bindings())

        second_root = Path(self.temporary.name) / "artifact-root"
        clean_journey.execute(PLAN_PATH, second_root, stop_after=None, bindings=self.bindings(), resume=False)
        (second_root / "evidence" / "conformance.json").write_text('{"tampered":true}\n', encoding="utf-8")
        with self.assertRaisesRegex(clean_journey.HarnessError, "manifest does not exactly match"):
            clean_journey.verify(second_root, PLAN_PATH, self.bindings())

    def test_root_marker_and_symlinked_root_are_rejected(self) -> None:
        paused = clean_journey.execute(PLAN_PATH, self.root, stop_after="preserve", bindings=self.bindings(), resume=False)
        marker_path = self.root / ".clean-journey-root.json"
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
        marker["created_unix"] -= 1
        marker_path.write_text(json.dumps(marker) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(clean_journey.HarnessError, "marker seal mismatch"):
            clean_journey.execute(PLAN_PATH, self.root, stop_after=None, bindings=self.bindings(), resume=True, resume_anchor_sha256=paused["manifest_sha256"])
        symlink = Path(self.temporary.name) / "root-link"
        symlink.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(clean_journey.HarnessError, "must not be a symlink"):
            clean_journey.verify(symlink, PLAN_PATH, self.bindings())

    def test_critical_layout_symlink_escape_is_detected(self) -> None:
        outside = Path(self.temporary.name) / "outside"
        outside.mkdir()
        wrapper = self.write_attack_wrapper("layout-escape", f'''
root = Path(os.environ["CLEAN_JOURNEY_ROOT"])
project = Path(os.environ["CLEAN_JOURNEY_PROJECT"])
project.rename(root / "moved-project")
project.symlink_to({str(outside)!r}, target_is_directory=True)
''')
        plan, bindings = self.plan_for_wrapper(wrapper, action="layout-escape", command_index=0)
        with self.assertRaisesRegex(clean_journey.HarnessError, "layout"):
            clean_journey.execute(self.write_plan(plan), self.root, stop_after=None, bindings=bindings, resume=False)

    def test_secret_in_argv_or_artifact_is_never_preserved_in_records(self) -> None:
        secret_dir = Path(self.temporary.name) / "github_pat_123456789012345678901234567890"
        secret_dir.mkdir()
        secret_wrapper = secret_dir / "fixture.py"
        secret_wrapper.write_bytes(FIXTURE_TOOL.read_bytes())
        plan = self.load_plan()
        plan["execution_contract"]["bindings"]["fixture_tool"]["sha256"] = clean_journey.sha256_file(secret_wrapper)
        with self.assertRaisesRegex(clean_journey.HarnessError, "resolved argv"):
            clean_journey.execute(self.write_plan(plan, "argv-secret-plan.json"), self.root, stop_after=None, bindings={"python": sys.executable, "fixture_tool": str(secret_wrapper)}, resume=False)
        command_dir = self.root / "evidence" / "commands"
        self.assertFalse(command_dir.exists() and list(command_dir.iterdir()))

        second_root = Path(self.temporary.name) / "artifact-secret-root"
        wrapper = self.write_attack_wrapper("artifact-secret", '''
evidence = Path(os.environ["CLEAN_JOURNEY_EVIDENCE"]) / "conformance.json"
evidence.write_text('{"token":"github_pat_123456789012345678901234567890"}\\n', encoding="utf-8")
''')
        attack_plan, bindings = self.plan_for_wrapper(wrapper, action="artifact-secret")
        attack_path = self.write_plan(attack_plan, "artifact-secret-plan.json")
        with self.assertRaisesRegex(clean_journey.HarnessError, "evidence artifacts"):
            clean_journey.execute(attack_path, second_root, stop_after=None, bindings=bindings, resume=False)
        record = (second_root / "evidence" / "commands" / "10-conformance.json").read_text(encoding="utf-8")
        artifact = (second_root / "evidence" / "conformance.json").read_text(encoding="utf-8")
        self.assertNotIn("github_pat_", record)
        self.assertNotIn("github_pat_", artifact)

    def test_timeout_kills_process_group_and_cannot_be_expected_success(self) -> None:
        late_path = Path(self.temporary.name) / "late-write.txt"
        wrapper = self.write_attack_wrapper("timeout", f'''
subprocess.Popen([sys.executable, "-c", "import pathlib,time; time.sleep(1); pathlib.Path({str(late_path)!r}).write_text('escaped')"])
time.sleep(10)
''')
        plan, bindings = self.plan_for_wrapper(wrapper, action="timeout")
        plan["commands"][-1]["timeout_seconds"] = 1
        plan["commands"][-1]["expected_exit_codes"] = [124]
        with self.assertRaisesRegex(clean_journey.HarnessError, "timed out"):
            clean_journey.execute(self.write_plan(plan, "timeout-plan.json"), self.root, stop_after=None, bindings=bindings, resume=False)
        time.sleep(1.2)
        self.assertFalse(late_path.exists())

    def test_project_required_rejects_unrelated_mutation(self) -> None:
        wrapper = self.write_attack_wrapper("wrong-mutation", '''
project = Path(os.environ["CLEAN_JOURNEY_PROJECT"])
evidence = Path(os.environ["CLEAN_JOURNEY_EVIDENCE"])
(project / "unrelated.txt").write_text("not the declared output\\n", encoding="utf-8")
(evidence / "conformance.json").write_text("{}\\n", encoding="utf-8")
''')
        plan, bindings = self.plan_for_wrapper(wrapper, action="wrong-mutation")
        plan["commands"][-1]["mutation_policy"] = "project-required"
        plan["commands"][-1]["project_mutation_paths"] = ["expected-output.txt"]
        with self.assertRaisesRegex(clean_journey.HarnessError, "outside declared mutation paths"):
            clean_journey.execute(self.write_plan(plan, "mutation-plan.json"), self.root, stop_after=None, bindings=bindings, resume=False)

    def test_live_completion_requires_exact_prerequisite_evidence_and_resolved_identities(self) -> None:
        plan = json.loads(LIVE_PLAN_PATH.read_text(encoding="utf-8"))
        for row in plan["prerequisites"]:
            row["status"] = "complete"
            row["evidence"] = "looks-complete"
        with self.assertRaisesRegex(clean_journey.HarnessError, "work_product_id"):
            clean_journey.validate_plan(plan)
        for row in plan["prerequisites"]:
            row["evidence"] = {"work_product_id": 1, "sha256": "a" * 64}
        with self.assertRaisesRegex(clean_journey.HarnessError, "exact identity contract"):
            clean_journey.validate_plan(plan)
        plan["identities"] = {
            "framework_commit": "a" * 40,
            "framework_tree": "b" * 40,
            "framework_tag": "refs/tags/v5.15.0",
            "framework_signer": "SHA256:FIfppOkzwXZUAamELQzYoSUQXiEAmTYiVewHe1ACMZo",
            "organization_release_receipts_sha256": "sha256:" + "c" * 64,
            "accounting_release_receipts_sha256": "sha256:" + "d" * 64,
            "approved_census_id": "sha256:" + "e" * 64,
            "claude_runtime_model_sha256": "sha256:" + "f" * 64,
            "codex_runtime_model_plugin_sha256": "sha256:" + "0" * 64,
        }
        plan["session_id"] = "TASK-303-20260814T210000Z"
        for spec in plan["execution_contract"]["bindings"].values():
            spec["sha256"] = "1" * 64
            spec["review_evidence"] = "not-an-exact-work-product"
        with self.assertRaisesRegex(clean_journey.HarnessError, "review evidence must bind"):
            clean_journey.validate_plan(plan)


if __name__ == "__main__":
    unittest.main()
