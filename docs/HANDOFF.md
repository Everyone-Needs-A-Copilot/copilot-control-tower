# HANDOFF — Copilot Control Tower

A self-contained brief to **start a fresh conversation in this repo** and continue building. Everything a new session needs to pick up with zero prior context.

---

## Paste this to begin a new session

> Read `docs/HANDOFF.md`, then `docs/START-HERE.md`, `docs/01-architecture/architecture.md`, and `docs/02-prd/prd.md`. We're building **Copilot Control Tower**. Confirm you understand the one invariant (*the app parses CLI output; it never computes*) and the state below. The immediate task is to **freeze the WS-A CLI contract** (`docs/01-architecture/cli-contract.md`) — note it lives in the **`claude-copilot` repo's `copilot`/`cc` CLI, not this repo**. Before writing any code, propose the WS-A implementation plan (the exact `--json` schema files, the verbs to add, `flock`, `COPILOT_MANAGED_BY`, and the CI contract test).

---

## Where we are (state at handoff)

| | |
|---|---|
| **Repo** | `Everyone-Needs-A-Copilot/copilot-control-tower` (private; goes **public at launch**) |
| **Local path** | `/Volumes/Dev/Sites/COPILOT/copilot-control-tower` |
| **Hosts wired** | **Both** Claude Copilot (framework agents/commands/cc/tc; fitness 111/111) **and** Codex Copilot (`AGENTS.md` + Codex skills over shared `cc`/`tc`) |
| **Spec** | **Complete and validated** — architecture + parallel PRD + 3 design streams + 2 red-team reports (25 Critical/High findings, all mapped to fixes in `architecture.md` §10) |
| **Build** | **Not started.** No app code exists. This repo holds the spec + docs + framework scaffold only. |
| **Commits** | `09d1707` (docs scaffold) → `dc662a8` (both hosts) → `5a19b0e` (slug normalize + Codex trim) on `main` |

**What has NOT been done yet:** the WS-A CLI contract is not implemented; no Tauri app; the UI/UX is not designed; `05-security/`, `06-deployment/`, `07-contributing/` are stubs.

---

## What Control Tower is (30 seconds)

An open-source macOS **menu-bar app** (Tauri v2, single process) that is a **face + supervisor over the `copilot`/`cc` CLI** — it keeps every machine synced and self-healed and gives a non-technical user ("Bob") a working Copilot partner from one double-click. **Two faces, one binary:** Operator mode (end-user client) + Admin mode (open-source IT setup/deploy tool + docs). The name is the model: a control tower doesn't fly the plane — it monitors, coordinates, clears, and alarms.

**The one invariant (never violate):** Control Tower **parses; it never computes.** Every health verdict, resolution, signature check, prune, and wipe is done by the CLI. If the app vanished, the CLI would still be correct. If you find yourself re-implementing resolution/sync logic in Rust, stop — it belongs in the CLI.

---

## Locked decisions (do not relitigate)

| Decision | Value |
|---|---|
| Name / repo | Copilot Control Tower · `copilot-control-tower` |
| Stack | Tauri v2 (Rust core + minimal web UI), macOS-first (Windows = later re-skin) |
| Process model | **Single process** + a `launchd` **crash-only watchdog**; the CLI self-serializes via `flock` on `copilot.lock` |
| Role | Face + supervisor over the CLI — never a second brain |
| Host model | Host-aware (Claude + Codex) via detection + `copilot derive` column selection |
| Distribution | Developer ID signed + notarized; MDM-deployable (Jamf/Kandji/Intune) |
| Escalation | Route by **actor-competence × reversibility** (auto-act / escalate-IT / ask-Bob), not event-class |
| Open source | A requirement (auditable always-on agent), public at launch |
| `/cli` write-gate | confirm on writes to systems of record, reads unprompted |

---

## Read in this order

