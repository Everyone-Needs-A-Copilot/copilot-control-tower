//! FF-M6-B (M6/S2, task 53, SOUL.md Principle 2 / the Alert Machine
//! anti-pattern): the `AskBob` output is a CLOSED SET of exactly the two
//! non-deferrable decisions about Bob's own data — `sign-in` and
//! `dirty-wip`. Three independent proofs:
//!
//! 1. **Type-level (structural)**: `routing::BobPromptKind` has EXACTLY two
//!    variants — a source scan of its declaration, so a future third variant
//!    is a visible, reviewed diff to this exact enum rather than a silent
//!    widening.
//! 2. **Source-level**: `routing::policy::route`'s `HeldForApproval`/
//!    `Blocked` match arms contain NO `Routed::AskBob` construction at all —
//!    not a runtime guard that happens to agree, a match arm structurally
//!    incapable of returning `AskBob` (mirrors
//!    `fitness_m5_deprovision_is_it_routed.rs`'s "a match with no Bob branch,
//!    not a runtime guard" standard).
//! 3. **Value-level (exhaustive property test)**: `routing::policy::tests::
//!    doctor_and_update_events_never_produce_askbob_across_every_field_
//!    combination` (an ordinary `cargo test`, referenced here so this file's
//!    doc names the full proof) iterates every field combination of
//!    `DoctorFinding`/`UpdateChange` and confirms none ever produces
//!    `AskBob` — a held-major, a policy denial, and an update change (signed,
//!    unsigned, pruned, or shadow-suspended) can never reach Bob.

use std::fs;
use std::path::{Path, PathBuf};

fn src_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("src")
}

fn strip_comments(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    let bytes = src.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'/') {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
        } else if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'*') {
            i += 2;
            while i < bytes.len() && !(bytes[i] == b'*' && bytes.get(i + 1) == Some(&b'/')) {
                i += 1;
            }
            i += 2;
        } else {
            out.push(bytes[i] as char);
            i += 1;
        }
    }
    out
}

fn strip_cfg_test_blocks(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    let marker = "#[cfg(test)]";
    let mut rest = src;
    while let Some(idx) = rest.find(marker) {
        out.push_str(&rest[..idx]);
        let after_marker = &rest[idx + marker.len()..];
        let brace_start = match after_marker.find('{') {
            Some(b) => b,
            None => {
                out.push_str(marker);
                rest = after_marker;
                continue;
            }
        };
        let body = &after_marker[brace_start..];
        let mut depth = 0i32;
        let mut end = None;
        for (pos, ch) in body.char_indices() {
            match ch {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        end = Some(pos + 1);
                        break;
                    }
                }
                _ => {}
            }
        }
        let end = end.unwrap_or(body.len());
        rest = &body[end..];
    }
    out.push_str(rest);
    out
}

fn read_production_source(path: &Path) -> String {
    let raw = fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    strip_cfg_test_blocks(&strip_comments(&raw))
}

#[test]
fn bob_prompt_kind_has_exactly_two_variants_sign_in_and_dirty_wip() {
    let mod_path = src_dir().join("routing").join("mod.rs");
    let production_only = read_production_source(&mod_path);

    let marker = "pub enum BobPromptKind {";
    let start = production_only
        .find(marker)
        .expect("expected routing/mod.rs to declare `pub enum BobPromptKind`");
    let body_start = start + marker.len();
    let rest = &production_only[body_start..];
    let end = rest
        .find('}')
        .expect("unbalanced braces in BobPromptKind enum");
    let body = &rest[..end];

    let variants: Vec<&str> = body
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();

    assert_eq!(
        variants,
        vec!["SignIn", "DirtyWip"],
        "BobPromptKind must be EXACTLY the closed set {{SignIn, DirtyWip}} — task 53's own \
         instruction: 'Nothing else may become a BobPrompt'"
    );
}

/// `HeldForApproval`/`Blocked` — task 53's two named SOUL rejections — must
/// have no `Routed::AskBob` construction anywhere in their match arms. This
/// scans the FULL arm body (from `RoutableEvent::HeldForApproval` /
/// `RoutableEvent::Blocked` to the next top-level `RoutableEvent::` arm) for
/// the literal `Routed::AskBob` construction.
#[test]
fn held_for_approval_and_blocked_arms_never_construct_askbob() {
    let policy_path = src_dir().join("routing").join("policy.rs");
    let production_only = read_production_source(&policy_path);

    for variant in ["RoutableEvent::HeldForApproval", "RoutableEvent::Blocked"] {
        let arm_start = production_only
            .find(variant)
            .unwrap_or_else(|| panic!("expected route's match to contain a {variant} arm"));
        // The arm body runs until the next `RoutableEvent::` arm marker (a
        // coarse but sufficient boundary — every arm in this match starts
        // with `RoutableEvent::`).
        let after = &production_only[arm_start + variant.len()..];
        let next_arm_offset = after
            .find("RoutableEvent::")
            .unwrap_or(after.len().min(400));
        let arm_body = &after[..next_arm_offset];

        assert!(
            !arm_body.contains("Routed::AskBob"),
            "{variant}'s match arm constructs Routed::AskBob — SOUL.md Case Law forbids this: \
             a held-major/policy-denial event must never be routed to Bob"
        );
    }
}

/// Belt-and-suspenders: confirms the scan itself is exercising real,
/// nonempty files.
#[test]
fn governed_files_actually_exist_and_are_nonempty() {
    for rel in ["routing/mod.rs", "routing/policy.rs"] {
        let path = src_dir().join(rel);
        let raw =
            fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        assert!(
            !raw.trim().is_empty(),
            "{} is unexpectedly empty",
            path.display()
        );
    }
}
