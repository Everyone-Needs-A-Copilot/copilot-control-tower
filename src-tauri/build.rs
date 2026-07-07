use std::env;
use std::path::PathBuf;

fn main() {
    // T8/F3 (sec review — capability tightening): without this, `get_state`/
    // `refresh_now`/`hide_popover` are app-defined commands with no ACL
    // manifest entry at all, so Tauri's runtime authority
    // (`has_app_acl_manifest`) skips the capability check for them entirely
    // (verified against the `tauri` 2.11.5 crate source,
    // `src/webview/mod.rs`'s invoke-handling: ACL is only enforced for a
    // local app command when the app registers an `AppManifest`).
    // Registering them here is what makes `capabilities/default.json`'s
    // explicit `allow-get-state`/`allow-refresh-now`/`allow-hide-popover`
    // entries the actual, enforced allow-list, instead of the commands being
    // reachable unconditionally regardless of what capabilities.json says.
    // `hide_popover` (T9 D2 follow-up): the Esc/click-outside popover
    // dismiss command — see `src-tauri/src/commands.rs`. `get_settings`/
    // `save_settings`/`open_settings_window` (M2/S6): the Settings IPC seam
    // — same ACL-enforcement reasoning applies, and each has its own
    // `allow-*` entry scoped to only the window that legitimately calls it
    // (`capabilities/default.json` for `open_settings_window`, called from
    // the popover's footer; `capabilities/settings.json` for
    // `get_settings`/`save_settings`, called from the Settings window).
    // `get_wizard_state`/`get_wizard_product_catalog`/`is_first_run`/
    // `wizard_advance`/`wizard_choose_products`/`wizard_set_layers`/
    // `wizard_begin_signin`/`wizard_poll_signin`/`open_wizard_window`
    // (M3/S6, `get_wizard_product_catalog` added S8): the first-run wizard's
    // IPC seam — same ACL-enforcement reasoning, scoped to only the wizard
    // window (`capabilities/wizard.json`).
    let attributes =
        tauri_build::Attributes::new().app_manifest(tauri_build::AppManifest::new().commands(&[
            "get_state",
            "refresh_now",
            "hide_popover",
            "get_settings",
            "save_settings",
            "open_settings_window",
            "get_wizard_state",
            "get_wizard_product_catalog",
            "is_first_run",
            "wizard_advance",
            "wizard_choose_products",
            "wizard_set_layers",
            "wizard_begin_signin",
            "wizard_poll_signin",
            "open_wizard_window",
        ]));
    tauri_build::try_build(attributes).expect("tauri_build::try_build failed");

    rasterize_tray_glyph();
}

