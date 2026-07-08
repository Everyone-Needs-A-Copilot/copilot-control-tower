# Signing Custody — Two-of-N Release Signing

| | |
|---|---|
| **STATUS** | **M7/S5 deliverable, updated 2026-07-08** (`.copilot/wp` task 64, `tc task get 64`). Documents the two-of-N signing-custody mechanism as landed in code: `src-tauri/src/updater/multisig.rs` (`TRUST_ROOTS_B64: [&str; 3]`, `TRUST_ROOT_SIGNATURE_IDS`, `THRESHOLD_K: usize = 2`), `src-tauri/src/updater/verify.rs`'s `verify_update_multisig`, and the live `src-tauri/src/updater/check.rs` transport that fetches root-specific signature siblings and calls that k-of-N verifier. **The live verifier is real; production custody is not.** All three compiled-in roots are dev keys — no production key exists, and no second (or third) custodian has been assigned. This is the primary security-team reference for the mechanism; [`../06-deployment/two-of-n-custody-runbook.md`](../06-deployment/two-of-n-custody-runbook.md) is the operator/standup-facing companion. |
| **Scope** | The two-of-N signing policy itself, key custody separation (codesign cert vs. minisign key(s)), and the transparency-log-witness alternative considered. Does **not** cover incident response for a compromised key (see [`incident-response.md`](incident-response.md) §1) or the day-to-day standup sequencing (see the runbook above). |
| **Governing invariant** | `CLAUDE.md` invariant #4: "security posture is inherited and enforced, never weakened." A trust root — one, or N of them — is **compiled-in code, not config**, in every version of this mechanism; no `--skip-verify`/`--force` bypass exists at any threshold. |
| **Flag** | **G-M7-4** — the real two-of-N keys and the second-key-holder assignment are owner-gated, batched for release (`architecture.md` §11 item 1, `threat-model.md` §5 item 1). |

---

## 1. The problem this mechanism closes

M4 shipped a single compiled-in minisign trust root (`updater::trust::TRUST_ROOT_PUBLIC_KEY_B64`) gating every self-update: `updater::verify::verify_update` refuses to stage an update unless its manifest carries a valid signature from that one key. This closed "no signature at all" and "wrong/tampered signature," but left one key as a **single point of trust failure** — `threat-model.md` §2.3 B4 rates minisign-key-compromise the #2 DREAD threat in this project (avg 6.6, "Medium-High"): a single popped or leaked private key lets an attacker ship a validly-signed, malicious release that every auto-updating machine installs, with a live `gh` token and `.claude/`-rewrite capability in scope, fleet-wide, on the normal update cadence.

**Two-of-N signing directly closes that gap**: no single custodian's key compromise is sufficient on its own to forge a valid update. This is the mechanism `architecture.md` §7 names ("two-of-N signing or a transparency-log witness") and `architecture.md` §11 item 1 lists as an open decision on *who holds which key* — this document specifies the *mechanism* (now landed in code) and the custody-separation policy; it does not, and cannot, make the human custody assignment.

## 2. The two-of-N policy, as landed in code

