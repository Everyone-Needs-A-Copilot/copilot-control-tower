"""configs.py — the 4-config ladder (TASK-125 / W-3).

Config isolation, verbatim from phase-4-outcome-program-prd.md par.3 W-3:
"bare = fresh dir, no framework files; +framework = claude-copilot install;
+knowledge = CC_KNOWLEDGE_REPO populated vs empty tree; +integrations =
cli-copilot on PATH with .env." Register-first (V-2): this file IS the
`ladder_config_materialization` definition claims.yaml points at.

DESIGN: two isolation levers, verified live against this machine's actual
installed `claude` CLI (`claude --help`, 2026-07-13) before writing any of
this, per this repo's "before calling a third-party API, check the real
docs/help for the installed version" rule:

  1. `--setting-sources project` (a REAL flag: "Comma-separated list of
     setting sources to load (user, project, local)") on every config,
     including bare. This is the actual isolation mechanism, not cwd
     alone: this dev machine already has claude-copilot installed at the
     user level (~/.claude/, ~/.local/bin/{tc,cc}), so cwd-only isolation
     (an empty directory) would still risk inheriting USER-scope
     CLAUDE.md/agents/settings the same way ../resume_cost/run.py's design
     notes describe a tool-enabled model reaching a real fixture that
     happened to exist elsewhere on the same host ("this dev machine is
     not a clean room"). `--setting-sources project` closes that path
     structurally: only the job workdir's OWN `.claude/` (materialized or
     absent, per config) is ever loaded, regardless of what this machine's
     real user-level ~/.claude contains.
  2. A per-config PATH override. `tc`/`cc` live at a single directory on
     this machine (LOCAL_BIN, resolved via `command -v tc`/`command -v cc`
     while building this bench — both resolve to ~/.local/bin) and
     cli-copilot's `copilot` entry point lives in its own venv
     (CLI_COPILOT_VENV_BIN, verified via `<venv>/bin/copilot --help`,
     since no `copilot` binary is installed anywhere else on this machine
     — `/opt/homebrew/bin/copilot` named in ../../../README.md and
     ../mcp_twin/run.py does NOT exist here, an honest environment gap
     recorded in warnings[] below rather than silently worked around).
     `bare` and `+framework` PATH excludes both; `+knowledge` still
     excludes the cli-copilot venv bin; `+integrations` includes it.

HOME is also overridden, uniformly across all 4 configs, to a fresh
per-ladder-run temp directory. This is NOT part of the PRD's config
isolation spec — it exists so a live run's `claude -p` calls write their
session transcripts under an isolated HOME's `~/.claude/projects/` rather
than this machine's REAL transcript corpus, which several OTHER collectors
(framework_soul's agent-frugality distribution, transcripts.py) already
read as production data. Mixing synthetic ladder-bench transcripts into
that corpus would silently contaminate those other claims. See README.md
"Open risk before the first live run" for the one thing this does NOT
verify: whether an isolated HOME still resolves Anthropic auth (OAuth
token / keychain) the same way the real HOME does — untested here,
deliberately not asserted as fact.

Every materialize_*() function is idempotent and side-effect-scoped to the
run_root directory it is given (never touches this repo, ~/.claude, or
~/.local/bin) — safe to call during --dry-run.
"""
from __future__ import annotations

import json
import os
import shutil
from dataclasses import dataclass, field
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

COPILOT_ROOT = Path(os.environ.get("COPILOT_ROOT", "/Users/pabs/Sites/COPILOT"))
CLAUDE_COPILOT_ROOT = Path(os.environ.get("CLAUDE_COPILOT_ROOT", str(COPILOT_ROOT / "claude-copilot")))
KNOWLEDGE_COPILOT_ROOT = Path(os.environ.get("CC_KNOWLEDGE_REPO_REAL", str(COPILOT_ROOT / "knowledge-copilot")))
CLI_COPILOT_ROOT = Path(os.environ.get("CLI_COPILOT_ROOT", str(COPILOT_ROOT / "cli-copilot")))
CLI_COPILOT_VENV_BIN = CLI_COPILOT_ROOT / ".venv313" / "bin"
LOCAL_BIN = Path(os.environ.get("CC_TC_LOCAL_BIN", str(Path.home() / ".local" / "bin")))

