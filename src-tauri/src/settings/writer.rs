//! Atomic, never-destroy `copilot.layers.yml` writer (M2/S2, ADR-M2-002).
//!
//! **This module persists; it computes nothing.** `write_manifest` takes the
//! layers a caller wants upserted, folds them into whatever is already on
//! disk, and writes the result — it never invents a `rank`, never resolves
//! anything, and refuses (rather than "fixes") a manifest that fails S1's
//! validator. That assembly step (deciding `rank`/`id`/`auth`) is S4,
//! decision-gated on D-1-M2; this module only knows how to persist an
//! already-valid manifest safely.
//!
//! ## Never-destroy (invariant #3) — merge by layer `id`
//!
//! The manifest may be hand-authored and carry layers or fields this app has
//! never shown in a form. So this is **read-modify-write, not
//! serialize-and-overwrite**: every layer in `incoming` is upserted into the
//! on-disk manifest by `id` (replace the whole layer if the id already
//! exists, append it if it doesn't); every on-disk layer whose `id` isn't in
//! `incoming` is carried forward **unchanged**, `extra` fields and all,
//! because it was never re-serialized through a struct that dropped them
//! (that's what S1's `#[serde(flatten)] extra` groundwork is for). Top-level
//! `version`/`extra` are preserved the same way — `incoming` only overrides
//! what it actually sets.
//!
//! ## Atomic (crash-safe)
//!
//! `atomic_write` writes the new content to a temp file **in the same
//! directory** as the target (so the final `rename` is same-filesystem and
//! therefore atomic on every platform this app targets), `fsync`s it, then
//! `rename`s it over the target. A crash or kill at any point before the
//! rename leaves the original manifest exactly as it was; a crash after the
//! rename leaves the new manifest exactly as intended. There is no window in
//! which the target is truncated, partially written, or missing.
//!
//! ## Fail-closed validation
//!
//! The **merged** manifest (not just the incoming edit) is run through
//! `settings::validate::validate_layers` before anything touches disk. An
//! edit that would make the whole manifest invalid (e.g. a duplicate rank
//! against an untouched layer) is refused wholesale — this module never
//! writes a manifest it knows to be broken, and never partially applies an
//! edit.

use std::io::Write as _;
use std::path::{Path, PathBuf};

use super::manifest::{parse_manifest, to_yaml_string, Layer, LayerManifest};
use super::validate::{validate_layers, FieldError};

/// D-3-M2: default manifest location for a solo/unmanaged user —
/// `~/.copilot/copilot.layers.yml`, alongside `~/.copilot/manifest.local.yml`
/// (ecosystem-architecture §3.3). Callers that don't have a more specific
/// path (S6) should ask for this one. Returns `None` only when `$HOME` isn't
/// set at all (never guesses a fallback location).
pub fn default_manifest_path() -> Option<PathBuf> {
    std::env::var_os("HOME").map(|home| {
        PathBuf::from(home)
            .join(".copilot")
            .join("copilot.layers.yml")
    })
}

/// What `write_manifest` did, in counts a caller can render honestly
/// ("updated 1 layer, left 3 untouched") without needing to diff the
/// manifest itself.
#[derive(Debug, Clone, PartialEq)]
pub struct WriteReport {
    pub path: PathBuf,
    /// Layers in `incoming` whose `id` did not already exist on disk.
    pub layers_added: usize,
    /// Layers in `incoming` whose `id` matched an existing layer (that
    /// layer's whole entry was replaced).
    pub layers_updated: usize,
    /// On-disk layers not present in `incoming` — carried forward verbatim.
    pub layers_preserved: usize,
}

/// Why `write_manifest` refused to write, or failed while trying. Every
/// message is plain language — no raw io/serde/yaml text ever reaches a
/// caller (SOUL "a Git error to a non-technical person"), matching
/// `settings::validate`'s and `settings::manifest`'s discipline.
#[derive(Debug, Clone, PartialEq)]
pub enum WriteError {
    /// The merged manifest fails S1's validator — refused before any write
    /// happens (fail closed). Carries every problem found, same shape a
    /// Settings form would show.
    Invalid(Vec<FieldError>),
    /// A filesystem problem: couldn't read the existing manifest, couldn't
    /// create the parent directory, couldn't write/fsync/rename the temp
    /// file, or the existing on-disk file isn't valid YAML at all. The
    /// message is already plain language; never propagate the underlying
    /// `std::io::Error`/`serde_yaml` text past this point.
    Io(String),
}

