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

The census assets prepare TASK-300’s owner-approval gate without changing any project. The preserved provisional reports document earlier dependency states. The checked approval-ready report records TASK-281, TASK-295, and TASK-297 complete, but its single canonical plan expired at `2026-08-14T19:12:12Z`; it is deliberately stale evidence, cannot be presented for owner approval, and grants zero mutation authority. A new census and unexpired plan must be generated and independently verified when the upstream completion gates are settled.

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

An approval-ready census is valid only while every planned row shares the same plan ID, plan fingerprint, and expiration and that single plan remains unexpired. Canonical reconcile rows require nonempty exact targets, canonical no-change rows require empty targets, and held or excluded rows must be plan-free; no dependency-refresh operation can survive promotion. Preparation accepts only the private plan store's exact unclaimed `reviewed` state and captures one current UTC instant for its creation/expiration check. Validation likewise captures the current UTC time once for the entire census so no row can observe a different expiration boundary. An expired or consumed approval-ready plan must be regenerated from a fresh read-only plan; changing timestamps or copying a different plan identity into the old census is not permitted. Provisional historical evidence remains valid because it contains no plans and grants zero authority. A superseded census can never regain mutation authority.

The census identity excludes only the owner’s decision fields: global approval, row approval status, row eligibility derived from approval, and approval counters. Those fields are normalized to their pending zero-authority values before hashing. Consequently, approving or rejecting rows preserves the exact approval-ready census ID that the owner reviewed; repository observations, dispositions, plans, targets, exclusions, and every other fact remain identity-bound.

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

Do not ask the owner to approve a provisional or expired approval-ready report. When the upstream completion gates are settled:

1. rerun the collector against the same configured root and the installed entitlement ledger;
2. use `prepare-fleet-census.py` to run the canonical transaction’s read-only plan for the exact remaining candidates;
3. retain only its exact plan ID, expiration, fingerprint, and exact file targets in the census;
4. independently verify every held/excluded/candidate disposition;
5. request owner approval for that immutable census ID only.

## Owner-decision ceremony

[`approve-fleet-census.py`](approve-fleet-census.py) records the owner’s decision without touching a fleet repository. It accepts only a schema-valid, semantically valid, unexpired `approval-ready` census whose global and row decisions are still pending and whose mutation authority is zero. The owner must explicitly supply the exact census ID, the `product-owner` actor, an `approved` or `rejected` decision, and a separate selection JSON file. There is no wildcard, inferred selection, or default-all option.

The selection JSON repeats the reviewed census ID and its single canonical plan identity. Every selected repository record must contain the exact repository identity, exact absolute repository path, and the complete sorted target list copied from that repository’s plan:

```json
{
  "census_id": "sha256:<reviewed-census-digest>",
  "plan": {
    "plan_id": "plan_<reviewed-plan-id>",
    "plan_fingerprint": "sha256:<reviewed-plan-digest>",
    "expires_at": "<reviewed-plan-expiration>"
  },
  "repositories": [
    {
      "repo_identity": "sha256:<reviewed-repository-identity>",
      "repo_path": "/exact/repository/path",
      "target_paths": [
        "/exact/repository/path/exact-reviewed-target"
      ]
    }
  ]
}
```

For `approved`, the explicit nonempty selection is the complete authorized mutation subset; every unselected candidate and every canonical-no-change row is recorded as rejected and ineligible. For `rejected`, the selection must explicitly enumerate every canonical-reconcile candidate and its exact targets, proving which complete proposal the owner rejected. Held, excluded, ambiguous, dirty, customized, non-canonical, and exact Hermes rows can never be selected.

Run the command only after independent QA confirms the plan remains unexpired:

```bash
python3 approve-fleet-census.py fresh-approval-ready-census.json \
  --selection exact-owner-selection.json \
  --census-id 'sha256:<reviewed-census-digest>' \
  --actor product-owner \
  --decision approved \
  --output approved-fleet-census.json
```

The command captures one UTC instant, validates both input and output against the existing validator at that instant, preserves the immutable census ID, changes only global/row decision fields and approval counters, and creates the output exclusively. It refuses an existing output path or the input path, so approval evidence is never silently overwritten. A stale, superseded, invalid, census-mismatched, plan-mismatched, partial, extra, reordered, duplicate, wildcard, or previously authorized request fails before output creation.

TASK-288 must reject any request that supplies a wildcard, a different census ID, an unapproved row, or a target not present in that row’s exact canonical plan.
