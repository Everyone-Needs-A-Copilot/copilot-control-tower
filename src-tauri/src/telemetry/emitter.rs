//! The telemetry emitter (M7/S3 + S9, `.copilot/wp/43.md`, tasks 62/68) —
//! the piece that actually SENDS a content-free [`FleetEvent`] somewhere,
//! gated by [`super::optin::telemetry_optin`]. Everything upstream of this
//! file ([`super::schema`]'s [`FleetEvent`] shape, [`super::optin`]'s gate)
//! already exists; this module is the transport SEAM plus the mapping from
//! this crate's own already-routed facts (M6's [`crate::routing::ItSignal`]s,
//! a doctor status transition) into [`FleetEvent`]s.
//!
//! ## Off means off — no network, no attempt
//!
//! [`TelemetrySink::emit`] checks [`super::optin::telemetry_optin`] FIRST,
//! every call. When it resolves [`super::optin::TelemetryDecision::Disabled`]
//! (the default), this function returns immediately — [`TelemetryTransport::
//! send`] is never invoked, not even once, not even with an empty batch.
//! `emitter_is_a_no_op_when_disabled_zero_transport_calls` (below) proves
//! this against a transport that panics if it is EVER called, not merely one
//! that records zero calls — the strongest form of "never attempted" this
//! crate's test harness can express.
//!
//! ## Content-free by construction, not by convention
//!
//! [`TelemetryTransport::send`] takes `&[FleetEvent]` — the SAME content-free
//! type [`super::schema`]'s own module doc already pins to a closed set of
//! ids/enums/numbers, zero free-text fields (`tests/
//! fitness_m7_telemetry_schema_content_free.rs`). There is no second, richer
//! type this seam could accept instead — the trait signature itself is the
//! structural proof a personal item name cannot reach the transport boundary
//! through this seam; `tests/fitness_m7_telemetry_transport_content_free.rs`
//! pins the source-level signature (a scoped, S3-level pin — the FULL
//! FF-M7-CONTENTFREE suite across every producer is a later, `qa`-owned
//! stream per `fitness_m7_telemetry_schema_content_free.rs`'s own doc).
//!
//! ## Real transport is owner-gated infra — this ships the seam + a mock
//!
//! [`MockTransport`] always succeeds and touches no network — a stand-in
//! that lets [`TelemetrySink`] be exercised end to end without a live
//! collector. [`CaptureTransport`] is the test double every unit test below
//! uses to assert exactly which [`FleetEvent`]s were sent. The REAL HTTP
//! transport to an org's own collector endpoint (owner infra, G-M7-3 — the
//! collector's own query/ingest API is undefined today) is NOT built here;
//! wiring a real `reqwest`-backed [`TelemetryTransport`] behind
//! [`super::optin::TelemetryDecision::Enabled`]'s resolved `endpoint` is
//! future, owner-gated work, batched alongside G-M7-3 — building it now
//! would mean guessing a wire contract for a collector API this milestone
//! does not define.
//!
//! ## Fail-closed: a transport error is retained, never a crash
//!
//! Mirrors `routing::emit`'s own "a sink error is audited + retained, never
//! silently dropped, never a panic" discipline exactly, applied here to the
//! transport boundary instead of the `ItSignalSink` boundary — see
//! [`audit_transport_failure`] and [`TelemetryEmitOutcome`].
//!
//! ## G-M7-6 (flagged, not resolved here): retry/backoff params
//!
//! [`DEFAULT_RETRY_ATTEMPTS`]/[`DEFAULT_RETRY_BACKOFF`] are named,
//! documented placeholders for a real retry/backoff policy a future,
//! owner-ratified transport would use — this build performs exactly ONE
//! send attempt per [`TelemetrySink::emit`] call and relies on the next poll
//! cycle as its retry (the same "retained for the caller, not busy-looped
//! inside this fail-closed boundary" discipline `routing::emit::
//! ItSignalSinkError` already establishes). A real retry/backoff loop built
//! against these consts is deferred until G-M7-6 is ratified, not silently
//! guessed at here.
//!
//! ## Mapping M6's `ItSignal`s into `FleetEvent`s
//!
//! [`fleet_event_kind_for_it_signal`] maps [`ItSignalKind`]'s variants onto
//! [`super::schema::FleetEventKind`]'s — a partial mapping, deliberately:
//! [`super::schema`]'s own module doc already narrows `FleetEventKind` to
//! ONE unified, minimal set (not a 1:1 mirror of every `ItSignalKind`
//! variant), so a handful of `ItSignalKind` variants
//! (`DeprovisionAmbiguous`/`BobItemTimedOut`/`PruneNeedsReview`/
//! `RepairNeedsReview`/`UnrecognizedEvent`) have no analytics-telemetry
//! equivalent YET and map to `None` — analytics telemetry stays silent for
//! them rather than inventing a mapping the frozen schema doesn't name
//! (never a fabricated "closest fit"). `LocalSink`'s own IT-audit path
//! (M6/S3, unchanged) still records every one of these regardless — this
//! mapping only decides what the SEPARATE, opt-in analytics stream reports.

use std::fmt;
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use super::optin::{telemetry_optin, TelemetryDecision};
use super::schema::{FleetEvent, FleetEventKind, Host, MachineId, OccurredAt};
use crate::model::state::{CliStatus, DoctorVerdict};
use crate::routing::{ItSignal, ItSignalKind};

