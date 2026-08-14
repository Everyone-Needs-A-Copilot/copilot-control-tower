# TASK-303 clean-environment harness independent QA and security report

Date: 2026-08-14

Verdict: `APPROVED` for the hardened harness boundary only. The final TASK-303 live journey remains pending and TASK-303 must not be completed until TASK-285, TASK-291, TASK-300, TASK-288, and TASK-299 are evidence-bound as complete and the exact released ecosystem passes this harness with independent QA.

VERDICT: APPROVED

## Findings and remediation

The initial harness was not safe enough to establish final proof. `shell=False` still permitted a plan to invoke `sh -c`, `env`, or `python -c`; executable bindings were arbitrary paths without hashes and could change on resume; live prerequisites accepted arbitrary truthy evidence; plan identities accepted placeholders; records, state, and manifest were not cross-checked against the exact plan prefix; current evidence artifacts were not rehashed during verification; the ownership marker was not bound to the root identity; command-created symlinks could replace critical directories; secrets in arguments and artifacts were not scanned; a timeout could be expected as success and could leave descendants alive; and any unrelated project change satisfied `project-required`.

The hardened schema closes those paths. Plans, prerequisites, execution bindings, commands, and placeholder syntax use closed fields. Every declared trusted binding must be used. Live bindings require exact executable SHA-256 values and work-product-bound app-free review evidence. Fixture-only `capture-at-run` identities are locked into the run and cannot establish live proof. Environment and command dispatchers are forbidden; recognized shell or language interpreters cannot be relabeled as ordinary executables, can run only an exact declared script, and cannot use inline execution. A shebang script cannot masquerade as a standalone executable because that would leave its interpreter unbound. Resume requires unchanged plan and binding digests, an unchanged root/layout marker, an exact evidence prefix, and an externally retained paused-manifest digest. Live verification requires an externally retained final-manifest digest.

Prerequisite rows in live mode must be exactly TASK-285, TASK-291, TASK-300, TASK-288, and TASK-299. A completed row requires a positive work-product ID and exact evidence SHA-256. The complete live identity field set is mandatory; Git objects, immutable semantic tag, signer fingerprint, census identity, shared-release receipt digests, and runtime/model/plugin receipt digests each have an exact format, and any unresolved placeholder anywhere in the live plan fails execution.

Each project-changing command declares its permitted mutation paths. The harness compares complete before/after manifests and rejects both no-op claims and changes outside those paths. Evidence must be a new or changed regular file inside the root. The final manifest contains current hashes for every declared evidence artifact, so post-run artifact tampering changes the reconstructed manifest.

The subprocess runs in its own process group. Timeout sends `SIGKILL` to that group and always fails the evidence contract. Argument secrets block before execution; output secrets are suppressed; artifact secrets are overwritten with a suppression marker before the failing record is preserved.

## Acceptance checks

| Check | Result | Evidence |
| --- | --- | --- |
| Closed executable identity contract | Pass | Exact declared binding set, resolved paths and hashes, live exact-hash rule, before/after identity checks |
| Shell, environment, and inline interpreter bypass | Pass | `/bin/sh`, `/usr/bin/env`, and Python `-c` regression attacks are rejected |
| Changed executable or resume binding | Pass | Wrong hash, extra binding, and same-byte different-path resume attacks are rejected |
| Root ownership and symlink escape | Pass | Root UID/mode/path/device/inode, layout inode, marker seal, and symlink regressions |
| State replay and changed plan | Pass | Resealed rollback state, modified pause state, and changed-plan resume regressions |
| Evidence truncation, insertion, reordering, manifest tamper, and artifact tamper | Pass | Exact plan-prefix and reconstructed-manifest regressions |
| Argument, output, and artifact secret leakage | Pass | All three sources fail; persisted output/artifact content is suppressed |
| Timeout descendants | Pass | Process-group child cannot perform its delayed write after timeout; expected 124 still fails |
| Mutation-policy false positive | Pass | Unrelated mutation does not satisfy a declared required path |
| App-dependency bypass | Pass at the local harness trust boundary | Literal dependency rejection plus exact hash and explicit app-free review contract; no claim of OS sandboxing |
| Premature prerequisite authorization | Pass | Exact task set and evidence shape required; unresolved live template remains blocked |
| Pause/resume with external anchor | Pass | Fresh CLI process requires the exact paused manifest SHA-256 |
| Final fixture verification | Pass | All 11 records and current artifacts reconstruct to the final manifest |

## Test execution

`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v test_clean_journey.py` exited 0 with 23 tests passing.

The public CLI accepted the fixture plan, accepted the live template only for inspection with `--allow-pending`, blocked the unresolved live template without that flag, completed and independently verified an 11-command fixture run, paused after preservation, required its external manifest anchor, resumed in a new process, and independently verified the completed result.

ARTIFACT: test-run|`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v test_clean_journey.py`|exit=0|`Ran 23 tests ... OK`

ARTIFACT: test-run|public CLI full run and verify|exit=0|`records=11 result=verified status=completed manifest_sha256=91c98f128e8de8f300bcda81b4c3d25af0be757f739aa89194f34db8fbd065cc`

ARTIFACT: test-run|public CLI pause, externally anchored resume, and verify|exit=0|`paused_manifest_sha256=014bf835bf1ac5f770e57cd9eb94c7b0da12de2981266cf70ef62ea12d41850e final_manifest_sha256=f8b7f4402998d7601baa4640d91607cc6dc137375db40e5214cca3b2f85cdba5 records=11`

## Claim boundary and residual risk

This approval establishes that the local harness detects the specified accidental and adversarial failures under its trust model. It does not establish that the ecosystem works, that pending prerequisites are complete, or that the live drivers are acceptable.

The harness is not an OS sandbox. Exact hash and review evidence make executable behavior auditable and immutable for the proof, but a reviewed executable can still access resources available to the operating-system user. A malicious same-user administrator can replace the harness and recompute local seals; TASK-303's final evidence must therefore anchor the reviewed harness source hash, paused manifest hash, and final manifest hash in external task work products. Protection against a malicious local administrator would require external signing or an isolated runner.

The live plan still needs real prerequisite work-product hashes, exact release and runtime identities, exact driver hashes, and review references. Its final run and QA are correctly blocked. No fixture result authorizes closing TASK-303 or claiming that the ecosystem is ready for owner dogfooding.
