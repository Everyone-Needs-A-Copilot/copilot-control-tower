//! `StatusState` -> tray template image + badge overlay (T6). RENDER only.
//!
//! Per the D-4 finding (see `tray.rs`), Tauri 2.11.5's tray API supports
//! template images natively (`icon_as_template`) but has **no** badge/overlay
//! compositing primitive — `set_icon` always replaces the whole image. This
//! module is therefore responsible for producing one final composited
//! `tauri::image::Image` per `(StatusState, badge shape)` pair, with the
//! aviator mask and badge shape baked into the same pixel buffer ahead of
//! time. `tray.rs` then hands that finished image straight to `set_icon` /
//! `icon_as_template`; there is no draw-time overlay to ask the OS for.
//!
//! ## Brand art (real asset, rasterized at build time)
//!
//! The base silhouette is the owner's real brand mark —
//! `src-tauri/icons/aviators.svg`, an aviator-sunglasses silhouette —
//! rasterized once at **build time** (see `build.rs`'s `rasterize_tray_glyph`)
//! into two alpha-only pixel masks (`AVIATOR_SOLID`, `AVIATOR_HOLLOW`) that
//! this module embeds via `include_bytes!` and composites entirely as an
//! alpha-channel silhouette (RGB is always pure black, per the macOS
//! template-image contract — only alpha carries shape). Rasterizing at build
//! time rather than at runtime keeps the `resvg`/`usvg`/`tiny-skia` SVG
//! stack a build-dependency only — it never ships in the app binary. The
//! `treatment_for` mapping table below (state -> base treatment + badge
//! shape) is unrelated art-direction and was untouched by this swap.
//!
//! ## Badge shapes (grayscale-safe — shape is the only encoder here)
//!
//! Reuses `RenderState::header::glyph_state` (`CliStatus::glyph_badge()` /
//! `render::derive`'s `"bang"` for `CliUnreadable`) — the same 11-token
//! `BadgeState` vocabulary `src/types.ts` and (in T7) `src/render/badges.ts`
//! render in the popover. This module does not invent a second mapping; see
//! `treatment_for` for the exact table, transcribed from
//! `docs/product-design/04-experience-design/60-ui-design.md` § "The
//! Status-Glyph Family".

use tauri::image::Image;

/// Canvas size in pixels. 44 = a retina (@2x) rendering of the classic 22pt
/// macOS menu-bar glyph — supplied as a single higher-resolution bitmap since
/// `tauri::image::Image` carries only one raster (no separate @1x/@2x
/// representations); the OS scales it to fit the menu-bar's actual point
/// size. Kept as one named constant so every drawing helper below shares it.
pub const GLYPH_SIZE: u32 = 44;

/// The real aviator-sunglasses brand mark's filled silhouette, rasterized at
/// build time from `icons/aviators.svg` (see `build.rs`'s
/// `rasterize_tray_glyph`) into a `GLYPH_SIZE * GLYPH_SIZE` alpha-only mask
/// (one byte per pixel, row-major). Used directly by `BaseTreatment::Solid`
/// and scaled down by `BaseTreatment::Dimmed`.
const AVIATOR_SOLID: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/aviator_solid.bin"));

/// The same brand mark, reduced at build time to an outline-only band
/// straddling its edge (see `build.rs`'s `outline_from_mask`). Used by
/// `BaseTreatment::Hollow`.
const AVIATOR_HOLLOW: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/aviator_hollow.bin"));

const _: () = assert!(AVIATOR_SOLID.len() == (GLYPH_SIZE * GLYPH_SIZE) as usize);
const _: () = assert!(AVIATOR_HOLLOW.len() == (GLYPH_SIZE * GLYPH_SIZE) as usize);

/// How the aviator base silhouette itself is drawn for a given state, per
/// 60-ui-design.md's "Base treatment" column.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BaseTreatment {
    /// Fully opaque silhouette — the default for every state except the two
    /// below.
    Solid,
    /// Hollow outline only, no fill — Setup-needed's "invitation, not
    /// error" treatment (its slow-pulse animation is a popover/T7 concern;
    /// the tray glyph itself is a static hollow outline).
    Hollow,
    /// Reduced-alpha fill — Offline / Waiting-for-network's "dimmed overlay"
    /// treatment ("transient, restores the prior state underneath").
    Dimmed,
}

/// The badge shape composited into the lower-trailing corner, per
/// 60-ui-design.md's "Badge shape" column. `None` = no badge at all
/// (Healthy, Setup-needed — the base treatment alone carries the state).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum BadgeShape {
    None,
    Wrench,
    Key,
    Triangle,
    CloudSlash,
    Clock,
    Ring,
    Dot,
    Spinner,
    Bang,
}

