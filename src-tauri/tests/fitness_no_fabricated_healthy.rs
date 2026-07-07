//! T3 fitness function (architecture WP "Fitness functions" / T3 acceptance
//! criteria): `CliStatus::Healthy` must be *constructed* at exactly ONE call
//! site in the whole crate, and that site must be guarded (see
//! `model::state::parse_cli_status`, and the guard immediately after its
//! call site in `model::state::parse_doctor_body`).
//!
//! Two independent detectors, deliberately (T8/F2 — the sec review's finding
//! that a single textual heuristic has blind spots):
//!
//! 1. `healthy_is_constructed_at_exactly_one_guarded_call_site` — the
//!    original textual scan: a **construction** is the literal
//!    `CliStatus::Healthy` written as a value (e.g. `Some(CliStatus::Healthy)`);
//!    a **read** is the same token used as a match pattern (`CliStatus::Healthy
//!    => ...`, always immediately followed by `=>`). Cheap, but only
//!    recognizes the fully-qualified spelling — it would silently miss
//!    `Self::Healthy` used as a *value* (not a match pattern), `use ... as
//!    Alias;` then `Alias::Healthy`, or `use ...CliStatus::*;` then a bare
//!    `Healthy`.
//! 2. `healthy_construction_is_syntactically_confined_to_the_one_guarded_call_site`
//!    — a real `syn`-based AST walk (dev-dependency only; nothing here ships
//!    in the app binary) that closes exactly those three gaps: it resolves
//!    `Self` inside `impl CliStatus`/`impl _ for CliStatus` blocks, `use ...
//!    as Alias` renames, and `use ...CliStatus::*` globs, and — because it
//!    only visits genuine `syn::Expr::Path` nodes (never `syn::Pat` nodes) —
//!    it structurally cannot mistake a match-arm/`matches!` pattern read for
//!    a construction; no `=> `-adjacency heuristic needed for that
//!    distinction at all.
//!
//! Both scans exclude `#[cfg(test)]` code (test code asserting "this fixture
//! parsed to Healthy" is not the invariant under test here) and, for the
//! same reason stated originally, work from literal source rather than
//! macro-expanded output (`#[derive(Serialize)]` et al. reintroduce the
//! fully-qualified variant path invisibly, at compile time, but only ever in
//! *read* position inside the generated `Serialize` impl — not a
//! construction vector).

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

/// Strips `//...` line comments and `/* ... */` block comments (this covers
/// doc comments too, `///`/`//!` both start with `//`). Good enough for this
/// crate's actual source — none of it puts `//` or `/*` inside a string
/// literal.
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

/// Removes every `#[cfg(test)] ... { ... }` item's body (brace-matched) from
/// `src` — test-only code doesn't participate in the "one construction site"
/// production invariant.
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
                // No block follows (shouldn't happen in this crate) — keep scanning.
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

/// Counts *construction* occurrences of `needle` in `text` — i.e. the token
/// NOT immediately followed by `=>` (a match-arm pattern is a read).
fn count_constructions(text: &str, needle: &str) -> usize {
    let mut count = 0;
    let mut rest = text;
    while let Some(idx) = rest.find(needle) {
        let after = &rest[idx + needle.len()..];
        if !after.trim_start().starts_with("=>") {
            count += 1;
        }
        rest = &rest[idx + needle.len()..];
    }
    count
}

#[test]
fn healthy_is_constructed_at_exactly_one_guarded_call_site() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut files = Vec::new();
    collect_rs_files(&src_dir, &mut files);
    assert!(
        !files.is_empty(),
        "expected to find .rs files under {}",
        src_dir.display()
    );

    const NEEDLE: &str = "CliStatus::Healthy";
    let mut sites: Vec<(PathBuf, usize)> = Vec::new();
    let mut total = 0usize;

    for file in &files {
        let raw =
            fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        let production_only = strip_cfg_test_blocks(&strip_comments(&raw));
        let n = count_constructions(&production_only, NEEDLE);
        if n > 0 {
            sites.push((file.clone(), n));
        }
        total += n;
    }

    assert_eq!(
        total, 1,
        "CliStatus::Healthy must be CONSTRUCTED at exactly one guarded call site \
         (model::state::parse_cli_status); found {total} construction site(s) across \
         {sites:?}. Match-arm reads (`CliStatus::Healthy => ...`) are fine anywhere; only \
         values (`Some(CliStatus::Healthy)` etc.) count against this invariant."
    );

    assert_eq!(
        sites,
        vec![(src_dir.join("model").join("state.rs"), 1)],
        "the one construction site must live in model/state.rs (parse_cli_status)"
    );
}