// == Retry/backoff placeholders (G-M7-6, unratified) =========================

/// Named placeholder for a future retry policy's attempt count. See the
/// module doc's "G-M7-6" section — not wired into an actual retry loop here.
pub const DEFAULT_RETRY_ATTEMPTS: u32 = 3;

/// Named placeholder for a future retry policy's backoff duration. See the
/// module doc's "G-M7-6" section — not wired into an actual retry loop here.
pub const DEFAULT_RETRY_BACKOFF: Duration = Duration::from_secs(5);

// == The transport seam ======================================================

/// A transport failed to deliver a batch. Carries only a short,
/// human-readable description — never a re-embedded event payload (there is
/// nothing content-bearing in a `&[FleetEvent]` to leak in the first place;
/// see the module doc's "content-free by construction" section).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransportError(pub String);

impl fmt::Display for TransportError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "telemetry transport error: {}", self.0)
    }
}

impl std::error::Error for TransportError {}

/// The telemetry transport seam. `send` takes ONLY `&[FleetEvent]` — see the
/// module doc's "content-free by construction" section for why the
/// signature itself is the structural guarantee here, not a convention.
/// `Send + Sync` so a `TelemetrySink` holding a `Box<dyn TelemetryTransport>`
/// can be `.manage()`d as Tauri state (invariant #2 — one managed instance,
/// same discipline `routing::emit::LocalSink` already follows).
pub trait TelemetryTransport: Send + Sync {
    /// Sends one batch of already-content-free events to `endpoint` (the
    /// value `TelemetryDecision::Enabled` resolved — never guessed, never
    /// defaulted; see `telemetry::optin`'s own doc). Implementations decide
    /// their own wire format; [`TelemetrySink::emit`] treats any `Err` as
    /// "undelivered, never silently dropped" (see the module doc).
    fn send(&self, endpoint: &str, events: &[FleetEvent]) -> Result<(), TransportError>;
}

/// The real transport's stand-in: always succeeds, touches no network. See
/// the module doc's "real transport is owner-gated infra" section for why
/// this — not a live HTTP client — is what this build ships.
#[derive(Debug, Default)]
pub struct MockTransport;

impl TelemetryTransport for MockTransport {
    fn send(&self, _endpoint: &str, _events: &[FleetEvent]) -> Result<(), TransportError> {
        Ok(())
    }
}

/// One recorded [`CaptureTransport::send`] call — the endpoint it was given
/// plus the exact batch, so a test can assert on both.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapturedSend {
    pub endpoint: String,
    pub events: Vec<FleetEvent>,
}

/// A test double that records every `send` call it receives, and can
/// optionally simulate a transport failure (an offline collector /
/// unreachable endpoint) — used by this module's own tests, and available to
/// any future integration test that needs to assert on what telemetry
/// actually sent without a real network call.
#[derive(Debug, Default)]
pub struct CaptureTransport {
    calls: Mutex<Vec<CapturedSend>>,
    fail: bool,
}

impl CaptureTransport {
    /// A transport that always succeeds and records what it received.
    pub fn new() -> Self {
        Self::default()
    }

    /// A transport that always fails (simulates an offline/unreachable
    /// collector) — still records that a call was attempted, so a test can
    /// distinguish "never called" (opt-out) from "called, but failed"
    /// (opted-in, transport error).
    pub fn always_failing() -> Self {
        Self {
            calls: Mutex::new(Vec::new()),
            fail: true,
        }
    }

    /// Every call this transport has recorded so far, in order.
    pub fn calls(&self) -> Vec<CapturedSend> {
        self.calls
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    }

    /// Convenience: every [`FleetEvent`] across every recorded call,
    /// flattened, in order.
    pub fn captured_events(&self) -> Vec<FleetEvent> {
        self.calls().into_iter().flat_map(|c| c.events).collect()
    }
}

impl TelemetryTransport for CaptureTransport {
    fn send(&self, endpoint: &str, events: &[FleetEvent]) -> Result<(), TransportError> {
        self.calls
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .push(CapturedSend {
                endpoint: endpoint.to_string(),
                events: events.to_vec(),
            });
        if self.fail {
            return Err(TransportError("simulated transport outage".to_string()));
        }
        Ok(())
    }
}

/// A transport that panics if `send` is EVER invoked — the strongest
/// possible proof that "opted-out ⇒ zero bytes leave the machine" means
/// literally no attempt, not merely zero successful calls. Used only by
/// this module's own `Disabled`-path tests.
#[derive(Debug, Default)]
pub struct PanicIfCalledTransport;

impl TelemetryTransport for PanicIfCalledTransport {
    fn send(&self, _endpoint: &str, _events: &[FleetEvent]) -> Result<(), TransportError> {
        panic!(
            "TelemetryTransport::send must never be invoked while telemetry is opted out — \
             off means off, not 'best-effort silence'"
        );
    }
}

/// Emits the transport-failure audit line via `eprintln!` — same interim
/// facility `routing::emit::audit_sink_failure`/`managed::forced::
/// audit_ignored_user_domain_value` already use (no logging/tracing crate in
/// this crate yet). Carries only the error text and how many events were in
/// the failed batch — never the events' own content (already content-free,
/// but this function doesn't even try to serialize them).
fn audit_transport_failure(error: &TransportError, batch_len: usize) {
    eprintln!(
        "[copilot-control-tower] audit: telemetry transport failed for a {batch_len}-event \
         batch: {error} — retained in TelemetryEmitOutcome::error, never silently dropped. A \
         retry/backoff loop (G-M7-6, unratified: DEFAULT_RETRY_ATTEMPTS={DEFAULT_RETRY_ATTEMPTS}, \
         DEFAULT_RETRY_BACKOFF={DEFAULT_RETRY_BACKOFF:?}) is owner-gated, not built here."
    );
}

