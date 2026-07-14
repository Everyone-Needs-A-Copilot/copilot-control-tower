"""configs.py — the 4-config ladder (TASK-125 / W-3).

Config isolation, verbatim from phase-4-outcome-program-prd.md par.3 W-3:
"bare = fresh dir, no framework files; +framework = claude-copilot install;
+knowledge = CC_KNOWLEDGE_REPO populated vs empty tree; +integrations =
cli-copilot on PATH with .env." Register-first (V-2): this file IS the
`ladder_config_materialization` definition claims.yaml points at.

DESIGN: three isolation levers, verified live against this machine's
actual installed `claude` CLI (`claude --help`, 2026-07-13) before writing
any of this, per this repo's "before calling a third-party API, check the
real docs/help for the installed version" rule. QA WP-23 finding 5
(corrected): an earlier draft of this docstring credited
`--setting-sources project` with isolating USER-level CLAUDE.md/agents —
that is wrong, corrected here so the isolation doesn't silently break if a
future edit removes the HOME override thinking `--setting-sources` alone
covers it:

  1. **The per-run HOME override (the PRIMARY isolator of user-level
     CLAUDE.md/agents/skills).** This dev machine already has
     claude-copilot installed at the user level (`~/.claude/agents/`,
     `~/.claude/CLAUDE.md` if any, `~/.local/bin/{tc,cc}`), so cwd-only
     isolation (an empty directory) would still risk inheriting that
     content the same way ../resume_cost/run.py's design notes describe a
     tool-enabled model reaching a real fixture that happened to exist
     elsewhere on the same host ("this dev machine is not a clean room").
     Claude Code auto-discovers user-level CLAUDE.md/agents/skills
     relative to `$HOME/.claude/` — pointing `HOME` at a fresh, empty,
     per-run temp directory (see `_fresh_home()`) means there IS no real
     `~/.claude/` to discover, structurally, not by instruction. This is
     the mechanism that actually closes the leakage path; it is not
     merely a transcript-hygiene nicety (see below).
  2. `--setting-sources project` (a REAL flag: "Comma-separated list of
     setting sources to load (user, project, local)") on every config,
     including bare — a SECONDARY, narrower restriction on which
     `settings.json`-style permission/hook configuration sources merge
     (this is what the flag's own `--help` text scopes it to: "setting
     sources," not CLAUDE.md/agent-file discovery, which lever 1 already
     handles). Kept as defense-in-depth so a project-level `settings.json`
     this bench might materialize later can't accidentally merge with any
     user-level one.
  3. A per-config PATH override. `tc`/`cc` live at a single directory on
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

A secondary, welcome effect of the per-run HOME override (lever 1): a live
run's `claude -p` calls also write their session transcripts under the
isolated HOME's `~/.claude/projects/` rather than this machine's REAL
transcript corpus, which several OTHER collectors (framework_soul's
agent-frugality distribution, transcripts.py) already read as production
data — so mixing synthetic ladder-bench transcripts into that corpus is
avoided as a side effect of the SAME mechanism that does the isolation
job, not a second, separate measure. See README.md "Open risk before the
first live run" for the one thing this does NOT verify: whether an
isolated HOME still resolves Anthropic auth (OAuth token / keychain) the
same way the real HOME does — untested here, deliberately not asserted as
fact.

Every materialize_*() function is idempotent and side-effect-scoped to the
run_root directory it is given (never touches this repo, ~/.claude, or
~/.local/bin) — safe to call during --dry-run. QA WP-23 finding 4 (fixed):
every workdir/home is now keyed on (job_id, config_name, rep) — a prior
version keyed on (job_id, config_name) only, so `--reps > 1` silently
reused the same directory across reps with no cleanup, contaminating rep 2
with rep 1's leftover files.
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
REAL_HOME = Path.home()
LOCAL_BIN = Path(os.environ.get("CC_TC_LOCAL_BIN", str(REAL_HOME / ".local" / "bin")))

# QA fix (DEC-6 live-run pre-flight, 2026-07-14): resolved ONCE, against the
# operator's own real PATH at import time -- never against a per-config
# isolated PATH -- so every rung (bare included) can still find the real
# `claude` binary even after its own PATH is narrowed. See
# _claude_only_bin_dir()'s docstring for why `bare` specifically needed this
# (verified live: on this machine `claude` is co-located with tc/cc at
# LOCAL_BIN, so excluding LOCAL_BIN to hide tc/cc from `bare` also hid
# `claude` itself -- a real defect --dry-run could never catch, since it
# never calls shutil.which/subprocess for claude).
REAL_CLAUDE_BIN = shutil.which("claude")

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


def _seed_home_for_auth(home: Path, warnings: list) -> None:
    """QA fix (DEC-6 live-run pre-flight, 2026-07-14): a completely fresh
    isolated HOME could materialize/dry-run fine but could NEVER actually
    authenticate a live `claude -p` call -- verified live, not assumed:
    `claude auth status` reported `loggedIn: false` under a bare fresh HOME
    even with the real macOS login keychain unlocked, because (a) `claude`'s
    keychain lookup resolves the OS keychain SEARCH LIST from files under
    `$HOME/Library/...`, so a fresh HOME has no keychain to find at all, and
    (b) even with the keychain reachable, `claude` also needs the account
    state normally cached at `$HOME/.claude.json` (`oauthAccount`, `userID`)
    to consider itself logged in -- a bare `HOME` override has neither.
    README.md's "Open risk before the first live run" flagged this as
    UNTESTED; this closes it, narrowly:
      1. Symlink `<home>/Library/Keychains` -> the REAL user's
         `~/Library/Keychains` (read-only reuse of the already-unlocked
         login keychain for THIS OS user; no secret is copied into any
         file this bench writes -- the keychain item itself never leaves
         the OS keychain).
      2. Copy (never symlink) the REAL `~/.claude.json` into
         `<home>/.claude.json` so account/session state resolves too --
         copied, not linked, so a live run's own writes to this file (e.g.
         `numStartups`, `projects`) land in the isolated copy and never
         mutate the operator's real file.
    Neither step widens what this bench isolates: `.claude/{agents,
    commands,skills}`, CLAUDE.md, and tc/cc/copilot on PATH -- the actual
    ladder-rung levers -- are untouched by this, only account identity is
    restored so the call can authenticate at all."""
    fake_keychains = home / "Library" / "Keychains"
    if not fake_keychains.exists():
        real_keychains = REAL_HOME / "Library" / "Keychains"
        fake_keychains.parent.mkdir(parents=True, exist_ok=True)
        if real_keychains.is_dir():
            try:
                fake_keychains.symlink_to(real_keychains)
            except FileExistsError:
                pass
            except OSError as exc:
                warnings.append(f"could not symlink {real_keychains} into isolated HOME ({exc}) -- live auth will likely fail")
        else:
            warnings.append(f"real keychain dir {real_keychains} not found -- isolated HOME live auth will likely fail")

    fake_claude_json = home / ".claude.json"
    if not fake_claude_json.exists():
        real_claude_json = REAL_HOME / ".claude.json"
        if real_claude_json.is_file():
            shutil.copy2(real_claude_json, fake_claude_json)
        else:
            warnings.append(f"real {real_claude_json} not found -- isolated HOME live auth will likely fail (no oauthAccount state to seed)")


def _fresh_home(run_root: Path, config_name: str, rep: int, warnings: list) -> Path:
    """QA WP-23 finding 4 (fixed): keyed on rep too, not just config_name —
    a prior version reused the same home dir across every rep of a
    --reps > 1 run, silently carrying over whatever a previous rep's job
    call (or a materialization side effect) had written there.

    QA fix (DEC-6 live-run pre-flight, 2026-07-14): now also seeds the
    fresh home for auth (_seed_home_for_auth) -- see that function's
    docstring."""
    home = run_root / "homes" / config_name / f"rep{rep}"
    home.mkdir(parents=True, exist_ok=True)
    _seed_home_for_auth(home, warnings)
    return home


def _copy_framework_files(
    workdir: Path, job_id: str, warnings: list, include_claude_md: bool = True, include_agents: bool = True
) -> None:
    """Replicates the essential file-copy steps of claude-copilot's own
    `/setup-project` FULL-mode flow (.claude/commands/setup-project.md
    Steps 4-7), directly in Python rather than by running that slash
    command inside a live session — running it live would itself spend
    model calls this harness is trying to measure the MARGINAL cost of a
    job on top of, not the one-time per-project setup cost (see module
    docstring's O-1 framing: the ladder isolates the job's own cost, with
    the framework already installed, same as a real project's second and
    subsequent solutions).

    QA WP-79 fix (TASK-142, in-situ scaffold-cost ablation): `include_claude_md`
    / `include_agents` let a caller omit just ONE scaffold component while
    keeping everything else (commands, skills, .mcp.json) identical to
    +framework — see materialize_framework_minus_claudemd() and
    materialize_framework_minus_agents() below. WP-79's own ablation
    (claude -p, isolated HOME, --model haiku, a TRIVIAL no-tool prompt)
    attributed only ~62% of the ladder's measured turn-1 cache_creation
    premium to named scaffold (CLAUDE.md + agent frontmatter + skills +
    commands) and explicitly required a same-model, same-real-task-type
    matched ablation before any O-4 number is published — these two configs
    are that ablation, run at THIS harness's real model (sonnet) against
    THIS harness's real jobs, not a synthetic haiku probe."""
    version_json = CLAUDE_COPILOT_ROOT / "VERSION.json"
    if not version_json.is_file():
        warnings.append(f"CLAUDE_COPILOT_ROOT/VERSION.json not found at {version_json}; +framework materialization skipped")
        return
    version = json.loads(version_json.read_text())

    agents_dir = workdir / ".claude" / "agents"
    commands_dir = workdir / ".claude" / "commands"
    skills_dir = workdir / ".claude" / "skills"
    commands_dir.mkdir(parents=True, exist_ok=True)

    if include_agents:
        agents_dir.mkdir(parents=True, exist_ok=True)
        roster = version.get("components", {}).get("agents", {}).get("frameworkAgents", [])
        src_agents = CLAUDE_COPILOT_ROOT / ".claude" / "agents"
        for agent in roster:
            src = src_agents / f"{agent}.md"
            if src.is_file():
                shutil.copy2(src, agents_dir / f"{agent}.md")
            else:
                warnings.append(f"framework agent {agent!r} listed in VERSION.json but {src} not found")
    else:
        warnings.append("WP-79 ablation: .claude/agents/ deliberately OMITTED (materialize_framework_minus_agents)")

    project_commands = version.get("components", {}).get("commands", {}).get("projectCommands", [])
    src_commands = CLAUDE_COPILOT_ROOT / ".claude" / "commands"
    for cmd in project_commands:
        src = src_commands / cmd
        if src.is_file():
            shutil.copy2(src, commands_dir / cmd)

    src_skills = CLAUDE_COPILOT_ROOT / "templates" / "skills"
    if src_skills.is_dir():
        shutil.copytree(src_skills, skills_dir, dirs_exist_ok=True)

    if include_claude_md:
        template = CLAUDE_COPILOT_ROOT / "templates" / "CLAUDE.template.md"
        if template.is_file():
            text = template.read_text()
            text = text.replace("{{PROJECT_NAME}}", f"cse-bench-ladder-{job_id}")
            text = text.replace("{{PROJECT_DESCRIPTION}}", "cse-bench ladder harness job (TASK-125 / W-3) -- synthetic, not a real project")
            text = text.replace("{{TECH_STACK}}", "Python (stdlib)")
            (workdir / "CLAUDE.md").write_text(text)
    else:
        warnings.append("WP-79 ablation: CLAUDE.md deliberately OMITTED (materialize_framework_minus_claudemd)")

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


