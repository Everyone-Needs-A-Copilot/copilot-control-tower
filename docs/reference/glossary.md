# Glossary

Reference — the canonical definitions for terms used across the Control Tower docs. If a term is
defined differently in an older doc, **this page wins**; fix the drift there, not here.

> **Mode.** This is a Reference page (Diátaxis) — information-oriented, dry, alphabetized within
> groups, built for lookup. It does not teach or narrate; see
> [`docs/00-overview/product-brief.md`](../00-overview/product-brief.md) for the narrative version and
> [`SOUL.md`](../../SOUL.md) for the reasoning behind the vocabulary.

---

## Core architecture

**Layer vs. tier vs. product vs. dimension** — four distinct axes; the docs use them precisely and
none of them substitute for another:
- **Tier** is the conceptual precedence rank in the inheritance stack: **PERSONAL (10) › DEPARTMENT
  (20) › ORG (30) › FOUNDATION (40)**. A tier is a *position*, not a file.
- **Layer** is a concrete, self-describing manifest entry (`id`/`role`/`rank`/`source`/`auth`/
  `product`) that *occupies* a tier. One tier can hold more than one layer — e.g. a user in two
  departments declares two `department`-role layers at distinct ranks (`20`, `21`). `role` is an
  open string, so a 5th tier (`squad`, `region`) is a data edit, not a schema change.
  Ref: [`four-tier-topology.md`](four-tier-topology.md) §§2–4.
- **Product** — an independently four-tier-layered bundle of dimensions; the initial products are
  **Knowledge Copilot, CLI Copilot, Claude Copilot, Codex Copilot**. Product is **config-driven** —
  these four are the initial set declared in `ecosystem.yml`/`copilot.layers.yml`, not a hardcoded
  count — and a new product is additive by adding layers, not a schema change. **Invariant: a layer
  belongs to exactly one product × tier.** Product is a first-class **attribution + grouping axis**
  carried on every layer and every resolved item (a `product` field), distinct from the *tier* it
  occupies and the *dimension(s)* it resolves. Ref: [`four-tier-topology.md`](four-tier-topology.md)
  §4; [`ecosystem-architecture.md`](ecosystem-architecture.md) §§1, 3.
- **Dimension** — a content-*kind* the resolver resolves: **agents, skills, commands, protocol,
  knowledge, memory, tasks, cli-integrations**. Each dimension has its own fold semantics (override,
  accumulate, personal-write, project-local — see `ecosystem-architecture.md` §3.1) applied
  per-layer, independent of which product or tier the layer belongs to.
  Ref: [`ecosystem-architecture.md`](ecosystem-architecture.md) §3.1.
- **The crisp distinction:** *tier* is **where** in precedence a layer sits; *product* is **which
  bundle** a layer belongs to (an attribution/grouping label carried alongside); *dimension* is
  **what kind of content** the resolver is folding when it walks that layer. A layer has exactly one
  tier and exactly one product; it may contribute to one or more dimensions.

**Materialize** — the act of copying the *resolved* (winning, per-name) set of agents/skills/
commands/knowledge out of local layer clones into the paths a host actually scans (e.g. `.claude/`).
Materialize is **copy, not read-time merge** — the host is layer-unaware. As of the reconciling-sync
fix it behaves like `rsync --delete`: every `copilot update` diffs the current resolved set against
the previous lockfile and **prunes** anything whose owning layer/product left the set, not just adds.
Ref: [`architecture.md`](../01-architecture/architecture.md) §3.2 (via `ecosystem-architecture.md`),
[`ecosystem-architecture.md`](ecosystem-architecture.md) §3.2.

**Read-only mirror** — the local clone of an org/dept/foundation layer that feeds resolve →
materialize. It is **disposable**: Control Tower may `git fetch && reset --hard` or reclone it
freely on drift or force-push, because nothing valuable is stored there uncommitted. Distinct from
an **authoring working copy** (the tier-scoped checkout a trained author edits before `copilot
publish`), which is treated as a "dirty personal working tree" and is never touched.
Ref: [`inheritance-and-publish.md`](../01-architecture/inheritance-and-publish.md) §2.2.

