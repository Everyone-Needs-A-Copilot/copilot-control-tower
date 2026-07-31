# Phase 6 — Truthful setup and project integration aftercare handoff

> Initiative: [`02-enac-self-onboarding`](../README.md)
>
> Previous handoff:
> [`phase-6-v0.1.3-user-install-handoff.md`](phase-6-v0.1.3-user-install-handoff.md)
>
> **This is the 0.2.2 release-completion record as of 2026-07-31.** The previous
> handoff remains implementation and release history. The checked-in package
> now embeds the separately signed and Apple-notarized cc 1.7.14 universal
> helper, exposes the complete four-component/four-tier ecosystem after setup,
> passes both the walkthrough and completed-setup acceptance gates, and can
> launch guided Codex or Claude Code work in a visible Terminal session.

> **Owner-review closeout, 2026-07-30:** the installed Step 7 experience exposed
> a continuous 53-project register, unclear category language, dead-end assistant
> launch controls, and generic couldn't-verify recovery. Task `tc` 195 revises
> walkthroughs 07 and 08 around focused triage, visible guided execution, and
> exact evidence; task `tc` 196 implements that experience in the native wizard
> and menu-bar aftercare. Current source passes the revised 38-assertion gate.
> The signed 0.1.9 release facts below remain historical truth and do not imply
> that release artifact contains this later source implementation.
>
> **Completed-state closeout, 2026-07-30:** owner review found that the
> post-setup window hid Foundation, Organization, Department, and Personal,
> inferred readiness without proving all four Personal components, and reduced
> project aftercare to a generic list. Task `tc` 198 adds the walkthroughs,
> complete component/tier topology, truthful Personal recovery, and the same
> focused project categories used during setup. “Personal” is the product term;
> its backing GitHub repository is private.
>
> **Guided-launch closeout, 2026-07-31:** owner testing found that **Run in
> Claude Code** opened an empty Terminal and **Run in Codex** appeared to do
> nothing. Task `tc` 199 traced this to the signed User app lacking the macOS
> Apple Events entitlement and purpose string. Release 0.2.2 adds that signed
> permission contract, resolves absolute assistant executables before launch,
> sends the command before bringing Terminal forward, and gives exact recovery
> guidance when the assistant, project folder, or Automation permission is
> unavailable.

Date: 2026-07-31
Primary repository: `copilot-control-tower`
Branch: `app-build`
CLI repository: `claude-copilot`
CLI branch: `feat/adopt-and-project-setup`
Task lineage: `tc` 182 → 183 → 184 → 185 → 187 → 188–193 → 195 → 196 → 197 → 198 → 199
Historical release status: signed and notarized Control Tower 0.1.9 passed
clean-install and installed-artifact verification

Current release status: truthful completed setup, durable project aftercare,
and working visible guided-assistant launch are published in signed and
notarized Control Tower 0.2.2; task 199 owns the defect, implementation,
release, and artifact QA record

## Start Here

Read the numbered walkthrough index:

`docs/40-initiatives/02-enac-self-onboarding/walkthroughs/README.md`

The walkthroughs are intentionally ordered `01` through `14`. For the current
setup and project-integration problem, concentrate on:

1. `05-truthful-setup-recovery-uxd-walkthrough.html`
2. `06-truthful-setup-recovery-uids-walkthrough.html`
3. `07-project-integration-aftercare-uxd-walkthrough.html`
4. `08-project-integration-aftercare-uids-walkthrough.html`
5. `09-completed-setup-topology-uxd-walkthrough.html`
6. `10-completed-setup-topology-uids-walkthrough.html`

The UIDS walkthroughs are the high-fidelity experience. The UXD walkthroughs
explain the interaction decisions behind them.

## What Has Been Established

The installed Control Tower 0.1.7 CLI reported 53 projects:

- 31 had both Claude and Codex recognized.
- 5 were called Ready while only one recommended Copilot was recognized.
- 17 materially different projects were collapsed into one generic
  “existing setup needs review” blocker.

The `31 Ready / 11 likely safe finish / 11 guided integration` split is a
research-backed candidate grouping. It is not an executable verdict. A richer
CLI contract must compute the authoritative classification.

Representative project shapes were verified against the local projects:

- `pipeline-copilot`: customized and already integrated.
- `admin-server`: compatible Claude setup with critical project safety rules.
- `codex-copilot`: recognizable Codex setup without current proof.
- `h3` and `convoco-policy-build`: only one recommended Copilot is integrated.
- `crm-automation-copilot`: valuable project guidance without shared framework
  integration.
