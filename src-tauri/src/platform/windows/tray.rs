//! Windows `platform::tray_art` surface — M9/Stream-F (task 75, `uid`),
//! `.copilot/wp/52.md` ADR-M9-001, memory `m9-windows-reskin-decisions`,
//! `docs/01-architecture/windows-parity.md` §1 row 6.
//!
//! ## The gap this fills (why Windows needs its own file at all)
//!
//! `NSStatusItem` template images give macOS automatic OS re-tinting for
//! free (`icon_as_template`/`set_icon_with_as_template` — see
//! `render::glyph`'s and `tray.rs`'s own doc comments). Windows notification-
//! area icons have **no** such auto-recolor: whatever RGBA bytes this module
//! hands `TrayIcon::set_icon` are painted verbatim, on whatever taskbar
//! background the user happens to have. A pure-black silhouette (what
//! `render::glyph::composite` always paints — see below) is invisible on a
//! dark taskbar. That is the entire, sole Windows-specific problem this file
//! solves: **which RGB tint to paint**, chosen from the live system theme.
//!
//! ## Invariant #1 — reuse, don't fork, the state->badge table
//!
//! `render::glyph` is a plain, cross-platform Rust module (no macOS-only
//! API — it draws into a `tauri::image::Image` RGBA buffer using only
//! arithmetic) already compiled unconditionally (`render/mod.rs`'s
//! `pub mod glyph;` carries no `cfg` at all). Its `pub fn composite` is
//! therefore reusable here **verbatim** — this file calls it directly rather
//! than re-declaring `treatment_for`'s state->badge lookup table, the
//! `BaseTreatment`/`BadgeShape` enums, or any of the pixel-drawing helpers.
//! There is exactly one place in this crate that decides "given this
//! CLI-derived `glyph_state` token, what shape does the tray icon draw" —
//! `render::glyph::treatment_for` — and this module never re-derives or
//! re-ranks that decision; it only recolors the RGB channel of the already-
//! finished pixels `render::glyph::composite` produced. The theme choice
//! below is an **asset/color selection**, never a second status computation
//! (parse-never-compute, invariant #1 of `CLAUDE.md`, holds identically
//! here).
//!
//! ## Why no new build-time asset generation (deliberately, not an oversight)
//!
//! `build.rs`'s `rasterize_tray_glyph` already rasterizes the real aviator
//! brand mark (`icons/aviators.svg`) into build-time alpha-only masks
//! (`AVIATOR_SOLID`/`AVIATOR_HOLLOW`) that `render::glyph::composite` embeds
//! and composites at runtime — see that module's doc. Because
//! `render::glyph::composite` is reusable as-is (previous section), producing
//! a Windows "light" and "dark" variant needs no second SVG rasterization
//! pass, no new `.ico`/`.png` asset files under `icons/`, and no `build.rs`
//! edit: both variants are the exact same alpha-shaped pixels, differing only
//! in the RGB tint painted under that alpha, which is cheap to compute once
//! per poll at runtime (`recolor_for_theme`, below) from the one shared mask
//! both platforms already embed. This keeps the `resvg`/`usvg`/`tiny-skia`
//! stack a **build-dependency only** (never touched by Windows code) exactly
//! as `render::glyph`'s own doc already requires for macOS, and it means
//! Stream-F never has to touch `build.rs` at all — leaving that file, and its
//! single-owner note for this exact stream, untouched.
//!
//! Tauri's tray-icon API itself needs no literal `.ico` file either: the
//! cross-platform `tauri::image::Image` raw-RGBA-buffer type this module
//! returns is the SAME type `TrayIconBuilder`/`TrayIcon::set_icon` accept on
//! every OS (parity doc row 6 calls this out as the one row the framework
//! already abstracts) — Windows resolves an `Image` to its own native `HICON`
//! internally. "Explicit light/dark ICO variants" (the task's framing) is
//! therefore implemented here as two recolored in-memory rasters, not two
//! packaged `.ico` files on disk.
//!
//! ## Theme detection + live theme-change
//!
//! The system apps theme is read from
//! `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`'s
//! `AppsUseLightTheme` DWORD (`0` = dark, non-zero = light — the same value
//! Windows itself uses to decide whether to tint its OWN chrome dark or
//! light). This module does not install a `WM_SETTINGCHANGE` listener (that
//! needs a live Windows message loop this machine cannot construct or test);
//! instead, per `platform::tray_art`'s existing contract, `composite` is
//! called fresh on every status poll (`tray::update`, driven by
//! `timer::poll_once`), so a theme change is picked up on the next poll
//! without any dedicated event hook — "react to theme-change" is satisfied
//! by re-reading the registry each call, not by caching the theme at
//! startup. A genuinely instant (sub-poll-interval) repaint on theme change
//! would need that message-loop hook; that responsiveness gap is real and
//! owner-gated (needs a live Windows desktop to build/verify), not silently
//! claimed here.
//!
//! ## Owner-gated (be honest)
//!
//! Nothing below has ever been compiled or run — there is no Windows
//! toolchain on this machine. `winreg`'s registry-read shape is authored
//! against its documented API; the exact `AppsUseLightTheme` semantics,
//! whether it exists on every supported Windows 10/11 build, and whether the
//! poll-driven repaint reads as "live enough" in the overflow tray, are
//! owner-gated to a real Windows box per ADR-M9-005/006 and
//! `docs/06-deployment/m9-owner-gated-split.md`.

