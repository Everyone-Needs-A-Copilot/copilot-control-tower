# Writable Inheritance Tiers & Non-Technical Conflict Resolution (Publish Path)

| | |
|---|---|
| **STATUS** | **RATIFIED 2026-07-07 (owner).** Promoted from `proposals/writable-inheritance-and-conflict.md` (draft RFC) to a canonical architecture doc. |
| **Type** | Architecture RFC (foundational — resolves two of the three open problems in SOUL.md §9) |
| **Scope** | Reconciles writable org/dept tiers with invariant #3 (never-destroy); designs non-technical merge-conflict resolution (SOUL anti-pattern *The Git Error To A Non-Technical Person*) |
| **Grounds in** | `architecture.md` §3 · `cli-contract.md` · `reference/four-tier-topology.md` §§3–6 · `reference/ecosystem-architecture.md` §3, §5.2, §5.4, §8.1 · `product-design/02-service-design/10-service-blueprint.md` (W1–W5, F15/F16) · SOUL.md §4 (Leak, Git-Error), §9 |
| **Governed by** | The five invariants in `CLAUDE.md`. This design KEEPS all five intact; the one *optional* invariant-text clarification (§5) was offered for ratification and is **not** adopted unless separately ratified — the ratified design needs no invariant change. |
| **Red-team IDs addressed** | F15 (merge-conflict UNSOLVED), the #3-strain on writable tiers; adjacent to F16 (credentials-carrier, out of scope here — see §6) |

> **One-paragraph verdict.** The invariant tension is **apparent, not real**, and dissolves under one distinction the current docs imply but never state: **never-destroy governs the PULL/materialize side; collaborative conflict lives entirely on a separate PUSH/publish side that never-destroy does not — and need not — cover.** A consumer machine only ever *pulls* (its shared clones are read-only mirrors Control Tower may reset/reclone freely), so a non-author Bob physically cannot create a local edit-conflict on shared content. Conflicts arise only between *authors of the same tier*, at *publish time*, against the *remote* — which is a new governed CLI path (`copilot publish`), not a weakening of never-destroy. Invariant #3 is **kept intact**; a clarifying (non-weakening) elaboration is offered as optional and marked for ratification.

---

## 1. Problem framing

### 1.1 Problem 1 — Writable org/dept tiers vs. never-destroy / read-only mirrors

The inheritance model is **foundation → org → department → personal** (`four-tier-topology.md` §2). The interview (`interview-ground-truth.md` §3) made org and department tiers **writable** by trained, gated authors (Obsidian → save → push → cadence sync) and **consumed** by everyone else on a pull cadence.

Invariant #3 (`CLAUDE.md`):

> **Never-destroy.** May freely re-materialize `.claude/` and re-clone read-only **mirrors**; **never** touches a dirty personal working tree.

The architecture leans on this: materialize is a reconciling `rsync --delete` sync from local clones (`ecosystem-architecture.md` §3.2), and repair is **split by layer role** — org/dept/foundation mirrors get `git fetch && reset --hard`/reclone, the personal layer gets stash-and-flag-never-discard (`ecosystem-architecture.md` §5.2, A-H11). That safety model assumes org/dept clones are **disposable read-only mirrors**. **A writable tier is not a read-only mirror.** SOUL §9 logs this as a genuine foundational conflict: *"a writable tier is not a read-only mirror … must be resolved before write access opens to a second author."*

**The tension, stated precisely:** if the department clone on a machine is both (a) the thing Control Tower may `reset --hard`/reclone at will, and (b) the thing an author edits and has uncommitted local changes in, then a cadence sync could destroy an author's in-progress work — violating never-destroy's spirit, or forcing us to weaken it.

### 1.2 Problem 2 — Non-technical merge-conflict resolution

Owner's words (`interview-ground-truth.md` §6): *Bob the accountant edits a financial file in DEPARTMENT knowledge; a colleague edits the same file; they sync → merge conflict; **neither knows Git.*** It must resolve **elegantly, invisibly, with no data loss and no Git literacy** — ideally behind the scenes, else held safely and escalated in plain language. SOUL's anti-pattern **The Git-Error-To-A-Non-Technical-Person** makes this a hard line: *"Raw Git/VCS output is **never** shown to Bob. Resolution is non-technical by construction or it does not surface to a non-technical person at all."*

