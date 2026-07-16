# doctor fixture corpus + mock `cc` (T2)

Drives Control Tower through every `doctor --json` state without a real fleet or a real
CLI. Referenced by the M1 architecture WP (`.copilot/wp/1.md` §4) and consumed by T3/T4/T8/T9.

**M3 addition:** `mock-cc` now also implements an `auth` verb — the first-run wizard's
device-flow sign-in seam (`cc auth --json` / `cc auth login --json`, ceremony + poll,
scenarios `authorized|denied|expired|timeout|pending`). See
[`wizard/README.md`](wizard/README.md) for the auth seam docs and the wizard scenario
corpus (`wizard/scenarios/*.json`); this file continues to document the `doctor`-only
corpus below.

**WS-A Stream-Z addition:** `mock-cc` now also implements `auth status`, `layers`/
`layers join <id>`, `freshness --all-projects`, and `update --project <path>`/
`update --fanout` — the app-side surfaces for the WS-A verbs landed in `claude-copilot`'s
`tools/cc`. The `auth` ceremony/poll bodies additionally carry `schema_version`/`kind`
(and the ceremony a `device_code`) ADDITIVELY, matching `auth.schema.json`, without
breaking the existing wizard consumer (unknown fields are dropped by the Rust seam). See
[`layers/README.md`](layers/README.md) and [`projects/README.md`](projects/README.md)
for those two new fixture corpora (both validated by `validate.sh`, alongside the
`doctor` corpus below); `deprovision/corpus/` and `update/corpus/` remain unchanged and
are still exercised by this repo's Rust-side tests directly, not this Python validator.

Conforms to [`docs/01-architecture/schemas/doctor.schema.json`](../../docs/01-architecture/schemas/doctor.schema.json)
(Draft 2020-12) and [`_envelope.schema.json`](../../docs/01-architecture/schemas/_envelope.schema.json).

## Layout

```
src-tauri/fixtures/
  README.md          this file
  validate.sh         runs the schema validator — green on corpus/, invalid/ excluded by design
  validate.py          the actual validator (Python + jsonschema, Draft 2020-12)
  mock-cc             executable stand-in for the real `cc`/`copilot` CLI
  corpus/             *.json — schema-valid fixtures, one per top-level `status`
  invalid/            *.json — adversarial/malformed fixtures for the CliUnreadable path
```

## Corpus map (`corpus/`) — one file per `status` value

| File | `status` | What it exercises |
|---|---|---|
| `healthy-clean-fleet.json` | `healthy` | All 4 products (`knowledge`/`cli`/`claude`/`codex`) x all 4 layers (`foundation`/`org`/`dept`/`personal`) — 16 checkers, all `pass`, `offline:false`, no `auth` entries. Satisfies the schema's fail-closed `allOf` (no fail checker, no offline, no expired/revoked auth). The baseline that proves the dropdown renders all 16 (product, layer) buckets. |
| `needs-attention-codex-dept-fail.json` | `needs-attention` | Worst-wins: `codex`/`dept` has a `fail` (destructive, with `repair` + `escalate`), `claude`/`dept` has a `warn`, everything else `pass` — proves one failing product/layer drags the whole top-level status down while the other products stay healthy in their own buckets. |
| `offline.json` | `offline` | `offline:true`, cached/stale `warn` findings (no `fail`), 3 products touched. |
| `signed-out-claude-personal.json` | `signed-out` | `auth: [{state:"expired"}]` for `claude`/`personal`; a `warn` checker cross-references it. |
| `setup-needed-first-run.json` | `setup-needed` | First-run lifecycle state: minimal checkers, `score:0`, nothing materialized yet. |
| `it-config-incomplete-org-mdm.json` | `it-config-incomplete` | `knowledge`/`org` `fail` (`escalate:"it"`) plus `auth: [{state:"revoked"}]` — exercises the *other* auth state and the top-of-ladder precedence (outranks signed-out/needs-attention). |
| `update-available-cli-foundation.json` | `update-available` | `cli`/`foundation` `warn` with `repair`, `local_sha`/`remote_sha` diverging. |
| `syncing-knowledge-org.json` | `syncing` | `knowledge`/`org` `warn` mid-sync, `claude`/`personal` `pass` — mixed org-syncing/personal-healthy per the task's required scenario. |
| `waiting-for-network-startup.json` | `waiting-for-network` | Lifecycle state distinct from a *confirmed* `offline` verdict — the app hasn't completed its first check yet; minimal/no product-scoped checkers. |
| `updating-app-self-update.json` | `updating-app` | Self-update-in-progress lifecycle state. |

Across the 10 files, all 4 products and all 4 layers appear at least once (all 16 combos
appear in `healthy-clean-fleet.json` alone); both `auth.state` values (`expired`,
`revoked`) each appear once.

## Adversarial corpus (`invalid/`) — the CLI-unreadable / 11th-state cases

These must **never** render as `healthy` (or any other trusted state) — they exist so
T3/T9 can prove the app's own client-side `CliUnreadable` fallback (the 11th state,
never emitted by the CLI itself — see `doctor.schema.json`'s `$comment` on `status`).