#![cfg(windows)]

use tauri::image::Image;
use winreg::enums::HKEY_CURRENT_USER;
use winreg::RegKey;

/// Registry location Windows itself uses for the system light/dark apps
/// theme — the same key Explorer/the taskbar reads to decide its own chrome
/// color, so relying on it (rather than inventing a private heuristic) keeps
/// this icon's contrast honestly in sync with what the user actually sees
/// their own taskbar do.
const PERSONALIZE_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
const APPS_USE_LIGHT_THEME_VALUE: &str = "AppsUseLightTheme";

/// The two tray-icon tints this module ever selects between. Deliberately
/// NOT named/shaped anything like `render::glyph`'s `BaseTreatment` —
/// that enum governs the GLYPH'S OWN shape (solid/hollow/dimmed), a decision
/// this module never touches; `WindowsTheme` only ever governs which flat RGB
/// color is painted under whatever alpha shape `render::glyph::composite`
/// already produced.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WindowsTheme {
    /// Light system theme -> light taskbar background -> paint the glyph
    /// dark, matching the RGB `render::glyph`'s masks already paint by
    /// default.
    Light,
    /// Dark system theme -> dark taskbar background -> the identical shape
    /// must be repainted light, or it reads as invisible.
    Dark,
}

impl WindowsTheme {
    /// Reads `AppsUseLightTheme`, failing closed to [`WindowsTheme::Light`]
    /// (the RGB `render::glyph::composite`'s masks already paint verbatim,
    /// so an unreadable registry reproduces the exact bytes the proven
    /// macOS build already ships, never a guessed-at color) on any read
    /// failure — a missing key, a missing value, or a value of an
    /// unexpected type must never panic the tray-update poll loop.
    fn detect() -> Self {
        RegKey::predef(HKEY_CURRENT_USER)
            .open_subkey(PERSONALIZE_KEY)
            .and_then(|key| key.get_value::<u32, _>(APPS_USE_LIGHT_THEME_VALUE))
            .map(|value| {
                if value == 0 {
                    WindowsTheme::Dark
                } else {
                    WindowsTheme::Light
                }
            })
            .unwrap_or(WindowsTheme::Light)
    }

    /// The flat RGB tint painted under the shared alpha shape for this
    /// theme. Only ever these two literal colors — no gradient, no
    /// accent-color sampling — both grayscale-legible, matching
    /// `render::glyph`'s own "grayscale-safe, shape is the only encoder"
    /// rule for the badges baked into that shape.
    fn rgb(self) -> (u8, u8, u8) {
        match self {
            WindowsTheme::Light => (0, 0, 0),
            WindowsTheme::Dark => (255, 255, 255),
        }
    }
}

/// The `platform::tray_art` seam's Windows implementation — see
/// `platform::mod`'s doc for why this must keep the EXACT
/// `fn(glyph_state: &str) -> Image<'static>` shape the macOS alias
/// (`render::glyph::composite`) exposes, so `tray.rs`'s call site never
/// needs a `#[cfg]` of its own.
///
/// Reuses `render::glyph::composite` verbatim for the shape (the SAME
/// `treatment_for` state->badge table macOS uses — see this module's own
/// doc for why that is never re-declared here), then recolors only the RGB
/// channel per the live system theme. No status is computed in this
/// function; `glyph_state` is an already-decided token, exactly as on
/// macOS.
pub fn composite(glyph_state: &str) -> Image<'static> {
    let shape = crate::render::glyph::composite(glyph_state);
    recolor_for_theme(shape, WindowsTheme::detect())
}

/// Rewrites every pixel's RGB channel to `theme`'s flat tint, leaving alpha
/// (the glyph/badge SHAPE `render::glyph::composite` already baked in from
/// the shared state->badge table) untouched byte-for-byte. Walks every pixel
/// unconditionally for both theme arms — rather than special-casing `Light`
/// as a byte-identical no-op against `render::glyph`'s always-black masks —
/// so there is exactly one recolor code path to reason about, not one path
/// plus a "trust it's already black" assumption that a future change to the
/// shared masks could silently invalidate.
fn recolor_for_theme(image: Image<'static>, theme: WindowsTheme) -> Image<'static> {
    let width = image.width();
    let height = image.height();
    let (r, g, b) = theme.rgb();
    let mut buf = image.rgba().to_vec();
    for pixel in buf.chunks_exact_mut(4) {
        pixel[0] = r;
        pixel[1] = g;
        pixel[2] = b;
        // pixel[3] (alpha) intentionally left untouched — it is the shape,
        // never recomputed here.
    }
    Image::new_owned(buf, width, height)
}