impl std::fmt::Display for WriteError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WriteError::Invalid(errors) => {
                write!(f, "This manifest can't be saved yet — ")?;
                let messages: Vec<&str> = errors.iter().map(|e| e.message.as_str()).collect();
                write!(f, "{}", messages.join(" "))
            }
            WriteError::Io(message) => write!(f, "{message}"),
        }
    }
}

impl std::error::Error for WriteError {}

/// Reads whatever is at `path` (or starts from an empty manifest if nothing
/// is there yet), upserts every layer in `incoming` by `id`, validates the
/// merged result, and — only if that passes — writes it atomically. Never
/// touches `path` at all if validation fails.
pub fn write_manifest(path: &Path, incoming: &LayerManifest) -> Result<WriteReport, WriteError> {
    let existing = read_existing(path)?;
    let (merged, layers_added, layers_updated, layers_preserved) = merge_by_id(existing, incoming);

    let errors = validate_layers(&merged);
    if !errors.is_empty() {
        return Err(WriteError::Invalid(errors));
    }

    let yaml = to_yaml_string(&merged).map_err(|e| WriteError::Io(e.message))?;
    atomic_write(path, yaml.as_bytes())?;

    Ok(WriteReport {
        path: path.to_path_buf(),
        layers_added,
        layers_updated,
        layers_preserved,
    })
}

