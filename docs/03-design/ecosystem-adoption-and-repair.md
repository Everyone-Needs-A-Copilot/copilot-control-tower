# Ecosystem adoption and repair

Status: implemented for Phase 6 onboarding
Authority: `cc onboard` computes; Admin and User apps render

## Service promise

Setup begins by learning what is already present. A person never has to remove
an existing Copilot ecosystem just to make it manageable by Control Tower.
Recognized state is adopted, missing state is added, and unfamiliar state is
left untouched for review.

This promise applies at the boundary each app owns:

- Admin checks organization and department repositories on GitHub. It reuses
  compatible private repositories, creates only confirmed-missing private
  repositories, and blocks on public, unreadable, or incompatible state.
- User Setup checks personal repositories, the machine SSH identity, the layer
  manifest, materialized Claude and Codex state, and approved project roots.
  It never reads personal content into organization output.
- Project activation checks each discovered project independently. Existing
  Claude or Codex setup is kept; only missing components are offered.

## User-facing vocabulary

The apps use five plain actions. These labels are renderings of CLI decisions,
not app-side inference.

| App label | CLI action | Meaning |
|---|---|---|
| Keep | `reuse` | Already supported; make no content change. |
| Add | `create` | Confirmed missing; create the managed item. |
| Move safely | `migrate` | Recognized predecessor at a supported legacy location; preserve a rollback copy and move it. |
| Complete | `repair` | Recognized partial managed setup; retain compatible layers and add the missing ones. |
| Needs review | `review` | Ownership or compatibility is ambiguous; perform no mutation. |

The interface summarizes decisions before Apply. “Needs review” is a holding
state, not a destructive remediation path. It shows what was preserved and
offers retry after the external issue is resolved.

## Journey

1. **Check.** The engine performs the complete read-only inventory.
2. **Explain.** The app shows what will be kept, added, moved, completed, or
   held for review.
3. **Confirm.** The normal Continue/Set up action authorizes only the displayed
   plan.
4. **Recheck.** Apply repeats repository, SSH, store, and local-state probes.
5. **Adopt and repair.** Recognized changes are applied atomically. An existing
   manifest receives a content-addressed rollback copy before replacement.
6. **Verify.** The independent doctor/setup check reads the resulting state
   again. Success is rendered only from a healthy engine verdict.

## Manifest migration rule

The supported predecessor used `component:` where the current manifest uses
`product:`. That exact structural predecessor may be translated
deterministically. Existing products outside the requested Claude/Codex stacks,
including the CLI product, are retained in the merged manifest.

The current machine-wide manifest location is:

`~/.config/copilot/copilot.layers.yml`

Recognized manifests at prior supported locations may be migrated there.
Before a repair or migration, the original bytes are copied to:

`<manifest-parent>/.copilot-control-tower-backups/<sha256>/copilot.layers.yml`

Unrecognized YAML, conflicting Claude/Codex identities, duplicate ranks, or
invalid layer shapes are never normalized by guesswork.

## State and failure cases

- **Nothing exists:** show Add; create only after confirmation.
- **Everything is current:** show Keep; Apply is idempotent.
- **Recognized partial setup:** show Complete; keep unrelated products and add
  missing managed layers.
- **Recognized legacy location/schema:** show Move safely and explain that a
  rollback copy is kept.
- **Existing personal repository with unfamiliar content:** show Needs review;
  do not seed, overwrite, or create other repositories during that Apply.
- **Unmanaged SSH alias or manifest conflict:** hold before any mutation.
- **Offline/unreadable:** distinguish unknown from missing and make no change.
- **Interrupted Apply:** a rerun starts from a new read-only inventory and
  reuses completed stages.

## Accessibility and visual behavior

Action is never communicated by color alone. Each row has a shape, action word,
title, and detail. The reading order is title, action, explanation, rollback
note. Native light/dark colors and system symbols are used. No countdown or
indeterminate promise of completion is shown; progress uses named stages.

## Security boundaries

- No personal path, repository content, or credential enters Admin output.
- No raw token or private key enters the report, backup, manifest, or app log.
- Apply is fail-closed: all adoption decisions must be safe before the first
  mutation.
- Backups are local and contain only the already-local non-secret layer
  manifest. Secret-shaped material is never migrated by this flow.
- The app never computes compatibility or edits YAML. The signed CLI owns
  inventory, migration, atomic write, rollback location, and verification.
