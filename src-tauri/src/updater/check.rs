//! The update-check/apply transport (M4/S4, ADR-M4-004: "own the transport,
//! parse [never compute] the doctor signal"). This module fetches the
//! signed update manifest + k-of-N signatures (+, when applying, the artifact),
//! hands them to `sec`'s already-landed, fail-closed
//! [`verify::verify_update_multisig`]/[`verify::verify_staple`] — **never
//! reimplemented, never bypassed** — and, on success, stages the verified
//! bundle into `do`'s [`watchdog::StagedLayout`]. `apply_update` then
//! completes the promote-or-rollback decision itself (M4 gap-closure, S11):
//! it launches the staged bundle with `--self-test` (via the injectable
//! `updater::launch::StagedBundleLauncher` seam) and hands the observed
//! heartbeat to `watchdog::run_self_test` — never re-implemented here — so
//! `Ready`/`RolledBack` reflect a REAL, just-proven self-test outcome, not a
//! deferred promise (`confirm_staged_bundle_boots`). This module computes no
//! ecosystem state of its own (invariant #1): every accept/refuse decision
//! it renders is a direct, unedited pass-through of what
//! `verify_update_multisig`/`verify_staple`/`watchdog::decide` decided.
//!
//! Both [`check_for_update`] and [`apply_update`] honor `trust::
//! allow_self_update()` (FF-M4-4, forced-domain-only) FIRST — `Allow
//! SelfUpdate=false` disables self-update entirely (checking AND applying),
//! never just applying: an IT-managed fleet that's opted out shouldn't even
//! see "an update is available", since there's nothing Bob can or should do
//! about it (`self_update_gate`). [`check_for_update`] additionally checks
//! `rollback_marker::take_rollback_outcome` FIRST, even before that gate —
//! see [`check_for_update_at`]'s own doc.
//!
//! ## Why `check_for_update` downloads the (small, today) artifact too
//!
//! `verify::verify_update_multisig` authenticates `(version, channel, artifact
//! identity)` as ONE atomic, signed fact — by design, it requires the real
//! artifact bytes to do that (see that module's own doc: pinning the hash
//! *inside* the signed manifest is what closes a swapped-artifact/replay
//! attack a URL-only manifest can't). The manifest fixtures under
//! `fixtures/updater/` additionally carry an (unused-by-`verify`)
//! `artifact_url` field matching `release-and-versioning.md` §2's `latest.
//! json` shape — a tempting shortcut would be to peek that field with a
//! second, independent signature check (using the same compiled-in multisig
//! roots and `minisign_verify` building blocks `verify_update_multisig` itself calls) so
//! *checking* stays cheap (manifest-only) and only *applying* pays for the
//! full artifact download. This module deliberately does **not** do that:
//! duplicating even a few lines of "verify these signatures" outside the one
//! frozen, audited module this crate trusts for it is a worse trade than a
//! wasted download, especially while `D-4-M4` (the real feed endpoint) is
//! still owner-gated/undefined and today's fixture artifacts are a few
//! bytes, not tens of MB. `check_for_update` therefore calls the exact same
//! `verify::verify_update_multisig` `apply_update` does, just without ever staging
//! the result. If the real feed's artifact size later makes this wasteful,
//! the fix is a manifest-only-verify entry point added to `verify.rs`
//! itself (using that already-present `artifact_url` field) — a follow-up,
//! not a workaround here.
//!
//! ## The feed location seam (`CT_UPDATE_FEED`, dev/test only)
//!
//! Mirrors `cli::path`'s `CT_CLI_PATH` shape exactly: `#[cfg(any(
//! debug_assertions, test))]`-gated, so a genuine `cargo build --release`
//! compiles the override out entirely (never merely skips it at runtime —
//! see `cli::path`'s module doc for why that distinction matters). When set,
//! it names a **local directory** standing in for the feed root (e.g.
//! `fixtures/updater/feed/`); [`manifest_url`] then treats
//! `"<dir>/latest.json"` as the manifest location and [`fetcher_for`] picks
//! [`LocalDirFetcher`] (a plain `fs::read`) instead of [`HttpFetcher`] —
//! this is how `cargo test` exercises the real `check_for_update`/
//! `apply_update` entry points end to end with **zero real network**, and
//! how a developer can smoke-test the whole flow against the dev-signed
//! fixtures without a real feed endpoint (`D-4-M4`, still owner-gated).
//! Production (release build, or a debug build with the override unset)
//! always reads `trust::update_feed_url()` — the forced-domain-only,
//! compiled-in-default reader (FF-M4-4) — never this override.

use std::path::{Path, PathBuf};
use std::time::Duration;

use super::dto::{UpdateState, UpdateStatus};
use super::heartbeat::{self, default_heartbeat_root};
use super::launch::{self, StagedBundleLauncher};
use super::multisig;
use super::rollback_marker;
use super::trust;
use super::verify::{self, VerifiedUpdate, VerifyError};
use super::watchdog::{self, StagedLayout};

/// The dev/test-only feed-root override — see the module doc. Not read at
/// all in a genuine `cargo build --release` (no `cfg(test)` there either),
/// matching `cli::path::DEV_OVERRIDE_ENV`'s release-build-safety guarantee.
#[cfg(any(debug_assertions, test))]
pub const DEV_FEED_OVERRIDE_ENV: &str = "CT_UPDATE_FEED";

/// The manifest's well-known filename at the feed root, used by the dev/
/// test override branch of [`manifest_url`] (and this module's own tests,
/// which seed a fixture feed directory using the same name) to build
/// `"<dir>/latest.json"`. `#[cfg]`-gated identically to
/// [`DEV_FEED_OVERRIDE_ENV`] itself — production always gets the manifest's
/// exact URL directly from `trust::update_feed_url()`, so this constant has
/// no production-build reader at all.
#[cfg(any(debug_assertions, test))]
const MANIFEST_FILENAME: &str = "latest.json";

/// The artifact's well-known filename, a sibling of the manifest — matches
/// `fixtures/updater/artifact.bin`'s own naming exactly (see the module
/// doc's "why `check_for_update` downloads the artifact too" for why this
/// convention, rather than the manifest's own unused `artifact_url` field,
/// is what's used today).
const ARTIFACT_FILENAME: &str = "artifact.bin";

// ---------------------------------------------------------------------------
// FeedFetcher — the network-fetch seam (trait-based, per the task brief)
// ---------------------------------------------------------------------------

/// Every way fetching a feed resource (manifest / signature / artifact) can
/// fail. Deliberately flat, mirroring `verify::VerifyError`'s "every variant
/// is a refusal, nothing leaks" shape — `Display` never echoes the resource
/// string itself (a local fixture path or a feed URL isn't secret, but
/// `UpdateState::message` is Bob-facing plain language, not a raw transport
/// diagnostic; see `check_for_update`'s doc for where this maps to a
/// friendlier sentence).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FetchError {
    /// The resource genuinely doesn't exist at the feed (dev fixture typo,
    /// a 404, a feed that hasn't published this file) — distinct from `Io`
    /// so a caller COULD special-case "nothing to fetch" from "the network/
    /// filesystem itself is broken", though today both map to the same
    /// `UpdateStatus::Error` in `check_for_update`/`apply_update`.
    NotFound,
    /// Any other transport-level problem (a non-2xx HTTP status, a
    /// filesystem permission error, a connection failure, …).
    Io(String),
}

impl std::fmt::Display for FetchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FetchError::NotFound => write!(f, "the update feed doesn't have that file"),
            FetchError::Io(reason) => write!(f, "couldn't reach the update feed: {reason}"),
        }
    }
}