1. `docs/START-HERE.md` — orientation + build order
2. `docs/01-architecture/architecture.md` — the hardened design (§10 = the 25 red-team fixes)
3. `docs/01-architecture/cli-contract.md` — **WS-A**, the prerequisite that gates everything
4. `docs/02-prd/prd.md` — the parallel, multi-phase PRD (workstreams, acceptance, phase gates)
5. `docs/03-design/` — the three design streams; `ui-ux/README.md` = the Product Creation Copilot track
6. `docs/04-validation/` — the two red-team reports
7. `docs/reference/` + `docs/assets/*.html` — self-contained ecosystem context + the two diagrams

---

## The immediate next step: freeze WS-A

**What it is:** implement + publish + version-lock the machine-readable interface the app reads — `--json` for `doctor`/`update`/`resolve --explain`/`deprovision`/`freshness`, plus `flock` on `copilot.lock` and `COPILOT_MANAGED_BY=controltower`, guarded by a **CI contract test**. Full spec: `docs/01-architecture/cli-contract.md`.

**Why first:** the app is "parse, never compute," so it can only be built against a *stable, versioned* interface. Freezing it (a) unblocks the 8 app workstreams to run in parallel, (b) contains the #1 red-team risk (schema drift → the app shows green over a red pipeline), and (c) decouples CLI and app release cadences.

**⚠ Where it lives:** **the `claude-copilot` repo** (the `copilot`/`cc` CLI), **not this repo.** Control Tower consumes it as a vendored, version-pinned dependency. So WS-A is a change to the ecosystem CLI; the app build (WS-B onward) starts only after it's frozen.

---

## Build order after WS-A

1. **`/orchestrate`** the PRD (`docs/02-prd/prd.md`) to scaffold the parallel worktrees (WS-B…WS-I). Critical path: WS-A → WS-B shell → WS-D signing → WS-E MDM.
2. **Product Creation Copilot** for the UI/UX track (`docs/03-design/ui-ux/README.md`) — design-only (we skip its discovery); it produces Figma/Storybook for the menu-bar dropdown, wizard, Admin-mode UI, and fleet dashboard. PCC is at `/Volumes/Dev/Sites/COPILOT/product-creation-copilot` (run `claude` there, say "Read quickstart.md and let's begin").
3. **`@agent-sec`** for `docs/05-security/security-and-trust.md` (the enterprise security-review enablement).

---

## Cross-repo dependencies (important)

- **WS-A** implementation is in `claude-copilot` (`copilot`/`cc` CLI).
- **Cross-repo binary contract (WS-D2):** `claude-copilot` CI must publish `copilot`/`cc` as already-signed/notarized, universal, pinned-SHA artifacts that Control Tower vendors and *verifies* (never re-signs).
- The `claude-copilot` **`ecosystem-extensions` branch** holds all the ecosystem design (docs `00`–`06` of `docs/80-initiatives/01-ecosystem-extensions/`) and is **committed but NOT pushed** (latest `1b5cfa9`). The Control Tower docs here are copies of `05`/`06` + the design/redteam appendices.

---

## Open items / loose ends

- **`AGENTS.md` dangling refs** — Codex's `AGENTS.md` still references the two files we trimmed (`SOUL.md`, `docs/01-architecture/12-architecture-guiding-principles.md`). Decide: strip the two refs from `AGENTS.md` (clean), or regenerate the instruments (PCC produces the real `soul.md`). Low-impact but unresolved.
- **`docs/00-overview/soul.md`** is a DRAFT stub — the real product essence comes from Product Creation Copilot.
- **License** — deferred to launch (README notes it).
- **Stub docs** — `05-security/`, `06-deployment/`, `07-contributing/` are index stubs with owners assigned.

---

## Practical notes for the new session

- **Framework is set up.** Run `/protocol` to start disciplined work; the framework agents (ta, me, qa, do, doc, sec, sd, uxd, uids, uid, …) are available; `cc memory search "<topic>"` recalls decisions; `tc` tracks tasks/PRDs.
- **Both hosts work.** In Claude Code use `/protocol` etc.; in Codex read `AGENTS.md` and use `$protocol`.
- **Don't start app code before WS-A is frozen.** Keep the app a thin skin.
- **The diagrams** (`docs/assets/ecosystem-diagram.html`, `ecosystem-walkthrough.html`) render the layer model and the operator walkthrough — open them in a browser for the big picture.
