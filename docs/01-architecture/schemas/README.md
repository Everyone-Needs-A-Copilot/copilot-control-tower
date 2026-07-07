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
| `doctor.schema.json` | `copilot doctor --json` | Health verdict. Encodes the "a false Healthy is impossible" invariant (healthy ⇒ not offline, no `fail` checker). |
| `update.schema.json` | `copilot update --json` | Reconciling sync; `pruned` op + `severity_trailer`/`shadowed_by` banner drivers. |
| `resolve.schema.json` | `copilot resolve --explain --json` | Per-item layered resolution; `live_hash_matches:false` ⇒ MODIFIED. |
| `deprovision.schema.json` | `copilot deprovision <org> --json` | `secrets_touched` pinned to `const: 0`; dirty trees retained. |
| `freshness.schema.json` | `copilot freshness --json` | Cheap single-SHA poll target. |
| `publish.schema.json` | `copilot publish --json` | Author-side push; `auto-merged` / `needs-choice` / `parked-escalated` conflict states; fail-closed `tier` + `leak_scan`. |

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
defensible interpretation and carries a `"$comment"` flagging the assumption for the owner to tighten
(notably: `doctor.status` value set, `checker.repair` type, `deprovision.removed.materialized` type,
`publish.conflict.state`, and the entire `repair.schema.json`, whose `--json` shape is *not* specified
in `cli-contract.md` and is reconstructed from `architecture.md` §5.2).