/// The result of one [`TelemetrySink::emit`] call.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct TelemetryEmitOutcome {
    /// How many events were actually handed to the transport (0 whenever
    /// telemetry is disabled, the batch was empty, or the transport failed).
    pub sent: usize,
    /// Retained, never silently discarded — see the module doc's
    /// "fail-closed" section.
    pub error: Option<TransportError>,
}

/// The real emitter — owns a transport, gates every call on the opt-in
/// decision. `.manage()`d as Tauri state (`lib.rs`), read by `timer.rs` on
/// every doctor poll (M7/S9).
pub struct TelemetrySink {
    transport: Box<dyn TelemetryTransport>,
}

impl TelemetrySink {
    pub fn new(transport: Box<dyn TelemetryTransport>) -> Self {
        Self { transport }
    }

    /// The real entry point: resolves [`telemetry_optin`] fresh on every
    /// call (never cached — a live MDM profile change must take effect on
    /// the very next poll, not after a stale in-memory flag expires) and
    /// gates on it. See [`Self::emit_via`] for the carrier-generic,
    /// unit-testable form this delegates to.
    pub fn emit(&self, events: &[FleetEvent]) -> TelemetryEmitOutcome {
        self.emit_via(&telemetry_optin(), events)
    }

    /// The decision-generic gate. `Disabled` (the default, and every
    /// absent/partial/untrusted-carrier case per `telemetry::optin`'s own
    /// doc) is a hard, total no-op — [`TelemetryTransport::send`] is never
    /// invoked, not even with an empty batch. `Enabled` with an EMPTY batch
    /// is likewise a no-op (nothing to send, so nothing is sent) — a doctor
    /// poll that produced no new fact must not still cost a network call.
    pub fn emit_via(
        &self,
        decision: &TelemetryDecision,
        events: &[FleetEvent],
    ) -> TelemetryEmitOutcome {
        let TelemetryDecision::Enabled { endpoint } = decision else {
            return TelemetryEmitOutcome::default();
        };
        if events.is_empty() {
            return TelemetryEmitOutcome::default();
        }
        match self.transport.send(endpoint, events) {
            Ok(()) => TelemetryEmitOutcome {
                sent: events.len(),
                error: None,
            },
            Err(err) => {
                audit_transport_failure(&err, events.len());
                TelemetryEmitOutcome {
                    sent: 0,
                    error: Some(err),
                }
            }
        }
    }
}

/// A placeholder local machine id this build's LIVE wiring uses. The REAL
/// per-install HMAC-SHA256 derivation ([`super::schema::derive_machine_id`])
/// needs a real hardware UUID plus a persisted per-install keychain salt —
/// both still-deferred OS-integration work (see `telemetry`'s own module
/// doc). An honest, fixed placeholder, never presented as a real derived id.
pub const DEV_LOCAL_MACHINE_ID: &str = "local-machine";

/// The Tauri-managed telemetry aggregation (M7/S9) — owns the
/// [`TelemetrySink`] plus the fixed local [`MachineId`]/[`Host`] this build's
/// live wiring uses. `.manage()`d once in `lib.rs`'s `.setup()`, alongside
/// `routing::emit::LocalSink`; `timer::poll_once` is the one live caller.
pub struct TelemetryState {
    sink: TelemetrySink,
    machine_id: MachineId,
    host: Host,
}

impl TelemetryState {
    pub fn new(sink: TelemetrySink, machine_id: MachineId, host: Host) -> Self {
        Self {
            sink,
            machine_id,
            host,
        }
    }

    /// The production instance: [`MockTransport`] (see the module doc for
    /// why the real HTTP transport is owner-gated — this never touches a
    /// network, even if a future forced-domain carrier somehow enabled
    /// telemetry on a dev box), the dev/mock local machine id
    /// ([`DEV_LOCAL_MACHINE_ID`]), and `Host::ClaudeCode` (this app
    /// supervises the `copilot`/`cc` CLI; no live per-poll host detection
    /// exists yet — a fixed, flagged placeholder, same discipline as the
    /// machine id).
    pub fn production() -> Self {
        Self::new(
            TelemetrySink::new(Box::new(MockTransport)),
            MachineId::from_hash(DEV_LOCAL_MACHINE_ID),
            Host::ClaudeCode,
        )
    }

    /// M7/S9's live wiring entry point — `timer::poll_once`'s one call
    /// site, once per doctor poll. Builds this poll's [`FleetEvent`]s
    /// ([`fleet_events_for_poll`]) from the SAME already-trusted `verdict`
    /// this poll's `routing::wire::wire_doctor` call already routed,
    /// re-derived via `routing::wire::doctor_it_signals` — a pure, sink-free
    /// read (see that function's own doc), never a second CLI spawn and
    /// never a second trust decision — and hands the result to the sink.
    /// **Off means off**: when telemetry is opted out,
    /// [`TelemetrySink::emit`]'s own gate makes this whole call a no-op
    /// before a single byte is ever prepared for a network call.
    pub fn emit_for_doctor_verdict(
        &self,
        verdict: &DoctorVerdict,
        previous_status: Option<CliStatus>,
    ) -> TelemetryEmitOutcome {
        let ctx = FleetEventContext {
            machine_id: self.machine_id.clone(),
            host: self.host,
            status: verdict.status,
            occurred_at: OccurredAt::from_rfc3339(now_rfc3339()),
        };
        let it_signals = crate::routing::wire::doctor_it_signals(verdict);
        let events = fleet_events_for_poll(&ctx, previous_status, &it_signals);
        self.sink.emit(&events)
    }
}

