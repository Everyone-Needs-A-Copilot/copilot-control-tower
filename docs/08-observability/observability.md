# Observability & Telemetry — Closing the Named Ecosystem Gap

| | |
|---|---|
| **STATUS** | **Canonical.** Normative spec for both telemetry channels. Supersedes the illustrative sketch in `../03-design/design-integration.md` §6 (kept as source material only — its `machine_id` formula is superseded by §5 below, per the B-H5 fix). **Conformed 2026-07-09 to `cse-alignment-decisions.md` D4:** MDM is dropped completely; `AdminContact` and every other security-sensitive telemetry-config key are honored only from the signed, inherited org/foundation config, never an MDM-forced domain. There is no MDM-enrolled fleet in this product: §7.1's IT view is a rollup of per-machine health from machines opted into an org's own collector, never a fleet score, and is explicitly not Admin mode's center of gravity. |
| **Reads on** | [`architecture.md`](../01-architecture/architecture.md) §8.3 (`AdminContact`), §9 (the Bob-agency escalation model, the named gap), [`error-taxonomy.md`](../01-architecture/error-taxonomy.md) (severity/exit-code vocabulary, reused not reinvented), [`../05-security/credentials-and-boundary.md`](../05-security/credentials-and-boundary.md) (the secrets/PII boundary this pipeline must never cross), [`../05-security/threat-model.md`](../05-security/threat-model.md) §2.5/§2.6/§3 (the `AdminContact` inherited-org-config gap this spec closes), `../CLAUDE.md` invariants #1, #4, #6. |
| **Governing rule** | Invariant #1 applies to telemetry exactly as it applies to health status: **Control Tower computes no analytics and assigns no severity of its own.** Every field in every payload below is a 1:1 copy of a value the CLI already computed (`doctor`/`update`/`resolve`/`freshness --json`) or a structural fact the OS already exposes (hardware UUID). If a field isn't already sitting in a parsed CLI payload, it does not belong in a telemetry event. |
| **Scope** | Both telemetry channels end-to-end: schema, transport, delivery semantics, the dashboards they feed, and the privacy guarantees that bound them. Does not re-derive the escalation *logic* (architecture.md §9 owns that) — this doc specifies the **wire format and privacy contract** for what §9 already decided to escalate. |

> **Why this doc exists.** The ecosystem's own walkthrough names Observability as the one open gap: *"no telemetry on what actually gets used, corpus health, or adoption — you can't improve what you can't measure."* Control Tower closes it. There is no MDM-enrolled fleet in this product (`cse-alignment-decisions.md` D4): observability here means honest, per-user, per-machine health, aggregated only across the machines that have opted their org into telemetry, never a blended or computed score. The same always-on position that lets it measure usage across an org's own machines is also the single biggest data-exfiltration surface in this product (`threat-model.md` B7). Closing the gap and holding the leakage wall (`credentials-and-boundary.md`) are the same design problem, solved together below.

---

## 1. Two channels, kept separate — the one-line rule

There are **two independent telemetry systems**, not one system with an opt-in flag. They have different defaults, different endpoints, different payloads, and different failure modes. Conflating them was the exact shape of finding **A-C5** (safety escalations silently gated behind an off-by-default analytics toggle) — this doc keeps them structurally apart so that mistake cannot recur.

