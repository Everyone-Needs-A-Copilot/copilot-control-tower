//! The parse-never-compute boundary (T3), as two deliberately separated
//! layers so the compute line is a *type* boundary, not a convention:
//!
//! - `envelope` + `doctor` — the **wire layer**: serde structs mirroring
//!   `docs/01-architecture/schemas/doctor.schema.json` and
//!   `_envelope.schema.json` exactly, decoded through the `failclosed`
//!   adaptors rather than raw `Option`.
//! - `failclosed` — the fail-closed deserialization defaults: missing
//!   `severity` => `Fail` (never `Pass`); missing `destructive` => `true`;
//!   an unknown `status` string routes to the app-owned `CliUnreadable`
//!   state rather than being silently dropped.
//! - `state` — the **domain layer**: the typed `CliStatus`/`DoctorVerdict`
//!   the rest of the app renders, plus the parse boundary itself
//!   (`parse_doctor_body`). Constructing a `CliStatus` is a *mapping* from
//!   the wire layer, never a computation — see ADR-M1-001/002 in the
//!   architecture WP for exactly where that line is.
//!
//! T3: implemented. `render::derive` consumes `state::DoctorVerdict` /
//! `state::ParseOutcome` to produce the `RenderState` DTO the web UI renders.
//!
//! M5/S2 (`.copilot/wp/30.md`): `deprovision` is the same wire+domain+parse-
//! boundary split, for `cc deprovision <org> --json` instead of `doctor
//! --json` — collapsed into one file since that shape is small. See its own
//! module doc for the deprovision-specific fail-closed rules (`secrets_touched`
//! in particular).

pub mod deprovision;
pub mod doctor;
pub mod envelope;
pub mod failclosed;
pub mod state;