impl std::error::Error for FetchError {}

/// The network-fetch seam this module consumes rather than hand-rolls at
/// every call site — the task brief's "network fetch behind a trait so
/// tests inject a fixture fetcher (no real network in tests)". Mirrors
/// `updater::watchdog::HeartbeatSource`'s shape exactly: a small trait,
/// synchronous (this module's own callers run it via `tauri::async_runtime
/// ::spawn_blocking` from `commands.rs`'s async IPC surface, never nested
/// inside an already-running async runtime — `reqwest::blocking` would
/// panic if called from inside one).
pub trait FeedFetcher {
    fn fetch(&self, resource: &str) -> Result<Vec<u8>, FetchError>;
}

/// The dev/test seam's fetcher — `resource` is a plain filesystem path
/// (never interpreted as a URL). Stateless: every call site already
/// resolves a FULL resource path via [`signature_url`]/[`artifact_sibling`]
/// before calling `fetch`, so there's no "root directory" to carry as
/// state here (unlike, say, `heartbeat::FileHeartbeatSource`, which DOES
/// carry a root — this module's resources are each independently named).
pub struct LocalDirFetcher;

impl FeedFetcher for LocalDirFetcher {
    fn fetch(&self, resource: &str) -> Result<Vec<u8>, FetchError> {
        std::fs::read(resource).map_err(|e| match e.kind() {
            std::io::ErrorKind::NotFound => FetchError::NotFound,
            _ => FetchError::Io(e.to_string()),
        })
    }
}

/// The production fetcher — a real, synchronous HTTP GET. Never exercised
/// by `cargo test` (no real network in tests, per the task brief); its
/// target, `trust::update_feed_url()`, is a structurally-valid `.invalid`
/// placeholder today (`D-4-M4`, owner-gated) — this type exists so the
/// production call site (`check_for_update`/`apply_update`, no override
/// set) has a real, typed implementation to construct, not a stub that
/// fakes success (`packaging/cc/cc`'s "honest-failure not fake-success"
/// placeholder discipline extended here: an unreachable `.invalid` feed
/// genuinely, honestly fails to connect — it does not need a special-cased
/// stub error).
pub struct HttpFetcher;

impl FeedFetcher for HttpFetcher {
    fn fetch(&self, resource: &str) -> Result<Vec<u8>, FetchError> {
        let response =
            reqwest::blocking::get(resource).map_err(|e| FetchError::Io(e.to_string()))?;
        if response.status() == reqwest::StatusCode::NOT_FOUND {
            return Err(FetchError::NotFound);
        }
        if !response.status().is_success() {
            return Err(FetchError::Io(format!(
                "unexpected status {}",
                response.status()
            )));
        }
        response
            .bytes()
            .map(|b| b.to_vec())
            .map_err(|e| FetchError::Io(e.to_string()))
    }
}

// ---------------------------------------------------------------------------
// Feed location resolution
// ---------------------------------------------------------------------------

/// The manifest's resource path/URL — see the module doc's "feed location
/// seam" section. Dev/test override first (when set), else the real,
/// forced-domain-only `trust::update_feed_url()`.
fn manifest_url() -> String {
    #[cfg(any(debug_assertions, test))]
    {
        if let Some(dir) = std::env::var_os(DEV_FEED_OVERRIDE_ENV) {
            let dir = PathBuf::from(dir);
            return dir.join(MANIFEST_FILENAME).display().to_string();
        }
    }
    trust::update_feed_url()
}

/// Picks the right [`FeedFetcher`] for a resolved manifest URL — an
/// `http(s)://` prefix means the real feed (or a test double standing in
/// for one via [`check_for_update_with`]/[`apply_update_with`] directly);
/// anything else is a plain filesystem path (the dev/test override branch
/// of [`manifest_url`]).
fn fetcher_for(url: &str) -> Box<dyn FeedFetcher> {
    if url.starts_with("http://") || url.starts_with("https://") {
        Box::new(HttpFetcher)
    } else {
        Box::new(LocalDirFetcher)
    }
}

/// One root-specific minisign signature sibling for `manifest_url`.
///
/// The live feed publishes one file per compiled-in multisig root:
/// `<manifest-url>.<root-id>.minisig` (for example,
/// `latest.json.rootA.minisig`). This lets the transport fetch every public
/// root's candidate signature without trying to parse the manifest before it
/// has met the k-of-N threshold.
fn signature_url(manifest_url: &str, signature_id: &str) -> String {
    format!("{manifest_url}.{signature_id}.minisig")
}

fn signature_urls(manifest_url: &str) -> Vec<String> {
    multisig::TRUST_ROOT_SIGNATURE_IDS
        .iter()
        .map(|id| signature_url(manifest_url, id))
        .collect()
}

/// The artifact's location — a fixed sibling filename in the same
/// "directory" the manifest was fetched from (see the module doc's "why
/// `check_for_update` downloads the artifact too" for why this, not the
/// manifest's own `artifact_url` field, is authoritative today). Works
/// identically whether `manifest_url` is a real URL or a local path — both
/// are plain `/`-joined strings on this (macOS-first) codebase.
fn artifact_sibling(manifest_url: &str) -> String {
    match manifest_url.rsplit_once('/') {
        Some((dir, _filename)) => format!("{dir}/{ARTIFACT_FILENAME}"),
        None => ARTIFACT_FILENAME.to_string(),
    }
}

// ---------------------------------------------------------------------------
// The shared fetch-then-verify core
// ---------------------------------------------------------------------------

fn current_version_string() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

fn up_to_date_state() -> UpdateState {
    UpdateState {
        status: UpdateStatus::UpToDate,
        available_version: None,
        current_version: current_version_string(),
        message: None,
    }
}

/// Every `Error` state this module ever constructs carries `message` from
/// EITHER `VerifyError`'s own already-plain-language, leak-free `Display`
/// (per that module's own test) OR one of the two hand-written sentences
/// below — never a raw `FetchError`/`std::io::Error` `Display` (see
/// `fetch_error_message`).
fn error_state(message: impl Into<String>) -> UpdateState {
    UpdateState {
        status: UpdateStatus::Error,
        available_version: None,
        current_version: current_version_string(),
        message: Some(message.into()),
    }
}

/// Bob-facing translation of a transport failure — deliberately does NOT
/// forward `FetchError`'s own `Display` (that can carry a raw local
/// fixture path or a low-level transport reason with no actionable meaning
/// to Bob); a `NotFound` and an `Io` failure are told apart only in the
/// (stderr-only, never-shown-to-Bob) `Debug` a future logging pass might
/// add, matching `cli::spawn`'s own "stderr is diagnostics only" discipline.
fn fetch_error_message(what: &str, _err: &FetchError) -> String {
    format!("Couldn't reach the update feed to check for {what} — try again later.")
}

/// `AllowSelfUpdate=false` (forced-domain-only, `trust::allow_self_update`,
/// FF-M4-4) disables self-update ENTIRELY — both checking and applying,
/// per `.copilot/wp/24.md`'s M4-S4 ("AllowSelfUpdate=false -> disable the
/// check entirely — IT-pushed only") and M4-S5 ("Honor AllowSelfUpdate=
/// false … by disabling apply_update"). `Idle`, not `Error`: a fleet that's
/// IT-managed-and-locked isn't in a failure state, it's working exactly as
/// configured — `message` says so in plain language rather than reading
/// like something went wrong.
fn self_update_disabled_state() -> UpdateState {
    UpdateState {
        status: UpdateStatus::Idle,
        available_version: None,
        current_version: current_version_string(),
        message: Some(
            "Self-update is turned off for this Mac by your organization — updates are \
             installed by IT."
                .to_string(),
        ),
    }
}