| | **Safety / IT-escalation channel** | **Analytics channel** |
|---|---|---|
| **Carries** | Content-free *signals* that something requires IT action: `sig-fail`, `auth-revoked`, `policy-conflict`, `stalled-onboarding`, `persistence-disabled`, `notifications-off` | Aggregate *health/usage* facts: sync state, drift counts, auth-expiry, version skew, usage/adoption counts |
| **Default** | **ON by default for every machine with `AdminContact` configured.** Not a preference; a mandatory, signed-inherited-org-config key (`AdminContact`). | **OFF by default, everywhere.** Opt-in only via the org's own `ecosystem.yml` (`telemetry.enabled: true`, `telemetry.endpoint: <org-owned URL>`). |
| **Endpoint authority** | `AdminContact` — honored **only** from the signed, inherited org/foundation config, exactly like `UpdateFeedURL`/`FoundationMirror` (§6 below closes a gap the threat model found here). | `telemetry.endpoint` — read from the org's signed `ecosystem.yml`, never a local preference. |
| **Recipient** | The org's own IT (`AdminContact`) — never ENAC. | The org's own collector — never ENAC. |
| **Who it names** | May name a specific **org-authoritative identity** (e.g. an SSO subject IT already administers) — but **only** for categories where a named person is who must act. | **Never** names a person. Counts and layer-scoped item names only. |
| **Delivery guarantee** | At-least-once, durable, retried until acknowledged — a missed safety signal is the one outcome this channel exists to prevent. | Best-effort — a dropped analytics event costs a data point, not a security posture. |
| **Escalation-lane mapping** | The wire format for exactly the Bob-agency model's **lane 2 (Escalate to IT)** (`architecture.md` §9) — nothing from lane 1 (auto-act, silent) or lane 3 (ask Bob) ever reaches this wire. | Not lane-mapped — it is a passive health/usage snapshot, not an event stream tied to the escalation ladder. |

**The one-line rule:** *safety signals name what's broken, and — only when a specific person is the one who must act — who, because IT already owns that identity; analytics signals count what's used and by how many pseudonymous machines, never who, and neither channel ever reaches ENAC.*

**What each MUST NEVER carry (both channels, unconditionally):** file contents, prompts/completions, memory entries, task/work-product bodies, personal-layer item names or bodies, knowledge-doc text or search queries/results, secrets/credentials of any kind (`credentials-and-boundary.md` §1 — telemetry is not a carrier any more than git is), free-text `detail` strings from `doctor --json` checkers (those are for the operator's own UI, never for the wire), IP address or device serial, or any `$HOME`-relative file path beyond a layer-relative item name.

---

## 2. Severity & category vocabulary (reused, not reinvented)

Telemetry does not invent its own severity scale — it mirrors the CLI's, per invariant #1.

| Vocabulary | Source | Reused as |
|---|---|---|
| `severity ∈ {pass, warn, fail}` | `error-taxonomy.md` §1 (canonical checker verdict); `_envelope.schema.json` `$defs.severity` | Every safety-channel event's `severity` field is a direct copy of the triggering checker's severity — always `fail` in practice, since only `fail`-class findings escalate to IT (`error-taxonomy.md` §2 "Blocked"/"Auth-revoked" categories). |
| `escalate ∈ {none, user, it}` | The CLI's per-checker escalation hint (already sampled in `doctor --json`'s `auth-live` checker, `design-integration.md` §1.1) | Formalized here as a required field on any checker whose finding can reach the wire. Only `escalate: it` findings are eligible for the safety channel — this is the field that decides lane membership in the Bob-agency model (`architecture.md` §9), not a judgment Control Tower makes. |
| `exit ∈ {0, 1, 2}` | `error-taxonomy.md` §1 | Not carried in telemetry payloads directly — exit code is a transport-layer signal for the CLI invocation itself, already fully consumed by the app's own state machine before a telemetry event is ever constructed. |

### 2.1 Safety-channel categories, mapped to their CLI source

| Category | Triggering condition | CLI/system source |
|---|---|---|
| `sig-fail` | `signature-verify` checker returns `fail`, or a `publish`/`update` payload carries a `severity_trailer: security` on a blocked item | `doctor --json` checkers; `update --json` `blocked[]` |
| `auth-revoked` | `auth[].state == "revoked"` (permanent — distinct from transient `expired`, which stays app-local per `error-taxonomy.md` §2) | `doctor --json` `auth[]` |
| `policy-conflict` | A `capability-policy` denial, or an `update --json` item in `blocked[]` for a policy reason | `doctor --json`, `update --json` |
| `stalled-onboarding` | First-run wizard checkpoint has not progressed past a threshold window while `Waiting-for-network`/`IT-config-incomplete` persists | Wizard checkpoint state (`architecture.md` §4) |
| `persistence-disabled` | `SMAppService.status == .requiresApproval` (login item force-disabled), or the crash-watchdog's circuit breaker has tripped | `architecture.md` §3, §8.3 (B-H3) |
| `notifications-off` | Notification permission denied at the OS level, defeating the notify tier | `architecture.md` §9 (A-H10) |