**The tension, stated precisely:** collaborative tiers are the product's own doing, so the conflict class is the product's to absorb — but invariant #1 (*parse, never compute*) forbids the **app** from implementing merge logic. So the resolution must be **computed in the CLI and merely rendered by the app**, and it must never expose Git.

### 1.3 Why the two problems are coupled

Both are the same seam viewed from two sides: **where an author's push meets a consumer's pull.** Problem 1 is "can a sync destroy local author work?"; Problem 2 is "when two authors' pushes collide, how does a non-technical person reconcile?" Both are resolved by the same structural move: **separate the authoring working copy from the read-only mirror, and route all cross-author reconciliation through a governed publish path in the CLI.**

---

## 2. Key insight / reconciliation — the tension is apparent, not real

### 2.1 The consumer is read-only by construction → never-destroy holds untouched for consumers

Trace the data to its consumer (the contract lives downstream, not at the Obsidian input surface):

- A **consumer** machine (Bob, and every non-author) runs the supervisor's `freshness → update` pull on cadence (`architecture.md` §3; service-blueprint W4). Its org/dept clones are **read-only mirrors**: `copilot update` does `git fetch && reset --hard`/reclone (`ecosystem-architecture.md` §5.2).
- A consumer **never commits to the shared clone locally.** Bob edits *only* through `copilot add/edit skill --personal`, which writes the **personal layer** (a separate tree, separate remote), never the department clone (`ecosystem-architecture.md` §5.4, A-H14). Materialized `.claude/` is made read-only with fold-back-to-personal on drift.
- Therefore a consumer **cannot physically produce a local edit-conflict on shared content.** There is nothing dirty in the department mirror to conflict; `reset --hard` is always safe because the mirror is disposable and the only writable thing Bob owns (personal) is protected by never-destroy's existing stash-and-flag rule.

**Conclusion:** for the ~99% of machines that are consumers, **never-destroy holds exactly as written, unmodified.** Problem 1 does not exist on a consumer machine. The scary "Bob the accountant hits a merge conflict" scenario can only occur if Bob is an **author** of the department tier (see §2.4).

### 2.2 The author has a *writable working copy* — which is a protected personal tree, not a mirror

An author (Ada; or an author-Bob) additionally has a **writable authoring checkout** of the tier repo — the Obsidian vault she edits (service-blueprint W2). The clean architecture requires this to be **physically distinct** from the consumer read-only mirror that feeds resolution/materialization on the same machine:

