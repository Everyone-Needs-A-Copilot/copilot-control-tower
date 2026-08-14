# Initiative 06 validation assets

This directory contains the technical validation contracts and evidence for Initiative 06. The active owner-approved test contract is the [Phase 5 technical completion plan](../phases/phase-5-technical-ecosystem-completion-plan.md).

Current assets include:

- [`github-governance-audit-2026-08-14.md`](github-governance-audit-2026-08-14.md), which records the applied solo-owner GitHub settings and Hermes exclusions;
- [`clean-framework-environment-validation-protocol.md`](clean-framework-environment-validation-protocol.md), which prepares TASK-303's mandatory clean-environment technical proof; and
- the fleet census collector, schema, validator, fixtures, and provisional reports described below.

Two preserved protocols are deferred and are not Initiative 06 completion gates:

- [`clean-home-second-mac-validation-protocol.md`](clean-home-second-mac-validation-protocol.md) prepares TASK-289 / AC-18 against the final signed artifact.
- [`nontechnical-participant-validation-protocol.md`](nontechnical-participant-validation-protocol.md) preserves future participant-validation requirements after Pablo's technical dogfooding.

The deferred protocols are durable future contracts only. They do not claim a second-Mac run, participant recruitment, consent, scheduling, or result.

## Eligible fleet census preparation

The census assets prepare TASK-300’s owner-approval gate without changing any project. The current report is provisional because TASK-297's signed organization/accounting releases are not complete. TASK-295’s entitlement lifecycle is complete, but release inputs still prevent approval.

## Contract

[`fleet-census.schema.json`](fleet-census.schema.json) and [`validate-fleet-census.py`](validate-fleet-census.py) jointly require one row per exact absolute repository path. Schema validation alone is insufficient: the semantic validator binds each unique repository identity to its unique path, and each proposed operation to that repository and its exact targets. Wildcards are invalid. Every row records:

- repository class and detected product families;
- entitlement state and non-identifying evidence selected independently for that repository’s product families and protected layers;
- dirty, customized, missing, and ambiguous state without recording file names or content;
- structured census exclusions, their source, and a plain reason;
- the responsible actor, proposed operation, exact target paths, and approval status.

Owner-policy exclusions are supplied as repeated exact `--owner-exclusion` paths. The collector rejects wildcards. A path absent from classification is accepted only when it is a readable nested Git root below a classified archive; the collector emits a synthetic exact no-mutation row for that repository. This lets the legacy nested Hermes h1 checkout remain explicitly protected without making an archive subtree part of ordinary project fanout. The current company policy excludes every confirmed Hermes repository from company-wide ecosystem mutation.

The census does not replace conformance’s global exception schema. Its exclusions answer only whether an exact repository may enter a later fleet operation. A conformance failure still belongs to the conformance report and its reviewed exception mechanism.

Approval status is a closed `pending`, `approved`, or `rejected` enum. Every row in a provisional report is `pending`, ineligible, and plan-free, so a provisional census always grants zero mutation authority. The collector always emits provisional evidence, even after its release dependencies complete. [`prepare-fleet-census.py`](prepare-fleet-census.py) is the only promotion path: it requests one fresh canonical plan for the exact non-excluded candidates, verifies the private and public plan records agree, records the expiration, binds every exact target, and distinguishes planned mutation from canonical no-change. A wildcard, directory family, repository glob, or stream-plan brace expansion is never mutation authority.

## Read-only collector

[`collect-fleet-census.py`](collect-fleet-census.py) enumerates only committed `classification.toml` rows under the configured projects root. It reads Git status as NUL-delimited metadata, project lock checksums, and the private entitlement ledger. The report stores only a ledger kind/state/receipt and per-repository evidence receipts; it never stores the ledger path or local identity. It does not fetch, install, reconcile, invoke Control Tower, inspect Git remotes, or write in a candidate repository. Dirty Git paths, branch names, identities, tokens, file content, and remote URLs are not stored.

The provisional baseline was produced with explicit inputs:

```bash
python3 collect-fleet-census.py \
  --projects-root /Volumes/Dev/Sites \
  --classification /Volumes/Dev/Sites/COPILOT/claude-copilot/tools/cc/classification.toml \
  --entitlement-ledger <machine-local-entitlement-ledger> \
  --owner-exclusion /Volumes/Dev/Sites/TSM/_archive/h1 \
  --owner-exclusion /Volumes/Dev/Sites/TSM/h2 \
  --owner-exclusion /Volumes/Dev/Sites/TSM/h3 \
  --owner-exclusion /Volumes/Dev/Sites/TSM/hermes \
  --dependency TASK-281=completed \
  --dependency TASK-295=completed \
  --dependency TASK-297=in_progress \
  --observed-at 2026-08-12T18:15:00Z \
  --output provisional-fleet-census-2026-08-12.json
```

The exact timestamp is an explicit input so identical filesystem state and inputs produce identical output and census identity.

Validate both the JSON shape and cross-row/authority semantics before review:

```bash
python3 validate-fleet-census.py \
  provisional-fleet-census-2026-08-12.json \
  --schema fleet-census.schema.json
```

## Required refresh before approval

Do not ask the owner to approve this provisional report. After TASK-297 completes:

1. rerun the collector against the same configured root and the installed entitlement ledger;
2. use `prepare-fleet-census.py` to run the canonical transaction’s read-only plan for the exact remaining candidates;
3. retain only its exact plan ID, expiration, fingerprint, and exact file targets in the census;
4. independently verify every held/excluded/candidate disposition;
5. request owner approval for that immutable census ID only.

TASK-288 must reject any request that supplies a wildcard, a different census ID, an unapproved row, or a target not present in that row’s exact canonical plan.