No category above is computed by Control Tower — each is a direct translation of a field or state the CLI (or the OS API) already produced. The app's only job is picking the right envelope, never deriving the verdict.

---

## 3. Safety-channel schema

```json
{
  "schema_version": "1.0",
  "event_id": "b2e1e9d0-6f31-4b7a-9c2e-1a0f6d3c9e11",
  "sent_at": "2026-07-07T09:12:03Z",
  "machine_id": "6f1a9c...e2b4",
  "org": "acme-corp",
  "host": "claude-code",
  "category": "auth-revoked",
  "severity": "fail",
  "escalate": "it",
  "layer": "dept-finance",
  "identity": "bob@acme.com",
  "occurred_at": "2026-07-07T09:10:44Z",
  "escalation_deadline": null,
  "source_checker": "auth-live"
}
```

| Field | Type | Required | Meaning |
|---|---|---|---|
| `schema_version` | string | yes | Same versioned-contract pattern as every `--json` verb (`_envelope.schema.json`). |
| `event_id` | UUID | yes | De-duplication key for the at-least-once retry semantics (§4). |
| `sent_at` | ISO-8601 | yes | When the event left the machine (may differ from `occurred_at` under retry/backoff). |
| `machine_id` | string | yes | Pseudonymous, per-user, non-reversible — derivation in §5. |
| `org` | string | yes | The org slug the machine is enrolled under — an organizational fact, not personal data. |
| `host` | `claude-code \| codex` | yes | Which host the finding came from — per-host, matching the architecture's per-host status model. |
| `category` | enum (§2.1) | yes | One of the six safety categories. No free-text category is ever emitted. |
| `severity` | `pass \| warn \| fail` | yes | Copied verbatim from the triggering checker. Always `fail` in practice for this channel. |
| `escalate` | `none \| user \| it` | yes | Copied verbatim; only `it` reaches this channel — a structural filter, not a judgment call. |
| `layer` | `org \| dept-<slug> \| foundation \| null` | yes | The layer implicated, if any — never a personal-tier value (personal never reaches telemetry at all, §7). |
| `identity` | string \| null | no | The **org-authoritative** SSO/GitHub identity IT already administers (e.g. an IdP subject). Present **only** for categories where a specific person is who must act (`auth-revoked`, `stalled-onboarding`); omitted for machine-only categories (`sig-fail`, `persistence-disabled`, `notifications-off`, most `policy-conflict`). This is not new PII — IT already owns this identity↔employee mapping via its own IdP; Control Tower adds no identity IT doesn't already hold. |
| `occurred_at` | ISO-8601 | yes | When the underlying CLI finding was produced. |
| `escalation_deadline` | ISO-8601 \| null | no | Set for time-boxed Bob-actionable items that graduated to IT past a deadline (`architecture.md` §9, A-H13) — e.g. backup-missing, re-auth un-acted. |
| `source_checker` | string | yes | The `doctor`/`update` checker `id` that produced this event — a traceability key, never a free-text detail. |

**Never in this payload:** the checker's human-readable `detail` string, any repair token's arguments, any file path, any personal-tier reference.

---

## 4. Analytics-channel schema

