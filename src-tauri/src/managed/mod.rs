//! M5/S1 — the consolidated, audited forced-domain boundary + frozen
//! managed-key registry (`.copilot/wp/30.md`, memory `m5-mdm-security-decisions`,
//! ADR-M5-001, invariant #4).
//!
//! ## Module home — a deliberate choice, not the default (WP §1)
//!
//! `settings::managed` already existed (M2/S5) before this milestone, and
//! its name is confusingly close to this one. They are NOT the same thing
//! and are not merged:
//!
//! - **`settings::managed`** (unchanged scope) owns the managed-vs-unmanaged
//!   **business decision** for Settings: `is_managed()` (with its own
//!   `CT_MANAGED_OVERRIDE` whole-machine dev override), `apply_gate()`
//!   (locks org/dept `LayerRow`s), `refuse_locked_writes()` (fail-closed
//!   write refusal). None of that is a forced-domain FFI concern per se —
//!   it's what Settings DOES once it knows the answer.
//! - **`crate::managed`** (this module, NEW) owns the forced-domain FFI
//!   **mechanism** itself: the one place `CFPreferencesAppValueIsForced`/
//!   `CFPreferencesCopyAppValue` are ever called ([`forced`]), and the
//!   frozen registry of every key name this app knows about ([`keys`]).
//!
//! `settings::managed::key_is_forced` now delegates to
//! [`forced::key_is_forced`] instead of carrying its own FFI call; so does
//! `updater::trust`'s equivalent. This module is a new **top-level** crate
//! module (`crate::managed`, i.e. `src-tauri/src/managed/`) rather than
//! nested inside `settings::` — putting the crate's single most
//! security-critical FFI boundary one level away from any one feature
//! module (Settings) makes it visibly a cross-cutting concern every stream
//! (M2's Settings, M4's updater, and M5's own S3/S5/S6) depends on, not
//! something that looks like it's "owned by" whichever feature happened to
//! need it first. This also matches the file layout `.copilot/wp/30.md`
//! itself specifies (`src-tauri/src/managed/{mod,forced,keys}.rs`).
//!
//! ## What lives here
//!
//! - [`forced`] — the sole `CFPreferences` FFI boundary: `key_is_forced`,
//!   `forced_string`, `forced_bool`, and the `resolve_string`/`resolve_bool`
//!   folds that apply a compiled-in default and audit an ignored
//!   user-domain value. See that module's doc for the full three-way
//!   decision (`ForcedLookup`) and the dev-mockable override seam.
//! - [`keys`] — the FROZEN registry of every managed/forced key name this
//!   app's Rust code knows about, plus the one authoritative bundle-domain
//!   constant ([`keys::APPLICATION_ID`]). This is the single source of
//!   truth the S4 `.mobileconfig` generator and every reader (this module,
//!   `settings::managed`, `updater::trust`, and S3/S5/S6's future readers)
//!   share — generator and reader can never disagree on a key name because
//!   there is exactly one list.
//!
//! If you are adding a new managed/forced key: add it to
//! [`keys::MANAGED_KEYS`] first (with evidence for its
//! `security_sensitive`/`forced_only` classification, per that module's doc)
//! — never hand-spell a new key name directly at a `forced::forced_string`/
//! `forced::forced_bool` call site.

pub mod forced;
pub mod keys;
pub mod secret_store;