**Shadow / override-stale / worst-wins:**
- **Shadow** — when a nearer-tier item overrides (hides) a farther-tier item of the same name;
  `resolve --explain` prints the full shadow chain (`personal/qa shadows dept/qa shadows org/qa
  shadows foundation/qa`). A `shadowed_by` field in `update --json` names what a given item is
  currently hidden behind.
- **Override-stale** — a `doctor` checker that fires when a personal (or any nearer-tier) override
  is shadowing an upstream item that has since **changed** — the override "went stale" relative to
  what it's hiding. This is the mechanism that stops a security fix from being silently defeated by
  an old override.
- **Worst-wins** — the precedence rule for combining per-host status into one menu-bar icon: with
  two hosts (Claude, Codex) on one machine, the icon shows the **worse** of the two states, never a
  blended average.
  Ref: [`architecture.md`](../01-architecture/architecture.md) §2 (worst-wins), §7.4 (override-stale);
  [`cli-contract.md`](../01-architecture/cli-contract.md) (`shadowed_by`).

---

## People & personas

**"Bob"** — the change-averse, non-technical **consumer** archetype (primary persona). Not a
developer, has no terminal, routinely denies OS permission prompts, ignores single nudges. "Bob is
not a reliable actor" is a load-bearing design assumption: he is asked *at most three* things at
setup and interrupted almost never after. His detail-orientation means he **will** catch a dishonest
or drifted status, which is why "the icon that cannot lie" is survival, not polish. Bob is a
psychology, not a role — anyone in any department can "be Bob."
Ref: [`00-vision.md`](../product-design/00-overview/00-vision.md) Target Users; `SOUL.md` §1.

**Author (the trained early-adopter)** — the second consumer psychographic: a more comfortable,
gated user who **writes** org/department content (skills, agents, knowledge) in a markdown editor
(Obsidian) and pushes it via `copilot publish`. Write access is *earned and gated*, starting with a
few innovators. An author is never forced to become a Git user to resolve a collision — see
**needs-choice** below. Distinct from a **consumer**, who only ever pulls.
Ref: `SOUL.md` §1; [`inheritance-and-publish.md`](../01-architecture/inheritance-and-publish.md) §1.

**Consumer** — anyone (including Bob) who only runs the `freshness → update` pull path. A consumer's
org/dept clones are read-only mirrors; a consumer **never** commits to a shared clone locally and so
cannot physically produce a local edit-conflict on shared content — the entire class of "Bob hits a
merge conflict" only happens if Bob is also an author.
Ref: [`inheritance-and-publish.md`](../01-architecture/inheritance-and-publish.md) §2.1.

---

## The CLI verbs (`copilot`/`cc`)

All emit a versioned `--json` mode; this is the **only** surface Control Tower is allowed to read
(never screen-scraped human output). Schema is authoritative in
[`cli-contract.md`](../01-architecture/cli-contract.md).

| Verb | What it does | Exit codes |
|---|---|---|
| **`doctor`** | Runs the health checkers, returns a 0–100 score + `status` + per-checker findings (`pass\|warn\|fail`). `status` is computed CLI-side, never by the app. | `0` clean · `1` any fail · `2` env error |
| **`update`** | Pulls, resolves, and materializes (reconciling sync) the current resolved set; reports `changed[]` (`added\|updated\|pruned\|unchanged`), `held_for_approval`, `blocked`. | — |
| **`repair`** | Runs the same idempotent phase engine as install/doctor to fix a specific failing checker. Split by layer role: read-only mirrors get fetch/reset/reclone; the personal layer gets stash-and-flag, never discard. | — |
| **`resolve --explain`** | Per-item provenance: winning layer, shadow chain, source SHA, signer, `live_hash_matches`. Re-hashes the live file rather than trusting a stale "signed ✓". | — |
| **`deprovision <org>`** | Wipes materialized items + layer clones for a leaver/offboarded org. `secrets_touched` MUST be `0` (proof no secret ever lived in a layer). Never touches a dirty personal tree. | — |
| **`freshness`** | The cheap poll target — a single `{latest_lock_sha, current_lock_sha, stale, checked_at}` fetch, not a full `update`. What Control Tower actually polls on a cadence. | — |
| **`publish`** | The **author-side push** of a writable org/dept tier — the one path where cross-author conflicts arise. CLI computes the merge/conflict; the app only renders the chooser and passes back `--resolve <choice>`. | `0` published (incl. a cleanly-reported conflict) · `1` publish refused (leak-scan tripped, unresolvable non-fast-forward, stale `--resolve`) · `2` env/credential error |