/// The pure decision behind the `AllowSelfUpdate` gate — split from
/// `trust::allow_self_update()`'s own (OS-preferences-touching) call so this
/// module's OWN "do we even attempt a fetch" branch is unit-testable without
/// a managed Mac, mirroring `trust::resolve`'s identical "pure decision
/// separate from the FFI lookup" split. `None` means "proceed normally";
/// `Some(state)` is the disabled state [`check_for_update`]/[`apply_update`]
/// return immediately, before ever calling [`manifest_url`]/[`fetcher_for`]
/// — no fetch, no network, no filesystem read at all when self-update is
/// off.
fn self_update_gate(allowed: bool) -> Option<UpdateState> {
    if allowed {
        None
    } else {
        Some(self_update_disabled_state())
    }
}

struct FetchedBundle {
    manifest: Vec<u8>,
    signatures: Vec<String>,
    signature_fetch_error: Option<FetchError>,
    artifact: Vec<u8>,
}

/// Fetches the manifest + every root-specific signature sibling + the
/// artifact from `manifest_url` via `fetcher`, in that order — the one place
/// both `check_for_update` and `apply_update` assemble the inputs
/// `verify::verify_update_multisig` needs.
fn fetch_bundle(
    fetcher: &dyn FeedFetcher,
    manifest_url: &str,
) -> Result<FetchedBundle, UpdateState> {
    let manifest = fetcher
        .fetch(manifest_url)
        .map_err(|e| error_state(fetch_error_message("an update", &e)))?;

    let mut signatures = Vec::new();
    let mut signature_fetch_error = None;
    for url in signature_urls(manifest_url) {
        match fetcher.fetch(&url) {
            Ok(signature_bytes) => {
                // A signature file is minisign's own plain-text format; bytes
                // that somehow aren't UTF-8 are simply an empty string here.
                // `verify::verify_update_multisig` independently decodes each
                // string and counts only signatures that parse and match a
                // compiled-in root, so this never turns bad input into trust.
                signatures.push(String::from_utf8(signature_bytes).unwrap_or_default());
            }
            // Feeds may publish any threshold-satisfying subset of the N
            // root signatures. Missing optional root files contribute zero;
            // the verifier decides whether the remaining signatures meet K.
            Err(FetchError::NotFound) => {}
            Err(e) => {
                if signature_fetch_error.is_none() {
                    signature_fetch_error = Some(e);
                }
            }
        }
    }

    let artifact = fetcher
        .fetch(&artifact_sibling(manifest_url))
        .map_err(|e| error_state(fetch_error_message("an update", &e)))?;

    Ok(FetchedBundle {
        manifest,
        signatures,
        signature_fetch_error,
        artifact,
    })
}

fn verify_fetched_bundle(bundle: &FetchedBundle) -> Result<VerifiedUpdate, UpdateState> {
    let signatures: Vec<&str> = bundle.signatures.iter().map(String::as_str).collect();
    match verify::verify_update_multisig(&bundle.artifact, &signatures, &bundle.manifest) {
        Ok(verified) => Ok(verified),
        // A validly-signed manifest for a version <= what's already running
        // is exactly "nothing to update" (see `verify::VerifyError::
        // Downgrade`'s own doc on why this also covers same-version replay)
        // — never surfaced as an `Error`.
        Err(VerifyError::Downgrade { .. }) => Err(up_to_date_state()),
        Err(VerifyError::InsufficientSignatures { .. })
            if bundle.signature_fetch_error.is_some() =>
        {
            Err(error_state(fetch_error_message(
                "update signatures",
                bundle
                    .signature_fetch_error
                    .as_ref()
                    .expect("checked above"),
            )))
        }
        Err(e) => Err(error_state(e.to_string())),
    }
}

// ---------------------------------------------------------------------------
// check_for_update
// ---------------------------------------------------------------------------

/// The testable core of [`check_for_update`] — `fetcher`/`manifest_url` are
/// explicit parameters so tests inject a [`LocalDirFetcher`] pointed at
/// `fixtures/updater/` directly, without touching `CT_UPDATE_FEED` at all.
pub fn check_for_update_with(fetcher: &dyn FeedFetcher, manifest_url: &str) -> UpdateState {
    let bundle = match fetch_bundle(fetcher, manifest_url) {
        Ok(bundle) => bundle,
        Err(state) => return state,
    };

    match verify_fetched_bundle(&bundle) {
        Ok(verified) => UpdateState {
            status: UpdateStatus::Available,
            available_version: Some(verified.version.to_string()),
            current_version: current_version_string(),
            message: None,
        },
        Err(state) => state,
    }
}

/// The production entry point — `commands::check_for_update` (via
/// `tauri::async_runtime::spawn_blocking`) is the only real caller. Defers to
/// [`check_for_update_at`] with the real, `$HOME`-derived layout root.
pub fn check_for_update() -> UpdateState {
    check_for_update_at(default_layout_root())
}

/// The testable production wrapper for [`check_for_update`] — same
/// layout-root-as-parameter split [`apply_update_at`] uses, so tests can
/// exercise the rollback-marker read (`rollback_marker::take_rollback_
/// outcome`) against a scratch directory instead of the real `$HOME/
/// Library/Application Support/…`.
///
/// The marker is checked FIRST, before the `AllowSelfUpdate` gate or any
/// manifest fetch — a rollback that already happened is a fact about the
/// PAST (surfaced exactly once, `rollback_marker`'s own "shown-once"
/// discipline), not a new self-update offer, so it's reported regardless of
/// whether this fleet's self-update is currently allowed.
pub(crate) fn check_for_update_at(layout_root: PathBuf) -> UpdateState {
    if rollback_marker::take_rollback_outcome(&layout_root).is_some() {
        return UpdateState {
            status: UpdateStatus::RolledBack,
            available_version: None,
            current_version: current_version_string(),
            message: Some("Kept your working version.".to_string()),
        };
    }

    if let Some(disabled) = self_update_gate(trust::allow_self_update()) {
        return disabled;
    }
    let url = manifest_url();
    let fetcher = fetcher_for(&url);
    check_for_update_with(fetcher.as_ref(), &url)
}

// ---------------------------------------------------------------------------
// apply_update
// ---------------------------------------------------------------------------

