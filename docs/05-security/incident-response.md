# Incident Response Runbook — Copilot Control Tower

| | |
|---|---|
| **STATUS** | **Maintainer runbook, 2026-07-07.** Operationalizes the threats ratified in [`threat-model.md`](threat-model.md) and [`credentials-and-boundary.md`](credentials-and-boundary.md), and the findings in [`../04-validation/redteam-platform.md`](../04-validation/redteam-platform.md) / [`redteam-use-cases.md`](../04-validation/redteam-use-cases.md). It does not introduce new controls — every containment/eradication step below cites a mechanism already specified in [`../01-architecture/architecture.md`](../01-architecture/architecture.md) or one of the two documents above. Where a cited mechanism is itself an **open design item** (not yet built, or not yet assigned an owner), that is stated plainly rather than assumed solved — see §6. |
| **Scope** | Five incident classes: minisign signing-key compromise, malicious/compromised ecosystem content, leaked secret/credential, compromised update feed or MDM config redirect, and coordinated vulnerability disclosure. |
| **Non-goal** | This is not a general SOC playbook. It does not cover host-level malware response, physical security, or law-enforcement engagement — those are the receiving org's own IR process once a Control Tower-specific incident is triaged as also being a broader endpoint compromise. |
| **No time estimates** | Every step below is ordered by trigger and dependency, never by duration. Where the architecture cites a fixed cadence (e.g., the 15-minute freshness-poll floor) that is a *design fact being reasoned about*, not an SLA this runbook imposes. |
| **Invariant this runbook must never violate** | Per `CLAUDE.md` invariant #4: response actions must never weaken the inherited security posture. No incident response step may recommend `--skip-verify`, `--force`, disabling signature checks, honoring a user-domain override of a security-sensitive key, or any other fail-*open* shortcut — every containment step below is fail-closed by construction, matching the posture it is defending. |

---

## 0. Roles referenced throughout

- **Maintainer(s)** — hold or can invoke access to the release pipeline (CI, signing custody) and this repo.
- **Key custodian(s)** — hold one half of the two-of-N minisign signing scheme (§7 of `architecture.md`). **Who these people are is an open item — see §6.1.**
- **Org IT / security team** — the receiving end of the `AdminContact` safety-escalation channel (`architecture.md` §8.3, §9) for a managed fleet; the entity that runs Admin mode's policy-signer key (`architecture.md` §8.1 step 3).
- **Reporter** — an external researcher or user filing a report via the root `SECURITY.md` (§5).

---

## 1. Minisign signing-key compromise (the fleet-wide-RCE case — B-M4)

