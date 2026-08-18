# connections fixture corpus (task 221 bridge stage C)

Drives Control Tower through every `cc connections --json` outcome (the organization's declared connections roster + shared-store reachability) without a real fleet, a real `ecosystem.yml`, or a real Infisical store. See [`../../../docs/01-architecture/schemas/connections.schema.json`](../../../docs/01-architecture/schemas/connections.schema.json) and [`../../../docs/01-architecture/cli-contract.md`](../../../docs/01-architecture/cli-contract.md).

Conforms to [`docs/01-architecture/schemas/connections.schema.json`](../../../docs/01-architecture/schemas/connections.schema.json) and [`_envelope.schema.json`](../../../docs/01-architecture/schemas/_envelope.schema.json) — validated by [`../validate.sh`](../validate.sh) (top-level, alongside the doctor/layers/projects corpora).

## Layout

```
scripts/tests/fixtures/connections/
  README.md   this file
  corpus/     *.json — one connections.schema.json report per representative outcome
```

## Corpus map (`corpus/`)

| File | `result` | `store.reachable` | What it exercises |
|---|---|---|---|
| `ready-and-needs-connect.json` | `ok` | `true` | The common case: some rows `ready` (no required secret, or a `keychain`-hinted one), some `needs-connect` (a `store`/`any`-hinted name absent from a reachable store). Mirrors the real org's live `git`/`discord`/`infisical`/`uspto` shape (task 221's WP-388 trace). |
| `store-unreachable.json` | `ok` | `false` | The shared store itself could not be reached this run (transient/offline) — `git` (no required secret) still reads `ready`; `coolify`/`brevo` (store/any-hinted) read `no-store`, grouped under `store.detail`'s honest explanation. |
| `org-config-unavailable.json` | `org-config-unavailable` | `false` | No `ecosystem.yml` materialized on this Mac at all — `connections` is STILL the full roster (per the schema's own note), every store/any-hinted row forced to `no-store`; `detail` carries the top-level reason. |
| `copilot-unavailable.json` | `copilot-unavailable` | `false` | The `copilot` binary itself could not be resolved/run — `connections` is empty (the ONE case the schema allows this), `detail` is the only thing to render. |

## `mock-cc connections --json`

Same `$CT_FIXTURE`/`$CC_FIXTURE`/`--fixture` selection convention as every other verb (`mock-cc`'s own header comment documents the shared precedence order); defaults to `ready-and-needs-connect` when unset.

```bash
CT_FIXTURE=store-unreachable scripts/tests/fixtures/mock-cc connections --json
CT_FIXTURE=list              scripts/tests/fixtures/mock-cc doctor --json   # enumerates this corpus too

# simulate the env-error / exit-2 path (no trustworthy body at all)
CT_FIXTURE=exit-2 scripts/tests/fixtures/mock-cc connections --json

# simulate an installed `cc` build that PREDATES this verb entirely — exit 2,
# empty stdout, a Click-style usage error on stderr. Verified live against
# the bundled 0.3.2 app's real `cc 2.1.2` helper (task 221 stage C).
CT_FIXTURE=verb-unavailable scripts/tests/fixtures/mock-cc connections --json
```

**Exit codes:** `0` once any fixture body is found (same simpler convention as `layers`/`deprovision`/`update` — `result` inside the body itself carries any degradation, never the exit code); `2` for `exit-2`, `verb-unavailable`, or an unknown fixture name.

`native/render-state.swift`'s `CliError.looksLikeMissingConnectionsVerb` is the app-side classifier that turns `verb-unavailable`'s exact shape (exit 2, no readable `{schema_version, error}` envelope) into the quiet "update to see your organization's connections" line — structurally, never by matching this fixture's stderr text.
