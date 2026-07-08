//! Fail-closed update-manifest signature verification + offline staple check
//! (M4/S2, ADR-M4-004's `Verified(sig+staple, fail-closed)` step,
//! FF-M4-5/FF-M4-2). No `--force`/`--skip-verify`/"insecure" branch exists
//! anywhere in this module — every error path in [`VerifyError`] refuses to
//! stage, full stop; `tests/fitness_no_update_bypass.rs` grep-denies the
//! literal flag spellings across the whole crate as a second, independent
//! guarantee.
//!
//! ## The manifest/signature format (frozen here, per M4/S1's task)
//!
//! The signed unit is a single small JSON document (`UpdateManifestWire`
//! below) carrying the new version, the release channel, and — critically —
//! the **sha256 of the actual update artifact**, all under one minisign
//! signature. This is a deliberate choice over signing the (potentially
//! large) artifact bytes directly:
//!
//! - **One signature authenticates the whole decision, not just the bytes.**
//!   If only the artifact were signed, an attacker who can influence which
//!   `(version, channel, url)` tuple gets *paired* with a validly-signed
//!   artifact could still stage a stale/wrong artifact under new claims (a
//!   swapped-URL or replayed-old-version attack) without invalidating
//!   anything. Pinning the artifact's hash *inside* the signed manifest
//!   means version, channel, and artifact identity are one atomic, signed
//!   fact — changing any one byte of any field invalidates the signature
//!   (see `tampered-manifest.json`'s fixture test below).
//! - **Cheap to verify offline and repeatedly.** The manifest is a few
//!   hundred bytes; the artifact (tens of MB) is hashed with a plain SHA-256
//!   (this module's own `sha256`, see its doc for why it's hand-rolled
//!   rather than a second dependency), not re-run through public-key
//!   crypto.
//! - **Matches `release-and-versioning.md` §2's `latest.json` shape**
//!   (version, notes, per-platform url+signature), extended with the
//!   artifact hash field so the offline verifier never needs a second
//!   network fetch to confirm artifact identity.
//!
//! `verify_update` performs steps 1-2 of `release-and-versioning.md` §5's
//! rollback trigger order (signature, then artifact-hash-as-"the bytes are
//! what was signed", then downgrade); [`verify_staple`] performs step 2's
//! other half (offline notarization-staple check) as a **separate** function
//! because it operates on a bundle *path* on disk (the extracted/staged
//! `.app`), not the raw artifact bytes `verify_update` receives — S3's state
//! machine calls both before ever transitioning `Verified -> Staged`
//! (ADR-M4-004). Neither function alone reaches `Verified`.
//!
//! ## Two-of-N: [`verify_update_multisig`] (M7/S5, `.copilot/wp` task 64)
//!
//! [`verify_update_multisig`] is a stricter SIBLING entrypoint to
//! `verify_update`, not a replacement — `verify_update` still requires
//! exactly the one compiled-in root ([`trust::trust_root`]) M4 always did,
//! kept working unmodified. `verify_update_multisig` instead requires **at
//! least [`super::multisig::THRESHOLD_K`] DISTINCT roots** (out of
//! [`super::multisig::TRUST_ROOTS_B64`]) to each independently produce a
//! valid signature over the exact same manifest bytes before the manifest is
//! trusted enough to parse. Both entrypoints share the identical
//! post-authentication logic (downgrade + artifact-hash checks — see
//! [`after_authenticated`]): once *either* scheme has authenticated the
//! manifest bytes, "is this actually a newer, hash-matching update" is the
//! same question with the same fail-closed answer either way.

use std::collections::HashSet;
use std::path::Path;

use minisign_verify::Signature;
use serde::Deserialize;

use super::multisig;
use super::trust;

// ---------------------------------------------------------------------------
// Version — a minimal, dependency-free semver-shaped comparator
// ---------------------------------------------------------------------------

/// Just enough of semver to compare "is this update newer than what's
/// running" (`major.minor.patch`, optionally followed by a `-`/`+`
/// pre-release/build suffix this comparator ignores for ordering purposes —
/// a known, deliberate simplification: this app's own releases are plain
/// `MAJOR.MINOR.PATCH`, `release-and-versioning.md` §1.1, so a pre-release
/// suffix never actually appears in a `Cargo.toml`/manifest `app_version`
/// this crate produces or consumes today). Not a public general-purpose
/// semver type — `super::verify` is its only consumer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Version {
    pub major: u64,
    pub minor: u64,
    pub patch: u64,
}

impl Version {
    pub fn parse(s: &str) -> Option<Version> {
        let core = s.split(['-', '+']).next().unwrap_or(s);
        let mut parts = core.split('.');
        let major = parts.next()?.parse().ok()?;
        let minor = parts.next()?.parse().ok()?;
        let patch = parts.next()?.parse().ok()?;
        if parts.next().is_some() {
            return None; // more than three dot components — refuse, don't guess
        }
        Some(Version {
            major,
            minor,
            patch,
        })
    }
}

impl std::fmt::Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

/// This crate's own currently-running version, from `Cargo.toml` — the
/// "current" side of the downgrade check `verify_update` runs by default.
fn current_app_version() -> Version {
    Version::parse(env!("CARGO_PKG_VERSION"))
        .expect("this crate's own Cargo.toml version must be well-formed major.minor.patch")
}

// ---------------------------------------------------------------------------
// The wire manifest
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
struct UpdateManifestWire {
    #[allow(dead_code)] // carried for forward-compat / future schema gating, not yet branched on
    schema_version: String,
    app_version: String,
    channel: String,
    #[serde(default)]
    notes: Option<String>,
    artifact_sha256: String,
}

/// The successfully-verified result of [`verify_update`] — everything a
/// caller (S3's staged-update state machine) needs to proceed to staging,
/// and nothing it didn't already prove: `version`/`channel`/`artifact_sha256`
/// all came from a manifest whose minisign signature checked out against
/// the compiled-in trust root, and whose declared artifact hash matches the
/// bytes actually supplied.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifiedUpdate {
    pub version: Version,
    pub channel: String,
    pub artifact_sha256: [u8; 32],
    pub notes: Option<String>,
}

