# Non-technical participant validation protocol

> **Deferred on 2026-08-14.** This protocol is preserved for future product validation but is not an Initiative 06 completion gate. See [ADR-010](../decisions/adr-010-technical-ecosystem-first.md).

Status: preserved future-validation protocol; not recruited, scheduled, or executed Preservation record: TASK-290 Future execution record: create a new task when Pablo authorizes the study Acceptance criterion: AC-19F remains pending

## Purpose

Observe whether a real non-technical person can use the provisioned framework to begin a representative problem-to-solution journey, understand each prompt, and leave with a useful, owned next step without terminal work, Git knowledge, Pablo's intervention, or observer coaching.

This is a service-validation protocol, not a model-quality benchmark. One participant cannot prove general usability or ecosystem effectiveness. A team member, agent, scripted persona, model simulation, or the product author cannot substitute for a real participant.

## Preservation boundary

TASK-290 preserves this executable protocol and its evidence requirements. Completing TASK-290 means only that a future study can begin from a reviewed, durable protocol after Pablo has dogfooded the technically complete ecosystem. It does not mean a participant was recruited, a session occurred, or AC-19F passed.

The future study must receive a new `tc` task rather than reopening or reinterpreting TASK-290. That execution task must link this protocol, the exact then-current clean-environment proof, the framework and content identities used, its consent and privacy approval, the redacted observation record, and an independent QA verdict. Until that record exists, PRD-23 and later product records must describe AC-19F as `PENDING — STUDY NOT RUN`.

TASK-290 therefore has no execution dependencies. Its former TASK-299 and TASK-303 dependency links were conditions for running a participant session; ADR-010 moved that session out of this initiative's completion graph. The equivalent then-current security and clean-environment evidence remains mandatory at the future study's entry gate below.

This protocol has no Control Tower dependency. It evaluates the ordinary provisioned framework workflow that exists after technical dogfooding. A later app-specific participant journey belongs to PRD-24 or its successor and cannot borrow a verdict from this framework-only protocol.

## Service boundary and journey

The participant's job is to turn an ordinary problem into a useful, owned next step without learning the ecosystem's machinery. The study owner's job is to create a safe, neutral environment and observe where that journey succeeds or breaks without repairing it during the session.

| Stage | Participant frontstage | Framework backstage | Study owner and support boundary | Transition evidence |
| --- | --- | --- | --- | --- |
| Prepare | Sees nothing and provides no credentials or work data | Exact released framework and synthetic task packet are provisioned and sealed | Confirms entry gates, consent materials, privacy controls, stop contacts, and artifact identities before recruitment | Approved prerequisite record and packet digest |
| Consent | Chooses whether to participate and whether any recording is allowed | No framework interaction begins | Explains voluntary participation, withdrawal, retention, compensation, and data handling in plain language | Signed consent stored outside Git/`tc`; pseudonymous session ID in the evidence record |
| Begin | Starts from the ordinary problem and participant instructions | Normal routing selects relevant specialist work | Gives the brief and only permitted neutral prompts; does not translate or coach | Timestamped start, visible state, action, and routing evidence |
| Create | Frames the problem, weighs evidence and unknowns, and creates a shareable decision brief | Entitled context and specialist craft support the work without exposing internal architecture | Records behavior and stopping points without steering choices | Redacted event notes and hashed project artifact |
| Preserve and return | Finds the saved work, explains the next step, and shows how they would return | Task state and artifact links survive the process/session boundary | Does not reconstruct the prompt or navigate on the participant's behalf | Pre-pause state, fresh-session return evidence, and participant explanation |
| Recover or stop | Encounters the planned unavailable-state probe or an unplanned failure and decides what to do | Failure state remains honest, bounded, and actor-appropriate | Stops on any safety condition; never repairs in the evidence session | Failure/recovery event, actor/action comprehension, or sealed stop reason |
| Debrief | Explains what happened, what remains theirs to decide, and whether they feel finished | Produces no new claim on the participant's behalf | Asks the fixed debrief questions and confirms quotation permissions | Completed rubric with evidence links and approved quotations only |
| Seal | Has no further obligation beyond compensation and withdrawal rights | No live state is treated as evidence after identities change | Redacts, scans, independently reviews, retains, and deletes records according to the approved policy | Evidence manifest, redaction result, QA verdict, and deletion dates |

The recommended first execution is one moderated think-aloud session using the neutral observer script below because it makes comprehension failures and prohibited assistance observable while preserving a precise stop record. An unmoderated run may be useful later for ecological validity, but it should not replace the first moderated evidence session because missing context would make failures hard to interpret. Internal rehearsals, simulated participants, expert walkthroughs, and Pablo's dogfooding are rejected as AC-19F evidence because they do not test the intended participant boundary.

## Entry gate

Do not recruit or schedule a participant until:

- the then-current clean-framework-environment proof satisfies the TASK-303 contract for AC-18F;
- the then-current immutable-release proof satisfies the TASK-297 contract and identifies the exact owner-approved shared content and framework revision used in the session;
- the then-current integrated security proof satisfies the TASK-299 contract for post-fan-out entitlement, personal/shared, secret, symlink, lock, and ownership boundaries;
- the study owner has approved the recruitment text, consent form, data fields, compensation if any, retention schedule, observer, location, and stop/escalation contacts;
- the test account/device contains only synthetic task material and no other person's private workspace.

If any gate is absent, store `NOT RUN — PREREQUISITE MISSING`. Do not use an internal rehearsal as evidence.

## Participant profile and recruitment

Recruit an adult who:

- is within the intended non-technical solution-creator audience;
- does not use a terminal or Git as part of ordinary work;
- did not build, test, administer, or author this ecosystem;
- is not expected to understand repositories, manifests, ranks, severity tokens, CLI commands, or model/runtime architecture;
- can voluntarily decline without employment, client, or relationship consequence.

Recruitment must state the purpose in plain language: testing the product, not the person's competence. It must state what will be observed, what may be recorded, the synthetic nature of the task, expected compensation, voluntary participation, withdrawal rights, and whom to contact. Do not recruit through a manager in a way that makes participation feel mandatory.

## Consent and privacy

Before the product is shown, obtain affirmative written consent for observation and note-taking. Screen/audio/video recording is off by default and requires a separate explicit choice. Withdrawal stops the session immediately; where legally possible, delete that participant's unaggregated study data on request.

Use a random session ID. Keep name, contact information, consent, and payment records outside Git and `tc` in an access-limited study record. The initiative artifact may contain only the session ID, eligibility declaration, artifact identities, redacted observations, rubric results, and participant quotations that the participant explicitly approved.

Retention:

- optional raw screen/audio/video recording: access-limited and deleted within 14 days after the redacted evidence is independently verified;
- contact/session mapping: deleted within 30 days after compensation and any withdrawal request are resolved;
- consent/payment record: retained only for the period required by the approved study policy; if no policy is approved, do not recruit;
- de-identified criterion evidence: retained with Initiative 06 provenance.

Never collect personal passwords, tokens, recovery codes, private notes, client names, financial information, health information, unrelated screen content, home paths, device serials, or repository identities. Pause capture before the participant enters their own credentials. Run a value-suppressing sensitive-content scan before evidence enters `tc` or Git.

## Representative task

Give the participant the neutrally provisioned framework workflow and ordinary participant instructions only. Provisioning is not part of this participant test and may not continue during observation. Use this synthetic brief without ecosystem jargon:

> A fictional regional transportation team knows riders abandon support when travel plans change unexpectedly. You have a short packet of fictional rider comments and operating constraints. Use this tool to help the team decide what problem to solve, what kind of solution to explore, and what they should do next. Stop when you believe you have a decision brief you could share with the fictional team.

The packet must be the versioned synthetic EVAL-01 input approved through TASK-284/285, with no private oracle, real company/client/person data, or preselected feature. Record its digest. The participant owns the decisions; the system must expose choices, evidence, unknowns, and next steps rather than declare unreviewed user validation or a final answer on the team's behalf.

## Observer script

Read this introduction verbatim:

> Thank you for helping us test the product. We are testing the product, not you. The task and all people or organizations in it are fictional. Please work as you normally would and say what you expect or find confusing. I will not tell you where to click or how the system works. You may pause or stop at any time. Please do not enter personal or work-confidential information.

Then give the brief and ordinary instructions. The observer may use only these neutral prompts:

- “What are you expecting to happen?”
- “What does that message mean to you?”
- “What would you do next?”
- “What makes you feel finished?”

The observer must not name a button, translate jargon, recommend a specialist, suggest prompt wording, handle sign-in, open Terminal, edit a file, copy a repository, resolve an error, or ask Pablo to intervene. If the participant asks for help, reply once: “Please do what you would normally do if I were not here.” If they still cannot continue, record the stopping point as product evidence; do not coach around it.

After the participant stops, ask:

1. “In your own words, what did the system help you do?”
2. “What decision does the fictional team still own?”
3. “What evidence or unknowns would you check next?”
4. “Did the system ask you to do anything you did not understand or did not feel was yours to decide?”
5. “What would you expect to happen if the network or sign-in stopped working?”
6. “Would you know how to return to this work later? Show me, without changing the result.”

## Observation record

Use event notes, not interpretation alone. For each meaningful event record:

- pseudonymous session ID and timestamp;
- visible state or prompt in redacted plain language;
- participant action or verbatim approved short quotation;
- whether the action was independent, requested help, or stopped;
- linked screenshot/output/Task Copilot evidence identity where consented;
- criterion affected and observer rationale;
- any intervention. An intervention automatically prevents an independent-pass verdict for that step.

Record the exact framework/runtime/content identities and the TASK-303 environment evidence. Preserve the complete journey and stopping point; do not retain only successful moments or rerun because the first result is unflattering.

## Future evidence packet