This is the single highest-*damage* threat in the threat model (`threat-model.md` §3, DREAD rank #2, D=10/R=7/E=3/A=10/Disc=3, avg 6.6) — a compromised minisign private key lets an attacker ship a validly-signed, malicious Control Tower update that every auto-updating machine installs, carrying a live `gh` token and the ability to rewrite `.claude/` agents fleet-wide.

### Detection signal
- Any of: a CI/secrets-management alert indicating unauthorized access to the minisign private key material or its custodial HSM/vault; a release appearing on the update feed that no maintainer authored or that is missing from the release log; the staged-rollout anomaly-halt tripping (post-update crash/behavior-spike telemetry, `architecture.md` §7) on a release nobody recognizes as legitimate; an external report (via `SECURITY.md`, §5) of a Control Tower binary behaving unexpectedly after an update; a key custodian reporting their half of the two-of-N material may have been exposed.

### Containment — halt the update feed first, before anything else
1. **Freeze the release pipeline.** Revoke CI's ability to publish to `UpdateFeedURL` immediately — pull the publish credentials/CI runner access, not just "stop merging." This must happen before any other step, because every subsequent action (rotation, re-signing) is worthless if the attacker can still publish.
2. **Instruct the surviving, uncompromised co-signer to refuse all counter-signatures** until the compromised key is confirmed revoked. Two-of-N signing means a single popped key cannot alone produce a validly double-signed manifest — **provided the second custodian slot is actually staffed and reachable**. If it is not (see §6.1), treat this incident as if the scheme is currently one-of-one and escalate containment urgency accordingly: the feed freeze in step 1 is the *only* real control until a second custodian exists.
3. **Confirm the staged-rollout anomaly-halt is armed** for any release currently mid-rollout — if telemetry shows anomalous post-update behavior on any machine, that rollout halts automatically per `architecture.md` §7; do not manually override this halt to "unblock" a release during an active incident.
4. **Do not trust the compromised feed for distributing the fix.** The normal `UpdateFeedURL` path is not a safe channel to ship the eradication update through until the malicious key's trust is fully revoked (step below) — plan the fix release through a channel a compromised key cannot also forge (see Eradication, step 3).

### Eradication — rotate keys, and recognize that trust-root rotation requires a *signed app release*, not a config change
1. **Generate replacement minisign keypair(s) in a fresh, separately-custodied HSM/vault** — never reuse the compromised material, and never regenerate in the same location that was compromised.
2. **Recognize the bootstrapping constraint:** per `threat-model.md` §1 and `architecture.md` §7, the minisign public key is **compiled-in code, not config** — no managed-domain or user-domain preference can repoint which key the watchdog trusts. This means rotating the trust root is not a config push; it requires building, signing, and shipping a **new Control Tower release** whose binary embeds the new public key(s) and revokes the old one(s).
3. **Sign this specific emergency release with maximum available assurance**, since it is the release that re-establishes trust: use every uncompromised custodian available (the surviving half of the two-of-N pair, plus, if available, an out-of-band witness — a transparency-log entry or a second maintainer's independent confirmation of the build hash) even if that exceeds the normal two-of-N minimum for routine releases.
4. **Distribute the emergency release out-of-band from the (potentially still-suspect) normal feed**: for `AllowSelfUpdate=false` managed fleets, push the version-locked CLI+app pair directly via MDM (`architecture.md` §7) rather than relying on the updater to pull it; for unmanaged/solo installs, publish the release through the project's GitHub Releases page with a signed security advisory (§5) stating the build hash and the old key's revocation, so an install can be verified independently of the update feed's own integrity.
5. **Bake the old key's revocation into the new release** (a compiled-in revoked-key list, or equivalent), so no future forged manifest signed with the old private key is ever honored again, even if the attacker retains the stolen private key indefinitely.

### Recovery
1. Confirm, via the staged-rollout telemetry and anomaly-halt signal, that the emergency release is adopting cleanly across the fleet.
2. Cross-reference machine telemetry (or, for unmanaged installs, `doctor --json` output collected via the safety-escalation channel) against the known-malicious release's version marker to identify any machine that installed the attacker's build before containment.
3. Any machine confirmed to have run the malicious build is treated as a **compromised endpoint**, not merely a Control Tower incident: escalate it to the org's own endpoint-security/IR process (out of this runbook's scope) — the live `gh` token and `.claude/` write capability on that machine must be assumed exercised.
4. Publish a transparency-log entry (or equivalent public record) of the key revocation and the new trust root, independent of the update feed itself, so the revocation is auditable even by someone who never receives the update.

### Comms
- Publish a security advisory through the `SECURITY.md` contact channel (§5) disclosing the compromise, the affected release range, the new trust root, and remediation steps for any machine that may have installed the malicious build.
- Fire the safety-escalation signal (`AdminContact`, content-free per `architecture.md` §9) to every managed fleet's IT channel, flagged as its own incident class distinct from routine sig-fail/auth-revoked signals.
- Do not disclose the specific custody arrangement or HSM details in any public advisory — disclose the impact and the fix, not the internal control weaknesses that led to it, beyond what's needed for affected orgs to assess their own exposure.

---

## 2. Malicious or compromised ecosystem content (a bad skill/agent published to a tier)

### Detection signal
- A capability-policy signature check failing or flagging content signed by an unauthorized signer (`architecture.md` §8.1 step 3); a `severity_trailer: security` marker on content that also shadows a personal override (the auto-suspend case, `architecture.md` §9); a user or researcher report of unexpected/unsafe skill behavior; anomalous usage telemetry for a newly published item; a leak-scan trip on the publish side (`credentials-and-boundary.md` §2.3 guarantee D) that surfaces the content as policy-violating before it ever reaches a consumer.

### Containment
1. **Revoke via the capability-policy channel, not via a git history rewrite.** The security team signs an updated `ecosystem.yml` capability policy denying the malicious skill/agent immediately — this is a `severity_trailer: security` + policy-deny event, which the Bob-agency model already routes to **auto-suspend, not notify-and-hope** (`architecture.md` §9, closing A-C3): any personal override shadowing the malicious content is suspended and the corrected/denied state wins without waiting on a user's attention.
2. **Understand the propagation-speed limit before promising anything faster than it can deliver.** Revocation propagates only as fast as the fleet's **freshness-poll cadence** (15 minutes on AC power, hourly on battery, paused on metered/low-power connections, per `architecture.md` §8/§2.2 of the design) — unless the org has enabled the **publish webhook**, which is not universally available (this is an explicitly **open item**, `architecture.md` §11 item 2 — see §6.2 below). State this propagation floor honestly in any advisory rather than implying instant fleet-wide kill.
3. If the org has the publish webhook enabled, use it to push the revocation immediately rather than waiting on the poll.

### Eradication
1. Revert the malicious commit in the affected tier's repo using a normal, auditable `git revert` — **never a force-push or history rewrite**, consistent with this project's git-safety posture and the never-destroy invariant's spirit even at the ecosystem-content layer.
2. Determine the root cause of the publish: if the content was published using a legitimate contributor's credentials that were themselves compromised, treat this as a **leaked-credential incident** as well and run §3 in parallel (revoke that author's push credential via team-membership removal, `credentials-and-boundary.md` §6.3). If the capability-policy signer key itself was compromised rather than an individual author, rotate that policy-signer key (a security-team-held key distinct from push authority, `architecture.md` §8.1) and re-sign a clean policy.