```json
{
  "schema_version": "1.0",
  "org": "acme-corp",
  "sent_at": "2026-07-06T14:00:00Z",
  "machine_id": "6f1a9c...e2b4",
  "host": "claude-code",
  "app_version": "1.2.0",
  "sync": {
    "lock_sha": "2c8f1a3",
    "score": 82,
    "status": "needs-attention",
    "offline": false,
    "last_update_result": "applied"
  },
  "drift_events": [
    { "checker": "materialize-drift", "layer": "org", "count": 1 }
  ],
  "auth": [
    { "layer": "dept-finance", "state": "expired", "days_to_expiry": -1 }
  ],
  "version_skew": {
    "foundation_local": "5.13.0",
    "foundation_latest": "5.14.0",
    "behind_by": "minor"
  },
  "usage": [
    { "kind": "skill", "layer": "org", "name": "close-process", "fires": 12 },
    { "kind": "agent", "layer": "foundation", "name": "qa", "invocations": 8 }
  ],
  "adoption": { "components": ["claude", "knowledge"], "layers_resolved": 4 }
}
```

Field shapes are unchanged from the source material in `design-integration.md` §6.2 (this doc did not need to redesign a working schema) — **except** `machine_id`, whose derivation is corrected here per the B-H5 fix (§5). Note what is **structurally absent** from this schema and **must stay absent**: no `identity` field, no `category`/`severity`/`escalate` fields (analytics is not an event stream against the escalation ladder), no free-text anywhere. `auth[]` reports only `layer`/`state`/`days_to_expiry` — never the identity the safety channel is permitted to carry, because analytics has no actionability requirement that would justify naming a person.

