# Verify Support Report — Architecture

## Context

Release 0.6.5 runs `doctor → update → doctor` during Verify. When the final
doctor report remains non-healthy, `holdingInfo(forNonHealthy:)` keeps only the
schema version. The first doctor report, the typed update receipt, and all
non-pass checker facts are discarded. The current support block then fabricates
an identity-only report. Raw doctor JSON is not shareable: the live 2.9.1 report
includes a host name, absolute paths, repository-adjacent identifiers, and SHAs.

## Decision

Capture one immutable `VerificationSupportAttempt` from the typed values already
decoded by `CliClient`: initial doctor, optional update receipt, final doctor or
typed CLI error, and one app timestamp. A pure formatter projects a closed,
redacted report. It includes only app identity; schema/result values; product
plus plain tier labels for non-pass checks; and update changed/held/blocked
counts. It explicitly omits host, account/org/project names, paths, repository
addresses, layer ids, item names, SHAs, raw detail, auth identity, stdout/stderr,
arbitrary exception text, file content, environment values, and secrets.

Persist the exact formatted bytes below
`~/.claude/cc/diagnostics/control-tower/` as a mode-0600, no-follow, exclusive
file. Create only missing current-user-owned real directories, use mode 0700 for
created directories, reject a symlink/non-directory/untrusted owner at every
boundary, fsync the file, and retain the newest 20 app-owned `verify-*.txt`
reports. If any persistence check fails, keep the in-memory report and expose
Copy without claiming a file exists.

`WizardModel` publishes the current artifact before entering a Verify-origin
hold. Existing non-Verify holding support remains unchanged. Verify-origin
disclosures render the artifact, offer Copy and Show in Finder when saved, and
use the existing selectable monospaced evidence block. The repeat caption becomes
**The latest check reached the same result.** globally; it describes the repeated
verdict and makes no filesystem claim.

No helper version is inferred from human CLI output. Release builds bundle the
already-pinned `packaging/cc/VERSION` as a read-only version resource beside the
helper; unbundled development builds honestly say the version was not reported.

## Rejected alternatives

- Raw stdout/stderr or `doctor --json` log: leaks machine identity and paths,
  bypasses typed schema boundaries, and breaks the “nothing private” promise.
- OSLog as the primary artifact: difficult to locate/copy, retention is outside
  the product’s control, and useful evidence would still need a redaction
  contract.
- New `cc support` verb: the app owns the multi-call check/update/check sequence;
  round-tripping all three typed reports into another process adds a second
  contract and private temporary payload without improving correctness.
- Identity-only text plus a reveal of the reconciliation diagnostics folder:
  that folder may prove project transactions but does not contain the Verify
  attempt that caused this screen.
- A diagnostics dashboard or Advanced settings pane: unnecessary audit and UI
  surface for the current job.

## Failure modes

- Persistence boundary is missing: create only safe missing directories;
  otherwise copy-only.
- Boundary or file is symlinked/untrusted: refuse to write; copy-only.
- Optional report field missing: omit the line or section.
- Future checker product/layer role unrecognized: label as **Setup check** or
  **This Mac** and never print the opaque token.
- Clipboard write fails: keep text selectable and do not claim **Copied**.
- Update fails after an initial doctor: format the initial status plus typed
  error code when available, persist, then route through existing Holding logic.
- Final doctor still reports update available: preserve all three phases, which
  is the exact 0.6.5 regression.
- Healthy final doctor: no Holding report is shown; persistence is not needed.

## Implementation and verification units

1. Add the pure attempt/formatter and private store.
   - Deterministic output; only non-pass rows; missing-field omission; forbidden
     sentinel exclusion; mode 0600; directory mode 0700; symlink refusal;
     retention.
2. Wire Verify to retain initial/update/final typed reports and publish the
   artifact before Holding.
   - `update-available → applied → update-available` produces all three sections;
     update failure produces initial plus failure; healthy completion is
     unchanged.
3. Extend the existing support disclosure/buttons with the artifact, Copy,
   Reveal, copy feedback, and revised repeat caption.
   - Selftest output, file existence, exact copied-source bytes, accessibility
     labels, and visual walkthrough/design-fidelity check.
4. Vendor the fix from claude-copilot commit `2f9b880` plus the completed
   executable version markers in `6368f10` (`cc 2.9.2`), bump the app release,
   build from pushed immutable source, sign/notarize/staple, verify the packaged
   helper and installed artifact, and publish provenance.

G-1 and G-2 remain unchanged.
