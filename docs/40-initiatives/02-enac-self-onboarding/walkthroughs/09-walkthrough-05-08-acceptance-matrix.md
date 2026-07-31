# Walkthrough 05–08 implementation acceptance matrix

> **Implementation update, 2026-07-30:** walkthroughs 07 and 08 define the
> revised Step 7 triage experience under `tc` 195, implemented under `tc` 196.
> The 07/08 assertions now cover focused category navigation, durable
> menu-bar aftercare, exact couldn't-confirm evidence, and visible Terminal
> execution for guided setup.

This is the executable completion gate for the UX and UI walkthroughs:

- 05 / 06: truthful setup, recovery, and its high-fidelity realization
- 07 / 08: project integration, aftercare, and its high-fidelity realization

The gate is screen-level, requires at least 95% overall coverage, and permits
zero failures in critical safety, truthfulness, verification, or packaged-
helper criteria.

Run:

```bash
scripts/tests/test_walkthrough_05_08_acceptance.sh
```

For a development artifact, pass the exact frozen helper embedded in the test
app:

```bash
CT_ACCEPTANCE_CC=/path/to/app/Contents/Resources/cc \
scripts/tests/test_walkthrough_05_08_acceptance.sh
```

That override proves functional compatibility only. The default release gate
uses `packaging/cc/cc`, which must remain the separately signed, notarized
1.7.15 universal artifact and must pass
`scripts/verify-vendored-cc.sh --release packaging/cc/cc`.

| Range | Acceptance surface | Evidence |
|---|---|---|
| 05-01…05-11 | Named four-copilot roster; exact missing state; real denominator; post-setup Doctor verification; five project classifications; safe preservation review; distinct routes; truthful results; final outcome summary; readable popover; honest recovery | Native model/render assertions |
| 06-V | High-fidelity wizard hierarchy | Native card/status hierarchy plus visual inspection |
| 07-01…07-23 | Five classifications; focused category navigation; Ready capability/evidence; review-first safe finish; opaque action; per-component state; full guided contract; visible Terminal assistant choice; prompt preview; owner handoff; return verification; fail-closed outcomes; persistent capability visibility; durable return-later path; exact diagnostic evidence; helper-authored read-only diagnosis; signed Terminal automation permission; resolved absolute assistant paths | Schema fixtures, native route assertions, signed-bundle entitlement gate, clean helper lifecycle, real-pixel inspection |
| 08-V | High-fidelity popover hierarchy | Readable status/layer hierarchy plus visual inspection |
| PKG-01…02 | Exact embedded helper version and verbs | Executed helper boundary |
| CLEAN-01…02 | Clean-home classifications and `safe-finish → Ready → verify` | Executed helper against authoritative framework sources |

Current source truth: the checked-in cc 1.7.15 package and revised native
implementation pass **40/40 (100%)** with zero critical failures. The signed,
notarized 0.2.2 release artifact passed the same **40/40** matrix against its
exact embedded helper. Earlier releases remain historical.
