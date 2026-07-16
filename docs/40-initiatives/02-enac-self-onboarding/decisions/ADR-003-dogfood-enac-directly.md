# ADR-003 — Dogfood ENAC directly, no Acme throwaway

**Status:** Accepted (owner, 2026-07-16)
**Initiative:** [`02-enac-self-onboarding`](../README.md)

## Decision

Onboard **Everyone Needs A Copilot** onto its own ecosystem directly, as the first
real consumer. Do **not** run a throwaway `Acme-Copilot` practice company first.

## Why

- **ENAC is the hardest case** — publisher *and* first consumer at once. If
  onboarding works for ENAC, it works for any customer. A vanilla-customer practice
  run (Acme) would not exercise the ENAC-specific split (public base vs private
  `-internal`) at all.
- **The owner's stated intent:** "I want to do it with my company... knowing that
  everything's in place to actually make it work for anybody."
- **Safety comes from sequencing, not from a fake company.** The risks are
  contained by: (1) making repos public is decoupled and deferred to the very last
  gated step; (2) validating on a scratch project before any real one;
  (3) snapshotting the three machine-global surfaces; (4) never-destroy protecting
  every working tree during rollout. See
  [`phase-2-standup-and-rollout.md`](../phases/phase-2-standup-and-rollout.md).

## Consequence

- The initiative plans ENAC's real migration, including the Phase 1 base extraction
  that a vanilla customer would never do.
- The one thing ENAC has that no customer has — the private→public promotion
  pipeline (`copilot promote`, not yet built) — is expected and documented, not a
  surprise.

## Alternative rejected

A throwaway `Acme-Copilot` org as a practice run before touching ENAC. Rejected by
the owner: it throws away the work of a practice run, doesn't test the publisher
case, and the safety it was meant to provide is better achieved by sequencing on
ENAC directly.