# The literal flag every config uses (see module docstring, lever 1).
COMMON_CLAUDE_FLAGS = ["--setting-sources", "project"]


@dataclass
class MaterializedConfig:
    name: str
    workdir: Path
    home_dir: Path
    env: dict
    claude_flags: list
    notes: list = field(default_factory=list)
    warnings: list = field(default_factory=list)

    def env_summary(self) -> dict:
        """A redacted-safe summary for audit-trail JSON: PATH and the
        handful of named vars this bench sets are not secrets, but any
        real KEY=VALUE pairs pulled from cli-copilot's .env (integrations
        config only) are — never write those values into output/."""
        redacted_env = {
            k: (v if k not in self._env_file_keys else "<redacted, see .env source file>")
            for k, v in self.env.items()
        }
        return {
            "PATH": redacted_env.get("PATH"),
            "HOME": redacted_env.get("HOME"),
            "CC_KNOWLEDGE_REPO": redacted_env.get("CC_KNOWLEDGE_REPO"),
            "env_var_names": sorted(self.env.keys()),
            "dotenv_keys_loaded": sorted(self._env_file_keys),
        }

    _env_file_keys: set = field(default_factory=set)


def _minimal_system_path() -> str:
    """A deliberately small PATH: system dirs plus wherever THIS machine's
    python3 actually resolves (found via shutil.which, not hardcoded — every
    job pack job needs to run python3; nothing else is assumed)."""
    system_dirs = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    python3 = shutil.which("python3")
    extra = [str(Path(python3).parent)] if python3 else []
    return ":".join(dict.fromkeys(extra + system_dirs))  # dedupe, preserve order


def _fresh_home(run_root: Path, config_name: str) -> Path:
    home = run_root / "homes" / config_name
    home.mkdir(parents=True, exist_ok=True)
    return home


def _copy_framework_files(workdir: Path, job_id: str, warnings: list) -> None:
    """Replicates the essential file-copy steps of claude-copilot's own
    `/setup-project` FULL-mode flow (.claude/commands/setup-project.md
    Steps 4-7), directly in Python rather than by running that slash
    command inside a live session — running it live would itself spend
    model calls this harness is trying to measure the MARGINAL cost of a
    job on top of, not the one-time per-project setup cost (see module
    docstring's O-1 framing: the ladder isolates the job's own cost, with
    the framework already installed, same as a real project's second and
    subsequent solutions)."""
    version_json = CLAUDE_COPILOT_ROOT / "VERSION.json"
    if not version_json.is_file():
        warnings.append(f"CLAUDE_COPILOT_ROOT/VERSION.json not found at {version_json}; +framework materialization skipped")
        return
    version = json.loads(version_json.read_text())

    agents_dir = workdir / ".claude" / "agents"
    commands_dir = workdir / ".claude" / "commands"
    skills_dir = workdir / ".claude" / "skills"
    agents_dir.mkdir(parents=True, exist_ok=True)
    commands_dir.mkdir(parents=True, exist_ok=True)

    roster = version.get("components", {}).get("agents", {}).get("frameworkAgents", [])
    src_agents = CLAUDE_COPILOT_ROOT / ".claude" / "agents"
    for agent in roster:
        src = src_agents / f"{agent}.md"
        if src.is_file():
            shutil.copy2(src, agents_dir / f"{agent}.md")
        else:
            warnings.append(f"framework agent {agent!r} listed in VERSION.json but {src} not found")

    project_commands = version.get("components", {}).get("commands", {}).get("projectCommands", [])
    src_commands = CLAUDE_COPILOT_ROOT / ".claude" / "commands"
    for cmd in project_commands:
        src = src_commands / cmd
        if src.is_file():
            shutil.copy2(src, commands_dir / cmd)

    src_skills = CLAUDE_COPILOT_ROOT / "templates" / "skills"
    if src_skills.is_dir():
        shutil.copytree(src_skills, skills_dir, dirs_exist_ok=True)

    template = CLAUDE_COPILOT_ROOT / "templates" / "CLAUDE.template.md"
    if template.is_file():
        text = template.read_text()
        text = text.replace("{{PROJECT_NAME}}", f"cse-bench-ladder-{job_id}")
        text = text.replace("{{PROJECT_DESCRIPTION}}", "cse-bench ladder harness job (TASK-125 / W-3) -- synthetic, not a real project")
        text = text.replace("{{TECH_STACK}}", "Python (stdlib)")
        (workdir / "CLAUDE.md").write_text(text)

    (workdir / ".mcp.json").write_text('{"mcpServers":{}}\n')


