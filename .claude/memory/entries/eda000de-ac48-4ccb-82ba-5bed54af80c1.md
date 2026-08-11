---
id: eda000de-ac48-4ccb-82ba-5bed54af80c1
type: decision
tags: []
created: 2026-08-05T11:07:37Z
updated: 2026-08-05T11:07:37Z
scope: project
---

CliLocator hardened against WP-525 Finding A: CT_CLI_PATH override now requires the target to satisfy a compiled-in ProductionTrustAnchor (anchor apple generic + team 3SYGVX2HB8) whenever the running process is itself the Developer-ID-signed article; ad-hoc/unsigned dev-test builds keep the override unchanged. This required reordering scripts/package-user-release.sh's headless-detect/headless-setup-transaction proofs to run BEFORE scripts/sign.sh, since they rely on CT_CLI_PATH=mock-cc against what must remain a not-yet-production-signed app wrapper -- verified empirically that running them post-sign now correctly refuses mock-cc and would otherwise silently invoke the real cc apply verb.
