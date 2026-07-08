# AUDIT PROMPT — copy/paste to kick off the audit

This document holds a ready-to-paste prompt for an independent auditor — a developer
using Claude Code (or any capable AI coding agent) in a fresh session inside the
`copilot-control-tower` repo. It pairs with [`AUDIT-HANDOFF.md`](AUDIT-HANDOFF.md),
which carries the full detail the prompt points at.

**How to use:** open a fresh session in the repo, then copy everything inside the
code block below (from `You are auditing…` to the end) and paste it as the first
message. Two variants are provided — pick one.

---

## Variant A — full independent audit (recommended)

```text
You are auditing Copilot Control Tower — an open-source macOS menu-bar app (Tauri v2,
Rust core + vanilla-TS UI) that is a "parse, never compute" face + supervisor over the
`copilot`/`cc` CLI. The build is complete (9 milestones, ~741 test fns, pushed to branch
`app-build`). Your job is to independently VERIFY the work, adversarially — try to
DISPROVE its claims, not confirm them.

START HERE: read `docs/AUDIT-HANDOFF.md` end-to-end. It is your complete brief — it lists
the six invariants that are the acceptance criteria, the build/test commands (including the
`CC=/usr/bin/cc` gotcha), a per-milestone map of what to break, the invariant fitness tests
to mutation-test, and the list of intentionally-mocked seams you must NOT file as defects.

Then, in order:
1. Reproduce a green build + test run. Use:
   cd src-tauri && PATH="/usr/bin:$PATH" CC=/usr/bin/cc cargo test
   and `npm run build` for the web UI. If you cannot reproduce green, STOP and report that
   as finding #1 before anything else.
2. Audit the six invariants from `CLAUDE.md`, prioritizing #1 (parse-never-compute: a false
   "Healthy" must be structurally impossible) and #6 (secrets never enter inheritance content
   or any git repo). For each invariant, find the enforcing code and try to construct an input
   or state that violates it.
3. Mutation-test the fitness tests (FF-M4-* through FF-M7-*): break the code the test guards
   and confirm the test goes red. A green test over unenforced code is a critical finding.
4. Probe fail-closed deserialization (`model/failclosed.rs`, `model/doctor.rs`,
   `model/envelope.rs`): feed malformed/partial/hostile JSON and confirm it refuses rather than
   coercing to a safe-looking default (e.g. missing `signed` must mean UNSIGNED, never signed).
5. Cross-check every candidate finding against `docs/AUDIT-HANDOFF.md` §8 (known mocked gaps)
   before reporting it — a mocked seam is not a bug.
6. Look for security vulnerabilities, inefficient code, and low-performing code.
7. Ensure the final product aligns with the product vision.

RULES:
- Do NOT modify product code except throwaway mutations to test a fitness test (revert them).
- Do NOT try to prove Windows behavior — it's `#[cfg(windows)]`-gated and unbuildable on macOS.
- Prefer a concrete reproduction (input/state → wrong output) over a "this looks risky" smell.

DELIVERABLE: findings ranked most-severe first. For each: file:line, the invariant it breaks
(or "quality"), severity (Critical/High/Medium/Low/Nit), a concrete failure scenario, and
whether a fitness test should have caught it. End with a one-paragraph verdict per invariant:
holds / holds-with-caveats / broken, with evidence.
```

---

## Variant B — fast triage (time-boxed, invariants #1 and #6 only)

```text
You are doing a time-boxed security triage of Copilot Control Tower, a Tauri v2 "parse, never
compute" supervisor over the `copilot`/`cc` CLI (branch `app-build`). Read `docs/AUDIT-HANDOFF.md`
§2, §3, §7, and §8 only.

Focus ONLY on the two load-bearing invariants:
1. Parse-never-compute — the app must never compute a "Healthy"/green state; it only renders
   CLI `--json` verdicts. Try to make the tray/popover show healthy without the CLI saying so.
   Look at `render/derive.rs`, `model/doctor.rs`.
2. Secrets never travel — inheritance/manifest content and telemetry must carry NO secret and
   NO personal name/path, only `requires_secret: <NAME>` references. Try to get a high-entropy
   token, a map KEY, or a single-char-class token past the leak-scan in `settings/guard.rs`;
   confirm telemetry (`telemetry/schema.rs`) is content-free.

Build/test: cd src-tauri && PATH="/usr/bin:$PATH" CC=/usr/bin/cc cargo test

Report only Critical/High findings with a concrete reproduction. Skip anything in
`AUDIT-HANDOFF.md` §8 (intentionally mocked). Give a two-line verdict on each of the two
invariants.
```

---

## Notes for whoever runs this

- **Both variants are self-contained** — the auditor needs nothing from you beyond repo access; the prompt sends them to `AUDIT-HANDOFF.md` for all detail.
- **If the auditor is a human** (no AI agent), hand them `AUDIT-HANDOFF.md` directly — the prompt block is the same checklist in imperative form.
- **The `CC=/usr/bin/cc` prefix is not optional** on this machine — without it, `cargo test` fails to compile `aws-lc-sys` because the `copilot` CLI (installed as `cc`) shadows the C compiler. Tell the auditor up front.
- **Expected honest result:** invariants hold; findings, if any, will be in fail-closed edge
  cases, fitness-test tightness, or quality — not in the core parse-never-compute/secrets
  guarantees, which are the most heavily tested. If an auditor reports a Critical against #1 or
  #6, take it seriously and reproduce it before shipping.