### Recovery
1. Confirm via telemetry (or, absent telemetry, via a manual `doctor --json` sweep on managed machines) that the fleet has pulled the corrected/denied policy state.
2. Confirm any auto-suspended personal override correctly re-affirms only against the corrected content, not the malicious version.

### Comms
- Fire the safety-escalation signal (policy-conflict/security class) to the `AdminContact` channel for affected managed fleets.
- If the malicious content reached the **foundation** (public) tier, this is a supply-chain-relevant disclosure — follow the coordinated-disclosure process in §5, since it affects consumers outside any single org's fleet.

### Why blast radius is bounded regardless of response speed
The personal↔shared leakage-wall structural guarantees (`credentials-and-boundary.md` §2.3 A–E) mean malicious tier content can never itself propagate into a personal tree or gain push access to a broader tier than it was published to — the automated sync/materialize path is pull-only in the upward direction (`credentials-and-boundary.md` §2.4), so a compromised skill cannot use the sync mechanism itself to spread beyond the tier it was published into. This bounds the incident; it does not eliminate the need to revoke and communicate.

---

## 3. Leaked secret or credential (integration secret, or an author git-push credential)

### Detection signal
- A GitHub secret-scanning alert (if a secret ever entered git despite the policy that it never should, `credentials-and-boundary.md` §1.3 — treat this specific case as its own escalated sub-incident, see step 3 below); a vendor/IdP-side anomaly alert on an integration token; a user report of an accidentally exposed key (screen share, paste, log leak); a leak-scan trip on a push attempt (`credentials-and-boundary.md` §2.3 guarantee D — defense-in-depth, not the primary control).

### Containment — revoke first, using the primitive that matches the credential type
1. **Integration secret** (an API key/token resolved via `requires_secret: <NAME>` from the OS keychain, or from the optional shared secret store, `credentials-and-boundary.md` §1.4/§1.6): revoke it **at the vendor/IdP**, not just locally — server-side revocation is the real backstop, the same pattern already established for deprovision (`architecture.md` §8.3, "the real backstop is server-side token revocation"). The stale local keychain entry then surfaces as `Signed-out` on next resolution attempt, with no further action needed client-side.
2. **Author git-push credential** (`ssh-personal`/`ssh-work`): revoke via **team-membership removal first** — the fast, centralized lever (`credentials-and-boundary.md` §6.3) that instantly removes push capability regardless of the local key's state. If this is a suspected-compromise case rather than routine offboarding, **additionally** delete the specific public key from the author's GitHub account via the API (key-level removal), invalidating that one key without disturbing team membership — useful when the same person continues authoring from a different, trusted machine.
3. **Shared secret store secret** (Enhancement A, Infisical/OpenBao, `credentials-and-boundary.md` §1.6): rotate via the store's native rotation mechanism (§1.6.2 step 4); pull the audit log to determine which authorized member's service-token fetched the secret and when, since the store's audit trail attributes to the *service-token*, not the downstream action (`credentials-and-boundary.md` §1.6.5 — a documented, real residual repudiation gap for shared credentials).