`usage[]` and `adoption` emit **only** items whose CLI-computed winning layer (`resolve --explain`) resolves to `org`, `dept`, or `foundation` — an item shadowed by a personal override is dropped from usage entirely, never trusted by name alone (this is the B-H5 fix: don't infer scope from a string, read it from `winning_layer`).

---

## 5. `machine_id` derivation (canonical — supersedes `design-integration.md`)

```
machine_id = HMAC-SHA256(hardware_uuid || posix_uid, per_install_random_salt)
```

- **Per-user, not per-device.** Keying on `hardware_uuid + posix_uid` (not hardware UUID alone) means two people sharing one Mac get two distinct, non-colliding `machine_id`s — closing the collision half of B-H5.
- **Salt is per-install and random, never org-wide.** `design-integration.md`'s earlier `hmac_sha256(hardware_uuid, org_salt)` is **superseded** — an org-wide salt makes the HMAC a *stable, re-identifiable pseudonym* an admin could correlate against any device roster they separately maintain (the other half of B-H5; there is no MDM inventory in this product, D4). A per-install random salt, generated once at first run and never transmitted, means the same physical machine's `machine_id` cannot be correlated back to any org-maintained roster by any party who doesn't already control the machine.
- **Non-reversible.** Neither the hardware UUID nor the salt is ever transmitted — only the HMAC output. IT can count distinct machines and tell a stuck one from a healthy one; it cannot derive who owns which `machine_id` from the telemetry stream alone.
- **Stable across sessions, not across reinstalls.** The salt persists in the same per-user keychain entry the credentials mechanism already uses (`credentials-and-boundary.md` §1.4's storage pattern, reused rather than inventing a second local secret store) — so historical usage trend lines survive normal use, but a clean reinstall issues a fresh, unlinkable `machine_id`, which is the correct privacy default (no persistent device fingerprint that outlives the user's own uninstall).

---

## 6. Delivery semantics & the fail-closed/opt-in posture

- **Analytics is opt-in, fail-closed on absence.** No `telemetry.enabled: true` + `telemetry.endpoint` in the org's signed `ecosystem.yml` ⇒ **zero** analytics bytes leave the machine — not a reduced payload, not a default endpoint guessed from convention. This mirrors the same "absent ⇒ treated as the safe default, never guessed" posture `error-taxonomy.md` already mandates for missing security fields.
- **Safety escalation is on by default for any machine with `AdminContact` configured, fail-closed on its absence.** If no `AdminContact` is present (a solo install, or one with no org config synced, has no IT to notify), the safety *channel* emits nothing over the network — there is no endpoint to send to — but the underlying signal still surfaces **in-app** (popover/notification), because a solo user is the only actor who could ever act on it anyway (`architecture.md` §9, A-H10's fallback).
- **`AdminContact` MUST be honored only from the signed, inherited org config — closing the open threat-model gap.** `threat-model.md` §2.5/§3 found `AdminContact` was *not* in the enumerated list of keys honored only from the signed, inherited org/foundation config, alongside `UpdateFeedURL`/`FoundationMirror`/`HTTPSProxy` — meaning a local, non-admin write to local config could silently redirect every safety escalation to an attacker-controlled endpoint, fully defeating A-C5 without ever touching the escalation logic (DREAD ≈ 7.6, ranked the top open finding in that document). **This spec requires the fix as a hard precondition of the safety channel's design**: `AdminContact` is honored only from the signed, inherited org/foundation config exactly like the other security-sensitive keys; a value present only in local, user-editable config is ignored in favor of "no safety endpoint configured" (never silently substituted) and logged as a tamper event. The mechanical extension is one line in an existing enumerated list — see `threat-model.md` §3 rank #1 for the fix's own framing.
- **`telemetry.endpoint`/`telemetry.enabled` are honored only from the org's signed `ecosystem.yml`**, never a local preference domain, symmetric with the `AdminContact` rule above, so neither channel's destination can be locally spoofed.
- **Delivery guarantee is asymmetric by design.** Safety events are retried with backoff until acknowledged (durable, at-least-once, deduplicated on `event_id`) — a missed `auth-revoked` signal is the one failure mode this channel exists to prevent. Analytics events are best-effort and may be dropped under sustained offline/backoff — an incomplete usage snapshot costs a data point, not a security posture, and is never worth retry pressure on a metered/low-power connection (`design-integration.md` §5's battery/network etiquette applies identically here).
- **Notification-permission fallback (B-M7, A-H10).** If OS notification permission is denied, a `fail`-severity, `escalate: it` finding still opens the popover locally **and** still reaches the safety channel — the notification profile (`Notifications configuration profile`, B-M7) pre-authorizes the bundle precisely so this fallback isn't itself gated behind a permission a local attacker or an unaware Bob could deny.

---

## 7. The dashboard spec

### 7.1 The IT operator's view (Admin-mode telemetry view, `architecture.md` §8.1 item 6; visual spec in `product-design/04-experience-design/60-ui-design.md` §6)

There is no MDM-enrolled fleet in this product (`cse-alignment-decisions.md` D4), so this view is not a fleet inventory and is not the center of gravity of Admin mode (that is the repo/team/secret-store/seed-generator surface, D9). It is a rollup of the per-machine `doctor`/`update`/`resolve`/`freshness` snapshots that machines have chosen to send, over the analytics channel, to this org's own collector (opt-in, §6). A machine appears here only while it is actively reporting; there is no separate roster of entitled-but-silent machines to reconcile against.

Four per-machine health states, worst-wins per host, matching the product's own recurring framing (`architecture.md` §8.1, product-design vision/success-metrics docs): **Healthy / Stuck / Behind / Needs re-auth.**

| State | Sourced from | Machines-table rendering |
|---|---|---|
| **Healthy** | `sync.status == healthy`, no open safety events | Quietest row: a plain green dot + "In sync" — no emphasis, per the tray's own silence-is-success rule. |
| **Stuck** | `sync.status == needs-attention` with an unhealable `fail`, or an unresolved `policy-conflict`/`blocked` safety event | Amber badge + plain-language cell naming the failing checker/host — never a bare color. |
| **Behind** | `version_skew.behind_by` non-null, or `held_for_approval` non-empty | Dot badge; feeds the aggregate version-skew bar ("83% on current SHA," an honest fraction, never a gauge). |
| **Needs re-auth** | `auth[].state ∈ {expired, revoked}` for a required layer, or an open `auth-revoked`/`sig-fail` safety event | Key badge; revoked-state rows link directly into the safety-escalation feed (below), not just the table. |

**Machines table** — rows = the machines currently reporting to this org's own collector, same badge family as the tray glyph (shape + color + a plain-language cell, never color alone — a11y applies to the IT operator too), sortable by health family. **Never a computed "overall health 94/100" score, trophy ring, sparkline flourish, or any other blended metric** — a number that reads as computed-by-the-app implies a judgment the app never makes (`SOUL.md`, *The Second Pilot*, Case Law); this view stays an honest per-machine rollup, not a fleet score.

**Safety-escalation feed** — a separate, always-visible list sourced *only* from the safety channel (§3): each row is `category` + `layer`/`identity` (when present) + `occurred_at` + `escalation_deadline`, actionable and content-free. This is the wire realization of "IT notified is never a no-op" (`architecture.md` §9) — nothing in this feed is also shown to Bob (per the Govern-queue rule already specified in the UI doc), and nothing in it is a free-text description.

**Red/green preflight** and the **version-skew bar** are related Admin-mode surfaces but are **not** telemetry — preflight is a one-time, on-demand validation call before rollout (`architecture.md` §8.1 item 5), not a continuous signal from reporting machines; it is mentioned here only to keep this view's full surface legible, not because it shares this doc's wire format.

### 7.2 What the ecosystem owner (ENAC) sees: nothing from this pipeline

Per architecture.md §9 ("org-scoped, never ENAC") and the Soul's own founding decision (pure OSS, no hosted service — *The Ledger That Learns to Bill*): **there is no ENAC-side dashboard fed by either channel.** Analytics flows to the org's own collector; safety escalations flow to the org's own `AdminContact`. ENAC receives **zero** bytes from any deployed fleet, by construction — not by policy discipline, the same "impossible by accident" standard the leakage wall holds itself to. The only ecosystem-level visibility ENAC (or anyone) has into product adoption is the **public** OSS-project surface already exposed by GitHub itself (stars, release-download counts, issue volume on the public `copilot-control-tower` repo) — genuinely public data anyone can see, entirely out of scope for this telemetry pipeline, and never a hidden phone-home dressed up as "usage analytics."

---

## 8. PII / privacy guarantees

**Never collected, either channel, unconditionally:**
- Personal-layer content of any kind — no personal skill/agent/knowledge bodies, names, or counts.
- Knowledge contents — no doc text, title, or search query/result.
- Secrets, tokens, or credentials of any kind (`credentials-and-boundary.md` §1's rule 1 applies to telemetry exactly as it applies to git: no carrier, ever).
- Prompts, completions, memory entries, task/work-product bodies.
- File paths under `$HOME` beyond a layer-relative item name.
- Free-text `detail` strings, IP address, geolocation, or device serial.

**The one narrow, justified exception:** the safety channel's optional `identity` field (§3) — bounded to categories where a named person is who must act, populated only from an identity IT's own IdP already maps to that employee. This is not new PII exposure to a third party; it is the same identity fact IT already holds, delivered to IT, about that org's own machine, over that org's own configured endpoint. It never appears in the analytics channel, never leaves the org boundary, and never reaches ENAC.

**Fail-closed / opt-in posture, restated as the guarantee:** analytics telemetry is off until an org explicitly signs `telemetry.enabled: true` into its own `ecosystem.yml`; safety escalation requires an explicit, signed-inherited-org-config `AdminContact` value to leave the machine at all, and falls back to a local, in-app surface when absent rather than guessing an endpoint or silently dropping the signal. Neither channel's destination is ever honored from local, user-editable config (§6) — the same "security-sensitive state is honored only from a signed, trusted channel, never user-editable config" rule (`CLAUDE.md` invariant #4) that governs `UpdateFeedURL`/`FoundationMirror` governs `AdminContact`/`telemetry.endpoint` identically.

---

## 9. Where it lives — invariant #1 discipline

| Piece | CLI / ecosystem | Signed inherited org config | Control Tower (the app) |
|---|---|---|---|
| Finding computation (severity, escalate, `winning_layer`, `auth.state`) | **Owns it entirely** — `doctor`/`update`/`resolve --explain`/`freshness --json` already compute every field either payload carries | — | **No role** — never derives a severity, category, or layer scope of its own |
| Safety-event construction | — | — | Translates an already-`escalate: it`-tagged CLI finding into the §3 envelope — field copy only, no interpretation |
| Analytics-event construction | — | — | Translates the latest `doctor`/`update`/`resolve` snapshot into the §4 envelope on the org's configured cadence — aggregation (counts, not judgments) only |
| `machine_id` computation | — | — | Computes the HMAC (§5) from OS-exposed facts (hardware UUID, POSIX UID) + its own locally-generated, keychain-resident salt — a structural derivation, not a CLI verdict, so this is the one field the app is trusted to compute directly |
| `AdminContact` / `telemetry.endpoint` delivery | — | **Owns delivery of `AdminContact`** (signed inherited org config only, §6) | Reads both, honors neither from local, user-editable config; renders `IT-config-incomplete`-shaped state if a required key is malformed, never guesses a substitute |
| Transport (HTTPS send, retry/backoff) | — | — | Owns the wire send — this is automation of an already-decided signal, not computation of a new one (the borderline-capability test in `SOUL.md` §2: "renders or automates something the CLI already computed and verified, adds zero judgment of its own") |
| Dashboard rendering (IT view) | — | — | Renders the org's own collected events — no ranking, scoring, or health-verdict logic beyond the same worst-wins precedence the tray icon already uses |

**If Control Tower vanished, both pipelines would still be correct in the sense that matters:** the CLI's `doctor`/`update`/`resolve` JSON would still carry every fact either channel needs; only the *wire delivery* of those facts to IT/the org collector would stop, which is an availability property of the always-on app, not a computation the CLI depended on it for.

---

## 10. Consistency with the validation record

| Finding | Where addressed here |
|---|---|
| **A-C5** (safety escalation gated behind an off-by-default analytics toggle) | §1's channel split + §6 ("safety escalation is on by default for managed machines, fail-closed on absence of `AdminContact`, never conditioned on the analytics opt-in") |
| **B-M7** (Notifications configuration profile) | §6's notification-permission fallback — the profile exists precisely so the popover+IT-channel fallback isn't itself gated behind a deniable OS permission |
| **B-H5** (machine_id collision / re-identification; personal-name leak into usage) | §5 (per-user + per-install-random-salt, not org-wide) and §4 (`usage[]` gated on CLI-computed `winning_layer`, never inferred from a name string) |
| **`threat-model.md` §2.5/§3 rank #1 — NEW, `AdminContact` inherited-org-config gap** | §6: this spec requires `AdminContact` be added to the same signed-inherited-org-config-only key list as `UpdateFeedURL`/`FoundationMirror`/`HTTPSProxy`, closing the single highest-ranked open finding in the threat model as a precondition of this channel's design, not an afterthought |
| **A-H10** (notification permission denied ⇒ notify tier dead) | §6's fallback (popover + safety-channel re-route) |
| **A-H13** (time-boxed Bob-actionable items escalating to IT) | §3's `escalation_deadline` field |

---

## 11. Residual / open items

1. **Stalled-onboarding threshold window** is not yet a ratified number (mirrors the open "sync cadence values" item in `SOUL.md` §9's engineering-roadmap TODOs) — needs a concrete value before `stalled-onboarding` can fire deterministically.
2. **`telemetry.endpoint` transport integrity** beyond "HTTPS" is assumed, not independently specified, matching the same open assumption `threat-model.md` §5 item 7 already flags for the general telemetry sink — no evidence of a defect, flagged as an assumption.
3. **Safety-channel retry/backoff parameters** (max queue depth, backoff ceiling on a fully offline machine) are specified here as a guarantee ("durable, at-least-once") but not yet as concrete numbers — needs its own pass alongside the CLI-contract schema work (WS-A), consistent with `threat-model.md` §5 item 5's flag on `--json` payload bounds generally.