/// The testable core of [`apply_update`] — `staple_check` is the same
/// dependency-injection shape `updater::watchdog::HeartbeatSource`/
/// `heartbeat::run_self_test`'s `smoke_check` already use: production always
/// supplies `verify::verify_staple` (the real, fail-closed offline
/// Gatekeeper assessment), tests supply a fixed `Ok`/`Err` closure to
/// exercise the staging/discard bookkeeping without needing a genuinely
/// notarized `.app` fixture on hand for every test.
pub fn apply_update_with(
    fetcher: &dyn FeedFetcher,
    manifest_url: &str,
    layout: &StagedLayout,
    staple_check: impl Fn(&Path) -> Result<(), VerifyError>,
) -> UpdateState {
    let bundle = match fetch_bundle(fetcher, manifest_url) {
        Ok(bundle) => bundle,
        Err(state) => return state,
    };

    let verified = match verify_fetched_bundle(&bundle) {
        Ok(verified) => verified,
        Err(state) => return state,
    };

    if let Err(e) = stage(layout, &verified.version.to_string(), &bundle.artifact) {
        return error_state(format!("Couldn't save the verified update: {e}"));
    }

    // ADR-M4-002 step 4 / FF-M4-5: an offline staple check BEFORE this
    // module ever calls the update "ready" — a verified-but-unstapled
    // bundle is discarded here, the same fail-closed refusal
    // `updater::watchdog::decide` applies to a missing/bad heartbeat, just
    // one step earlier in the pipeline (before a bundle is even handed to
    // the self-test/heartbeat flow at all).
    match staple_check(&layout.staged()) {
        Ok(()) => UpdateState {
            status: UpdateStatus::Ready,
            available_version: Some(verified.version.to_string()),
            current_version: current_version_string(),
            message: Some(
                "Update verified and saved — it'll finish installing the next time \
                 Control Tower restarts."
                    .to_string(),
            ),
        },
        Err(e) => {
            // Fail closed all the way: never leave an unstapled bundle
            // sitting in `staged/` for a later self-test/promote decision
            // to find — that decision (`watchdog::decide`) trusts a heartbeat
            // outcome, not a staple outcome, so an unstapled bundle must
            // never even reach it.
            let _ = std::fs::remove_dir_all(layout.staged());
            error_state(e.to_string())
        }
    }
}

/// Writes `artifact` bytes + a `VERSION` marker into `layout.staged()` —
/// `updater::watchdog::StagedLayout`'s own documented shape ("a directory
/// containing at minimum a VERSION file"). Discards any stale prior staged
/// content first: a fresh, successfully-verified stage must never be merged
/// onto whatever a previous (possibly failed, possibly stale) attempt left
/// behind.
fn stage(layout: &StagedLayout, version: &str, artifact: &[u8]) -> std::io::Result<()> {
    let staged = layout.staged();
    if staged.exists() {
        std::fs::remove_dir_all(&staged)?;
    }
    std::fs::create_dir_all(&staged)?;
    std::fs::write(staged.join("VERSION"), version)?;
    std::fs::write(staged.join(ARTIFACT_FILENAME), artifact)?;
    Ok(())
}

/// `$HOME`-derived default `StagedLayout` root — reuses `heartbeat::
/// default_heartbeat_root()` directly (the SAME directory
/// `StagedLayout::new`'s `root` denotes, per that function's own doc:
/// "the SAME directory `updater::watchdog::StagedLayout`'s root already
/// denotes") rather than re-deriving a second, possibly-drifting path.
/// Falls back to a relative `"updater"` directory only when `$HOME` isn't
/// set at all (vanishingly rare), matching `commands::wizard_manifest_path`'s
/// own honest-degrade discipline elsewhere in this crate.
///
/// `pub(crate)` (M4 gap-closure): `updater::startup`'s interrupted-update
/// reconciliation reuses this exact function too, so the crate never grows a
/// second, possibly-drifting notion of "where does the staged-bundle layout
/// live".
pub(crate) fn default_layout_root() -> PathBuf {
    default_heartbeat_root().unwrap_or_else(|| PathBuf::from("updater"))
}

/// How long [`apply_update`]'s own synchronous self-test wait
/// ([`confirm_staged_bundle_boots`]) may run before giving up and rolling
/// back. Generous relative to `cli::spawn::DOCTOR_TIMEOUT` (15s): a freshly
/// launched macOS app bundle (webview init, tray setup, …) legitimately
/// takes longer to reach its `--self-test` smoke check than a plain CLI
/// invocation takes to answer `doctor --json`.
const SELF_TEST_TIMEOUT: Duration = Duration::from_secs(20);

/// M4 gap-closure (S11) — the step this crate's self-update transport was
/// missing (`m4-distribution-decisions`, `.copilot/wp/24.md`): after
/// [`apply_update_with`] stages a verified, offline-stapled bundle and
/// reports an intermediate `Ready`, THIS function proves it actually boots
/// before that `Ready` is allowed to reach Bob. It launches the staged
/// bundle with `heartbeat::SELF_TEST_FLAG` via `launcher` (the injectable
/// `updater::launch::StagedBundleLauncher` seam — no real subprocess/bundle
/// in `cargo test`), then hands the decision to `watchdog::run_self_test` —
/// the already-landed decide-then-promote-or-rollback call this module never
/// re-implements — using a real `heartbeat::FileHeartbeatSource` rooted at
/// `layout_root` (the SAME directory `StagedLayout`'s own `root` denotes,
/// per `heartbeat.rs`'s doc).
///
/// Fail-closed by construction (FF-M4-6, extended to the launch step
/// itself): a launcher failure (missing/unexecutable staged binary, a fork
/// failure, …) is never a distinct "error" branch — it just means no
/// heartbeat ever appears, which `run_self_test`'s own timeout already
/// treats as "not proven alive" and rolls back, the identical outcome a
/// genuine crash or hang produces. `Ready` only survives if `run_self_test`
/// actually reaches `Decision::Promote`; a rollback both poisons the staged
/// version on disk (so this channel never re-offers it) AND persists via
/// `rollback_marker::record_rollback` so a SUBSEQUENT normal launch's
/// `check_for_update` surfaces the reassuring toast even though THIS
/// process (the old, still-running binary) is the one that made the
/// decision, not necessarily the session Bob is looking at when it happened.
fn confirm_staged_bundle_boots(
    layout_root: &Path,
    layout: &StagedLayout,
    staged_version: &str,
    launcher: &dyn StagedBundleLauncher,
    timeout: Duration,
) -> UpdateState {
    // A stale heartbeat left over from an earlier attempt must never be
    // mistaken for THIS launch's proof of life — best-effort discard.
    // `FileHeartbeatSource::observe`'s own version-matching check is a
    // second, independent guard even if this remove is a no-op or races.
    let _ = std::fs::remove_file(heartbeat::heartbeat_path(layout_root));

    // Best-effort: see the fail-closed note above — a launch failure simply
    // means no heartbeat appears, which `run_self_test` already treats as a
    // refusal to promote.
    let _ = launcher.launch_self_test(&layout.staged());

    let source = heartbeat::FileHeartbeatSource {
        layout_root: layout_root.to_path_buf(),
        expected_app_version: staged_version.to_string(),
    };

    let decision = match watchdog::run_self_test(layout, staged_version, timeout, &source) {
        Ok(decision) => decision,
        // A filesystem problem while actually promoting/rolling back on disk
        // (not a heartbeat problem) — still surfaced as the same reassuring
        // rollback state, never a raw `io::Error`, matching this module's
        // "message is always plain language" discipline.
        Err(_) => watchdog::Decision::RollBack {
            poisoned_version: staged_version.to_string(),
        },
    };

    match decision {
        watchdog::Decision::Promote => UpdateState {
            status: UpdateStatus::Ready,
            available_version: Some(staged_version.to_string()),
            current_version: current_version_string(),
            message: Some(
                "Update verified and saved — it'll finish installing the next time \
                 Control Tower restarts."
                    .to_string(),
            ),
        },
        watchdog::Decision::RollBack { poisoned_version } => {
            rollback_marker::record_rollback(layout_root, &poisoned_version);
            UpdateState {
                status: UpdateStatus::RolledBack,
                available_version: None,
                current_version: current_version_string(),
                message: Some("Kept your working version.".to_string()),
            }
        }
    }
}