def _new_workdir(run_root: Path, config_name: str, job_id: str, rep: int) -> Path:
    """QA WP-23 finding 4 (fixed): keyed on rep too — see _fresh_home()'s
    docstring for the bug this closes (silent workdir reuse across reps,
    with no cleanup, when --reps > 1)."""
    workdir = run_root / "jobs" / job_id / config_name / f"rep{rep}"
    workdir.mkdir(parents=True, exist_ok=True)
    return workdir


def _base_env(home: Path, path_dirs: list) -> dict:
    env = {
        "HOME": str(home),
        "PATH": ":".join(dict.fromkeys(path_dirs)),
    }
    # QA fix (DEC-6 live-run pre-flight, 2026-07-14): verified live that
    # `env -i HOME=<real> ...` (no USER/LOGNAME) ALSO reports "Not logged
    # in" -- `claude`'s keychain account lookup needs USER/LOGNAME, not
    # just a resolvable HOME/keychain. TMPDIR/SHELL are passed through too
    # (unrelated to auth, but real subprocess.run(env=...) REPLACES the
    # entire environment, not just PATH/HOME, and a real coding job's Bash
    # tool calls can depend on both being set). None of these four are part
    # of the ladder's deliberate isolation levers (.claude/ discovery,
    # tc/cc/copilot on PATH, CC_KNOWLEDGE_REPO) -- passing them through
    # narrows nothing this bench is actually trying to ablate.
    for key in ("USER", "LOGNAME", "TMPDIR", "SHELL"):
        value = os.environ.get(key)
        if value:
            env[key] = value
    return env