// == Mapping ItSignal -> FleetEvent ==========================================

/// The per-poll facts every [`FleetEvent`] this module builds needs, beyond
/// the one content-free fact ([`ItSignalKind`], or "the status changed")
/// that varies event to event. Bundled so callers (`timer.rs`) build it
/// once per poll rather than threading four parameters through every
/// mapping function below.
#[derive(Debug, Clone)]
pub struct FleetEventContext {
    pub machine_id: MachineId,
    pub host: Host,
    pub status: CliStatus,
    pub occurred_at: OccurredAt,
}

/// Maps an [`ItSignalKind`] onto the analytics-telemetry [`FleetEventKind`]
/// it mirrors — `None` for the handful of kinds `telemetry::schema`'s own
/// closed set does not (yet) name. See the module doc's own "Mapping M6's
/// `ItSignal`s" section for why a partial mapping is deliberate, not an
/// oversight.
pub fn fleet_event_kind_for_it_signal(kind: ItSignalKind) -> Option<FleetEventKind> {
    match kind {
        ItSignalKind::SecurityShadowAutoSuspended => Some(FleetEventKind::SecurityShadowSuspended),
        ItSignalKind::HeldMajorAwaitingApproval => Some(FleetEventKind::HeldMajor),
        ItSignalKind::AuthRevokedDeprovisionOffer => Some(FleetEventKind::Revoked),
        ItSignalKind::SignatureFailure => Some(FleetEventKind::SignatureFailure),
        ItSignalKind::PolicyDenial => Some(FleetEventKind::PolicyConflict),
        ItSignalKind::PersistenceDisabled => Some(FleetEventKind::PersistenceDisabled),
        ItSignalKind::NotificationsDisabled => Some(FleetEventKind::NotificationsOff),
        ItSignalKind::DeprovisionTriggered => Some(FleetEventKind::DeprovisionTriggered),
        // No FleetEventKind equivalent exists yet for these — see the
        // module doc; analytics telemetry stays silent rather than
        // inventing a mapping the frozen schema doesn't name. The M6
        // LocalSink audit path (unchanged) still records every one of these
        // regardless.
        ItSignalKind::DeprovisionAmbiguous
        | ItSignalKind::BobItemTimedOut
        | ItSignalKind::PruneNeedsReview
        | ItSignalKind::RepairNeedsReview
        | ItSignalKind::UnrecognizedEvent => None,
    }
}

/// Builds one [`FleetEvent`] from an already-routed [`ItSignal`], if (and
/// only if) [`fleet_event_kind_for_it_signal`] has a mapping for its kind.
/// `escalate` mirrors `signal.admin_contact.is_some()` — the SAME boolean
/// fact `routing::emit::LocalSink` already records as `deliverable`, per
/// [`FleetEvent::escalate`]'s own doc.
///
/// `occurrence_count` is always `1` in this build — this wiring layer does
/// not yet track "how many consecutive polls has this exact condition
/// persisted" across polls (a genuinely new, small piece of state no
/// current caller maintains). This is an honest deferral, not a fabricated
/// count: mirrors this crate's own precedent for "no live producer yet"
/// facts (`render::bob_lane::BobLaneView::notifications_denied` is always
/// `false` for the identical reason). A future stream that adds real
/// cross-poll tracking plugs into this SAME function's caller; nothing
/// about this mapping needs to change when it does.
pub fn fleet_event_for_it_signal(signal: &ItSignal, ctx: &FleetEventContext) -> Option<FleetEvent> {
    let kind = fleet_event_kind_for_it_signal(signal.kind)?;
    Some(FleetEvent::new(
        ctx.machine_id.clone(),
        ctx.host,
        ctx.status,
        kind,
        ctx.occurred_at.clone(),
        signal.admin_contact.is_some(),
        1,
    ))
}

/// Builds the `status_change` [`FleetEvent`] for one poll — `escalate` is
/// always `false` (an ordinary status transition is not, itself, an IT
/// escalation; a concurrent safety signal produces its OWN event via
/// [`fleet_event_for_it_signal`]).
pub fn fleet_event_for_status_change(ctx: &FleetEventContext) -> FleetEvent {
    FleetEvent::new(
        ctx.machine_id.clone(),
        ctx.host,
        ctx.status,
        FleetEventKind::StatusChange,
        ctx.occurred_at.clone(),
        false,
        1,
    )
}

