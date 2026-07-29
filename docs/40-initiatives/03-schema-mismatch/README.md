---
initiative: 03-schema-mismatch
title: CLI Layer Schema Mismatch and Discord Hook Outage
status: complete
status_note: Original remediation released in 0.1.1; Finder-path Detect follow-up released with signed/notarized cc 1.7.10 in Control Tower 0.1.2.
owner: Pablo Alejo
created: 2026-07-28
execution_context:
  prd: "Incident remediation tracked under tc task 170."
  tasks: "tc tasks 171-174; release replacement is task 174."
superseded_by: null
---

# CLI layer schema mismatch and Discord hook outage

| Field | Value |
|---|---|
| Date | 2026-07-28 |
| Status | Remediation released in Control Tower 0.1.1 |
| Impact | Claude Code rejected every prompt at `UserPromptSubmit` |
| Trigger | The aggregate layer manifest used `product: cli`, while CLI Copilot still filtered for `component: cli` |

## Executive summary

The ecosystem manifest contract had migrated from `component` to `product`, but
CLI Copilot's layer resolver and its reference documentation had not migrated
with it. The resolver therefore treated a valid aggregate manifest as if it had
no CLI layers, loaded only the public foundation, and omitted the internal
Discord service.

The user-level Discord hook then ran `copilot discord ...`. That command did not
exist in the foundation-only command set and exited with status 2. Claude Code
correctly treats a nonzero `UserPromptSubmit` hook as a prompt rejection, so an
optional notification bridge became a full harness outage.

The repair establishes `product` as the canonical manifest field, retains a
bounded compatibility path for legacy `component` manifests, rejects
contradictory dual declarations, and makes Discord hook shims fail open when the
optional transport is unavailable.

## 2026-07-29 follow-up: Finder Detect failure

Control Tower 0.1.1 later reached `layer-manifest` and reported:

```text
The installed `copilot` command is unavailable.
```

This was a separate launch-environment defect with the same underlying process
failure: a local terminal happened to supply state that the shipped app did not.
The app correctly located its bundle-relative `cc` helper by absolute path, but
that helper located its own `copilot` dependency only with `shutil.which`.
Finder launches an app with `/usr/bin:/bin:/usr/sbin:/sbin`, so Homebrew's
`/opt/homebrew/bin/copilot` disappeared even though it was installed and usable.

Three testing gaps allowed this to ship:

1. App tests replaced `cc` with a mock and therefore stopped at the app/CLI
   boundary. They never exercised the bundled helper's dependencies.
2. The upstream release probe erased the entire environment instead of changing
   only `PATH`, then accepted any exit-0/exit-1 ecosystem report without
   requiring the `layer-manifest` inspection.
3. The branch producing `cc` had no CI job for its onboarding contracts.

The repaired boundary follows one rule: `cc` owns machine inventory and
resolves every direct dependency to a canonical absolute executable. Control
Tower remains a parse-only client. Both the UI and the headless runner call the
same `CliClient.ecosystemOnboardPlan` production verb; neither reimplements
inventory.

New controls:

- `cc 1.7.10` centrally resolves `gh`, `copilot`, `claude`, and `codex` from
  the current `PATH` followed by bounded user/Homebrew locations.
- The upstream macOS release gate preserves the signed-in session, substitutes
  Finder's `PATH`, covers both products, and requires a real layer-manifest
  inspection.
- Control Tower's production binary accepts `--headless-detect`, runs all
  three calls in the exact app Detect seam (`auth status`, `doctor`, and the
  ecosystem onboarding plan), prints their typed results as JSON, and exits
  before creating UI.
- `scripts/headless-detect.sh` runs that mode against any app bundle. The User
  release pipeline runs it against the exact embedded, signed helper before
  notarization.
- `scripts/headless-setup-transaction.sh` runs the production
  `WizardModel` from Set up through Verify against the inert fixture helper,
  and independently verifies that the exact apply and verify commands were
  sent. The User release pipeline runs this against the same signed app while
  guaranteeing that the bundled real helper and the user's files are not
  touched.

This is the required testing shape for future background operations: test the
state engine directly, test the app's typed seam headlessly, then run the same
headless command against the final packaged artifact. Opening the UI is a
visual-product check, not the primary integration test.

Follow-up release evidence:

- upstream `cc` PRs:
  <https://github.com/Everyone-Needs-A-Copilot/claude-copilot/pull/46> and
  <https://github.com/Everyone-Needs-A-Copilot/claude-copilot/pull/47>;
- Control Tower PR:
  <https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/pull/3>;
- release:
  <https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/releases/tag/v0.1.2>;
- exact app source:
  `c0fc74a99cb6bd05ec16fbddd922b9030c324d64`;
- `cc 1.7.10` notarization:
  `71e46514-09f5-47ea-a97d-854bb2a26563` (`Accepted`);
- app/DMG notarization:
  `74ac2bb0-80a1-47b5-962c-5295bae1697f` (`Accepted`);
- DMG SHA-256:
  `93c2898ef21b7676859aec5430eb0fca893b452a96187934b232a6d7e92903f6`;