def _claude_only_bin_dir(run_root: Path) -> Path:
    """QA fix (DEC-6 live-run pre-flight, 2026-07-14): on this machine
    `claude` itself is co-located with tc/cc at LOCAL_BIN (verified live:
    `shutil.which('claude')` resolves under the same directory as
    `shutil.which('tc')`), so `bare`'s original isolation -- exclude
    LOCAL_BIN entirely to hide tc/cc -- ALSO hid `claude`, leaving `bare`
    unable to invoke the model at all. `--dry-run` could never catch this
    (it never calls shutil.which/subprocess for claude). Fix: materialize a
    run-scoped directory containing ONLY a symlink named `claude` -> the
    real claude binary (REAL_CLAUDE_BIN, resolved once at import time
    against the operator's own real PATH), and put that narrow directory on
    `bare`'s PATH instead of the whole LOCAL_BIN directory -- keeps "no
    tc/cc/copilot reachable from bare" while making claude itself
    reachable everywhere, including bare."""
    bin_dir = run_root / "claude-only-bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    link = bin_dir / "claude"
    if not link.exists() and REAL_CLAUDE_BIN is not None:
        try:
            link.symlink_to(REAL_CLAUDE_BIN)
        except FileExistsError:
            pass
    return bin_dir


def materialize_bare(run_root: Path, job_id: str, rep: int = 1) -> MaterializedConfig:
    workdir = _new_workdir(run_root, "bare", job_id, rep)
    warnings: list = []
    home = _fresh_home(run_root, "bare", rep, warnings)
    claude_bin_dir = _claude_only_bin_dir(run_root)
    env = _base_env(home, [str(claude_bin_dir), _minimal_system_path()])
    if REAL_CLAUDE_BIN is None:
        warnings.append("`claude` not found via shutil.which() on this machine -- bare rung cannot invoke the model at all")
    return MaterializedConfig(
        name="bare",
        workdir=workdir,
        home_dir=home,
        env=env,
        claude_flags=list(COMMON_CLAUDE_FLAGS),
        notes=[
            "fresh empty workdir, no .claude/, no CLAUDE.md, no tc/cc/copilot on PATH",
            f"`claude` itself reachable via a narrow run-scoped symlink dir ({claude_bin_dir}) since it happens to co-reside with tc/cc at LOCAL_BIN on this machine (QA fix, 2026-07-14)",
        ],
        warnings=warnings,
    )


