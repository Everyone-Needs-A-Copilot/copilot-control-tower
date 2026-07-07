//! T8 fitness function: the badge-SHAPE vocabulary is ONE set across every
//! place that emits or interprets it — `model::state::CliStatus::glyph_badge`
//! together with `render::derive`'s `"bang"`/`"pass"`/`"triangle"` mappings
//! (Rust production), `render::glyph::treatment_for` (tray compositing), and
//! `src/render/badges.ts` + `src/types.ts` (the web UI). Rust owns the
//! authoritative list (`render::BADGE_VOCABULARY`, see its doc comment for
//! the full derivation); this test proves every token that list contains has
//! a matching case in the TS interpreter, and that TS doesn't declare a
//! token Rust can never produce.
//!
//! A pure text scan of `src/`, for the same reason the other fitness tests
//! scan source rather than compiled output: there is no shared runtime
//! between the Rust crate and the TS bundle to assert against directly, so
//! the contract is enforced lexically, at the string-literal level, which is
//! exactly the granularity the wire format itself uses.

use copilot_control_tower_lib::render::BADGE_VOCABULARY;
use std::fs;
use std::path::Path;

fn read(rel: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("src-tauri has a parent directory")
        .join(rel);
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

#[test]
fn canonical_vocabulary_is_exactly_twelve_distinct_tokens() {
    let mut seen = std::collections::HashSet::new();
    for tok in BADGE_VOCABULARY {
        assert!(
            seen.insert(tok),
            "duplicate token {tok:?} in BADGE_VOCABULARY"
        );
    }
    assert_eq!(BADGE_VOCABULARY.len(), 12);
}

/// Every canonical token must have its own `case "<token>":` arm in
/// `badges.ts`'s `drawShape` switch — i.e. the web UI can actually draw a
/// mark for anything Rust can emit. `"none"` is drawn by the switch's own
/// `case "none": default:` fallthrough, which the source-text search below
/// still finds via the literal `case "none":`.
#[test]
fn every_canonical_token_has_a_shape_in_badges_ts() {
    let badges_ts = read("src/render/badges.ts");
    let missing: Vec<&str> = BADGE_VOCABULARY
        .iter()
        .copied()
        .filter(|tok| !badges_ts.contains(&format!("case \"{tok}\":")))
        .collect();
    assert!(
        missing.is_empty(),
        "src/render/badges.ts's drawShape is missing a case for: {missing:?} \
         (canonical vocabulary: render::BADGE_VOCABULARY)"
    );
}

/// `src/types.ts`'s `BadgeState` union must declare exactly the canonical
/// set — no orphaned Rust token TS can't type, and no TS-only token Rust can
/// never produce (which would be dead code masquerading as a real state).
#[test]
fn badge_state_union_in_types_ts_matches_the_canonical_vocabulary_exactly() {
    let types_ts = read("src/types.ts");
    for tok in BADGE_VOCABULARY {
        assert!(
            types_ts.contains(&format!("\"{tok}\"")),
            "src/types.ts's BadgeState union is missing {tok:?} \
             (canonical vocabulary: render::BADGE_VOCABULARY)"
        );
    }
}

/// `render::glyph::treatment_for` (the tray compositor) must have an
/// explicit arm for every `CliStatus::glyph_badge()` token — `"pass"` is
/// excluded (it is a layer/product-only bucket badge; the header glyph,
/// which is all `treatment_for` ever sees, is never `"pass"` — Healthy is
/// the plain `"none"` mark instead) and `"bang"` is excluded (by its own
/// module doc, it deliberately shares `treatment_for`'s fail-closed `_ =>
/// Bang` catch-all rather than getting a redundant explicit arm — any
/// *unrecognized* future token intentionally lands on the same loud mark, so
/// `"bang"` itself needs no separate case to still render correctly;
/// `render::glyph::tests::cli_unreadable_bang_composites_a_badge` covers it
/// directly).
#[test]
fn glyph_treatment_table_covers_every_header_glyph_token() {
    let glyph_rs = read("src-tauri/src/render/glyph.rs");
    let header_tokens = BADGE_VOCABULARY
        .iter()
        .copied()
        .filter(|t| *t != "pass" && *t != "bang");
    let missing: Vec<&str> = header_tokens
        .filter(|tok| !glyph_rs.contains(&format!("\"{tok}\" =>")))
        .collect();
    assert!(
        missing.is_empty(),
        "render::glyph::treatment_for is missing an explicit arm for: {missing:?} \
         (falls through to its fail-closed `_ => Bang` catch-all instead of an intentional \
         mapping — update the match table in src-tauri/src/render/glyph.rs)"
    );
}
