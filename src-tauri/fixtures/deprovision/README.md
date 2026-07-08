# deprovision fixture corpus (M5/S2)

Drives Control Tower's `deprovision::run_deprovision` through every `cc deprovision
<org> --json` outcome without ever running the real, MUTATING CLI verb (it would
actually wipe `~/.claude`). Referenced by `.copilot/wp/30.md` and consumed by
`model::deprovision`, `deprovision::render`, and `deprovision::run_deprovision`'s own
tests.

Conforms to
[`docs/01-architecture/schemas/deprovision.schema.json`](../../../docs/01-architecture/schemas/deprovision.schema.json)
and [`_envelope.schema.json`](../../../docs/01-architecture/schemas/_envelope.schema.json).

## Layout

```
src-tauri/fixtures/deprovision/
  README.md   this file
  corpus/     *.json — fixtures the app PARSES AS TRUSTED (see the note on
              secrets-touched-alarm.json below — "trusted" is not the same as
              "clean")
  invalid/    *.json — fixtures the app must fail closed on (Unreadable, never a
              fabricated wiped/partial/noop)
```

## Corpus map (`corpus/`)

| File | `result` | What it exercises |
|---|---|---|
| `wiped-clean.json` | `wiped` | The clean-success path: 3 materialized items + 2 clones removed, `secrets_touched:0`, AND one `retained_dirty` entry — proves a `wiped` org-level result still honestly reports a personal dirty tree that was kept (never-destroy, invariant #3, holds even on the "everything's gone" outcome). |
| `partial.json` | `partial` | Some, not all, of the org's materialized data removed. |
| `noop.json` | `noop` | Nothing to remove — `removed.materialized:0`, empty `clones`, empty `retained_dirty`. |
| `secrets-touched-alarm.json` | `wiped` | **Adversarial, deliberately in `corpus/` not `invalid/`.** `secrets_touched:1` — violates the JSON Schema's `const:0`, but `model::deprovision::parse_deprovision_body` does NOT reject it: a present-but-nonzero `secrets_touched` is real, trusted content the render layer must surface as a loud alarm (invariant #6), not swallow into a parse failure. Rejecting it here would DELETE the very fact ("a secret was touched") the alarm exists to report. See `model::deprovision`'s own module doc, "fail-closed philosophy" section, for the full reasoning. |

## Adversarial corpus (`invalid/`) — the Unreadable / fail-closed cases

These must **never** render as `wiped`/`partial`/`noop` — they prove
`DeprovisionParseOutcome::Unreadable` is reachable and that the resulting
`DeprovisionView` never fabricates a clean success.

| File | What's wrong | Maps to |
|---|---|---|
| `malformed.json` | Not JSON at all | `DeprovisionUnreadableReason::ParseError` |
| `missing-secrets-touched.json` | The one field the schema says MUST be present (and MUST be `0`) is structurally absent | `DeprovisionUnreadableReason::MissingSecurityField` — this is a STRICTER failure than an ordinary missing field; see the module doc for why absence and "present-but-nonzero" get different treatment |
| `unknown-result.json` | `result: "obliterated"` — not one of `wiped`/`partial`/`noop` | `DeprovisionUnreadableReason::InvalidContent` — the concrete mechanism behind "unknown result => not a clean success, never a fabricated wiped cleanly" |
| `schema-version-above-max.json` | `schema_version: "2.0"` | `DeprovisionUnreadableReason::SchemaOutOfRange` — reuses `model::envelope`'s bidirectional range gate, same as `doctor` |

## Running against the mock `cc`

```bash
CT_CLI_PATH=/absolute/path/to/src-tauri/fixtures/mock-cc \
CT_FIXTURE=wiped-clean \
  src-tauri/fixtures/mock-cc deprovision acme-corp --json

# adversarial: the honest alarm
CT_FIXTURE=secrets-touched-alarm src-tauri/fixtures/mock-cc deprovision acme-corp --json

# fail-closed
CT_FIXTURE=malformed src-tauri/fixtures/mock-cc deprovision acme-corp --json

# env error / flock-held path
CT_FIXTURE=exit-2 src-tauri/fixtures/mock-cc deprovision acme-corp --json
```

Same `$CT_FIXTURE`/`$CC_FIXTURE`/`--fixture` selection convention as `doctor`
(`mock-cc`'s own header comment documents the shared precedence order); defaults to
`wiped-clean` when unset. Unlike `doctor`, this verb's exit code has no documented
per-body contract (`cli-contract.md`'s `deprovision` row names none), so `mock-cc`
always exits `0` once a fixture body is found — including every `invalid/` fixture,
by design: the app's OWN fail-closed parsing is what's under test, never the exit code.

## NEVER run the real CLI

`cc deprovision` is destructive. Every test that exercises `deprovision::
run_deprovision` end-to-end points `CT_CLI_PATH` at `mock-cc` (never the real,
vendored `cc`) — the mock is pure text-in/text-out and never touches the filesystem
beyond reading its own fixture file, matching the invariant `tests/
fitness_m5_no_wipe_logic.rs` (FF-M5-2) proves at the source level for the Rust module
itself.
