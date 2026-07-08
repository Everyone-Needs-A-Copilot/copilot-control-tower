# update fixture corpus (M6/S1)

Drives `model::update::parse_update_body` through every `copilot update --json` outcome
without ever running the real (mutating) `copilot update` verb. Referenced by
`.copilot/wp/37.md` and task 52, consumed by `model::update`'s own tests and, downstream,
the M6/S2 router.

Conforms to
[`docs/01-architecture/schemas/update.schema.json`](../../../docs/01-architecture/schemas/update.schema.json)
and [`_envelope.schema.json`](../../../docs/01-architecture/schemas/_envelope.schema.json)
— except where noted below, which is deliberate.

## Layout

```
src-tauri/fixtures/update/
  README.md   this file
  corpus/     *.json — fixtures the app PARSES AS TRUSTED (see the note on
              missing-signed.json below — "trusted" is not the same as "every
              field present")
  invalid/    *.json — fixtures the app must fail closed on (Unreadable, never
              a fabricated "applied")
```

## Corpus map (`corpus/`)

| File | `result` | What it exercises |
|---|---|---|
| `applied-clean.json` | `applied` | The clean-success path: an `updated` CLI-binary change and an `added` knowledge-doc change, both `signed:true`. |
| `up-to-date.json` | `up-to-date` | Nothing changed — `changed:[]`, `lock_before == lock_after`. |
| `held.json` | `held` | `held_for_approval` populated with one held-major (`reason: "major; ecosystem.yml policy=hold-majors"`) — the IT-routed lane. |
| `blocked.json` | `blocked` | `blocked` populated with one capability-policy-denial-shaped entry (see the "`blocked[]` is open" note below — this shape is illustrative, not frozen). |
| `offline.json` | `offline` | No connectivity to reconcile against. |
| `pruned-change.json` | `applied` | A `changed[]` entry with `op:"pruned"` — the reconciling-sync deletion `cli-contract.md` calls out explicitly. |
| `security-shadow.json` | `applied` | A `changed[]` entry with `signed:false`, a non-null `severity_trailer`, and a non-null `shadowed_by` — the un-dismissable security-banner input (unsigned content shadowing a signed org-tier file). |
| `missing-signed.json` | `applied` | **Adversarial, deliberately in `corpus/` not `invalid/`.** One `changed[]` entry omits `signed` entirely — violates the schema's `required` list, but `model::update::parse_update_body` does NOT reject the whole body: the missing field is defaulted to `false` (unsigned) on that one entry, per the schema's own security note ("a missing value is treated as unsigned"). Rejecting this to `Unreadable` would DELETE the very fact ("this content is unsigned") the fail-closed rule exists to surface — same reasoning as `fixtures/deprovision/corpus/secrets-touched-alarm.json`. |

## Adversarial corpus (`invalid/`) — the Unreadable / fail-closed cases

These must **never** render as `applied` (or any other trusted result) — they prove
`UpdateParseOutcome::Unreadable` is reachable and that the resulting `UpdateVerdict`
never fabricates a clean success.

| File | What's wrong | Maps to |
|---|---|---|
| `missing-op.json` | A `changed[]` entry omits `op` entirely | `UpdateUnreadableReason::MissingSecurityField` — `op`'s structural absence is NEVER defaulted to the benign `unchanged`; the whole body fails closed instead. |
| `unknown-extra-field.json` | An unrecognized top-level key | `UpdateUnreadableReason::ParseError` — mirrors the schema's top-level `"additionalProperties": false`. |
| `malformed.json` | Truncated/non-JSON body | `UpdateUnreadableReason::ParseError`. |
| `schema-version-above-max.json` | `schema_version: "2.0"` | `UpdateUnreadableReason::SchemaOutOfRange` — reuses `model::envelope`'s bidirectional range gate, same as `doctor`/`deprovision`. |
| `schema-version-below-min.json` | `schema_version: "0.9"` | `UpdateUnreadableReason::SchemaOutOfRange` — the other direction; "older is as fatal as newer". |
| `unknown-result.json` | `result: "obliterated"` — not one of `applied`/`up-to-date`/`held`/`blocked`/`offline` | `UpdateUnreadableReason::InvalidContent` — the concrete mechanism behind "unknown result => never a fabricated 'applied cleanly'". |

## `blocked[]` is an OPEN shape (G-M6-4 — flagged for CLI freeze)

`update.schema.json`'s own `$comment` on `blocked` notes the upstream design shows no
concrete example item shape (only an empty `blocked: []`). `blocked.json` above uses an
illustrative `{dimension, layer, item, reason}` shape, but `model::update::BlockedEntry`
does **not** assume this shape — every element is retained verbatim as opaque JSON, so a
divergent real shape from the CLI is never silently dropped. See `model::update`'s own
module doc for the full reasoning, and `cli-contract.md`'s open-gaps list for G-M6-4
itself.

## Running against the mock `cc`

```bash
CT_CLI_PATH=/absolute/path/to/src-tauri/fixtures/mock-cc \
CT_FIXTURE=applied-clean \
  src-tauri/fixtures/mock-cc update --json

# adversarial: the honest unsigned default
CT_FIXTURE=missing-signed src-tauri/fixtures/mock-cc update --json

# fail-closed
CT_FIXTURE=missing-op src-tauri/fixtures/mock-cc update --json

# env error / flock-held path
CT_FIXTURE=exit-2 src-tauri/fixtures/mock-cc update --json
```

Same `$CT_FIXTURE`/`$CC_FIXTURE`/`--fixture` selection convention as `doctor`/
`deprovision` (`mock-cc`'s own header comment documents the shared precedence order);
defaults to `applied-clean` when unset. Like `deprovision`, this verb's exit code has no
documented per-body contract, so `mock-cc` always exits `0` once a fixture body is
found — including every `invalid/` fixture, by design: the app's OWN fail-closed parsing
is what's under test, never the exit code.

## NEVER run the real CLI

`copilot update` mutates the local ecosystem state (applies a reconciling sync). Every
test in `model::update` reads a fixture file directly (`std::fs::read`); none of them, and
none of a future spawn-boundary's tests, should ever point at the real, vendored `cc` —
only `mock-cc`, which is pure text-in/text-out and never touches the filesystem beyond
reading its own fixture file.