Ref: [`cli-contract.md`](../01-architecture/cli-contract.md).

---

## Concurrency & process model

**`flock` / `copilot.lock`** — `update`/`repair`/`deprovision` each take an **exclusive `flock`** on
`copilot.lock` and fail fast if held, as a **global per-host mutex across all verbs**. This is what
lets a `deprovision` drain pending syncs before wiping, and is why "the CLI self-serializes — Control
Tower is not the lock." No process arrangement (a stray second instance, a manual CLI run,
fast-user-switching) can double-write.
Ref: [`architecture.md`](../01-architecture/architecture.md) §3; [`cli-contract.md`](../01-architecture/cli-contract.md) Concurrency.

**Crash-only watchdog / `KeepAlive`** — `launchd` runs Control Tower under
`KeepAlive={SuccessfulExit:false}`, `RunAtLoad=false`: it relaunches only after a **crash**, never
after a clean Quit. `KeepAlive=true` is explicitly and permanently forbidden (it would resurrect the
app after a deliberate Quit and crash-loop a bad build) — this is a named anti-pattern
(*The Convenience Backdoor*), not a tuning knob.
Ref: [`architecture.md`](../01-architecture/architecture.md) §3; `SOUL.md` §4.

---

## Trust, security & governance

**Managed / MDM domain** — the forced preferences domain (`com.apple.ManagedClient.preferences` for
bundle ID `dev.enac.controltower`) that an MDM (Jamf/Kandji/Intune) writes. **Security-sensitive
keys are honored only from this forced domain** — `UpdateFeedURL`, `FoundationMirror`,
`EcosystemSeedURL`, `HTTPSProxy`, `GitHubHost`, `AuthMode`, `AllowSelfUpdate`, `Deprovisioned` — read
via `CFPreferencesAppValueIsForced`. A value present only in the unmanaged user domain is **ignored**
and logged as a tamper event; on unmanaged machines the compiled-in trust root is authoritative.
Ref: [`architecture.md`](../01-architecture/architecture.md) §8.3.