/// Every refusal path — deliberately flat (no nested source chain that could
/// carry key material or manifest content through `{:?}`/`{:#?}` formatting).
/// `Display` and `Debug` are both asserted, by test, to never contain the
/// trust-root public key, the raw signature text, or artifact bytes. There
/// is no `Bypass`/`Insecure`/`Forced` variant — every variant here means
/// "refuse to stage," full stop (FF-M4-5).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VerifyError {
    /// The signature text didn't decode as a minisign signature at all
    /// (empty, garbage, or truncated) — covers both "no signature was
    /// supplied" and "the signature is malformed".
    MalformedSignature,
    /// The manifest bytes are not valid JSON, or are missing a required
    /// field, or `app_version`/`artifact_sha256` don't parse as their
    /// expected shape.
    MalformedManifest,
    /// The signature decoded fine but does not verify against the
    /// compiled-in trust root for these exact manifest bytes — covers a
    /// signature from the wrong key AND a signature from the right key over
    /// DIFFERENT bytes (a tampered manifest field), since minisign can't
    /// distinguish those two causes and this module must not guess.
    SignatureMismatch,
    /// The manifest's declared `artifact_sha256` does not match the sha256
    /// of the `artifact` bytes actually supplied — the signed manifest and
    /// the bytes being staged disagree about what "the update" is.
    ArtifactHashMismatch,
    /// The manifest's `app_version` is not strictly newer than the version
    /// currently running (`<=`, deliberately — see the module's downgrade
    /// note below).
    Downgrade {
        attempted: Version,
        current: Version,
    },
    /// [`verify_staple`]: the bundle failed Gatekeeper's offline assessment
    /// outright (unsigned, ad-hoc signed, or a signature Gatekeeper
    /// rejects).
    UnstapledBundle,
    /// [`verify_staple`]: Gatekeeper accepted the bundle but NOT via a
    /// genuine Developer-ID notarization ticket (e.g. an Apple System
    /// binary, or some other trust path) — this app's own updates must
    /// always be notarized; "accepted for some other reason" still refuses.
    InvalidStaple,
    /// [`verify_update_multisig`] only: fewer than
    /// [`super::multisig::THRESHOLD_K`] of the supplied signatures verified
    /// against DISTINCT compiled-in roots. `valid` is the number of distinct
    /// roots actually satisfied (duplicate signatures from the same root,
    /// garbage/malformed signatures, and signatures from a key outside the
    /// compiled-in set all contribute zero); `required` is
    /// [`super::multisig::THRESHOLD_K`].
    InsufficientSignatures { valid: usize, required: usize },
    /// [`verify_authenticode`] (Windows only, M9/Stream-J, ADR-M9-004): the
    /// staged bundle failed Authenticode signature verification outright
    /// (unsigned, a revoked/expired-without-timestamp signature, or a
    /// signature `signtool verify` rejects) — Windows' nearest analog of
    /// [`VerifyError::UnstapledBundle`]. There is no staple concept on
    /// Windows (ADR-M9-004's own "Consequences": the offline-deterministic
    /// first-launch guarantee is structurally weaker here than macOS's
    /// notarize+staple), so this is the strongest refusal this platform's
    /// pre-promote check can make.
    UnsignedBundle,
}

impl std::fmt::Display for VerifyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VerifyError::MalformedSignature => {
                write!(f, "This update's signature is missing or unreadable — it can't be verified, so it will not be installed.")
            }
            VerifyError::MalformedManifest => {
                write!(
                    f,
                    "This update's manifest is unreadable — it will not be installed."
                )
            }
            VerifyError::SignatureMismatch => {
                write!(f, "This update's signature doesn't match — it will not be installed. This can mean the update was tampered with, or wasn't signed by Everyone Needs a Copilot.")
            }
            VerifyError::ArtifactHashMismatch => {
                write!(f, "This update's contents don't match what was signed — it will not be installed.")
            }
            VerifyError::Downgrade { attempted, current } => {
                write!(f, "This update ({attempted}) is not newer than the version already running ({current}) — it will not be installed.")
            }
            VerifyError::UnstapledBundle => {
                write!(
                    f,
                    "This update isn't notarized by Apple — it will not be installed."
                )
            }
            VerifyError::InvalidStaple => {
                write!(f, "This update wasn't notarized the way Everyone Needs a Copilot releases are — it will not be installed.")
            }
            VerifyError::InsufficientSignatures { valid, required } => {
                write!(f, "This update has only {valid} of the required {required} independent signatures — it will not be installed.")
            }
            VerifyError::UnsignedBundle => {
                write!(
                    f,
                    "This update isn't signed the way Everyone Needs a Copilot releases are — it will not be installed."
                )
            }
        }
    }
}

impl std::error::Error for VerifyError {}

// ---------------------------------------------------------------------------
// verify_update
// ---------------------------------------------------------------------------

/// Verifies `signature` (a minisign signature, in minisign's own multi-line
/// text format) against `manifest` (the raw manifest bytes — see the module
/// doc for the exact JSON shape) using the compiled-in trust root
/// ([`trust::trust_root`]), checks `manifest`'s declared version is newer
/// than the version currently running, and checks `artifact`'s sha256
/// matches what the (now-authenticated) manifest declares. Fail-closed on
/// every step: nothing about `manifest`'s CONTENT is trusted until its
/// signature has been checked against the raw bytes first.
pub fn verify_update(
    artifact: &[u8],
    signature: &str,
    manifest: &[u8],
) -> Result<VerifiedUpdate, VerifyError> {
    verify_update_against(artifact, signature, manifest, &current_app_version())
}

/// The testable core of [`verify_update`] — takes the "current version" as
/// an explicit parameter so the downgrade-refusal path can be exercised
/// against fixtures without depending on this crate's own (constantly
/// advancing) `Cargo.toml` version. `verify_update` is the only production
/// call site; this function carries no bypass semantics of its own.
pub(crate) fn verify_update_against(
    artifact: &[u8],
    signature: &str,
    manifest: &[u8],
    current: &Version,
) -> Result<VerifiedUpdate, VerifyError> {
    let sig = Signature::decode(signature).map_err(|_| VerifyError::MalformedSignature)?;

    trust::trust_root()
        .verify(manifest, &sig, false)
        .map_err(|_| VerifyError::SignatureMismatch)?;

    // Only now — after the signature over these EXACT bytes has checked
    // out — is `manifest`'s content trusted enough to parse and act on.
    after_authenticated(artifact, manifest, current)
}

