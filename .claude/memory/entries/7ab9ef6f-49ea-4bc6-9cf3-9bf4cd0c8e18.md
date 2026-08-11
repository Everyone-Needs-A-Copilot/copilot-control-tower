---
id: 7ab9ef6f-49ea-4bc6-9cf3-9bf4cd0c8e18
type: context
tags: []
created: 2026-07-31T21:08:46Z
updated: 2026-07-31T21:08:46Z
scope: project
---

G-9 resolved (task 213): ADR-006/007/008 written in docs/40-initiatives/02-enac-self-onboarding/decisions/. ADR-006 = onboard preflighted-saga (8-state classifier, preflight-before-writes, postconditions, completed_actions ledger, resume/adoption, never-destroy compensation scoped to manifest rollback only). ADR-007 = onboard schema_version 2.0 breaking bump (layers_state typed-absence, required row fields, ledger/resume formalized). ADR-008 = owner ruling that repair lives inside cc onboard's routing (no first-class cc repair verb) and cc publish is formally deferred; cli-contract.md verb inventory now lists only implemented/scoped verbs with a Deferred verbs section, CLAUDE.md invariant 1 reworded to match. Do not re-litigate; if repair/publish are ever built, supersede ADR-008 explicitly.