| Tree | Purpose | Who writes it | never-destroy treatment |
|---|---|---|---|
| **Read-only mirror** (`~/.copilot/mirrors/<tier>`) | Feeds resolve → materialize | Only `copilot update` (fetch/reset/reclone) | Disposable — reset/reclone freely (**unchanged**) |
| **Materialized tree** (`~/.claude/`) | What the host scans | Only `copilot update` (reconciling sync) | Disposable — re-materialize freely (**unchanged**) |
| **Authoring working copy** (the tier-scoped Obsidian vault) | Where an author edits before publishing | The author (Obsidian) + `copilot publish` | **A dirty personal working tree → never touched** (**already covered by invariant #3 as written**) |

The decisive observation: **the author's authoring checkout is, for never-destroy's purposes, a "dirty personal working tree"** — it is human-owned, may hold uncommitted work, and invariant #3 *already* says never touch that. Control Tower re-materializes from the **mirror**, never from the authoring vault. So the two roles the tension conflated — "disposable mirror" and "human's live edits" — are **two different trees**, and each already has the correct, unchanged never-destroy treatment. Nothing is weakened; the model just has to make the separation explicit.

### 2.3 Conflicts live on the PUSH side — which never-destroy does not cover, and need not

Never-destroy is a statement about what Control Tower may do to the **local filesystem on the pull/materialize path**. A cross-author conflict is not a local-destruction event at all — it is a **remote non-fast-forward rejection** when `copilot publish` tries to push a tier commit whose base a colleague already advanced. That is:

- **On the push side**, which invariant #3 never addressed (it is about re-materializing and re-cloning, i.e. pull);
- **Non-destructive by construction** — the author's commit is safe in local history; the remote simply won't accept it yet;
- **The natural serialization point** — the remote is the single source of truth for tier order, so the *remote* (not local `flock`) is what serializes two authors on two machines. Local `flock` on `copilot.lock` (`cli-contract.md`) still self-serializes verbs *on one machine*; the remote serializes *across* machines.

**So Problem 2 is a new, additive, governed path (`copilot publish`), orthogonal to never-destroy.** Adding it does not touch invariant #3.

### 2.4 Residue — where the dissolution is not total

The consumer-read-only / author-writable split fully dissolves the *invariant tension*. Three residues remain — each already contained by an existing mechanism, none reopening invariant #3:

1. **A consumer promoted to author.** Promotion (service-blueprint W1) is a **provisioning event**: add a writable authoring checkout + a write credential; it does not convert the existing read-only mirror into a writable tree. After promotion the machine simply has *both* trees (§2.2). No safety-model change — only a new tree that never-destroy already protects. *(The write **credential** is the F16 credentials-carrier problem — out of scope here; see §6.)*
2. **The personal tier is writable by definition.** Already handled: personal is **single-writer** (one individual owns it), so there is no *inter-author* conflict. The only collision is an author's **own two machines** (Mac Mini + laptop — `interview-ground-truth.md` §2), which is a self-vs-self rebase: auto-mergeable when hunks don't overlap, and when they do, the same person can be asked the plain-language "keep both / choose" (§3) with zero ambiguity about authority. Personal↔shared crossing stays impossible by construction (separate trees/remotes — SOUL *The Leak*).
3. **"Bob the accountant" in the interview is an author-Bob.** The scenario presupposes write access to department knowledge, so that Bob is a *trained early-adopter author* who still doesn't know Git — the exact target of §3. A pure-consumer Bob never reaches this path. This is a **persona clarification worth recording**, not an architectural gap.

**Net:** Problem 1 dissolves without touching invariant #3. Problem 2 is real and needs the mechanism in §3, but lives entirely on the additive publish path.

---

## 3. Options for Problem 2 (non-technical conflict resolution)

All options assume the **two-lane model** (service-blueprint W1–W5): authors *push* via `copilot publish`; consumers *pull* on cadence. The design question is only **how `copilot publish` reconciles two authors of one tier without Git literacy or data loss.** Merge logic lives in the **CLI** in every option (invariant #1); the app at most renders a plain-language choice and passes it back as a parameter.

### Option A — Pull-before-publish auto-rebase + auto-merge non-overlapping hunks *(the workhorse)*

`copilot publish` fetches the tier remote, rebases the author's local tier commits onto the new tip, and lets Git **auto-merge line/hunk ranges that don't overlap** (Git already does this cleanly on rebase/3-way merge). Two accountants editing *different* sections of the same file merge silently.

- **Data loss?** No — non-overlapping merges are lossless by definition.
- **Git literacy?** None — happens inside the verb; the author sees "publishing to Finance… published" (service-blueprint W3).
- **Lives where?** **CLI** (`copilot publish --json`). App renders progress only.
- **Limit:** does nothing for a *true overlap* (same lines). Needs Option B behind it.

### Option B — Plain-language "two versions: keep yours / keep theirs / keep both" *(the overlap resolver)*

On a true overlap, the CLI does **not** emit Git conflict markers. It emits a **structured** `--json` conflict describing the collision in content terms, and offers non-destructive resolutions:

```
copilot publish --json  → { conflict: true, tier: "finance", file: "close-checklist.md",
    section: "Q3 close steps",
    yours:  { author, ts, rendered },
    theirs: { author, ts, rendered },
    base:   { ts, rendered },
    resolutions: ["keep-yours", "keep-theirs", "keep-both", "escalate"] }
```

The app renders: *"You and Maria both changed the 'Q3 close steps' section. Keep yours · Keep Maria's · **Keep both** (side by side) · Ask the Finance lead."* The chosen resolution is passed back as a parameter — `copilot publish --resolve keep-both` — and the **CLI applies it and completes the push.**

- **Data loss?** No — **keep-both is always offered and is the safe default framing** (nothing is discarded; both versions land side-by-side for a human to reconcile in content, never in Git).
- **Git literacy?** None — the author picks between *rendered content versions*, never hunks or markers.
- **Lives where?** **CLI** computes the conflict, produces both rendered versions, and applies the chosen resolution. **App renders the chooser only** — zero merge logic in the app (invariant #1 intact; SOUL Case-Law "invisible merge-conflict resolution → IN").

### Option C — Hold-and-escalate to a competent author *(the safety net for sensitive classes)*

For a **sensitive file class** (e.g. anything under a `finance/` or policy-flagged path where a wrong merge loses money), or when the author declines to choose, `copilot publish` **parks the local change safely** (a held ref / server-side branch — never lost) and escalates in plain language to a competent author / tier lead: *"Maria also edited this. Your version is saved. The Finance lead will reconcile."*

- **Data loss?** No — the change is parked on a durable ref, not dropped.
- **Git literacy?** None — the author sees a held-and-escalated sentence; the *tier lead* (a more comfortable author) reconciles, still via Option B's content-level chooser, never raw Git.
- **Lives where?** **CLI** parks + emits the escalation signal; escalation routing reuses the **Bob-agency competence model** (`architecture.md` §9) — route to the competent actor, never dump on the non-competent one. App/IT channel renders the plain-language state.

### Option D — Advisory soft-lock / check-out + fine-grained files *(collision *prevention*, structural)*

Reduce P(collision) so A–C rarely fire: (i) an **advisory soft-lock** ("Maria is editing 'close-checklist' — edit anyway?") surfaced at publish/open time from a lightweight lock convention in the tier repo; and (ii) an **ecosystem-repo structural convention** favouring many small single-topic files over monoliths, so two authors rarely touch the same file.

- **Data loss?** No (it prevents, doesn't resolve).
- **Git literacy?** None.
- **Lives where?** **Ecosystem repo structure** (file granularity) + **CLI** (advisory lock read/write). *Cannot be a hard lock* — offline authors and the personal two-machine case (§2.4) would deadlock. Advisory only.

### Recommendation — a layered combination (A → B → C, with D as friction-reducer)

Ship a **layered** `copilot publish` where the deterministic guarantee rises with each layer, exactly as the ecosystem's own routing spine is layered (`ecosystem-architecture.md` §5.6):

| Layer | Mechanism | Guarantee | Home |
|---|---|---|---|
| **L0** (prevention) | Option D — fine-grained files + advisory soft-lock | Fewer collisions ever occur | Ecosystem repo structure + CLI |
| **L1** (workhorse) | Option A — pull-before-publish auto-rebase + non-overlap auto-merge | Silent, lossless resolution of the common case | **CLI** (`copilot publish`) |
| **L2** (overlap) | Option B — content-level keep-yours/theirs/**both** chooser | True overlaps resolved with no data loss, no Git | **CLI** computes; **app** renders the choice |
| **L3** (safety net) | Option C — park-and-escalate to a competent author | Sensitive/declined cases never lost, never dumped on the non-competent | **CLI** parks; **Bob-agency §9** routes |

This is the mechanism SOUL Case-Law already ratified **IN** ("auto-merge non-overlapping edits; plain-language keep-both/choose for a genuine collision; hold-and-escalate if unsafe") and that service-blueprint W5 sketches — now assigned to concrete homes. **Keep-both is the always-available floor**, so *no path ever loses data*; **escalate is the always-available exit**, so *no non-technical person is ever cornered by a Git decision*.

---

## 4. Where each piece lives (invariant #1: parse, never compute)

| Concern | Home | Rationale |
|---|---|---|
| Tree separation (mirror vs authoring vault vs materialized) | **Ecosystem / CLI provisioning** | The safety model is a filesystem-layout contract the CLI owns; Control Tower only *reads* which is which. |
| Pull-before-publish rebase, non-overlap auto-merge | **CLI** — new `copilot publish --json` verb | It computes a merge → by definition CLI, not app. |
| Conflict detection + rendering both content versions + applying a chosen resolution | **CLI** — `copilot publish --json` emits the structured conflict; `--resolve <choice>` applies it | Merge computation and application are CLI; the app supplies only the human's choice. |
| Park-and-escalate on sensitive/declined | **CLI** parks the ref; **`architecture.md` §9 Bob-agency** routes the escalation | Reuses the existing competence-routing lane; no new escalation engine. |
| Advisory soft-lock | **CLI** reads/writes the lock convention | Advisory state is CLI-owned; app renders "Maria is editing." |
| Leak-scan on publish (tier-scoped, fail-closed) | **CLI** (`copilot publish` refuses cross-tier / personal content) | Enforces SOUL *The Leak* by construction on the push path — service-blueprint W3. |
| **Rendering** the "keep yours/theirs/both/escalate" chooser and the "publishing… / published / held-escalated" states | **App** (Operator surface, or a light authoring affordance) | The app **renders CLI-computed options and passes back a choice** — it implements **zero** merge logic. Same "parse, never compute" contract as every other verb. |

**Contract addition (WS-A):** add **`copilot publish --json`** to the versioned CLI contract in `cli-contract.md`, alongside `doctor/update/resolve/deprovision/freshness`. It carries: `{schema_version, tier, result, conflict?, resolutions[], parked_ref?, escalated_to?, leak_scan}`; **missing security-relevant fields fail closed** (a missing `leak_scan`/`tier` ⇒ refuse to publish), matching the contract's existing fail-closed rule. A CI contract test asserts the schema, same as every other verb.

> **Note on primacy (SOUL Founding Decision #2, Bob-first).** Control Tower's Operator surface is the *consumer* client first. `copilot publish` and the author flow are the **subordinate author-tier enabler** (SOUL §9, a HYPOTHESIS — never run with >1 writer). This RFC specifies the CLI contract and where rendering *would* live; it does **not** commit Control Tower's Operator UI to hosting the authoring/publish experience in v1. Whether publish is rendered by Control Tower, by a dedicated authoring affordance, or by Obsidian tooling is an open UX decision (§6) — but the **computation is CLI regardless.**

---

## 5. Invariant impact

- **Invariant #1 (parse, never compute): KEPT INTACT.** All merge/rebase/conflict/apply logic is in `copilot publish` (CLI). The app renders CLI-computed options and passes back a choice. No merge logic in the app — verified by the same code-review gate SOUL §6 already mandates.
- **Invariant #3 (never-destroy): KEPT INTACT — no wording change required.** The reconciliation (§2) works *because* it uses invariant #3 exactly as written: the mirror stays a disposable read-only mirror; the authoring vault is "a dirty personal working tree" the invariant *already* forbids touching; conflicts live on the additive push path the invariant never governed. **This RFC's recommendation does not require refining invariant #3.**
- **Invariant #4 (security posture never weakened): REINFORCED.** `copilot publish` is tier-scoped and fail-closed (SOUL *The Leak* — no personal content has a route into a shared remote); no `--force` push, no `--skip-verify`; publish participates in the same signed/policy-gated pipeline.
- **Invariants #2, #5:** untouched. `flock` still self-serializes local verbs; the remote serializes cross-author. Escalation routes by the §9 competence model.

### Optional clarifying elaboration of invariant #3 — REQUIRES OWNER RATIFICATION

The invariant **holds as written**; the recommendation needs no change. However, because SOUL §9 flagged this as a foundational conflict, the owner *may* wish to record the mirror/vault distinction *in the invariant itself* to remove future ambiguity. This is a **clarification, not a weakening** (it narrows nothing and grants Control Tower no new power). Proposed elaboration — **not adopted unless the owner ratifies it**:

> **3. Never-destroy.** May freely re-materialize `.claude/` and re-clone read-only **mirrors** (the clones that feed resolution); **never** touches a **human-owned working tree** — a dirty personal tree *or an author's tier-scoped authoring checkout*, which are distinct trees from the mirrors. Cross-author reconciliation happens only on the governed **publish** path (`copilot publish`) against the remote, never by destroying a local tree.

**Recommendation: KEEP invariant #3 exactly as written** and treat the above as documentation in this RFC and the architecture, unless the owner prefers the invariant text carry it. **Owner decision required — do not assume.**

---

## 6. Residual unknowns / open questions

1. **[BIGGEST] The credentials-carrier (F16, SOUL §9 open #1).** The entire writable/publish path presupposes an author's **write credential** reaching her machine safely in a *pull-based* model with **no cloud secret store**. This doc assumes provisioning exists; it does not solve it. **This gates whether any of §3 can ship** and must be resolved by the security/threat-model work before write access opens to a second author. Tracked as the one carried-forward seam in **§7**; the security-side design lives in [`proposals/credentials-and-boundary.md`](proposals/credentials-and-boundary.md). *(Explicitly out of scope here; the single largest dependency.)*
2. **Keep-both semantics for a structured financial file.** "Keep both" is lossless at the document level but can produce a file a human must still reconcile in *content* (two versions of a number). Where is the line between "author chooses (Option B)" and "auto-escalate a sensitive class (Option C)"? Proposed default: **path/class-flagged sensitive files skip straight to L3 escalate**; needs owner input on which classes.
3. **Tree-layout & Obsidian binding.** Exact on-disk locations for mirror vs authoring vault vs materialized tree, and whether the existing `.obsidian/` vault binds to the authoring checkout — must be specified so a cadence `reset --hard` on the mirror can never touch the vault.
4. **Advisory-lock UX and offline authors.** Soft-lock cannot be hard (offline/two-machine deadlock). Needs prototyping for how stale locks expire and how "edit anyway" reads to a non-technical author.
5. **Where publish is rendered (UX primacy).** Control Tower Operator surface vs a dedicated authoring affordance vs Obsidian tooling (§4 note). Bob-first says the consumer client leads; the author lane is a subordinate enabler and unvalidated (SOUL §9, HYPOTHESIS) — do not over-commit UI.
6. **Multi-writer validation.** The whole authoring loop is **MODEL-IN-HEAD — never run with >1 writer** (`interview-ground-truth.md` §9). §3 should be prototyped with two real authors before ratification.

## 7. Carried-forward seam — author git-push-credential provisioning (open follow-up)

The publish path in §3 is **specified in principle but not fully worked** on exactly one point: **how an author's git-push credential is provisioned to her machine.** Everything downstream of "the author holds a write credential for the tier remote" is designed here (rebase, auto-merge, the content-level chooser, park-and-escalate, the `copilot publish --json` contract). The step *upstream* of it is not:

- **Where it leans.** The intended mechanism is the **four-tier SSH-alias model** — the `ssh-personal` / `ssh-work` / `anon` / `gh-app:<slug>` aliases that `reference/four-tier-topology.md` §6.1 already chose for multi-account git auth. An author's dept/org write credential is meant to be the `ssh-work` (or a tier-scoped `gh-app:<slug>`) identity, provisioned once at promotion (§2.4). This reuses existing machinery rather than inventing a new carrier.
- **Why it is not closed here.** Provisioning that credential **safely, in a pull-based model with no cloud secret store**, is the credentials-carrier problem (F16 / SOUL §9 open #1) — a *security-architecture* question, not a publish-path question. It gates whether any of §3 can ship to a second author, but its resolution is out of scope for this doc.
- **Where it is worked.** The security-side design (STRIDE/DREAD, the personal↔shared leakage wall, and how a forced/managed-domain carrier satisfies invariant #4) lives in [`proposals/credentials-and-boundary.md`](proposals/credentials-and-boundary.md) — **still a draft RFC, not yet ratified.** This doc's ratification does **not** ratify that one; the seam stays explicitly open until the credentials carrier is resolved and write access opens to a second author.

**Net:** the publish contract is ratified and can be frozen (WS-A) independently; the author-credential provisioning that feeds it is the single carried-forward dependency, tracked against the credentials RFC.

---

*END — RATIFIED 2026-07-07 (owner). This doc closes SOUL §9 open problem #3 (writable-tier vs never-destroy) and specifies the mechanism for F15 (non-technical conflict). It does **not** close F16 (credentials-carrier), which gates it — the carried-forward seam tracked in §6 (open #1) and §7.*
