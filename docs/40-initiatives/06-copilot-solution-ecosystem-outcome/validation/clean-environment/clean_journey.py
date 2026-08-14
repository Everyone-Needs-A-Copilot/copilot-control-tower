#!/usr/bin/env python3
"""Isolated, resumable evidence harness for TASK-303's clean framework journey."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import signal
import stat
import string
import subprocess
import tempfile
import time
from typing import Any


SCHEMA_VERSION = 2
STAGE_ORDER = (
    "inventory",
    "install",
    "assemble",
    "problem",
    "apply_create",
    "preserve",
    "continue",
    "update",
    "failure",
    "recovery",
    "conformance",
)
LIVE_REQUIRED_PREREQUISITES = {"TASK-285", "TASK-291", "TASK-300", "TASK-288", "TASK-299"}
LIVE_REQUIRED_IDENTITIES = {
    "framework_commit",
    "framework_tree",
    "framework_tag",
    "framework_signer",
    "organization_release_receipts_sha256",
    "accounting_release_receipts_sha256",
    "approved_census_id",
    "claude_runtime_model_sha256",
    "codex_runtime_model_plugin_sha256",
}
LIVE_IDENTITY_PATTERNS = {
    "framework_commit": re.compile(r"[0-9a-f]{40}"),
    "framework_tree": re.compile(r"[0-9a-f]{40}"),
    "framework_tag": re.compile(r"refs/tags/v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?"),
    "framework_signer": re.compile(r"SHA256:[A-Za-z0-9_+/=-]{20,}"),
    "organization_release_receipts_sha256": re.compile(r"sha256:[0-9a-f]{64}"),
    "accounting_release_receipts_sha256": re.compile(r"sha256:[0-9a-f]{64}"),
    "approved_census_id": re.compile(r"sha256:[0-9a-f]{64}"),
    "claude_runtime_model_sha256": re.compile(r"sha256:[0-9a-f]{64}"),
    "codex_runtime_model_plugin_sha256": re.compile(r"sha256:[0-9a-f]{64}"),
}
BUILTIN_BINDINGS = {"root", "home", "project", "evidence"}
PLAN_KEYS = {"schema_version", "session_id", "mode", "prerequisites", "identities", "execution_contract", "problem", "commands"}
PREREQUISITE_KEYS = {"task", "status", "evidence"}
PREREQUISITE_EVIDENCE_KEYS = {"work_product_id", "sha256"}
COMMAND_KEYS = {"id", "stage", "argv", "evidence_paths", "mutation_policy", "project_mutation_paths", "preserve_paths", "expected_exit_codes", "timeout_seconds"}
FORBIDDEN_DISPATCHER_NAMES = {
    "command",
    "env",
    "xargs",
}
INTERPRETER_FAMILY_PATTERNS = {
    "python": re.compile(r"python(?:\d+(?:\.\d+)*)?$"),
    "posix-shell": re.compile(r"(?:ba|da|k|z)?sh$"),
    "node": re.compile(r"node(?:js)?$"),
    "perl": re.compile(r"perl(?:\d+(?:\.\d+)*)?$"),
    "ruby": re.compile(r"ruby(?:\d+(?:\.\d+)*)?$"),
}
KNOWN_INTERPRETER_NAMES = re.compile(r"(?:awk|gawk|nawk|osascript|php(?:\d+(?:\.\d+)*)?|lua(?:\d+(?:\.\d+)*)?|tclsh(?:\d+(?:\.\d+)*)?|wish(?:\d+(?:\.\d+)*)?|deno|bun)$")
INTERPRETER_INLINE_FLAGS = {"-c", "-e", "-m", "--eval", "--execute", "--module", "-"}
APP_DEPENDENCY_PATTERNS = (
    re.compile(r"\.app(?:/|$)", re.IGNORECASE),
    re.compile(r"(?:^|/)native/", re.IGNORECASE),
    re.compile(r"\bxcodebuild\b", re.IGNORECASE),
    re.compile(r"\bcodesign\b", re.IGNORECASE),
    re.compile(r"\bnotarytool\b", re.IGNORECASE),
    re.compile(r"package-user-release", re.IGNORECASE),
)
SECRET_PATTERNS = (
    re.compile(r"(?<![A-Za-z0-9])gh[pousr]_[A-Za-z0-9_]{20,}"),
    re.compile(r"(?<![A-Za-z0-9])github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"(?i)authorization\s*:\s*bearer\s+\S+"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
)
ALLOWED_INHERITED_ENV = (
    "LANG",
    "LC_ALL",
    "PATH",
    "REQUESTS_CA_BUNDLE",
    "SSL_CERT_FILE",
    "TERM",
)


class HarnessError(RuntimeError):
    pass


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_manifest(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    for candidate in sorted(path.rglob("*")):
        relative = candidate.relative_to(path).as_posix()
        if candidate.is_symlink():
            rows.append({"path": relative, "kind": "symlink", "target": os.readlink(candidate)})
        elif candidate.is_file():
            rows.append({"path": relative, "kind": "file", "sha256": sha256_file(candidate), "size": candidate.stat().st_size})
        elif candidate.is_dir():
            rows.append({"path": relative, "kind": "directory"})
    return rows


def tree_digest(path: Path) -> str:
    return sha256_bytes(canonical_json(tree_manifest(path)))


def changed_tree_paths(before: list[dict[str, Any]], after: list[dict[str, Any]]) -> list[str]:
    before_by_path = {row["path"]: row for row in before}
    after_by_path = {row["path"]: row for row in after}
    return sorted(path for path in before_by_path.keys() | after_by_path.keys() if before_by_path.get(path) != after_by_path.get(path))


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HarnessError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise HarnessError(f"expected a JSON object in {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False).encode("utf-8") + b"\n")


def detect_secret(value: str) -> str | None:
    for pattern in SECRET_PATTERNS:
        if pattern.search(value):
            return pattern.pattern
    return None


def contains_app_dependency(values: list[str] | tuple[str, ...]) -> bool:
    return any(pattern.search(value) for value in values for pattern in APP_DEPENDENCY_PATTERNS)


def detect_file_secret(path: Path) -> str | None:
    decoder_overlap = ""
    try:
        with path.open("rb") as handle:
            for raw in iter(lambda: handle.read(1024 * 1024), b""):
                text = decoder_overlap + raw.decode("utf-8", errors="ignore")
                match = detect_secret(text)
                if match:
                    return match
                decoder_overlap = text[-512:]
    except OSError as exc:
        raise HarnessError(f"cannot scan evidence artifact {path}: {exc}") from exc
    return None


def validate_relative_path(value: str, *, field: str) -> None:
    candidate = Path(value)
    if not value or candidate.is_absolute() or value in {".", ".."} or ".." in candidate.parts:
        raise HarnessError(f"{field} must be a non-empty relative path without traversal: {value!r}")


def resolve_inside(root: Path, relative: str) -> Path:
    validate_relative_path(relative, field="evidence path")
    candidate = (root / relative).resolve(strict=False)
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise HarnessError(f"path escapes isolated root: {relative!r}") from exc
    return candidate


def validate_root(root_path: Path, *, allow_existing: bool) -> Path:
    expanded = root_path.expanduser()
    if expanded.is_symlink():
        raise HarnessError(f"isolated root must not be a symlink: {expanded}")
    root = expanded.resolve(strict=False)
    forbidden = {Path.home().resolve(), Path.cwd().resolve(), Path("/")}
    if root in forbidden:
        raise HarnessError(f"refusing unsafe isolated root: {root}")
    if root.exists():
        if not root.is_dir() or root.is_symlink():
            raise HarnessError(f"isolated root is not a real directory: {root}")
        root_stat = root.stat()
        if root_stat.st_uid != os.getuid():
            raise HarnessError(f"isolated root is not owned by the current user: {root}")
        if stat.S_IMODE(root_stat.st_mode) & 0o022:
            raise HarnessError(f"isolated root is group/world writable: {root}")
        git_marker = root / ".git"
        if git_marker.exists() or git_marker.is_symlink():
            raise HarnessError(f"isolated root must not be a Git repository: {root}")
        entries = list(root.iterdir())
        if entries and not allow_existing:
            raise HarnessError(f"isolated root must be empty: {root}")
        if entries and not (root / ".clean-journey-root.json").is_file():
            raise HarnessError(f"existing root lacks the harness ownership marker: {root}")
    else:
        root.mkdir(parents=True, mode=0o700)
    os.chmod(root, 0o700)
    return root


def validate_plan(plan: dict[str, Any], *, allow_pending: bool = False) -> None:
    if set(plan) != PLAN_KEYS:
        raise HarnessError("plan must contain only the closed schema fields")
    if plan.get("schema_version") != SCHEMA_VERSION:
        raise HarnessError(f"unsupported schema_version: {plan.get('schema_version')!r}")
    mode = plan.get("mode")
    if mode not in {"fixture", "live"}:
        raise HarnessError("mode must be fixture or live")
    if not isinstance(plan.get("session_id"), str) or not plan["session_id"].strip():
        raise HarnessError("session_id is required")
    if detect_secret(json.dumps(plan, ensure_ascii=False)):
        raise HarnessError("plan contains suspected secret material")
    prerequisites = plan.get("prerequisites")
    if not isinstance(prerequisites, list) or not prerequisites or not all(isinstance(row, dict) for row in prerequisites):
        raise HarnessError("prerequisites must be a non-empty object array")
    prerequisite_names = [row.get("task") for row in prerequisites]
    if len(prerequisite_names) != len(set(prerequisite_names)):
        raise HarnessError("prerequisite task names must be unique")
    if mode == "live" and set(prerequisite_names) != LIVE_REQUIRED_PREREQUISITES:
        raise HarnessError("live plan must contain the exact TASK-285/TASK-291/TASK-300/TASK-288/TASK-299 prerequisite set")
    pending: list[str] = []
    for row in prerequisites:
        if set(row) != PREREQUISITE_KEYS:
            raise HarnessError("each prerequisite must contain only task, status, and evidence")
        task = row.get("task")
        if not isinstance(task, str) or not task:
            raise HarnessError("each prerequisite requires a task name")
        if row.get("status") != "complete":
            pending.append(task)
            continue
        evidence = row.get("evidence")
        if mode == "live":
            if not isinstance(evidence, dict) or set(evidence) != PREREQUISITE_EVIDENCE_KEYS or not isinstance(evidence.get("work_product_id"), int) or evidence["work_product_id"] <= 0 or not re.fullmatch(r"[0-9a-f]{64}", str(evidence.get("sha256", ""))):
                raise HarnessError(f"completed live prerequisite {task} requires a work_product_id and exact evidence SHA-256")
        elif not evidence:
            pending.append(task)
    if pending and not allow_pending:
        raise HarnessError(f"live prerequisites are unresolved: {', '.join(pending)}")
    identities = plan.get("identities")
    if not isinstance(identities, dict) or not identities:
        raise HarnessError("identities must bind the run to exact inputs")
    if mode == "live":
        if set(identities) != LIVE_REQUIRED_IDENTITIES:
            raise HarnessError("live identities must contain the exact required identity fields")
        if not allow_pending:
            for name, value in identities.items():
                if not isinstance(value, str) or not LIVE_IDENTITY_PATTERNS[name].fullmatch(value):
                    raise HarnessError(f"live identity {name} does not match its exact identity contract")
        if re.search(r"REPLACE|PENDING|TBD|UNKNOWN", plan["session_id"], re.IGNORECASE) and not allow_pending:
            raise HarnessError("live session_id is unresolved")
    problem = plan.get("problem")
    if not isinstance(problem, dict) or set(problem) != {"id", "text"} or not isinstance(problem.get("id"), str) or not isinstance(problem.get("text"), str):
        raise HarnessError("problem must provide string id and text values")
    if not problem["id"].strip() or not problem["text"].strip():
        raise HarnessError("problem id and text must not be empty")
    contract = plan.get("execution_contract")
    if not isinstance(contract, dict) or set(contract) != {"bindings"}:
        raise HarnessError("execution_contract must contain only bindings")
    binding_specs = contract.get("bindings") if isinstance(contract, dict) else None
    if not isinstance(binding_specs, dict) or not binding_specs:
        raise HarnessError("execution_contract.bindings must be a non-empty object")
    for name, spec in binding_specs.items():
        if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or not isinstance(spec, dict):
            raise HarnessError(f"invalid trusted binding declaration: {name!r}")
        kind = spec.get("kind")
        if kind not in {"executable", "interpreter", "script"}:
            raise HarnessError(f"invalid trusted binding kind for {name}: {kind!r}")
        expected_spec_keys = {"kind", "sha256", "app_dependency_free", "review_evidence"}
        if kind == "interpreter":
            expected_spec_keys |= {"interpreter_family", "allowed_script_bindings"}
        if set(spec) != expected_spec_keys:
            raise HarnessError(f"trusted binding {name} must contain only its closed kind-specific fields")
        expected_hash = spec.get("sha256")
        if expected_hash == "capture-at-run":
            if mode != "fixture":
                raise HarnessError(f"live trusted binding {name} requires an exact SHA-256")
        elif mode == "live" and allow_pending and isinstance(expected_hash, str) and re.search(r"REPLACE|PENDING|TBD|UNKNOWN", expected_hash, re.IGNORECASE):
            pass
        elif not isinstance(expected_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_hash):
            raise HarnessError(f"trusted binding {name} requires an exact SHA-256")
        if spec.get("app_dependency_free") is not True or not isinstance(spec.get("review_evidence"), str) or not spec["review_evidence"].strip():
            raise HarnessError(f"trusted binding {name} requires app_dependency_free=true and review_evidence")
        if mode == "live" and not allow_pending and re.search(r"REPLACE|PENDING|TBD|UNKNOWN", spec["review_evidence"], re.IGNORECASE):
            raise HarnessError(f"trusted binding {name} review evidence is unresolved")
        if mode == "live" and not allow_pending and not re.fullmatch(r"WP-[1-9][0-9]*:sha256:[0-9a-f]{64}", spec["review_evidence"]):
            raise HarnessError(f"trusted binding {name} review evidence must bind one exact work product")
        allowed_scripts = spec.get("allowed_script_bindings", [])
        if kind == "interpreter" and (not isinstance(allowed_scripts, list) or not allowed_scripts or not all(isinstance(item, str) for item in allowed_scripts)):
            raise HarnessError(f"interpreter binding {name} requires allowed_script_bindings")
        if kind == "interpreter" and spec.get("interpreter_family") not in INTERPRETER_FAMILY_PATTERNS:
            raise HarnessError(f"interpreter binding {name} requires a supported interpreter_family")
    commands = plan.get("commands")
    if not isinstance(commands, list) or not commands:
        raise HarnessError("commands must be a non-empty list")
    seen_ids: set[str] = set()
    used_bindings: set[str] = set()
    stage_positions: list[int] = []
    for row in commands:
        if not isinstance(row, dict):
            raise HarnessError("each command must be an object")
        if not set(row).issubset(COMMAND_KEYS):
            raise HarnessError("each command must contain only the closed command fields")
        command_id = row.get("id")
        stage = row.get("stage")
        argv = row.get("argv")
        if not isinstance(command_id, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", command_id) or command_id in seen_ids:
            raise HarnessError(f"command id must be unique and filesystem-safe: {command_id!r}")
        seen_ids.add(command_id)
        if stage not in STAGE_ORDER:
            raise HarnessError(f"unknown stage for {command_id}: {stage!r}")
        stage_positions.append(STAGE_ORDER.index(stage))
        if not isinstance(argv, list) or not argv or not all(isinstance(part, str) and part for part in argv):
            raise HarnessError(f"argv must be a non-empty string array for {command_id}")
        if contains_app_dependency(tuple(argv)):
            raise HarnessError(f"app dependency is forbidden in command {command_id}")
        executable_match = re.fullmatch(r"\{([a-z][a-z0-9_]*)\}", argv[0])
        if not executable_match or executable_match.group(1) not in binding_specs:
            raise HarnessError(f"command {command_id} argv[0] must be one declared trusted binding placeholder")
        executable_name = executable_match.group(1)
        executable_spec = binding_specs[executable_name]
        if executable_spec["kind"] == "script":
            raise HarnessError(f"command {command_id} cannot execute a script binding without its trusted interpreter")
        if executable_spec["kind"] == "interpreter":
            if len(argv) < 2 or argv[1] in INTERPRETER_INLINE_FLAGS:
                raise HarnessError(f"command {command_id} must invoke a declared script, not inline interpreter code")
            script_match = re.fullmatch(r"\{([a-z][a-z0-9_]*)\}", argv[1])
            allowed_scripts = executable_spec["allowed_script_bindings"]
            if not script_match or script_match.group(1) not in allowed_scripts or binding_specs.get(script_match.group(1), {}).get("kind") != "script":
                raise HarnessError(f"command {command_id} interpreter target is not an allowed trusted script binding")
        placeholders: set[str] = set()
        for argument in argv:
            try:
                parsed = tuple(string.Formatter().parse(argument))
            except ValueError as exc:
                raise HarnessError(f"command {command_id} has malformed placeholder syntax") from exc
            for _, field_name, format_spec, conversion in parsed:
                if field_name is None:
                    continue
                if not re.fullmatch(r"[a-z][a-z0-9_]*", field_name) or format_spec or conversion:
                    raise HarnessError(f"command {command_id} has non-canonical placeholder syntax")
                placeholders.add(field_name)
        unknown_placeholders = placeholders - BUILTIN_BINDINGS - set(binding_specs)
        if unknown_placeholders:
            raise HarnessError(f"command {command_id} has undeclared bindings: {', '.join(sorted(unknown_placeholders))}")
        used_bindings.update(placeholders & set(binding_specs))
        expected = row.get("expected_exit_codes", [0])
        if not isinstance(expected, list) or not expected or not all(isinstance(code, int) and not isinstance(code, bool) for code in expected):
            raise HarnessError(f"expected_exit_codes must be an integer array for {command_id}")
        timeout = row.get("timeout_seconds", 300)
        if not isinstance(timeout, int) or isinstance(timeout, bool) or not 1 <= timeout <= 3600:
            raise HarnessError(f"timeout_seconds must be an integer from 1 to 3600 for {command_id}")
        policy = row.get("mutation_policy", "any")
        if policy not in {"project-required", "project-forbidden"}:
            raise HarnessError(f"unknown mutation_policy for {command_id}")
        mutation_paths = row.get("project_mutation_paths", [])
        if not isinstance(mutation_paths, list) or not all(isinstance(item, str) for item in mutation_paths):
            raise HarnessError(f"project_mutation_paths must contain strings for {command_id}")
        for mutation_path in mutation_paths:
            validate_relative_path(mutation_path, field="project mutation path")
        if policy == "project-required" and not mutation_paths:
            raise HarnessError(f"project-required command {command_id} must declare project_mutation_paths")
        if policy == "project-forbidden" and mutation_paths:
            raise HarnessError(f"project-forbidden command {command_id} cannot declare project_mutation_paths")
        for field in ("evidence_paths", "preserve_paths"):
            values = row.get(field, [])
            if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
                raise HarnessError(f"{field} must contain strings for {command_id}")
            for value in values:
                validate_relative_path(value, field=field)
    if stage_positions != sorted(stage_positions):
        raise HarnessError("commands must follow the required journey stage order")
    missing_stages = [stage for stage in STAGE_ORDER if stage not in {row["stage"] for row in commands}]
    if missing_stages:
        raise HarnessError(f"plan omits required stages: {', '.join(missing_stages)}")
    if used_bindings != set(binding_specs):
        raise HarnessError("every trusted binding declaration must be used by an explicit placeholder")
    if mode == "live" and not allow_pending and re.search(r"REPLACE|PENDING|TBD|UNKNOWN", json.dumps(plan, ensure_ascii=False), re.IGNORECASE):
        raise HarnessError("live plan contains an unresolved placeholder")


def clean_env(root: Path) -> dict[str, str]:
    home = root / "home"
    env = {key: os.environ[key] for key in ALLOWED_INHERITED_ENV if os.environ.get(key)}
    env.update(
        {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "XDG_DATA_HOME": str(home / ".local" / "share"),
            "CLAUDE_CONFIG_DIR": str(home / ".claude"),
            "CODEX_HOME": str(home / ".codex"),
            "GNUPGHOME": str(home / ".gnupg"),
            "GIT_CONFIG_GLOBAL": str(home / ".gitconfig"),
            "TMPDIR": str(root / "tmp"),
            "CLEAN_JOURNEY_ROOT": str(root),
            "CLEAN_JOURNEY_HOME": str(home),
            "CLEAN_JOURNEY_PROJECT": str(root / "project"),
            "CLEAN_JOURNEY_EVIDENCE": str(root / "evidence"),
        }
    )
    return env


def resolve_execution_bindings(plan: dict[str, Any], bindings: dict[str, str]) -> tuple[dict[str, str], dict[str, dict[str, Any]], str]:
    specs = plan["execution_contract"]["bindings"]
    if set(bindings) != set(specs):
        missing = sorted(set(specs) - set(bindings))
        extra = sorted(set(bindings) - set(specs))
        raise HarnessError(f"trusted bindings must match the plan exactly; missing={missing}, extra={extra}")
    resolved_values: dict[str, str] = {}
    identities: dict[str, dict[str, Any]] = {}
    for name, spec in sorted(specs.items()):
        supplied = Path(bindings[name]).expanduser()
        if not supplied.is_absolute():
            raise HarnessError(f"trusted binding {name} must be an absolute path")
        if not supplied.exists() or not supplied.is_file():
            raise HarnessError(f"trusted binding {name} is not a file")
        resolved = supplied.resolve(strict=True)
        basename = resolved.name.lower()
        if basename in FORBIDDEN_DISPATCHER_NAMES and spec["kind"] != "script":
            raise HarnessError(f"environment/command dispatcher is forbidden for trusted binding {name}")
        if contains_app_dependency((str(supplied), str(resolved))):
            raise HarnessError(f"app dependency is forbidden in trusted binding {name}")
        if spec["kind"] in {"executable", "interpreter"} and not os.access(resolved, os.X_OK):
            raise HarnessError(f"trusted binding {name} is not executable")
        if spec["kind"] == "interpreter" and not INTERPRETER_FAMILY_PATTERNS[spec["interpreter_family"]].fullmatch(basename):
            raise HarnessError(f"trusted binding {name} does not match its declared interpreter family")
        recognized_interpreter = any(pattern.fullmatch(basename) for pattern in INTERPRETER_FAMILY_PATTERNS.values()) or KNOWN_INTERPRETER_NAMES.fullmatch(basename)
        if recognized_interpreter and spec["kind"] != "interpreter":
            raise HarnessError(f"trusted binding {name} is an interpreter and must use the interpreter contract")
        with resolved.open("rb") as handle:
            has_shebang = handle.read(2) == b"#!"
        if spec["kind"] == "executable" and has_shebang:
            raise HarnessError(f"trusted binding {name} is a script and must use an exact declared interpreter")
        actual_hash = sha256_file(resolved)
        expected_hash = spec["sha256"]
        if expected_hash != "capture-at-run" and actual_hash != expected_hash:
            raise HarnessError(f"trusted binding {name} SHA-256 mismatch")
        resolved_values[name] = str(resolved)
        identities[name] = {
            "kind": spec["kind"],
            "resolved_path": str(resolved),
            "sha256": actual_hash,
            "app_dependency_free": True,
            "review_evidence": spec["review_evidence"],
        }
    digest = sha256_bytes(canonical_json(identities))
    return resolved_values, identities, digest


def substitute(value: str, root: Path, bindings: dict[str, str]) -> str:
    builtins = {
        "root": str(root),
        "home": str(root / "home"),
        "project": str(root / "project"),
        "evidence": str(root / "evidence"),
    }
    values = {**builtins, **bindings}
    try:
        return value.format_map(values)
    except KeyError as exc:
        raise HarnessError(f"missing command binding: {exc.args[0]}") from exc


def display_arg(value: str, root: Path) -> str:
    rendered = value.replace(str(root / "project"), "$CLEAN_PROJECT")
    rendered = rendered.replace(str(root / "evidence"), "$CLEAN_EVIDENCE")
    rendered = rendered.replace(str(root / "home"), "$CLEAN_HOME")
    return rendered.replace(str(root), "$CLEAN_ROOT")


def layout_identity(root: Path) -> dict[str, dict[str, int]]:
    result: dict[str, dict[str, int]] = {}
    for relative in ("home", "project", "evidence", "evidence/commands", "tmp"):
        path = root / relative
        if path.is_symlink() or not path.is_dir() or path.resolve() != path:
            raise HarnessError(f"isolated layout path is not a real in-root directory: {relative}")
        path_stat = path.stat()
        if path_stat.st_uid != os.getuid():
            raise HarnessError(f"isolated layout path has an unexpected owner: {relative}")
        result[relative] = {"device": path_stat.st_dev, "inode": path_stat.st_ino, "owner_uid": path_stat.st_uid}
    return result


def initialize_root(root: Path, plan: dict[str, Any], plan_digest: str, execution_digest: str) -> dict[str, Any]:
    home = root / "home"
    project = root / "project"
    evidence = root / "evidence"
    for path in (home, project, evidence, evidence / "commands", root / "tmp", home / ".config", home / ".cache", home / ".local" / "share", home / ".claude", home / ".codex", home / ".gnupg"):
        path.mkdir(parents=True, mode=0o700, exist_ok=True)
    (project / "problem.md").write_text(plan["problem"]["text"].rstrip() + "\n", encoding="utf-8")
    root_stat = root.stat()
    nonce = secrets.token_hex(32)
    marker = {
        "schema_version": SCHEMA_VERSION,
        "session_id": plan["session_id"],
        "plan_sha256": plan_digest,
        "execution_bindings_sha256": execution_digest,
        "root_path": str(root),
        "root_device": root_stat.st_dev,
        "root_inode": root_stat.st_ino,
        "owner_uid": root_stat.st_uid,
        "layout": layout_identity(root),
        "run_nonce": nonce,
        "created_unix": int(time.time()),
    }
    marker["seal_sha256"] = sha256_bytes(canonical_json(marker))
    write_json(root / ".clean-journey-root.json", marker)
    os.chmod(root / ".clean-journey-root.json", 0o600)
    state = {
        "schema_version": SCHEMA_VERSION,
        "session_id": plan["session_id"],
        "plan_sha256": plan_digest,
        "execution_bindings_sha256": execution_digest,
        "run_nonce": nonce,
        "next_command_index": 0,
        "previous_record_sha256": None,
        "status": "prepared",
    }
    write_state(root, state)
    return state


def state_payload(state: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in state.items() if key != "seal_sha256"}


def write_state(root: Path, state: dict[str, Any]) -> None:
    sealed = dict(state_payload(state))
    sealed["seal_sha256"] = sha256_bytes(canonical_json(sealed))
    write_json(root / "evidence" / "state.json", sealed)


def read_state(root: Path) -> dict[str, Any]:
    state = read_json(root / "evidence" / "state.json")
    actual = state.get("seal_sha256")
    expected = sha256_bytes(canonical_json(state_payload(state)))
    if actual != expected:
        raise HarnessError("resume state seal mismatch")
    return state


def validate_marker(root: Path, marker: dict[str, Any], plan: dict[str, Any], plan_digest: str, execution_digest: str) -> None:
    marker_payload = {key: value for key, value in marker.items() if key != "seal_sha256"}
    if marker.get("seal_sha256") != sha256_bytes(canonical_json(marker_payload)):
        raise HarnessError("isolated root ownership marker seal mismatch")
    root_stat = root.stat()
    expected = {
        "schema_version": SCHEMA_VERSION,
        "session_id": plan["session_id"],
        "plan_sha256": plan_digest,
        "execution_bindings_sha256": execution_digest,
        "root_path": str(root),
        "root_device": root_stat.st_dev,
        "root_inode": root_stat.st_ino,
        "owner_uid": os.getuid(),
    }
    for key, value in expected.items():
        if marker.get(key) != value:
            raise HarnessError(f"isolated root ownership marker mismatch: {key}")
    if not isinstance(marker.get("run_nonce"), str) or not re.fullmatch(r"[0-9a-f]{64}", marker["run_nonce"]):
        raise HarnessError("isolated root ownership marker has an invalid nonce")
    if marker.get("layout") != layout_identity(root):
        raise HarnessError("isolated root layout identity changed")


def validate_state_identity(state: dict[str, Any], marker: dict[str, Any], plan: dict[str, Any], plan_digest: str, execution_digest: str) -> None:
    expected = {
        "schema_version": SCHEMA_VERSION,
        "session_id": plan["session_id"],
        "plan_sha256": plan_digest,
        "execution_bindings_sha256": execution_digest,
        "run_nonce": marker["run_nonce"],
    }
    for key, value in expected.items():
        if state.get(key) != value:
            raise HarnessError(f"resume state identity mismatch: {key}")
    index = state.get("next_command_index")
    if not isinstance(index, int) or isinstance(index, bool) or not 0 <= index <= len(plan["commands"]):
        raise HarnessError("resume state has an invalid command index")


def preserved_hashes(root: Path, paths: list[str]) -> dict[str, str | None]:
    result: dict[str, str | None] = {}
    for relative in paths:
        candidate = resolve_inside(root, relative)
        if candidate.is_file() and not candidate.is_symlink():
            result[relative] = sha256_file(candidate)
        elif candidate.exists() or candidate.is_symlink():
            result[relative] = tree_digest(candidate) if candidate.is_dir() else sha256_bytes(os.readlink(candidate).encode())
        else:
            result[relative] = None
    return result


def artifact_hashes(root: Path, paths: list[str]) -> dict[str, str | None]:
    result: dict[str, str | None] = {}
    for relative in paths:
        artifact = resolve_inside(root, relative)
        result[relative] = sha256_file(artifact) if artifact.is_file() and not artifact.is_symlink() else None
    return result


def mutation_allowed(path: str, declared: list[str]) -> bool:
    for allowed in declared:
        if path == allowed or path.startswith(allowed + "/") or allowed.startswith(path + "/"):
            return True
    return False


def execute_process(argv: list[str], *, cwd: Path, env: dict[str, str], timeout_seconds: int) -> tuple[int, str, str, bool]:
    process = subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
        return process.returncode, stdout, stderr, False
    except subprocess.TimeoutExpired as exc:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        partial_stdout = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        partial_stderr = exc.stderr.decode(errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        if stdout and not stdout.startswith(partial_stdout):
            partial_stdout += stdout
        if stderr and not stderr.startswith(partial_stderr):
            partial_stderr += stderr
        return 124, partial_stdout, partial_stderr, True


def verify_execution_bindings(plan: dict[str, Any], original_bindings: dict[str, str], expected_digest: str) -> tuple[dict[str, str], dict[str, dict[str, Any]]]:
    resolved, identities, actual_digest = resolve_execution_bindings(plan, original_bindings)
    if actual_digest != expected_digest:
        raise HarnessError("trusted execution binding identity changed")
    return resolved, identities


def run_command(root: Path, plan: dict[str, Any], command: dict[str, Any], index: int, bindings: dict[str, str], binding_identities: dict[str, dict[str, Any]], execution_digest: str, marker: dict[str, Any], previous_record_sha256: str | None) -> tuple[dict[str, Any], str]:
    argv = [substitute(part, root, bindings) for part in command["argv"]]
    if detect_secret("\n".join(argv)):
        raise HarnessError(f"command {command['id']} contains suspected secret material in resolved argv")
    if contains_app_dependency(tuple(argv)):
        raise HarnessError(f"resolved command contains an app dependency: {command['id']}")
    executable_binding = re.fullmatch(r"\{([a-z][a-z0-9_]*)\}", command["argv"][0]).group(1)
    invoked_bindings = [executable_binding]
    if binding_identities[executable_binding]["kind"] == "interpreter":
        script_binding = re.fullmatch(r"\{([a-z][a-z0-9_]*)\}", command["argv"][1]).group(1)
        invoked_bindings.append(script_binding)
    project = root / "project"
    project_before_manifest = tree_manifest(project)
    project_before = sha256_bytes(canonical_json(project_before_manifest))
    preserved_before = preserved_hashes(root, command.get("preserve_paths", []))
    evidence_before = artifact_hashes(root, command.get("evidence_paths", []))
    started = time.time()
    exit_code, stdout, stderr, timed_out = execute_process(argv, cwd=project, env=clean_env(root), timeout_seconds=command.get("timeout_seconds", 300))
    if marker.get("layout") != layout_identity(root):
        raise HarnessError(f"command {command['id']} changed the isolated root layout")
    current_marker = read_json(root / ".clean-journey-root.json")
    if current_marker != marker:
        raise HarnessError(f"command {command['id']} changed the isolated root ownership marker")
    secret_pattern = detect_secret(stdout + "\n" + stderr)
    if secret_pattern:
        stdout = "[SUPPRESSED: suspected secret material]"
        stderr = "[SUPPRESSED: suspected secret material]"
    artifact_secret_paths: list[str] = []
    for relative in command.get("evidence_paths", []):
        artifact = resolve_inside(root, relative)
        if artifact.is_file() and not artifact.is_symlink() and detect_file_secret(artifact):
            artifact.write_text("[SUPPRESSED: suspected secret material]\n", encoding="utf-8")
            artifact_secret_paths.append(relative)
    project_after_manifest = tree_manifest(project)
    project_after = sha256_bytes(canonical_json(project_after_manifest))
    changed_paths = changed_tree_paths(project_before_manifest, project_after_manifest)
    preserved_after = preserved_hashes(root, command.get("preserve_paths", []))
    evidence_after = artifact_hashes(root, command.get("evidence_paths", []))
    missing_evidence: list[str] = []
    stale_evidence: list[str] = []
    artifact_secret = bool(artifact_secret_paths)
    evidence_artifacts = []
    for relative in command.get("evidence_paths", []):
        artifact = resolve_inside(root, relative)
        if not artifact.is_file() or artifact.is_symlink():
            missing_evidence.append(relative)
        else:
            if evidence_before[relative] == evidence_after[relative]:
                stale_evidence.append(relative)
            evidence_artifacts.append({"path": relative, "sha256": sha256_file(artifact), "size": artifact.stat().st_size})
    policy = command["mutation_policy"]
    violations: list[str] = []
    if timed_out:
        violations.append("command timed out")
    if exit_code not in command.get("expected_exit_codes", [0]):
        violations.append(f"unexpected exit code {exit_code}")
    if policy == "project-required" and not changed_paths:
        violations.append("project was required to change but did not")
    if policy == "project-forbidden" and changed_paths:
        violations.append("project changed despite project-forbidden policy")
    undeclared_changes = [path for path in changed_paths if not mutation_allowed(path, command.get("project_mutation_paths", []))]
    if policy == "project-required" and undeclared_changes:
        violations.append(f"project changed outside declared mutation paths: {', '.join(undeclared_changes)}")
    if preserved_before != preserved_after:
        changed = sorted(key for key in preserved_before if preserved_before[key] != preserved_after[key])
        violations.append(f"preserved paths changed: {', '.join(changed)}")
    if missing_evidence:
        violations.append(f"missing evidence: {', '.join(missing_evidence)}")
    if stale_evidence:
        violations.append(f"evidence was not created or changed by this command: {', '.join(stale_evidence)}")
    if secret_pattern:
        violations.append("suspected secret material appeared in command output")
    if artifact_secret:
        violations.append(f"suspected secret material appeared in evidence artifacts and was suppressed: {', '.join(artifact_secret_paths)}")
    record = {
        "schema_version": SCHEMA_VERSION,
        "session_id": plan["session_id"],
        "plan_sha256": sha256_bytes(canonical_json(plan)),
        "execution_bindings_sha256": execution_digest,
        "run_nonce": marker["run_nonce"],
        "command_index": index,
        "command_id": command["id"],
        "stage": command["stage"],
        "argv": [display_arg(part, root) for part in argv],
        "invoked_binding_identities": {name: binding_identities[name] for name in invoked_bindings},
        "cwd": "$CLEAN_PROJECT",
        "expected_exit_codes": command.get("expected_exit_codes", [0]),
        "exit_code": exit_code,
        "timed_out": timed_out,
        "duration_ms": round((time.time() - started) * 1000),
        "stdout": stdout,
        "stderr": stderr,
        "project_tree_before_sha256": project_before,
        "project_tree_after_sha256": project_after,
        "project_changed_paths": changed_paths,
        "declared_project_mutation_paths": command.get("project_mutation_paths", []),
        "preserved_before": preserved_before,
        "preserved_after": preserved_after,
        "evidence_artifacts": evidence_artifacts,
        "secret_scan": "pass" if not secret_pattern and not artifact_secret else "fail-output-suppressed" if secret_pattern else "fail-artifact",
        "app_dependency_scan": "pass-exact-reviewed-bindings",
        "previous_record_sha256": previous_record_sha256,
        "violations": violations,
        "result": "pass" if not violations else "fail",
    }
    record_path = root / "evidence" / "commands" / f"{index:02d}-{command['id']}.json"
    write_json(record_path, record)
    record_sha256 = sha256_file(record_path)
    if violations:
        raise HarnessError(f"command {command['id']} failed evidence contract: {'; '.join(violations)}")
    return record, record_sha256


def verify_record_prefix(root: Path, plan: dict[str, Any], state: dict[str, Any], marker: dict[str, Any], execution_digest: str) -> list[dict[str, str]]:
    next_index = state["next_command_index"]
    commands_dir = root / "evidence" / "commands"
    expected_paths = [commands_dir / f"{index:02d}-{plan['commands'][index]['id']}.json" for index in range(next_index)]
    actual_paths = sorted(commands_dir.iterdir())
    if actual_paths != expected_paths:
        raise HarnessError("evidence record set does not exactly match the executed plan prefix")
    previous = None
    records: list[dict[str, str]] = []
    for index, path in enumerate(expected_paths):
        record = read_json(path)
        command = plan["commands"][index]
        expected_fields = {
            "schema_version": SCHEMA_VERSION,
            "session_id": plan["session_id"],
            "plan_sha256": state["plan_sha256"],
            "execution_bindings_sha256": execution_digest,
            "run_nonce": marker["run_nonce"],
            "command_index": index,
            "command_id": command["id"],
            "stage": command["stage"],
            "previous_record_sha256": previous,
            "result": "pass",
        }
        for key, value in expected_fields.items():
            if record.get(key) != value:
                raise HarnessError(f"evidence chain mismatch at {path.name}: {key}")
        previous = sha256_file(path)
        records.append({"path": path.relative_to(root).as_posix(), "sha256": previous})
    if previous != state.get("previous_record_sha256"):
        raise HarnessError("state does not point at the evidence-chain head")
    return records


def build_final_manifest(root: Path, plan: dict[str, Any], state: dict[str, Any], marker: dict[str, Any], execution_identities: dict[str, dict[str, Any]], execution_digest: str) -> dict[str, Any]:
    records = verify_record_prefix(root, plan, state, marker, execution_digest)
    declared_artifacts = []
    for relative in sorted({path for command in plan["commands"][: state["next_command_index"]] for path in command.get("evidence_paths", [])}):
        artifact = resolve_inside(root, relative)
        if not artifact.is_file() or artifact.is_symlink():
            raise HarnessError(f"declared evidence artifact is no longer a regular file: {relative}")
        if detect_file_secret(artifact):
            raise HarnessError(f"declared evidence artifact contains suspected secret material: {relative}")
        declared_artifacts.append({"path": relative, "sha256": sha256_file(artifact), "size": artifact.stat().st_size})
    return {
        "schema_version": SCHEMA_VERSION,
        "session_id": plan["session_id"],
        "run_nonce": marker["run_nonce"],
        "mode": plan["mode"],
        "result": state["status"],
        "plan_sha256": state["plan_sha256"],
        "state_seal_sha256": state["seal_sha256"],
        "execution_bindings_sha256": execution_digest,
        "execution_bindings": execution_identities,
        "identities": plan["identities"],
        "problem": {"id": plan["problem"]["id"], "sha256": sha256_file(root / "project" / "problem.md")},
        "prerequisites": plan["prerequisites"],
        "commands": records,
        "declared_evidence_artifacts": declared_artifacts,
        "evidence_chain_head_sha256": state["previous_record_sha256"],
        "project_tree_sha256": tree_digest(root / "project"),
        "home_tree_sha256": tree_digest(root / "home"),
        "control_tower_app_used": False,
        "app_dependency_proof": "literal-plan scan plus exact reviewed execution-binding hashes",
        "subprocess_executables": sorted({identity["resolved_path"] for identity in execution_identities.values() if identity["kind"] != "script"}),
        "environment_contract": {
            "isolated_home": "$CLEAN_HOME",
            "isolated_project": "$CLEAN_PROJECT",
            "isolated_xdg": True,
            "inherited_environment_allowlist": list(ALLOWED_INHERITED_ENV),
            "shell_inline_dispatch": "forbidden; exact interpreter-plus-script contract required",
            "inline_interpreter_execution": "forbidden",
            "stdin": "disabled",
            "timeout_process_group_kill": True,
        },
    }


def write_manifest(root: Path, manifest: dict[str, Any]) -> str:
    path = root / "evidence" / "manifest.json"
    write_json(path, manifest)
    return sha256_file(path)


def execute(plan_path: Path, root_path: Path | None, *, stop_after: str | None, bindings: dict[str, str], resume: bool, resume_anchor_sha256: str | None = None) -> dict[str, Any]:
    plan = read_json(plan_path)
    validate_plan(plan)
    plan_digest = sha256_bytes(canonical_json(plan))
    if resume:
        if root_path is None:
            raise HarnessError("--root is required when resuming")
        root = validate_root(root_path, allow_existing=True)
    else:
        root = validate_root(root_path, allow_existing=False) if root_path else validate_root(Path(tempfile.mkdtemp(prefix="copilot-clean-journey-")), allow_existing=True)
    resolved_bindings, execution_identities, execution_digest = resolve_execution_bindings(plan, bindings)
    if resume:
        marker = read_json(root / ".clean-journey-root.json")
        state = read_state(root)
        validate_marker(root, marker, plan, plan_digest, execution_digest)
        validate_state_identity(state, marker, plan, plan_digest, execution_digest)
        if state.get("status") != "paused":
            raise HarnessError(f"cannot resume a journey in state {state.get('status')!r}")
        verify_record_prefix(root, plan, state, marker, execution_digest)
        manifest_path = root / "evidence" / "manifest.json"
        if not isinstance(resume_anchor_sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", resume_anchor_sha256):
            raise HarnessError("resume requires the externally retained paused manifest SHA-256")
        if not manifest_path.is_file() or sha256_file(manifest_path) != resume_anchor_sha256:
            raise HarnessError("paused manifest does not match the external resume anchor")
        if read_json(manifest_path) != build_final_manifest(root, plan, state, marker, execution_identities, execution_digest):
            raise HarnessError("paused manifest does not match the sealed execution state")
        if manifest_path.exists():
            manifest_path.unlink()
    else:
        state = initialize_root(root, plan, plan_digest, execution_digest)
        marker = read_json(root / ".clean-journey-root.json")
    commands = plan["commands"]
    state["status"] = "running"
    write_state(root, state)
    try:
        for index in range(int(state["next_command_index"]), len(commands)):
            resolved_bindings, execution_identities = verify_execution_bindings(plan, bindings, execution_digest)
            command = commands[index]
            _, record_sha256 = run_command(root, plan, command, index, resolved_bindings, execution_identities, execution_digest, marker, state.get("previous_record_sha256"))
            verify_execution_bindings(plan, bindings, execution_digest)
            state["next_command_index"] = index + 1
            state["previous_record_sha256"] = record_sha256
            state["last_stage"] = command["stage"]
            if stop_after == command["stage"]:
                state["status"] = "paused"
                write_state(root, state)
                state = read_state(root)
                manifest = build_final_manifest(root, plan, state, marker, execution_identities, execution_digest)
                manifest_sha256 = write_manifest(root, manifest)
                return {"result": "paused", "root": str(root), "manifest": str(root / "evidence" / "manifest.json"), "manifest_sha256": manifest_sha256, "evidence_chain_head_sha256": state["previous_record_sha256"]}
            write_state(root, state)
    except Exception:
        state["status"] = "failed"
        write_state(root, state)
        raise
    state["status"] = "completed"
    write_state(root, state)
    state = read_state(root)
    manifest = build_final_manifest(root, plan, state, marker, execution_identities, execution_digest)
    manifest_sha256 = write_manifest(root, manifest)
    return {"result": "completed", "root": str(root), "manifest": str(root / "evidence" / "manifest.json"), "manifest_sha256": manifest_sha256, "evidence_chain_head_sha256": state["previous_record_sha256"]}


def parse_bindings(values: list[str]) -> dict[str, str]:
    bindings: dict[str, str] = {}
    for value in values:
        if "=" not in value:
            raise HarnessError(f"binding must be NAME=VALUE: {value!r}")
        name, bound = value.split("=", 1)
        if not re.fullmatch(r"[a-z][a-z0-9_]*", name):
            raise HarnessError(f"invalid binding name: {name!r}")
        if not bound:
            raise HarnessError(f"empty binding: {name!r}")
        if name in bindings:
            raise HarnessError(f"duplicate binding: {name!r}")
        bindings[name] = bound
    return bindings


def verify(root: Path, plan_path: Path, bindings: dict[str, str], expected_manifest_sha256: str | None = None) -> dict[str, Any]:
    root = validate_root(root, allow_existing=True)
    plan = read_json(plan_path)
    validate_plan(plan)
    plan_digest = sha256_bytes(canonical_json(plan))
    _, execution_identities, execution_digest = resolve_execution_bindings(plan, bindings)
    marker = read_json(root / ".clean-journey-root.json")
    state = read_state(root)
    validate_marker(root, marker, plan, plan_digest, execution_digest)
    validate_state_identity(state, marker, plan, plan_digest, execution_digest)
    if state.get("status") not in {"paused", "completed"}:
        raise HarnessError(f"journey state is not independently verifiable: {state.get('status')!r}")
    if state["status"] == "completed" and state["next_command_index"] != len(plan["commands"]):
        raise HarnessError("completed state does not cover every planned command")
    records = verify_record_prefix(root, plan, state, marker, execution_digest)
    manifest_path = root / "evidence" / "manifest.json"
    actual_manifest_sha256 = sha256_file(manifest_path)
    if plan["mode"] == "live":
        if not isinstance(expected_manifest_sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_manifest_sha256):
            raise HarnessError("live verification requires the externally retained final manifest SHA-256")
        if actual_manifest_sha256 != expected_manifest_sha256:
            raise HarnessError("final manifest does not match the external verification anchor")
    manifest = read_json(manifest_path)
    expected_manifest = build_final_manifest(root, plan, state, marker, execution_identities, execution_digest)
    if manifest != expected_manifest:
        raise HarnessError("manifest does not exactly match the sealed execution evidence")
    if manifest.get("control_tower_app_used") is not False:
        raise HarnessError("manifest does not prove the app was absent")
    return {"result": "verified", "status": state.get("status"), "records": len(records), "root": str(root), "manifest_sha256": actual_manifest_sha256, "evidence_chain_head_sha256": state["previous_record_sha256"]}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    check_parser = subparsers.add_parser("check-plan", help="validate a plan without executing it")
    check_parser.add_argument("--plan", type=Path, required=True)
    check_parser.add_argument("--allow-pending", action="store_true")
    run_parser = subparsers.add_parser("run", help="prepare an isolated root and execute a plan")
    run_parser.add_argument("--plan", type=Path, required=True)
    run_parser.add_argument("--root", type=Path)
    run_parser.add_argument("--stop-after", choices=STAGE_ORDER)
    run_parser.add_argument("--bind", action="append", default=[])
    resume_parser = subparsers.add_parser("resume", help="continue a sealed interrupted run")
    resume_parser.add_argument("--plan", type=Path, required=True)
    resume_parser.add_argument("--root", type=Path, required=True)
    resume_parser.add_argument("--stop-after", choices=STAGE_ORDER)
    resume_parser.add_argument("--bind", action="append", default=[])
    resume_parser.add_argument("--anchor-sha256", required=True)
    verify_parser = subparsers.add_parser("verify", help="verify the evidence chain and isolation manifest")
    verify_parser.add_argument("--plan", type=Path, required=True)
    verify_parser.add_argument("--root", type=Path, required=True)
    verify_parser.add_argument("--bind", action="append", default=[])
    verify_parser.add_argument("--expected-manifest-sha256")
    args = parser.parse_args(argv)
    try:
        if args.command == "check-plan":
            plan = read_json(args.plan)
            validate_plan(plan, allow_pending=args.allow_pending)
            result = {"result": "valid", "mode": plan["mode"], "pending_allowed": args.allow_pending}
        elif args.command == "run":
            result = execute(args.plan, args.root, stop_after=args.stop_after, bindings=parse_bindings(args.bind), resume=False)
        elif args.command == "resume":
            result = execute(args.plan, args.root, stop_after=args.stop_after, bindings=parse_bindings(args.bind), resume=True, resume_anchor_sha256=args.anchor_sha256)
        else:
            result = verify(args.root, args.plan, parse_bindings(args.bind), args.expected_manifest_sha256)
    except HarnessError as exc:
        print(json.dumps({"result": "blocked", "error": str(exc)}, sort_keys=True))
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