/// Companion no-compute check (T3/T9 fitness function): `score` is parsed —
/// it's a schema-required field on `model::doctor::DoctorWire` — but never
/// read again anywhere else in the crate. A `.score` reference outside that
/// one wire struct would be the first step toward a computed health score,
/// which invariant #1 forbids.
#[test]
fn score_field_is_never_read_outside_the_wire_struct() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut files = Vec::new();
    collect_rs_files(&src_dir, &mut files);

    let exempt = src_dir.join("model").join("doctor.rs");
    for file in &files {
        if *file == exempt {
            continue; // the wire struct itself is allowed to declare the field
        }
        let text =
            fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        assert!(
            !text.contains(".score"),
            "found a `.score` reference outside model/doctor.rs in {} — score must never be \
             read/computed on (invariant #1, \"parse never compute\")",
            file.display()
        );
    }
}

// ---------------------------------------------------------------------------
// T8/F2: the syn-AST-based detector. See the module doc for why this exists
// alongside (not instead of) the textual scan above.
// ---------------------------------------------------------------------------

/// Per-file `use`-import state the AST walk needs to resolve a path back to
/// `model::state::CliStatus::Healthy`: every local name that aliases
/// `CliStatus` itself (`"CliStatus"` is always present, even with no `use`
/// at all — the crate's own module always spells it that way), and whether
/// a glob import (`use ...CliStatus::*;` or `use ...state::*;`) brought the
/// bare variant names into scope.
///
/// File-global, not scope-precise (Rust's real name resolution is finer —
/// a `use` can be shadowed inside a nested block). That's a deliberate,
/// documented over-approximation: this crate's files are flat (no nested
/// `mod` blocks with their own competing `use` statements — verified against
/// the crate's actual layout), so file-global is exact for the code that
/// exists today, and erring toward over-detection (a false positive that
/// fails a build) is the safe direction for a security fitness function —
/// under-detection is the failure mode this test exists to close.
#[derive(Default)]
struct ImportState {
    cli_status_aliases: std::collections::HashSet<String>,
    glob_imported: bool,
}

fn collect_import_state(file: &syn::File) -> ImportState {
    let mut state = ImportState::default();
    state.cli_status_aliases.insert("CliStatus".to_string());
    for item in &file.items {
        if let syn::Item::Use(item_use) = item {
            walk_use_tree(&item_use.tree, &mut Vec::new(), &mut state);
        }
    }
    state
}

fn walk_use_tree(tree: &syn::UseTree, prefix: &mut Vec<String>, state: &mut ImportState) {
    match tree {
        syn::UseTree::Path(p) => {
            prefix.push(p.ident.to_string());
            walk_use_tree(&p.tree, prefix, state);
            prefix.pop();
        }
        syn::UseTree::Name(n) => {
            if n.ident == "CliStatus" {
                state.cli_status_aliases.insert(n.ident.to_string());
            }
        }
        syn::UseTree::Rename(r) => {
            if r.ident == "CliStatus" {
                state.cli_status_aliases.insert(r.rename.to_string());
            }
        }
        syn::UseTree::Glob(_) => {
            let last = prefix.last().map(String::as_str);
            if last == Some("CliStatus") || last == Some("state") {
                state.glob_imported = true;
            }
        }
        syn::UseTree::Group(g) => {
            for t in &g.items {
                walk_use_tree(t, prefix, state);
            }
        }
    }
}

/// `true` if the self-type of an `impl` block is (textually) `CliStatus` —
/// i.e. `impl CliStatus { .. }` or `impl SomeTrait for CliStatus { .. }`,
/// so `Self::Healthy` inside it resolves to the same variant.
fn impl_self_type_is_cli_status(ty: &syn::Type) -> bool {
    matches!(ty, syn::Type::Path(p) if p.path.segments.last().is_some_and(|s| s.ident == "CliStatus"))
}

/// Visits every genuine expression-position path in the file — NEVER a
/// pattern (`syn::Pat`) — so a match arm or a `matches!(x, Self::Healthy)`
/// guard structurally cannot be miscounted as a construction; syn simply
/// never calls `visit_expr_path` for those, no adjacency heuristic required.
struct HealthyConstructionVisitor<'a> {
    imports: &'a ImportState,
    in_cli_status_impl: bool,
    /// One human-readable `path::segments` string per construction found.
    hits: Vec<String>,
}

