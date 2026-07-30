# Walkthrough 05–08 acceptance matrix

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
1.7.12 universal artifact and must pass
`scripts/verify-vendored-cc.sh --release packaging/cc/cc`.

| Range | Acceptance surface | Evidence |
|---|---|---|
| 05-01…05-11 | Named four-copilot roster; exact missing state; real denominator; post-setup Doctor verification; five project classifications; safe preservation review; distinct routes; truthful results; final outcome summary; readable popover; honest recovery | Native model/render assertions |
| 06-V | High-fidelity wizard hierarchy | Native card/status hierarchy plus visual inspection |
| 07-01…07-16 | Five classifications; register; Ready capability/evidence; review-first safe finish; opaque action; per-component state; full guided contract; assistant choice; prompt preview; owner handoff; return verification; fail-closed outcomes; persistent capability visibility | Schema fixtures, native route assertions, clean helper lifecycle |
| 08-V | High-fidelity popover hierarchy | Readable status/layer hierarchy plus visual inspection |
| PKG-01…02 | Exact embedded helper version and verbs | Executed helper boundary |
| CLEAN-01…02 | Clean-home classifications and `safe-finish → Ready → verify` | Executed helper against authoritative framework sources |

Current release truth: the checked-in signed and notarized cc 1.7.12 package
passes **33/33 (100%)** with zero critical failures.