- final artifact headless result:
  `contract=pass`, `read_only=true`, products `claude,codex`,
  `layer-manifest=changes-required/repair`.

## Causal chain

1. Control Tower and the `cc` manifest authority wrote and validated
   `product: cli`.
2. `copilot_cli.config.layers.resolve_cli_layer_chain()` selected only entries
   whose `component` equaled `cli`.
3. It returned no CLI chain instead of reporting a schema incompatibility.
4. Service discovery fell back to the 12-service public foundation.
5. Discord, which lives in the org overlay, disappeared from the command tree.
6. The installed `UserPromptSubmit` shim executed `copilot discord hook ...`.
7. Typer returned status 2 for the missing `discord` command.
8. Claude Code blocked the original prompt.

The original `/protocol` prompt content was unrelated. Any prompt would have
failed while this hook and resolver state were active.

## Contributing factors

- The canonical Control Tower reference still documented `component`, even
  though the running `cc` authority and Rust manifest model required `product`.
- CLI Copilot's resolver treated “zero matching entries” as the ordinary
  foundation-only state. It could not distinguish a real foundation-only
  installation from schema drift.
- Resolver tests primarily used the legacy field, so the aggregate manifest
  shape was not exercised.
- The generated hook skipped safely when no `copilot` executable existed, but
  not when the executable lacked the Discord command or the hook command failed.
- The internal checkout's root virtual environment still pointed at the removed
  pre-overlay `copilot_cli` package, obscuring which executable was healthy.
- Both CLI repositories had long-red default-branch CI. The lint dependency was
  unbounded, the public Git fixture lacked an isolated author identity, and the
  internal job installed an empty legacy root package instead of the split
  foundation plus overlay.
- Control Tower had no packaged N-1/N reader gate. Unit tests in each source
  repository could pass without proving that the exact shipped artifacts
  preserved an organization-only capability.

## Decisions

### Manifest contract

`product` is the field of record:

```yaml
layers:
  - id: org-internal
    role: org
    product: cli
    rank: 30
```

CLI Copilot now follows these rules:

1. Read `product` when present.
2. Fall back to legacy `component` only when `product` is absent.
3. If both fields are present and conflict on a CLI layer, fail with a
   `LayersManifestError`.
4. Do not silently let a legacy field override the canonical field.

The `component: "cli"` field in the JSON output of `copilot layers --json` and
`copilot update --json` is a separate, versioned command-response contract. It
was intentionally left unchanged by this manifest-input migration.

### Hook failure policy

Discord is an optional transport around the local harness. Losing Discord must
not make Claude Code or Codex unusable.

Generated prompt and stop shims now:

- return success when no `copilot` executable is present;
- return success with a concise diagnostic when `copilot discord` is
  unavailable;
- return success with a concise diagnostic when the Discord hook command
  itself fails;
- preserve stdout unchanged when the hook succeeds, so harness context and
  bridge behavior continue to work.

This is transport fail-open, not security fail-open: it only permits the local
harness turn to continue without Discord.

### Writer transaction policy

A manifest writer may not publish a schema or capability change merely because
its own validator accepts the candidate. `cc onboard` now:

1. retains raw unrequested layers and top-level fields;
2. validates the staged candidate with `cc`;
3. asks the installed `copilot --json layers` reader to prove the exact CLI
   chain and service provenance;
4. applies downstream changes before moving the live manifest pointer;
5. restores exact prior bytes and rematerializes prior state on failure; and
6. refuses rollback if another process changed the candidate concurrently.

## Source updates

### `cli-copilot`

- Updated the resolver and its contract documentation to canonical `product`.
- Added legacy-only `component` compatibility.
- Added a hard error for conflicting dual declarations.
- Converted resolver, settings, inheritance, service-loader, and CLI
  integration fixtures to exercise `product`.
- Updated the tier-inheritance reference and user-facing diagnostics.

Primary regression coverage:

- canonical `product: cli` resolves and sorts;
- non-CLI products are excluded;
- legacy `component: cli` still resolves;
- conflicting `product`/`component` declarations fail loudly.

### `cli-copilot-internal`

- Updated the shipped CLI layer template to `product: cli`.
- Hardened generated Claude and Codex Discord hook shims with command
  verification, buffered stdout, separate process groups, a 20-second internal
  timeout capped at 25 seconds, and transport fail-open behavior.
- Added executable-shim tests for command absence, hook failure, and successful
  stdout preservation.
- Migrated the Discord test module to the overlay's canonical
  `copilot_overlay_internal.services.discord` namespace.
- Updated overlay fixtures to the canonical manifest field.

### `claude-copilot` / `cc`

- Released `cc 1.7.9` in signed foundation snapshot `v5.13.10`.
- Added bounded legacy-reader compatibility and dual-field conflict rejection.
- Made onboarding writes product-scoped, consumer-validated, pointer-last, and
  exactly reversible.
- Quarantined `v5.13.9` / `cc 1.7.8`; its tag remains only as immutable incident
  history and its GitHub release is marked prerelease with a do-not-install
  warning.

