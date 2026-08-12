# Security Policy

Please do not report a vulnerability in a public issue, pull request, or
discussion.

Use GitHub’s private vulnerability-reporting form from this repository’s
**Security** tab. Include reproduction steps, affected versions, the attacker’s
required access, and the impact you observed. Do not include live credentials,
private keys, client data, or machine-identifying paths unless the private report
specifically requires them.

Security-sensitive areas include:

- source, signing, notarization, and update provenance;
- the boundary between CLI facts and rendered app state;
- GitHub authorization and repository materialization;
- preservation of dirty or user-authored content;
- secret-store and keychain handling;
- crash-only supervision and install/uninstall behavior.

The project will acknowledge the report, validate impact, coordinate a fix and
disclosure timeline, and credit the reporter unless anonymity is requested.

See the [threat model](docs/05-security/threat-model.md) and
[incident-response guide](docs/05-security/incident-response.md) for the public
security design.