def _empty_knowledge_tree(run_root: Path) -> Path:
    """The +framework rung's knowledge-side control: an EMPTY directory
    (not merely an unset env var), so the +knowledge rung's ablation is
    "content vs. no content," not "mechanism present vs. absent" — per
    PRD par.3 W-3's own phrasing, "+knowledge = CC_KNOWLEDGE_REPO populated
    vs empty tree.\""""
    empty = run_root / "empty-knowledge-tree"
    empty.mkdir(parents=True, exist_ok=True)
    return empty


def _parse_dotenv(path: Path) -> dict:
    """Minimal KEY=VALUE .env parser: skips blank lines and '#' comments,
    strips surrounding quotes. copilot_cli itself does not call
    load_dotenv/find_dotenv anywhere in its source (checked directly,
    2026-07-13) -- so ".env on PATH" for the +integrations config means
    THIS bench exports the file's key/value pairs into the job's
    subprocess env explicitly; cwd-based autoload cannot be assumed."""
    if not path.is_file():
        return {}
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            env[key] = value
    return env


def _new_workdir(run_root: Path, config_name: str, job_id: str) -> Path:
    workdir = run_root / "jobs" / job_id / config_name
    workdir.mkdir(parents=True, exist_ok=True)
    return workdir


def _base_env(home: Path, path_dirs: list) -> dict:
    return {
        "HOME": str(home),
        "PATH": ":".join(dict.fromkeys(path_dirs)),
    }


def materialize_bare(run_root: Path, job_id: str) -> MaterializedConfig:
    workdir = _new_workdir(run_root, "bare", job_id)
    home = _fresh_home(run_root, "bare")
    warnings: list = []
    env = _base_env(home, [_minimal_system_path()])
    return MaterializedConfig(
        name="bare",
        workdir=workdir,
        home_dir=home,
        env=env,
        claude_flags=list(COMMON_CLAUDE_FLAGS),
        notes=["fresh empty workdir, no .claude/, no CLAUDE.md, no tc/cc/copilot on PATH"],
        warnings=warnings,
    )


def materialize_framework(run_root: Path, job_id: str) -> MaterializedConfig:
    workdir = _new_workdir(run_root, "framework", job_id)
    home = _fresh_home(run_root, "framework")
    warnings: list = []
    _copy_framework_files(workdir, job_id, warnings)
    empty_knowledge = _empty_knowledge_tree(run_root)
    env = _base_env(home, [str(LOCAL_BIN), _minimal_system_path()])
    env["CC_KNOWLEDGE_REPO"] = str(empty_knowledge)
    if not LOCAL_BIN.is_dir():
        warnings.append(f"LOCAL_BIN {LOCAL_BIN} not found -- tc/cc will not actually be reachable even though PATH includes it")
    return MaterializedConfig(
        name="framework",
        workdir=workdir,
        home_dir=home,
        env=env,
        claude_flags=list(COMMON_CLAUDE_FLAGS),
        notes=[
            ".claude/{agents,commands,skills}/ + CLAUDE.md materialized from claude-copilot's own VERSION.json roster",
            f"tc/cc on PATH via {LOCAL_BIN}",
            f"CC_KNOWLEDGE_REPO points at an EMPTY tree ({empty_knowledge}), not unset -- isolates 'knowledge content' from 'knowledge mechanism present' (see _empty_knowledge_tree docstring)",
        ],
        warnings=warnings,
    )