- **N compiled-in roots.** `updater::multisig::TRUST_ROOTS_B64: [&str; 3]` — three minisign public keys, the same raw-base64 shape as M4's single `TRUST_ROOT_PUBLIC_KEY_B64`, compiled into the binary as literal `pub const` values. There is no function anywhere in this crate that reads a multisig trust root from a preference, environment variable, or file — the same "code, not config" guarantee M4's single root carries, extended to an array. Enforced by `updater::multisig`'s own fitness tests and `tests/fitness_m7_two_of_n_signing.rs`.
- **A k-of-N threshold.** `updater::multisig::THRESHOLD_K: usize = 2` — at least this many of the N roots must each independently produce a valid signature over the exact same manifest bytes. `THRESHOLD_K >= 2` is asserted **at compile time** (`const _: () = assert!(THRESHOLD_K >= 2, ...)`), not merely by test — a future edit that silently dropped the threshold to `1` (reverting to single-key trust) fails the **build**, never ships as a quiet regression.
- **Distinct-root accounting.** `updater::verify::verify_update_multisig` tracks *which root index* each supplied signature verified against, and de-duplicates by index before comparing against `THRESHOLD_K`. Two signature blobs that both verify against the **same** root count as **one**, not two — a duplicated, re-submitted, or replayed single custodian's signature can never masquerade as a second, independent approval. A garbage/malformed signature, or a structurally-valid signature from a key **outside** the compiled-in set (an attacker's own keypair), contributes nothing to the count.
- **Fail closed.** Fewer than `THRESHOLD_K` distinct valid signatures → `VerifyError::InsufficientSignatures { valid, required }`, refuse to stage. No `--force`/`--skip-verify` branch exists at any point in this path (`updater::multisig`'s and `updater::verify`'s own fitness scans grep-deny those spellings in production code).
- **Downgrade/hash checks unchanged.** Meeting the k-of-N threshold authenticates the manifest *bytes*; it does not exempt the manifest's declared version from M4's anti-replay downgrade rule (`attempted <= current` is still refused) or from the artifact-sha256 match. Both entrypoints (`verify_update`, `verify_update_multisig`) share the identical post-authentication logic (`updater::verify::after_authenticated`) — there is exactly one downgrade rule and one hash rule in this crate, regardless of which trust scheme authenticated the bytes.
- **Live transport is k-of-N.** The update-check/apply transport fetches signature siblings named `<manifest-url>.<root-id>.minisig` for every `TRUST_ROOT_SIGNATURE_IDS` entry and hands the collected signatures to `verify_update_multisig`. Missing optional root files count as zero signatures; a threshold-satisfying subset still accepts, and fewer than `THRESHOLD_K` distinct valid roots refuses. M4's single-root `verify_update` remains tested and available as a compatibility entrypoint, but it is not the live self-update path.

## 3. Custody separation — two different things, held by different parties

Per `architecture.md` §7, two credentials gate a shipped release, and they must never be held (or compromised) as a single unit:

1. **The Apple Developer ID codesigning certificate** — proves *this Team ID built the binary*. Lives in Apple's own signing/notarization chain, independent of minisign entirely.
2. **The minisign signing key(s)** — proves *this update manifest is the one the release process actually cut*, independent of the Apple chain. Under two-of-N, this custody **splits further still**: at least two independent parties (or an HSM/vault plus a separate human custodian) must each hold one key/share, so compromising a single custodian's material is insufficient to forge a valid release signature alone.

A single popped credential — a leaked Developer ID certificate, or one compromised minisign custodian's share — must never, on its own, grant the ability to ship a malicious *update*. The minisign gate is a second, separately-custodied check the watchdog verifies (via `verify_update`/`verify_update_multisig` + the offline notarization-staple check, `verify_staple`) before ever promoting a staged bundle, and two-of-N applies that same "no single point of failure" principle a second time, *within* the minisign gate itself.

**Practical custody guidance for whoever is assigned the real keys (not yet decided — see §5):**
- Generate each of the N production keypairs in a **fresh**, dedicated HSM/vault — never derive from, or reuse, the dev key checked into `updater::multisig`'s doc comment, and never generate in a location any single engineer's laptop could exfiltrate from.
- No two of the N roots may be held by the same person or the same single system/vault — that would silently collapse an "N-key" scheme back to fewer independent points of failure than N implies (the exact concern `updater::multisig::tests::the_n_trust_roots_are_pairwise_distinct` guards structurally for the *compiled-in literals*; the *custody* half of that same guarantee is a human/process decision this repo cannot enforce in code).
- The codesigning certificate and every minisign key share must be held in **separate** custodial systems from each other, so a single vault compromise cannot yield both halves of the release-signing chain at once.

## 4. Alternative considered: a transparency-log witness