**Translocation-safe path** — the CLI must be invoked by an **absolute path resolved from the
running app bundle** (`Bundle.main.bundleURL`), never a hardcoded `/Applications` path and never a
bare `copilot` on `$PATH` (which collides with GitHub's own `gh copilot`). This survives Gatekeeper's
app translocation (a randomized quarantine path on first launch of a moved `.app`).
Ref: [`architecture.md`](../01-architecture/architecture.md) §7; `CLAUDE.md` Tech section.

**"The icon that cannot lie"** — the design mandate that the menu-bar icon has **no code path** to
fabricate a Healthy state it can't prove from parsed CLI JSON. Offline, uninstalled, or
schema-mismatched all render as an honest holding state, never a guessed green. This is the concrete
form of invariant #1 (parse, never compute) at the UI layer.
Ref: `SOUL.md` §2, Case Law; [`architecture.md`](../01-architecture/architecture.md) §2.

**"Silent first light"** — the moment a managed (MDM-pushed) Bob reaches a working, team-scoped
Copilot partner having been asked **zero** technical questions — he watches a progress bar and is
done. The hero happy-path moment-that-matters (MTM-1) the whole wizard and MDM-profile-generator
chain exists to deliver.
Ref: [`40-moments-that-matter.md`](../product-design/02-service-design/40-moments-that-matter.md)
MTM-1; [`00-vision.md`](../product-design/00-overview/00-vision.md).

**"Copilot-ready"** — the ongoing state Control Tower keeps a machine in: synced and self-healed on
a cadence, with an authorized upstream change simply *appearing* without ever touching personal
work. It is the product's "one thing" — not a one-time setup outcome but a standing property Control
Tower maintains for as long as it runs.
Ref: [`00-vision.md`](../product-design/00-overview/00-vision.md) "The One Thing";
[`product-brief.md`](../00-overview/product-brief.md).

**`requires_secret` reference** — the way inheritance content (a skill/agent/MCP manifest) declares
a dependency on a secret **without ever carrying its value**: `requires_secret: <NAME>` names the
secret and its acquisition method only. At invocation time the CLI resolves the name against the OS
keychain (or, per the v1.3 amendment, an IT-managed shared secret store) and injects the live value
into the spawned process only — never writing it back to a repo, config file, or telemetry. Git is
permanently excluded as a secrets carrier at any tier.
Ref: [`credentials-and-boundary.md`](../05-security/credentials-and-boundary.md) §1.4, §1.6.

**Leak-scan** — the fail-closed scan run on every writable-tier `copilot publish` and on the
foundation promotion pipeline, checking for secrets/tokens, personal-tier markers, and PII before a
remote accepts the change. A tripped scan **blocks the push** with a plain-language explanation —
never a raw git/VCS error. `leak_scan` is a security-relevant field in `publish --json`: missing or
malformed ⇒ refuse to publish (fail-closed), never treated as safe.
Ref: [`inheritance-and-publish.md`](../01-architecture/inheritance-and-publish.md) §7; `SOUL.md`
Founding Decision #10, rule 4.

---

## The two faces

**Operator mode** — the end-user client: the Bob-facing menu-bar tray, status icon, first-run
wizard, and escalation routing (architecture §§2–7). This is the primary, Bob-first face; done
first, judged first.

**Admin mode** — `control-tower admin`, the IT setup/deploy tool: seed generator, repo/access
scaffolding, capability-policy authoring, MDM-profile generator, preflight validation, fleet
dashboard, deployment runbooks. It is the **enabler** of Operator mode at fleet scale, never a
co-equal audience — "Bob-first" is a founding, locked decision.
Ref: [`architecture.md`](../01-architecture/architecture.md) §8; `SOUL.md` Founding Decision #2.

---

## Workstreams (WS-A … WS-I)

The PRD's parallel decomposition. **WS-A is the sole prerequisite** — it freezes the CLI `--json`/
`flock`/`COPILOT_MANAGED_BY` contract in the `copilot` repo — and gates every workstream below it;
once frozen, WS-B onward proceed concurrently, each against the same frozen schema.

| Workstream | Scope | Depends on |
|---|---|---|
| **WS-A** | CLI contract (`--json` + `flock` + `COPILOT_MANAGED_BY`) — lives in `claude-copilot`/`copilot`, not this repo | — (prerequisite) |
| **WS-B** | App shell & supervisor: single process, state machine, host detection, timers | A |
| **WS-C** | Wizard & onboarding | B, A |
| **WS-D** | Distribution & self-update | B; cross-repo signing contract with A's repo |
| **WS-E** | MDM & security | D (for deploy), B (for runtime) |
| **WS-F** | Bob-agency & escalation | B, A |
| **WS-G** | Observability & IT dashboard | F |
| **WS-H** | Admin mode & docs (open source enablement) | A, partial E |
| **WS-I** | Windows re-skin (P4) | B, D |

Ref: [`prd.md`](../02-prd/prd.md) §2.

## Phase gates (P0–P4)

Maturity gates, **not sequential teams** — a workstream advances through phases at its own pace; no
time estimates attach to any phase.

| Phase | Exit criterion |
|---|---|
| **P0** | WS-A contract frozen + `flock`; WS-B shell runs and reads `doctor --json` with correct per-host state. |
| **P1** | WS-C wizard (silent + fail-closed + Waiting-for-network); WS-D signed/notarized + cross-repo binary contract + watchdog rollback. |
| **P2** | WS-E MDM (forced-domain keys, managed login item, MDM-native deprovision); WS-F actor-competence escalation + safety-channel-on-by-default. |
| **P3** | WS-G opt-in telemetry + IT dashboard + two-of-N signing; WS-H Admin mode + docs. |
| **P4** | WS-I Windows re-skin. |

Ref: [`prd.md`](../02-prd/prd.md) §2, §12 roadmap; [`architecture.md`](../01-architecture/architecture.md) §12.
