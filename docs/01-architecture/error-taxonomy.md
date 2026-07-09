# Error & Exit-Code Taxonomy

| | |
|---|---|
| **STATUS** | **Canonical.** This is the single source of truth for CLI exit codes, error categories, and their app-side rendering. `cli-contract.md`, `design-integration.md`, and `architecture.md` §6 each restated a version of this table — they now **reference this doc** instead of repeating it. If you find a fourth copy, delete it and link here. |
| **Schema authority** | [`cli-contract.md`](cli-contract.md) remains the authority for the **`--json` payload shapes** (field names, types, `schema_version`). This doc is the authority for **what exit codes and error categories mean and how the app must render/degrade for each** — a distinct, narrower concern. |
| **Governed by** | Invariant #1 (`CLAUDE.md`) — Control Tower **parses, never computes**. Every row below is a rendering/degrade rule for a verdict the CLI already reached; none of it is app-side judgment. |

---

## 1. Canonical exit-code table

Every `copilot`/`cc` verb Control Tower invokes returns one of these three exit codes. The **verdict
itself is always computed CLI-side** (`status`, `result`, `conflict.state`, etc., inside the `--json`
payload) — the exit code is a coarse, scriptable signal; the JSON body is what the app actually
renders. An exit code and its JSON body disagreeing (e.g. exit `0` with a `fail`-severity checker) is
schema drift and must be treated as an environment error (§2), never resolved by trusting one over
the other.

