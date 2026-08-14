# TASK-303 clean-environment harness security review

Date: 2026-08-14

Scope: harness readiness only. This review does not approve the pending live plan, its future driver executables, or completion of TASK-303.

## Assets and actors

The protected assets are the exact released framework and knowledge identities, prerequisite evidence, the ordinary problem and human-owned project bytes, runtime credentials, Task Copilot continuity state, declared evidence artifacts, the record chain, and the final outcome claim.

The expected actor is the repository owner running reviewed tools under one macOS user. Other relevant actors are exact Claude, Codex, `cc`, installer, and journey-driver processes; a corrupted or substituted executable; a process that attempts to escape the isolated root; and another process running as the same operating-system user.

## Trust boundaries

The plan and reviewed harness source define the proof contract. CLI binding values cross into that contract only after the declared binding set, resolved file identity, executable role, exact hash, app-free review assertion, and review reference pass. Live plans cannot use the fixture-only `capture-at-run` exception.

The isolated root separates configuration and evidence from the operator's real home, but it is not an operating-system sandbox. Exact reviewed executables remain inside the trusted computing base and retain the filesystem and network privileges of the user.

Local hash seals detect inconsistent state but are not authentication against a same-user actor who can rewrite all local files. The externally retained paused and final manifest hashes cross that boundary and must be stored with the reviewed harness source identity in Task Copilot work products.

## Threats and controls

| Threat | Initial risk | Control and evidence | Residual risk |
| --- | --- | --- | --- |
| Shell or interpreter dispatch bypass | High | Closed argv0 binding, environment/command dispatcher denylist, declared interpreter family, known interpreter binaries cannot be relabeled as ordinary executables, interpreter requires an allowed exact script at argv1, shebang executables rejected, inline flags rejected, regression tests for substituted or relabeled interpreters, `env`, Python `-c`, and unbound shebangs | Low within reviewed binding contract |
| Executable substitution | High | Live exact SHA-256, resolved path identity, no extra bindings, binding digest in marker/state/records/manifest, before/after command recheck, changed-path and changed-byte tests | Same-user race remains part of local-admin residual |
| Root or path escape | High | Real non-writable owner root, path/device/inode/UID binding, critical layout inode binding, path resolution inside root, marker seal, symlink attack tests | A trusted executable still has ambient user permissions |
| State replay or evidence surgery | High | Random run nonce, exact plan prefix, exact filenames/IDs/stages, linked hashes, state head, current artifact hashes, reconstructed manifest, external pause/final anchors, truncation/insertion/replay/tamper tests | Same-user actor can replace harness and all external evidence unless release/task provenance is independently preserved |
| Premature prerequisite authorization | High | Exact five-task set, positive work-product ID and SHA-256 for every completed prerequisite, closed plan fields, exact cryptographic identity formats, work-product-bound executable reviews, and whole-plan placeholder rejection | Quality of referenced upstream evidence remains TASK-303 QA's responsibility |
| Credential disclosure | High | Secret environment variables dropped, stdin disabled, plan/argv blocked before execution, output suppressed, declared artifact content suppressed, regressions for all paths | Pattern-based scanning may not recognize a future credential format |
| Timeout descendant mutation | Medium | Dedicated process group, group `SIGKILL`, timeout always fails even when exit 124 is expected, delayed-child regression | A reviewed executable could deliberately detach into another session; OS isolation is not claimed |
| False mutation success | Medium | Exact before/after tree manifests and declared allowed mutation paths, freshness requirement for every evidence artifact, unrelated-change regression | Semantic correctness of an allowed changed file requires live QA |
| Hidden Control Tower app dependency | Medium | Literal plan/path deny rules plus exact executable hash and explicit app-free review evidence; manifest derives proof basis and subprocess inventory | No dynamic system-call sandbox; executable review must cover indirect PATH/network behavior |

## Security verdict

No unmitigated high-risk harness defect remains within the stated local proof boundary. The 23-test adversarial suite and public CLI run support approval of the harness for a later exact live plan.

ARTIFACT: test-run|`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v test_clean_journey.py`|exit=0|`23 adversarial and journey tests passed`

ARTIFACT: file-check|hardened harness SHA-256|`7a51c0f571a3816d1ba5556b0739a3ec18aed293cc61788bcb47d1f21ce00d0f`

SECURITY VERDICT: APPROVED-FOR-HARNESS-READINESS

Final live execution must still bind every executable to an exact immutable source/release, preserve the external digest anchors, verify no app dependency in each executable's review evidence, and receive a new independent security/QA verdict. This review does not authorize marking TASK-303 complete.
