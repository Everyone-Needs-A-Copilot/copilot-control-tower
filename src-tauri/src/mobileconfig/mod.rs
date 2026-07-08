//! Admin-mode `.mobileconfig` generator (M5/S4, `.copilot/wp/30.md`,
//! `architecture.md` §8.1 item 4: "MDM profile generator — the high-leverage
//! piece: emits a ready-to-upload `.mobileconfig`... so IT uploads one
//! artifact to Jamf/Kandji/Intune and every employee's wizard runs silent").
//!
//! See [`generator`] for the actual XML builder. This module's own job is
//! small and deliberate: [`generator::generator_domain`] MUST equal
//! [`crate::managed::keys::APPLICATION_ID`] — the exact domain
//! [`crate::managed::forced`] (S1's sole forced-domain FFI boundary) reads
//! from. Before this stream, the closest thing to a written-down domain was
//! `architecture.md`'s own prose, which says `dev.enac.controltower` — a
//! **documentation** value the shipped reader has never once read from (see
//! `managed::keys`'s own doc, G-M5-1). If this generator had picked that
//! doc value instead of the code-authoritative constant, every
//! `.mobileconfig` it produced would silently write to a domain macOS never
//! looks at — the generator and the reader would each be internally
//! consistent and mutually, catastrophically wrong.
//! `tests/fitness_m5_generator_domain_and_no_secrets.rs` (FF-M5-6) is the
//! standing, regression-proof guard against that ever happening again.
//!
//! Real MDM upload/enrollment is owner-gated (this module only builds the
//! artifact; pushing it to Jamf/Kandji/Intune is an IT action outside this
//! crate entirely) — see `packaging/mobileconfig/` for a checked-in sample
//! artifact and `src-tauri/fixtures/mobileconfig/` for the golden fixture
//! this module's own drift test compares against.

pub mod generator;