### Eradication — confirm no secret ever entered git
1. For an integration secret, confirm by construction: it should never have lived in a git-tracked path at all (`credentials-and-boundary.md` §1, DREAD ≈ 9.2/10 on the rejected "secrets in git" anti-pattern) — verify the leak's origin was the keychain/environment, not a committed file.
2. If a leak-scan trip **did** catch a secret in a push attempt, confirm the push was actually blocked fail-closed and never landed on the remote — check the repo's real commit history to verify absence; do not assume the block worked without checking.
3. If evidence shows a secret **did** land in git history (a scan bypass, or a push predating the scan's deployment), treat the exposed value as **permanently burned** the moment it is confirmed in history — rotate it at the source regardless of repo visibility (private-repo exposure to even a small team is still exposure, `credentials-and-boundary.md` §1.3). Do **not** default to a destructive history rewrite to "remove" it — per this project's own git-safety posture, rewriting history is disfavored; the correct response is rotation (the leaked value is dead the instant it's rotated) plus documenting who had read access during the exposure window, reserving history rewrite for cases where the org's own policy explicitly requires it.

### Recovery
1. Reissue a new credential through the correct primitive: interactive OAuth/device-flow re-authentication for an integration secret (`credentials-and-boundary.md` §1.4); a freshly generated on-device SSH keypair for a compromised author-push credential (`credentials-and-boundary.md` §6.2, the same rotation path already specified for routine key rotation).
2. Confirm the `Signed-out` state clears once the new credential resolves successfully.

### Comms
- Notify the affected individual directly via the existing re-auth/sign-in prompt path — this doubles as the recovery mechanism and the notification.
- For a shared-store secret, notify every tier member whose access could be implicated, since the store's own trade-off (`credentials-and-boundary.md` §1.6.5) is a larger blast radius than a per-user credential.
- Escalate to the org's IT/security channel via the safety-escalation signal if the leak involved a managed-fleet integration.

---

## 4. Compromised update feed or MDM config redirect (B-C5 / the `AdminContact` finding)

### Detection signal
- A **tamper event** logged when a value for a security-sensitive key present in the user-writable preference domain is rejected because it did not come from the forced/managed domain (`architecture.md` §8.3: `UpdateFeedURL`, `FoundationMirror`, `EcosystemSeedURL`, `HTTPSProxy`, `GitHubHost`, `AuthMode`, `AllowSelfUpdate`, `Deprovisioned`, and — per the fix now folded into §8.3 that closes the threat-model's originally-flagged gap — `AdminContact`). This is the primary detection signal for a **local, non-privileged attacker** attempting the redirect (the B-C5 attack shape).
- A distinct and more severe case: the **legitimate forced/managed domain itself** is repointed — i.e., an attacker with actual MDM-admin access (or a compromised MDM console) pushes a malicious profile setting `UpdateFeedURL`/`FoundationMirror`/`AdminContact` to an attacker-controlled endpoint. This is **not** caught by the `CFPreferencesAppValueIsForced` check, because the value genuinely does come from the forced domain — detection here is organizational, not app-side: an MDM console audit log entry for an unexpected profile push, or a fleet-wide telemetry anomaly (multiple machines suddenly resolving a different feed/mirror than the fleet norm).

### Containment
1. **For the user-domain-spoof case:** no action is needed against the app itself — the value is already ignored by construction (`architecture.md` §8.3) and only the *tamper-event log entry* needs review to confirm the rejection occurred and to identify the affected machine for follow-up (the presence of a spoofing attempt may indicate broader compromise of that specific endpoint worth investigating outside this runbook's scope).
2. **For the forced-domain-compromise case:** treat the MDM console/profile-management system itself as compromised. Revoke or correct the malicious profile at the MDM management console immediately, and force a profile re-push to the fleet. Do **not** rely on the app-provided `AdminContact` channel to coordinate this response if `AdminContact` itself is plausibly the redirected value — use the org's independently known-good IT contact list, not anything the app surfaces, until the profile is confirmed corrected.

### Eradication
- If the forced-domain redirect resulted in any machine installing a malicious update, this incident converges with §1 (minisign key compromise) or with a malicious-mirror scenario — run the relevant eradication steps from §1 in parallel, since a compromised `FoundationMirror`/`UpdateFeedURL` value pointed at an attacker endpoint is a delivery mechanism for exactly that payload class.
- Correct the MDM profile at the source; confirm the correction propagates via the next managed-profile refresh.

### Recovery
1. Re-check forced-domain values across the fleet (via the next `doctor --json`/freshness poll) to confirm every machine now reflects the corrected profile.
2. Review tamper-event logs fleet-wide for the affected window to identify every machine that attempted or received a user-domain spoof during the incident, even if the attempt was rejected.

### Comms
- Notify fleet IT via an out-of-band channel (not the app's own `AdminContact` surface, for the reasons above) if the forced domain itself was implicated.
- If any machine's actual security posture was degraded (malicious update installed), fold this into the §1 comms process rather than treating it as separate.

---

## 5. Coordinated disclosure — how researchers report

A root [`SECURITY.md`](../../SECURITY.md) has been created pointing here. Researchers reporting a vulnerability should:

1. Contact the maintainer via the channel named in `SECURITY.md` (contact placeholder pending — see the file itself).
2. Provide enough detail to reproduce and assess severity — this runbook's authors will score the report using STRIDE + DREAD (per `threat-model.md`'s own methodology) before deciding remediation priority.
3. Expect acknowledgment of receipt, followed by a severity triage against this runbook's incident classes (§1–§4 above, whichever applies), and coordination on a disclosure timeline that allows a fix to ship before public detail is published.
4. For a minisign-key or supply-chain-class finding specifically, expect the response to follow §1's process, including the out-of-band distribution step for any emergency release — do not expect the fix to arrive solely via the normal update feed if the feed's own integrity is what's in question.

---

## 6. Open / unassigned items — explicitly not resolved by this runbook

These are carried forward from the architecture and threat-model documents, not newly discovered here. This runbook describes the *process* assuming each mechanism exists; where the mechanism itself is not yet built or not yet assigned an owner, that gap is the actual residual risk, not a gap in this runbook.

### 6.1 Signing custody (open — `architecture.md` §11 item 1, `threat-model.md` §5.1)
Two-of-N signing (or a transparency-log witness) is the specified *mechanism* for Control Tower releases, but **who holds the second of the two keys is not yet assigned.** Until a second custodian is named and operational, §1's containment step 2 (the surviving co-signer refusing counter-signatures) has no one to execute it — the scheme is, in practice, one-of-one with a placeholder. This is the single largest gap bearing on the highest-damage incident class in this runbook.

### 6.2 Publish-webhook vs freshness-poll floor (open — `architecture.md` §11 item 2, `redteam-use-cases.md` M16)
§2's containment step 2 depends on whether an org has enabled the publish webhook. Where it has not, urgent revocation of malicious ecosystem content propagates only as fast as the freshness-poll cadence (15 minutes AC / hourly battery / paused on metered). Whether to accept this floor as the baseline or require the webhook for orgs with a credible urgent-revocation need is an open decision this runbook does not resolve — it only documents the propagation-speed consequence honestly so an incident responder doesn't overpromise.

### 6.3 Implementation status
As of this writing, `copilot-control-tower` is in its design/specification phase (per the phased roadmap, `architecture.md` §12 — P0 through P4 are not yet built). Several detection signals cited above (tamper-event logging, anomaly-halt telemetry, the hash-chained action log) are **specified**, not yet **implemented**. Until they ship, detection for several of the incident classes above will need to rely on manual review (log inspection, direct `doctor --json` calls, out-of-band reports) rather than the automated signals this runbook describes as the target state.