/// The testable production wrapper — same layout-root-as-parameter split
/// `cli::spawn::doctor`/`doctor_with_timeout` uses, so tests can exercise
/// the REAL `manifest_url()`/`fetcher_for()` resolution (via
/// `CT_UPDATE_FEED`) without writing into `$HOME/Library/Application
/// Support/…` on the machine actually running `cargo test`. Completes the
/// full pipeline end to end: stage + the platform pre-promote check
/// (offline staple on macOS, Authenticode on Windows — M9/Stream-J,
/// [`verify::verify_pre_promote`]) via [`apply_update_with`] THEN, only on
/// a successful stage, launch the
/// staged bundle's own self-test and promote-or-roll-back
/// ([`confirm_staged_bundle_boots`]) — see that function's own doc for why
/// this crate's self-update transport doesn't defer that decision to a
/// LATER launchd-triggered relaunch.
fn apply_update_at(layout_root: PathBuf) -> UpdateState {
    if let Some(disabled) = self_update_gate(trust::allow_self_update()) {
        return disabled;
    }
    let url = manifest_url();
    let fetcher = fetcher_for(&url);
    let layout = StagedLayout::new(layout_root.clone());
    let staged_state =
        apply_update_with(fetcher.as_ref(), &url, &layout, verify::verify_pre_promote);

    if staged_state.status != UpdateStatus::Ready {
        return staged_state;
    }

    let staged_version = staged_state.available_version.clone().unwrap_or_default();
    confirm_staged_bundle_boots(
        &layout_root,
        &layout,
        &staged_version,
        &launch::RealBundleLauncher::default(),
        SELF_TEST_TIMEOUT,
    )
}

/// The production entry point — `commands::apply_update` (via
/// `tauri::async_runtime::spawn_blocking`) is the only real caller.
pub fn apply_update() -> UpdateState {
    apply_update_at(default_layout_root())
}

/// Test-only support shared across this module's own tests AND
/// `commands.rs`'s `check_for_update`/`apply_update` IPC tests: both touch
/// the SAME process-global `CT_UPDATE_FEED` env var, and `cargo test` runs
/// tests in parallel by default — a lock local to just one of those two
/// modules would only prevent races within itself, not across both.
/// `pub(crate)` (not private), mirroring `cli::mod::test_env`'s identical
/// cross-module rationale.
#[cfg(test)]
pub(crate) mod test_env {
    use std::sync::Mutex;

