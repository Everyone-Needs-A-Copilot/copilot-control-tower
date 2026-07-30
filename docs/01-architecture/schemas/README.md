# CLI `--json` contract schemas (WS-A)

These JSON Schema (Draft 2020-12) files are the **machine-readable source of truth** for the
`copilot`/`cc` `--json` contract that Control Tower consumes. They exist to power the
**CI contract test** (in the `copilot` repo) that asserts every `--json` verb matches its
published schema on every release — the safety boundary where *schema drift = silent security
bypass* (a misread `fail`→`pass` shows green over a red pipeline).

Invariant #1 — **parse, never compute**: Control Tower renders whatever these schemas describe;
it implements no resolution/merge/sign/wipe logic of its own.

## Files

| Schema | Verb | Notes |
|---|---|---|
| `_envelope.schema.json` | — | Shared `$defs` (`schema_version`, `git_sha`, `timestamp`, `severity`) `$ref`'d by every verb. There is **no** uniform status/error wrapper in the contract; the only universal field is `schema_version`. |
| `auth.schema.json` | `copilot auth [login\|grant\|status] --json` | GitHub device-flow sign-in plus the identity-bound, least-privilege `write:public_key` upgrade. Five `kind`-discriminated payloads (`device-code`/`poll`/`grant-device-code`/`grant-poll`/`status`) plus the shared error envelope; NO-SECRET fitness recursively forbids credential-shaped keys at every depth. |
| `doctor.schema.json` | `copilot doctor --json` | Health verdict. Encodes the "a false Healthy is impossible" invariant (healthy ⇒ not offline, no `fail` checker). |
| `update.schema.json` | `copilot update --json` | Reconciling sync; `pruned` op + `severity_trailer`/`shadowed_by` banner drivers. Additive `path` property (Component Sync Stream-E) carries this same shape for a single project's `copilot materialize --project <path> --json` result. |
| `resolve.schema.json` | `copilot resolve --explain --json` | Per-item layered resolution; `live_hash_matches:false` ⇒ MODIFIED. |
| `deprovision.schema.json` | `copilot deprovision <org> --json` | `secrets_touched` pinned to `const: 0`; dirty trees retained. |
| `freshness.schema.json` | `copilot freshness --json` | Cheap single-SHA poll target; optional additive `layers[]` breakdown (opt-in `--per-layer`). |
| `publish.schema.json` | `copilot publish --json` | Author-side push; `auto-merged` / `needs-choice` / `parked-escalated` conflict states; fail-closed `tier` + `leak_scan`. |
| `layers.schema.json` | `copilot layers [join] --json` **(proposed, D7.1)** | Entitlement discovery (`list_report`) + join action (`join_result`), discriminated structurally (`layers[]` vs. `result`). `entitled: null` fails closed (never treated as `true`). |
| `projects.schema.json` | `copilot projects freshness --all --json` / `copilot materialize --fanout --json` | Component Sync (`docs/80-initiatives/02-component-sync/`) machine-wide fan-out: all-projects freshness sweep + fan-out roll-up. A single project's own `copilot materialize --project <path> --json` result reuses `update.schema.json`'s shape (see its additive `path` property) rather than a third shape. |
| `workspaces.schema.json` | `cc workspace --all\|--project --json` / `cc workspace finish\|verify\|plan\|hold ... --json` | Authoritative schema 1.1 project-integration inspection. Carries closed per-component classification, exact safe actions, generated guided prompts and owner handoffs, preservation rules, and independent verification. Control Tower renders these facts and round-trips opaque IDs; it does not inspect or classify project contents. |
| `workspace-root.schema.json` | `cc workspace approve-root\|forget-root --path <folder> [--apply] --json` / `cc workspace roots --json` / `cc workspace decline [--apply] --json` | Explicit, non-symlinked folder grant/revocation, the read-only listing of approved folders plus detected one-click candidates (conventional folders under the home directory that already contain a project), and the machine-wide opt-out. Folder identity round-trips via `path`; only `name`/`label` are ever rendered. |