- `preflight-copilot`: deeply specialized older ecosystem with 24 agents, eight
  skills, and eight commands.
- `research-copilot` and `transformation`: mixed Claude and Codex customization.

## Product Decisions

1. A project is self-contained. Control Tower does not sync or own project
   contents.
2. Control Tower renders CLI facts; it does not classify project contents itself.
3. Project customization is a positive capability, not a failure state.
4. Exact compatible layouts may receive a bounded safe-finish action.
5. Semantic reconciliation receives a CLI-generated plan and guarded prompt.
6. An authorized author may open that prompt in Codex or Claude Code.
7. A non-owner receives a prepared, shareable handoff. “Owner will review” by
   itself is not an outcome.
8. The CLI independently verifies the project after external work. An assistant’s
   self-report never marks the project Ready.
9. Existing project agents, skills, commands, rules, and integrations must be
   preserved unless a competent owner explicitly decides otherwise.

These decisions follow `SOUL.md`: parse-never-compute, route by actor competence,
keep Bob out of technical decisions, and preserve projects as self-contained
products.

## Implemented CLI Contract

Workspace inspection now returns, per project and per Copilot component:

- expected contract and version;
- recognized setup and evidence;
- missing requirements;
- classification: Ready, can finish safely, guided integration, owner decision,
  or could not verify;
- exact safe action, when one exists;
- responsible actor;
- project capabilities and files that must be preserved;
- prohibited actions;
- generated integration-plan and prompt payload;
- verification command and stop conditions.

The complete service contract is in:

- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/project-integration-aftercare-service-spec.md`
- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/project-integration-aftercare-analysis.md`
- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/truthful-setup-recovery-service-spec.md`

The frozen consumer contract is:

- [`docs/01-architecture/schemas/workspaces.schema.json`](../../../01-architecture/schemas/workspaces.schema.json)

Its SHA-256 is
`470a663277f77b0d60359103e1f206852f05c1b7392f3b5c31b1810b90c75c33`,
identical to the CLI repository's frozen fixture.

## Completed Implementation

1. The CLI owns a closed, fail-closed five-state classification for each
   project and each Claude/Codex component.
2. Exact safe-finish actions are opaque, bounded, and independently verified.
3. Guided plans carry preservation facts, prohibited actions, guarded prompts,
   owner handoffs, persistent holds, and authoritative verification commands.
4. Control Tower decodes the frozen contract and renders its facts directly. It
   does not reproduce classification or semantic inspection logic.
5. Safe-finish, guided-integration, owner-decision, and could-not-verify routes
   have explicit controls. Guided actions open a visible Terminal session in
   the selected project and run the CLI-generated prompt with Codex or Claude
   Code; uncertain projects receive a helper-authored read-only diagnostic.
6. Only CLI verification can transition a project to Ready.
7. Representative live projects were inspected read-only; classification did
   not mutate their working trees.

## Completed Design and QA

- Tasks 183 and 184 are complete with service, UX, UI, and QA work products.
- Task 185 orders the walkthroughs, records the future naming convention, and
  produces this handoff.
- Tasks 187 through 193 cover the architecture, frozen schema, classification,
  safe finish, guided integration, representative-project QA, and Control Tower
  consumer.
- CLI QA passed 61 focused tests and the environment-excluded full suite with
  1,186 passing tests. Read-only representative-project checks preserved every
  pre-inspection fingerprint.
- Control Tower QA passed the frozen-contract decoder, user-app bundle,
  compatibility release gate, CLI seam smoke suite, and the 126-scenario matrix.
- Live safe-finish and guided-integration popovers passed production-width visual
  checks, including the full guided-plan drill-in.
- The focused walkthroughs passed Chromium navigation, theme, responsive,
  no-external-request, no-console-error, Aviator-branding, and visual checks.
- The shared UxD and UIDS skills now require
  `NN-<feature>-<stage>-walkthrough.html`, contiguous narrative ordering, adjacent
  UXD/UIDS pairs, a directory index, and reference updates when renumbering.

## Walkthrough 05–08 Acceptance Gate

The executable matrix is:

- [`09-walkthrough-05-08-acceptance-matrix.md`](../walkthroughs/09-walkthrough-05-08-acceptance-matrix.md)
- `scripts/tests/test_walkthrough_05_08_acceptance.sh`

Measured results:

- current source implementation with the checked-in cc 1.7.14 package:
  **40/40, 100%, zero critical failures**;
- production User app bundle, project-integration contract, in-binary triage,
  diagnostic, Terminal-launch quoting, and clean-home lifecycle tests: pass;
- completed-setup acceptance gate, including fixed four-component topology,
  four tiers, truthful incomplete readiness, Personal/private language,
  same-view project aftercare, and return-later routing: pass;
- exact signed and notarized 0.2.2 app binary topology, aftercare, launcher,
  signing-entitlement, and purpose-string self-tests:
  pass;
- clean-home lifecycle: `safe-finish → finish → Ready → verify`, plus
  independent guided-integration and owner-decision routes;
- the release helper is cc 1.7.14 from signed foundation snapshot `v5.13.16`,
  accepted by Apple notarization, universal for arm64 and x86_64, and pinned by
  SHA-256 in `packaging/cc/PINNED_SHA256`.

## 0.2.2 Release Closure

The visible guided-assistant launch boundary is closed:

- Control Tower tag `v0.2.2` resolves to source commit
  `a769502f1feb4e379ba96fc5c46e36c08c216499`.
- The release app is version 0.2.2, build 13, with unchanged cc 1.7.14 pinned at
  `6a7b9b5278b33ac96fb9bc9125dc715a016d3c0b71675fee1ebdfe85c92dcf07`.
- Apple accepted app submission
  `6047bab9-ca81-4de5-8d0e-5188484a4638` and DMG submission
  `9cabac2d-ce22-43da-87c6-d638c947ab19`. Both are stapled and pass
  Gatekeeper.
- The final DMG SHA-256 is
  `e7e48e5042600bc2f80897049e7d83037bc5d961eb72f20551db0ec673bf68ce`.
- The exact release app carries
  `com.apple.security.automation.apple-events=true` and a non-empty
  `NSAppleEventsUsageDescription`; the release pipeline rejects the app if
  either requirement is absent.
- A visible, harmless Terminal probe exercised both launch forms with a path
  containing spaces and a multiline shell-looking prompt. Codex received the
  selected project through `-C`; Claude Code ran from that directory; both
  received the exact prompt; no prompt text executed as shell syntax.
- The complete regression evidence includes 126/126 scenario checks and the
  revised walkthrough matrix at **40/40, 100%, zero critical failures**.
- The published GitHub release was downloaded after publication and all five
  assets were byte-compared with the locally verified originals; the DMG
  checksum passed again.
- The release is published at
  `https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/releases/tag/v0.2.2`.
- The exact checked-in release artifacts are under
  `release/control-tower-0.2.2-a769502/`.

On the first guided launch, macOS may ask whether Copilot Control Tower may
control Terminal. The user must choose **Allow**. If permission was denied,
enable Terminal for Copilot Control Tower in **System Settings → Privacy &
Security → Automation**, then retry. The fallback prompt remains copied, and
only independent `cc workspace verify` can mark the project Ready.

## 0.2.1 Release Closure

The truthful completed-setup release boundary is closed:

- Control Tower tag `v0.2.1` resolves to source commit
  `e3584557ebed3967632e7790ee391d0b257dbc75`.
- The release app is version 0.2.1, build 12, with cc 1.7.14 pinned at
  `6a7b9b5278b33ac96fb9bc9125dc715a016d3c0b71675fee1ebdfe85c92dcf07`.
- The helper comes from signed foundation snapshot `v5.13.16`, whose snapshot
  source commit is `566ed5007fe70e7258637b9d1c1b4b8fa581b6b0`; its release-tool source is
  `507c97012e1e4ce27fc5d627afcb5327cceb9185`.
- Apple accepted helper submission
  `cec4033a-89d8-481f-b0dd-d5bc806831ce`, app submission
  `085acf1f-e998-43f9-aeb5-df025138197d`, and DMG submission
  `93f11320-d61d-4143-ae5c-7d719859ca7c`.
- Both app and DMG are stapled and pass Gatekeeper. The final DMG SHA-256 is
  `b20f7297a474319edf05dcb906f56c353dd93210b2205e74d9ec428f2532cc37`.
- The exact tagged app passed its project topology/aftercare, onboarding
  question, tray project, setup-progress, and named-wait binary self-tests.
  The full source regression suite, schema compatibility gate, signed-helper
  gate, 214-case Admin setup suite, 126-scenario matrix, and walkthrough
  acceptance matrix at **38/38, 100%, zero critical failures** also passed.
- Real-pixel QA against the owner's current setup correctly rendered
  **2 of 4 Personal components ready**, Knowledge and CLI recovery, all four
  tiers, and the 53-project Ready/Guided/Couldn't Confirm aftercare categories.
- The app release is published at
  `https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/releases/tag/v0.2.1`;
  the helper release is published at
  `https://github.com/Everyone-Needs-A-Copilot/claude-copilot/releases/tag/v5.13.16`.