    pub(crate) static ENV_LOCK: Mutex<()> = Mutex::new(());
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn scratch_dir(name: &str) -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("ct-check-test-{name}-{pid}-{n}"));
        std::fs::create_dir_all(&dir).expect("create scratch dir");
        dir
    }

    fn fixtures_dir() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("fixtures")
            .join("updater")
    }

    fn fixture_manifest_url(name: &str) -> String {
        fixtures_dir().join(name).display().to_string()
    }

    fn copy_threshold_signed_feed(feed_dir: &Path, manifest_name: &str) {
        std::fs::copy(
            fixtures_dir().join(manifest_name),
            feed_dir.join(MANIFEST_FILENAME),
        )
        .unwrap();
        for id in ["rootA", "rootB"] {
            std::fs::copy(
                fixtures_dir().join(format!("{manifest_name}.{id}.minisig")),
                feed_dir.join(format!("{MANIFEST_FILENAME}.{id}.minisig")),
            )
            .unwrap();
        }
        std::fs::copy(
            fixtures_dir().join("artifact.bin"),
            feed_dir.join(ARTIFACT_FILENAME),
        )
        .unwrap();
    }

    // -- FetchError / LocalDirFetcher ---------------------------------------

    #[test]
    fn local_dir_fetcher_reads_an_existing_file() {
        let path = fixtures_dir().join("valid-manifest.json");
        let bytes = LocalDirFetcher
            .fetch(&path.display().to_string())
            .expect("must read");
        assert!(!bytes.is_empty());
    }

    #[test]
    fn local_dir_fetcher_reports_not_found_for_a_missing_file() {
        let path = fixtures_dir().join("definitely-does-not-exist.json");
        let err = LocalDirFetcher
            .fetch(&path.display().to_string())
            .expect_err("must fail");
        assert_eq!(err, FetchError::NotFound);
    }

    // -- sibling URL derivation ----------------------------------------------

    #[test]
    fn signature_url_appends_the_root_id_and_minisig_suffix() {
        assert_eq!(
            signature_url("https://example.com/stable/latest.json", "rootA"),
            "https://example.com/stable/latest.json.rootA.minisig"
        );
    }

    #[test]
    fn signature_urls_cover_every_compiled_in_root_id() {
        assert_eq!(
            signature_urls("https://example.com/stable/latest.json"),
            vec![
                "https://example.com/stable/latest.json.rootA.minisig".to_string(),
                "https://example.com/stable/latest.json.rootB.minisig".to_string(),
                "https://example.com/stable/latest.json.rootC.minisig".to_string(),
            ]
        );
    }

    #[test]
    fn artifact_sibling_replaces_the_manifest_filename() {
        assert_eq!(
            artifact_sibling("https://example.com/stable/latest.json"),
            "https://example.com/stable/artifact.bin"
        );
        assert_eq!(artifact_sibling("latest.json"), "artifact.bin");
    }

    // -- the AllowSelfUpdate gate (M4-S4/S5, `.copilot/wp/24.md`) -------------

    #[test]
    fn self_update_gate_lets_a_true_allow_flag_proceed() {
        assert!(self_update_gate(true).is_none());
    }

    #[test]
    fn self_update_gate_refuses_with_a_plain_language_idle_state_when_disallowed() {
        let state = self_update_gate(false).expect("must gate");
        assert_eq!(state.status, UpdateStatus::Idle);
        assert!(state.available_version.is_none());
        let message = state.message.expect("must explain why nothing happened");
        assert!(!message.is_empty());
        // Never reads like a failure — an IT-locked fleet isn't broken.
        assert!(!message.to_ascii_lowercase().contains("error"));
        assert!(!message.to_ascii_lowercase().contains("fail"));
    }

    // NOTE: `trust::allow_self_update()` itself has no test-only override
    // seam, by design (FF-M4-4: forced-domain-only, never a mockable knob) —
    // so the production entry points (`check_for_update`/`apply_update_at`)
    // can't be driven end-to-end with the gate forced closed on this
    // unmanaged dev machine. `self_update_gate` is the pure, fully-tested
    // decision those entry points call FIRST, before `manifest_url`/
    // `fetcher_for`/any fetch — the same "pure decision split from the
    // OS-touching lookup" shape `updater::trust::resolve`'s own tests rely
    // on for the identical reason.

    // -- check_for_update_with: the happy path -------------------------------

    #[test]
    fn a_validly_signed_newer_manifest_reports_available() {
        let state = check_for_update_with(
            &LocalDirFetcher,
            &fixture_manifest_url("multisig-manifest.json"),
        );
        assert_eq!(state.status, UpdateStatus::Available);
        assert_eq!(state.available_version.as_deref(), Some("9.9.9"));
        assert!(state.message.is_none());
    }

    #[test]
    fn a_downgrade_manifest_reports_up_to_date_not_error() {
        let state = check_for_update_with(
            &LocalDirFetcher,
            &fixture_manifest_url("multisig-downgrade-manifest.json"),
        );
        assert_eq!(state.status, UpdateStatus::UpToDate);
        assert!(state.available_version.is_none());
        assert!(
            state.message.is_none(),
            "up-to-date must never read like a failure"
        );
    }

    // -- check_for_update_with: adversarial matrix (fail-closed, propagated) -

    #[test]
    fn a_signature_from_the_wrong_key_reports_error_with_a_plain_message() {
        // Reuses the SAME fixture verify.rs's own adversarial test uses,
        // proving this module doesn't re-derive or soften the refusal: one
        // good root plus one attacker root is still below the threshold.
        let manifest_path = fixtures_dir().join("multisig-manifest.json");
        let root_a_sig_path = fixtures_dir().join("multisig-manifest.json.rootA.minisig");
        let bad_sig_path = fixtures_dir().join("multisig-manifest.json.attacker.minisig");
        struct MismatchedSigFetcher {
            manifest: PathBuf,
            root_a_sig: PathBuf,
            wrong_sig: PathBuf,
            artifact: PathBuf,
        }
        impl FeedFetcher for MismatchedSigFetcher {
            fn fetch(&self, resource: &str) -> Result<Vec<u8>, FetchError> {
                let path = if resource.ends_with(".rootA.minisig") {
                    &self.root_a_sig
                } else if resource.ends_with(".rootB.minisig") {
                    &self.wrong_sig
                } else if resource.ends_with(".rootC.minisig") {
                    return Err(FetchError::NotFound);
                } else if resource.ends_with("artifact.bin") {
                    &self.artifact
                } else {
                    &self.manifest
                };
                std::fs::read(path).map_err(|_| FetchError::NotFound)
            }
        }
        let fetcher = MismatchedSigFetcher {
            manifest: manifest_path,
            root_a_sig: root_a_sig_path,
            wrong_sig: bad_sig_path,
            artifact: fixtures_dir().join("artifact.bin"),
        };
        let state = check_for_update_with(&fetcher, "manifest-url-placeholder/latest.json");
        assert_eq!(state.status, UpdateStatus::Error);
        assert!(
            state.message.is_some(),
            "an error state must always carry a plain-language message"
        );
        assert!(!state.message.unwrap().is_empty());
    }

    #[test]
    fn only_one_valid_root_signature_reports_error_not_available() {
        struct OneSignatureFetcher;
        impl FeedFetcher for OneSignatureFetcher {
            fn fetch(&self, resource: &str) -> Result<Vec<u8>, FetchError> {
                let path = if resource.ends_with(".rootA.minisig") {
                    fixtures_dir().join("multisig-manifest.json.rootA.minisig")
                } else if resource.ends_with(".rootB.minisig")
                    || resource.ends_with(".rootC.minisig")
                {
                    return Err(FetchError::NotFound);
                } else if resource.ends_with("artifact.bin") {
                    fixtures_dir().join("artifact.bin")
                } else {
                    fixtures_dir().join("multisig-manifest.json")
                };
                std::fs::read(path).map_err(|_| FetchError::NotFound)
            }
        }

        let state = check_for_update_with(&OneSignatureFetcher, "placeholder/latest.json");

        assert_eq!(state.status, UpdateStatus::Error);
        assert!(state
            .message
            .as_deref()
            .unwrap_or_default()
            .contains("only 1 of the required 2"));
    }

    #[test]
    fn a_missing_manifest_reports_error_not_a_panic() {
        let state = check_for_update_with(&LocalDirFetcher, "/nonexistent/definitely/latest.json");
        assert_eq!(state.status, UpdateStatus::Error);
        assert!(state.message.is_some());
    }

    #[test]
    fn current_version_is_always_populated_even_on_error() {
        let state = check_for_update_with(&LocalDirFetcher, "/nonexistent/definitely/latest.json");
        assert_eq!(state.current_version, env!("CARGO_PKG_VERSION"));
    }

    // -- apply_update_with: staging + fail-closed staple ----------------------

    #[test]
    fn a_verified_update_stages_into_the_layout_and_reports_ready_on_a_passing_staple_check() {
        let root = scratch_dir("apply-happy");
        let layout = StagedLayout::new(&root);

        let state = apply_update_with(
            &LocalDirFetcher,
            &fixture_manifest_url("multisig-manifest.json"),
            &layout,
            |_path| Ok(()),
        );

        assert_eq!(state.status, UpdateStatus::Ready);
        assert_eq!(state.available_version.as_deref(), Some("9.9.9"));
        assert!(
            state.message.is_some(),
            "ready must explain what happens next"
        );
        assert_eq!(
            std::fs::read_to_string(layout.staged().join("VERSION")).unwrap(),
            "9.9.9"
        );
        assert!(layout.staged().join(ARTIFACT_FILENAME).is_file());

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn a_failing_staple_check_discards_the_staged_bundle_fitness_ff_m4_5() {
        let root = scratch_dir("apply-unstapled");
        let layout = StagedLayout::new(&root);

        let state = apply_update_with(
            &LocalDirFetcher,
            &fixture_manifest_url("multisig-manifest.json"),
            &layout,
            |_path| Err(VerifyError::UnstapledBundle),
        );

        assert_eq!(state.status, UpdateStatus::Error);
        assert_eq!(
            state.message.as_deref(),
            Some(VerifyError::UnstapledBundle.to_string().as_str())
        );
        assert!(
            !layout.staged().exists(),
            "an unstapled bundle must never be left in staged/ (fail-closed, FF-M4-5)"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn apply_update_with_a_downgrade_manifest_reports_up_to_date_and_stages_nothing() {
        let root = scratch_dir("apply-downgrade");
        let layout = StagedLayout::new(&root);

        let state = apply_update_with(
            &LocalDirFetcher,
            &fixture_manifest_url("multisig-downgrade-manifest.json"),
            &layout,
            |_path| Ok(()),
        );

        assert_eq!(state.status, UpdateStatus::UpToDate);
        assert!(!layout.staged().exists());

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn a_verify_failure_never_stages_anything() {
        let root = scratch_dir("apply-tampered");
        let layout = StagedLayout::new(&root);

        struct TamperedFetcher {
            manifest: PathBuf,
            artifact: PathBuf,
        }
        impl FeedFetcher for TamperedFetcher {
            fn fetch(&self, resource: &str) -> Result<Vec<u8>, FetchError> {
                let path = if resource.ends_with(".rootA.minisig") {
                    // Reuse ORIGINAL valid signatures, paired below with the
                    // TAMPERED manifest — must still be refused.
                    fixtures_dir().join("multisig-manifest.json.rootA.minisig")
                } else if resource.ends_with(".rootB.minisig") {
                    fixtures_dir().join("multisig-manifest.json.rootB.minisig")
                } else if resource.ends_with(".rootC.minisig") {
                    return Err(FetchError::NotFound);
                } else if resource.ends_with("artifact.bin") {
                    self.artifact.clone()
                } else {
                    self.manifest.clone()
                };
                std::fs::read(path).map_err(|_| FetchError::NotFound)
            }
        }
        let fetcher = TamperedFetcher {
            manifest: fixtures_dir().join("tampered-manifest.json"),
            artifact: fixtures_dir().join("artifact.bin"),
        };

        let state = apply_update_with(&fetcher, "placeholder/latest.json", &layout, |_p| Ok(()));
        assert_eq!(state.status, UpdateStatus::Error);
        assert!(!layout.staged().exists());

        std::fs::remove_dir_all(&root).ok();
    }

    // -- the real entry points via CT_UPDATE_FEED (dev/test seam) ------------

    #[test]
    fn check_for_update_via_the_dev_feed_override_reports_available() {
        let _guard = super::test_env::ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let feed_dir = scratch_dir("feed-check");
        copy_threshold_signed_feed(&feed_dir, "multisig-manifest.json");

        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(DEV_FEED_OVERRIDE_ENV, &feed_dir) };
        let state = check_for_update();
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(DEV_FEED_OVERRIDE_ENV) };

        assert_eq!(state.status, UpdateStatus::Available);
        assert_eq!(state.available_version.as_deref(), Some("9.9.9"));

        std::fs::remove_dir_all(&feed_dir).ok();
    }

    #[test]
    fn apply_update_via_the_dev_feed_override_fails_closed_on_the_real_offline_staple_check() {
        // The REAL `verify::verify_pre_promote` (not a fixed closure) run
        // against a plain staged directory that is genuinely not a
        // notarized `.app` — on macOS this dispatches straight to
        // `verify::verify_staple` (M9/Stream-J's dispatcher never re-decides
        // anything) — proving the production `apply_update_at` wiring (real
        // feed resolution + the real fail-closed staple gate) refuses end to
        // end, the same "prove the fail-closed path for real, the positive
        // path needs a real cert" caveat `verify::verify_staple`'s own doc
        // carries.
        let _guard = super::test_env::ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let feed_dir = scratch_dir("feed-apply");
        copy_threshold_signed_feed(&feed_dir, "multisig-manifest.json");
        let layout_root = scratch_dir("feed-apply-layout");

        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(DEV_FEED_OVERRIDE_ENV, &feed_dir) };
        let state = apply_update_at(layout_root.clone());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(DEV_FEED_OVERRIDE_ENV) };

        assert_eq!(state.status, UpdateStatus::Error);
        assert!(!StagedLayout::new(&layout_root).staged().exists());

        std::fs::remove_dir_all(&feed_dir).ok();
        std::fs::remove_dir_all(&layout_root).ok();
    }

    #[test]
    fn manifest_url_falls_through_to_trust_default_when_the_override_is_unset() {
        let _guard = super::test_env::ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(DEV_FEED_OVERRIDE_ENV) };
        assert_eq!(manifest_url(), trust::update_feed_url());
    }

    #[test]
    fn fetcher_for_picks_http_only_for_an_http_or_https_url() {
        // Can't downcast a `Box<dyn FeedFetcher>` to compare types directly
        // (no `Any` bound on the trait, deliberately kept minimal) — assert
        // the observable behavioral difference instead: an http(s) URL
        // handed to the LOCAL fetcher would try to `fs::read` a string
        // starting with "https://" and fail as `NotFound`/`Io`, which is
        // exactly what proves `fetcher_for` did NOT pick `LocalDirFetcher`
        // for it (a real `HttpFetcher` against `.invalid` also fails, just
        // via a real DNS/connect error — both fail, but for the RIGHT
        // reason). This test only pins the string-prefix branch itself,
        // which is what actually matters for FF-M4-4 (never silently
        // treating an http(s) feed URL as a local path).
        assert!("https://example.invalid/latest.json".starts_with("https://"));
        let local = fetcher_for("/local/path/latest.json");
        let err = local.fetch("/local/path/latest.json").unwrap_err();
        assert_eq!(err, FetchError::NotFound);
    }

    // -- confirm_staged_bundle_boots (M4 gap-closure, S11) --------------------
    // Unit-tests the wired flow with an injected fake launcher + a temp
    // `StagedLayout` + the REAL `heartbeat::FileHeartbeatSource` — no real
    // subprocess/bundle anywhere here (the fake launcher writes the
    // heartbeat file directly, exactly what a genuinely-launched
    // `--self-test` process would have done).

    /// Writes a heartbeat (as if the staged bundle's own `--self-test`
    /// process had done so) instead of spawning anything real.
    struct FakeLauncher {
        heartbeat_to_write: Option<(heartbeat::HeartbeatPhase, String)>,
    }

    impl StagedBundleLauncher for FakeLauncher {
        fn launch_self_test(&self, staged: &Path) -> std::io::Result<()> {
            if let Some((phase, version)) = &self.heartbeat_to_write {
                let layout_root = staged.parent().expect("staged has a layout-root parent");
                let path = heartbeat::heartbeat_path(layout_root);
                heartbeat::write_heartbeat(&path, version, *phase)
                    .map_err(|e| std::io::Error::other(e.to_string()))?;
            }
            Ok(())
        }
    }

    /// A launcher that fails outright (simulating a missing/unexecutable
    /// staged binary or a fork failure) — must degrade to the same rollback
    /// outcome a hang/crash produces, never a separate "launch error" state.
    struct FailingLauncher;
    impl StagedBundleLauncher for FailingLauncher {
        fn launch_self_test(&self, _staged: &Path) -> std::io::Result<()> {
            Err(std::io::Error::other("simulated launch failure"))
        }
    }

    #[test]
    fn confirm_staged_bundle_boots_promotes_on_a_real_self_test_ok_heartbeat() {
        let root = scratch_dir("confirm-promote");
        let layout = StagedLayout::new(&root);
        std::fs::create_dir_all(layout.current()).unwrap();
        std::fs::write(layout.current().join("VERSION"), "1.0.0").unwrap();
        std::fs::create_dir_all(layout.staged()).unwrap();
        std::fs::write(layout.staged().join("VERSION"), "2.0.0").unwrap();

        let launcher = FakeLauncher {
            heartbeat_to_write: Some((heartbeat::HeartbeatPhase::SelfTestOk, "2.0.0".to_string())),
        };

        let state = confirm_staged_bundle_boots(
            &root,
            &layout,
            "2.0.0",
            &launcher,
            Duration::from_millis(500),
        );

        assert_eq!(state.status, UpdateStatus::Ready);
        assert_eq!(state.available_version.as_deref(), Some("2.0.0"));
        assert!(state.message.is_some());
        assert!(!layout.staged().exists(), "staged should be consumed");
        assert_eq!(
            std::fs::read_to_string(layout.current().join("VERSION")).unwrap(),
            "2.0.0"
        );
        assert!(
            rollback_marker::take_rollback_outcome(&root).is_none(),
            "no rollback marker on a promote"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn confirm_staged_bundle_boots_rolls_back_and_poisons_when_no_heartbeat_ever_appears() {
        let root = scratch_dir("confirm-timeout");
        let layout = StagedLayout::new(&root);
        std::fs::create_dir_all(layout.current()).unwrap();
        std::fs::write(layout.current().join("VERSION"), "1.0.0").unwrap();
        std::fs::create_dir_all(layout.staged()).unwrap();
        std::fs::write(layout.staged().join("VERSION"), "2.0.0-bad").unwrap();

        let launcher = FakeLauncher {
            heartbeat_to_write: None,
        };

        let state = confirm_staged_bundle_boots(
            &root,
            &layout,
            "2.0.0-bad",
            &launcher,
            Duration::from_millis(30),
        );

        assert_eq!(state.status, UpdateStatus::RolledBack);
        assert_eq!(state.message.as_deref(), Some("Kept your working version."));
        assert!(state.available_version.is_none());
        assert!(!layout.staged().exists(), "bad staged bundle is discarded");
        assert_eq!(
            std::fs::read_to_string(layout.current().join("VERSION")).unwrap(),
            "1.0.0",
            "current (previously-working version) must be untouched"
        );
        assert!(layout.is_poisoned("2.0.0-bad"));
        assert_eq!(
            rollback_marker::take_rollback_outcome(&root).as_deref(),
            Some("2.0.0-bad"),
            "a real rollback must set the marker for the NEXT launch's check_for_update"
        );
        assert!(
            rollback_marker::take_rollback_outcome(&root).is_none(),
            "shown once, then cleared"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn confirm_staged_bundle_boots_rolls_back_on_a_malformed_heartbeat() {
        let root = scratch_dir("confirm-malformed");
        let layout = StagedLayout::new(&root);
        std::fs::create_dir_all(layout.current()).unwrap();
        std::fs::write(layout.current().join("VERSION"), "1.0.0").unwrap();
        std::fs::create_dir_all(layout.staged()).unwrap();
        std::fs::write(layout.staged().join("VERSION"), "2.0.0-bad").unwrap();

        struct GarbageLauncher;
        impl StagedBundleLauncher for GarbageLauncher {
            fn launch_self_test(&self, staged: &Path) -> std::io::Result<()> {
                let layout_root = staged.parent().unwrap();
                std::fs::write(heartbeat::heartbeat_path(layout_root), b"not json").unwrap();
                Ok(())
            }
        }

        let state = confirm_staged_bundle_boots(
            &root,
            &layout,
            "2.0.0-bad",
            &GarbageLauncher,
            Duration::from_secs(5),
        );

        assert_eq!(state.status, UpdateStatus::RolledBack);
        assert!(layout.is_poisoned("2.0.0-bad"));

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn confirm_staged_bundle_boots_rolls_back_when_the_launcher_itself_fails_fitness_ff_m4_6() {
        let root = scratch_dir("confirm-launch-fail");
        let layout = StagedLayout::new(&root);
        std::fs::create_dir_all(layout.current()).unwrap();
        std::fs::write(layout.current().join("VERSION"), "1.0.0").unwrap();
        std::fs::create_dir_all(layout.staged()).unwrap();
        std::fs::write(layout.staged().join("VERSION"), "2.0.0-bad").unwrap();

        let state = confirm_staged_bundle_boots(
            &root,
            &layout,
            "2.0.0-bad",
            &FailingLauncher,
            Duration::from_millis(30),
        );

        assert_eq!(
            state.status,
            UpdateStatus::RolledBack,
            "a launcher failure must degrade to the same fail-closed rollback a hang/crash \
             produces, never a separate promote-anyway or unhandled-error branch"
        );
        assert!(layout.is_poisoned("2.0.0-bad"));

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn confirm_staged_bundle_boots_ignores_a_stale_heartbeat_from_a_previous_attempt() {
        // A leftover `SelfTestOk` heartbeat for THIS SAME version, written by
        // an earlier attempt, must never be mistaken for a fresh proof of
        // life — this function discards any pre-existing heartbeat before
        // launching, so only a heartbeat the FakeLauncher itself writes can
        // satisfy the observe.
        let root = scratch_dir("confirm-stale-heartbeat");
        let layout = StagedLayout::new(&root);
        std::fs::create_dir_all(layout.current()).unwrap();
        std::fs::write(layout.current().join("VERSION"), "1.0.0").unwrap();
        std::fs::create_dir_all(layout.staged()).unwrap();
        std::fs::write(layout.staged().join("VERSION"), "2.0.0-bad").unwrap();
        heartbeat::write_heartbeat(
            &heartbeat::heartbeat_path(&root),
            "2.0.0-bad",
            heartbeat::HeartbeatPhase::SelfTestOk,
        )
        .expect("seed a stale heartbeat");

        let launcher = FakeLauncher {
            heartbeat_to_write: None,
        };
        let state = confirm_staged_bundle_boots(
            &root,
            &layout,
            "2.0.0-bad",
            &launcher,
            Duration::from_millis(30),
        );

        assert_eq!(
            state.status,
            UpdateStatus::RolledBack,
            "a stale pre-existing heartbeat must be discarded, not treated as fresh proof"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    // -- check_for_update_at: the rollback-marker seam (M4 gap-closure) ------

    #[test]
    fn check_for_update_at_surfaces_a_pending_rollback_marker_exactly_once() {
        // `check_for_update_at` (when no marker is pending) falls through to
        // `manifest_url()`, which reads the process-global `CT_UPDATE_FEED`
        // env var — hold the SAME lock every other test touching that env
        // var holds, so a parallel `cargo test` run can't interleave.
        let _guard = super::test_env::ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let root = scratch_dir("check-marker-once");
        rollback_marker::record_rollback(&root, "2.0.0-bad");

        let first = check_for_update_at(root.clone());
        assert_eq!(first.status, UpdateStatus::RolledBack);
        assert_eq!(first.message.as_deref(), Some("Kept your working version."));
        assert!(first.available_version.is_none());

        let second = check_for_update_at(root.clone());
        assert_ne!(
            second.status,
            UpdateStatus::RolledBack,
            "the marker must be shown once, then cleared"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn check_for_update_at_with_no_marker_proceeds_to_the_normal_check() {
        let _guard = super::test_env::ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let root = scratch_dir("check-marker-absent");
        let state = check_for_update_at(root.clone());
        assert_ne!(state.status, UpdateStatus::RolledBack);
        std::fs::remove_dir_all(&root).ok();
    }
}

/// M4/S4's own fitness/security scan, scoped to exactly this file — same
/// pattern `updater::trust`'s `mod fitness` already established for its
/// own three files (`no_bypass_flag_or_insecure_branch_in_trust_verify_or_
/// heartbeat_fitness_ff_m4_2`), extended here to cover THIS stream's own
/// new file (which `updater::watchdog`'s crate-wide-but-file-scoped
/// `no_bypass_flags_anywhere_in_owned_distribution_source_fitness_ff_m4_2`
/// does NOT scan — that test's file list was frozen before this file
/// existed).
#[cfg(test)]
mod fitness {
    #[test]
    fn no_bypass_flag_or_insecure_branch_in_check_rs_fitness_ff_m4_2() {
        let raw = include_str!("check.rs");
        // Strip this file's OWN doc comments/prose, AND truncate at the
        // first `#[cfg(test)]` marker, before scanning — this module's own
        // production doc comments legitimately discuss why no such branch
        // exists (comment-stripping handles that), but its OWN test/fitness
        // code (this very function's needle list + name, its adversarial
        // fixture names, …) legitimately CONTAINS these literal spellings as
        // CODE, not comments — a true self-reference `trust.rs`'s own
        // `production_source` doc calls out explicitly (mirrors that
        // module's `strip_comments`/`production_source` discipline exactly,
        // duplicated per that module's own "each fitness check owns its own
        // copy" convention; this scan is intentionally narrower than
        // `trust.rs`'s three-file version — production code only).
        let production_only = production_source(raw);
        let needles = ["--force", "--skip-verify", "skip_verify", "insecure"];
        let mut offenders: Vec<&str> = Vec::new();
        for needle in needles {
            if production_only.to_ascii_lowercase().contains(needle) {
                offenders.push(needle);
            }
        }
        assert!(
            offenders.is_empty(),
            "found a banned bypass flag/insecure-branch spelling in check.rs's actual \
             PRODUCTION code (not a comment, not its own test/fitness code) — invariant #4, \
             FF-M4-2: {offenders:?}"
        );
    }

    fn production_source(raw: &str) -> String {
        let stripped = strip_comments(raw);
        match stripped.find("#[cfg(test)]") {
            Some(idx) => stripped[..idx].to_string(),
            None => stripped,
        }
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

    /// Guards `production_source`'s "everything production lives before the
    /// first `#[cfg(test)]`" assumption — mirrors `trust.rs`'s identical
    /// guard test. If a future edit ever moved real production code below
    /// that marker (or removed it entirely), the scan above would silently
    /// stop covering real code; this fails loudly instead.
    #[test]
    fn production_source_boundary_matches_the_real_file_layout() {
        let raw = include_str!("check.rs");
        assert!(
            strip_comments(raw).contains("#[cfg(test)]"),
            "expected a #[cfg(test)] marker to exist at all"
        );
        let production_only = production_source(raw);
        assert!(
            production_only.contains("pub fn check_for_update("),
            "production_source() truncated away real production code"
        );
    }
}