/// Builds every [`FleetEvent`] one doctor poll should report: a
/// `status_change` event only when `previous_status` differs from
/// `ctx.status` (never on every poll — a poll that reconfirmed the SAME
/// status is not itself a new fact), plus one mapped event per `it_signals`
/// entry that has a [`FleetEventKind`] ([`fleet_event_kind_for_it_signal`]'s
/// `None` cases are silently skipped, per that function's own doc — never a
/// fabricated fallback kind).
pub fn fleet_events_for_poll(
    ctx: &FleetEventContext,
    previous_status: Option<CliStatus>,
    it_signals: &[ItSignal],
) -> Vec<FleetEvent> {
    let mut events = Vec::new();
    if previous_status != Some(ctx.status) {
        events.push(fleet_event_for_status_change(ctx));
    }
    events.extend(
        it_signals
            .iter()
            .filter_map(|signal| fleet_event_for_it_signal(signal, ctx)),
    );
    events
}

// == A from-scratch RFC 3339 (UTC, second precision) formatter ===============
//
// No `chrono` dependency exists in this crate; `occurred_at` only needs a
// fixed-format UTC timestamp (`telemetry::schema::OccurredAt`'s own doc:
// "copy, don't compute" — this IS the one place that copy is produced, from
// the OS clock, never re-derived from CLI content). Howard Hinnant's
// `civil_from_days` algorithm (widely published, e.g. `<chrono>`'s own
// reference implementation) — from-scratch here the same way
// `telemetry::schema::hmac_sha256` is from-scratch, rather than pulling in a
// full date/time crate for one call site.

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32; // [1, 12]
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// Formats `t` as a fixed-format `YYYY-MM-DDTHH:MM:SSZ` string (UTC, second
/// precision) — the same shape every other `--json` verb's `generated_at`
/// already uses. Never panics: a `SystemTime` before the epoch (a clock this
/// broken has bigger problems) clamps to the epoch itself rather than
/// unwrapping.
pub fn format_rfc3339_utc(t: SystemTime) -> String {
    let secs = t.duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
    let days = (secs / 86_400) as i64;
    let rem = secs % 86_400;
    let (h, m, s) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    let (y, mo, d) = civil_from_days(days);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{m:02}:{s:02}Z")
}