- The exact checked-in release artifact is under
  `release/control-tower-0.2.1-e358455/`.

Installing the app remains read-only. It does not silently create repositories.
When Personal setup is incomplete, **Finish Personal Setup** reopens the setup
flow, where the user reviews and approves the plan that creates or reuses all
four private Personal backing repositories. Project work may likewise be
deferred and resumed from **Open project aftercare**.

The app/CLI JSON schema remains 1.0. The aggregate onboarding report now requires
the additive four-component set, and `controltower.compat.json` raises the
helper floor to 1.7.14.

## 0.2.0 Release Closure

The revised Step 7 release boundary is closed:

- Control Tower tag `v0.2.0` resolves to source commit
  `2cdb870dba05469a13d27a8304e3f38e757d4f1f`.
- The release app is version 0.2.0, build 11, with cc 1.7.13 pinned at
  `d391412655ccf5e319489c7730a818c9c0e053988d088fa839e7ed3cb5bc53f3`.
- The helper comes from signed foundation snapshot `v5.13.15`, whose orphan
  source commit is `bdaf99b4a20d0d79f78fc3607dcdc3472bfb6a63`.
- Apple accepted helper submission
  `9fab71bd-a901-4391-af80-e1503d133daf`, app submission
  `48cfeadc-23a5-461f-8221-57f0ef2a4442`, and DMG submission
  `d1a1aa79-f151-4b97-b8fb-c691f39274a9`.
- Both app and DMG are stapled and pass Gatekeeper. The final DMG SHA-256 is
  `57edfec6b8e753491d44b0c1549fe01b8b1f03cced4cabccd24ef08d3b54b837`.
- A drag-installed copy passed project/tray/setup self-tests, real read-only
  Detect, inert Set up → Verify, exact embedded-helper verification, and the
  walkthrough acceptance matrix at **38/38, 100%, zero critical failures**.
- The exact GitHub-downloaded DMG independently matched its checksum, validated
  its staple, and passed Gatekeeper.
- The app release is published at
  `https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/releases/tag/v0.2.0`;
  the helper release is published at
  `https://github.com/Everyone-Needs-A-Copilot/claude-copilot/releases/tag/v5.13.15`.
- The exact checked-in release artifact is under
  `release/control-tower-0.2.0-2cdb870/`.

The app/CLI JSON schema remains 1.0. The diagnostic payload is additive and
optional; `controltower.compat.json` raises the helper floor to 1.7.13.

## Historical 0.1.9 Release Closure

The release boundary is closed:

- Control Tower tag `v0.1.9` resolves to source commit
  `441f87f054cdf2c5d7e6a17b67eee110c7a19f57`.
- The release app is version 0.1.9, build 10, with the unchanged cc 1.7.12
  helper pinned at
  `8bc00f8c723ef903f37d39928167581872b0efadebed995556f118bd80994643`.
- Apple accepted the app submission
  `8dbe08c9-1ae6-40e1-acb2-423f453228c1` and DMG submission
  `d95990dd-3c5e-4e6e-9ea9-f52ce9b6bb5b`.
- The app is stapled before DMG assembly, so a drag-installed copy validates
  its ticket offline. Both the installed app and outer DMG also pass
  Gatekeeper assessment.
- The final DMG SHA-256 is
  `06ed5859814509d8560a1c2f5e59217e854eaedae0e8192ae38ed1a0423068f7`.
- A clean drag-install from the final DMG passed the installed app's project,
  setup-progress, named-wait, headless Detect, and Set up → Verify seams.
- The installed helper passed the default lifecycle matrix at **33/33, 100%,
  zero critical failures**.
- The exact release artifact is stored under
  `release/control-tower-0.1.9-441f87f/`.

The earlier immutable `v0.1.8` candidate was rejected—not rewritten—after
clean-install QA found that its app ticket had been stapled after DMG assembly.
The corrected 0.1.9 producer notarizes and staples the app first and has a
regression gate for that ordering.