/// Build-time-only rasterization of the real brand mark (`icons/aviators.svg`,
/// an aviator-sunglasses silhouette) into the two alpha-only pixel masks
/// `render::glyph` embeds and composites at runtime: the plain filled
/// silhouette (used by the `Solid` and `Dimmed` base treatments — `Dimmed`
/// just scales its alpha at runtime) and a derived outline-only mask (used by
/// `Hollow`). Rasterizing here, once, at build time — rather than parsing/
/// rendering the SVG on every app launch — keeps the `resvg`/`usvg`/
/// `tiny-skia` rendering stack a **build-dependency only**; none of it, nor
/// the SVG source, ships in or is touched by the running app binary (see
/// `Cargo.toml`'s `[build-dependencies]`).
fn rasterize_tray_glyph() {
    // Must match `render::glyph::GLYPH_SIZE` — that module asserts the two
    // embedded masks are exactly `GLYPH_SIZE * GLYPH_SIZE` bytes, so a drift
    // here fails the build rather than silently mis-sizing the tray icon.
    const GLYPH_SIZE: u32 = 44;
    // Fraction of the canvas width the aviators span, and the vertical
    // center they're placed at — tuned to match the footprint of the
    // procedural placeholder silhouette it replaces (right-lens edge and
    // lower-lens edge both land within a pixel of the old geometry), so the
    // badge's lower-trailing corner placement still reads cleanly untouched.
    const TARGET_W_FRAC: f32 = 0.82;
    const CENTER_Y_FRAC: f32 = 0.46;
    // Outline band radius for the `Hollow` mask's dilate/erode — half the
    // placeholder's old stroke width (`GLYPH_SIZE * 0.09 ≈ 4px`), so the
    // resulting band is comparably weighted.
    const OUTLINE_RADIUS_PX: i32 = 2;

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let svg_path = manifest_dir.join("icons").join("aviators.svg");
    println!("cargo:rerun-if-changed={}", svg_path.display());

    let svg_text = std::fs::read_to_string(&svg_path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", svg_path.display()));
    let tree = resvg::usvg::Tree::from_str(&svg_text, &resvg::usvg::Options::default())
        .unwrap_or_else(|e| panic!("failed to parse {}: {e}", svg_path.display()));

    let size = tree.size();
    let target_w = GLYPH_SIZE as f32 * TARGET_W_FRAC;
    let scale = target_w / size.width();
    let target_h = size.height() * scale;
    let tx = (GLYPH_SIZE as f32 - target_w) / 2.0;
    let ty = GLYPH_SIZE as f32 * CENTER_Y_FRAC - target_h / 2.0;

    let mut pixmap = resvg::tiny_skia::Pixmap::new(GLYPH_SIZE, GLYPH_SIZE)
        .expect("GLYPH_SIZE x GLYPH_SIZE pixmap allocation");
    let transform = resvg::tiny_skia::Transform::from_scale(scale, scale).post_translate(tx, ty);
    resvg::render(&tree, transform, &mut pixmap.as_mut());

    // Alpha channel only — the SVG's `#2D294E` fill is irrelevant for a
    // macOS template image (the OS re-tints RGB; only alpha is composited).
    // tiny-skia's pixmap data is premultiplied RGBA, but premultiplication
    // never changes the alpha byte itself, so reading it directly (no
    // demultiply step) yields the exact coverage value.
    let solid: Vec<u8> = pixmap.data().chunks_exact(4).map(|px| px[3]).collect();
    assert_eq!(
        solid.len(),
        (GLYPH_SIZE * GLYPH_SIZE) as usize,
        "rasterized aviator mask is the wrong size"
    );

    let hollow = outline_from_mask(&solid, GLYPH_SIZE, OUTLINE_RADIUS_PX);

    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));
    std::fs::write(out_dir.join("aviator_solid.bin"), &solid).expect("write aviator_solid.bin");
    std::fs::write(out_dir.join("aviator_hollow.bin"), &hollow).expect("write aviator_hollow.bin");
}

/// Derives an outline-only mask from a filled silhouette mask: a
/// `radius_px`-wide band straddling the shape's edge (dilate AND NOT erode —
/// a morphological gradient), used for the tray glyph's `Hollow` base
/// treatment ("invitation, not error" — see `render::glyph`'s module doc).
fn outline_from_mask(mask: &[u8], size: u32, radius_px: i32) -> Vec<u8> {
    let s = size as i32;
    let inside: Vec<bool> = mask.iter().map(|&a| a >= 128).collect();
    let dilated = morph(&inside, s, radius_px, true);
    let eroded = morph(&inside, s, radius_px, false);
    (0..inside.len())
        .map(|i| if dilated[i] && !eroded[i] { mask[i] } else { 0 })
        .collect()
}

/// Circular-kernel binary dilate (`dilate == true`: true if any neighbor
/// within `radius` is inside) or erode (`dilate == false`: true only if
/// every neighbor within `radius` is inside) over a `size x size` binary
/// mask. Pixels outside the canvas count as "outside" for both operations.
fn morph(bin: &[bool], size: i32, radius: i32, dilate: bool) -> Vec<bool> {
    let mut out = vec![false; bin.len()];
    for y in 0..size {
        for x in 0..size {
            let mut any_inside = false;
            let mut any_outside = false;
            for dy in -radius..=radius {
                for dx in -radius..=radius {
                    if dx * dx + dy * dy > radius * radius {
                        continue;
                    }
                    let (nx, ny) = (x + dx, y + dy);
                    let v = nx >= 0
                        && ny >= 0
                        && nx < size
                        && ny < size
                        && bin[(ny * size + nx) as usize];
                    if v {
                        any_inside = true;
                    } else {
                        any_outside = true;
                    }
                }
            }
            out[(y * size + x) as usize] = if dilate { any_inside } else { !any_outside };
        }
    }
    out
}
