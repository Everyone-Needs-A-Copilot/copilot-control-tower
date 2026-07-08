//! M9/Stream-F (task 75, `.copilot/wp/52.md`, `uid`) — invariant #1
//! (parse-never-compute) fitness check: the Windows tray art
//! (`platform::windows::tray`) must REUSE `render::glyph::treatment_for`'s
//! state->badge mapping table, never fork/re-declare a second one. Same
//! cheap, dependency-free source-scan style every other fitness test in this
//! crate already uses (see `fitness_m5_single_forced_boundary.rs`,
//! `fitness_m9_platform_windows_cfg_gated.rs`) — this crate has no Windows
//! toolchain, so a source-scan is the only verification possible here; it
//! compiles and runs unconditionally on macOS because it scans TEXT, not
//! `#[cfg(windows)]`-gated code.

use std::fs;
use std::path::{Path, PathBuf};

fn src_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("src")
}

fn read(rel: &str) -> String {
    let path = src_dir().join(rel);
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

/// `render::glyph::treatment_for` is the ONE place in this crate that maps a
/// `glyph_state` token to a (base treatment, badge shape) pair. Grep every
/// `.rs` file under `src/` and confirm the literal `fn treatment_for(` text
/// appears exactly once, crate-wide — a second occurrence would mean some
/// module (most plausibly the Windows tray) invented its own competing
/// state->badge table instead of reusing this one.
#[test]
fn treatment_for_is_declared_exactly_once_crate_wide_fitness_m9() {
    let mut occurrences = Vec::new();
    let mut stack = vec![src_dir()];
    while let Some(dir) = stack.pop() {
        for entry in
            fs::read_dir(&dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display()))
        {
            let path = entry.expect("dir entry").path();
            if path.is_dir() {
                stack.push(path);
                continue;
            }
            if path.extension().and_then(|e| e.to_str()) != Some("rs") {
                continue;
            }
            let text = fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
            if text.contains("fn treatment_for(") {
                occurrences.push(path);
            }
        }
    }
    assert_eq!(
        occurrences.len(),
        1,
        "expected exactly one `fn treatment_for(` declaration crate-wide (in \
         render/glyph.rs) — found {occurrences:?}. A second declaration means the \
         state->badge table was forked instead of reused (invariant #1)."
    );
    assert!(
        occurrences[0].ends_with("render/glyph.rs"),
        "the sole `fn treatment_for(` declaration must live in render/glyph.rs — found it in \
         {:?} instead",
        occurrences[0]
    );
}

/// Same reasoning, for the two enums `treatment_for` returns: `BaseTreatment`
/// and `BadgeShape` must each be declared exactly once crate-wide (in
/// `render/glyph.rs`) — a second `enum BadgeShape { .. }` elsewhere would be
/// a forked badge vocabulary, not a reuse of the shared one.
#[test]
fn base_treatment_and_badge_shape_enums_are_declared_exactly_once_crate_wide_fitness_m9() {
    for enum_name in ["enum BaseTreatment", "enum BadgeShape"] {
        let mut occurrences = Vec::new();
        let mut stack = vec![src_dir()];
        while let Some(dir) = stack.pop() {
            for entry in
                fs::read_dir(&dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display()))
            {
                let path = entry.expect("dir entry").path();
                if path.is_dir() {
                    stack.push(path);
                    continue;
                }
                if path.extension().and_then(|e| e.to_str()) != Some("rs") {
                    continue;
                }
                let text = fs::read_to_string(&path)
                    .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
                if text.contains(enum_name) {
                    occurrences.push(path);
                }
            }
        }
        assert_eq!(
            occurrences.len(),
            1,
            "expected exactly one `{enum_name}` declaration crate-wide (in render/glyph.rs) — \
             found {occurrences:?}"
        );
    }
}

/// `platform::windows::tray` must call `render::glyph::composite` (evidence
/// that it REUSES the shared, already-badged pixel output) rather than
/// re-implementing base/badge drawing itself. This is a positive-evidence
/// check (reuse IS present), complementing the two negative checks above (no
/// fork exists).
#[test]
fn windows_tray_calls_the_shared_render_glyph_composite_fitness_m9() {
    let text = read("platform/windows/tray.rs");
    assert!(
        text.contains("render::glyph::composite"),
        "expected platform/windows/tray.rs to call render::glyph::composite (reusing the \
         shared state->badge table), but no such call was found"
    );
}

/// Negative check, narrowly scoped to the Windows tray file itself: it must
/// not declare its own `treatment_for`/`BadgeShape`/`BaseTreatment` — this
/// duplicates the crate-wide checks above with a file-specific error message
/// that points a future editor directly at the offending file, rather than
/// making them hunt through a crate-wide occurrence list.
#[test]
fn windows_tray_declares_no_second_state_to_badge_mapping_fitness_m9() {
    let text = read("platform/windows/tray.rs");
    for forbidden in ["fn treatment_for(", "enum BadgeShape", "enum BaseTreatment"] {
        assert!(
            !text.contains(forbidden),
            "platform/windows/tray.rs must not declare {forbidden:?} — it must reuse \
             render::glyph's shared state->badge table, never fork it (invariant #1)"
        );
    }
}

/// `render::glyph` (the module `windows::tray` reuses) must remain a plain,
/// unconditionally-compiled module — if a future change ever gated it behind
/// `#[cfg(target_os = "macos")]`, the Windows tray's `render::glyph::composite`
/// call above would stop compiling on a real Windows target, silently
/// forcing a fork. This guards the PRECONDITION the reuse above depends on.
#[test]
fn render_glyph_module_is_not_macos_gated_fitness_m9() {
    let text = read("render/mod.rs");
    let idx = text
        .find("pub mod glyph;")
        .expect("expected `pub mod glyph;` in render/mod.rs");
    let preceding = &text[..idx];
    let last_line = preceding.lines().last().unwrap_or("");
    assert!(
        !last_line.contains("#[cfg("),
        "render/mod.rs's `pub mod glyph;` must stay unconditionally compiled (no #[cfg] guard) \
         so platform::windows::tray can keep reusing render::glyph::composite verbatim — found \
         a guard on the preceding line: {last_line:?}"
    );
}