// ---------------------------------------------------------------------------
// verify_update_multisig — two-of-N (M7/S5)
// ---------------------------------------------------------------------------

/// Verifies `signatures` — a slice of minisign signatures, each in
/// minisign's own multi-line text format, in ANY order — against `manifest`
/// using the compiled-in [`super::multisig::TRUST_ROOTS_B64`], requiring at
/// least [`super::multisig::THRESHOLD_K`] of them to each independently
/// verify against a DISTINCT root. Then checks `manifest`'s declared version
/// is newer than the version currently running, and that `artifact`'s
/// sha256 matches what the (now-authenticated) manifest declares — the
/// identical downgrade/hash logic [`verify_update`] applies, via
/// [`after_authenticated`].
///
/// **Distinct-root accounting, precisely:** for each supplied signature
/// string, this function tries every compiled-in root in turn; the FIRST
/// root it matches is recorded (by index) and no other root is tried for
/// that same signature (a genuine minisign signature can only ever verify
/// against the one key that produced it — trying further roots after a
/// match is pure waste, never a correctness concern). The set of matched
/// root INDICES (not the count of input signatures) is what is compared
/// against `THRESHOLD_K`, so:
/// - Two different signature strings that both verify against the SAME root
///   contribute exactly one index to the set (not two) — a duplicated or
///   re-submitted single custodian's approval can never masquerade as a
///   second, independent one.
/// - A malformed/garbage signature string fails to decode and contributes
///   nothing (never an error by itself — it simply doesn't count).
/// - A structurally-valid signature from a key OUTSIDE the compiled-in set
///   (e.g. an attacker's own keypair) matches no root and contributes
///   nothing.
///
/// Fails closed with [`VerifyError::InsufficientSignatures`] if, after
/// processing every supplied signature, fewer than `THRESHOLD_K` distinct
/// roots were satisfied.
pub fn verify_update_multisig(
    artifact: &[u8],
    signatures: &[&str],
    manifest: &[u8],
) -> Result<VerifiedUpdate, VerifyError> {
    verify_update_multisig_against(artifact, signatures, manifest, &current_app_version())
}

/// The testable core of [`verify_update_multisig`] — same "current version
/// as an explicit parameter" shape as [`verify_update_against`], and for the
/// identical reason (downgrade-refusal fixtures shouldn't depend on this
/// crate's own constantly-advancing `Cargo.toml` version).
pub(crate) fn verify_update_multisig_against(
    artifact: &[u8],
    signatures: &[&str],
    manifest: &[u8],
    current: &Version,
) -> Result<VerifiedUpdate, VerifyError> {
    let roots = multisig::trust_roots();
    let mut satisfied_root_indices: HashSet<usize> = HashSet::new();

    for signature in signatures {
        let Ok(sig) = Signature::decode(signature) else {
            continue; // malformed/garbage — contributes nothing, not an error
        };
        for (idx, root) in roots.iter().enumerate() {
            if root.verify(manifest, &sig, false).is_ok() {
                satisfied_root_indices.insert(idx);
                break; // a signature verifies against at most one root
            }
        }
    }

    if satisfied_root_indices.len() < multisig::THRESHOLD_K {
        return Err(VerifyError::InsufficientSignatures {
            valid: satisfied_root_indices.len(),
            required: multisig::THRESHOLD_K,
        });
    }

    // Only now — after >= THRESHOLD_K distinct roots have authenticated
    // these EXACT manifest bytes — is `manifest`'s content trusted enough to
    // parse and act on. Same downgrade/hash rules as the single-root path;
    // meeting the threshold is necessary, never sufficient, for acceptance.
    after_authenticated(artifact, manifest, current)
}

// ---------------------------------------------------------------------------
// after_authenticated — shared by both verify_update_against and
// verify_update_multisig_against, once each has independently established
// that `manifest`'s bytes are authentic (one root vs. k-of-N respectively).
// ---------------------------------------------------------------------------

/// Parses `manifest` (ALREADY authenticated by the caller — this function
/// trusts its content unconditionally) and checks the declared version is
/// strictly newer than `current`, then that `artifact`'s sha256 matches the
/// declared `artifact_sha256`. Neither the single-root nor the k-of-N
/// verifier reaches [`VerifiedUpdate`] without going through here — there is
/// exactly one downgrade rule and one hash rule in this crate, applied
/// identically regardless of which trust scheme authenticated the bytes.
fn after_authenticated(
    artifact: &[u8],
    manifest: &[u8],
    current: &Version,
) -> Result<VerifiedUpdate, VerifyError> {
    let wire: UpdateManifestWire =
        serde_json::from_slice(manifest).map_err(|_| VerifyError::MalformedManifest)?;

    let attempted = Version::parse(&wire.app_version).ok_or(VerifyError::MalformedManifest)?;

    // `<=`, not `<`, deliberately: a validly-signed manifest for the version
    // ALREADY running is refused too, not just a strictly older one. This
    // closes a replay variant the literal word "downgrade" doesn't quite
    // name — an attacker (or a stale mirror) replaying an old-but-still-
    // validly-signed manifest for the current version should never be
    // treated as a fresh, actionable "update available" — there is nothing
    // for the transport to newly stage in that case, and treating it as
    // verified would let a captured manifest be replayed indefinitely.
    if attempted <= *current {
        return Err(VerifyError::Downgrade {
            attempted,
            current: *current,
        });
    }

    let expected_sha =
        decode_hex_sha256(&wire.artifact_sha256).ok_or(VerifyError::MalformedManifest)?;
    let actual_sha = sha256(artifact);
    if actual_sha != expected_sha {
        return Err(VerifyError::ArtifactHashMismatch);
    }

    Ok(VerifiedUpdate {
        version: attempted,
        channel: wire.channel,
        artifact_sha256: actual_sha,
        notes: wire.notes,
    })
}

fn decode_hex_sha256(s: &str) -> Option<[u8; 32]> {
    let s = s.trim();
    if s.len() != 64 {
        return None;
    }
    let mut out = [0u8; 32];
    for (i, chunk) in s.as_bytes().chunks(2).enumerate() {
        let hi = (chunk[0] as char).to_digit(16)?;
        let lo = (chunk[1] as char).to_digit(16)?;
        out[i] = ((hi << 4) | lo) as u8;
    }
    Some(out)
}