def materialize_framework(run_root: Path, job_id: str, rep: int = 1) -> MaterializedConfig:
    workdir = _new_workdir(run_root, "framework", job_id, rep)
    warnings: list = []
    home = _fresh_home(run_root, "framework", rep, warnings)
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


def materialize_framework_minus_claudemd(run_root: Path, job_id: str, rep: int = 1) -> MaterializedConfig:
    """QA WP-79 ablation rung (TASK-142): identical to +framework EXCEPT
    CLAUDE.md is absent -- isolates CLAUDE.md's true in-situ turn-1
    cache_creation cost at the real model (sonnet) and real job/task type,
    closing WP-79's "same-model, same-task-type matched ablation" gate
    before any O-4 number citing CLAUDE.md's share may be published (its
    prior attribution came from a synthetic haiku, no-tool, trivial-prompt
    probe, not this harness)."""
    workdir = _new_workdir(run_root, "framework_minus_claudemd", job_id, rep)
    warnings: list = []
    home = _fresh_home(run_root, "framework_minus_claudemd", rep, warnings)
    _copy_framework_files(workdir, job_id, warnings, include_claude_md=False, include_agents=True)
    empty_knowledge = _empty_knowledge_tree(run_root)
    env = _base_env(home, [str(LOCAL_BIN), _minimal_system_path()])
    env["CC_KNOWLEDGE_REPO"] = str(empty_knowledge)
    if not LOCAL_BIN.is_dir():
        warnings.append(f"LOCAL_BIN {LOCAL_BIN} not found -- tc/cc will not actually be reachable even though PATH includes it")
    return MaterializedConfig(
        name="framework_minus_claudemd",
        workdir=workdir,
        home_dir=home,
        env=env,
        claude_flags=list(COMMON_CLAUDE_FLAGS),
        notes=[
            "WP-79 ablation: same as +framework (.claude/{agents,commands,skills}/) but CLAUDE.md is deliberately ABSENT",
            f"tc/cc on PATH via {LOCAL_BIN}",
            f"CC_KNOWLEDGE_REPO points at an EMPTY tree ({empty_knowledge}), same as +framework",
        ],
        warnings=warnings,
    )


