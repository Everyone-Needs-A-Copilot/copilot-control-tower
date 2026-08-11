# Security Policy

> **Status line — rebuilt from evidence, 2026-08-02.** Describes Copilot Control Tower v0.4.0. The prior version of this file referenced MDM-managed config as a sensitive surface; MDM (Jamf/Kandji/Intune) is dropped completely as a mechanism for this product — not deferred, not a future channel — per the CSE alignment decisions (`docs/10-reference/cse-alignment-decisions.md` D4).

Copilot Control Tower is a supervisor over an always-on, auto-updating agent with a live GitHub credential and write access to `.claude/` and the other component trees it materializes. We take reports about it seriously, especially anything touching the update/signing path or credential handling.

## What actually guards this app

Security-sensitive configuration (update feed, foundation mirror, HTTPS proxy, GitHub host, auth mode) is honored **only** from two sources: **compiled-in trust roots** (unchanged code, not config) and **signed, inherited org/foundation config** delivered as ordinary repo content the user already pulls, gated by the same GitHub-team read access as everything else in that repo. A value present only in local, user-editable config — a preference file, an environment variable, a CLI flag — is ignored in favor of the compiled-in default. There is no third channel: no MDM, no `.mobileconfig`, no forced-preference domain. This is invariant #4 in [`CLAUDE.md`](CLAUDE.md).

## Reporting a vulnerability

Please report security issues privately, not via a public GitHub issue.

**Contact:** <!-- TODO: security contact — no reporting channel is published yet; this was an unfilled placeholder in the prior version of this file too and remains a genuine open item, not something this rewrite could source from evidence. -->

Include enough detail to reproduce the issue and, if you can, an assessment of impact (what an attacker gains, on how many machines, with what precondition).

## What happens next

Reports are triaged and handled per the incident-response runbook at [`docs/05-security/incident-response.md`](docs/05-security/incident-response.md), which covers:

- Signing-key compromise (fleet-wide update-integrity failure)
- Malicious or compromised ecosystem content (a bad skill/agent published to a tier)
- Leaked secrets or credentials (integration secrets, author git-push credentials)
- Compromised update feed
- Coordinated disclosure and advisory publication

See also the full threat model: [`docs/05-security/threat-model.md`](docs/05-security/threat-model.md) (the app itself, re-scoped to the native renderer and the CLI seam) and [`docs/05-security/credentials-and-boundary.md`](docs/05-security/credentials-and-boundary.md) (what the app carries — secrets and the personal-shared data boundary).

**Honest note on enforcement.** The invariant above is an architectural commitment upheld by code review, not by an automated fitness-test suite against the shipping app. A test suite that would verify it (`fitness_m5_single_forced_boundary.rs` and related tests) exists in the retired Rust tree and has not been ported to the shipping Swift app or wired into an active CI job. Treat the invariant as a design position under review, not a mechanically-proven guarantee, until that port lands.

We will acknowledge receipt, coordinate a disclosure timeline with you, and credit you in the resulting advisory unless you prefer otherwise.
