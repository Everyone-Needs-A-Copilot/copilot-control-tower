# ENAC Self-Onboarding Walkthrough Order

Open the HTML walkthroughs in the numbered order below. The sequence starts with
the end-user ecosystem and progressively narrows into setup recovery and project
aftercare before moving to the Admin experience.

| Order | Walkthrough | What to review |
|---:|---|---|
| 01 | [Ecosystem adoption — UX](01-ecosystem-adoption-uxd-walkthrough.html) | The service-level adoption sequence and preservation promise. |
| 02 | [Ecosystem adoption — UI](02-ecosystem-adoption-uids-walkthrough.html) | The visual treatment of the adoption sequence. |
| 03 | [User Setup feedback — UX](03-user-setup-feedback-uxd-walkthrough.html) | Corrected connections, projects, failure, completion, and Aviator flows. |
| 04 | [User Setup feedback — UI](04-user-setup-feedback-uids-walkthrough.html) | The corresponding high-fidelity User Setup treatment. |
| 05 | [Truthful setup and recovery — UX](05-truthful-setup-recovery-uxd-walkthrough.html) | The complete four-Copilot inventory and recovery model. |
| 06 | [Truthful setup and recovery — UI](06-truthful-setup-recovery-uids-walkthrough.html) | The high-fidelity setup, verification, and steady-state experience. |
| 07 | [Step 7 project triage and aftercare — UX](07-project-integration-aftercare-uxd-walkthrough.html) | Focused project categories, guided execution, exact couldn't-confirm evidence, and recovery. |
| 08 | [Step 7 project triage and aftercare — UI](08-project-integration-aftercare-uids-walkthrough.html) | The high-fidelity, one-category-at-a-time Step 7 experience grounded in the observed 53-project inventory. |
| 09 | [Bulk project migration — UX](09-bulk-project-migration-uxd-walkthrough.html) | One guarded review-and-apply route for the projects with proven automatic updates, plus honest held and tailored routes. |
| 10 | [Bulk project migration — UI](10-bulk-project-migration-uids-walkthrough.html) | The high-fidelity Step 7 cohort review, confirmation, progress, and result ledger. |
| 11 | [Completed setup topology — UX](11-completed-setup-topology-uxd-walkthrough.html) | Honest machine-versus-ecosystem readiness, four-tier component disclosures, and shared project aftercare. |
| 12 | [Completed setup topology — UI](12-completed-setup-topology-uids-walkthrough.html) | The high-fidelity completed home with Personal terminology and Step 7 category routes. |
| 13 | [Admin zero-terminal readiness — UX](13-admin-zero-terminal-uxd-walkthrough.html) | Automatic readiness checks and owner-correct recovery. |
| 14 | [Admin form placeholders — UI](14-admin-form-placeholders-uids-walkthrough.html) | Form guidance for organization and infrastructure values. |
| 15 | [Admin completion and departments — UX](15-admin-completion-departments-uxd-walkthrough.html) | Completion, department inventory, duplicate refusal, and addition. |
| 16 | [Admin completion and departments — UI](16-admin-completion-departments-uids-walkthrough.html) | The final high-fidelity Admin completion and department experience. |
| 17 | [The connect experience — UX](17-connect-experience-uxd-walkthrough.html) | Bob's journey to his team's shared keys under both credential models, the shipped dead ends they replace, and the one open fork. |
| 18 | [Self-service store provisioning — UX](18-self-service-provisioning-uxd-walkthrough.html) | Both actors of the design that makes 17's North Star receipt real: Bob's unchanged day one, and the administrator's one-time setup, mapping governance, audit, rotation, bootstrap, the Connect sheet that shipped as a bridge and is built to be deleted, and the eight owner rulings. |
| 19 | [Default project batch — UX](19-default-project-batch-uxd-walkthrough.html) | The owner-directed default-all flow, individual project fallback, consolidated Mac prerequisite, and quiet all-ready state. |
| 20 | [Default project batch — UI](20-default-project-batch-uids-walkthrough.html) | The native visual hierarchy for one selected batch, two explanatory counts, quiet acknowledgements, and project-only checkboxes. |
| 21 | [Resolve with Claude Code — UX](21-resolve-with-claude-code-uxd-walkthrough.html) | The one-button default-all preparation flow, assistant and permission recovery, owner decisions, protected work, exact review, apply, fresh verify, and rollback outcomes. |
| 22 | [Resolve with Claude Code — UI](22-resolve-with-claude-code-uids-walkthrough.html) | The Quiet Instrument visual treatment for visible assistant preparation, proposal triage, decisions, held work, exact plans, and evidence-bound receipts. |
| 23 | [Fleet-guided reconciliation — UX](23-fleet-guided-reconciliation-uxd-walkthrough.html) | The corrected one-session Sites-root handoff, durable instruction package, same-conversation questions, and independent fleet verification. |
| 24 | [Fleet-guided reconciliation — UI](24-fleet-guided-reconciliation-uids-walkthrough.html) | The native visual hierarchy for assistant choice, verified progress, owner questions, and the quiet completed state. |

Walkthroughs 17 and 18 read last as a pair, and not merely because they are newest. 17 poses the question — what Bob's connect experience should be, and the one fork left undecided — and 18 assumes the answer the owner ratified, rendering both actors of the mechanism that makes 17's receipt true along with what the security passes qualified about it. Both span the member's wizard and Admin governance, both still carry undecided items, and their user-side screens depend on the setup and completion model established by 01 to 12.

Walkthroughs 19 and 20 supersede the project-selection surface shown in 09 and
10. The exact-plan, transaction, and receipt safety model remains; only the
default decision and its presentation change.

Walkthroughs 21 and 22 extend 19 and 20 without weakening that default-all or
transaction model. Claude Code prepares bounded proposals in a visible session;
the person still resolves owner-only choices and Python remains the sole writer,
rollback authority, and fresh verifier.

Walkthroughs 23 and 24 supersede 21 and 22's content-free proposal-selection
experience. The assistant now receives one Python-authored instruction package
at the approved Sites root and works across the complete selected batch in one
conversation. Python remains the sole authority for scope and verified status;
the external assistant is the explicitly chosen writer for project-specific
guided work.

## Naming Convention

- Every viewable walkthrough uses `NN-<feature>-<stage>-walkthrough.html`.
- `NN` is a two-digit, contiguous viewing position within this directory.
- When both stages exist, the UXD walkthrough comes immediately before the UIDS
  walkthrough.
- Insert a new walkthrough where it belongs in the narrative, then renumber later
  walkthroughs and update references. Do not append it merely because it is new.
- Markdown specifications and analysis files remain unnumbered; their companion
  links point to the exact numbered HTML filename.