Store the redacted study result as a manifest that links, rather than embeds, privacy-sensitive source records. Every required field must be present even when the value is `NOT RUN`, `NOT COLLECTED`, `STOPPED`, or `NOT APPLICABLE` with a reason.

| Evidence group | Required fields or linked artifacts |
| --- | --- |
| Authorization | Future execution task ID; study owner; protocol commit and content digest; recruitment, consent, compensation, retention, observer, location, and stop-contact approvals; authorization date |
| Preconditions | TASK-303 successor evidence; TASK-297 and TASK-299 successor evidence as applicable to the then-current release; framework, runtime/model, organization, department, fixture, and synthetic packet identities; clean test account/device declaration |
| Consent boundary | Pseudonymous session ID; eligibility attestation; consent timestamp; separate recording choice; confirmation that identifying consent/payment records remain outside Git and `tc` |
| Journey record | Start and end timestamps; ordered redacted events; independent/help-requested/stopped classification; interventions; visible states; artifact and Task Copilot identities; exact stopping point |
| Rubric | One `DEMONSTRATED`, `PARTIAL`, `ABSENT`, or `VIOLATED` decision per criterion; evidence link; rationale; hard-gate summary; no numeric or aggregate score |
| Privacy and integrity | Sensitive-value scan result; redaction review; allowed quotation approvals; artifact hashes; unexpected writes; retention and deletion deadlines |
| Verdict | Session state `COMPLETED`, `STOPPED`, `FAILED`, or `INVALID`; bounded claim text; independent QA task and work product; `ARTIFACT:` marker; exact `VERDICT:` token |

The independent QA work product must be evidence-bound and use this minimum form:

```text
Task: TASK-<future-execution-task> | WP: WP-<qa-work-product>
Protocol: <commit>:docs/40-initiatives/06-copilot-solution-ecosystem-outcome/validation/nontechnical-participant-validation-protocol.md
Session: <pseudonymous-session-id>
Artifact identities: <manifest digest and linked redacted evidence digests>
Hard gates: <criterion-by-criterion result>
Intervention: NONE | <exact intervention and invalidated step>
Claim: This participant completed this recorded task with these immutable inputs under this protocol.
ARTIFACT: file-check|<evidence location and digest>
VERDICT: APPROVED | APPROVED-WITH-MINOR-FIXES | REJECTED
```

`APPROVED-WITH-MINOR-FIXES` may correct documentation or redaction defects only. It cannot waive a missing hard gate, observer intervention, identity mismatch, consent failure, privacy breach, or incomplete task.

## Success and comprehension rubric

Each row receives `DEMONSTRATED`, `PARTIAL`, `ABSENT`, or `VIOLATED`, with an evidence link and rationale. There is no numeric score or average. A hard-gate violation rejects the session.

| Criterion | Demonstrated when | Hard gate |
| --- | --- | --- |
| Independent start | Participant launches and begins from ordinary instructions without coaching | Yes |
| Problem framing | Participant reaches a human need/struggling-moment frame before a feature backlog | No |
| Specialist journey | Relevant specialist work occurs without the participant selecting internal roles or understanding routing | Yes |
| Prompt comprehension | Participant can explain each requested action in their own words; no raw Git, manifest, rank, tier, CLI, or severity knowledge is required | Yes |
| Actor-appropriate requests | The participant is asked only for their own sign-in or decisions about their own/synthetic material | Yes |
| Evidence discipline | Result separates supplied facts, assumptions, unknowns, and validation steps | No |
| Decision ownership | Participant can state what the fictional team still decides; the system does not claim validation or final authority | Yes |
| Durable continuation | Participant can find the saved work and explain the next step without observer help | Yes |
| Honest failure | Offline/sign-in/unavailable states do not fabricate readiness and name an understandable next actor/action | Yes |
| Privacy and boundaries | No unrelated/private data appears or moves into shared evidence | Yes |
| Completion | Participant produces a shareable synthetic decision brief and independently says they are finished | Yes |

AC-19F is supported only if every hard row is demonstrated, no prohibited intervention occurred, the participant completed the representative task, and independent QA accepts the redacted evidence. Partial comprehension is not a pass. A successful internal expert session is not participant evidence.

## Stop conditions

Stop immediately if the participant withdraws or shows distress; personal, client, credential, or unrelated data appears; the product requests terminal, Git, hidden settings, administrator judgment, or another person's authority; the observer would need to repair or coach; the artifact/content identity no longer matches TASK-303; a false success state appears; an unexpected external write is proposed; or a TASK-299 boundary concern emerges.

Seal a redacted record as `STOPPED`, `FAILED`, or `INVALID` with the exact reason and responsible actor. Do not resume after repair in the same evidence session. A new build or changed task packet requires new consent and a new session ID.

## Claim boundary

A passing session supports only the bounded claim that this participant completed this recorded task with these immutable framework/content inputs under this protocol. It does not prove general usability, accessibility for every person, organization-wide readiness, model quality, or the complete initiative outcome. If no suitable participant is available, AC-19F remains pending; no agent, author, colleague rehearsal, or simulated persona may replace the run.