/// `RenderState.header.glyph_state` -> (base treatment, badge shape). A pure
/// lookup table transcribed from 60-ui-design.md's Status-Glyph Family table
/// — reuses the SAME `glyph_badge()` tokens `model::state::CliStatus` and
/// `render::derive` already produced (see `CliStatus::glyph_badge` and
/// `render::derive::render_unreadable`'s `"bang"`); this function does not
/// re-derive or re-rank anything, it only decides how to DRAW a token that
/// was already decided upstream.
///
/// An unrecognized token (should never happen — the 11 values below are
/// exhaustive over `CliStatus::glyph_badge()` + `CliUnreadableReason`'s
/// `"bang"`) fails closed to the loudest, most-legible mark (`Bang`) rather
/// than silently falling back to the quiet Healthy mark — the tray must
/// never render a false-Healthy, even on a token bug.
fn treatment_for(glyph_state: &str) -> (BaseTreatment, BadgeShape) {
    match glyph_state {
        "none" => (BaseTreatment::Solid, BadgeShape::None), // Healthy
        "hollow" => (BaseTreatment::Hollow, BadgeShape::None), // Setup-needed
        "wrench" => (BaseTreatment::Solid, BadgeShape::Wrench), // IT-config-incomplete
        "key" => (BaseTreatment::Solid, BadgeShape::Key),   // Signed-out
        "triangle" => (BaseTreatment::Solid, BadgeShape::Triangle), // Needs-attention
        "cloud-slash" => (BaseTreatment::Dimmed, BadgeShape::CloudSlash), // Offline
        "clock" => (BaseTreatment::Dimmed, BadgeShape::Clock), // Waiting-for-network
        "ring" => (BaseTreatment::Solid, BadgeShape::Ring), // Syncing
        "update" => (BaseTreatment::Solid, BadgeShape::Dot), // Update-available
        "spinner" => (BaseTreatment::Solid, BadgeShape::Spinner), // Updating-app
        // "bang" (CLI-unreadable/Error) and any unrecognized token both land
        // here — see the fail-closed note above.
        _ => (BaseTreatment::Solid, BadgeShape::Bang),
    }
}

/// The T5/T6 entry point: `RenderState.header.glyph_state` -> a finished,
/// composited template image ready for `TrayIcon::set_icon_with_as_template`.
pub fn composite(glyph_state: &str) -> Image<'static> {
    let (base, badge) = treatment_for(glyph_state);
    let mut buf = vec![0u8; (GLYPH_SIZE * GLYPH_SIZE * 4) as usize];
    draw_base(&mut buf, base);
    draw_badge(&mut buf, badge);
    Image::new_owned(buf, GLYPH_SIZE, GLYPH_SIZE)
}

// ---------------------------------------------------------------------------
// Pixel-level drawing primitives. Template images are pure alpha-channel
// silhouettes (RGB is always black — the OS re-tints for light/dark), so
// every helper below only ever writes `alpha`; there is no color blending.
// ---------------------------------------------------------------------------

fn set_px(buf: &mut [u8], x: i32, y: i32, alpha: u8) {
    if x < 0 || y < 0 || x >= GLYPH_SIZE as i32 || y >= GLYPH_SIZE as i32 {
        return;
    }
    let i = ((y as u32 * GLYPH_SIZE + x as u32) * 4) as usize;
    buf[i] = 0;
    buf[i + 1] = 0;
    buf[i + 2] = 0;
    buf[i + 3] = alpha;
}

fn fill_circle(buf: &mut [u8], cx: f32, cy: f32, r: f32, alpha: u8) {
    let x0 = (cx - r).floor() as i32 - 1;
    let x1 = (cx + r).ceil() as i32 + 1;
    let y0 = (cy - r).floor() as i32 - 1;
    let y1 = (cy + r).ceil() as i32 + 1;
    for y in y0..=y1 {
        for x in x0..=x1 {
            let dx = x as f32 + 0.5 - cx;
            let dy = y as f32 + 0.5 - cy;
            if dx * dx + dy * dy <= r * r {
                set_px(buf, x, y, alpha);
            }
        }
    }
}