// ---------------------------------------------------------------------------
// sha256 — hand-rolled, not a second crate dependency
// ---------------------------------------------------------------------------

/// A plain, textbook SHA-256 (FIPS 180-4) over `data`. Deliberately NOT a
/// third dependency (`Cargo.toml`'s own note on this module already picked
/// `minisign-verify` as the one security-critical crypto crate this milestone
/// adds; "keep deps minimal" per the task) — SHA-256 here is an **integrity
/// pin inside an already-signed manifest**, not itself the trust boundary
/// (the minisign signature over the manifest, which CONTAINS this hash, is
/// the actual authentication; a naive-but-correct implementation of a
/// standard, fully-specified hash function gives the same collision
/// resistance as any other correct implementation — there is no "signature
/// scheme design" risk here the way there would be for the minisign
/// verification itself, which is why that part stays in the vetted crate).
/// Verified against all three NIST/FIPS 180-4 test vectors below.
fn sha256(data: &[u8]) -> [u8; 32] {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];

    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let mut msg = data.to_vec();
    let bit_len = (data.len() as u64) * 8;
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[i * 4],
                chunk[i * 4 + 1],
                chunk[i * 4 + 2],
                chunk[i * 4 + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let (mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh) =
            (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]);

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = [0u8; 32];
    for (i, word) in h.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}

// ---------------------------------------------------------------------------
// verify_staple — offline notarization-staple check (ADR-M4-004's other half)
// ---------------------------------------------------------------------------

/// Offline Gatekeeper assessment of a staged `.app` bundle at `bundle_path`,
/// via `/usr/sbin/spctl --assess --type execute` — this genuinely never
/// contacts a network (Gatekeeper consults the locally-cached/stapled
/// ticket only for `--assess`), which is exactly what makes it safe for an
/// air-gapped fleet on an internal mirror (`release-and-versioning.md` §2
/// step 4). Fails closed on every non-success path: a missing `spctl`, a
/// rejected assessment, or an assessment accepted via some path OTHER than
/// genuine Developer-ID notarization (`InvalidStaple`) all refuse.
///
/// **What this module can and cannot prove without a real signing
/// ceremony:** the fail-closed (refuse) path is fully exercised by
/// `fixtures/updater/staple/UnsignedApp.app` below, using the REAL system
/// `spctl` (not a mock) against a genuinely unsigned fixture — this proves
/// the shell-out plumbing and the fail-closed interpretation of its output
/// actually work end to end on this machine. The POSITIVE path (a real
/// Developer-ID-notarized bundle producing `Ok(())`) cannot be exercised
/// here — it requires a real Apple Developer ID + notarization, which is
/// the explicitly owner-gated item this task calls out. `real_is_managed`
/// in `settings::managed` carries the identical caveat for the same reason.
#[cfg(target_os = "macos")]
pub fn verify_staple(bundle_path: &Path) -> Result<(), VerifyError> {
    let output = std::process::Command::new("/usr/sbin/spctl")
        .arg("--assess")
        .arg("--type")
        .arg("execute")
        .arg("-vv")
        .arg(bundle_path)
        .output();

    let output = match output {
        Ok(o) => o,
        Err(_) => return Err(VerifyError::UnstapledBundle),
    };

    if !output.status.success() {
        return Err(VerifyError::UnstapledBundle);
    }

    let stderr = String::from_utf8_lossy(&output.stderr);
    if stderr
        .lines()
        .any(|l| l.trim() == "source=Notarized Developer ID")
    {
        Ok(())
    } else {
        Err(VerifyError::InvalidStaple)
    }
}

// ---------------------------------------------------------------------------
// verify_authenticode — Windows pre-promote check, no staple (M9/Stream-J,
// ADR-M9-004, `docs/01-architecture/windows-parity.md` Section 1 row 5 /
// Section 3 Q3)
// ---------------------------------------------------------------------------

/// Env var naming the ABSOLUTE path to `signtool.exe` — this function never
/// resolves it via a bare `PATH` lookup (the same "never invoke bare
/// `<name>`" discipline `platform::windows::forced`'s
/// `dsregcmd_absolute_path` and `scripts/sign-windows.ps1`'s own
/// `CT_SIGNTOOL_PATH` requirement already apply). Unlike `dsregcmd.exe`
/// (fixed at `%SystemRoot%\System32\dsregcmd.exe`), `signtool.exe` ships
/// with the Windows SDK at a build-machine-specific path with no single
/// well-known system location — so this module REQUIRES an operator to
/// supply an absolute path via this env var; it never guesses one, and
/// never falls back to a bare `Command::new("signtool")`. Missing or
/// non-absolute is treated identically to "signtool verify failed" —
/// [`VerifyError::UnsignedBundle`], fail-closed, never a silent skip.
pub const SIGNTOOL_PATH_ENV: &str = "CT_SIGNTOOL_PATH";

/// Pure helper: given the raw env var value (or `None`), decide whether
/// it's usable as an absolute `signtool.exe` path. Deliberately NOT
/// `#[cfg(windows)]` — kept cross-platform so this decision logic gets
/// real `cargo test` coverage on THIS (macOS) machine, unlike the
/// OS-touching [`verify_authenticode`] wrapper itself, which only compiles
/// on Windows and has never been run anywhere. `#[allow(dead_code)]` on a
/// non-Windows, non-test build (e.g. a plain macOS `cargo build`): its only
/// production caller ([`verify_authenticode`]) is `#[cfg(windows)]`-gated
/// out here, and its test coverage below only runs under `cargo test` —
/// this is intentional cross-platform testability, not actually-dead code.
#[allow(dead_code)]
fn resolve_signtool_path(raw: Option<&str>) -> Option<&str> {
    let raw = raw?;
    if raw.is_empty() {
        return None;
    }
    if Path::new(raw).is_absolute() {
        Some(raw)
    } else {
        None
    }
}

