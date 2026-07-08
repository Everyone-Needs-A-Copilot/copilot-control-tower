# Copilot Control Tower Architecture Guiding Principles

Use this file to decide how accepted product direction should be built.

## System Context

- Project: `copilot-control-tower`
- Stack: Tauri v2 / Rust / TypeScript / Vite
- Description: Open-source macOS-first menu-bar app that supervises the `copilot`/`cc` CLI and provides an Admin mode for IT setup and deployment.

## Principles

1. Preserve the face-and-supervisor role: Control Tower parses CLI contracts and renders them; it does not compute ecosystem state.
2. Keep the app thin around stable boundaries: UI, Tauri commands, Rust orchestration, CLI process execution, persistence, and packaging should stay explicit.
3. Maintain one signed process for tray, supervisor, and scheduler behavior; do not add a daemon, fallback loop, or second writer.
4. Protect the never-destroy invariant: disposable inherited material may be rematerialized, but dirty personal working trees and personal content are not touched.
5. Treat security posture as inherited and enforced: no bypass flags, no user-editable trust roots, no secret propagation through inheritance content.
6. Route failures by actor competence and reversibility, so automatic repair, IT escalation, and user prompts remain distinct.
7. Make failure states visible, recoverable, and attributable to the right host or actor.
8. Add abstractions only when they protect a contract, reduce real duplication, or match an established local pattern.

## Design-Led Implementation Rules

- Start with the workflow, state model, and CLI JSON contract before choosing code shape.
- Keep UI copy and interaction states aligned with the product's Bob-agency model.
- Prefer schema validation, fixtures, and fitness tests for behavior that protects invariants.
- Make managed and unmanaged paths explicit, including offline, partial-profile, and version-mismatch states.
- Use absolute, translocation-safe CLI paths and preserve the `copilot`/`cc` boundary.
- Treat observability and safety escalation as product behavior, not logging afterthoughts.

## Review Questions

Before durable technical work, answer:

1. Which product invariant is this implementation serving?
2. What CLI contract, schema, or actor boundary must stay stable?
3. What failure mode needs first-class handling?
4. What security, privacy, or deployment assumption could be weakened by this change?
5. What complexity are we intentionally rejecting?