/// Strokes an arc of the circle `(cx, cy, r)` from `start_deg` to `end_deg`
/// (measured counter-clockwise-normalized 0..360, `start_deg <= end_deg`;
/// callers needing a wraparound arc should pre-normalize). `start_deg == 0.0
/// && end_deg == 360.0` draws a full ring — `stroke_circle` below is exactly
/// that special case. Used directly by `Spinner` to leave a deliberate gap
/// (the "spinner" shape read as a ring with a break, distinct from the
/// unbroken `Ring` badge).
// 8 explicit params (not a struct) is deliberate for this small, self-
// contained pixel-art module: every call site below reads as a literal
// geometry spec, which matters more here than trimming an arg count.
#[allow(clippy::too_many_arguments)]
fn stroke_arc(
    buf: &mut [u8],
    cx: f32,
    cy: f32,
    r: f32,
    thickness: f32,
    start_deg: f32,
    end_deg: f32,
    alpha: u8,
) {
    let x0 = (cx - r - thickness).floor() as i32 - 1;
    let x1 = (cx + r + thickness).ceil() as i32 + 1;
    let y0 = (cy - r - thickness).floor() as i32 - 1;
    let y1 = (cy + r + thickness).ceil() as i32 + 1;
    for y in y0..=y1 {
        for x in x0..=x1 {
            let dx = x as f32 + 0.5 - cx;
            let dy = y as f32 + 0.5 - cy;
            let dist = (dx * dx + dy * dy).sqrt();
            if (dist - r).abs() > thickness / 2.0 {
                continue;
            }
            let mut angle = dy.atan2(dx).to_degrees();
            if angle < 0.0 {
                angle += 360.0;
            }
            if angle >= start_deg && angle <= end_deg {
                set_px(buf, x, y, alpha);
            }
        }
    }
}

fn stroke_circle(buf: &mut [u8], cx: f32, cy: f32, r: f32, thickness: f32, alpha: u8) {
    stroke_arc(buf, cx, cy, r, thickness, 0.0, 360.0, alpha);
}

fn fill_rect(buf: &mut [u8], ax: f32, ay: f32, bx: f32, by: f32, alpha: u8) {
    let (x0, x1) = (ax.min(bx), ax.max(bx));
    let (y0, y1) = (ay.min(by), ay.max(by));
    for y in (y0.floor() as i32)..(y1.ceil() as i32) {
        for x in (x0.floor() as i32)..(x1.ceil() as i32) {
            set_px(buf, x, y, alpha);
        }
    }
}

/// Fills a thick capsule along the segment `(x0,y0)-(x1,y1)`. `alpha == 0`
/// ERASES along the segment instead of painting it — used by `CloudSlash` to
/// cut a visible gap through an already-opaque shape (a template image has
/// no color contrast to lean on, so "slash" has to read as a punched-out
/// stripe, not an overpainted one).
fn fill_line(buf: &mut [u8], x0: f32, y0: f32, x1: f32, y1: f32, thickness: f32, alpha: u8) {
    let min_x = (x0.min(x1) - thickness).floor() as i32 - 1;
    let max_x = (x0.max(x1) + thickness).ceil() as i32 + 1;
    let min_y = (y0.min(y1) - thickness).floor() as i32 - 1;
    let max_y = (y0.max(y1) + thickness).ceil() as i32 + 1;
    let dx = x1 - x0;
    let dy = y1 - y0;
    let len2 = dx * dx + dy * dy;
    let half_thick2 = (thickness / 2.0) * (thickness / 2.0);
    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let px = x as f32 + 0.5;
            let py = y as f32 + 0.5;
            let t = if len2 > 0.0 {
                (((px - x0) * dx + (py - y0) * dy) / len2).clamp(0.0, 1.0)
            } else {
                0.0
            };
            let cx = x0 + t * dx;
            let cy = y0 + t * dy;
            let ddx = px - cx;
            let ddy = py - cy;
            if ddx * ddx + ddy * ddy <= half_thick2 {
                set_px(buf, x, y, alpha);
            }
        }
    }
}