/// Windows' pre-promote check on a staged bundle (an MSI, or an extracted
/// staging directory containing one — the exact staged-artifact shape is
/// `updater::check`'s concern, not this function's): `signtool verify /pa
/// /tw` against `bundle_path`. There is no staple to check on Windows
/// (ADR-M9-004) — Authenticode signature validity is the nearest analog,
/// and version-monotonicity (this ADR's OTHER named half) is already
/// enforced upstream, once, cross-platform, by [`after_authenticated`]'s
/// downgrade check inside [`verify_update`]/[`verify_update_multisig`] —
/// this function does not re-implement or duplicate that check.
///
/// Fails closed on every non-success path: a missing/non-absolute
/// [`SIGNTOOL_PATH_ENV`], a failure to spawn `signtool.exe`, or a non-zero
/// `signtool verify` exit are all [`VerifyError::UnsignedBundle`] — never a
/// silent "couldn't check, assume fine."
///
/// **OWNER-GATED, in full** (no Windows toolchain, no `signtool.exe`, no EV
/// cert exist on this machine — this function has never run against a
/// real signed OR unsigned artifact): whether `/pa /tw` is the right
/// verification-policy flag combination for THIS app's actual signing
/// shape, and whether a real EV-signed MSI produced by
/// `scripts/sign-windows.ps1` actually passes this check end to end, are
/// both unverified here. `windows-parity.md` §3 Q3 also names the
/// SmartScreen reputation gap (a DIFFERENT, non-deterministic system this
/// function does not touch or attempt to satisfy) as its own separate,
/// owner-gated residual — recommended mitigation there is an EV cert plus
/// an MDM-pushed `SmartScreenForTrustedAppsEnabled` allow-list for
/// air-gapped fleets, not anything this verify function can itself
/// influence.
#[cfg(windows)]
pub fn verify_authenticode(bundle_path: &Path) -> Result<(), VerifyError> {
    let raw = std::env::var(SIGNTOOL_PATH_ENV).ok();
    let Some(signtool) = resolve_signtool_path(raw.as_deref()) else {
        return Err(VerifyError::UnsignedBundle);
    };

    let output = std::process::Command::new(signtool)
        .arg("verify")
        .arg("/pa")
        .arg("/tw")
        .arg(bundle_path)
        .output();

    match output {
        Ok(o) if o.status.success() => Ok(()),
        _ => Err(VerifyError::UnsignedBundle),
    }
}

// ---------------------------------------------------------------------------
// verify_pre_promote — the cross-platform dispatcher `updater::check`'s
// single production call site uses (M9/Stream-J)
// ---------------------------------------------------------------------------

/// The pre-promote check [`super::check::apply_update_at`]'s single
/// production call site invokes (ADR-M4-004's "Verified -> Staged" gate's
/// second half). A cross-platform DISPATCHER, never itself doing OS work
/// or re-deciding anything: macOS calls [`verify_staple`] (offline
/// notarization-staple check, unchanged from M4); Windows calls
/// [`verify_authenticode`] (ADR-M9-004 — no staple exists on Windows,
/// Authenticode signature validity is the nearest analog); every other
/// target fails closed exactly as `verify_staple`'s PRE-M9
/// `#[cfg(not(target_os = "macos"))]` stub always did
/// ([`VerifyError::UnstapledBundle`], never guessed). Introducing this
/// dispatcher — rather than leaving [`verify_staple`] itself compiled (and
/// silently wrong) on every non-macOS target — is what lets
/// [`verify_staple`] become genuinely `#[cfg(target_os = "macos")]`-only
/// below: a caller that needs "the right pre-promote check for whatever
/// platform this is" now names THIS function, never `verify_staple`
/// directly, off macOS.
#[cfg(target_os = "macos")]
pub fn verify_pre_promote(bundle_path: &Path) -> Result<(), VerifyError> {
    verify_staple(bundle_path)
}

/// See [`verify_pre_promote`] (macOS arm) — this is the Windows arm.
#[cfg(windows)]
pub fn verify_pre_promote(bundle_path: &Path) -> Result<(), VerifyError> {
    verify_authenticode(bundle_path)
}

