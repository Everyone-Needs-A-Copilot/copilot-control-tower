# Security Policy

Copilot Control Tower is a supervisor over an always-on, auto-updating agent with a live `gh` token and write access to `.claude/`. We take reports about it seriously, especially anything touching the update/signing path, MDM-managed config, or credential handling.

## Reporting a vulnerability

Please report security issues privately, not via a public GitHub issue.

**Contact:** <!-- TODO: security contact -->

Include enough detail to reproduce the issue and, if you can, an assessment of impact (what an attacker gains, on how many machines, with what precondition).

## What happens next

Reports are triaged and handled per the incident-response runbook at [`docs/05-security/incident-response.md`](docs/05-security/incident-response.md), which covers:

- Minisign signing-key compromise (fleet-wide update-integrity failure)
- Malicious or compromised ecosystem content (a bad skill/agent published to a tier)
- Leaked secrets or credentials (integration secrets, author git-push credentials)
- Compromised update feed or MDM managed-config redirect
- Coordinated disclosure and advisory publication

See also the full threat model: [`docs/05-security/threat-model.md`](docs/05-security/threat-model.md) (the app itself) and [`docs/05-security/credentials-and-boundary.md`](docs/05-security/credentials-and-boundary.md) (what the app carries — secrets and the personal↔shared data boundary).

We will acknowledge receipt, coordinate a disclosure timeline with you, and credit you in the resulting advisory unless you prefer otherwise.
