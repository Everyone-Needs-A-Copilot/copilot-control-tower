# M5/S4 `.mobileconfig` golden fixture

The golden output of `mobileconfig::generator::generate` for a fictional org
("Acme Corp"), used by `tests/fitness_m5_generator_domain_and_no_secrets.rs`'s
drift check and (FF-M5-6/FF-M5-7) domain/no-secret fitness assertions.
Referenced by `.copilot/wp/30.md` (M5/S4).

## Regenerating

Never hand-edit `sample-acme-corp.mobileconfig` — it (and the identical copy
at `packaging/mobileconfig/sample-acme-corp.mobileconfig`, the "ready to
upload" deliverable IT would actually download) are produced by the same
generator `cargo test` exercises:

```bash
cargo run --example gen_mobileconfig_fixture
```

`tests/fitness_m5_generator_domain_and_no_secrets.rs`'s
`golden_fixture_matches_what_the_real_generator_produces_right_now` and
`packaging_deliverable_is_byte_identical_to_the_test_fixture` fail CI if
either copy has drifted from what the generator produces right now, or from
each other.

## Validating the plist shape

`cargo test` cannot shell out to a macOS-only binary, so the authoritative
XML-plist-well-formedness check is a separate, manual step (also run once
per S4 delivery, see the S4 summary):

```bash
plutil -lint src-tauri/fixtures/mobileconfig/sample-acme-corp.mobileconfig
plutil -lint packaging/mobileconfig/sample-acme-corp.mobileconfig
```

Both must print `OK`. `cargo test`'s own
`golden_fixture_is_well_formed_xml_with_a_plist_root` is the cheap,
dependency-free, portable stand-in that runs on every `cargo test` (tag
balance + `<plist>`/`</plist>` wrapper) — not a substitute for the real
`plutil -lint` pass.

## What the sample org sets (and deliberately leaves unset)

`examples/gen_mobileconfig_fixture.rs`'s `sample_inputs()` sets 16 of the 17
[`managed::keys::MANAGED_KEYS`](../../src/managed/keys.rs) entries —
`HTTPSProxy` is deliberately left unset (an org with no forced proxy is a
real, valid configuration) to exercise the "a key with no supplied value is
simply omitted, never emitted as an empty placeholder" path
(`missing_keys`/the "absent from output" fitness test).

Every string value in the sample is a plausible **endpoint/reference/flag**
(a mirror URL, an admin contact email, a secret-store endpoint reference) —
**never** a credential. `mobileconfig::generator::generate` itself refuses
to emit any value [`looks_like_a_secret`](../../src/mobileconfig/generator.rs)
flags (FF-M5-7); this fixture's job is to prove that refusal never trips on
an *ordinary* config value, not to hold a real secret to prove it gets
rejected (see `generator.rs`'s own `#[cfg(test)]` suite for the
rejection-path tests, which use inline decoy values, never anything
checked into this directory).