/// See [`verify_pre_promote`] (macOS arm) — the fail-closed fallback for
/// every OTHER target (e.g. a Linux dev build of this crate), matching
/// `verify_staple`'s own pre-M9 off-macOS behavior exactly: refuse,
/// unconditionally, never guess.
#[cfg(not(any(target_os = "macos", windows)))]
pub fn verify_pre_promote(_bundle_path: &Path) -> Result<(), VerifyError> {
    Err(VerifyError::UnstapledBundle)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn fixtures_dir() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("fixtures")
            .join("updater")
    }

    fn read_fixture(name: &str) -> Vec<u8> {
        let path = fixtures_dir().join(name);
        std::fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
    }

    fn read_fixture_string(name: &str) -> String {
        String::from_utf8(read_fixture(name)).unwrap_or_else(|e| panic!("utf8 {name}: {e}"))
    }

    fn old_current() -> Version {
        // Every fixture manifest's `app_version` is chosen to be newer than
        // this, so the ONLY thing under test in the sig/hash tests is the
        // sig/hash logic, not an incidental downgrade refusal.
        Version {
            major: 0,
            minor: 0,
            patch: 0,
        }
    }

    // -- sha256 self-test (NIST/FIPS 180-4 vectors) ------------------------

    #[test]
    fn sha256_matches_known_test_vectors() {
        assert_eq!(
            hex_of(&sha256(b"")),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            hex_of(&sha256(b"abc")),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            hex_of(&sha256(
                b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
            )),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
    }

    fn hex_of(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    // -- Version -----------------------------------------------------------

    #[test]
    fn version_parses_plain_semver() {
        assert_eq!(
            Version::parse("1.2.3"),
            Some(Version {
                major: 1,
                minor: 2,
                patch: 3
            })
        );
    }

    #[test]
    fn version_ignores_a_prerelease_suffix_for_ordering() {
        assert_eq!(
            Version::parse("1.2.3-beta.1"),
            Some(Version {
                major: 1,
                minor: 2,
                patch: 3
            })
        );
    }

    #[test]
    fn version_refuses_malformed_input() {
        assert_eq!(Version::parse("1.2"), None);
        assert_eq!(Version::parse("1.2.3.4"), None);
        assert_eq!(Version::parse("not-a-version"), None);
    }

    #[test]
    fn version_ordering_is_numeric_not_lexicographic() {
        assert!(Version::parse("1.9.0") < Version::parse("1.10.0"));
    }

    // -- verify_update: the happy path --------------------------------------

    #[test]
    fn a_validly_signed_manifest_with_a_matching_artifact_verifies() {
        let artifact = read_fixture("artifact.bin");
        let signature = read_fixture_string("valid-manifest.json.minisig");
        let manifest = read_fixture("valid-manifest.json");

        let verified = verify_update_against(&artifact, &signature, &manifest, &old_current())
            .expect("must verify");
        assert_eq!(
            verified.version,
            Version {
                major: 9,
                minor: 9,
                patch: 9
            }
        );
        assert_eq!(verified.channel, "stable");
    }

    // -- verify_update: adversarial matrix (FF-M4-5) ------------------------

    #[test]
    fn an_empty_missing_signature_is_rejected() {
        let artifact = read_fixture("artifact.bin");
        let signature = read_fixture_string("missing.minisig");
        let manifest = read_fixture("valid-manifest.json");

        let err = verify_update_against(&artifact, &signature, &manifest, &old_current())
            .expect_err("must refuse");
        assert_eq!(err, VerifyError::MalformedSignature);
    }

    #[test]
    fn a_garbage_signature_is_rejected() {
        let artifact = read_fixture("artifact.bin");
        let signature = read_fixture_string("garbage.minisig");
        let manifest = read_fixture("valid-manifest.json");

        let err = verify_update_against(&artifact, &signature, &manifest, &old_current())
            .expect_err("must refuse");
        assert_eq!(err, VerifyError::MalformedSignature);
    }

    #[test]
    fn a_signature_from_the_wrong_key_is_rejected() {
        let artifact = read_fixture("artifact.bin");
        let signature = read_fixture_string("valid-manifest.json.wrongkey.minisig");
        let manifest = read_fixture("valid-manifest.json");

        let err = verify_update_against(&artifact, &signature, &manifest, &old_current())
            .expect_err("must refuse");
        assert_eq!(err, VerifyError::SignatureMismatch);
    }

    #[test]
    fn a_tampered_manifest_against_the_original_valid_signature_is_rejected() {
        // `tampered-manifest.json` is byte-different from `valid-manifest.json`
        // (a swapped artifact_sha256) but paired with the ORIGINAL valid
        // manifest's signature — proving the whole manifest is authenticated,
        // not just some "signature field" within it.
        let artifact = read_fixture("artifact.bin");
        let signature = read_fixture_string("valid-manifest.json.minisig");
        let manifest = read_fixture("tampered-manifest.json");

        let err = verify_update_against(&artifact, &signature, &manifest, &old_current())
            .expect_err("must refuse");
        assert_eq!(err, VerifyError::SignatureMismatch);
    }

    #[test]
    fn an_artifact_that_does_not_match_the_signed_hash_is_rejected() {
        // A validly-signed manifest, but paired with DIFFERENT artifact bytes
        // than the ones its (authenticated) sha256 names.
        let artifact = read_fixture("corrupted-artifact.bin");
        let signature = read_fixture_string("valid-manifest.json.minisig");
        let manifest = read_fixture("valid-manifest.json");

        let err = verify_update_against(&artifact, &signature, &manifest, &old_current())
            .expect_err("must refuse");
        assert_eq!(err, VerifyError::ArtifactHashMismatch);
    }

    #[test]
    fn a_replayed_older_version_is_rejected_as_a_downgrade() {
        let artifact = read_fixture("artifact.bin");
        let signature = read_fixture_string("downgrade-manifest.json.minisig");
        let manifest = read_fixture("downgrade-manifest.json");

        // "current" here is NEWER than the fixture's 0.0.1 — simulating a
        // fleet already on a later release being offered a validly-signed
        // but stale manifest.
        let current = Version {
            major: 5,
            minor: 0,
            patch: 0,
        };
        let err = verify_update_against(&artifact, &signature, &manifest, &current)
            .expect_err("must refuse");
        match err {
            VerifyError::Downgrade {
                attempted,
                current: c,
            } => {
                assert_eq!(
                    attempted,
                    Version {
                        major: 0,
                        minor: 0,
                        patch: 1
                    }
                );
                assert_eq!(c, current);
            }
            other => panic!("expected Downgrade, got {other:?}"),
        }
    }

    #[test]
    fn a_manifest_matching_the_currently_running_version_exactly_is_also_refused() {
        // Anti-replay: NOT strictly "older", but not an upgrade either — see
        // the module doc's note on why `<=` is deliberate.
        let artifact = read_fixture("artifact.bin");
        let signature = read_fixture_string("valid-manifest.json.minisig");
        let manifest = read_fixture("valid-manifest.json");

        let current = Version {
            major: 9,
            minor: 9,
            patch: 9,
        }; // == the fixture's own version
        let err = verify_update_against(&artifact, &signature, &manifest, &current)
            .expect_err("must refuse a same-version replay");
        assert!(matches!(err, VerifyError::Downgrade { .. }));
    }

    #[test]
    fn malformed_manifest_json_is_rejected_even_with_a_wellformed_signature_shape() {
        // A signature that decodes fine but simply won't verify against
        // garbage manifest bytes — must still fail closed as a refusal, not
        // panic, and must not be misreported as a JSON error before the
        // signature is checked (signature-first, per the module doc).
        let artifact = read_fixture("artifact.bin");
        let signature = read_fixture_string("garbage.minisig");
        let manifest = b"{ not json at all";

        let err = verify_update_against(&artifact, &signature, manifest, &old_current())
            .expect_err("must refuse");
        assert_eq!(err, VerifyError::MalformedSignature);
    }

    // -- verify_update_multisig: two-of-N adversarial matrix (FF-M7-TWO-OF-N,
    //    M7/S5) --------------------------------------------------------------

    fn multisig_old_current() -> Version {
        Version {
            major: 0,
            minor: 0,
            patch: 0,
        }
    }

    #[test]
    fn k_valid_distinct_signatures_are_accepted() {
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("multisig-manifest.json");
        let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");
        let sig_b = read_fixture_string("multisig-manifest.json.rootB.minisig");

        let verified = verify_update_multisig_against(
            &artifact,
            &[&sig_a, &sig_b],
            &manifest,
            &multisig_old_current(),
        )
        .expect("two distinct valid signatures must meet the two-of-N threshold");
        assert_eq!(
            verified.version,
            Version {
                major: 9,
                minor: 9,
                patch: 9
            }
        );
    }

    #[test]
    fn all_n_signatures_present_still_accepts() {
        // More than K distinct valid signatures is fine — THRESHOLD_K is a
        // MINIMUM, not an exact count.
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("multisig-manifest.json");
        let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");
        let sig_b = read_fixture_string("multisig-manifest.json.rootB.minisig");
        let sig_c = read_fixture_string("multisig-manifest.json.rootC.minisig");

        assert!(verify_update_multisig_against(
            &artifact,
            &[&sig_a, &sig_b, &sig_c],
            &manifest,
            &multisig_old_current(),
        )
        .is_ok());
    }

    #[test]
    fn k_minus_one_valid_signatures_are_refused() {
        // Exactly ONE valid signature — one short of THRESHOLD_K (2) — must
        // be refused, never treated as "good enough".
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("multisig-manifest.json");
        let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");

        let err = verify_update_multisig_against(
            &artifact,
            &[&sig_a],
            &manifest,
            &multisig_old_current(),
        )
        .expect_err("a single valid signature must never satisfy a two-of-N threshold");
        assert_eq!(
            err,
            VerifyError::InsufficientSignatures {
                valid: 1,
                required: multisig::THRESHOLD_K,
            }
        );
    }

    #[test]
    fn zero_signatures_supplied_is_refused() {
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("multisig-manifest.json");

        let err =
            verify_update_multisig_against(&artifact, &[], &manifest, &multisig_old_current())
                .expect_err("no signatures at all must refuse");
        assert_eq!(
            err,
            VerifyError::InsufficientSignatures {
                valid: 0,
                required: multisig::THRESHOLD_K,
            }
        );
    }

    #[test]
    fn two_valid_signatures_from_the_same_root_do_not_count_twice() {
        // The SAME root's signature, submitted twice (simulating a
        // duplicated/re-submitted single custodian's approval, or an
        // attacker who only ever got one custodian to sign trying to pad
        // the list), must still only satisfy ONE of the two required
        // distinct roots.
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("multisig-manifest.json");
        let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");

        let err = verify_update_multisig_against(
            &artifact,
            &[&sig_a, &sig_a],
            &manifest,
            &multisig_old_current(),
        )
        .expect_err("duplicate signatures from one root must never count as two");
        assert_eq!(
            err,
            VerifyError::InsufficientSignatures {
                valid: 1,
                required: multisig::THRESHOLD_K,
            }
        );
    }

    #[test]
    fn a_mix_of_one_valid_and_one_garbage_signature_is_refused() {
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("multisig-manifest.json");
        let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");
        let garbage = read_fixture_string("garbage.minisig");

        let err = verify_update_multisig_against(
            &artifact,
            &[&sig_a, &garbage],
            &manifest,
            &multisig_old_current(),
        )
        .expect_err("one valid signature plus one garbage signature is still below threshold");
        assert_eq!(
            err,
            VerifyError::InsufficientSignatures {
                valid: 1,
                required: multisig::THRESHOLD_K,
            }
        );
    }

    #[test]
    fn a_signature_from_a_key_outside_the_compiled_in_set_never_counts() {
        // The "attacker" fixture is a structurally-valid minisign signature
        // over the SAME manifest bytes, but from a key that is not one of
        // the three compiled-in roots — it must verify against none of them.
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("multisig-manifest.json");
        let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");
        let attacker_sig = read_fixture_string("multisig-manifest.json.attacker.minisig");

        let err = verify_update_multisig_against(
            &artifact,
            &[&sig_a, &attacker_sig],
            &manifest,
            &multisig_old_current(),
        )
        .expect_err("a non-root signature must never count toward the threshold");
        assert_eq!(
            err,
            VerifyError::InsufficientSignatures {
                valid: 1,
                required: multisig::THRESHOLD_K,
            }
        );
    }

    #[test]
    fn empty_and_missing_signatures_mixed_in_never_count() {
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("multisig-manifest.json");
        let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");
        let sig_b = read_fixture_string("multisig-manifest.json.rootB.minisig");
        let missing = read_fixture_string("missing.minisig"); // empty file

        // k valid distinct + noise (an empty signature entry) still accepts —
        // noise must never SUBTRACT from an otherwise-sufficient threshold.
        assert!(verify_update_multisig_against(
            &artifact,
            &[&sig_a, &sig_b, &missing],
            &manifest,
            &multisig_old_current(),
        )
        .is_ok());
    }

    #[test]
    fn a_downgrade_is_refused_even_with_k_valid_distinct_signatures() {
        // M4's downgrade rule must survive completely intact under the
        // multisig scheme: meeting the two-of-N threshold authenticates the
        // BYTES, it does not exempt the manifest's declared version from the
        // anti-replay/downgrade check.
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("multisig-downgrade-manifest.json");
        let sig_a = read_fixture_string("multisig-downgrade-manifest.json.rootA.minisig");
        let sig_b = read_fixture_string("multisig-downgrade-manifest.json.rootB.minisig");

        let current = Version {
            major: 5,
            minor: 0,
            patch: 0,
        };
        let err = verify_update_multisig_against(&artifact, &[&sig_a, &sig_b], &manifest, &current)
            .expect_err("k-of-N authentication must not exempt a manifest from the downgrade rule");
        match err {
            VerifyError::Downgrade {
                attempted,
                current: c,
            } => {
                assert_eq!(
                    attempted,
                    Version {
                        major: 0,
                        minor: 0,
                        patch: 1
                    }
                );
                assert_eq!(c, current);
            }
            other => panic!("expected Downgrade, got {other:?}"),
        }
    }

    #[test]
    fn a_tampered_manifest_against_original_multisig_signatures_is_refused() {
        // Same "whole manifest is authenticated, not just a signature field"
        // property as the single-root fixture, exercised against the k-of-N
        // path: pairing a DIFFERENT manifest's bytes with valid-looking
        // signatures for the original bytes must fail every root check.
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("tampered-manifest.json"); // M4's tampered fixture
        let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");
        let sig_b = read_fixture_string("multisig-manifest.json.rootB.minisig");

        let err = verify_update_multisig_against(
            &artifact,
            &[&sig_a, &sig_b],
            &manifest,
            &multisig_old_current(),
        )
        .expect_err("signatures over different bytes must not verify against tampered bytes");
        assert_eq!(
            err,
            VerifyError::InsufficientSignatures {
                valid: 0,
                required: multisig::THRESHOLD_K,
            }
        );
    }

    // -- error messages never leak key material / secrets -------------------

    #[test]
    fn no_verify_error_ever_contains_the_trust_root_public_key_or_raw_signature_text() {
        let pubkey = trust::TRUST_ROOT_PUBLIC_KEY_B64;
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("valid-manifest.json");
        let wrongkey_sig = read_fixture_string("valid-manifest.json.wrongkey.minisig");

        let cases: Vec<VerifyError> = vec![
            verify_update_against(&artifact, "", &manifest, &old_current()).unwrap_err(),
            verify_update_against(&artifact, &wrongkey_sig, &manifest, &old_current()).unwrap_err(),
            VerifyError::UnstapledBundle,
            VerifyError::InvalidStaple,
        ];

        for err in cases {
            let display = err.to_string();
            let debug = format!("{err:?}");
            assert!(
                !display.contains(pubkey),
                "Display leaked the trust root: {display}"
            );
            assert!(
                !debug.contains(pubkey),
                "Debug leaked the trust root: {debug}"
            );
            assert!(
                !display.contains(&wrongkey_sig) && !debug.contains(&wrongkey_sig),
                "leaked raw signature text"
            );
        }
    }

    #[test]
    fn no_verify_error_ever_contains_a_multisig_trust_root_public_key_or_raw_signature_text() {
        let artifact = read_fixture("artifact.bin");
        let manifest = read_fixture("multisig-manifest.json");
        let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");
        let attacker_sig = read_fixture_string("multisig-manifest.json.attacker.minisig");

        let cases: Vec<VerifyError> = vec![
            verify_update_multisig_against(&artifact, &[], &manifest, &multisig_old_current())
                .unwrap_err(),
            verify_update_multisig_against(
                &artifact,
                &[&sig_a, &attacker_sig],
                &manifest,
                &multisig_old_current(),
            )
            .unwrap_err(),
        ];

        for err in cases {
            let display = err.to_string();
            let debug = format!("{err:?}");
            for pubkey in multisig::TRUST_ROOTS_B64 {
                assert!(
                    !display.contains(pubkey) && !debug.contains(pubkey),
                    "leaked a multisig trust root: {display} / {debug}"
                );
            }
            assert!(
                !display.contains(&sig_a) && !debug.contains(&sig_a),
                "leaked raw multisig signature text"
            );
        }
    }

    // -- verify_staple: fail-closed on a genuinely unsigned fixture ---------
    // (real `/usr/sbin/spctl`, not a mock — see the function's own doc for
    // what this test can and can't prove.)

    #[cfg(target_os = "macos")]
    #[test]
    fn an_unsigned_fixture_bundle_fails_the_offline_staple_check() {
        let bundle = fixtures_dir().join("staple").join("UnsignedApp.app");
        assert!(
            bundle.exists(),
            "fixture bundle must exist at {}",
            bundle.display()
        );
        let err = verify_staple(&bundle).expect_err("an unsigned fixture must never pass");
        assert_eq!(err, VerifyError::UnstapledBundle);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn a_nonexistent_bundle_path_fails_closed_rather_than_panicking() {
        let bundle = fixtures_dir().join("staple").join("DoesNotExist.app");
        let err = verify_staple(&bundle).expect_err("a missing bundle must refuse, never panic");
        assert_eq!(err, VerifyError::UnstapledBundle);
    }

    // -- verify_pre_promote: the macOS arm must be IDENTICAL to calling
    //    verify_staple directly — the dispatcher must never re-decide
    //    anything, only route (M9/Stream-J). This is the one arm of the
    //    dispatcher this machine can actually execute and compare. ---------

    #[cfg(target_os = "macos")]
    #[test]
    fn verify_pre_promote_on_macos_matches_verify_staple_on_an_unsigned_fixture() {
        let bundle = fixtures_dir().join("staple").join("UnsignedApp.app");
        assert_eq!(verify_pre_promote(&bundle), verify_staple(&bundle));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn verify_pre_promote_on_macos_matches_verify_staple_on_a_missing_bundle() {
        let bundle = fixtures_dir().join("staple").join("DoesNotExist.app");
        assert_eq!(verify_pre_promote(&bundle), verify_staple(&bundle));
    }

    // -- resolve_signtool_path: cross-platform pure logic (M9/Stream-J) —
    //    real `cargo test` coverage on THIS machine, unlike the
    //    `#[cfg(windows)]`-gated `verify_authenticode` wrapper it backs. ---

    #[test]
    fn resolve_signtool_path_accepts_an_absolute_path() {
        // `Path::is_absolute`'s definition of "absolute" is HOST-RULES-
        // dependent — a Windows drive-letter path (`C:\...`) is only
        // recognized as absolute under Windows' own path rules, which this
        // macOS test host does not have; that combination is exercised for
        // real only on a genuine Windows `cargo test` run (owner-gated, no
        // Windows toolchain here). What IS portable, and asserted here: a
        // Unix-style absolute path counts as absolute under THIS host's
        // rules, proving the function's "absolute, full stop — never a
        // relative path" contract, independent of which OS actually runs
        // it.
        assert_eq!(
            resolve_signtool_path(Some("/usr/bin/signtool")),
            Some("/usr/bin/signtool")
        );
    }

    #[test]
    fn resolve_signtool_path_rejects_a_relative_path() {
        assert_eq!(resolve_signtool_path(Some("signtool.exe")), None);
        assert_eq!(resolve_signtool_path(Some("bin/signtool.exe")), None);
    }

    #[test]
    fn resolve_signtool_path_rejects_empty_or_absent() {
        assert_eq!(resolve_signtool_path(Some("")), None);
        assert_eq!(resolve_signtool_path(None), None);
    }

    // -- UnsignedBundle error message never leaks anything sensitive
    //    (mirrors the existing staple/signature leak tests above) ----------

    #[test]
    fn unsigned_bundle_error_message_is_generic_and_non_empty() {
        let err = VerifyError::UnsignedBundle;
        let display = err.to_string();
        assert!(!display.is_empty());
        assert!(
            !display.contains("signtool"),
            "message should be user-facing, not tool-internal"
        );
    }
}
