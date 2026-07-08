//! Rendering (T5/T6) — presentation only, never a new verdict.
//!
//! - `derive` — maps CLI `status` -> `StatusState` (a lookup, not a
//!   computation) and buckets `checkers[]` by `(product, layer)` for the
//!   popover's product-first display. Bucketing is a `group_by`, never a
//!   roll-up into a new 10-state status — that line is ADR-M1-002.
//! - `glyph` — `StatusState` -> tray template image + composited badge. Per
//!   the D-4 finding (`tray.rs`), Tauri's tray API has no overlay/badge
//!   primitive, so this module owns compositing the badge into the icon's
//!   pixel buffer before it's handed to `TrayIcon::set_icon`.
//!
//! Fitness function this module must keep true (per the architecture WP):
//! no arithmetic on `score`, no severity->status synthesis anywhere in this
//! module or `model/`.

// M6/S6 (task 57, `.copilot/wp/37.md`): the Bob-lane DTO + its Tauri-managed
// aggregation — backs uid's (S5) `get_bob_lane` IPC command. See that
// module's own doc for why the router wiring lives here rather than in
// `commands.rs`.
pub mod bob_lane;
pub mod derive;
pub mod glyph;
pub mod security_banner;

/// THE canonical badge-SHAPE vocabulary (T8 — reconciling the T3/T7
/// contract). Every string this crate can ever put in `RenderState.header
/// .glyph_state` or a `LayerView`/`ProductView`'s `badge_state` lives here,
/// and nothing outside this list is a legal value on that wire:
///
/// - the 10 tokens `model::state::CliStatus::glyph_badge()` produces
///   (`"none"`/`"hollow"`/`"wrench"`/`"key"`/`"triangle"`/`"cloud-slash"`/
///   `"clock"`/`"ring"`/`"update"`/`"spinner"`),
/// - `"bang"` — `render::derive::render_unreadable`'s CLI-unreadable glyph,
///   and `render::derive::severity_badge`'s `Severity::Fail` mapping,
/// - `"pass"` — `render::derive::severity_badge`'s `Severity::Pass` mapping
///   (layer/product buckets only; the header glyph is never `"pass"` —
///   Healthy renders as the plain `"none"` mark instead, ADR-M1-001's
///   "silence is the success state").
///
/// This is the SAME 12-token union `src/types.ts`'s `BadgeState` declares
/// and `src/render/badges.ts`'s `drawShape` switch draws a mark for, and the
/// same set `render::glyph::treatment_for` maps to a tray composite (its
/// `_ => Bang` arm is the fail-closed catch-all for anything NOT in this
/// list, so an orphaned/renamed token here still renders loud, never
/// quietly Healthy). `tests/fitness_badge_vocabulary.rs` is the
/// cross-language check that keeps all four in sync.
pub const BADGE_VOCABULARY: [&str; 12] = [
    "pass",
    "ring",
    "key",
    "update",
    "triangle",
    "wrench",
    "clock",
    "cloud-slash",
    "bang",
    "spinner",
    "hollow",
    "none",
];