def materialize_knowledge(run_root: Path, job_id: str) -> MaterializedConfig:
    workdir = _new_workdir(run_root, "knowledge", job_id)
    home = _fresh_home(run_root, "knowledge")
    warnings: list = []
    _copy_framework_files(workdir, job_id, warnings)
    env = _base_env(home, [str(LOCAL_BIN), _minimal_system_path()])
    env["CC_KNOWLEDGE_REPO"] = str(KNOWLEDGE_COPILOT_ROOT)
    if not KNOWLEDGE_COPILOT_ROOT.is_dir():
        warnings.append(f"KNOWLEDGE_COPILOT_ROOT {KNOWLEDGE_COPILOT_ROOT} not found on this machine")
    if not LOCAL_BIN.is_dir():
        warnings.append(f"LOCAL_BIN {LOCAL_BIN} not found -- tc/cc will not actually be reachable even though PATH includes it")
    return MaterializedConfig(
        name="knowledge",
        workdir=workdir,
        home_dir=home,
        env=env,
        claude_flags=list(COMMON_CLAUDE_FLAGS),
        notes=[
            "same .claude/ materialization as +framework",
            f"CC_KNOWLEDGE_REPO points at the REAL knowledge-copilot repo ({KNOWLEDGE_COPILOT_ROOT})",
        ],
        warnings=warnings,
    )


def materialize_integrations(run_root: Path, job_id: str) -> MaterializedConfig:
    workdir = _new_workdir(run_root, "integrations", job_id)
    home = _fresh_home(run_root, "integrations")
    warnings: list = []
    _copy_framework_files(workdir, job_id, warnings)
    env = _base_env(home, [str(CLI_COPILOT_VENV_BIN), str(LOCAL_BIN), _minimal_system_path()])
    env["CC_KNOWLEDGE_REPO"] = str(KNOWLEDGE_COPILOT_ROOT)

    dotenv_path = CLI_COPILOT_ROOT / ".env"
    dotenv_vars = _parse_dotenv(dotenv_path)
    env.update(dotenv_vars)

    if not KNOWLEDGE_COPILOT_ROOT.is_dir():
        warnings.append(f"KNOWLEDGE_COPILOT_ROOT {KNOWLEDGE_COPILOT_ROOT} not found on this machine")
    if not LOCAL_BIN.is_dir():
        warnings.append(f"LOCAL_BIN {LOCAL_BIN} not found -- tc/cc will not actually be reachable even though PATH includes it")
    copilot_bin = CLI_COPILOT_VENV_BIN / "copilot"
    if not copilot_bin.is_file():
        warnings.append(
            f"cli-copilot's copilot entry point not found at {copilot_bin} -- this environment gap means "
            "job-3-integration-report's honest-fallback path ('integrations unavailable') is what would "
            "actually be exercised for +integrations on THIS machine, not the real health-check path; "
            "see README.md 'Open risk before the first live run'"
        )
    if not dotenv_path.is_file():
        warnings.append(f"cli-copilot's .env not found at {dotenv_path} -- 0 vars loaded into the job env")

    config = MaterializedConfig(
        name="integrations",
        workdir=workdir,
        home_dir=home,
        env=env,
        claude_flags=list(COMMON_CLAUDE_FLAGS),
        notes=[
            "same .claude/ + CC_KNOWLEDGE_REPO materialization as +knowledge",
            f"cli-copilot's copilot entry point on PATH via {CLI_COPILOT_VENV_BIN}",
            f".env loaded from {dotenv_path}: {len(dotenv_vars)} var(s) exported into the job env (values never logged)",
        ],
        warnings=warnings,
    )
    config._env_file_keys = set(dotenv_vars.keys())
    return config


LADDER_CONFIGS = [
    ("bare", materialize_bare),
    ("framework", materialize_framework),
    ("knowledge", materialize_knowledge),
    ("integrations", materialize_integrations),
]
CONFIG_NAMES = [name for name, _ in LADDER_CONFIGS]


def materialize(config_name: str, run_root: Path, job_id: str) -> MaterializedConfig:
    for name, fn in LADDER_CONFIGS:
        if name == config_name:
            return fn(run_root, job_id)
    raise KeyError(f"configs.py: unknown config {config_name!r} (known: {CONFIG_NAMES})")
