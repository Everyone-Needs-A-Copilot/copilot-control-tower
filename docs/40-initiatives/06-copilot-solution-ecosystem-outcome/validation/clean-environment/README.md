# TASK-303 clean-environment journey harness

Status: harness implemented, adversarially hardened, and fixture-verified; final live proof remains prerequisite-blocked.

This directory contains the isolated execution and evidence boundary for S-12. It proves the harness before it is trusted with the final released ecosystem. Fixture success is harness evidence only and must never be reported as ecosystem success.

## Safety boundary

`clean_journey.py` creates a dedicated root with isolated `HOME`, XDG directories, Claude configuration, Codex home, Git global configuration, GnuPG home, temporary directory, project, and evidence directory. It inherits only a small non-secret environment allowlist, disables subprocess stdin, refuses environment and command dispatchers, refuses inline shell or interpreter code, requires every interpreter to be paired with an exact reviewed script, invokes argument arrays without a subprocess shell, terminates the subprocess process group on timeout, rejects an existing unowned or writable directory or Git repository, and prevents declared paths from escaping the isolated root.

The root marker binds the resolved path, owner UID, device, inode, critical layout identities, plan digest, execution-binding digest, session, and random run nonce. Every command record binds those identities, its exact plan position, the previous record digest, declared project mutation paths, protected-path hashes, fresh evidence artifacts, output scans, and the exact reviewed executable or interpreter/script identities it invoked. Resume accepts only a deliberately paused run and requires the paused manifest SHA-256 retained outside the isolated root.

The execution contract is closed: every `--bind` name must be declared and every declaration must be used through an explicit placeholder. Live plans require exact SHA-256 values and review evidence for every executable and script. Fixture plans may use `capture-at-run` only to test the harness portably; the actual resolved path and hash are still locked into the marker, state, records, and manifest for that run. Bindings cannot be added, substituted, moved, or changed between pause and resume.

Suspected credentials in the plan or resolved argument vector block execution before a command record is created. Suspected credentials in stdout or stderr are suppressed, and suspected credentials in a declared evidence artifact are overwritten with a suppression marker before the failing record is written. A timed-out command always fails even if exit 124 was listed as expected.

The verifier reconstructs the expected record set from the executed plan prefix and rejects missing, extra, reordered, renamed, replayed, non-passing, or identity-mismatched records. It reconstructs the complete manifest from current state, plan, records, executable identities, declared artifacts, project tree, and home tree. Live independent verification also requires the final manifest SHA-256 retained outside the isolated root.

## Application exclusion

The command plan refuses application build, signing, notarization, native-source, and `.app` dependencies. Literal scans alone are not treated as sufficient: each exact executable hash must carry an explicit `app_dependency_free` review assertion and evidence. The final manifest derives its subprocess inventory from those locked identities and describes the proof basis. No app installation or app source is part of this journey.

## Fixture verification

Run the deterministic harness tests from this directory:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v test_clean_journey.py
```

Run and independently verify the complete fake journey in a disposable root:

```bash
python3 clean_journey.py run --plan fixtures/fixture-plan.json --bind python="$(command -v python3)" --bind fixture_tool="$PWD/fixtures/fixture_runtime.py"
python3 clean_journey.py verify --plan fixtures/fixture-plan.json --root /path/returned/by/run --bind python="$(command -v python3)" --bind fixture_tool="$PWD/fixtures/fixture_runtime.py"
```

The fixture covers problem intake and routing, Claude/Codex assembly, artifact creation, durable preservation, fresh-process continuation, an approved update, an expected dirty-project hold, entitlement recovery, and conformance. It also proves that human-owned fixture bytes survive update and recovery. The fixture runtime is a test double and does not establish that any released component works.

To exercise a real process boundary, retain the `manifest_sha256` returned by the paused command outside the isolated root and supply it to resume:

```bash
python3 clean_journey.py run --plan fixtures/fixture-plan.json --stop-after preserve --bind python="$(command -v python3)" --bind fixture_tool="$PWD/fixtures/fixture_runtime.py"
python3 clean_journey.py resume --plan fixtures/fixture-plan.json --root /path/returned/by/run --anchor-sha256 PAUSED_MANIFEST_SHA256 --bind python="$(command -v python3)" --bind fixture_tool="$PWD/fixtures/fixture_runtime.py"
python3 clean_journey.py verify --plan fixtures/fixture-plan.json --root /path/returned/by/run --bind python="$(command -v python3)" --bind fixture_tool="$PWD/fixtures/fixture_runtime.py"
```

## Final live run

`live-plan.template.json` is intentionally not executable. Its TASK-285, TASK-291, TASK-300, TASK-288, and TASK-299 prerequisites are pending, its identities are placeholders, and every trusted executable hash and review reference is unresolved. Inspection accepts the template only with `--allow-pending`; execution never accepts pending prerequisites or placeholder identities.

After TASK-299, copy the template to a timestamped plan. Replace every prerequisite with an evidence object containing a real work-product ID and exact SHA-256. Replace every ecosystem identity with the final commit, tree, immutable tag, signer, census, runtime, model, and plugin evidence. Replace every execution-contract placeholder with the SHA-256 and review evidence for the exact executable that will be bound at runtime. Validate the exact plan before execution:

```bash
python3 clean_journey.py check-plan --plan live-plan.template.json --allow-pending
python3 clean_journey.py check-plan --plan live-plan.TIMESTAMP.json
```

The live operator runs the exact plan, pauses after `preserve`, retains the returned paused manifest SHA-256 outside the root, and resumes in a new process using `--anchor-sha256`. After completion, the operator retains the returned final manifest SHA-256 in the TASK-303 work product. Independent QA must call `verify` with `--expected-manifest-sha256 FINAL_MANIFEST_SHA256` as well as the exact original bindings.

TASK-303 may be completed only when that live manifest passes, final conformance has zero blocking unexplained results, the external digest anchors are preserved, and independent QA approves the live evidence.

## Trust boundary and residual risk

This harness is not an operating-system sandbox. An exactly hashed executable remains capable of filesystem or network behavior beyond its declared arguments. That is why live execution requires an exact hash plus explicit review evidence rather than accepting a path or command name. The same-user operator also controls the harness source and could replace both code and evidence; final provenance must therefore bind the harness source hash and final manifest hash in a work product outside the isolated root. Stronger resistance to a malicious local administrator would require an external signer or isolated runner and is outside TASK-303's local clean-environment proof.
