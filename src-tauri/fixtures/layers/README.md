# layers fixture corpus (WS-A Stream-Z, D7.1)

Drives Control Tower through every `cc layers --json` (entitlement discovery, list) and
`cc layers join <id> --json` (join action) outcome without a real GitHub identity, a
real `ecosystem.yml`, or a real mirror sync. See
[`../../../docs/01-architecture/cli-contract.md`](../../../docs/01-architecture/cli-contract.md)'s
"`copilot layers [join] --json` (proposed contract addition, D7.1)" section.

Conforms to
[`docs/01-architecture/schemas/layers.schema.json`](../../../docs/01-architecture/schemas/layers.schema.json)
and [`_envelope.schema.json`](../../../docs/01-architecture/schemas/_envelope.schema.json) —
validated by [`../validate.sh`](../validate.sh) (top-level, alongside the doctor corpus).

## Layout

```
src-tauri/fixtures/layers/
  README.md   this file
  corpus/     *.json — one `list_report` (layers.schema.json) per entitlement/join state
```

## Corpus map (`corpus/`) — one file per layer-entry state

| File | `entitled` / `joined` | What it exercises |
|---|---|---|
| `available.json` | `true` / `false` | Entitled, not yet joined — the normal "you can join this" row. |
| `joined.json` | `true` / `true` | Already synced onto this machine. |
| `not-entitled.json` | `false` / `false` | No GitHub repo access to this layer's repo — never rendered as joinable. |
| `offline.json` | `null` / `false`, `reason:"offline"` | Entitlement could not be determined (mirror-sync/entitlement-check unreachable) — `null` must be treated as NOT entitled (fail-closed), never as `true`. |

## `mock-cc layers join <id> --json`

There is no separate join-result corpus: `mock-cc layers join <id> --json` reuses the
SAME `$CT_FIXTURE`/`$CC_FIXTURE`/`--fixture` selection as `layers --json` (list) to pick
the join **outcome**, synthesizing a small `join_result` body inline (echoing the
caller's own `<id>` argument) rather than a fourth on-disk fixture per state:

| Fixture name | `join` `result` | Exit code |
|---|---|---|
| `available` | `joined` (with `synced_lock_sha`) | 0 |
| `joined` | `already-joined` | 0 |
| `not-entitled` | `not-entitled` | 0 |
| `offline` | `offline` (with `reason`) | 0 |
| `error` | `error` (unknown layer id) | 1 |
| `exit-2` | — (env/credential error, no body) | 2 |

```bash
CT_FIXTURE=available src-tauri/fixtures/mock-cc layers join finance --json
CT_FIXTURE=list       src-tauri/fixtures/mock-cc doctor --json   # enumerates this corpus too
```

Same `$CT_FIXTURE`/`$CC_FIXTURE`/`--fixture` convention as `doctor` (`mock-cc`'s own
header comment documents the shared precedence order); defaults to `available` when
unset. `layers` (list) always exits `0` once a fixture body is found (same simpler
convention as `deprovision`/`update`) — `layers join` follows cli-contract.md D7.1's
per-`result` exit-code table above.