### `copilot-control-tower`

- Corrected the canonical four-tier manifest reference from `component` to
  `product`.
- Corrected the onboarding manifest example.
- Vendored the signed/notarized universal `cc 1.7.9` helper.
- Added a self-contained release gate over checksum-pinned CLI 1.4.5 and 1.4.6
  wheels plus legacy, canonical, matching-dual, and conflicting manifests.
- Raised the app compatibility floor to `cc 1.7.9` and recorded the exact
  released reader and hook commits.
- Added this incident record, quarantine record, and prevention checklist.
- Published Control Tower `v0.1.1` from exact source commit
  `1288aa64a84f358c8b4e1755e83e87c6eff3e8ac`.

### CI and release controls

- Restored green Python 3.11/3.12 CI in both CLI repositories.
- Pinned Ruff 0.15.20 instead of resolving an unbounded lint tool.
- Made internal CI install a checksum-pinned public foundation artifact and the
  live overlay, then run the Discord and overlay suites.
- Kept private cross-repository credentials out of CI; organization policy
  disables deploy keys, so exact test wheels are committed with provenance and
  checksums.

## Live machine repair

The source-backed global `copilot` executable now resolves the current
aggregate manifest and loads the org overlay. Both user-level Claude and Codex
hook pairs were regenerated from the hardened source.

The internal checkout's root environment was repaired with editable installs of
the foundation and overlay:

```bash
uv pip install \
  --python /Volumes/Dev/Sites/COPILOT/cli-copilot-internal/.venv/bin/python \
  -e /Volumes/Dev/Sites/COPILOT/cli-copilot \
  -e /Volumes/Dev/Sites/COPILOT/cli-copilot-internal/copilot_overlay_internal
```

Do not point `COPILOT_BIN` at an unverified checkout environment. Confirm it
with `copilot layers` and `copilot discord --help` first.

## Verification

The following checks passed after the repair:

```text
cli-copilot v0.3.1:
996 passed, 10 deselected; Python 3.11/3.12 CI green

cli-copilot-internal v0.1.1:
149 passed, 1 deselected; Python 3.11/3.12 CI green

cc 1.7.9:
complete tools/cc suite, focused Ruff, format, and diff checks passed

Control Tower packaged compatibility gate:
CLI 1.4.5/1.4.6 × legacy/canonical/dual/conflict manifests passed

Control Tower native validation:
User bundle passed; 110 smoke scenarios; 214 admin bootstrap checks

Release artifacts:
signed tags v0.3.1, v0.1.1, and v5.13.10 verified by GitHub;
cc 1.7.9 and Control Tower 0.1.1 accepted by Apple notarization;
Control Tower app and DMG passed stapling and Gatekeeper assessment
```

Control Tower release evidence:

- PR: <https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/pull/1>
- release: <https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/releases/tag/v0.1.1>
- app notarization submission:
  `13e2d9e5-c993-4390-8b6f-28787e204411` (`Accepted`)
- DMG SHA-256:
  `4b8be66bc72a46845875b99d3e89c4cbf5bdaea85903c30bb299e39d1a954d75`
- isolated-HOME packaged-helper result: valid `setup-needed` report, with no
  live account or manifest writes

Live behavior was also verified:

- `copilot layers` resolves `org-internal` and `foundation`;
- `discord` is reported as `org-internal (provides)`;
- `copilot discord --help` succeeds;
- the repaired internal `.venv/bin/copilot` succeeds;
- all four installed Claude/Codex hook shims pass `bash -n`;
- all four installed shims contain the fail-open guards.

## Prevention checklist

Before changing the shared layer manifest:

1. Treat `cc`'s manifest validator as the schema authority.
2. Update every consumer to accept the new field before any writer emits it.
3. Keep one release of bounded read compatibility for the prior field.
4. Add a conflicting-dual-field test so ambiguity cannot be silently resolved.
5. Exercise the aggregate multi-product manifest, not only product-local
   fixtures.
6. Run:

   ```bash
   copilot layers
   copilot --json layers
   copilot discord --help
   ```

7. Verify at least one internal-only service appears with org provenance.
8. Execute generated prompt and stop shims against:
   - a binary without `discord`;
   - a Discord hook that exits nonzero;
   - a successful hook that emits stdout.
9. Require all three shim cases to leave the harness usable.
10. Keep the canonical schema reference, validator, writer, and consumer tests
    on the same terminology.
11. Pin CI tool versions and require the default branch to be green before a
    compatibility migration begins.
12. Test exact packaged N-1 and N readers in a clean HOME; do not substitute a
    source checkout or the operator's global environment.

## Release note

Released upstream replacements:

- `cli-copilot v0.3.1` / Python package `1.4.6`;
- `cli-copilot-internal v0.1.1`;
- foundation snapshot `v5.13.10` / `cc 1.7.9`.

`v5.13.9` / `cc 1.7.8` is quarantined and must not be installed or packaged.
Control Tower 0.1.1 is the replacement app train; it may be published only
after its signed/notarized package, clean-HOME onboarding, and compatibility
gates pass.
