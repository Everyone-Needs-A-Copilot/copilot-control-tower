//! FF-M5-3 (M5/S6, `.copilot/wp/30.md`, task 49 — route-by-competence,
//! invariant #5): the deprovision trigger and the auth-revoked deprovision
//! offer are IT-routed, NEVER Bob-facing. This is the routing half of the
//! discipline `fitness_m5_no_wipe_logic.rs` (FF-M5-2) already proves for the
//! compute half — that test proves `src/deprovision/` contains no wipe
//! logic; this test proves `src/routing/` (this task's own module) and the
//! entire Bob-facing surface (`src/commands.rs`'s Tauri IPC handlers,
//! `src/lib.rs`'s `invoke_handler!` registration, `src/tray.rs`'s popover)
//! never wire a deprovision trigger or an auth-revoked offer to anything Bob
//! can see or click. Same cheap, dependency-free text-scan style every other
//! fitness test in this crate uses (see `fitness_m5_no_wipe_logic.rs`,
//! `fitness_m5_single_forced_boundary.rs`) — no call-graph analysis, no live
//! Tauri runtime.

use std::fs;
use std::path::{Path, PathBuf};

fn src_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("src")
}

fn collect_rs_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display())) {
        let path = entry.expect("dir entry").path();
        if path.is_dir() {
            collect_rs_files(&path, out);
        } else if path.extension().and_then(|e| e.to_str()) == Some("rs") {
            out.push(path);
        }
    }
}

/// Strips `//...` line comments and `/* ... */` block comments — same
/// approach every other fitness test in this crate already uses, so a needle
/// mentioned only in a doc comment (explaining what must NOT be present)
/// never trips this test.
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

/// Removes every `#[cfg(test)] ... { ... }` item's body (brace-matched) —
/// identical logic to `fitness_m5_no_wipe_logic.rs`'s
/// `strip_cfg_test_blocks`, duplicated per this crate's "each fitness check
/// owns its own copy" convention. This module's own test suites legitimately
/// name `run_deprovision`/`route_deprovision_trigger`/etc. in their
/// `#[cfg(test)] mod tests` bodies — that is the invariant's own unit-test
/// coverage, not a Bob-facing wiring site, and must not trip this scan.
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

/// Tauri/Bob-facing wiring primitives — none of these may appear in the
/// routing module's own production source. If `src/routing/` ever needs one
/// of these, that IS the invariant #5 violation this test exists to catch:
/// the deprovision/auth-revoked lane must never grow a direct line to a
/// Tauri command, an emitted event, or the popover window.
const BOB_FACING_NEEDLES: [&str; 7] = [
    "tauri::command",
    "AppHandle",
    ".emit(",
    "invoke_handler",
    "toggle_popover",
    "hide_popover_window",
    "POPOVER_LABEL",
];

#[test]
fn routing_module_never_touches_a_tauri_or_popover_primitive() {
    let routing_dir = src_dir().join("routing");
    let mut files = Vec::new();
    collect_rs_files(&routing_dir, &mut files);
    assert!(
        files.len() >= 2,
        "expected at least routing/mod.rs + routing/deprovision_trigger.rs, found {files:?}"
    );

    let mut offenders: Vec<(PathBuf, &str)> = Vec::new();
    for file in &files {
        let production_only = read_production_source(file);
        for needle in BOB_FACING_NEEDLES {
            if production_only.contains(needle) {
                offenders.push((file.clone(), needle));
            }
        }
    }

    assert!(
        offenders.is_empty(),
        "the routing module must never wire a Bob-facing Tauri/popover primitive \
         (invariant #5 — deprovision/auth-revoked routing is IT/managed-only): {offenders:?}"
    );
}

/// The symbols a Bob-facing Tauri command surface would need to actually
/// expose the deprovision trigger or the auth-revoked offer to the popover.
/// None of these may appear in `commands.rs` (the entire Rust<->web-UI IPC
/// surface) or `tray.rs` (the popover window owner) — if either file ever
/// needs one, that IS a Bob-facing deprovision affordance, which invariant
/// #5 forbids outright (deprovision is IT/managed/leaver-only, never a Bob
/// prompt).
const DEPROVISION_ROUTING_SYMBOLS: [&str; 6] = [
    "routing::",
    "deprovision_trigger",
    "route_deprovision_trigger",
    "route_credential_state",
    "run_deprovision",
    "DeprovisionView",
];

#[test]
fn the_bob_facing_ipc_and_popover_surface_never_references_deprovision_routing() {
    for rel in ["commands.rs", "tray.rs"] {
        let path = src_dir().join(rel);
        assert!(path.is_file(), "expected {} to exist", path.display());
        let production_only = read_production_source(&path);
        for needle in DEPROVISION_ROUTING_SYMBOLS {
            assert!(
                !production_only.contains(needle),
                "{} references {:?} — a Bob-facing IPC/popover surface must never touch the \
                 deprovision trigger or the auth-revoked offer (invariant #5, deprovision is \
                 IT/managed/leaver-only, never a Bob prompt)",
                path.display(),
                needle
            );
        }
    }
}

/// `lib.rs`'s `invoke_handler!` registration list is the literal Tauri
/// command allow-list the web UI can call at all — confirms no deprovision/
/// routing symbol is registered there either. Belt-and-suspenders alongside
/// the `commands.rs`/`tray.rs` scan above (scoped to just the macro's
/// argument list, not the whole file, since `lib.rs`'s own module doc
/// legitimately names `routing`/`deprovision` in prose describing what each
/// module is and is NOT wired to).
#[test]
fn invoke_handler_registration_never_lists_a_deprovision_routing_command() {
    let path = src_dir().join("lib.rs");
    let production_only = read_production_source(&path);
    let marker = "generate_handler![";
    let start = production_only
        .find(marker)
        .unwrap_or_else(|| panic!("expected lib.rs to contain a tauri::generate_handler! call"));
    let body_start = start + marker.len();
    let end = production_only[body_start..]
        .find(']')
        .map(|i| body_start + i)
        .unwrap_or(production_only.len());
    let handler_block = &production_only[body_start..end];

    assert!(
        !handler_block.trim().is_empty(),
        "expected a non-empty generate_handler! argument list"
    );

    for needle in DEPROVISION_ROUTING_SYMBOLS {
        assert!(
            !handler_block.contains(needle),
            "invoke_handler! registers {needle:?} — deprovision/auth-revoked routing must never \
             become a Bob-invokable Tauri command"
        );
    }
}

/// Belt-and-suspenders: confirms the scan itself is exercising real,
/// nonempty files, not silently matching zero because a path changed
/// underneath it (a fitness test that can't fail is worthless).
#[test]
fn governed_files_actually_exist_and_are_nonempty() {
    for rel in [
        "routing/mod.rs",
        "routing/deprovision_trigger.rs",
        "commands.rs",
        "tray.rs",
        "lib.rs",
    ] {
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