impl<'a> HealthyConstructionVisitor<'a> {
    fn path_constructs_healthy(&self, path: &syn::Path) -> bool {
        let Some(last) = path.segments.last() else {
            return false;
        };
        if last.ident != "Healthy" {
            return false;
        }
        match path.segments.len() {
            // A bare `Healthy` — only a construction if a glob import
            // brought the variant names into scope.
            1 => self.imports.glob_imported,
            _ => {
                let head = &path.segments[path.segments.len() - 2].ident;
                (self.in_cli_status_impl && head == "Self")
                    || self.imports.cli_status_aliases.contains(&head.to_string())
            }
        }
    }
}

impl<'a, 'ast> syn::visit::Visit<'ast> for HealthyConstructionVisitor<'a> {
    fn visit_item_mod(&mut self, node: &'ast syn::ItemMod) {
        // Same "test code isn't the invariant under test" exclusion as the
        // textual scan — don't descend into `#[cfg(test)] mod ... { .. }`.
        let is_cfg_test = node.attrs.iter().any(|a| {
            a.path().is_ident("cfg") && a.parse_args::<syn::Ident>().is_ok_and(|i| i == "test")
        });
        if !is_cfg_test {
            syn::visit::visit_item_mod(self, node);
        }
    }

    fn visit_item_impl(&mut self, node: &'ast syn::ItemImpl) {
        let prev = self.in_cli_status_impl;
        if impl_self_type_is_cli_status(&node.self_ty) {
            self.in_cli_status_impl = true;
        }
        syn::visit::visit_item_impl(self, node);
        self.in_cli_status_impl = prev;
    }

    /// Deliberately a no-op — does NOT call `syn::visit::visit_pat`, so this
    /// visitor never descends into ANY pattern subtree (match arms, `if
    /// let`/`while let`, parameter bindings). This is load-bearing, not an
    /// optimization: syn 2.x's grammar type-aliases several `Pat` variants
    /// directly onto their `Expr` counterparts (`Pat::Path` IS an
    /// `ExprPath`, `Pat::Const`/`Pat::Lit`/`Pat::Macro`/`Pat::Range` are
    /// their `Expr` equivalents too — see `syn::pat`'s re-exports and its
    /// generated `visit_pat`, which literally calls `v.visit_expr_path(..)`
    /// for `Pat::Path`). Left un-vetoed, a match arm like `Self::Healthy =>
    /// "none"` (a READ) would be indistinguishable, at the syn API level,
    /// from a real construction — the exact false-positive this rewrite
    /// exists to avoid. Patterns can never construct a value, so skipping
    /// the whole subtree is both safe and the correct fix (verified against
    /// this crate's actual match arms in `model::state::CliStatus::
    /// glyph_badge` and `render::derive::build_sentence`, both of which
    /// match on `CliStatus`/`Self` variants and must NOT count as hits).
    fn visit_pat(&mut self, _node: &'ast syn::Pat) {}

    fn visit_expr_path(&mut self, node: &'ast syn::ExprPath) {
        if self.path_constructs_healthy(&node.path) {
            let joined = node
                .path
                .segments
                .iter()
                .map(|s| s.ident.to_string())
                .collect::<Vec<_>>()
                .join("::");
            self.hits.push(joined);
        }
        syn::visit::visit_expr_path(self, node);
    }
}

#[test]
fn healthy_construction_is_syntactically_confined_to_the_one_guarded_call_site() {
    use syn::visit::Visit;

    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut files = Vec::new();
    collect_rs_files(&src_dir, &mut files);
    assert!(
        !files.is_empty(),
        "expected to find .rs files under {}",
        src_dir.display()
    );

    let mut total = 0usize;
    let mut sites: Vec<(PathBuf, usize)> = Vec::new();

    for file in &files {
        let raw =
            fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        let parsed = syn::parse_file(&raw)
            .unwrap_or_else(|e| panic!("syn::parse_file failed on {}: {e}", file.display()));
        let imports = collect_import_state(&parsed);
        let mut visitor = HealthyConstructionVisitor {
            imports: &imports,
            in_cli_status_impl: false,
            hits: Vec::new(),
        };
        visitor.visit_file(&parsed);
        if !visitor.hits.is_empty() {
            sites.push((file.clone(), visitor.hits.len()));
            total += visitor.hits.len();
        }
    }

    assert_eq!(
        total, 1,
        "AST walk found {total} construction site(s) of CliStatus::Healthy (including any \
         Self::Healthy / aliased / glob-imported spelling) across {sites:?} — expected exactly \
         one, the guarded call site in model::state::parse_cli_status. Match-arm/`matches!` \
         pattern reads are never counted (syn only visits Expr::Path here, never Pat)."
    );
    assert_eq!(
        sites,
        vec![(src_dir.join("model").join("state.rs"), 1)],
        "the one construction site must live in model/state.rs (parse_cli_status)"
    );
}