`architecture.md` §7 names a transparency-log witness (an independent, append-only public log recording every release build's hash) as a live alternative to — or complement of — k-of-N key custody. Considered and **not (yet) chosen** as the sole mechanism:

- **What it would buy:** independent, publicly-auditable proof that a given release hash was logged before distribution, making a silently-forged release detectable after the fact even if an attacker fully compromises the signing key itself (a witness log doesn't require the *signing* key to be split — it adds a second, independent *detection* channel instead of splitting *authorization*).
- **Why it doesn't replace k-of-N here:** a transparency log is a **detection** control (you find out a bad release was logged, possibly after machines have already installed it) rather than a **prevention** control (k-of-N structurally prevents a single compromised key from producing a validly-signed manifest at all). Given this project's threat model rates minisign-key-compromise as the single highest-*damage* threat (fleet-wide RCE with a live `gh` token in scope), prevention was judged the higher-priority mechanism to land first.
- **Not mutually exclusive.** Nothing about `verify_update_multisig`'s design forecloses adding a transparency-log witness *alongside* k-of-N later (e.g., requiring both k valid signatures **and** a matching, independently-logged build-hash entry before promoting) — that would be a strictly additive check on top of the existing `after_authenticated` step, not a redesign. This is left as a future enhancement, not built in this milestone; `architecture.md` §11 item 1 keeps "k-of-N vs. transparency-log witness (or both)" open pending the real custody decision.

## 5. What's owner-gated (G-M7-4) — not this session's, or any code session's, to resolve

- **Who holds the second (and third) key.** A two-of-N scheme with an unassigned second custodian is, in practice, a one-of-one scheme with a placeholder (`threat-model.md` §5 item 1's exact framing) — assigning real people/systems to real key shares is a human decision.
- **Generating the real production keypair(s)** in fresh, dedicated custody (§3 above) — never reusing any dev key from this repo's fixtures.
- **Choosing k-of-N vs. a transparency-log witness (or both)** as the release process the org actually runs (§4).
- **Swapping `updater::multisig`'s compiled-in literals** for the real production keys before `stable`-channel self-update promotion is ever enabled in CI (`release-and-versioning.md` §2 step 3) — a mechanical edit once the custody decision above is made, not a design change; this document's and `updater::multisig`'s shape do not change. The live path is already cut over to `verify_update_multisig`; what remains owner-gated is real custody and real production root material.

Until all of the above is resolved, treat the two-of-N mitigation as **designed and code-complete, not yet operationally real** — exactly the caveat `threat-model.md` §5 item 1 already carries forward.

## 6. If a key is ever compromised

This document is about the *design* of custody, not incident response. If a minisign key is suspected compromised (dev or, eventually, production), follow [`incident-response.md`](incident-response.md) §1 — it covers generating replacement keys in fresh custody, the bootstrapping constraint (rotating a compiled-in trust root requires shipping a new signed release, not a config push), and signing that emergency release with every uncompromised custodian available, even exceeding the normal two-of-N minimum for that one release.

## 7. Cross-references

- [`../01-architecture/architecture.md`](../01-architecture/architecture.md) §7 (distribution/signing), §11 item 1 (the open custody decision).
- [`threat-model.md`](threat-model.md) §2.3 B4, §3, §5 item 1 — the full STRIDE/DREAD analysis this mechanism mitigates, and the explicit "not yet assigned" flag on the second key.
- [`incident-response.md`](incident-response.md) §1 — what to do if a minisign key is actually compromised.
- [`security-and-trust.md`](security-and-trust.md) — the broader trust-basis doc (compiled-in trust roots, cross-repo signing contract, STRIDE across self-update).
- [`../06-deployment/two-of-n-custody-runbook.md`](../06-deployment/two-of-n-custody-runbook.md) — the operator/standup-facing companion to this document.
- `src-tauri/src/updater/multisig.rs`, `src-tauri/src/updater/verify.rs` (`verify_update_multisig`), `src-tauri/tests/fitness_m7_two_of_n_signing.rs`, `src-tauri/fixtures/updater/README.md` — the actual landed code and its fixture corpus.
