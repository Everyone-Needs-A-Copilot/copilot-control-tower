//! M5/S2 fitness function (FF-M5-2, `.copilot/wp/30.md`): "no wipe logic in
//! the app". Control Tower RENDERS a CLI/MDM-performed deprovision; it must
//! never contain any file-deletion, tree-wiping, or git-history-destroying
//! primitive itself — the CLI computes AND PERFORMS the entire
//! deprovision. This is a pure text scan of the deprovision module's own
//! production source (`src/deprovision/` and `src/model/deprovision.rs`,
//! `#[cfg(test)]` blocks excluded — a test helper writing a throwaway temp
//! fixture script is not the invariant under test here), independent of the
//! compiled/visibility boundary, matching the same approach
//! `fitness_no_bare_cli_name.rs`/`fitness_no_fabricated_healthy.rs` already
//! use for their own source-level fitness checks.

use std::fs;
use std::path::{Path, PathBuf};

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
/// approach as `fitness_no_bare_cli_name.rs`'s `strip_comments`, so a
/// needle mentioned only in a doc comment (explaining what must NOT be
/// present) never trips this test.
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
/// identical logic to `fitness_no_bare_cli_name.rs`'s
/// `strip_cfg_test_blocks`, duplicated rather than shared so each fitness
/// test file stays independently readable/auditable. Test helpers in this
/// module tree legitimately create/remove their OWN throwaway temp
/// directories/scripts (e.g. a hung-CLI stub) — that is test-harness
/// bookkeeping, not deprovision wipe logic, and is exactly the case this
/// exclusion exists for.
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

/// Every needle a genuine wipe/retain-decision primitive would contain.
/// Deliberately coarse (a tripwire, not an exhaustive AST analysis) — this
/// module should contain literally NONE of these; it only spawns `cc` (via
/// its own `Command`, exactly like `wizard::signin` does for `auth`),
/// parses the body it prints, and renders the result.
const FORBIDDEN_NEEDLES: [&str; 11] = [
    "remove_dir_all",
    "remove_dir(",
    "remove_file(",
    "fs::remove",
    "rmdir",
    "fs::write(",
    "std::fs::write(",
    "git clean",
    "git reset",
    "git rm",
    "git checkout",
];

/// The exact two source locations FF-M5-2 governs: the `deprovision/` module
/// tree (spawn + orchestration + render) and `model/deprovision.rs` (the
/// wire/domain/parse layer). Scoped this narrowly — not the whole crate —
/// because legitimate file-write primitives exist elsewhere for unrelated,
/// already-audited reasons (e.g. `settings::writer`'s never-destroy
/// manifest writer, `updater`'s staged-bundle machinery); this fitness
/// function's job is proving the deprovision RENDER surface specifically
/// carries none, matching this task's own scope.
fn governed_files() -> Vec<PathBuf> {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut files = Vec::new();

    let deprovision_dir = manifest_dir.join("src").join("deprovision");
    collect_rs_files(&deprovision_dir, &mut files);

    let model_deprovision = manifest_dir
        .join("src")
        .join("model")
        .join("deprovision.rs");
    assert!(
        model_deprovision.is_file(),
        "expected {} to exist",
        model_deprovision.display()
    );
    files.push(model_deprovision);

    files
}

#[test]
fn no_wipe_or_git_destructive_primitive_anywhere_in_the_deprovision_module() {
    let files = governed_files();
    assert!(
        files.len() >= 3,
        "expected at least model/deprovision.rs + deprovision/mod.rs + deprovision/render.rs, \
         found {files:?}"
    );

    let mut offenders: Vec<(PathBuf, &str)> = Vec::new();
    for file in &files {
        let raw =
            fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        let production_only = strip_cfg_test_blocks(&strip_comments(&raw));
        for needle in FORBIDDEN_NEEDLES {
            if production_only.contains(needle) {
                offenders.push((file.clone(), needle));
            }
        }
    }

    assert!(
        offenders.is_empty(),
        "found a wipe/retain-decision-shaped primitive in the deprovision render surface \
         (invariant #1/#3 — Control Tower parses and renders a CLI-performed deprovision, it \
         never performs one itself): {offenders:?}. All removal/retention logic belongs in the \
         `copilot`/`cc` CLI."
    );
}

/// Belt-and-suspenders: confirms the scan itself is exercising real files,
/// not silently matching zero because a path changed underneath it (a
/// fitness test that can't fail is worthless).
#[test]
fn governed_files_actually_exist_and_are_nonempty() {
    for file in governed_files() {
        let raw =
            fs::read_to_string(&file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        assert!(
            !raw.trim().is_empty(),
            "{} is unexpectedly empty",
            file.display()
        );
    }
}
