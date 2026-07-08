//! The isolated telemetry stream (M7/S1, `.copilot/wp/43.md` ADR-M7-002,
//! `docs/08-observability/observability.md` §3/§4/§5, task 60).
//!
//! This module owns exactly the **wire contract** — the content-free
//! `FleetEvent` type (`schema`) — that closes the ecosystem's named
//! observability gap without becoming a second data-exfiltration surface
//! (`threat-model.md` B7). Deliberately self-contained: nothing outside
//! `telemetry/` needs to reach into its internals for THIS task, and this
//! module reaches nothing outside itself except the doctor status enum it
//! reuses (`crate::model::state::CliStatus`) — the same "content-free by
//! construction, not by convention" discipline `routing::ItSignal` already
//! established for M6, applied here to the fleet-event wire.
//!
//! ## Kept deliberately narrow — later streams build ON this, not INTO it
//!
//! Per the M7 stream split (`tc wp get 43`, `tc task list --prd 7`):
//! - **S2** (`telemetry::optin`, a `sec` agent, task 61, FF-M7-OPTIN) — the
//!   opt-in gate + endpoint resolution (analytics off-by-default via a
//!   trusted carrier behind a seam; interim carrier is the forced/managed
//!   domain pending G-M7-1's owner ratification of the eventual CLI
//!   `--json`-field carrier). Shipped as part of this task, alongside the
//!   schema this module already carries.
//! - **S3/S9** (`telemetry::emitter`, tasks 62/68) — landed. The real
//!   transport seam ([`emitter::TelemetryTransport`]) + [`emitter::
//!   TelemetrySink`] (gated by [`optin::telemetry_optin`] — off means off,
//!   no transport call at all, not even an attempt) + the mapping from M6's
//!   [`crate::routing::ItSignal`]s and a doctor status transition into
//!   [`schema::FleetEvent`]s, wired live in `timer::poll_once`. The real
//!   hardware-UUID + keychain-salt plumbing behind [`schema::
//!   derive_machine_id`] remains a flagged, OS-integration deferral (see
//!   that function's own doc) — the live wiring uses a fixed dev/mock
//!   `MachineId` today, same "clearly a dev/mock source" discipline
//!   `render::fleet`'s `get_fleet` command holds itself to. The real HTTP
//!   transport to an org's own collector endpoint is still owner-gated
//!   (G-M7-3, the collector's own ingest API is undefined) — this build
//!   ships the seam plus `emitter::MockTransport`/`CaptureTransport` only.
//! - **S4** (`render::fleet.rs` + `src/admin/`, a `uid` agent) — the IT
//!   fleet dashboard that RENDERS a stream of [`schema::FleetEvent`]s.
//!
//! This task (S1) built only the TYPE those three streams consume/
//! produce — no gate, no transport, no dashboard, no Tauri command existed
//! yet at the time it was written; S2/S3/S9 above have since landed the
//! gate and the transport. Per S1's own brief: don't invent a parallel
//! content-carrying type — a fleet event is essentially a content-free
//! `ItSignal` (`crate::routing::ItSignal`/`ItSignalKind`) plus a machine id
//! and a status, so `schema` mirrors that shape's discipline (a closed set
//! of enums/newtypes/numbers, zero free-text fields) rather than
//! reinventing a second, richer wire format.
//!
//! ## G-M7-2 — flagged, not resolved, here
//!
//! `observability.md`'s own §11 residual-items list and ADR-M7-002 both
//! name this gap: the fleet-event schema is not yet a versioned `--json`
//! home under `docs/01-architecture/schemas/` (unlike `doctor.schema.json`/
//! `update.schema.json`, which the CLI's WS-A contract already freezes).
//! [`schema::FLEET_EVENT_SCHEMA_VERSION`] models the SAME versioned-contract
//! pattern (`schema_version: "1.0"`) so a future JSON Schema can be authored
//! against this Rust type without a breaking rename, but no such schema
//! file exists yet — this is that flag, not a fix.
//!
//! ## Scope deliberately deferred to S2/S3 (not silently dropped)
//!
//! - The real per-install, keychain-resident salt (§5: "salt is per-install
//!   and random, never org-wide... persists in the same per-user keychain
//!   entry the credentials mechanism already uses") is OS-integration work
//!   for S2/S3's real `ItSignalSink` — this task ships the pure derivation
//!   MATH ([`schema::derive_machine_id`]), tested against a known
//!   HMAC-SHA256 vector, with the salt/hardware-UUID supplied by the
//!   caller rather than read from the OS here.
//! - The full dual-envelope split `observability.md` §3/§4 describes
//!   (a richer SAFETY envelope with `event_id`/`org`/`layer`/`identity`/
//!   `escalation_deadline`/`source_checker`, and a wholly separate
//!   aggregate-counts ANALYTICS envelope) is intentionally NOT built here.
//!   This task's own brief narrows S1 to one unified, minimal
//!   [`schema::FleetEvent`] — every field it needs is already the closed,
//!   content-free set below; a richer split is additive work for whichever
//!   stream first needs `identity`/aggregate usage counts, not a rewrite of
//!   this type.

pub mod emitter;
pub mod optin;
pub mod schema;
