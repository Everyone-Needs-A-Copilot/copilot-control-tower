# Non-technical participant validation protocol

Status: protocol only; not recruited, scheduled, or executed
Task: TASK-290
Acceptance criterion: [AC-19](../phases/phase-1-outcome-prd.md#8-acceptance-criteria-and-current-evidence)

## Purpose

Observe whether a real non-technical person can use the final signed ecosystem
to begin a representative problem-to-solution journey, understand each prompt,
and leave with a useful, owned next step without terminal work, Git knowledge,
Pablo's intervention, or observer coaching.

This is a service-validation protocol, not a model-quality benchmark. One
participant cannot prove general usability or ecosystem effectiveness. A team
member, agent, scripted persona, model simulation, or the product author cannot
substitute for a real participant.

## Entry gate

Do not recruit or schedule a participant until:

- TASK-289 has accepted clean-home and real second-Mac evidence for
  [AC-18](../phases/phase-1-outcome-prd.md#8-acceptance-criteria-and-current-evidence);
- TASK-297 and TASK-298 identify the exact owner-approved shared content and
  final published signed artifact used in the session;
- TASK-299 has approved post-fan-out entitlement, personal/shared, secret,
  symlink, lock, and ownership boundaries;
- the study owner has approved the recruitment text, consent form, data fields,
  compensation if any, retention schedule, observer, location, and stop/escalation
  contacts;
- the test account/device contains only synthetic task material and no other
  person's private workspace.

If any gate is absent, store `NOT RUN — PREREQUISITE MISSING`. Do not use an
internal rehearsal as evidence.

## Participant profile and recruitment

Recruit an adult who:

- is within the intended non-technical solution-creator audience;
- does not use a terminal or Git as part of ordinary work;
- did not build, test, administer, or author this ecosystem;
- is not expected to understand repositories, manifests, ranks, severity
  tokens, CLI commands, or model/runtime architecture;
- can voluntarily decline without employment, client, or relationship
  consequence.

Recruitment must state the purpose in plain language: testing the product, not
the person's competence. It must state what will be observed, what may be
recorded, the synthetic nature of the task, expected compensation, voluntary
participation, withdrawal rights, and whom to contact. Do not recruit through
a manager in a way that makes participation feel mandatory.

## Consent and privacy

Before the product is shown, obtain affirmative written consent for observation
and note-taking. Screen/audio/video recording is off by default and requires a
separate explicit choice. Withdrawal stops the session immediately; where
legally possible, delete that participant's unaggregated study data on request.

Use a random session ID. Keep name, contact information, consent, and payment
records outside Git and `tc` in an access-limited study record. The initiative
artifact may contain only the session ID, eligibility declaration, artifact
identities, redacted observations, rubric results, and participant quotations
that the participant explicitly approved.

Retention:

- optional raw screen/audio/video recording: access-limited and deleted within
  14 days after the redacted evidence is independently verified;
- contact/session mapping: deleted within 30 days after compensation and any
  withdrawal request are resolved;
- consent/payment record: retained only for the period required by the approved
  study policy; if no policy is approved, do not recruit;
- de-identified criterion evidence: retained with Initiative 06 provenance.

Never collect personal passwords, tokens, recovery codes, private notes,
client names, financial information, health information, unrelated screen
content, home paths, device serials, or repository identities. Pause capture
before the participant enters their own credentials. Run a value-suppressing
sensitive-content scan before evidence enters `tc` or Git.

## Representative task

Give the participant the final signed user-facing artifact and the ordinary
published instructions only. Use this synthetic brief without ecosystem
jargon:

> A fictional regional transportation team knows riders abandon support when
> travel plans change unexpectedly. You have a short packet of fictional rider
> comments and operating constraints. Use this tool to help the team decide
> what problem to solve, what kind of solution to explore, and what they should
> do next. Stop when you believe you have a decision brief you could share with
> the fictional team.

The packet must be the versioned synthetic EVAL-01 input approved through
TASK-284/285, with no private oracle, real company/client/person data, or
preselected feature. Record its digest. The participant owns the decisions;
the system must expose choices, evidence, unknowns, and next steps rather than
declare unreviewed user validation or a final answer on the team's behalf.

## Observer script

Read this introduction verbatim:

> Thank you for helping us test the product. We are testing the product, not
> you. The task and all people or organizations in it are fictional. Please
> work as you normally would and say what you expect or find confusing. I will
> not tell you where to click or how the system works. You may pause or stop at
> any time. Please do not enter personal or work-confidential information.

Then give the brief and ordinary instructions. The observer may use only these
neutral prompts:

- “What are you expecting to happen?”
- “What does that message mean to you?”
- “What would you do next?”
- “What makes you feel finished?”

The observer must not name a button, translate jargon, recommend a specialist,
suggest prompt wording, handle sign-in, open Terminal, edit a file, copy a
repository, resolve an error, or ask Pablo to intervene. If the participant
asks for help, reply once: “Please do what you would normally do if I were not
here.” If they still cannot continue, record the stopping point as product
evidence; do not coach around it.

After the participant stops, ask:

1. “In your own words, what did the system help you do?”
2. “What decision does the fictional team still own?”
3. “What evidence or unknowns would you check next?”
4. “Did the system ask you to do anything you did not understand or did not
   feel was yours to decide?”
5. “What would you expect to happen if the network or sign-in stopped working?”
6. “Would you know how to return to this work later? Show me, without changing
   the result.”

## Observation record

Use event notes, not interpretation alone. For each meaningful event record:

- pseudonymous session ID and timestamp;
- visible state or prompt in redacted plain language;
- participant action or verbatim approved short quotation;
- whether the action was independent, requested help, or stopped;
- linked screenshot/output/Task Copilot evidence identity where consented;
- criterion affected and observer rationale;
- any intervention. An intervention automatically prevents an independent-pass
  verdict for that step.

Record the exact application/runtime/content identities and the TASK-289
environment evidence. Preserve the complete journey and stopping point; do not
retain only successful moments or rerun because the first result is
unflattering.

## Success and comprehension rubric

Each row receives `DEMONSTRATED`, `PARTIAL`, `ABSENT`, or `VIOLATED`, with an
evidence link and rationale. There is no numeric score or average. A hard-gate
violation rejects the session.

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

AC-19 is supported only if every hard row is demonstrated, no prohibited
intervention occurred, the participant completed the representative task, and
independent QA accepts the redacted evidence. Partial comprehension is not a
pass. A successful internal expert session is not participant evidence.

## Stop conditions

Stop immediately if the participant withdraws or shows distress; personal,
client, credential, or unrelated data appears; the product requests terminal,
Git, hidden settings, administrator judgment, or another person's authority;
the observer would need to repair or coach; the artifact/content identity no
longer matches TASK-289; a false success state appears; an unexpected external
write is proposed; or a TASK-299 boundary concern emerges.

Seal a redacted record as `STOPPED`, `FAILED`, or `INVALID` with the exact
reason and responsible actor. Do not resume after repair in the same evidence
session. A new build or changed task packet requires new consent and a new
session ID.

## Claim boundary

A passing session supports only the bounded claim that this participant
completed this recorded task with these signed artifacts under this protocol.
It does not prove general usability, accessibility for every person,
organization-wide readiness, model quality, or the complete initiative
outcome. If no suitable participant is available, AC-19 remains pending; no
agent, author, colleague rehearsal, or simulated persona may replace the run.