| Exit code | Meaning | App rendering / behavior | Degrade path |
|---|---|---|---|
| **`0`** | Clean success. For `doctor`: 0 fail-severity findings. For `update`/`publish`: the operation completed, **including** a cleanly-reported conflict or held-approval — those are normal outcomes, not errors. | Render the JSON body's own status/result verbatim (Healthy, Syncing→Healthy, `auto-merged`, `needs-choice`, `parked-escalated`, `held_for_approval`). No app-side reinterpretation. | None needed — this is the success path. If `held_for_approval`/`blocked` is non-empty despite exit `0`, render the specific state (§3), not a blanket "Healthy." |
| **`1`** | An operational fail condition the CLI ran to completion and reported. For `doctor`: at least one `fail`-severity checker. For `update`: refused/blocked (capability-policy denial, signature failure, unresolved non-fast-forward). For `publish`: refused (leak-scan tripped, unresolvable non-fast-forward, a stale `--resolve`). | Render the **specific** failing finding/reason from the JSON body — never a generic "something went wrong." Route through the escalation ladder (§3) by category: auto-heal, notify, or escalate to IT, per the actor-competence model (`architecture.md` §9). Never retried by the app as if it were exit `2`. | The CLI already completed its pipeline; there is no CLI-side retry to offer. The app's only job is correct routing + a plain-language message, never a fix attempt of its own. |
| **`2`** | Environment/credential error — the CLI **could not run its pipeline at all** (missing binary, unreadable config, expired/absent credential the CLI needs just to start, schema the app can't parse). This is categorically different from `1`: the CLI never reached a verdict. | Render an **honest holding state**, never a guessed verdict of any kind — the app has nothing to parse. Typical renders: `Signed-out` (credential-shaped), `IT-config-incomplete` (signed inherited org config malformed/missing), or a generic "can't verify — run `copilot doctor` in a terminal" **only** as the last-resort schema-mismatch degrade (§8's contract-drift case). | No auto-repair is ever attempted against exit `2` — there is no CLI verdict to act on. The app polls again next cadence tick; it never fabricates Healthy in the interim. |

**Fail-closed rule that applies across all three codes:** a `--json` payload missing a
security-relevant field (`destructive`, `signed`, `severity`, `leak_scan`, `tier`) is treated as
**destructive/unsigned/fail/refuse**, regardless of the exit code that carried it. A missing field
is never read as safe. Ref: `cli-contract.md` Requirements; `SOUL.md` §6.

---

## 2. Error categories a parsing app must handle

These are the **shapes of failure** Control Tower's state machine must classify — a superset that
spans multiple verbs and exit codes. Each category maps to exactly one rendered status state (§3);
never to app-computed severity.

| Category | What it looks like | Typical exit code | Rendered status |
|---|---|---|---|
| **CLI-unreadable** | `copilot`/`cc` binary missing, unspawnable (Gatekeeper quarantine, translocation path broken), or produced output that doesn't parse as JSON at all. | `2` (or spawn failure before any exit code) | `IT-config-incomplete` (if a managed install is expected) or a "can't verify" schema-mismatch degrade — never a guessed Healthy. |
| **Version-mismatch** | `schema_version` in the JSON body is outside the app's declared `min_schema`/`max_schema` range — gated **bidirectionally**: a CLI schema older than the floor is as fatal as one newer. | `0` or `2` (schema check happens before trusting the body) | The app hard-refuses to parse and shows "versions don't match — click to update," driving a paired CLI/app update. Never rendered as any health state. |
| **Auth-needed** | `auth[].state == "expired"` (transient) for a required layer. | `1` (doctor) | `Signed-out` — one-click re-auth offered; partner keeps working on cached content until resolved. |
| **Blocked** | `update`/`publish` refused an item: capability-policy denial, signature-verify failure, or an unresolvable non-fast-forward. | `1` | `Needs-attention` (policy denials render as IT-log-only, never a Bob notification) or an un-dismissable security banner if `severity_trailer` is present. |
| **Holding** | A legitimate, non-error pause: `held_for_approval` (major version awaiting IT sign-off) or `publish` returning `needs-choice`/`parked-escalated`. | `0` | `Update-available` (held-major) or the plain-language publish chooser / "parked and escalated" message — rendered as a normal state, not a failure banner. |
| **Offline** | `doctor.offline == true` or `update.result == "offline"` — network unreachable, CLI is operating on cached SHAs. | `0` (offline is an honest completed state, not a CLI failure) | `Offline` — dimmed icon, "using cached content," never `Needs-attention`. Unreachable ≠ drift. |
| **Config-incomplete** | A signed inherited org config is present but fails schema validation, or a required key is absent past the settling window. | `2` | `IT-config-incomplete` — fails closed, distinct from *absent* (retry over a settling window) vs. *present-but-invalid* (immediate named-key error) vs. *valid*. Never rendered as Healthy or Setup-needed. |

**Auth-revoked** (permanent, distinct from Auth-needed/expired) is its own terminal category: the
CLI fails closed and offers the `deprovision` wipe rather than continuing to serve now-unsanctioned
content. Rendered as `Signed-out` transitioning to a fail-closed "access removed" message, then the
org's materialized content is cleared. Ref: `architecture.md` §8.3; `design-integration.md` §4.

---

## 3. Mapping to `copilot publish` conflict states

`publish` is the one verb whose **exit `0`** carries three materially different outcomes the app must
distinguish and render distinctly — none of them is an error, and none of them is computed by the
app:

| `result` / `conflict.state` | Exit code | Meaning | App rendering |
|---|---|---|---|
| **`auto-merged`** | `0` | Rebased + non-overlapping hunks merged silently; push completed. | "Published to `<tier>`" — no chooser, no interruption. |
| **`needs-choice`** | `0` | A true overlap on the same lines. CLI emits **rendered content versions** (never Git markers) plus the resolution options. | The app renders the plain-language chooser (`keep-yours` / `keep-theirs` / `keep-both` / `escalate`) and passes the pick back via `--resolve <choice>`. **`keep-both` is always offered as the lossless floor; `escalate` is always offered as the never-cornered exit.** Raw Git output is never shown. |
| **`parked-escalated`** | `0` | Sensitive path/class, or the author declined to choose. Change is parked on a durable held ref (never lost) and routed to a competent author via the actor-competence model. | Plain-language "your version is saved; `<competent author>` will reconcile" — never a Bob-facing decision prompt. |

`publish` exit `1` (leak-scan tripped, unresolvable non-fast-forward, stale `--resolve`) and exit `2`
(credential absent) follow the general table in §§1–2 — a refusal or an environment error, never one
of the three conflict states above.

Ref: [`cli-contract.md`](cli-contract.md) `copilot publish --json`; [`inheritance-and-publish.md`](inheritance-and-publish.md) §3.

---

## 4. What this doc does not do

Per invariant #1, nothing here authorizes the app to **compute** a verdict this doc doesn't already
attribute to a parsed CLI field. This is a rendering/routing reference, not a resolution engine:

- The app never decides *whether* something is `pass`/`warn`/`fail`, `auto-merged`/`needs-choice`, or
  destructive/safe — it renders the field the CLI already set.
- A missing or malformed security-relevant field is always the fail-closed reading (§1), never
  inferred as safe by the app filling a gap.
- If a future verb or field isn't in this table, treat it as **exit `2`-shaped** (an honest "can't
  verify" state) until this doc is updated — never guess a rendering for an unlisted case.

---

## Superseded restatements

The following docs previously restated this table and should now **link here** instead of repeating
it:

- [`cli-contract.md`](cli-contract.md) — keep its per-verb schema tables (field shapes); exit-code
  semantics point to this doc.
- [`../03-design/design-integration.md`](../03-design/design-integration.md) §1.1, §2 — keep its
  state-machine entry conditions; exit-code meaning points to this doc.
- [`architecture.md`](architecture.md) §6 — keep its contract-requirements narrative; exit-code table
  points to this doc.
