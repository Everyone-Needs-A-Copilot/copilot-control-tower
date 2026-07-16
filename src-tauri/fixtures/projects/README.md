# projects fixture corpus (WS-A Stream-Z, Component Sync)

Drives Control Tower through the Component Sync machine-wide surfaces —
`cc freshness --all-projects --json` (the read-only per-project sweep) and
`cc update --fanout --json` (the write-side fan-out roll-up) — without a real
fleet of embedding projects. See
[`../../../docs/80-initiatives/02-component-sync/README.md`](../../../docs/80-initiatives/02-component-sync/README.md).

Conforms to
[`docs/01-architecture/schemas/projects.schema.json`](../../../docs/01-architecture/schemas/projects.schema.json)
(which `$ref`s `update.schema.json` for a per-project materialize `report`) and
[`_envelope.schema.json`](../../../docs/01-architecture/schemas/_envelope.schema.json) —
validated by [`../validate.sh`](../validate.sh) (top-level, alongside the doctor corpus).

## Layout

```
src-tauri/fixtures/projects/
  README.md   this file
  corpus/     *.json — ONE directory, TWO shapes (projects.schema.json's `oneOf`),
              distinguished structurally exactly like the real schema: an
              `all_projects_freshness` body (`projects`+`global` keys) or a
              `fanout_report` body (`summary`+`results` keys) — never both.
```

## Corpus map (`corpus/`)

| File | Shape | What it exercises |
|---|---|---|
| `mixed-fresh-and-stale.json` | `all_projects_freshness` | Three projects: one stale (`claude` 5.8.1→5.9.0), one fully current, one with an unknown-latest component (`stale:null`, never coerced) — plus one deduped `global` (`knowledge`) entry. Backs `mock-cc freshness --all-projects --json`'s default. |
| `12-of-14-updated.json` | `fanout_report` | The "across 12 of your projects" roll-up line: `summary:{updated:12, held:1, up_to_date:1, failed:0, total:14}` — 12 `applied` per-project `report`s, 1 `held` (dirty WIP), 1 honest `up-to-date` skip (no full `report`, per the schema's own `results[].result` carve-out). Backs `mock-cc update --fanout --json`'s default. |
| `all-held-dirty.json` | `fanout_report` | The "waiting on your unsaved changes" worst case: every one of 5 discovered projects is `held` (`summary:{updated:0, held:5, ...}`), each `report.held_for_approval[].reason:"dirty-working-tree"` — zero files touched anywhere. |

## Running against the mock `cc`

```bash
# per-project freshness sweep (read-only)
CT_FIXTURE=mixed-fresh-and-stale src-tauri/fixtures/mock-cc freshness --all-projects --json

# fan-out roll-up, happy-ish path
CT_FIXTURE=12-of-14-updated src-tauri/fixtures/mock-cc update --fanout --json

# fan-out roll-up, everything held on dirty WIP
CT_FIXTURE=all-held-dirty src-tauri/fixtures/mock-cc update --fanout --json

# a single project's own materialize result (reuses ../update/corpus/, stamped
# with the given --project path — an additive update.schema.json `path` field,
# NOT this directory)
src-tauri/fixtures/mock-cc update --project /path/to/some-project --json
```

Same `$CT_FIXTURE`/`$CC_FIXTURE`/`--fixture` selection convention as `doctor`; defaults
to `mixed-fresh-and-stale` for `freshness --all-projects` and `12-of-14-updated` for
`update --fanout`. Both verbs exit `0` once a fixture body is found (same simpler,
no-per-body-severity convention as `deprovision`/`update`); `exit-2`/an unknown fixture
name exit `2`.
