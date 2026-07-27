# Release & Versioning Policy

Two independent version surfaces ship out of this repo, and this policy exists because they must never be conflated: the **app binary** (Control Tower.app) and the **`--json` contract** (`schema_version`, defined in [`../01-architecture/cli-contract.md`](../01-architecture/cli-contract.md) and the schemas in [`../01-architecture/schemas/`](../01-architecture/schemas/)). A contract change and an app change can each trigger a release on their own; this doc orders what happens when either does.

Related: [`../01-architecture/architecture.md`](../01-architecture/architecture.md) §7 (self-update) and §8.3 (signed-inherited-config managed keys), [`design-distribution.md`](../03-design/design-distribution.md) §1 and §4 (signing/notarization detail, superseded on process model only), [`../05-security/credentials-and-boundary.md`](../05-security/credentials-and-boundary.md), [`../05-security/threat-model.md`](../05-security/threat-model.md) (B4, the self-update trust chain).

---

## 1. Semver policy

### 1.1 The app binary

Control Tower.app is versioned `MAJOR.MINOR.PATCH` (standard semver). What triggers each:

- **MAJOR** — a change that breaks the compat matrix's guarantee to an existing CLI range (e.g. the app drops support for a `schema_version` floor a supported CLI still emits), or a change to a signed-inherited-config managed key's meaning (any org relying on the old semantics of `AllowSelfUpdate`, `UpdateFeedURL`, etc. would misbehave).
- **MINOR** — new capability that doesn't change existing behavior for a fleet that ignores it (new Admin-mode step, new Needs-attention state, widening a `min_schema`/`max_schema` range to admit a newer CLI without dropping the old floor).
- **PATCH** — bug fix, security fix, or dependency bump with no behavior change to the contract or managed-key surface.

### 1.2 The `--json` contract (`schema_version`)

