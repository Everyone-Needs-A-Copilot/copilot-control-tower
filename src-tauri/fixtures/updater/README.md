# M4/S1-S2 update-verification fixture corpus

Drives `updater::verify`'s fail-closed adversarial test matrix and
`updater::verify::verify_staple`'s offline Gatekeeper check without a real
signing/notarization ceremony (owner-gated — see `updater::trust`'s doc on
`TRUST_ROOT_PUBLIC_KEY_B64`). Referenced by `.copilot/wp/24.md` (M4-S1/S2) and
consumed by `src-tauri/src/updater/verify.rs`'s `#[cfg(test)]` suite.

## The dev keypair

The trust root compiled into `updater::trust::TRUST_ROOT_PUBLIC_KEY_B64` is:

```
RWTTB+DjHKSykfKOoWjbRLhHyzDyFlNvg5sByAbQf4xT9i64yyr7/QLY
```

This is a **dev-only minisign keypair**, generated for this milestone purely
so the fail-closed verification path is exercisable by `cargo test`. The
corresponding secret key is **not** committed anywhere in this repo — only
the fixtures it signed are. A second, throwaway "attacker" keypair was
generated the same way, used exactly once (to produce
`valid-manifest.json.wrongkey.minisig`), and then discarded; its public key
is not recorded anywhere and is not needed to regenerate anything below.

**Release migration:** replace `TRUST_ROOT_PUBLIC_KEY_B64` with the real,
two-of-N-custodied production key before enabling `stable` channel promotion
in CI (owner-gated, tracked in `architecture.md` §11 item 1 /
`threat-model.md` §2.3 B4) — this fixture corpus and its dev key are
unaffected by that migration; they exist purely to test the *verifier*, not
to ship as production trust material.

## Regenerating the corpus

Uses the `minisign` crate (full sign+verify — **not** a dependency of this
crate; `Cargo.toml` only takes the verify-only `minisign-verify`) in a
one-off scratch Cargo project, never committed:

```bash
# 1. Scratch project with the full `minisign` crate as its only dependency.
cargo new --bin /tmp/ct-keygen && cd /tmp/ct-keygen
cargo add minisign

# 2. Generate the dev keypair (see `src/main.rs` below) and print its
#    public key base64 (the exact 42-byte-decoded shape
#    `minisign_verify::PublicKey::from_base64` expects — NOT the two-line
#    `minisign.pub` file format).
cargo run -- genkey > dev_key.txt   # PUB_B64=... / SK_HEX=...

# 3. Sign each manifest fixture with the dev secret key.
cargo run -- sign dev_sk.hex valid-manifest.json "controltower-update-manifest:9.9.9" \
  > valid-manifest.json.minisig
cargo run -- sign dev_sk.hex downgrade-manifest.json "controltower-update-manifest:0.0.1" \
  > downgrade-manifest.json.minisig

# 4. Sign the SAME valid-manifest.json bytes with a SEPARATE, one-off
#    "attacker" keypair to produce the wrong-key fixture.
cargo run -- genkey > attacker_key.txt
cargo run -- sign attacker_sk.hex valid-manifest.json "controltower-update-manifest:9.9.9" \
  > valid-manifest.json.wrongkey.minisig
```

`src/main.rs` for the scratch project only needs three tiny subcommands
(`genkey` — `minisign::KeyPair::generate_unencrypted_keypair()`; `sign` —
`minisign::sign(None, &sk, data, Some(trusted_comment), None)`; nothing else
— verification of the freshly-produced fixtures is done by this crate's own
`cargo test`, not by the scratch project).

If `TRUST_ROOT_PUBLIC_KEY_B64` in `updater/trust.rs` is ever rotated (dev key
replaced by a new dev key — the real production key rotation is a separate,
owner-gated event per the module doc), every `.minisig` file below except
`valid-manifest.json.wrongkey.minisig` must be re-signed with the new key,
and `valid-manifest.json.wrongkey.minisig` must be re-signed with a
still-different one-off key. `garbage.minisig`/`missing.minisig` never need
regeneration — they're deliberately not real signatures.

## Layout

| File | What it is |
|---|---|
| `artifact.bin` | A small stand-in for a downloaded update bundle's bytes. |
| `corrupted-artifact.bin` | Different bytes than `artifact.bin` — its sha256 does NOT match any manifest below; used for the artifact-hash-mismatch case. |
| `valid-manifest.json` | `app_version: "9.9.9"`, `channel: "stable"`, `artifact_sha256` = sha256 of `artifact.bin`. |
| `valid-manifest.json.minisig` | The dev key's real minisign signature over `valid-manifest.json`'s exact bytes. |
| `valid-manifest.json.wrongkey.minisig` | A structurally-valid minisign signature over the SAME `valid-manifest.json` bytes, but from a different (one-off "attacker") key — must fail `SignatureMismatch` against the compiled-in trust root. |
| `tampered-manifest.json` | Byte-identical to `valid-manifest.json` except `artifact_sha256` points at `corrupted-artifact.bin` instead — paired with `valid-manifest.json.minisig` (the ORIGINAL signature) in the tampered-manifest test, proving the whole manifest is authenticated, not just a "signature field". |
| `downgrade-manifest.json` | `app_version: "0.0.1"`, validly signed — used to prove a validly-signed but non-newer manifest is still refused. |
| `downgrade-manifest.json.minisig` | The dev key's real signature over `downgrade-manifest.json`. |
| `garbage.minisig` | Not a minisign signature at all (arbitrary text) — the "malformed signature" case. |
| `missing.minisig` | An empty file — the "no signature supplied" case. |
| `staple/UnsignedApp.app/` | A fake `.app` bundle (no real code signature at all) for `verify_staple`'s fail-closed test — exercised against the REAL system `/usr/sbin/spctl`, not a mock; see `verify_staple`'s own doc for exactly what this can and can't prove without a real Developer ID. |

## What this corpus deliberately does NOT contain

A fixture that makes `verify_staple` return `Ok(())` — that requires a real
Apple Developer ID certificate and a real notarization round-trip, which is
this task's explicitly owner-gated, batched-for-release item (see
`updater::trust`'s and `updater::verify::verify_staple`'s doc comments). Every
fixture here exercises the **fail-closed** side of both `verify_update` and
`verify_staple`, which is the entire point of this milestone: a bad or
unsigned update must be structurally un-stageable, proven by tests that
never need the production key or a real signing ceremony to run.