/// `Ok(LayerManifest::default())` when nothing exists at `path` yet (a fresh
/// write) — never an error, since "the file doesn't exist yet" is the normal
/// first-write case, not a failure. Any other read/parse problem is a plain-
/// language `WriteError::Io`.
///
/// `pub(crate)` (M2/S6): `commands::get_settings`/`commands::save_settings`
/// reuse this exact read for the "load the current manifest, honestly empty
/// on first run" step, rather than re-implementing the same
/// not-found-is-fine / other-error-is-plain-language split a second time.
pub(crate) fn read_existing(path: &Path) -> Result<LayerManifest, WriteError> {
    match std::fs::read_to_string(path) {
        Ok(text) => parse_manifest(&text).map_err(|e| WriteError::Io(e.message)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(LayerManifest::default()),
        Err(e) => Err(WriteError::Io(format!(
            "Couldn't read the existing manifest at {}: {e}.",
            path.display()
        ))),
    }
}

/// The merge-by-`id` step (see module doc). Returns the merged manifest plus
/// `(added, updated, preserved)` counts for `WriteReport`.
///
/// `pub(crate)` (M2/S4): `settings::authoring::author_manifest` reuses this
/// SAME merge (never a second, drifting merge-by-id implementation) to build
/// the full merged view it runs the guard and S1's validator against, before
/// ever touching disk — see that module's doc.
pub(crate) fn merge_by_id(
    mut existing: LayerManifest,
    incoming: &LayerManifest,
) -> (LayerManifest, usize, usize, usize) {
    let mut added = 0usize;
    let mut updated = 0usize;

    for incoming_layer in &incoming.layers {
        let matched: Option<&mut Layer> = match incoming_layer.id.as_deref() {
            Some(id) if !id.trim().is_empty() => existing
                .layers
                .iter_mut()
                .find(|l| l.id.as_deref() == Some(id)),
            // No usable id to merge by — nothing to match, so this is always
            // an append. `validate_layers` will flag the missing id at
            // validate time (write_manifest still refuses the write); this
            // function's only job is the merge, not the semantic check.
            _ => None,
        };

        match matched {
            Some(slot) => {
                *slot = incoming_layer.clone();
                updated += 1;
            }
            None => {
                existing.layers.push(incoming_layer.clone());
                added += 1;
            }
        }
    }

    let preserved = existing.layers.len() - added - updated;

    // Top-level fields: `incoming` only overrides what it actually sets, so
    // an edit that only touches `layers` leaves `version`/`extra` exactly as
    // they were on disk.
    if incoming.version.is_some() {
        existing.version = incoming.version.clone();
    }
    for (key, value) in incoming.extra.iter() {
        existing.extra.insert(key.clone(), value.clone());
    }

    (existing, added, updated, preserved)
}

/// temp-file-in-same-dir + fsync + rename (see module doc's "Atomic"
/// section). Cleans up the temp file on any failure along the way so a
/// failed write never leaves stray `.tmp-*` files behind.
fn atomic_write(target: &Path, bytes: &[u8]) -> Result<(), WriteError> {
    let parent = target
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .ok_or_else(|| WriteError::Io("The manifest path has no parent directory.".to_string()))?;

    std::fs::create_dir_all(parent).map_err(|e| {
        WriteError::Io(format!(
            "Couldn't create the folder {} to save the manifest in: {e}.",
            parent.display()
        ))
    })?;

    let temp_path = unique_temp_path(parent, target);

    let write_result = (|| -> std::io::Result<()> {
        let mut file = std::fs::File::create(&temp_path)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        Ok(())
    })();

    if let Err(e) = write_result {
        let _ = std::fs::remove_file(&temp_path);
        return Err(WriteError::Io(format!(
            "Couldn't save the manifest safely: {e}."
        )));
    }

    if let Err(e) = std::fs::rename(&temp_path, target) {
        let _ = std::fs::remove_file(&temp_path);
        return Err(WriteError::Io(format!(
            "Couldn't finish saving the manifest: {e}."
        )));
    }

    // Best-effort: fsync the parent directory so the rename itself is
    // durable across a crash (POSIX doesn't guarantee a rename survives a
    // crash until the containing directory is fsync'd too). The file the
    // user can already see on disk is unaffected either way, so this isn't
    // a hard error.
    #[cfg(unix)]
    {
        if let Ok(dir) = std::fs::File::open(parent) {
            let _ = dir.sync_all();
        }
    }

    Ok(())
}

/// A same-directory temp filename that can't collide with a concurrent
/// writer or a concurrent test run — `.{name}.tmp-{pid}-{tid}` — and is
/// visually distinguishable (leading dot) from the real manifest.
fn unique_temp_path(parent: &Path, target: &Path) -> PathBuf {
    let file_name = target
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("copilot.layers.yml");
    parent.join(format!(
        ".{file_name}.tmp-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    /// A fresh, isolated temp directory per call — never the real
    /// `~/.copilot`. Nothing in this module ever touches a caller-chosen
    /// `HOME`; tests always pass an explicit path under here.
    fn temp_dir() -> PathBuf {
        let n = DIR_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "ct-writer-test-{}-{:?}-{n}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).expect("create temp test dir");
        dir
    }

    fn fixture_text(name: &str) -> String {
        let path = format!("{}/fixtures/settings/{name}", env!("CARGO_MANIFEST_DIR"));
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"))
    }

    fn fixture_manifest(name: &str) -> LayerManifest {
        parse_manifest(&fixture_text(name)).unwrap_or_else(|e| panic!("parse {name}: {e}"))
    }

    fn dir_entries(dir: &Path) -> Vec<String> {
        std::fs::read_dir(dir)
            .expect("read temp dir")
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect()
    }

    #[test]
    fn writing_a_fresh_manifest_reports_every_layer_as_added() {
        let dir = temp_dir();
        let target = dir.join("copilot.layers.yml");
        let incoming = fixture_manifest("valid-multi-layer.yml");

        let report = write_manifest(&target, &incoming).expect("should write");

        assert_eq!(report.path, target);
        assert_eq!(report.layers_added, 4);
        assert_eq!(report.layers_updated, 0);
        assert_eq!(report.layers_preserved, 0);

        let on_disk = parse_manifest(&std::fs::read_to_string(&target).unwrap()).unwrap();
        assert_eq!(on_disk.layers.len(), 4);
        assert!(validate_layers(&on_disk).is_empty());

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Never-destroy (ADR-M2-002): editing ONE layer must not disturb any
    /// other layer, including a field this app doesn't model (`notes:` on
    /// `dept-engineering`, S1's `extra` groundwork).
    #[test]
    fn editing_one_layer_preserves_every_other_layer_and_its_unknown_fields() {
        let dir = temp_dir();
        let target = dir.join("copilot.layers.yml");
        let original = fixture_manifest("valid-multi-layer.yml");
        write_manifest(&target, &original).expect("first write should succeed");

        // Edit only `personal-pablo`'s repo — a full, valid replacement
        // layer (S2 upserts whole layers; deciding *how* a partial UI edit
        // becomes a full layer is S4's job, not this module's).
        let mut edited_personal = original
            .layers
            .iter()
            .find(|l| l.id.as_deref() == Some("personal-pablo"))
            .cloned()
            .expect("fixture has personal-pablo");
        edited_personal.source.as_mut().unwrap().repo =
            Some("git@github-personal:pablitoalejo/renamed-repo.git".to_string());

        let incoming = LayerManifest {
            version: None, // untouched — must not clobber the on-disk `version: 1`.
            layers: vec![edited_personal.clone()],
            extra: Default::default(),
        };

        let report = write_manifest(&target, &incoming).expect("edit should succeed");
        assert_eq!(report.layers_added, 0);
        assert_eq!(report.layers_updated, 1);
        assert_eq!(report.layers_preserved, 3);

        let on_disk = parse_manifest(&std::fs::read_to_string(&target).unwrap()).unwrap();
        assert_eq!(
            on_disk.version, original.version,
            "top-level version must survive an untouched edit"
        );
        assert_eq!(on_disk.layers.len(), 4);

        let updated = on_disk
            .layers
            .iter()
            .find(|l| l.id.as_deref() == Some("personal-pablo"))
            .unwrap();
        assert_eq!(
            updated.source.as_ref().unwrap().repo.as_deref(),
            Some("git@github-personal:pablitoalejo/renamed-repo.git")
        );

        for id in ["dept-engineering", "org-acme", "foundation"] {
            let before = original
                .layers
                .iter()
                .find(|l| l.id.as_deref() == Some(id))
                .unwrap();
            let after = on_disk
                .layers
                .iter()
                .find(|l| l.id.as_deref() == Some(id))
                .unwrap();
            assert_eq!(
                before, after,
                "layer {id:?} must be preserved verbatim, including unknown fields"
            );
        }
        let dept = on_disk
            .layers
            .iter()
            .find(|l| l.id.as_deref() == Some("dept-engineering"))
            .unwrap();
        assert!(
            dept.extra.contains_key("notes"),
            "the hand-authored `notes` field must survive an unrelated edit"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn write_leaves_no_temp_file_behind_and_the_target_is_valid() {
        let dir = temp_dir();
        let target = dir.join("copilot.layers.yml");
        let incoming = fixture_manifest("valid-multi-layer.yml");

        write_manifest(&target, &incoming).expect("should write");

        let entries = dir_entries(&dir);
        assert_eq!(
            entries,
            vec!["copilot.layers.yml".to_string()],
            "no stray temp file should remain: {entries:?}"
        );

        let on_disk = parse_manifest(&std::fs::read_to_string(&target).unwrap()).unwrap();
        assert!(
            validate_layers(&on_disk).is_empty(),
            "target must be a valid manifest after write"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_invalid_merged_manifest_is_refused_and_never_written() {
        let dir = temp_dir();
        let target = dir.join("copilot.layers.yml");
        let incoming = fixture_manifest("invalid-missing-required-field.yml");

        let result = write_manifest(&target, &incoming);

        assert!(matches!(result, Err(WriteError::Invalid(_))));
        assert!(
            !target.exists(),
            "an invalid manifest must never be written at all"
        );
        assert!(
            dir_entries(&dir).is_empty(),
            "no temp file should be left behind by a refused write either"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Fail closed AND never-destroy: an edit that breaks validation must
    /// leave a pre-existing valid manifest exactly as it was, not half-merged
    /// on disk.
    #[test]
    fn a_refused_edit_leaves_the_existing_manifest_untouched() {
        let dir = temp_dir();
        let target = dir.join("copilot.layers.yml");
        let original = fixture_manifest("valid-multi-layer.yml");
        write_manifest(&target, &original).expect("first write should succeed");
        let before = std::fs::read_to_string(&target).unwrap();

        // Duplicate rank 10 against the untouched `personal-pablo` layer.
        let mut colliding = original.layers[1].clone(); // dept-engineering
        colliding.rank = Some(serde_yaml::Value::Number(10.into()));
        let incoming = LayerManifest {
            version: None,
            layers: vec![colliding],
            extra: Default::default(),
        };

        let result = write_manifest(&target, &incoming);
        assert!(matches!(result, Err(WriteError::Invalid(_))));

        let after = std::fs::read_to_string(&target).unwrap();
        assert_eq!(
            before, after,
            "a refused edit must not mutate the existing on-disk manifest"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn default_manifest_path_points_under_home_dot_copilot() {
        if let Some(path) = default_manifest_path() {
            assert!(path.ends_with("copilot.layers.yml"));
            assert!(path.to_string_lossy().contains(".copilot"));
        }
    }

    /// A plain-language `Display` — no raw serde/yaml/io jargon leaks past
    /// `WriteError`, mirroring `settings::validate`'s discipline.
    #[test]
    fn write_error_display_is_plain_language() {
        let dir = temp_dir();
        let target = dir.join("copilot.layers.yml");
        let incoming = fixture_manifest("invalid-duplicate-rank.yml");
        let err = write_manifest(&target, &incoming).unwrap_err();
        let message = err.to_string();
        let banned = ["yaml", "serde", "traceback", "panicked", "unwrap", "Err("];
        let lower = message.to_lowercase();
        for term in banned {
            assert!(
                !lower.contains(&term.to_lowercase()),
                "message leaks jargon {term:?}: {message}"
            );
        }
        let _ = std::fs::remove_dir_all(&dir);
    }
}