fn fill_triangle(buf: &mut [u8], p0: (f32, f32), p1: (f32, f32), p2: (f32, f32), alpha: u8) {
    let min_x = p0.0.min(p1.0).min(p2.0).floor() as i32 - 1;
    let max_x = p0.0.max(p1.0).max(p2.0).ceil() as i32 + 1;
    let min_y = p0.1.min(p1.1).min(p2.1).floor() as i32 - 1;
    let max_y = p0.1.max(p1.1).max(p2.1).ceil() as i32 + 1;
    let sign = |a: (f32, f32), b: (f32, f32), c: (f32, f32)| {
        (a.0 - c.0) * (b.1 - c.1) - (b.0 - c.0) * (a.1 - c.1)
    };
    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let p = (x as f32 + 0.5, y as f32 + 0.5);
            let d1 = sign(p, p0, p1);
            let d2 = sign(p, p1, p2);
            let d3 = sign(p, p2, p0);
            let has_neg = d1 < 0.0 || d2 < 0.0 || d3 < 0.0;
            let has_pos = d1 > 0.0 || d2 > 0.0 || d3 > 0.0;
            if !(has_neg && has_pos) {
                set_px(buf, x, y, alpha);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// The aviator base + per-shape badges.
// ---------------------------------------------------------------------------

/// Paints the real aviator brand mark's base silhouette for `treatment`, from
/// the build-time-rasterized alpha masks above. `Solid` and `Dimmed` both
/// paint `AVIATOR_SOLID` (`Dimmed` scales every alpha value down to the same
/// ~140/255 the old placeholder used flatly); `Hollow` paints
/// `AVIATOR_HOLLOW`, the derived outline-only mask.
fn draw_base(buf: &mut [u8], treatment: BaseTreatment) {
    let mask = match treatment {
        BaseTreatment::Solid | BaseTreatment::Dimmed => AVIATOR_SOLID,
        BaseTreatment::Hollow => AVIATOR_HOLLOW,
    };
    for y in 0..GLYPH_SIZE as i32 {
        for x in 0..GLYPH_SIZE as i32 {
            let i = (y as u32 * GLYPH_SIZE + x as u32) as usize;
            let raw = mask[i];
            if raw == 0 {
                continue;
            }
            let alpha = match treatment {
                BaseTreatment::Dimmed => ((raw as u32 * 140) / 255) as u8,
                _ => raw,
            };
            set_px(buf, x, y, alpha);
        }
    }
}

/// Composites `shape` into the lower-trailing circular badge field
/// (`--radius-badge: full`, per 60-ui-design.md's Design Tokens table).
fn draw_badge(buf: &mut [u8], shape: BadgeShape) {
    if shape == BadgeShape::None {
        return;
    }
    let s = GLYPH_SIZE as f32;
    let bx = s * 0.76;
    let by = s * 0.76;
    let rb = s * 0.20;
    let stroke_w = s * 0.06;

    match shape {
        BadgeShape::None => {}
        BadgeShape::Dot => fill_circle(buf, bx, by, rb * 0.55, 255),
        BadgeShape::Ring => stroke_circle(buf, bx, by, rb, stroke_w, 255),
        // A ring with a deliberate gap — distinct silhouette from the
        // unbroken Syncing `Ring`.
        BadgeShape::Spinner => stroke_arc(buf, bx, by, rb, stroke_w, 0.0, 270.0, 255),
        BadgeShape::Bang => {
            fill_rect(
                buf,
                bx - s * 0.03,
                by - rb * 0.85,
                bx + s * 0.03,
                by + rb * 0.15,
                255,
            );
            fill_circle(buf, bx, by + rb * 0.6, s * 0.045, 255);
        }
        BadgeShape::Triangle => fill_triangle(
            buf,
            (bx, by - rb),
            (bx - rb * 0.95, by + rb * 0.8),
            (bx + rb * 0.95, by + rb * 0.8),
            255,
        ),
        BadgeShape::Wrench => {
            fill_line(
                buf,
                bx - rb * 0.7,
                by + rb * 0.7,
                bx + rb * 0.7,
                by - rb * 0.7,
                s * 0.07,
                255,
            );
            stroke_circle(buf, bx - rb * 0.7, by + rb * 0.7, s * 0.065, s * 0.04, 255);
            fill_circle(buf, bx + rb * 0.7, by - rb * 0.7, s * 0.05, 255);
        }
        BadgeShape::Key => {
            stroke_circle(
                buf,
                bx - rb * 0.35,
                by - rb * 0.35,
                rb * 0.4,
                s * 0.045,
                255,
            );
            fill_line(buf, bx, by, bx + rb * 0.8, by + rb * 0.8, s * 0.06, 255);
            fill_line(
                buf,
                bx + rb * 0.55,
                by + rb * 0.55,
                bx + rb * 0.8,
                by + rb * 0.3,
                s * 0.045,
                255,
            );
        }
        BadgeShape::CloudSlash => {
            fill_circle(buf, bx - rb * 0.35, by, rb * 0.4, 255);
            fill_circle(buf, bx + rb * 0.15, by - rb * 0.15, rb * 0.5, 255);
            fill_rect(buf, bx - rb * 0.6, by, bx + rb * 0.6, by + rb * 0.3, 255);
            // Cut a diagonal gap through the cloud silhouette (erase, not
            // paint — see `fill_line`'s doc).
            fill_line(
                buf,
                bx - rb * 0.9,
                by - rb * 0.9,
                bx + rb * 0.9,
                by + rb * 0.9,
                s * 0.06,
                0,
            );
        }
        BadgeShape::Clock => {
            stroke_circle(buf, bx, by, rb * 0.85, s * 0.05, 255);
            fill_line(buf, bx, by, bx, by - rb * 0.55, s * 0.05, 255);
            fill_line(buf, bx, by, bx + rb * 0.4, by, s * 0.05, 255);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALL_GLYPH_STATES: [&str; 11] = [
        "none",
        "hollow",
        "wrench",
        "key",
        "triangle",
        "cloud-slash",
        "clock",
        "ring",
        "update",
        "spinner",
        "bang",
    ];

    /// Pure-map fitness check: every known `glyph_state` token maps to a
    /// stable, deterministic (base, badge) pair — this IS the "tray glyph
    /// selection is a pure map of RenderState" test the task brief asks for.
    #[test]
    fn every_known_glyph_state_maps_to_a_stable_treatment() {
        for state in ALL_GLYPH_STATES {
            let a = treatment_for(state);
            let b = treatment_for(state);
            assert_eq!(a, b, "treatment_for({state:?}) is not deterministic");
        }
    }

    #[test]
    fn healthy_and_setup_needed_carry_no_badge() {
        assert_eq!(
            treatment_for("none"),
            (BaseTreatment::Solid, BadgeShape::None)
        );
        assert_eq!(
            treatment_for("hollow"),
            (BaseTreatment::Hollow, BadgeShape::None)
        );
    }

    #[test]
    fn every_non_none_badge_state_is_distinct() {
        let badges: Vec<BadgeShape> = ALL_GLYPH_STATES
            .iter()
            .map(|s| treatment_for(s).1)
            .filter(|b| *b != BadgeShape::None)
            .collect();
        let mut seen = std::collections::HashSet::new();
        for b in &badges {
            assert!(
                seen.insert(*b),
                "badge shape {b:?} reused across states — not distinguishable"
            );
        }
    }

    #[test]
    fn unrecognized_token_fails_closed_to_bang_never_healthy() {
        assert_eq!(
            treatment_for("some-unmapped-future-status"),
            (BaseTreatment::Solid, BadgeShape::Bang)
        );
    }

    #[test]
    fn cli_unreadable_bang_composites_a_badge() {
        assert_eq!(treatment_for("bang").1, BadgeShape::Bang);
    }

    #[test]
    fn composite_produces_a_correctly_sized_rgba_buffer_for_every_state() {
        for state in ALL_GLYPH_STATES {
            let img = composite(state);
            assert_eq!(img.width(), GLYPH_SIZE);
            assert_eq!(img.height(), GLYPH_SIZE);
            assert_eq!(img.rgba().len(), (GLYPH_SIZE * GLYPH_SIZE * 4) as usize);
        }
    }

    #[test]
    fn composite_never_produces_an_all_transparent_image() {
        // Every state, including Healthy, must paint at least the base
        // silhouette — an all-zero-alpha buffer would render as an invisible
        // tray icon, not "quiet Healthy".
        for state in ALL_GLYPH_STATES {
            let img = composite(state);
            let painted = img.rgba().chunks_exact(4).any(|px| px[3] > 0);
            assert!(painted, "composite({state:?}) painted no pixels at all");
        }
    }

    #[test]
    fn healthy_glyph_has_no_pixels_in_the_badge_corner() {
        // "none" (Healthy) must be the plain, unbadged base — the corner
        // region a badge would occupy stays fully transparent.
        let img = composite("none");
        let rgba = img.rgba();
        let s = GLYPH_SIZE;
        let bx = (s as f32 * 0.76) as u32;
        let by = (s as f32 * 0.76) as u32;
        let i = ((by * s + bx) * 4 + 3) as usize;
        assert_eq!(
            rgba[i], 0,
            "Healthy glyph must never paint the badge corner"
        );
    }

    #[test]
    fn bang_glyph_paints_the_badge_corner() {
        let img = composite("bang");
        let rgba = img.rgba();
        let s = GLYPH_SIZE;
        let bx = (s as f32 * 0.76) as u32;
        let by = (s as f32 * 0.76) as u32;
        let i = ((by * s + bx) * 4 + 3) as usize;
        assert!(rgba[i] > 0, "CLI-unreadable glyph must paint a badge mark");
    }
}