def materialize_framework_minus_agents(run_root: Path, job_id: str, rep: int = 1) -> MaterializedConfig:
    """QA WP-79 ablation rung (TASK-142): identical to +framework EXCEPT
    .claude/agents/ is absent -- isolates the agent-frontmatter cost in
    situ at the real model/task, AND doubles as a capability control: if
    removing every subagent definition does not hurt this pack's
    discriminating jobs' O-1/O-6 outcomes, that is itself a finding about
    the agent layer's marginal value on THESE jobs, not just a token-cost
    ablation (see this bench's README.md 'Job pack v2' section for how
    that result is read)."""
    workdir = _new_workdir(run_root, "framework_minus_agents", job_id, rep)
    warnings: list = []
    home = _fresh_home(run_root, "framework_minus_agents", rep, warnings)
    _copy_framework_files(workdir, job_id, warnings, include_claude_md=True, include_agents=False)
    empty_knowledge = _empty_knowledge_tree(run_root)
    env = _base_env(home, [str(LOCAL_BIN), _minimal_system_path()])
    env["CC_KNOWLEDGE_REPO"] = str(empty_knowledge)
    if not LOCAL_BIN.is_dir():
        warnings.append(f"LOCAL_BIN {LOCAL_BIN} not found -- tc/cc will not actually be reachable even though PATH includes it")
    return MaterializedConfig(
        name="framework_minus_agents",
        workdir=workdir,
        home_dir=home,
        env=env,
        claude_flags=list(COMMON_CLAUDE_FLAGS),
        notes=[
            "WP-79 ablation: same as +framework (CLAUDE.md/{commands,skills}/) but .claude/agents/ is deliberately ABSENT",
            f"tc/cc on PATH via {LOCAL_BIN}",
            f"CC_KNOWLEDGE_REPO points at an EMPTY tree ({empty_knowledge}), same as +framework",
        ],
        warnings=warnings,
    )


def materialize_knowledge(run_root: Path, job_id: str, rep: int = 1) -> MaterializedConfig:
    workdir = _new_workdir(run_root, "knowledge", job_id, rep)
    warnings: list = []
    home = _fresh_home(run_root, "knowledge", rep, warnings)
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


def materialize_integrations(run_root: Path, job_id: str, rep: int = 1) -> MaterializedConfig:
    workdir = _new_workdir(run_root, "integrations", job_id, rep)
    warnings: list = []
    home = _fresh_home(run_root, "integrations", rep, warnings)
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
    # QA WP-79 ablation rungs (TASK-142): inserted between framework and
    # knowledge so the ladder's ORIGINAL 4-rung ordering (bare, framework,
    # knowledge, integrations) is still a contiguous subsequence -- a
    # --config filter or any code that assumed exactly 4 rungs still finds
    # the original 4 unchanged, just with 2 more names now valid too.
    ("framework_minus_claudemd", materialize_framework_minus_claudemd),
    ("framework_minus_agents", materialize_framework_minus_agents),
    ("knowledge", materialize_knowledge),
    ("integrations", materialize_integrations),
]
CONFIG_NAMES = [name for name, _ in LADDER_CONFIGS]


def materialize(config_name: str, run_root: Path, job_id: str, rep: int = 1) -> MaterializedConfig:
    for name, fn in LADDER_CONFIGS:
        if name == config_name:
            return fn(run_root, job_id, rep)
    raise KeyError(f"configs.py: unknown config {config_name!r} (known: {CONFIG_NAMES})")