/// The current instant, formatted the same way [`format_rfc3339_utc`] does —
/// the one call site in this module that actually reads the OS clock.
pub fn now_rfc3339() -> String {
    format_rfc3339_utc(SystemTime::now())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::test_env::ENV_LOCK;
    use crate::managed::forced::FORCED_OVERRIDE_ENV_PREFIX;
    use crate::telemetry::optin::{TELEMETRY_ENABLED_KEY, TELEMETRY_ENDPOINT_KEY};

    fn set_forced(key: &str, value: &str) {
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(
                format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase()),
                value,
            )
        };
    }
    fn clear_forced(key: &str) {
        unsafe {
            std::env::remove_var(format!(
                "{FORCED_OVERRIDE_ENV_PREFIX}{}",
                key.to_ascii_uppercase()
            ))
        };
    }

    fn sample_event() -> FleetEvent {
        FleetEvent::new(
            MachineId::from_hash("m-test"),
            Host::ClaudeCode,
            CliStatus::Healthy,
            FleetEventKind::StatusChange,
            OccurredAt::from_rfc3339("2026-07-07T09:10:44Z"),
            false,
            1,
        )
    }

    fn ctx() -> FleetEventContext {
        FleetEventContext {
            machine_id: MachineId::from_hash("m-test"),
            host: Host::ClaudeCode,
            status: CliStatus::NeedsAttention,
            occurred_at: OccurredAt::from_rfc3339("2026-07-07T09:10:44Z"),
        }
    }

    // -- CaptureTransport -----------------------------------------------------

    #[test]
    fn capture_transport_records_calls_and_flattens_events() {
        let t = CaptureTransport::new();
        t.send("https://collect.example/v1", &[sample_event()])
            .unwrap();
        assert_eq!(t.calls().len(), 1);
        assert_eq!(t.captured_events().len(), 1);
        assert_eq!(t.calls()[0].endpoint, "https://collect.example/v1");
    }

    #[test]
    fn always_failing_transport_still_records_the_attempted_call() {
        let t = CaptureTransport::always_failing();
        let err = t.send("https://collect.example/v1", &[sample_event()]);
        assert!(err.is_err());
        assert_eq!(
            t.calls().len(),
            1,
            "a failed attempt must still be observable, distinguishing it from opt-out silence"
        );
    }

    // -- TelemetrySink::emit_via — the opt-in gate itself ---------------------

    /// FF-M7-CONTENTFREE/opt-out: `Disabled` ⇒ ZERO transport calls, proven
    /// against a transport that panics if ever invoked — the strongest form
    /// of "off means off" this harness can express.
    #[test]
    fn emitter_is_a_no_op_when_disabled_zero_transport_calls() {
        let sink = TelemetrySink::new(Box::new(PanicIfCalledTransport));
        let outcome = sink.emit_via(&TelemetryDecision::Disabled, &[sample_event()]);
        assert_eq!(outcome, TelemetryEmitOutcome::default());
    }

    #[test]
    fn emitter_is_a_no_op_when_disabled_even_with_an_empty_batch() {
        let sink = TelemetrySink::new(Box::new(PanicIfCalledTransport));
        let outcome = sink.emit_via(&TelemetryDecision::Disabled, &[]);
        assert_eq!(outcome, TelemetryEmitOutcome::default());
    }

    /// The mirror-image proof, via a `CaptureTransport`: 0 calls recorded.
    #[test]
    fn disabled_capture_transport_receives_zero_calls() {
        let transport = std::sync::Arc::new(CaptureTransport::new());
        struct ArcTransport(std::sync::Arc<CaptureTransport>);
        impl TelemetryTransport for ArcTransport {
            fn send(&self, e: &str, ev: &[FleetEvent]) -> Result<(), TransportError> {
                self.0.send(e, ev)
            }
        }
        let sink = TelemetrySink::new(Box::new(ArcTransport(transport.clone())));
        sink.emit_via(&TelemetryDecision::Disabled, &[sample_event()]);
        assert!(transport.calls().is_empty());
    }

    /// Enabled + a non-empty batch ⇒ the transport receives EXACTLY those
    /// content-free events, at the resolved endpoint.
    #[test]
    fn emitter_sends_the_exact_batch_when_enabled() {
        let events = vec![sample_event(), fleet_event_for_status_change(&ctx())];
        let shared = std::sync::Arc::new(CaptureTransport::new());
        struct Shared(std::sync::Arc<CaptureTransport>);
        impl TelemetryTransport for Shared {
            fn send(&self, e: &str, ev: &[FleetEvent]) -> Result<(), TransportError> {
                self.0.send(e, ev)
            }
        }
        let sink = TelemetrySink::new(Box::new(Shared(shared.clone())));
        let decision = TelemetryDecision::Enabled {
            endpoint: "https://collect.acme.example/v1".to_string(),
        };
        let outcome = sink.emit_via(&decision, &events);
        assert_eq!(outcome.sent, 2);
        assert!(outcome.error.is_none());
        assert_eq!(shared.captured_events(), events);
        assert_eq!(
            shared.calls()[0].endpoint,
            "https://collect.acme.example/v1"
        );
    }

    #[test]
    fn emitter_is_a_no_op_when_enabled_but_the_batch_is_empty() {
        let transport = CaptureTransport::new();
        let sink = TelemetrySink::new(Box::new(transport));
        let decision = TelemetryDecision::Enabled {
            endpoint: "https://collect.acme.example/v1".to_string(),
        };
        let outcome = sink.emit_via(&decision, &[]);
        assert_eq!(outcome, TelemetryEmitOutcome::default());
    }

    /// Fail-closed: a transport error is retained on the outcome, never a
    /// panic, and `sent` stays 0.
    #[test]
    fn a_transport_failure_is_retained_never_a_panic() {
        let sink = TelemetrySink::new(Box::new(CaptureTransport::always_failing()));
        let decision = TelemetryDecision::Enabled {
            endpoint: "https://collect.acme.example/v1".to_string(),
        };
        let outcome = sink.emit_via(&decision, &[sample_event()]);
        assert_eq!(outcome.sent, 0);
        assert_eq!(
            outcome.error,
            Some(TransportError("simulated transport outage".to_string()))
        );
    }

    /// `TelemetrySink::emit` (the REAL entry point, not `emit_via`) actually
    /// consults the live `telemetry_optin()` gate end to end through the
    /// dev-mockable `managed::forced` env seam — default disabled.
    #[test]
    fn real_emit_entry_point_is_disabled_by_default() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        clear_forced(TELEMETRY_ENABLED_KEY);
        clear_forced(TELEMETRY_ENDPOINT_KEY);
        let sink = TelemetrySink::new(Box::new(PanicIfCalledTransport));
        let outcome = sink.emit(&[sample_event()]);
        assert_eq!(outcome, TelemetryEmitOutcome::default());
    }

    #[test]
    fn real_emit_entry_point_sends_once_the_forced_carrier_enables_it() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_forced(TELEMETRY_ENABLED_KEY, "forced:true");
        set_forced(
            TELEMETRY_ENDPOINT_KEY,
            "forced:https://collect.acme.example/v1",
        );

        let transport = std::sync::Arc::new(CaptureTransport::new());
        struct Shared(std::sync::Arc<CaptureTransport>);
        impl TelemetryTransport for Shared {
            fn send(&self, e: &str, ev: &[FleetEvent]) -> Result<(), TransportError> {
                self.0.send(e, ev)
            }
        }
        let sink = TelemetrySink::new(Box::new(Shared(transport.clone())));
        let outcome = sink.emit(&[sample_event()]);
        assert_eq!(outcome.sent, 1);
        assert_eq!(transport.captured_events(), vec![sample_event()]);

        clear_forced(TELEMETRY_ENABLED_KEY);
        clear_forced(TELEMETRY_ENDPOINT_KEY);
    }

    // -- ItSignal -> FleetEvent mapping ----------------------------------------

    #[test]
    fn every_mapped_it_signal_kind_round_trips_to_the_expected_fleet_event_kind() {
        let expected = [
            (
                ItSignalKind::SecurityShadowAutoSuspended,
                FleetEventKind::SecurityShadowSuspended,
            ),
            (
                ItSignalKind::HeldMajorAwaitingApproval,
                FleetEventKind::HeldMajor,
            ),
            (
                ItSignalKind::AuthRevokedDeprovisionOffer,
                FleetEventKind::Revoked,
            ),
            (
                ItSignalKind::SignatureFailure,
                FleetEventKind::SignatureFailure,
            ),
            (ItSignalKind::PolicyDenial, FleetEventKind::PolicyConflict),
            (
                ItSignalKind::PersistenceDisabled,
                FleetEventKind::PersistenceDisabled,
            ),
            (
                ItSignalKind::NotificationsDisabled,
                FleetEventKind::NotificationsOff,
            ),
            (
                ItSignalKind::DeprovisionTriggered,
                FleetEventKind::DeprovisionTriggered,
            ),
        ];
        for (kind, expected_kind) in expected {
            assert_eq!(fleet_event_kind_for_it_signal(kind), Some(expected_kind));
        }
    }

    #[test]
    fn unmapped_it_signal_kinds_yield_none_never_a_fabricated_fallback() {
        for kind in [
            ItSignalKind::DeprovisionAmbiguous,
            ItSignalKind::BobItemTimedOut,
            ItSignalKind::PruneNeedsReview,
            ItSignalKind::RepairNeedsReview,
            ItSignalKind::UnrecognizedEvent,
        ] {
            assert_eq!(fleet_event_kind_for_it_signal(kind), None);
        }
    }

    #[test]
    fn fleet_event_for_it_signal_carries_escalate_true_only_when_admin_contact_is_some() {
        let c = ctx();
        let with_contact = ItSignal {
            kind: ItSignalKind::SignatureFailure,
            admin_contact: Some("it@example.com".to_string()),
        };
        let event = fleet_event_for_it_signal(&with_contact, &c).expect("mapped kind");
        assert!(event.escalate);

        let without_contact = ItSignal {
            kind: ItSignalKind::SignatureFailure,
            admin_contact: None,
        };
        let event = fleet_event_for_it_signal(&without_contact, &c).expect("mapped kind");
        assert!(!event.escalate);
    }

    #[test]
    fn fleet_event_for_it_signal_is_none_for_an_unmapped_kind() {
        let c = ctx();
        let signal = ItSignal {
            kind: ItSignalKind::UnrecognizedEvent,
            admin_contact: None,
        };
        assert!(fleet_event_for_it_signal(&signal, &c).is_none());
    }

    #[test]
    fn fleet_events_for_poll_produces_a_status_change_only_when_status_actually_changed() {
        let c = ctx();
        let unchanged = fleet_events_for_poll(&c, Some(CliStatus::NeedsAttention), &[]);
        assert!(
            unchanged.is_empty(),
            "same status as last poll must not re-emit"
        );

        let changed = fleet_events_for_poll(&c, Some(CliStatus::Healthy), &[]);
        assert_eq!(changed.len(), 1);
        assert_eq!(changed[0].event_kind, FleetEventKind::StatusChange);

        let first_poll_ever = fleet_events_for_poll(&c, None, &[]);
        assert_eq!(
            first_poll_ever.len(),
            1,
            "no previous status at all must still report the first status_change"
        );
    }

    #[test]
    fn fleet_events_for_poll_includes_mapped_signals_and_skips_unmapped_ones() {
        let c = ctx();
        let signals = vec![
            ItSignal {
                kind: ItSignalKind::PolicyDenial,
                admin_contact: None,
            },
            ItSignal {
                kind: ItSignalKind::UnrecognizedEvent,
                admin_contact: None,
            },
        ];
        let events = fleet_events_for_poll(&c, Some(c.status), &signals);
        assert_eq!(
            events.len(),
            1,
            "the unmapped kind must be silently skipped"
        );
        assert_eq!(events[0].event_kind, FleetEventKind::PolicyConflict);
    }

    // -- RFC 3339 formatter -----------------------------------------------------

    #[test]
    fn format_rfc3339_utc_matches_the_unix_epoch() {
        assert_eq!(format_rfc3339_utc(UNIX_EPOCH), "1970-01-01T00:00:00Z");
    }

    #[test]
    fn format_rfc3339_utc_matches_a_known_date() {
        // 2026-07-08T00:00:00Z, cross-checked against Python's
        // `datetime.date(2026, 7, 8).toordinal()` arithmetic
        // (independently, outside this repo) — 20,642 days after the epoch.
        let t = UNIX_EPOCH + Duration::from_secs(20_642 * 86_400);
        assert_eq!(format_rfc3339_utc(t), "2026-07-08T00:00:00Z");
    }

    #[test]
    fn format_rfc3339_utc_carries_the_time_of_day_too() {
        let t = UNIX_EPOCH + Duration::from_secs(20_642 * 86_400 + 3661); // +1h1m1s
        assert_eq!(format_rfc3339_utc(t), "2026-07-08T01:01:01Z");
    }

    #[test]
    fn format_rfc3339_utc_never_panics_before_the_epoch() {
        let before = UNIX_EPOCH.checked_sub(Duration::from_secs(1));
        if let Some(t) = before {
            // Clamps to the epoch rather than panicking.
            assert_eq!(format_rfc3339_utc(t), "1970-01-01T00:00:00Z");
        }
    }

    #[test]
    fn now_rfc3339_produces_a_plausible_length_string() {
        let s = now_rfc3339();
        assert_eq!(s.len(), 20, "YYYY-MM-DDTHH:MM:SSZ is exactly 20 chars");
        assert!(s.ends_with('Z'));
    }

    // -- TelemetryState (M7/S9 live wiring) --------------------------------------

    fn doctor_verdict(
        status: CliStatus,
        auth: Vec<crate::model::state::AuthIssue>,
    ) -> DoctorVerdict {
        DoctorVerdict {
            host: "h".to_string(),
            status,
            offline: false,
            checkers: Vec::new(),
            auth,
        }
    }

    fn revoked_auth_issue() -> crate::model::state::AuthIssue {
        crate::model::state::AuthIssue {
            identity: "bob@example.com".to_string(),
            scope: "org".to_string(),
            state: crate::model::failclosed::AuthState::Revoked,
            expires_at: None,
        }
    }

    /// A transport that forwards to a shared, externally-readable
    /// `CaptureTransport` — lets a test hold onto an `Arc` for assertions
    /// after handing a `Box<dyn TelemetryTransport>` into a `TelemetrySink`.
    struct SharedTransport(std::sync::Arc<CaptureTransport>);
    impl TelemetryTransport for SharedTransport {
        fn send(&self, e: &str, ev: &[FleetEvent]) -> Result<(), TransportError> {
            self.0.send(e, ev)
        }
    }

    /// Opted-out ⇒ `emit_for_doctor_verdict` produces zero transport calls,
    /// even though the verdict genuinely changed status AND carries a
    /// revoked-auth safety signal — proven against `PanicIfCalledTransport`,
    /// the strongest available proof of "reaches no emit path at all".
    #[test]
    fn opted_out_doctor_poll_reaches_no_transport_call() {
        // Must hold ENV_LOCK and clear both forced keys: `telemetry_optin()`
        // reads process-global env vars without any lock of its own, and
        // several sibling tests in this same file legitimately set them
        // while holding this SAME lock — without it, this test could
        // observe a sibling's transient "enabled" state and spuriously trip
        // `PanicIfCalledTransport`.
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        clear_forced(TELEMETRY_ENABLED_KEY);
        clear_forced(TELEMETRY_ENDPOINT_KEY);

        let state = TelemetryState::new(
            TelemetrySink::new(Box::new(PanicIfCalledTransport)),
            MachineId::from_hash("m-test"),
            Host::ClaudeCode,
        );
        let verdict = doctor_verdict(CliStatus::NeedsAttention, vec![revoked_auth_issue()]);
        let outcome = state.emit_for_doctor_verdict(&verdict, Some(CliStatus::Healthy));
        assert_eq!(outcome, TelemetryEmitOutcome::default());
    }

    /// Opted-in ⇒ a status-changing doctor poll carrying a revoked-auth
    /// safety signal produces EXACTLY the two expected `FleetEvent`s: one
    /// `status_change` (the status genuinely differs from the previous
    /// poll) plus one `revoked`-kind event (mapped from the
    /// `AuthRevokedDeprovisionOffer` `ItSignal` this same verdict routes via
    /// `routing::wire::doctor_it_signals`) — content-free, in order.
    #[test]
    fn opted_in_doctor_poll_produces_the_expected_fleet_events() {
        let shared = std::sync::Arc::new(CaptureTransport::new());
        let state = TelemetryState::new(
            TelemetrySink::new(Box::new(SharedTransport(shared.clone()))),
            MachineId::from_hash("m-test"),
            Host::ClaudeCode,
        );

        // Fake an `Enabled` decision by driving `emit_for_doctor_verdict`
        // through a sink whose transport we can observe; the gate itself is
        // exercised separately by the `telemetry_optin`-driven tests above.
        // Since `emit_for_doctor_verdict` always calls the real
        // `TelemetrySink::emit` (which reads the live `telemetry_optin()`),
        // force it enabled via the dev-mockable forced-domain env seam.
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_forced(TELEMETRY_ENABLED_KEY, "forced:true");
        set_forced(
            TELEMETRY_ENDPOINT_KEY,
            "forced:https://collect.acme.example/v1",
        );

        let verdict = doctor_verdict(CliStatus::NeedsAttention, vec![revoked_auth_issue()]);
        let outcome = state.emit_for_doctor_verdict(&verdict, Some(CliStatus::Healthy));

        clear_forced(TELEMETRY_ENABLED_KEY);
        clear_forced(TELEMETRY_ENDPOINT_KEY);

        assert_eq!(outcome.sent, 2);
        let captured = shared.captured_events();
        assert_eq!(captured.len(), 2);
        assert_eq!(captured[0].event_kind, FleetEventKind::StatusChange);
        assert_eq!(captured[0].status, CliStatus::NeedsAttention);
        assert_eq!(captured[1].event_kind, FleetEventKind::Revoked);
        for event in &captured {
            assert_eq!(event.machine_id.as_str(), "m-test");
            assert_eq!(event.host, Host::ClaudeCode);
        }
    }

    /// A poll whose status is UNCHANGED from the previous poll, and carries
    /// no safety signal, produces an empty batch — `emit_for_doctor_verdict`
    /// must not cost a transport call for "nothing new happened".
    #[test]
    fn a_poll_with_no_new_fact_produces_zero_events_and_zero_transport_calls() {
        let shared = std::sync::Arc::new(CaptureTransport::new());
        let state = TelemetryState::new(
            TelemetrySink::new(Box::new(SharedTransport(shared.clone()))),
            MachineId::from_hash("m-test"),
            Host::ClaudeCode,
        );

        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_forced(TELEMETRY_ENABLED_KEY, "forced:true");
        set_forced(
            TELEMETRY_ENDPOINT_KEY,
            "forced:https://collect.acme.example/v1",
        );

        let verdict = doctor_verdict(CliStatus::Healthy, vec![]);
        let outcome = state.emit_for_doctor_verdict(&verdict, Some(CliStatus::Healthy));

        clear_forced(TELEMETRY_ENABLED_KEY);
        clear_forced(TELEMETRY_ENDPOINT_KEY);

        assert_eq!(outcome, TelemetryEmitOutcome::default());
        assert!(shared.calls().is_empty());
    }
}
