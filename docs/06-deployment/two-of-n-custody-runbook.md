# Two-of-N signing-custody runbook

> **UNVALIDATED HYPOTHESIS (Founding Decision #9).** This runbook is written
> for the org's security team / release-signing custodians interacting with
> Admin mode's release-signing setup — a facet of the same unvalidated
> IT/Admin-operator surface (`SOUL.md` §9 item 9). No real custodian has
> exercised this process end to end.

> **Status up front, plainly: the verifier now exists in code, but is not
> yet the LIVE path, and no real custody decision has been made.**
> `src-tauri/src/updater/multisig.rs` (M7-S5, `tc task get 64`) landed a
> compiled-in `TRUST_ROOTS_B64: [&str; 3]` array + `THRESHOLD_K = 2`, and
> `updater::verify::verify_update_multisig` requires that many **distinct**
> roots to each independently sign the same manifest (a duplicated signature
> from one root is de-duplicated, never counted twice — see that module's own
> doc). **This is a deliberate sibling entrypoint, not a replacement**:
> `updater::trust::trust_root()` and `updater::verify::verify_update` (the
> single-key path) are explicitly kept working, unmodified, and remain what
> the self-update flow actually calls today. All three roots in
> `TRUST_ROOTS_B64` are **dev keys** (the module's own doc comment says so
> plainly) — no production key exists, and no cutover from the single-key
> path to the multisig path has happened. Everything below documents the
> design (`architecture.md` §7/§11 item 1, `threat-model.md` §2.3/§3,
> `incident-response.md` §1) plus this landed-but-not-yet-live code — it is
> not a description of a control that is protecting a real release today.
> `docs/05-security/signing-custody.md` (the S5 task's own required
> deliverable, per `tc task get 64`'s acceptance criteria) had not been
> written as of this runbook's own drafting — check whether it now exists
> and read it as the primary security-team doc; this runbook is the
> operator/standup-facing companion, not a replacement for it.

## Why this exists

A self-update's minisign signature is the gate between a signed update
manifest and every machine that auto-installs it. If that single private key
is ever compromised, an attacker ships a validly-signed, malicious Control
Tower release that every auto-updating machine installs — with a live `gh`
token in scope and the ability to rewrite `.claude/` agents fleet-wide. This
is the single highest-*damage* entry in the threat model (`threat-model.md`
§3, DREAD rank #2, avg 6.6 — "Medium-High," mitigated not eliminated by
custody separation). A **single popped key should not be fleet-wide RCE** —
that is what two-of-N buys: no one custodian's compromise is sufficient on
its own.

## The design, as landed in code

- **A new module, not an edit to `trust.rs`.** Rather than mutating M4's
  single-root `trust.rs` in place, `updater::multisig` adds a **separate**
  compiled-in `TRUST_ROOTS_B64: [&str; 3]` array + `THRESHOLD_K: usize = 2`
  constant — same "code, not config" discipline as the single root (never
  read from a preference, environment variable, or file). Keeping the two
  trust models in separate files means `trust.rs`'s existing fitness scans
  stay scoped to exactly what they always scanned, and the single-key path
  keeps working unmodified while the k-of-N path is built and tested
  alongside it.
- **`updater::verify::verify_update_multisig`** is the new, stricter sibling
  to `verify_update`: it requires **k valid, independent signatures**
  (`THRESHOLD_K = 2` today) over the same manifest bytes. It tracks *which
  root index* each valid signature matched and de-duplicates by index before
  comparing against the threshold — two copies of the same custodian's
  signature count as **one**, never two, so a duplicated or replayed
  signature can never masquerade as a second, independent approval.
- **Compile-time guarantees, not just tests.** `THRESHOLD_K >= 2` and
  `TRUST_ROOTS_B64.len() >= THRESHOLD_K` are both asserted with `const _: ()
  = assert!(...)` — a future edit that dropped the threshold to 1 (silently
  reverting to single-key trust) fails the **build**, not just a test run.
- **Adversarial test coverage already exists**, including: fewer than k
  valid signatures rejected, a duplicate signature from one root not
  counting twice, an attacker-signed manifest rejected, and a downgrade
  manifest rejected under the multisig path the same way the single-key path
  already rejects one (`src-tauri/fixtures/updater/multisig-*.json` +
  `*.minisig` fixtures, generated the same scratch-project way `trust.rs`'s
  own dev key was — see `fixtures/updater/README.md`).
- **Dev keys only.** All three `TRUST_ROOTS_B64` entries are dev keypairs
  generated for this milestone; the corresponding secret keys are not
  committed anywhere, only the fixtures they signed are.
- **Not yet wired as the live path.** Nothing in the running update flow
  calls `verify_update_multisig` today — the self-update machinery still
  calls the single-key `verify_update`. Switching the live path over (and
  deciding whether that's a hard cutover or a channel-gated rollout) is a
  separate decision from the code existing.

## Custody separation (the actual operational content)

Two things must be held **separately**, by different people/systems, per
`architecture.md` §7:

1. **The Apple Developer ID codesigning certificate** — proves *this Team ID
   built the binary*.
2. **The minisign signing key(s)** — proves *this update manifest is the one
   the release process actually cut*, independent of the Apple chain.

A single popped credential (e.g. a leaked Developer ID cert) should not, on
its own, grant the ability to ship a malicious *update* — the minisign gate
is a second, separately-custodied check the watchdog verifies before
promoting a staged bundle. Under two-of-N specifically, the minisign
custody itself splits further: at least two independent parties (or an
HSM/vault plus a separate human custodian) must each hold one key/share, so
compromising one custodian's material is insufficient to forge a valid
release signature alone.

**Alternative considered and not (yet) chosen:** a transparency-log witness
(an independent, append-only public log of every release build hash) instead
of, or alongside, k-of-N key custody. `architecture.md` §7 names both as
live options; `architecture.md` §11 item 1 lists which mechanism to use, and
who holds the second key, as **open decisions** — not yet ratified.

## What's owner-gated (not this session's, or any code session's, to resolve)

- **Who holds the second (and any further) key.** `threat-model.md` §5 item 1
  says it plainly: *"a two-of-N scheme with an unassigned second custodian
  is, in practice, a one-of-one scheme with a placeholder."* Assigning real
  people/systems to real key shares is a human decision this repo cannot
  make for you.
- **Generating the real production keypair(s)** in a fresh, dedicated
  HSM/vault — never reusing the dev key checked into `trust.rs`'s doc
  comment, and never generating in a location any single engineer's laptop
  could exfiltrate from.
- **Choosing k-of-N vs. a transparency-log witness** (or both) as the
  release process the org actually runs.
- **Swapping `trust.rs`'s and/or `multisig.rs`'s literal(s)** for the real
  production key(s), and deciding whether the live self-update path cuts over
  from `verify_update` to `verify_update_multisig` (or runs both), before
  `stable`-channel self-update promotion is ever enabled in CI
  (`release-and-versioning.md` §2 step 3) — a mechanical edit once the
  custody decision above is made, not a design change.

## If a key is ever compromised

This runbook is about *setting up* custody, not incident response — if you
suspect a minisign key has been exposed, follow
[`../05-security/incident-response.md`](../05-security/incident-response.md)
§1 (minisign signing-key compromise) instead: it covers generating
replacement keys in fresh custody, the bootstrapping constraint (rotating the
trust root requires shipping a new signed release, not a config push), and
signing the emergency release with every uncompromised custodian available —
even exceeding the normal two-of-N minimum for that one release.

## Cross-references

- [`../05-security/security-and-trust.md`](../05-security/security-and-trust.md)
  — the trust-basis doc (compiled-in trust roots, cross-repo signing
  contract, STRIDE across self-update).
- [`../05-security/threat-model.md`](../05-security/threat-model.md) §2.3,
  §3, §5 — the full threat analysis this custody model mitigates, and the
  explicit "not yet assigned" flag on the second key.
- [`standup-runbook.md`](standup-runbook.md) step 7 — where this fits in the
  overall standup sequence (today: the verifier code exists, but there is
  no real custody to configure and no live cutover yet).