## Versioning

The contract is **versioned**. Every schema requires a top-level `schema_version`
(`_envelope.schema.json#/$defs/schema_version`). Control Tower declares a `min_schema`/`max_schema`
range and **gates both directions** — a CLI schema older than its floor is as fatal as one newer.
**Missing security-relevant fields fail closed** (absent `destructive`/`signed`/`severity`/`tier`/`leak_scan`
⇒ treated as destructive/unsigned/fail/refuse, never safe), so the CLI must always emit them and the
schemas mark them `required`.

## Sync rule

`cli-contract.md` (prose) and these schemas describe the same contract. When they disagree,
**the schemas win for machines** — they are what the CI contract test enforces. Any change to one
must update the other in the same change. Where the prose is ambiguous, the schema encodes the most
defensible interpretation and carries a `"$comment"` flagging the assumption for the owner to tighten.

**Freeze status (2026-07-07 reconciliation).** These schemas encode the *design*, not an implemented
CLI — WS-A is unstarted (see `cli-contract.md` "Freeze status & source of truth"). The authoritative
source is the upstream `claude-copilot` design docs (05-control-tower.md, 06-control-tower-prd.md,
research/design-control-tower-integration.md). Previously-open ambiguities now resolved against that
source:
- `doctor.status` — corrected from a draft `healthy|degraded|failed` (which wrongly conflated it with
  per-checker `severity`) to the authoritative ~10-state machine: `setup-needed`, `it-config-incomplete`,
  `healthy`, `syncing`, `update-available`, `needs-attention`, `signed-out`, `offline`,
  `waiting-for-network`, `updating-app`.
- `checker.repair` — confirmed nullable repair-token string (not a boolean).
- `doctor.auth[]` element — tightened to `{identity, scope, state: expired|revoked, expires_at}` per
  the upstream `doctor --json` example. (A `{layer, state, days_to_expiry}` shape exists upstream too,
  but belongs to the *telemetry* payload, §6.2 of the integration design — a different verb/schema, not
  `doctor`.)
- `update.result` — enumerated `applied|up-to-date|held|blocked|offline` per the upstream example.
- `update.held_for_approval[]` — tightened to `{dimension, from, to, reason}`.
- `deprovision.result` — enumerated `wiped|partial|noop` per the upstream example.
- `deprovision.removed.materialized` — corrected from boolean to a non-negative integer count (`N` in
  the upstream example); its exact semantics remain genuinely unspecified even upstream — open field,
  to be defined at freeze.
- `repair.schema.json` — NOT an upstream WS-A verb task (06-control-tower-prd.md §3 has no `repair`
  task); marked SPECULATIVE / control-tower's assumed shape pending upstream definition. `repair` is
  invoked, but driven by the `repair` token on each `doctor` checker, not a standalone frozen schema.
- `publish.schema.json` — NOT in upstream WS-A scope at all; marked as a control-tower-originated
  proposed addition (from this repo's ratified writable-inheritance & publish-path design) that must
  still be added upstream at freeze.
- `resolve.schema.json` — confirmed already aligned with the upstream per-item shape; no changes
  needed beyond a confirmation note.
- `freshness.schema.json` — **CORRECTED 2026-07-07 (WS-A slice 3, cc owner)**: `current_lock_sha` /
  `latest_lock_sha` / `stale` widened from non-nullable to nullable, and a required `offline` boolean
  added (mirroring `doctor.schema.json`'s existing `offline` field). The original shape had no way to
  represent "could not check" (offline, or no local lock yet) other than fabricating a SHA or a `stale`
  verdict — a false-Healthy-shaped bug the honesty rule forbids. `stale: null` is now the honest third
  state; a consumer must treat it as unknown, never as `false`/"up to date". See
  `tools/cc/src/cc/commands/freshness.py`'s module docstring in `claude-copilot` for the full rationale.
