//! Admin mode (M7-S6/S7, `.copilot/wp/43.md` tasks 65/66, `architecture.md`
//! §8.1 items 1 and 5): the IT/fleet-operator seed generator + preflight
//! surface.
//!
//! **SOUL framing (Case Law, `docs/06-deployment/standup-runbook.md`'s own
//! header stamp): the Admin/IT experience is an UNVALIDATED HYPOTHESIS
//! (Founding Decision #9) — no real IT operator has touched it.** Both
//! modules below are built to the design, not proven against a real fleet
//! (`cargo test`/fixtures only — no real `cc derive`, no real GitHub PR, no
//! real network probe). Both are IN per the SOUL case law "Admin-mode seed +
//! MDM-profile generator + red/green preflight" because they GENERATE
//! artifacts and RENDER validation results — they compute no ecosystem
//! verdict of their own (invariant #1), exactly like M5's `.mobileconfig`
//! generator this module mirrors.
//!
//! - [`seed`] (S6) — a pure-Rust builder for the org `ecosystem.yml` seed
//!   (`architecture.md` §8.1 item 1), mirroring `mobileconfig::generator`'s
//!   own shape: typed inputs -> fail-closed no-secret scan -> emitted text.
//!   See that module's own doc for the seed-shape provenance flag (G-M7-7,
//!   below).
//! - [`preflight`] (S7) — the on-demand red/green rollout gate
//!   (`architecture.md` §8.1 item 5) — NOT a continuous telemetry signal
//!   (`docs/08-observability/observability.md` §7.1 says this explicitly:
//!   "preflight is a one-time, on-demand validation call before rollout...
//!   not a continuous signal from the fleet"). Renders a checklist of
//!   `{check, status: pass|fail|unknown, detail}` — no aggregate score,
//!   ever (the same FF-M7-NOSCORE discipline `render::fleet`'s own
//!   `FleetView` holds itself to, applied here to a different surface).
//!
//! ## G-M7-7 (flagged, not silently resolved) — the `ecosystem.yml` seed
//! shape is DOC-frozen, not CODE-frozen
//!
//! The real CLI (`claude-copilot/tools/cc`) has no `ecosystem.yml` loader
//! or JSON Schema today — verified directly: `grep -rn "ecosystem.yml"
//! tools/cc/src/` finds nothing in the actual Python source; the only real,
//! shipped manifest loader/validator
//! (`cc/core/ecosystem/manifest.py`'s `load_layers`/`validate_layers`)
//! parses `copilot.layers.yml`, the DERIVE **OUTPUT** `cc derive` produces
//! **from** this seed, not the seed itself. What DOES exist is a detailed,
//! human-written worked example: `docs/reference/ecosystem-architecture.md`
//! §4.2's YAML block (`version`/`org`/`host`/`api_base`/`ssh_host`/
//! `foundation{owner,mirror,root_key,key_set}`/`auth`/`products`/
//! `departments`/`policy_signers`), plus
//! `docs/08-observability/observability.md` §6's `telemetry{enabled,
//! endpoint}` block layered on top (the analytics opt-in carrier this
//! milestone's S1/S2 streams wire the app side of). [`seed`] generates to
//! this best-known, evidence-cited, DOCUMENTED shape — it does not invent
//! new fields, and it does not wait for a schema that does not exist yet.
//! But the shape is still a documentation artifact, not a ratified contract
//! any real parser enforces — the same G-M5-1-shaped gap `managed::keys`'s
//! own doc already flagged for the `.mobileconfig` domain string. Flagged
//! here for the CLI/ecosystem owner to ratify a real `ecosystem.yml` JSON
//! Schema (or a `cc ecosystem validate` command) against, the same way
//! `four-tier-topology.md` already has one for `copilot.layers.yml`. Do not
//! read this module's shape as "the CLI already speaks this."

pub mod preflight;
pub mod seed;