This is the safety boundary (`cli-contract.md`: "schema drift = silent security bypass"), so its versioning rule is stricter than the app's and independent of the app's version number. `schema_version` is `MAJOR.MINOR[.PATCH]` per verb (per `_envelope.schema.json`'s `$defs/schema_version` pattern).

- **Breaking (schema MAJOR bump)** — any of:
  - Removing a field, or narrowing/renaming an enum value, that Control Tower currently reads.
  - Changing the meaning of a security-relevant field (`destructive`, `signed`, `severity`, `tier`, `leak_scan`, `secrets_touched`, `live_hash_matches`) — these fail closed on absence today, so redefining what "present" means is breaking even if the field's *name* doesn't change.
  - Changing an exit-code contract (e.g. what `0`/`1`/`2` mean for a verb).
  - Anything that would make a value the app currently treats as safe become unsafe, or vice versa, without the app's knowledge.
- **Compatible (schema MINOR or PATCH bump)** — adding an optional field, adding a new (additive) enum member the app doesn't yet branch on, adding a new verb, tightening a schema's `required` list in a way that only makes previously-optional-but-always-emitted fields formally required (no behavior change for a conformant CLI).

**The governing rule: the app must handle a contract MINOR bump gracefully — parse, never assume.** Concretely:
- The app declares a `min_schema`/`max_schema` range per verb (already specified in `cli-contract.md`) and range-gates **bidirectionally** — a CLI schema older than the floor is exactly as fatal as one newer than the ceiling (see [`../01-architecture/error-taxonomy.md`](../01-architecture/error-taxonomy.md), "Version-mismatch"). This is unaffected by MAJOR-vs-MINOR: any out-of-range schema is refused, in-range is parsed.
- Within the declared range, an unrecognized *additive* field or enum member is ignored, not fatal — the parser must not exhaustively-match on closed enums for forward-compat fields. A schema MINOR bump inside the app's already-declared `max_schema` ceiling must never require an app release to keep working.
- **Missing security-relevant fields fail closed** regardless of schema version (absent `destructive`/`signed`/`severity`/`tier`/`leak_scan` ⇒ treated as destructive/unsigned/fail/refuse). This rule does not move with versioning — it is invariant.

### 1.3 The app↔CLI compat matrix

Because the app version and the contract version move independently, the app publishes a compat matrix (`controltower.compat.json`, the Control Tower-renamed successor to the `aviator.compat.json` reference in `design-distribution.md` §4) declaring, per app version, the `copilot`/`cc` version ranges and `schema_version` range it supports. Publication and consumption order:

1. A `copilot`/`cc` change lands in `claude-copilot` that bumps `schema_version` (see the CI contract test requirement in `cli-contract.md`).
2. `claude-copilot` CI publishes the new universal CLI artifact at a pinned SHA+version with its upstream Developer ID signature and accepted Apple notarization record (the cross-repo signing contract — Control Tower CI verifies, never re-signs). Apple does not support stapling standalone-binary tickets, so offline Gatekeeper proof is performed after the unchanged helper is nested in the final notarized and stapled Control Tower app/DMG.
3. Control Tower CI checks the new CLI's `schema_version` against the **currently-released** app's `max_schema`. If it's within range, no app release is required — the compat matrix already covers it (this is the MINOR-bump-graceful-handling guarantee from §1.2).
4. If the new CLI's `schema_version` exceeds the released app's `max_schema` (or the CLI moved MAJOR), the compat matrix is what surfaces the mismatch: the app refuses to drive an out-of-range CLI and shows "versions don't match — click to update" rather than misbehaving. A **newer CLI pulls a newer Control Tower** release (never the reverse) — Control Tower CI blocks its own release if the vendored CLI is older than that release's declared compat floor.
5. `controltower.compat.json` is published alongside each app release artifact (same release pipeline as the signed manifest, §2) so both the app (self-check on launch and pre-update) and any fleet-monitoring tooling can read it without invoking the CLI.

`AllowSelfUpdate=false` fleets receive CLI+app as a version-locked pair in one pkg — the compat matrix still applies but is resolved once at packaging time rather than continuously.

---

## 2. Release channels

Two channels, gated by the same signed-inherited-config managed keys the architecture already defines (§8.3); no separate channel-gating mechanism is introduced here.

- **`stable`** — the default channel; what `UpdateFeedURL` points to when unset. Only a **schema-compatible** app build per §1.2/§1.3 is promoted here.
- **`beta`** (and a `pinned:<version>` pseudo-channel for IT-forced version locks) — pre-release builds and org-specific pins. Selected via the managed `UpdateChannel` key.

Both channels are read **only from the signature-verified, inherited org/foundation config** for the security-sensitive keys, `UpdateFeedURL`, `AllowSelfUpdate`, `UpdateChannel` if set alongside them, per invariant #4 and architecture §8.3: a value from an unsigned or tampered local copy is ignored in favor of the compiled-in default and logged as a tamper event. `AllowSelfUpdate=false` disables the channel entirely; the org must publish updates through its own channel/mirror instead.

**Signed/notarized artifact flow** (detail lives in `design-distribution.md` §1/§4 and the threat model; this policy references it, not redesigns it):

1. `tauri build` produces the universal `.app`.
2. Developer ID codesign (hardened runtime, inside-out order) + notarize + **staple** both `.app` and `.dmg` — required before any channel promotion, `stable` or `beta`.
3. The update manifest (`latest.json`: version, notes, per-platform `url` + `signature`) is signed with the **minisign key**, held in custody separate from the Developer ID cert. Per the threat model (B4, B-M4), this is **two-of-N signing or a transparency-log witness** — a single popped key must not be sufficient to promote a release to any channel. Signing custody assignment (who holds the second key) is tracked as an open decision in the architecture doc and must be resolved before `stable` promotion is enabled in CI, not worked around.
4. The watchdog verifies the staged bundle is stapled **offline** before promoting it (no dependency on reaching Apple's notarization CDN at swap time) — this is what makes air-gapped/proxy fleets on an internal `UpdateFeedURL` mirror safe to auto-update.
5. Only after 1–4 succeed does a build become eligible for either channel; `beta` vs `stable` is a promotion decision, not a different build pipeline.

For the hands-on publisher setup path (CSR, G2 Sub-CA certificate, G2
intermediate trust fix, **Publisher Setup.app**, local release env,
`scripts/setup-publisher.sh` fallback, `sign.sh`, and `notarize.sh`), see
[`publisher-release-runbook.md`](publisher-release-runbook.md).
Keep that publisher path separate from the Admin/IT deployment path in
[`../06-deployment/standup-runbook.md`](../06-deployment/standup-runbook.md):
the publisher signs artifacts; the administrator configures and deploys them.

---

## 3. Changelog conventions

Keep-a-changelog style (`Added` / `Changed` / `Deprecated` / `Removed` / `Fixed` / `Security`), one entry per release, ordered newest-first. A release note must state, in addition to the normal summary:

- **Whether `schema_version` moved**, and if so, whether it was a MAJOR (breaking) or MINOR/PATCH (compatible) bump per §1.2, plus the resulting `min_schema`/`max_schema` range the app now declares. This is not optional — it's the field a fleet operator reads to know whether they must re-check their CLI version before updating.
- **Security fixes** get their own `Security` entry regardless of how small, cross-referencing the threat-model finding ID (`B-M4`, `B-C5`, etc.) it closes or narrows, matching the convention already used in `threat-model.md` and `architecture.md` ("fixes B-C4").
- **Compat-matrix changes** — any change to the `copilot`/`cc` version range or the `schema_version` range in `controltower.compat.json` gets an explicit line, since it's what an IT admin checks before approving a fleet-wide promotion to `stable`.
- **Deprecations** (§4) are announced in the changelog at the point of deprecation, not just at removal.

---

## 4. Deprecation policy

The never-break-a-running-fleet rule: a CLI verb/field, a schema field, or an app capability is never removed in a way that turns an already-running, self-healing fleet member into a hard failure without a warning cycle it can act on. Order of operations for deprecating any of the three surfaces:

1. **Mark deprecated, keep emitting/accepting.** The CLI continues to emit a deprecated field (or accept a deprecated verb form) unchanged; the app continues to read it. The changelog entry (§3) states what's deprecated and what replaces it.
2. **Dual-emit/dual-accept, if the replacement isn't purely additive.** If a field is being renamed or restructured (not just superseded by a new optional field), the CLI emits both the old and new forms for at least one full schema MINOR cycle so an app still on the old `max_schema` ceiling and an app already updated to read the new field both function.
3. **Removal is a schema/app MAJOR event only**, never silent. Removing a deprecated field or verb is exactly the "removing a field the app currently reads" case from §1.2 — it requires a schema MAJOR bump, which the bidirectional `min_schema`/`max_schema` gate then correctly refuses to parse against an app that hasn't caught up, surfacing "versions don't match — click to update" instead of a silent misread.
4. **Security-relevant fields are never deprecated by omission.** Because absence of `destructive`/`signed`/`severity`/`tier`/`leak_scan` fails closed (treated as destructive/unsigned/fail/refuse), a security field can't be "soft-deprecated" by the CLI simply no longer emitting it — that would silently fail closed on every consumer, which is safe but is an outage, not a deprecation. It must go through the explicit MAJOR removal path in step 3, called out in the changelog as a `Security`/`Removed` entry.

This mirrors the same intersect-ranges model the compat matrix already uses for layer `requires` — deprecation is a range-narrowing event, never a silent break.

---

## 5. Rollback

Rollback is a property of the **watchdog**, not the new bundle — the bundle that might be broken cannot be trusted to roll itself back.

Trigger order for a bad self-update:

1. The updater downloads the new bundle, verifies the minisign signature (refuses install on failure — no `--skip-verify`/`--force` path exists, invariant #4), and verifies it's stapled offline (§2 step 4) before staging.
2. The stable watchdog (itself never self-updated) launches the staged bundle with `--self-test` and waits for an early liveness heartbeat file.
3. **No heartbeat within the launch attempt ⇒ automatic rollback**: discard the staged bundle, keep the current (previously-working) version running, mark the failed version poisoned (so the same channel doesn't re-offer it), and notify.
4. A poisoned version is excluded from that channel until a new build supersedes it — `stable` never re-serves a version its own watchdog rejected.
5. **IT-forced rollback**: independent of the watchdog's automatic path, `UpdateChannel=pinned:<known-good-version>` (set in the signed, inherited org config) lets IT force a downgrade/pin across an org without waiting on individual watchdog verdicts. This is the `AllowSelfUpdate=false`-adjacent lever for an org that wants to hold at a version regardless of what `stable` currently serves.
6. **Floor guarantee**: if the watchdog itself is ever the broken part (a bug in the updater breaking updating), the bootstrap install can be re-run from scratch (the same admin-free userland re-materialization the app already guarantees elsewhere), and the user (or admin, on their behalf) can reinstall a known-good signed `.dmg` from the org's release page over the top. There is no remote force-push in this model (D4); recovery is a manual reinstall. The never-destroy invariant means this reinstall path never touches a dirty personal working tree.