| File | What's wrong | Why it's excluded from the schema-valid set |
|---|---|---|
| `schema-version-above-max.json` | `schema_version:"2.0"` | **Syntactically schema-valid** (the JSON Schema only regex-checks `MAJOR.MINOR[.PATCH]`; the numeric range is a Rust-side compiled-in constant, not encodable in JSON Schema — see the schema's own `allOf` `$comment`). Otherwise a well-formed `healthy` body. Exercises the app's bidirectional range gate, not the JSON Schema validator. |
| `schema-version-below-min.json` | `schema_version:"0.9"` | Same as above, other direction — proves "older is as fatal as newer" per the contract. |
| `checker-missing-destructive.json` | a checker omits `destructive` | **Fails schema validation** (`destructive` is `required`). Missing security-relevant field ⇒ fail-closed, whole verdict unreadable per architecture §2. |
| `checker-missing-severity.json` | a checker omits `severity` | **Fails schema validation** (`severity` is `required`). Same fail-closed rule. |
| `not-valid-json.json` | truncated/malformed JSON body | Doesn't even parse as JSON. |

`validate.sh`/`validate.py` check `invalid/` too, but assert the *opposite* of `corpus/`:
every file must either fail schema validation, fail to parse, or be one of the two
documented schema-valid-but-semantically-out-of-range exceptions above. A regression
that makes an adversarial fixture "accidentally valid" fails the script.

## Running the validator

```bash
src-tauri/fixtures/validate.sh
```

Requires `python3` with `jsonschema` + `referencing` (`pip3 install jsonschema
referencing`). Validates every `corpus/*.json` against `doctor.schema.json`
(Draft 2020-12, resolving the `_envelope.schema.json` `$ref`s) and confirms every
`invalid/*.json` is doing its job. Exits non-zero on any surprise in either direction.

## Mock `cc` (`mock-cc`)

An executable bash script that stands in for the real `cc`/`copilot` CLI's `doctor
--json` verb, driven entirely by the fixture corpus above. As of M3 it also stands in
for `cc auth --json` (the wizard's device-flow sign-in seam) — see
[`wizard/README.md`](wizard/README.md) for that half; everything below is `doctor`-only.

```bash
# select by env var (matches the M1 architecture WP's documented convention)
CT_FIXTURE=needs-attention-codex-dept-fail src-tauri/fixtures/mock-cc doctor --json

# alias, same meaning
CC_FIXTURE=offline src-tauri/fixtures/mock-cc doctor --json

# or by flag (wins over either env var)
src-tauri/fixtures/mock-cc doctor --json --fixture signed-out-claude-personal

# list every available fixture name
CT_FIXTURE=list src-tauri/fixtures/mock-cc doctor --json

# simulate the env-error / exit-2 path (no trustworthy body at all)
CT_FIXTURE=exit-2 src-tauri/fixtures/mock-cc doctor --json
```

**Exit codes** (contractually correct per `cli-contract.md`'s `doctor` row):
- `0` — JSON parses and no checker has `severity:"fail"`
- `1` — JSON parses and at least one checker has `severity:"fail"`
- `2` — `CT_FIXTURE=exit-2`, an unknown fixture name, or a missing/unrecognized verb

Fixture name resolves against `corpus/<name>.json` first, then `invalid/<name>.json`,
then as a literal path. **Deliberate design choice:** every `invalid/` fixture *except*
`exit-2` is emitted with the exit code its body would earn on its own merits (usually
`0`, since none of them contain a `severity:"fail"` checker) — a "successful"-looking
exit code carrying a poisoned body. This is intentional and is the harder, more honest
adversarial case: it forces the app to fail closed on the **body** (parse failure,
missing required field, out-of-range `schema_version`) rather than leaning on the exit
code to save it. Only `exit-2` exercises "trust nothing, the CLI itself said error."

## How T4/T8 wire the app to it

Per the M1 architecture WP (`.copilot/wp/1.md` §3–4, `cli/path.rs`'s dev-override
branch): set the dev-only env var the path resolver already special-cases —

```bash
CT_CLI_PATH=/absolute/path/to/src-tauri/fixtures/mock-cc \
CT_FIXTURE=<corpus-or-invalid-name> \
  <run the Tauri app in dev>
```

`cli/path.rs` resolves `CT_CLI_PATH` instead of the bundle-relative production path
(dev/debug builds only — never consulted from a managed/forced domain), and
`cli/spawn.rs` invokes it exactly as it would the real CLI: `Command::new(CT_CLI_PATH)
.arg("doctor").arg("--json")`, reading stdout/exit-code the same way in both cases. The
web-UI-only static-fixture mode (§4 of the WP) can import `corpus/*.json` /
`invalid/*.json` directly through the same DTO shape to unblock UI work before the Rust
timer lands — point it at this directory rather than re-authoring fixtures.

To sweep every state in one session (e.g. for a manual QA pass or a screenshot script):

```bash
for f in src-tauri/fixtures/corpus/*.json src-tauri/fixtures/invalid/*.json; do
  name="$(basename "${f%.json}")"
  echo "=== $name ==="
  CT_FIXTURE="$name" src-tauri/fixtures/mock-cc doctor --json | head -c 200
  echo "  (exit=$?)"
done
```
