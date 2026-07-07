//! Settings (M2): the layer-manifest model + validator + never-destroy
//! writer + secret/security guard + authoring policy + managed gate + the
//! Settings IPC DTOs. See `.copilot/wp/5.md` for the full task breakdown.
//!
//! - `manifest.rs` (S1) — a serde model of `copilot.layers.yml` that
//!   round-trips faithfully (parses an existing manifest, re-emits it
//!   without losing unknown/optional fields).
//! - `validate.rs` (S1) — a validator mirroring the real consumer/authority,
//!   `claude-copilot/tools/cc/src/cc/core/ecosystem/manifest.py`'s
//!   `validate_layers`, with plain-language errors (never raw yaml/serde/git
//!   text — SOUL "a Git error to a non-technical person").
//! - `dto.rs` (S1) — the `SettingsState` / `LayerRow` / `FieldError` /
//!   `LayerInput` IPC contract shape `commands.rs` (S6) and the web UI (S7)
//!   build against.
//! - `writer.rs` (S2) — the atomic, backed-up, never-destroy manifest
//!   writer (`write_manifest`), and `default_manifest_path()` (D-3-M2).
//! - `config_pointer.rs` (S2) — sets the `layers.manifest` pointer by
//!   shelling to `cc config set` (D-5-M2), through the same dev-mockable
//!   `CT_CLI_PATH` seam `cli::path` uses.
//! - `guard.rs` (S3) — the fail-closed pre-write secret scanner +
//!   security-key write allowlist (invariants #4 and #6, the SOUL
//!   Convenience-Backdoor anti-pattern).
//! - `authoring.rs` (S4, decision-gated on D-1-M2's fallback path) —
//!   assembles a full valid `Layer` from a user-submitted `LayerInput`
//!   (deciding `id`/`rank`/`role`/`auth`/`activation` from the fixed
//!   published tier table — never user-entered, never a resolution
//!   computation), wiring S3's guard and S1's validator in before ever
//!   returning success.
//! - `managed.rs` (S5) — the managed/unmanaged gate (forced-domain
//!   detection via `CFPreferencesAppValueIsForced`, invariant #4) and the
//!   `LayerRow.editable` projection it drives.
//! - `commands.rs` (S6, crate root, not this module) — the actual
//!   `get_settings`/`save_settings`/`open_settings_window` Tauri commands
//!   that wire all of the above together: author -> guard -> write ->
//!   pointer -> re-poll.
//!
//! Parse-never-compute (invariant #1) applies throughout: this module models,
//! validates, and persists config the user (or a hand-authored file)
//! supplies; it never resolves, syncs, merges, or computes ecosystem state.
//! The `rank`/`role`/`auth` a fresh layer gets in `authoring.rs` are a
//! PUBLISHED, FIXED table emitted as data, not a computed precedence — the
//! `cc` resolver remains the only thing that ever *acts* on rank. The `cc`
//! CLI's `validate_layers` remains the final fail-closed authority — this
//! crate's validator is a client-side pre-check only, and is written to
//! match it exactly rather than being stricter or looser.

pub mod authoring;
pub mod config_pointer;
pub mod dto;
pub mod guard;
pub mod managed;
pub mod manifest;
pub mod validate;
pub mod writer;
