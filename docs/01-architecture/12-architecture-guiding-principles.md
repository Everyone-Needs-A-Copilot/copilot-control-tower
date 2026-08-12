# Copilot Control Tower Architecture Guiding Principles

> **Status line — rebuilt from evidence, 2026-08-02.** Describes Copilot Control Tower v0.4.0. The prior version of this file described a Tauri v2/Rust/TypeScript/Vite stack; the shipping app is native SwiftUI/AppKit and has been since before this rewrite. Use this file to decide how accepted product direction should be built.

## System Context

- Project: `copilot-control-tower`
- Stack: **Native macOS SwiftUI/AppKit**, compiled by `swiftc` from an explicit file list in [`native/`](../../native/) — no Xcode project, no Swift Package Manager manifest, no web framework. A retired Tauri v2/Rust/TypeScript/Vite tree remains on disk at `src-tauri/` as a historical reference; it is not built by any release script and not the target of this guidance.
- Description: Open-source macOS-only menu-bar app that supervises the `copilot`/`cc` CLI and provides an Admin mode for org setup and deployment.

## Principles

1. Preserve the face-and-supervisor role: Control Tower parses CLI contracts and renders them; it does not compute ecosystem state.
2. Keep the app thin around stable boundaries: the tray/wizard/Settings UI, the CLI-invocation seam (`CliClient`/`CliLocator`), the DTO/schema-gate layer, and packaging should stay explicit and separable.
3. Maintain one signed process for tray, supervisor, and scheduler behavior; do not add a daemon, fallback loop, or second writer. Note honestly: the crash-only `launchd` watchdog described in `CLAUDE.md` invariant #2 is a stated design position, not yet implemented in the shipping app (gap G-2) — building it is in scope for this principle, not a violation of it.
4. Protect the never-destroy invariant: disposable inherited material may be rematerialized. A dirty Product project may receive one additive local checkpoint commit when the complete work and prior index can be preserved, but it is never reset, overwritten, rebased, merged, deleted, or pushed. Ecosystem repositories are never checkpointed; dirty shared checkouts and personal content remain untouched.
5. Treat security posture as inherited and enforced: no bypass flags, no user-editable trust roots, no secret propagation through inheritance content, no MDM channel of any kind.
6. Route failures by actor competence and reversibility, so automatic repair, escalation, and user prompts remain distinct — even though the shipping app does not yet have a dedicated escalation router (see `architecture.md` §9); new work in this space should build toward that principle, not away from it.
7. Make failure states visible, recoverable, and attributable to the right component and tier — Control Tower now reports per component × tier, not a single blended verdict.
8. Add abstractions only when they protect a contract, reduce real duplication, or match an established local pattern already present in `native/*.swift`.

## Design-Led Implementation Rules

- Start with the workflow, state model, and CLI JSON contract before choosing code shape — read [`cli-contract.md`](cli-contract.md) and the schemas in [`schemas/`](schemas/) first.
- Keep UI copy and interaction states aligned with the native design of record: [`../03-design/control-tower-native-experience-architecture.md`](../03-design/control-tower-native-experience-architecture.md), [`-interaction-spec.md`](../03-design/control-tower-interaction-spec.md), [`-visual-system.md`](../03-design/control-tower-visual-system.md), [`-copy-deck.md`](../03-design/control-tower-copy-deck.md).
- Prefer schema validation, fixtures, and the shell-level test harnesses in `scripts/tests/` for behavior that protects invariants — there is no automated fitness-test suite scanning `native/*.swift` today (gap G-1); do not assume one exists or claim new code is "fitness-tested" without adding real coverage.
- Make managed and unmanaged paths explicit, including offline, partial-entitlement, and schema-version-mismatch states.
- Use absolute, translocation-safe CLI paths (`CliLocator`) and preserve the `copilot`/`cc` boundary — never spawn a bare `cc`/`copilot` name.
- Treat safety escalation as product behavior worth building toward (`architecture.md` §9), not as logging afterthought — but do not claim it is implemented until it is.

## Review Questions

Before durable technical work, answer:

1. Which product invariant is this implementation serving?
2. What CLI contract, schema, or actor boundary must stay stable?
3. What failure mode needs first-class handling?
4. What security, privacy, or deployment assumption could be weakened by this change?
5. What complexity are we intentionally rejecting?
6. Does this change close gap G-1 or G-2, touch either, or leave them as they are — and does the documentation still say so honestly afterward?
