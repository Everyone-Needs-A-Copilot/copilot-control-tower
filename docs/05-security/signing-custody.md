# Signing custody

Control Tower release candidates use Apple's Developer ID and notarization
chain. The release gate verifies the exact Team ID (`3SYGVX2HB8`), hardened
runtime, notarization acceptance, and stapled tickets. Narrative documentation
does not duplicate the certificate holder's personal name.

The publisher's signing identity and `ct-notary` profile live in macOS
Keychain. They are never committed, inherited, streamed through the outer Git
bootstrap, or accepted from the public repository. The outer compiled launcher
receives only a source ref and non-secret output intent. Signing/notarization
authority is loaded only by code compiled from and repeatedly verified against
the exact anonymously readable Git tree being released.

The independently built `cc` helper has its own checksum, Team ID, signature,
and notarization record. Control Tower verifies that artifact and embeds it
unchanged; it never re-signs the helper or treats the helper's publisher as a
second Control Tower release signer.

There is no in-app self-update mechanism or minisign/two-of-N update key in the
shipping native app. If self-update is introduced, its manifest trust and
custody model require a fresh architecture and security review rather than
reviving assumptions from the retired Tauri design.

See [`publisher-release-runbook.md`](../07-contributing/publisher-release-runbook.md)
and [`threat-model.md`](threat-model.md).
