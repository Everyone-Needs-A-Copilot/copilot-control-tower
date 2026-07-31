# ADR-007 — Onboard schema v2.0 breaking bump

Status: Accepted
Date: 2026-07-31
Task: `tc` 208 (documented under `tc` 213, gap G-9)

## Context

The prior `onboard.schema.json` (`schema_version` 1.0) left every `$defs.ecosystemLayer` topology field optional and `layers` unbounded. A raw four-field `{id,product,role,rank}` row therefore validated identically to a fully-computed topology row, and an exit that returned before topology was ever computed could emit `layers: []` indistinguishably from a `reported` empty array. Both ambiguities let the 0.2.4 live-setup blocker (`phases/phase-6-v0.2.4-live-setup-blocker-handoff.md`) reach a live apply without a release gate catching that the packaged helper's `layers` array had gone silently empty. Task 208 (commit `8aaa424` on `claude-copilot`) closes both, matched here by the schema and `cli-contract.md` edits in commit `5e9847e`.

## Decision

1. `$defs.ecosystemLayer.required` now also includes `action`, `local_state`, `sync_state`, `remote_state`, `repository_name`, and `local_path`, on top of the prior `id`/`product`/`role`/`rank` — the skeletal look-alike row no longer validates.
2. A new required `layers_state` enum (`reported` | `not-computed`) discriminates the two legal `layers` shapes via `allOf`/`if`/`then` conditionals: `reported` requires `layers` to carry at least one fully-required row (`minItems: 1`); `not-computed` requires `layers` to be exactly `[]`. An empty array is never valid on its own — it must be paired with the explicit `not-computed` state.
3. Only the one exit path that returns before the layer manifest itself is built (the personal-packages gate) may emit `not-computed`. Every other exit — including every blocked exit — threads the already-computed `topology_layers` through `_ecosystem_result`, so `layers` is always either a fully-populated topology row per layer or an explicit typed absence, never a bare `[]` of unstated meaning.
4. `completed_actions` (the task 207/G-4 mutation ledger — see [ADR-006](ADR-006-ecosystem-setup-preflighted-saga.md)) and `resume` (required whenever `result` is `blocked`) are formalized as part of the canonical schema rather than carried only in the CLI's own test fixture.
5. `schema_version` bumps 1.0 → 2.0. This is a breaking change for any consumer that read `layers` optimistically — treating a present-but-empty array, or a bare `id`/`product`/`role`/`rank` row, as meaningful topology evidence.

## Consequences

- Every app-side consumer must gate on the `min_schema`/`max_schema` range per the contract's global versioning rule (`cli-contract.md`) and treat a pre-2.0 CLI as incompatible for onboard rendering, not silently degrade.
- The vendored fixture in `claude-copilot` (`tools/cc/tests/fixtures/schemas/onboard.schema.json`) must stay byte-identical to this repo's schema; the CI contract test asserts every `--json` onboard response against it.
- A consumer can no longer treat a present-but-empty `layers` array as meaningful topology evidence, nor a bare `id`/`product`/`role`/`rank` row as a computed result — both were the exact ambiguities the 0.2.4 release gates missed.
- This is a versioning precedent: any future required-field tightening to a discriminated-union shape in this contract should follow the same `layers_state`-style typed-absence pattern rather than an ambiguous optional/empty convention.

## Rejected alternatives

- **Leaving `layers` optional/unbounded and relying on CLI discipline alone to never emit a skeleton row.** Rejected: this is the exact gap that shipped in 0.2.4 and reached a live apply.
- **Representing "not yet computed" as `null` instead of a discriminated `layers_state`.** Rejected: `null` on a required array field conflicts with this contract's global fail-closed rule that a missing or null security- or state-relevant field must never be treated as safe by default, and a named discriminator is self-documenting where `null` is not.
- **Treating this as a minor, non-breaking schema addition.** Rejected: any consumer that previously read empty-or-skeletal `layers` optimistically would silently continue misbehaving; a breaking bump forces every consumer to update deliberately.
