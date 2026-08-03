//
// Copilot Control Tower — native first-run wizard (S2, the ONLY install path).
//
// A titled `NSWindow` (NavigationSplitView roadmap sidebar + StepShell content
// pane + pinned footer), opened on demand from the tray popover's "Set up"
// action and the tray's dev-only "Open Wizard (dev)" menu item — see
// `native/control-tower-tray.swift`'s `StatusBarController.openWizard()`.
// Reuses `scripts/publisher_setup.swift`'s roadmap-sidebar / StepShell grammar
// verbatim (same anatomy: eyebrow, title, intro, content region, footer with
// leading Back, trailing primary) so the two apps read as one family. Also
// reused, unmodified, by `native/admin.swift`/`native/admin-support.swift`
// (both are heavy `StepShell` consumers) — do not change `StepShell`'s public
// shape here without checking those files first.
//
// THE SPEC (verbatim copy source): `docs/09-prototypes/user-experience-walkthrough.html`,
// Arc 2 (screens 6-15, anchors #w1-#w10). Every title/intro/button/state
// string below is lifted from that file's Arc-2 sections; see each view's own
// comment for which `#wN` anchor it renders. No em-dashes anywhere, per the
// spec's own house style.
//
// REAL CLI SEAM (no longer mock-backed): every network-shaped step drives
// `CliClient` (`native/cli-client.swift`) directly —
//   - Connect GitHub (step 2): `authLoginInitiate()` / `authLoginPoll(deviceCode:)`
//   - Detect (step 3): `authStatus()` + `doctor()` + aggregate `onboard` plan
//   - Departments (step 5): `layers()` / `layersJoin(id:)`
//   - Your connections (step 6): `connections()` (task 221 bridge stage C).
//     Shows the GitHub connection established in step 2 plus the org's
//     declared roster, grouped by the CLI's own `secret_state` into "Ready
//     to use" / "Available to connect"; a `cc` build that predates this verb
//     (or any other read failure) degrades to the same honest empty state
//     this step always had, with a quiet update hint when that specific
//     shape is detected. It never advertises a provider the organization has
//     not made available, and never computes readiness itself.
//   - Set up (step 7): aggregate `onboard --apply` (+ `updateFanout()` when a
//     department was joined)
//   - Verify (step 8): `doctor()`
// `WizardModel` never spawns `Process` itself — it only calls `CliClient`,
// which owns that seam alone (invariant #1, "Parse, never compute").
//
// CRITICAL SwiftUI/AppKit ordering constraint (see `.claude/memory` and this
// same discipline in `control-tower-tray.swift` / `publisher_setup.swift`): no
// blocking `Process`/file I/O, and no `CliClient` call, may run during a
// SwiftUI `@State`/`@StateObject` `init()`. `WizardModel.init()` (the implicit
// memberwise default — there is no explicit `init()` body) is pure; every
// `CliClient` call below is scheduled from a user action or a view's
// `.task`/`.onAppear`, always via an unstructured `Task { await ... }`, never
// from a property initializer.

import AppKit
import SwiftUI

// MARK: - Wizard roadmap (9 rows: Welcome / Connect GitHub / Detect / What
// you're getting / Departments / Your connections / Your projects / Set up /
// Verify)
//
// `.projects` (adopt-and-project-setup spec, "Step 7 of 9: Your projects")
// is a REAL step with a real sidebar row, positioned immediately before Set
// up — never conditional on `includeCodex`, never skipped silently. Every
// stage after it shifted by one; every "Step N of 9" eyebrow in this file
// became "Step N of 10" in the same change.

enum WizardStage: Int, CaseIterable, Identifiable, Equatable {
    case welcome, connectGitHub, detect, whatYoureGetting, departments, integrations, projects, materialize, verify
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .connectGitHub: return "Connect GitHub"
        case .detect: return "Detect"
        case .whatYoureGetting: return "What you're getting"
        case .departments: return "Departments"
        case .integrations: return "Your connections"
        case .projects: return "Your projects"
        case .materialize: return "Set up"
        case .verify: return "Verify"
        }
    }
}

// MARK: - Step 2, Connect GitHub: device-flow state

enum DeviceFlowStatus: Equatable {
    case idle, pending, authorized, expired, denied
}

/// RENDER data only (invariant #6) — there is no field here a real
/// token/credential could ever occupy. `deviceCode` is itself not a secret
/// (it is the poll handle `AuthDeviceCode.deviceCode` names), never a token.
struct DeviceFlowState {
    var status: DeviceFlowStatus = .idle
    var userCode: String?
    var verificationUri: String?
    var deviceCode: String?
    var interval: Int = 5
}

// MARK: - §2.1.1, the organization question: field validation
//
// A closed, three-condition table (copy spec §3's own order — spaces first,
// then `@`, then everything else GitHub wouldn't accept), evaluated only once
// the field is non-empty, and only ever shown once `WizardModel.orgFieldTouched`
// is true (the same `orgSlugTouched` discipline `native/admin.swift`'s own
// organization field already uses, per the copy spec's own citation) — never
// while the first characters are being typed.
enum OrgFieldValidation: Equatable {
    case none
    case containsSpaces(suggestion: String)
    case containsAt
    case invalidCharacters
}

// MARK: - Holding H7, granting a missing GitHub permission: device-flow
// state (copy spec §2.9.3) — same shape as `DeviceFlowState` above, with
// explicit fail-closed identity/scope terminal states.

enum GrantFlowStatus: Equatable {
    case idle, pending, granted, denied, expired, identityMismatch
    case insufficientScope, timedOut, unavailable
}

/// RENDER data only, same discipline as `DeviceFlowState` — no field here a
/// real credential could ever occupy.
struct GrantFlowState {
    var status: GrantFlowStatus = .idle
    var userCode: String?
    var verificationUri: String?
    var deviceCode: String?
    var interval: Int = 5
}

// MARK: - Step 5, Departments: per-row join state

enum DepartmentJoinState: Equatable {
    case joined
    case availableToJoin
    case joining
    case waitingForNetwork
    /// Covers both "not entitled" (the walkthrough's IT row) and the quiet
    /// revoked-race outcome ("isn't available to you anymore") — both are
    /// the same honest, non-error "not available to you" family, just with
    /// different copy for the caption.
    case notAvailable(caption: String)
}

struct DepartmentRow: Identifiable, Equatable {
    let id: String
    let name: String
    var state: DepartmentJoinState
}

// MARK: - Step 7, Your projects (adopt-and-project-setup spec)

/// One row in the projects list (`cc workspace --all --json`'s
/// `WorkspaceEntry`, grouped for display). The wizard step uses checkboxes
/// (`canApplyNow` is always false here — the copilots a project's setup
/// would copy from do not exist on this Mac yet at step 7, per the spec's
/// own rejected-alternative note); the menu bar drill-in uses immediate
/// `Add` instead, because by then `canApplyNow` is true.
enum ProjectRowGroup: String {
    case canBeSetUp
    case needsFinishing
    case alreadySetUp
    case keptAsIs
}

/// Presentation-only navigation for the five CLI-authored project
/// classifications. The category never classifies a project; it only filters
/// rows whose `WorkspaceEntry.classification` already came from `cc`.
enum ProjectTriageCategory: String, CaseIterable, Identifiable {
    case ready
    case safeFinish
    case guidedSetup
    case ownerDecision
    case couldNotConfirm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: return "Ready"
        case .safeFinish: return "Can finish automatically"
        case .guidedSetup: return "Needs guided setup"
        case .ownerDecision: return "Needs the project owner"
        case .couldNotConfirm: return "Couldn't confirm"
        }
    }

    var shortMeaning: String {
        switch self {
        case .ready: return "No action needed"
        case .safeFinish: return "Review the exact additions first"
        case .guidedSetup: return "A coding assistant can complete these"
        case .ownerDecision: return "A named decision is required"
        case .couldNotConfirm: return "Review what could not be proven"
        }
    }

    var classification: WorkspaceIntegrationClassification {
        switch self {
        case .ready: return .ready
        case .safeFinish: return .safeFinish
        case .guidedSetup: return .guidedIntegration
        case .ownerDecision: return .ownerDecision
        case .couldNotConfirm: return .couldNotVerify
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "checkmark.circle"
        case .safeFinish: return "plus.circle"
        case .guidedSetup: return "arrow.right.circle"
        case .ownerDecision: return "person.crop.circle"
        case .couldNotConfirm: return "questionmark.circle"
        }
    }
}

/// Pure copy/filter helpers shared by the wizard, menu-bar aftercare, and
/// executable selftests. Every input fact is CLI-authored.
enum ProjectTriageRender {
    static let pageSize = 6

    static func workspaces(
        _ workspaces: [WorkspaceEntry],
        in category: ProjectTriageCategory
    ) -> [WorkspaceEntry] {
        workspaces.filter { $0.classification == category.classification }
    }

    static func nonEmptyCategories(
        _ workspaces: [WorkspaceEntry]
    ) -> [ProjectTriageCategory] {
        ProjectTriageCategory.allCases.filter {
            !self.workspaces(workspaces, in: $0).isEmpty
        }
    }

    static func summary(_ workspaces: [WorkspaceEntry]) -> String {
        var sentences: [String] = []
        let ready = self.workspaces(workspaces, in: .ready).count
        let safe = self.workspaces(workspaces, in: .safeFinish).count
        let guided = self.workspaces(workspaces, in: .guidedSetup).count
        let owner = self.workspaces(workspaces, in: .ownerDecision).count
        let unavailable = self.workspaces(workspaces, in: .couldNotConfirm).count

        if ready > 0 {
            sentences.append("\(ready) \(ready == 1 ? "is" : "are") ready.")
        }
        if safe > 0 {
            sentences.append("\(safe) can finish automatically.")
        }
        if guided > 0 {
            sentences.append("\(guided) \(guided == 1 ? "needs" : "need") guided setup.")
        }
        if owner > 0 {
            sentences.append("\(owner) \(owner == 1 ? "needs" : "need") the project owner.")
        }
        if unavailable > 0 {
            sentences.append("Control Tower couldn't confirm \(unavailable).")
        }
        return sentences.joined(separator: " ")
    }

    static func reason(_ workspace: WorkspaceEntry) -> String {
        switch workspace.classification {
        case .ready:
            return "Claude and Codex passed authoritative verification."
        case .safeFinish:
            return workspace.safeAction?.detail ?? workspace.detail
        case .guidedIntegration, .ownerDecision, .couldNotVerify:
            let componentReasons = workspace.components.flatMap { component in
                component.missingRequirements.map {
                    "\(component.component == .claude ? "Claude" : "Codex"): \($0.detail)"
                }
            }
            return componentReasons.first ?? workspace.detail
        }
    }

    static func diagnosticReport(_ workspace: WorkspaceEntry) -> String {
        var lines = [
            "\(workspace.name) project integration report",
            "",
            workspace.detail,
            "Nothing was changed by Control Tower.",
            "",
            "Capabilities: \(workspace.capabilities.instructions) instructions, "
                + "\(workspace.capabilities.agents) agents, "
                + "\(workspace.capabilities.skills) skills, "
                + "\(workspace.capabilities.commands) commands, "
                + "\(workspace.capabilities.plugins) plugins.",
        ]
        for component in workspace.components {
            lines.append("")
            lines.append(component.component == .claude ? "Claude" : "Codex")
            if component.missingRequirements.isEmpty {
                lines.append("- No missing requirement was reported.")
            } else {
                lines.append(contentsOf: component.missingRequirements.map { "- \($0.detail)" })
            }
            if let recognized = component.recognizedSetup {
                lines.append(contentsOf: recognized.evidence.map {
                    "- \($0.path): \($0.detail)"
                })
            }
        }
        if let command = workspace.components.first?.verification.command {
            lines.append("")
            lines.append("Check again after the project setup changes:")
            lines.append(command.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}

/// Drives Verify's completion projects card per the spec's four body
/// variants: set up (with or without a failure), skipped, or declined
/// (card absent). `.notReached` only ever describes a wizard session that
/// never got as far as Set up at all.
enum ProjectsStepOutcome: Equatable {
    case notReached
    case declined
    case skipped
    case setUp(succeeded: Int, total: Int)
}

// MARK: - The one named-subject spinner construction site (wizard + tray)
//
// Per the progress-and-waiting spec's own architecture rule
// (`docs/40-initiatives/02-enac-self-onboarding/walkthroughs/progress-and-waiting-spec.md`
// §2, "The animated indicator is only reachable from `alive`"): every
// spinner in this app's user-facing surfaces goes through here, and every
// one of them REQUIRES the name of the thing it is working on — an
// indicator with no named subject can never be built, and a `notStarted`
// row has no branch that reaches this initialiser at all. `native/admin.swift`
// keeps its own equivalent for the organization run (that file is owned by
// a different task); this one is scoped to `wizard.swift`/
// `control-tower-tray.swift`, the two files this task owns.
struct CTNamedWaitSpinner: View {
    let subject: String
    var controlSize: ControlSize = .small

    var body: some View {
        ProgressView()
            .controlSize(controlSize)
            .accessibilityLabel(subject)
    }
}

// MARK: - Step 8, Set up: honest progress from real CLI results, never a timer
//
// REPLACES the old `MaterializePhaseState`'s fabricated `label`/`index`/
// `total`, which was paced by `cyclePhases`' own `Task.sleep` AFTER the real
// call had already returned (the exact defect the progress-and-waiting spec
// was written to close — see that doc's §1 table row "Wizard: setting up
// your copilots"). Nothing below is ever set by a timer; every field is set
// only from a real `EcosystemOnboardReport`/`WorkspacesReport` result.

/// One row's state in a Set up checklist. `notStarted` and `working` are
/// separate, exhaustive cases — never a `Bool` — so a never-started row and
/// an in-flight one can never render the same way (spec §2, "the rule that
/// makes never-started unmistakable"). `working` carries the moment it
/// started, purely so a row could add its own "still working" caption after
/// a while; it never drives a fabricated position. Equality ignores that
/// timestamp (two `.working` rows are "the same state" for every purpose
/// this app has), which is what lets tests compare states without racing a
/// clock.
enum SetupRowState: Equatable {
    case notStarted
    case working(startedAt: Date)
    case done(detail: String)
    /// An optional capability was deliberately left for later. This is
    /// neither a success checkmark nor a failure: the rest of setup may
    /// continue while the row remains explicit.
    case deferred(detail: String)
    case couldNotFinish(detail: String)
    /// The run ended without the engine ever naming this row (spec, "Work
    /// ends": "Any row the run never mentioned reads Setup didn't say what
    /// happened here.") — reconciliation, never a guess at what happened.
    case neverReported

    static func == (lhs: SetupRowState, rhs: SetupRowState) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted), (.neverReported, .neverReported): return true
        case (.working, .working): return true
        case (.done(let a), .done(let b)): return a == b
        case (.deferred(let a), .deferred(let b)): return a == b
        case (.couldNotFinish(let a), .couldNotFinish(let b)): return a == b
        default: return false
        }
    }
}

struct SetupRow: Identifiable, Equatable {
    let id: String
    let title: String
    var state: SetupRowState = .notStarted
}

/// The whole Set up checklist: one call row with a nested stage disclosure,
/// plus one row per chosen project (spec §5). The nested disclosure only
/// ever resolves all at once, the moment the call returns — the CLI reports
/// nothing finer-grained than "still running" for it today (a real limit,
/// not a UI choice), so it stays a P2 list inside this P1 row rather than
/// pretending to fill in one stage at a time.
struct SetupProgressState: Equatable {
    /// `onboard.schema.json`'s `ecosystemStage.stage` enum's first six
    /// values, in the CLI's own order — `materialize`/`doctor` (the
    /// trailing pair) are Verify's (#w8) own concern, not shown here. Named
    /// in plain words per the spec's own copy (§5), never the raw stage id
    /// (the app's own hard rule: no stage ids, internal state names, or
    /// jargon in a user-facing string).
    static let namedStages: [(id: String, title: String)] = [
        ("organization-handoff", "Getting your organization's shared setup"),
        ("personal-packages", "Setting up your own copy on this Mac"),
        ("device-ssh", "Giving this Mac its own key"),
        ("layer-manifest", "Writing down which copilots you get"),
        ("secret-store", "Connecting your organization's shared store"),
        ("codex-plugin", "Adding Codex Copilot"),
    ]

    var callRow = SetupRow(id: "call", title: "Your copilots on this Mac")
    var stageRows: [SetupRow] = SetupProgressState.namedStages.map { SetupRow(id: $0.id, title: $0.title) }
    var projectRows: [SetupRow] = []
    /// Set only once `updateFanout()` is actually fired (a department was
    /// joined this session) — never shown otherwise, since the sentence
    /// would promise something that isn't happening.
    var isFanningOut = false

    /// A fixed, real denominator across the call, its named CLI-reported
    /// stages, and approved projects. The numerator counts terminal reports,
    /// not elapsed time and not only successes: a deferred, failed, or
    /// unreported row is still an honest outcome. The six stage rows exist
    /// before the call starts, so the denominator never changes mid-run.
    var countLine: String? {
        let rows = [callRow] + stageRows + projectRows
        let reported = rows.filter {
            switch $0.state {
            case .done, .deferred, .couldNotFinish, .neverReported:
                return true
            case .notStarted, .working:
                return false
            }
        }.count
        return "\(reported) of \(rows.count) outcomes reported."
    }
}

// MARK: - Holding (#w10) — first-class, never a dead end, never adds its own
// sidebar row (`origin` is the stage it renders inline over).
//
// SEVEN variants (copy spec `control-tower-copy-deck.md` §2.9, replacing the
// old single "SETUP IS HOLDING" screen), chosen by WHO OWNS THE FIX, never by
// what went wrong (invariant #5):
//   H1 notInstalled  — the CLI isn't on this Mac at all (whoever installs software)
//   H2 unreadable    — a genuine CliError with no CLI-authored diagnosis (nobody; retry)
//   H3 fault         — a CLI stage blocked and did NOT classify it as held-for-you (nobody; retry)
//   H4 yours         — a CLI stage blocked AND classified it as held-for-you (the user; a decision)
//   H5 waiting[Offline|Busy] — offline, or another `cc` run holds the lock (nobody; wait)
//   H6 waitingOnOrg  — the org's own setup isn't finished (IT, via the user as courier)
//   H7 needsPermission — a GitHub permission only the user can grant is missing
//                        (the user; a real fix, not a decision — copy spec Appendix D.2/§3.2)
enum HoldingVariant: Hashable {
    case notInstalled
    case unreadable
    case fault
    case yours
    case waitingOffline
    case waitingBusy
    case waitingOnOrg
    case needsPermission

    /// `StepShell.headerTint` token per the taxonomy table (§1). H4 uses the
    /// shell's own default (`CTColor.state(.actionable)`) rather than
    /// repeating it here, so there is exactly one place ("no ramp color")
    /// that decides that value. H7 is `signed-out` blue (copy spec §3.2:
    /// "Actionable-by-you, informational blue, not alarm" — the same
    /// non-alarm blue as H4, reusing the shell's default rather than a new
    /// token). Values are the appearance-corrected ramp (`CTColor.state(_:)`,
    /// spec §2.3/P1-5) rather than the raw system colours these used to be —
    /// text drawn straight from `.systemRed`/`.systemOrange` measures 3.57:1
    /// / 2.31:1 on the light page, under this product's own 4.5:1 floor (G-5).
    var tint: Color {
        switch self {
        case .notInstalled, .waitingOffline, .waitingBusy, .waitingOnOrg:
            return CTColor.state(.neutral)
        case .unreadable: return CTColor.state(.blocked)
        case .fault: return CTColor.state(.attention)
        case .yours, .needsPermission: return CTColor.state(.actionable)
        }
    }

    /// The taxonomy table's "Mark" column, reusing the SAME closed
    /// `BadgeState` vocabulary the tray/popover already draw (`GlyphView`,
    /// `native/control-tower-tray.swift`) — hollow ring / filled circle+! /
    /// filled triangle / none / clock / wrench map exactly onto
    /// `.hollow`/`.bang`/`.triangle`/`.none`/`.clock`/`.wrench`. Purely
    /// decorative (§7 VoiceOver note: "the eyebrow carries the meaning in
    /// text"), never the only signal. H7 is `.key` — the SAME token the
    /// tray already uses for "signed-out" (S5's badge=key), and literally
    /// the subject of this screen (copy spec §3.2).
    var badge: BadgeState {
        switch self {
        case .notInstalled: return .hollow
        case .unreadable: return .bang
        case .fault: return .triangle
        case .yours: return .none
        case .waitingOffline, .waitingBusy: return .clock
        case .waitingOnOrg: return .wrench
        case .needsPermission: return .key
        }
    }
}

/// The "same variant and the same reason" identity a repeat hold is compared
/// against (§4's `Try again`/`Check again` row: "If it holds again with the
/// same variant and the same reason... Show that line only from the second
/// consecutive identical hold onward"). Deliberately excludes `recordedAt`
/// (`HoldingSupportInfo` below) and every render-only field — this is
/// identity, not display.
struct HoldingSignature: Hashable {
    let variant: HoldingVariant
    let origin: WizardStage
    let stage: String?
    let code: String?
    let message: String?
}

/// "Details for support" (§5) — one optional Swift property per optional
/// printed line, so a value this app never had (e.g. no `code` on a
/// stage-driven hold, no `schemaVersion` on an exit-2 failure) is omitted
/// from the block entirely rather than printed as a fabricated placeholder
/// (§5's own rule: "Never print `unknown`... A missing line is honest").
/// `nil` on `HoldingInfo.support` itself (not this type) means H1/H5, which
/// get no disclosure at all (§5: "four surfaces (H2, H3, H4, H6)").
struct HoldingSupportInfo: Equatable {
    let schemaVersion: String?
    let stage: String?
    let result: String?
    let code: String?
    let message: String?
    let recordedAt: Date

    /// Ignores `recordedAt` on purpose — see `HoldingSignature`'s doc.
    static func == (lhs: HoldingSupportInfo, rhs: HoldingSupportInfo) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion && lhs.stage == rhs.stage && lhs.result == rhs.result
            && lhs.code == rhs.code && lhs.message == rhs.message
    }
}

struct HoldingInfo {
    let variant: HoldingVariant
    let origin: WizardStage
    let eyebrow: String
    let title: String
    let intro: String
    /// The CLI's own stage `detail`, shown inline under "What setup found:"
    /// — set ONLY for the §3 gates the spec marks "frame" (`personal-packages`,
    /// `layer-manifest`'s review case) AND only once it passes §2.2 rule 3's
    /// presentability test (`HoldingInfo.isPresentable`). Every other gate's
    /// detail reaches the screen only via `support.message` (§3.1 "replace"),
    /// never here — see §2.2 rule 4, "never interpolated, never a headline".
    let framedDetail: String?
    /// H4's "What I left alone" card rows — captured at hold-entry time from
    /// the SAME report that triggered this hold, never re-read from
    /// `model.ecosystemInventory` later, so a subsequent mutation of that
    /// published property can never change what this card already showed.
    let reviewItems: [EcosystemInventoryItem]
    let support: HoldingSupportInfo?
    /// The full `stages` array from the SAME report that triggered this
    /// hold — captured the same way `reviewItems` above is, at hold-entry
    /// time, never re-read later. Populated ONLY by H4 (`holdingInfo(forBlockedOnboard:)`'s
    /// H4 branches), the one variant whose `Keep what I have` confirmation
    /// swap (§2.10) needs it, for the two honest-incompletion capability
    /// cards; empty for every other variant, which never reach that swap.
    var stages: [EcosystemOnboardStage] = []
    var isRepeat = false
    /// H7 ONLY, and only its self-serve flavor (§2.9's own owner test: "the
    /// fix is yours, it is a real fix and not a decision, and you can do it
    /// right here" — true here even though the mechanism is a terminal
    /// command this Mac's own admin can run, rather than a GitHub permission
    /// grant device flow). Set ONLY by `h7ForOrgSignIn(...)`, and only once
    /// BOTH `LocalAdminSignal.standupBriefExists` and
    /// `LocalAdminSignal.standupGitHubAppClientID` are true (never a
    /// placeholder to fill in by hand) — `nil` for the existing
    /// GitHub-permission H7, which keeps its own device-flow sheet.
    var selfServeCommand: String? = nil
    /// Set ONLY when this hold was reached as the direct consequence of an
    /// organization name the person (or this Mac's own silent admin-standup
    /// retry) just supplied to `auth login --org` (copy spec §2.1.1/§5) —
    /// never for a `no-company-app` reached any other way (e.g. a Mac whose
    /// organization pointer was already configured before this session
    /// started). Non-nil here is exactly what reveals `Use a different
    /// organization` (H6/H7-self-serve's own leading action, §2.9's Diff 3)
    /// and gives it the value to return to the field with.
    var orgNameForReturn: String? = nil
    /// Task 210/G-7: true (the default, and every non-onboard hold's only
    /// value — H1/H2/H4/H5/H6/H7 never override it) unless a blocked
    /// ecosystem report's own parsed facts say otherwise — `resume.safe_to_rerun`
    /// combined with the blocked stage's own row `action`/`sync_state`
    /// (`WizardModel.holdingInfo(forBlockedOnboard:)`). A Git-history
    /// review row (ahead/diverged/diverged-identical/local-changes/
    /// wrong-origin/unreadable) is never retryable regardless of
    /// `safe_to_rerun` — that field answers "is retrying safe", never "will
    /// retrying help" — so ONLY that classifier sets this `false`. Never
    /// derived from prose/string-matching (parse-never-compute).
    var retryable = true
    /// Task 211/G-4b: the SAME `completed_actions` ledger from the report
    /// that triggered this hold, captured once at hold-entry time (same
    /// discipline as `stages`/`reviewItems` above). A "nothing was changed"
    /// claim may render only when this is empty; see `HoldingInfo.hasCompletedWork`.
    var completedActions: [CompletedAction] = []
    /// Task 211/G-4b: the SAME `resume` hint, when the triggering report
    /// carried one (only ever present on a `blocked` result). Its `detail`
    /// is the safe-next-step line rendered alongside a non-empty ledger.
    var resume: ResumeHint? = nil

    var hasCompletedWork: Bool { !completedActions.isEmpty }

    var signature: HoldingSignature {
        HoldingSignature(variant: variant, origin: origin, stage: support?.stage, code: support?.code, message: support?.message)
    }
}

// MARK: - HoldingInfo construction (copy spec §1/§2/§5) — one pure factory
// per variant, all app-authored copy, EVERY string below shipped verbatim
// from `holding-copy-spec.md`. No fragment assembly (§7): the two
// conditional appends the spec allows (codex-plugin's trailing clause,
// materialize's held-count sentence) are built as their own complete
// strings by their call sites, never concatenated here.
extension HoldingInfo {
    /// §2.2 rule 3's presentability test — the CLI's own string is shown
    /// inline ONLY if it passes every one of these; otherwise it still
    /// reaches the support block (rule 5), just never the screen body.
    static func isPresentable(_ text: String) -> Bool {
        guard text.count <= 200, !text.contains("\n") else { return false }
        let forbiddenCharacters: Set<Character> = ["{", "}", "<", ">"]
        guard !text.contains(where: forbiddenCharacters.contains) else { return false }
        let forbiddenSubstrings = ["Traceback", "Error:", "Exception", "/Users/", ".py:"]
        return !forbiddenSubstrings.contains { text.contains($0) }
    }

    /// "Copilot Control Tower <version> (<build>)" — §5's first line, from
    /// this app's own `Info.plist`. `nil` (never a fabricated placeholder)
    /// when either key is missing, e.g. an unbundled dev/selftest binary.
    private static var appIdentityLine: String? {
        let info = Bundle.main.infoDictionary
        guard let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String),
              let version = info?["CFBundleShortVersionString"] as? String,
              let build = info?["CFBundleVersion"] as? String
        else { return nil }
        return "\(name) \(version) (\(build))"
    }

    private static func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// §5's exact block shape, one label per line, omitting any line this
    /// app cannot fill (never `unknown`/`nil`/`n/a`) — and never a bare
    /// label with nothing after it (never a dangling `Message: `), so a
    /// field the CLI sends as `""` (or all whitespace) is treated the same
    /// as a field it omitted. Matches the `!engineDetail.isEmpty` discipline
    /// already used by `couldNotFinishStageText` above, plus a trim so a
    /// whitespace-only value doesn't slip past a bare `isEmpty` check.
    static func supportLines(_ support: HoldingSupportInfo) -> [String] {
        // Presence test only — trims to catch whitespace-only values, but the
        // ORIGINAL (untrimmed) value is what's printed, so `Message:` stays
        // verbatim per §5 (`<CLI message, verbatim, uncapped>`).
        func hasContent(_ value: String?) -> Bool {
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var lines: [String] = []
        if let appIdentityLine { lines.append(appIdentityLine) }
        if let cliPath = CliLocator.locate()?.path { lines.append("Setup helper: \(cliPath)") }
        if let schemaVersion = support.schemaVersion, hasContent(schemaVersion) { lines.append("Report format: \(schemaVersion)") }
        if let stage = support.stage, hasContent(stage) { lines.append("Step: \(stage)") }
        if let result = support.result, hasContent(result) { lines.append("Result: \(result)") }
        if let code = support.code, hasContent(code) { lines.append("Code: \(code)") }
        if let message = support.message, hasContent(message) { lines.append("Message: \(message)") }
        lines.append("Recorded: \(formattedTimestamp(support.recordedAt))")
        return lines
    }

    // MARK: H1 — not installed

    static func h1(origin: WizardStage) -> HoldingInfo {
        HoldingInfo(
            variant: .notInstalled,
            origin: origin,
            eyebrow: "ONE MORE PIECE TO INSTALL",
            title: "The setup helper isn't installed yet",
            intro: "Control Tower works by reading a small helper on this Mac, and it isn't here yet. Installing it takes one step, and then I can pick up where I left off.",
            framedDetail: nil,
            reviewItems: [],
            support: nil
        )
    }

    // MARK: H2 — can't read your setup

    static func h2(origin: WizardStage, intro: String, code: String? = nil, message: String? = nil) -> HoldingInfo {
        HoldingInfo(
            variant: .unreadable,
            origin: origin,
            eyebrow: "SETUP PAUSED",
            title: "I can't read your setup, so I've paused",
            intro: intro,
            framedDetail: nil,
            reviewItems: [],
            support: HoldingSupportInfo(schemaVersion: nil, stage: nil, result: nil, code: code, message: message, recordedAt: Date())
        )
    }

    // MARK: H3 — couldn't finish a part of setup

    static func h3(
        origin: WizardStage,
        title: String = "I couldn't finish one part of setup",
        intro: String,
        framedDetail: String? = nil,
        schemaVersion: String? = nil,
        stage: String? = nil,
        result: String? = nil,
        message: String? = nil,
        retryable: Bool = true,
        completedActions: [CompletedAction] = [],
        resume: ResumeHint? = nil
    ) -> HoldingInfo {
        HoldingInfo(
            variant: .fault,
            origin: origin,
            eyebrow: "SETUP PAUSED",
            title: title,
            intro: intro,
            framedDetail: framedDetail,
            reviewItems: [],
            support: HoldingSupportInfo(schemaVersion: schemaVersion, stage: stage, result: result, code: nil, message: message, recordedAt: Date()),
            retryable: retryable,
            completedActions: completedActions,
            resume: resume
        )
    }

    // MARK: H4 — something here is already yours

    static func h4(
        origin: WizardStage,
        intro: String,
        framedDetail: String? = nil,
        reviewItems: [EcosystemInventoryItem],
        stages: [EcosystemOnboardStage] = [],
        schemaVersion: String? = nil,
        stage: String? = nil,
        result: String? = nil,
        message: String? = nil,
        completedActions: [CompletedAction] = [],
        resume: ResumeHint? = nil
    ) -> HoldingInfo {
        HoldingInfo(
            variant: .yours,
            origin: origin,
            eyebrow: "ONE THING TO DECIDE",
            title: "Something here is already yours",
            intro: intro,
            framedDetail: framedDetail,
            reviewItems: reviewItems,
            support: HoldingSupportInfo(schemaVersion: schemaVersion, stage: stage, result: result, code: nil, message: message, recordedAt: Date()),
            stages: stages,
            completedActions: completedActions,
            resume: resume
        )
    }

    // MARK: H5 — waiting (offline / busy)

    static func h5Offline(origin: WizardStage) -> HoldingInfo {
        HoldingInfo(
            variant: .waitingOffline,
            origin: origin,
            eyebrow: "WAITING FOR THE NETWORK",
            title: "I'll pick this up when you're back online",
            intro: "I can't reach the network right now, so I've paused. Nothing was changed, and I'll carry on as soon as you're back.",
            framedDetail: nil,
            reviewItems: [],
            support: nil
        )
    }

    static func h5Busy(origin: WizardStage) -> HoldingInfo {
        HoldingInfo(
            variant: .waitingBusy,
            origin: origin,
            eyebrow: "WAITING FOR THE NETWORK",
            title: "Something else is updating right now",
            intro: "Your setup is already being updated by something else, so I stepped back rather than get in the way.",
            framedDetail: nil,
            reviewItems: [],
            support: nil
        )
    }

    // MARK: H6 — waiting on your organization

    static func h6(origin: WizardStage, intro: String, code: String? = nil, stage: String? = nil, result: String? = nil, message: String? = nil) -> HoldingInfo {
        HoldingInfo(
            variant: .waitingOnOrg,
            origin: origin,
            eyebrow: "WAITING ON YOUR ORGANIZATION",
            title: "Your organization has a bit left to set up",
            intro: intro,
            framedDetail: nil,
            reviewItems: [],
            support: HoldingSupportInfo(schemaVersion: nil, stage: stage, result: result, code: code, message: message, recordedAt: Date())
        )
    }

    // MARK: H7 — something only you can do (a missing GitHub permission)

    static func h7(origin: WizardStage, schemaVersion: String? = nil, stage: String? = nil, result: String? = nil, message: String? = nil) -> HoldingInfo {
        HoldingInfo(
            variant: .needsPermission,
            origin: origin,
            eyebrow: "ONE THING ONLY YOU CAN DO",
            title: "Setup needs one permission from you",
            intro: "Setup gives this Mac its own key so it can reach GitHub safely. Adding that key needs a permission GitHub hasn't been asked for yet, and you're the only one who can give it.",
            framedDetail: nil,
            reviewItems: [],
            support: HoldingSupportInfo(schemaVersion: schemaVersion, stage: stage, result: result, code: nil, message: message, recordedAt: Date())
        )
    }

    // MARK: H7 (self-serve variant) — the org's own sign-in ID, not yet
    // given to this Mac

    /// The exact, already-verified fix for the `no-company-app` cause, ONLY
    /// when THIS Mac's own admin standup already wrote its non-secret brief
    /// here (`LocalAdminSignal.standupBriefExists`) AND that same brief
    /// names the org's GitHub App client id
    /// (`LocalAdminSignal.standupGitHubAppClientID`) — never a guess, never
    /// a placeholder to fill in by hand. `nil` when either fact isn't
    /// available, in which case the caller stays on the ordinary H6 (see
    /// `holdingInfo(forExit2Code:)`'s `no-company-app` branch): never claim
    /// a fix the app hasn't actually verified.
    nonisolated static func selfServeOrgSignInCommand() -> String? {
        guard LocalAdminSignal.standupBriefExists,
              let clientID = LocalAdminSignal.standupGitHubAppClientID
        else { return nil }
        return "cc config set github_app.client_id \(clientID)"
    }

    /// Reuses H7's variant identity (eyebrow, blue tint, `.key` badge) per
    /// §2.9's own owner test — "the fix is yours, it is a real fix and not a
    /// decision, and you can do it right here" is exactly as true of a
    /// terminal command this Mac's own admin can run as it is of a GitHub
    /// permission grant — rather than inventing an eighth variant. Never
    /// constructed directly by a call site: only reached through
    /// `selfServeOrgSignInCommand()` returning non-nil, so `command` is
    /// always the real, local, already-verified value.
    static func h7ForOrgSignIn(origin: WizardStage, command: String, code: String? = nil, message: String? = nil) -> HoldingInfo {
        HoldingInfo(
            variant: .needsPermission,
            origin: origin,
            eyebrow: "ONE THING ONLY YOU CAN DO",
            title: "Setup needs your organization's sign-in ID",
            intro: "Your organization hasn't finished setting up sign-in yet. I can see this Mac already set up your organization, so this one's yours to finish: your organization's sign-in already has its own ID, and this Mac just hasn't been given it.",
            framedDetail: nil,
            reviewItems: [],
            support: HoldingSupportInfo(schemaVersion: nil, stage: nil, result: nil, code: code, message: message, recordedAt: Date()),
            selfServeCommand: command
        )
    }
}

// MARK: - The wizard's own phase state machine

enum WizardPhase {
    case welcome
    case connectGitHub
    /// The organization question (copy spec §2.1.1), inline over Connect
    /// GitHub — same no-sidebar-row/no-step-number mechanism `.onboardQuestion`
    /// already uses over Detect. Entered when `cc auth login --json` returns
    /// `org-required` and this Mac's own admin standup brief either has no
    /// readable organization name or has already been tried silently and
    /// failed this session (`WizardModel.handleOrgRequired`).
    case orgQuestion
    case detecting
    /// The re-plan after a "One question first" decision (`Include what I
    /// have` / `Not now`) — same origin stage (`.detect`) as `.detecting`,
    /// distinct only so the progress card can show the spec's own
    /// "Checking what that means…" copy instead of Detect's first-visit
    /// "Checking what's already here…".
    case replanningAfterDecision
    case detected
    /// Inline over Detect, per the spec's "Architecture decision": built
    /// from the same `StepShell`/no-sidebar-row mechanism Holding already
    /// uses, entered only when the CLI's plan carries at least one
    /// adoptable ("ask") personal-space item.
    case onboardQuestion
    case whatYoureGetting
    case departments
    case integrations
    case projects
    case materializing
    case verifying
    case verified
    case holding(HoldingInfo)
}

// MARK: - Wizard model

/// Pure state + real `CliClient` transitions. `init()` is the implicit
/// memberwise default (every `@Published` property below has a literal
/// default) — nothing here runs I/O at initialization time, so it is safe to
/// instantiate from `WizardWindowController`'s own `init` (itself invoked
/// lazily, off the SwiftUI attribute graph, from an AppKit action — see that
/// class below).
@MainActor
final class WizardModel: ObservableObject {
    @Published var phase: WizardPhase = .welcome
    @Published var deviceFlow = DeviceFlowState()
    @Published var authorizedLogin: String?

    // MARK: §2.1.1, the organization question

    /// The field's current value — already paste-normalized (`orgNameInputChanged()`)
    /// by the time anything else reads it. Prefilled with this Mac's own
    /// standup-brief organization name when `handleOrgRequired()`'s silent
    /// retry is attempted, so a failure lands on the screen with it already
    /// in place (copy spec §2.1.1's second intro variant).
    @Published var orgNameInput = ""
    /// Same discipline as `native/admin.swift`'s `orgSlugTouched` — set the
    /// moment the field is edited, and it's what gates `orgFieldValidation`
    /// from showing anything while the field is still empty.
    @Published var orgFieldTouched = false
    /// True only while `Continue to sign in`'s own `auth login` call is in
    /// flight — guards against a double submit, nothing more (the screen
    /// itself never renders a spinner over the field; the person just sees
    /// the ordinary Connect GitHub code card the moment it resolves).
    @Published var orgQuestionSubmitting = false
    /// The exact value that most recently came back `org-not-found` from the
    /// CLI, or `nil`. Compared against `orgNameInput` live (`orgNotFoundMessage`)
    /// rather than cleared explicitly, so editing the field away from the
    /// failed value silently retires the message — the same "never explain a
    /// value the person didn't just try" rule the intro variant follows.
    private var orgNotFoundAttempt: String?
    /// The standup-brief organization name `handleOrgRequired()` tried
    /// silently, or `nil` if no silent attempt has happened this session.
    /// Compared against `orgNameInput` live (`orgQuestionIntro`,
    /// `useADifferentOrganization()`'s return-variant choice) rather than a
    /// separate frozen flag, so editing the prefilled value away from what
    /// was tried reverts the screen to its first intro variant, exactly as
    /// the copy spec requires ("the screen never has to explain a value the
    /// person did not type").
    private var silentlyTriedOrgName: String?
    /// Guards the silent standup-brief retry to once per session
    /// (`handleOrgRequired()`) — a second `org-required` this session (e.g.
    /// after `Use a different organization`) always asks instead of retrying
    /// the same brief value again.
    private var orgSilentAttemptTriedThisSession = false
    /// Whatever organization `beginDeviceFlow(org:)` was last called with —
    /// `nil` on the very first attempt. `beginDeviceFlow()`'s public, no-arg
    /// form (used by `getStarted()` and every Holding "Try again"/"Check
    /// again" whose origin is Connect GitHub) replays this exact value, so a
    /// retry re-asks the SAME organization rather than silently reverting to
    /// none.
    private var lastAttemptedOrg: String?

    var orgFieldValidation: OrgFieldValidation {
        guard orgFieldTouched, !orgNameInput.isEmpty else { return .none }
        return Self.validateOrgInput(orgNameInput)
    }

    var canContinueToSignIn: Bool {
        !orgNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var orgQuestionIntro: String {
        let constant = "Your organization sets up its own sign-in, so I need to know which one to ask. "
        if let silentlyTriedOrgName, orgNameInput == silentlyTriedOrgName {
            return constant + "This Mac already set up \(silentlyTriedOrgName), so I tried that first."
        }
        return constant + "You'll find its name on the page you downloaded Control Tower from, and in the email that sent you there."
    }

    var orgNotFoundMessage: String? {
        guard let orgNotFoundAttempt, orgNotFoundAttempt == orgNameInput else { return nil }
        return "I couldn't find \(orgNotFoundAttempt) on GitHub. It may be spelled differently there, and whoever looks after your Mac will know."
    }

    /// The field's own live paste-normalization (copy spec §2.1.1: a full
    /// GitHub address rewrites in place to the bare organization name, with
    /// no message — the rewrite is its own feedback). Called from the
    /// view's `onChange`, never from a `Binding` transform, so the touched
    /// flag and the normalization stay in one place.
    func orgNameInputChanged() {
        orgFieldTouched = true
        let normalized = Self.normalizedOrgInput(orgNameInput)
        if normalized != orgNameInput {
            orgNameInput = normalized
        }
    }

    /// The spaces-validation fix button, `Use <suggestion>` — fills the
    /// field with the transformed value and leaves it touched (it already
    /// was, to have reached this button at all).
    func applyOrgSpacesFix(_ suggestion: String) {
        orgNameInput = suggestion
        orgFieldTouched = true
    }

    /// `Continue to sign in` (copy spec §2.1.1's action table). Local
    /// validation runs first and blocks the call entirely when it fails —
    /// the CLI is never asked to resolve a value this screen's own rules
    /// already know GitHub would refuse.
    func continueToSignInFromOrgQuestion() {
        orgFieldTouched = true
        guard Self.validateOrgInput(orgNameInput) == .none else { return }
        guard !orgQuestionSubmitting else { return }
        orgQuestionSubmitting = true
        beginDeviceFlow(org: orgNameInput)
    }

    /// H6/H7-self-serve's `Use a different organization` (copy spec §5's
    /// "escape from H6"): returns to the field, pre-populated with the exact
    /// value that led to this hold, spending nothing (nothing was ever
    /// persisted for a `no-company-app` hold) so the correction costs one
    /// keystroke.
    func useADifferentOrganization() {
        guard case .holding(let info) = phase, let orgName = info.orgNameForReturn else { return }
        orgNameInput = orgName
        orgFieldTouched = false
        orgNotFoundAttempt = nil
        phase = .orgQuestion
    }

    /// Pure: GitHub's real organization-name rule. Mirrors
    /// `AdminSlug.isValidGitHubOrgName` (`native/admin.swift`) exactly, but
    /// duplicated rather than shared — that file is Admin-only
    /// (`scripts/build-admin.command`) and this one must also compile into
    /// the User build (`scripts/build-user.command`). Any change to GitHub's
    /// org-name rule must be made in BOTH places.
    nonisolated static func isValidGitHubOrgName(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 39 else { return false }
        let chars = Array(value)
        var previousWasHyphen = false
        for (index, ch) in chars.enumerated() {
            if ch == "-" {
                if index == 0 || index == chars.count - 1 || previousWasHyphen { return false }
                previousWasHyphen = true
                continue
            }
            let isAsciiLetter = ch.isASCII && ch.isLetter
            let isAsciiDigit = ch.isASCII && ch.isNumber
            guard isAsciiLetter || isAsciiDigit else { return false }
            previousWasHyphen = false
        }
        return true
    }

    /// Pure: the closed three-condition validation table (copy spec §3), in
    /// its own stated priority order — spaces before `@` before "anything
    /// else GitHub wouldn't accept", so a value with more than one problem
    /// shows exactly the one the spec puts first.
    nonisolated static func validateOrgInput(_ raw: String) -> OrgFieldValidation {
        guard !raw.isEmpty else { return .none }
        if raw.contains(" ") {
            return .containsSpaces(suggestion: dashedSuggestion(raw))
        }
        if raw.contains("@") { return .containsAt }
        if !isValidGitHubOrgName(raw) { return .invalidCharacters }
        return .none
    }

    /// Pure: "runs of spaces turned into single dashes" (copy spec §3's own
    /// dynamic pattern) — `Acme Corporation` -> `Acme-Corporation`, `Acme
    /// Co` (a run of three spaces) -> `Acme-Co`. Every other character is
    /// left exactly as typed; this transform touches spaces only.
    nonisolated static func dashedSuggestion(_ raw: String) -> String {
        raw.split(separator: " ").joined(separator: "-")
    }

    /// Pure: the paste-normalization rewrite (copy spec §2.1.1) —
    /// `https://github.com/Acme-Co`, `github.com/Acme-Co/copilot-bootstrap`,
    /// and `github.com/orgs/Acme-Co/repositories` all reduce to `Acme-Co`.
    /// Text this can't reduce (including a plain, already-bare name) is
    /// returned exactly as given — "left alone for validation to answer",
    /// never silently discarded.
    nonisolated static func normalizedOrgInput(_ raw: String) -> String {
        var working = raw
        if let schemeRange = working.range(of: "://") {
            working = String(working[schemeRange.upperBound...])
        }
        guard working.lowercased().hasPrefix("github.com/") else { return raw }
        var path = String(working.dropFirst("github.com/".count))
        if path.lowercased().hasPrefix("orgs/") {
            path = String(path.dropFirst("orgs/".count))
        }
        guard let firstSegment = path.split(separator: "/").first, !firstSegment.isEmpty else { return raw }
        return String(firstSegment)
    }

    @Published var detectLines: [String] = []
    @Published var detectedCopilotState: RenderState?
    @Published var verifiedCopilotState: RenderState?
    @Published var verifiedWorkspacesReport: WorkspacesReport?
    @Published var ecosystemInventory: [EcosystemInventoryItem] = []
    @Published var ecosystemInventorySummary: EcosystemInventorySummary?
    @Published var ecosystemLayers: [EcosystemOnboardLayer] = []
    @Published var copilotRepositoryRoot: String?
    @Published var adoptionRollbackPaths: [String] = []
    @Published var includeCodex = true
    @Published var departments: [DepartmentRow] = []
    /// Step 6, "Your connections" (task 221 bridge stage C) -- the GitHub
    /// card always renders regardless of this state; this drives only the
    /// "Ready to use" org rows and the "Available to connect" card.
    @Published var connectionsState: ConnectionsLoadState = .waiting
    @Published var setupProgress = SetupProgressState()
    @Published var workspaceFolderName: String?
    /// The last successful ecosystem `--apply` report's own `result`/`stages`
    /// — copy spec §2.10's completion rule reads these at Verify time
    /// (conditions 1-3), never a second/re-derived reading. Set ONLY by
    /// `beginMaterialize()`'s success branch; `nil`/empty means Verify was
    /// somehow reached without a prior successful apply, which the
    /// completion rule treats as failing (never assumed passing).
    @Published var lastOnboardResult: OnboardResult?
    @Published var lastOnboardStages: [EcosystemOnboardStage] = []
    /// Task 211/G-4b: the SAME report's `completed_actions`/`resume`, kept
    /// alongside `lastOnboardStages` for the one Verify-reached "here's
    /// where that leaves you" screen that has no `HoldingInfo` of its own to
    /// carry them (`WizardView`'s `honestIncompleteView(reachedFromDecision:
    /// false, ...)` call site) — every OTHER `honestIncompleteView`/H3
    /// screen reads these off its own `HoldingInfo` instead, captured at
    /// hold-entry time the same way `HoldingInfo.stages` already is.
    @Published var lastCompletedActions: [CompletedAction] = []
    @Published var lastResume: ResumeHint? = nil

    // MARK: Holding (#w10)

    /// H4 only: whether the CURRENT hold has already been answered with
    /// `Keep what I have` — swaps the H4 body for the §2.10 "Here's where
    /// that leaves you" confirmation on the SAME screen (§2.9's own words:
    /// "no new window"). Reset to `false` every time a fresh hold is entered
    /// (`WizardModel.enterHolding`), then possibly re-set to `true`
    /// immediately if this exact hold is already in `acknowledgedHoldingSignatures`.
    @Published var holdingConfirmed = false
    /// Every H4 hold this session's `Keep what I have` has already answered
    /// ("the same question is not asked again this session", §4) — a
    /// session-only memory, never written to disk, never sent to the CLI:
    /// the CLI still reports the same gate as blocked every time it's asked,
    /// this only stops the app from re-interrupting with a question the
    /// person already answered.
    private var acknowledgedHoldingSignatures: Set<HoldingSignature> = []
    private var lastHoldingSignature: HoldingSignature?

    // MARK: One question first (adopt-and-project-setup spec)

    /// Component names ("claude"/"codex"/"knowledge"/"cli") the person has
    /// consented to adopt so far this session — sent back as
    /// `--adopt-existing` on every subsequent plan/apply call, including
    /// Set up's own apply. Never cleared once set (declining is per-run,
    /// per the spec, but this app never re-asks after a decision — see
    /// `onboardQuestionAnswered`).
    @Published var adoptExisting: Set<String> = []
    /// The CLI's own personal-scope "ask" rows — one checkbox per adoptable
    /// component, in the CLI's order.
    @Published var onboardQuestionItems: [EcosystemInventoryItem] = []
    /// Personal-scope items the CLI marked for review instead of a
    /// question (no checkbox, "Kept as is") — shown on the SAME screen.
    @Published var onboardReviewItemsForQuestion: [EcosystemInventoryItem] = []
    /// Row ids currently checked on the question screen. Pre-selected to
    /// every question item's id the first time the screen is populated;
    /// preserved across a Holding round trip ("Include what I already
    /// have" returns "with the previous selections intact").
    @Published var onboardSelections: Set<String> = []
    private var onboardQuestionAnswered = false

    // MARK: Step 7, Your projects (adopt-and-project-setup spec)

    @Published var projectRoots: [WorkspaceRootListEntry] = []
    @Published var projectRootCandidates: [WorkspaceRootCandidate] = []
    @Published var projectWorkspaces: [WorkspaceEntry] = []
    @Published var projectsSummary: WorkspaceSummary?
    @Published var projectsLoading = false
    @Published var projectsDeclined = false
    /// Local, session-only confirmation line for "I don't keep projects on
    /// this Mac" — cleared whenever the step is re-entered with a folder
    /// already granted (the two states are mutually exclusive).
    @Published var projectsDeclineConfirmed = false
    @Published var selectedProjectPaths: Set<String> = []
    /// `nil` is the Step 7 overview. A value means the person opened one
    /// focused CLI-authored category. This is navigation state only; it is
    /// never persisted or treated as project truth.
    @Published var selectedProjectCategory: ProjectTriageCategory?
    @Published var projectsStepOutcome: ProjectsStepOutcome = .notReached
    /// Set only when one or more projects selected from a fresh, actionable
    /// CLI report still fail during configure. The Set up screen stays put
    /// until the person explicitly retries, returns to the project list, or
    /// continues without those projects.
    @Published var projectSetupNeedsDecision = false
    @Published var failedProjectPaths: Set<String> = []
    /// Schema-1.1 project detail selected from the first-run project register.
    /// This is always a CLI-authored row; the wizard never derives a plan.
    @Published var projectIntegrationDetail: WorkspaceEntry?
    @Published var projectIntegrationMessage: String?
    /// CLI-authored deterministic-migration census for the guided cohort.
    /// Swift never derives eligibility from `projectWorkspaces`; it only
    /// renders the candidate states and counts carried by this report.
    @Published var projectMigrationReport: WorkspaceMigrationReport?
    /// Preserved after apply while the ordinary workspace register and the
    /// next census refresh, so the completed-action ledger remains visible.
    @Published var projectMigrationApplyReport: WorkspaceMigrationReport?
    @Published var projectMigrationLoading = false
    @Published var projectMigrationApplying = false
    @Published var projectMigrationReviewOpen = false
    @Published var projectMigrationError: String?
    /// Set only after an external assistant successfully opens. The next
    /// activation of Control Tower consumes this value and asks the CLI to
    /// verify again; assistant self-report never changes project status.
    @Published private(set) var pendingProjectVerificationPath: String?
    /// "An unusable folder shows the CLI's blocked sentence next to the
    /// picker and keeps the step usable" (spec, Step 7's failure/recovery
    /// row) — this step never routes to Holding on its own; a bad folder
    /// choice is shown inline and the picker stays available to try again.
    @Published var projectsFolderBlockedDetail: String?
    private var hasLoadedProjectsStep = false

    private var authStatusTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var materializeInFlight = false

    // MARK: H7 — granting a missing GitHub permission (§2.9.3)

    @Published var grantFlow = GrantFlowState()
    /// Set true the first time `cc auth grant` is discovered NOT to be able
    /// to drive the flow this session — either the verb itself is absent on
    /// this Mac's installed CLI (indistinguishable, from here, from a
    /// graceful `unavailable` answer) or it explicitly reports
    /// `result: "unavailable"`. The ONLY thing that reveals H7's `Show me
    /// how to grant it` leading action (copy spec §3.4: "that state is the
    /// only thing that reveals the fallback") — never shown speculatively.
    @Published var grantUnavailableKnown = false
    private var grantPollTask: Task<Void, Never>?

    #if CT_VISUAL_TEST_BUILD
    /// Test-build-only direct state loading for pixel inspection. Production
    /// binaries do not compile this method or recognize CT_VISUAL_SCENARIO.
    /// The fixtures use the same model values and render paths as live CLI
    /// routing; they only remove device-flow/network timing from screenshot
    /// capture.
    func loadVisualScenario(_ name: String) {
        func inventoryItem(
            id: String,
            scope: String,
            title: String,
            state: String,
            action: String,
            detail: String,
            reversible: Bool,
            declineDetail: String? = nil
        ) -> EcosystemInventoryItem {
            EcosystemInventoryItem(
                id: id,
                scope: scope,
                title: title,
                state: state,
                action: action,
                detail: detail,
                sourcePath: nil,
                destinationPath: nil,
                reversible: reversible,
                declineDetail: declineDetail
            )
        }

        func stage(_ id: String, result: String, detail: String? = nil) -> EcosystemOnboardStage {
            let payload: [String: Any?] = [
                "stage": id,
                "result": result,
                "detail": detail,
            ]
            let normalized = payload.compactMapValues { $0 }
            let data = try! JSONSerialization.data(withJSONObject: normalized)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try! decoder.decode(EcosystemOnboardStage.self, from: data)
        }

        func workspace(
            _ json: String,
            classification: WorkspaceIntegrationClassification
        ) -> WorkspaceEntry {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try! decoder.decode(
                WorkspaceEntry.self,
                from: WorkspaceContractSelftestFixture.entry(
                    json,
                    classification: classification
                )
            )
        }

        func visualProject(
            _ name: String,
            index: Int,
            classification: WorkspaceIntegrationClassification
        ) -> WorkspaceEntry {
            let ready = classification == .ready
            let state = ready ? "ready" : (classification == .couldNotVerify ? "blocked" : "setup-available")
            let detail: String
            switch classification {
            case .ready:
                detail = "Claude and Codex passed authoritative project verification."
            case .guidedIntegration:
                detail = "Project-owned instructions or capabilities need guided setup."
            case .couldNotVerify:
                detail = "Required project integration evidence could not be confirmed."
            case .safeFinish:
                detail = "Control Tower can add only the missing project integration files."
            case .ownerDecision:
                detail = "This project needs a decision from the person who manages its setup."
            }
            let json = """
            {"path":"/p/\(index)-\(name)","name":"\(name)","project_id":null,"state":"\(state)","detail":"\(detail)","declared_components":["claude","codex"],"installed_components":["claude","codex"],"recommended_components":["claude","codex"],"personal_profile":{"state":"\(ready ? "associated" : "local-only")","project_id":null},"setup_policy":"\(ready ? "not-offered" : "ask")","policy_detail":"\(ready ? "Copilot is already set up here, so there is nothing to ask." : "Existing project setup is preserved until its route is completed.")","can_apply_now":false,"apply_blocked_detail":\(ready ? "null" : "\"Nothing was changed.\""),"undo":{"available":false,"detail":"There is nothing here to undo."}}
            """
            return workspace(json, classification: classification)
        }

        let heldItem = inventoryItem(
            id: "device-ssh",
            scope: "machine",
            title: "Your Mac's connection to GitHub",
            state: "held",
            action: "review",
            detail: "This Mac's existing GitHub connection signs in as a different account, so I left it exactly as it is.",
            reversible: false
        )
        let appliedStages = [
            stage("organization-handoff", result: "applied"),
            stage("personal-packages", result: "applied"),
            stage("device-ssh", result: "blocked", detail: heldItem.detail),
        ]

        switch name {
        case "connections":
            authorizedLogin = "pablo"
            phase = .integrations
        case "projects-feedback":
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            projectRoots = [
                try! decoder.decode(
                    WorkspaceRootListEntry.self,
                    from: Data(#"{"name":"Developer","path":"/Users/pablo/Developer","project_count":53}"#.utf8)
                )
            ]
            let readyNames = [
                "BM", "claude-copilot-private", "copilot-news", "knowledge-copilot",
                "test-pilot", "financial-tracker", "investr-app", "revenue-projections",
                "runway", "spanish-copilot", "sproutworks", "thoughts",
                "tigers-toads-fl-weekend", "tigers-toads-weekend-2026", "tracker", "h1", "h2",
            ]
            let guidedNames = [
                "admin-server", "cli-copilot", "cli-copilot-internal", "codex-copilot",
                "crm-automation-copilot", "drip-copilot", "flow", "lars-website",
                "n8n-copilot", "preflight-copilot", "product-creation-copilot",
                "project-copilot", "rfp-copilot", "the-collective", "transformation",
                "workflow-copilot", "h3",
            ]
            let unconfirmedNames = [
                "everyone-needs-knowledge-management", "claude-copilot", "convoco",
                "convoco-policy-build", "convoco-site", "copilot-control-tower",
                "force-readiness-assessment", "insights-copilot",
                "knowledge-copilot-internal", "method-copilot", "pipeline-copilot",
                "research-copilot", "saas-financial-model", "thought-leadership",
                "voice-copilot", "job-finder", "Delphi", "clio", "hermes",
            ]
            projectWorkspaces =
                readyNames.enumerated().map {
                    visualProject($0.element, index: $0.offset, classification: .ready)
                }
                + guidedNames.enumerated().map {
                    visualProject($0.element, index: 100 + $0.offset, classification: .guidedIntegration)
                }
                + unconfirmedNames.enumerated().map {
                    visualProject($0.element, index: 200 + $0.offset, classification: .couldNotVerify)
                }
            selectedProjectCategory = nil
            projectIntegrationDetail = nil
            phase = .projects
        case "projects-bulk-migration", "projects-bulk-migration-review":
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            projectRoots = [
                try! decoder.decode(
                    WorkspaceRootListEntry.self,
                    from: Data(#"{"name":"Sites","path":"/Volumes/Dev/Sites/COPILOT","project_count":62}"#.utf8)
                )
            ]
            let eligibleNames = [
                "convoco", "convoco-site", "copilot-control-tower", "insights-copilot",
                "method-copilot", "pipeline-copilot", "research-copilot",
                "thought-leadership", "voice-copilot",
            ]
            let heldNames = [
                "convoco-policy-build", "force-readiness-assessment", "job-finder",
                "Delphi", "clio", "hermes", "saas-financial-model",
            ]
            let tailoredNames = [
                "everyone-needs-knowledge-management", "admin-server", "cli-copilot",
                "cli-copilot-internal", "codex-copilot", "crm-automation-copilot",
                "drip-copilot", "flow", "lars-website", "n8n-copilot",
                "preflight-copilot", "product-creation-copilot", "project-copilot",
                "rfp-copilot", "the-collective", "transformation", "workflow-copilot",
            ]
            let allGuidedNames = eligibleNames + heldNames + tailoredNames
            projectWorkspaces = allGuidedNames.enumerated().map {
                visualProject($0.element, index: 300 + $0.offset, classification: .guidedIntegration)
            }
            let opaque = "sha256:" + String(repeating: "a", count: 64)
            let verification = WorkspaceMigrationVerification(
                command: ["cc", "workspace", "verify", "--json"],
                expected: "Every migrated component classifies Ready."
            )
            func candidate(
                _ name: String,
                index: Int,
                state: WorkspaceMigrationState
            ) -> WorkspaceMigrationCandidate {
                let isEligible = state == .eligible
                let detail: String
                switch state {
                case .eligible:
                    detail = "A recognized older setup can be updated without replacing project-owned instructions or tools."
                case .held:
                    detail = "This project has work in progress or a customized check, so Control Tower left it alone."
                case .residualGuidance:
                    detail = "This project needs a tailored setup plan. Nothing has been changed."
                case .notNeeded:
                    detail = "No guided migration is needed."
                }
                let action = isEligible
                    ? WorkspaceMigrationAction(
                        id: opaque,
                        inspectionId: opaque,
                        migrationKinds: [.codexPortableCopy],
                        willChange: [
                            WorkspaceMigrationChange(path: "plugins/codex-copilot", operation: "replace-recognized-link")
                        ],
                        willPreserve: [
                            WorkspaceArtifact(kind: .instruction, path: "AGENTS.md", detail: "Preserve the project Codex instructions.")
                        ],
                        willNotDo: ["overwrite-project-instructions"]
                    )
                    : nil
                return WorkspaceMigrationCandidate(
                    path: "/p/\(index)-\(name)",
                    name: name,
                    classification: .guidedIntegration,
                    inspectionId: opaque,
                    migrationKinds: isEligible ? [.codexPortableCopy] : [],
                    state: state,
                    automatable: isEligible,
                    reasonCode: isEligible ? nil : "visual-fixture",
                    detail: detail,
                    action: action,
                    verification: verification
                )
            }
            let candidates = eligibleNames.enumerated().map {
                candidate($0.element, index: 300 + $0.offset, state: .eligible)
            } + heldNames.enumerated().map {
                candidate($0.element, index: 309 + $0.offset, state: .held)
            } + tailoredNames.enumerated().map {
                candidate($0.element, index: 316 + $0.offset, state: .residualGuidance)
            }
            projectMigrationReport = WorkspaceMigrationReport(
                schemaVersion: "1.0",
                mode: "plan",
                result: .actionRequired,
                planId: opaque,
                summary: WorkspaceMigrationSummary(
                    eligible: 9,
                    held: 7,
                    residualGuidance: 17,
                    totalGuided: 33
                ),
                candidates: candidates,
                ledger: [],
                requestedPlanId: nil,
                detail: nil,
                applySummary: nil,
                after: nil
            )
            projectsSummary = WorkspaceSummary(
                ready: 26,
                setupAvailable: 33,
                activationRequired: 0,
                blocked: 3,
                total: 62
            )
            selectedProjectCategory = .guidedSetup
            projectIntegrationDetail = nil
            projectMigrationReviewOpen = name == "projects-bulk-migration-review"
            phase = .projects
        case "projects-guided-detail", "projects-unconfirmed-detail", "projects-ready-detail":
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            projectRoots = [
                try! decoder.decode(
                    WorkspaceRootListEntry.self,
                    from: Data(#"{"name":"Developer","path":"/Users/pablo/Developer","project_count":53}"#.utf8)
                )
            ]
            let classification: WorkspaceIntegrationClassification =
                name == "projects-guided-detail"
                    ? .guidedIntegration
                    : (name == "projects-unconfirmed-detail" ? .couldNotVerify : .ready)
            let projectName =
                classification == .guidedIntegration
                    ? "admin-server"
                    : (classification == .couldNotVerify ? "convoco" : "BM")
            let detail = visualProject(projectName, index: 1, classification: classification)
            projectWorkspaces = [detail]
            selectedProjectCategory = ProjectTriageCategory.allCases.first {
                $0.classification == classification
            }
            projectIntegrationDetail = detail
            phase = .projects
        case "project-failure":
            setupProgress.callRow.state = .done(detail: "Copilot on this Mac is ready.")
            setupProgress.projectRows = [
                SetupRow(
                    id: "/p/admin-server",
                    title: "admin-server",
                    state: .couldNotFinish(
                        detail: "Existing project setup needs review before Copilot can add shared files. Nothing was changed. Ask the person who manages this project to review its existing Copilot setup."
                    )
                )
            ]
            failedProjectPaths = ["/p/admin-server"]
            projectSetupNeedsDecision = true
            phase = .materializing
        case "verified-completion":
            authorizedLogin = "pablo"
            lastOnboardResult = .ready
            lastOnboardStages = Self.expectedStageIds(includeCodex: true).map {
                stage($0, result: "applied")
            }
            projectsStepOutcome = .setUp(succeeded: 2, total: 2)
            phase = .verified
        case "org-question":
            orgNameInput = ""
            orgFieldTouched = false
            phase = .orgQuestion
        case "adoption-offer":
            let item = inventoryItem(
                id: "device-ssh",
                scope: "machine",
                title: "Your Mac's connection to GitHub",
                state: "adoptable",
                action: "create",
                detail: "This Mac already connects to GitHub, and I checked that it works and that it's signed in as you. I'll leave that exactly as it is and add the one connection it's still missing.",
                reversible: true,
                declineDetail: "Without this, setup can't add the missing connection on this Mac."
            )
            onboardQuestionItems = [item]
            onboardSelections = [item.id]
            phase = .onboardQuestion
        case "completion-fallback":
            lastOnboardResult = .ready
            lastOnboardStages = appliedStages
            phase = .verified
        case "h1":
            phase = .holding(.h1(origin: .detect))
        case "h2":
            phase = .holding(.h2(
                origin: .detect,
                intro: "Something stopped me from reading your setup, so I won't guess.",
                code: "environment-error",
                message: "The setup report could not be read."
            ))
        case "h3":
            phase = .holding(.h3(
                origin: .detect,
                intro: "I couldn't give this Mac its own key, so I stopped. Nothing that was already here was changed.",
                schemaVersion: "1.0",
                stage: "device-ssh",
                result: "blocked",
                message: "This Mac could not finish its secure GitHub connection."
            ))
        case "h4":
            phase = .holding(.h4(
                origin: .detect,
                intro: "I found something that belongs to you, so I left it alone and stopped before changing anything.",
                reviewItems: [heldItem],
                stages: appliedStages,
                schemaVersion: "1.0",
                stage: "device-ssh",
                result: "blocked",
                message: heldItem.detail
            ))
        case "h5":
            phase = .holding(.h5Offline(origin: .detect))
        case "h6":
            phase = .holding(.h6(
                origin: .detect,
                intro: "I can see your organization's setup, but it isn't ready for this Mac yet.",
                code: "onboard-unavailable",
                stage: "organization-handoff",
                result: "blocked",
                message: "Could not reach GitHub to read the organization setup."
            ))
        case "h7":
            phase = .holding(.h7(
                origin: .detect,
                schemaVersion: "1.0",
                stage: "device-ssh",
                result: "blocked",
                message: "Your GitHub sign-in doesn't include permission to add this Mac's key."
            ))
        default:
            break
        }
    }
    #endif

    // MARK: Derived

    var currentStage: WizardStage {
        switch phase {
        case .welcome: return .welcome
        // `.orgQuestion` renders inline over Connect GitHub, same mechanism
        // as Holding/`.onboardQuestion`: no sidebar row of its own, no
        // step-number change (copy spec §2.1.1).
        case .connectGitHub, .orgQuestion: return .connectGitHub
        // `.onboardQuestion` renders inline over Detect, same mechanism as
        // Holding: no sidebar row of its own, no step-number change.
        case .detecting, .replanningAfterDecision, .detected, .onboardQuestion: return .detect
        case .whatYoureGetting: return .whatYoureGetting
        case .departments: return .departments
        case .integrations: return .integrations
        case .projects: return .projects
        case .materializing: return .materialize
        case .verifying, .verified: return .verify
        case .holding(let info): return info.origin
        }
    }

    var joinedDepartments: [DepartmentRow] {
        departments.filter { $0.state == .joined }
    }

    // MARK: Welcome -> Connect GitHub

    func start() {}

    func getStarted() {
        phase = .connectGitHub
        pollTask?.cancel()
        deviceFlow = DeviceFlowState(status: .pending)
        authStatusTask?.cancel()
        authStatusTask = Task { [weak self] in
            guard let self else { return }
            let result = await CliClient.shared.authStatus()
            guard !Task.isCancelled else { return }
            self.authStatusTask = nil

            switch result {
            case .success(let status):
                if status.state == .authorized {
                    // The CLI's offline-safe status verdict is backed by
                    // the existing Keychain credential. Reuse it and skip
                    // the device ceremony; Detect independently reads the
                    // verdict again as part of its normal trust gate.
                    self.authorizedLogin = status.identity?.login
                    self.deviceFlow.status = .authorized
                    self.runDetect()
                } else {
                    self.beginDeviceFlow()
                }
            case .failure(let error):
                // An unreadable credential store is not the same thing as
                // signed out. Hold visibly instead of starting a fresh
                // login and potentially replacing a valid connection.
                self.handleConnectGitHubError(error, attemptedOrg: nil)
            }
        }
    }

    // MARK: Connect GitHub (#w2) — device flow

    /// `initiate -> render userCode + Open GitHub -> poll every interval
    /// seconds via a cancellable Task -> authorized: stop, fetch
    /// authStatus(), enable Continue`, per the task contract. No countdown is
    /// ever rendered from this state (`DeviceFlowState` carries no visible
    /// timer), even though `startPolling` below tracks `expiresIn`
    /// internally to hard-stop the loop.
    ///
    /// The public, no-arg entry point every existing call site
    /// (`getStarted()`, and every Holding "Try again"/"Check again" whose
    /// origin is Connect GitHub) already used before the organization
    /// question existed — replays `lastAttemptedOrg` (`nil` on the very
    /// first call this session) rather than silently reverting to no
    /// organization on a retry.
    func beginDeviceFlow() {
        beginDeviceFlow(org: lastAttemptedOrg)
    }

    /// `org`, when non-nil, is passed straight through to `auth login --org`
    /// (copy spec §2.1.1) — either this Mac's own standup-brief name
    /// (`handleOrgRequired()`'s silent retry) or whatever the person just
    /// typed (`continueToSignInFromOrgQuestion()`). The pointer is persisted
    /// with `cc config set` ONLY after a device code actually comes back for
    /// this `org` (copy spec: "a name that never resolved is never
    /// persisted") — never before, and never for the `nil`/no-organization
    /// case, since there is nothing new to persist there.
    private func beginDeviceFlow(org: String?) {
        authStatusTask?.cancel()
        authStatusTask = nil
        pollTask?.cancel()
        lastAttemptedOrg = org
        deviceFlow = DeviceFlowState(status: .pending)
        Task {
            switch await CliClient.shared.authLoginInitiate(org: org) {
            case .success(let code):
                if let org {
                    guard await CliClient.shared.configSetGithubAppOrg(org) else {
                        self.orgQuestionSubmitting = false
                        self.enterHolding(HoldingInfo.h2(
                            origin: .connectGitHub,
                            intro: "Something on this Mac stopped the setup helper, so I've paused.",
                            code: "environment-error"
                        ))
                        return
                    }
                }
                self.orgQuestionSubmitting = false
                self.phase = .connectGitHub
                self.deviceFlow.userCode = code.userCode
                self.deviceFlow.verificationUri = code.verificationUri
                self.deviceFlow.deviceCode = code.deviceCode
                self.deviceFlow.interval = code.interval
                self.startPolling(deviceCode: code.deviceCode, interval: code.interval, expiresIn: code.expiresIn, org: org)
            case .failure(let error):
                self.orgQuestionSubmitting = false
                self.handleConnectGitHubError(error, attemptedOrg: org)
            }
        }
    }

    /// Hard stop at `expiresIn`, never a visible countdown. `pending` polls
    /// silently repeat; `authorized`/`expired`/`denied` are terminal. `org`
    /// carries through to every poll (`authLoginPoll(deviceCode:org:)`) —
    /// the CLI re-resolves the organization's client id on every call.
    private func startPolling(deviceCode: String, interval: Int, expiresIn: Int, org: String?) {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        let waitSeconds = UInt64(max(interval, 1))
        pollTask = Task { [weak self] in
            while true {
                if Task.isCancelled { return }
                guard let self else { return }
                if Date() >= deadline {
                    self.handleDeviceFlowExpired()
                    return
                }
                try? await Task.sleep(nanoseconds: waitSeconds * 1_000_000_000)
                if Task.isCancelled { return }
                switch await CliClient.shared.authLoginPoll(deviceCode: deviceCode, org: org) {
                case .success(let poll):
                    switch poll.status {
                    case .authorized:
                        self.handleDeviceFlowAuthorized()
                        return
                    case .expired:
                        self.handleDeviceFlowExpired()
                        return
                    case .denied:
                        self.handleDeviceFlowDenied()
                        return
                    case .pending:
                        continue
                    }
                case .failure(let error):
                    self.handleConnectGitHubError(error, attemptedOrg: org)
                    return
                }
            }
        }
    }

    private func handleDeviceFlowAuthorized() {
        deviceFlow.status = .authorized
        Task {
            if case .success(let status) = await CliClient.shared.authStatus() {
                self.authorizedLogin = status.identity?.login
            }
        }
    }

    /// Terminal, non-error outcomes — routed to Holding with "Try again"
    /// (restarts `beginDeviceFlow()`), per the task contract. Neither is one
    /// of the copy spec's seven named variants (`control-tower-copy-deck.md`
    /// §2.9 covers `CliError`/blocked-stage cases only); the spec gives no verbatim copy
    /// for a device-flow expiry/denial, so these keep their existing,
    /// unchanged intro strings under H3's shell (same eyebrow/title/tint/
    /// disclosure every other "nobody's fault, retry" case gets).
    private func handleDeviceFlowExpired() {
        deviceFlow.status = .expired
        enterHolding(HoldingInfo.h3(origin: .connectGitHub, intro: "That code expired before you finished. You can try again whenever you're ready."))
    }

    private func handleDeviceFlowDenied() {
        deviceFlow.status = .denied
        enterHolding(HoldingInfo.h3(origin: .connectGitHub, intro: "That sign-in was declined. You can try again whenever you're ready."))
    }

    /// The Connect GitHub-origin error router — a superset of `routeCliError`
    /// that additionally recognizes the three organization codes
    /// (copy spec Appendix E.1) before falling back to the shared table for
    /// every other `CliError`, tagging `no-company-app`'s `Use a different
    /// organization` return path (§5) onto the resulting hold whenever this
    /// attempt actually carried an organization name.
    private func handleConnectGitHubError(_ error: CliError, attemptedOrg: String?) {
        if case .exit2(let code, _) = error {
            switch code {
            case "org-required":
                handleOrgRequired()
                return
            case "org-not-found":
                // Stays on the organization screen with what was typed (or
                // silently tried) still in the field — never discarded, so
                // the difference between it and the real name stays visible.
                orgNotFoundAttempt = attemptedOrg
                orgQuestionSubmitting = false
                phase = .orgQuestion
                return
            case "network-unavailable":
                enterHolding(HoldingInfo.h5Offline(origin: .connectGitHub))
                return
            default:
                break
            }
        }
        guard var resolvedInfo = Self.holdingInfo(for: error, origin: .connectGitHub) else {
            pollTask?.cancel()
            phase = .connectGitHub
            beginDeviceFlow()
            return
        }
        if attemptedOrg != nil, resolvedInfo.variant == .waitingOnOrg || resolvedInfo.variant == .needsPermission {
            resolvedInfo.orgNameForReturn = attemptedOrg
        }
        enterHolding(resolvedInfo)
    }

    /// `org-required` (copy spec §2.1.1/§5): this Mac's own admin standup
    /// brief is tried silently, ONCE per session, before anything is ever
    /// shown — a success means the person never sees the organization
    /// screen at all. Every other case (no brief, an already-blank brief, or
    /// a brief already tried and failed this session) shows the screen.
    private func handleOrgRequired() {
        if !orgSilentAttemptTriedThisSession, let standupOrg = LocalAdminSignal.standupOrgName {
            orgSilentAttemptTriedThisSession = true
            silentlyTriedOrgName = standupOrg
            orgNameInput = standupOrg
            beginDeviceFlow(org: standupOrg)
        } else {
            phase = .orgQuestion
        }
    }

    func openGitHubSignIn() {
        guard let raw = deviceFlow.verificationUri, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyDeviceCode() {
        guard let code = deviceFlow.userCode else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
    }

    func continueFromConnectGitHub() {
        guard deviceFlow.status == .authorized else { return }
        runDetect()
    }

    func backToWelcome() {
        authStatusTask?.cancel()
        authStatusTask = nil
        pollTask?.cancel()
        phase = .welcome
    }

    // MARK: Detect (#w3) — verify-and-provision gate

    /// `authStatus() + doctor()`; unreadable -> Holding with the verbatim
    /// "I can't read what's already on this Mac right now, so I won't
    /// guess." line, per the task contract.
    func runDetect() {
        performDetect(replanning: false)
    }

    /// Shared by the first-ever Detect pass and the re-plan that follows a
    /// "One question first" decision (`includeOnboardSelections()` /
    /// `declineOnboardQuestion()` below) — the ONLY difference is which
    /// progress copy is shown while it runs (Detect's spec, "Ask" row:
    /// "the feedback is the shared progress card with **Checking what that
    /// means…**" for the post-decision case).
    private func performDetect(replanning: Bool) {
        phase = replanning ? .replanningAfterDecision : .detecting
        Task {
            async let authAsync = CliClient.shared.authStatus()
            async let doctorAsync = CliClient.shared.doctor()
            async let onboardAsync = CliClient.shared.ecosystemOnboardPlan(
                products: self.copilotProducts,
                adoptExisting: Array(self.adoptExisting),
                repositoryRoot: self.copilotRepositoryRoot
            )
            let authResult = await authAsync
            let doctorResult = await doctorAsync
            let onboardResult = await onboardAsync

            guard case .success(let status) = authResult else {
                if case .failure(let error) = authResult {
                    self.routeCliError(error, origin: .detect)
                }
                return
            }
            // A valid `auth status` envelope is not itself proof of a signed
            // in account: `signed-out` is an ordinary, decodable state. Detect
            // must never turn that into the false line "GitHub: signed in."
            // Return to the existing device-flow screen, the same recovery
            // used by the CLI's typed `signed-out` error.
            guard status.state == .authorized else {
                self.pollTask?.cancel()
                self.phase = .connectGitHub
                self.beginDeviceFlow()
                return
            }
            guard case .success(let doctor) = doctorResult else {
                if case .failure(let error) = doctorResult {
                    self.routeCliError(error, origin: .detect)
                }
                return
            }
            self.detectedCopilotState = RenderState.from(doctor, joinable: nil)
            guard case .success(let onboard) = onboardResult else {
                if case .failure(let error) = onboardResult {
                    self.routeCliError(error, origin: .detect)
                }
                return
            }
            self.ecosystemInventory = onboard.inventory ?? []
            self.ecosystemInventorySummary = onboard.inventorySummary
            self.ecosystemLayers = onboard.layers
            self.copilotRepositoryRoot = onboard.stages.first(where: { $0.stage == "repository-location" })?.path
                ?? onboard.layers.compactMap(\.localPath).first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }

            // "One question first" (adopt-and-project-setup spec, "Ask" row):
            // asked BEFORE the blocked-guard below, and only once per
            // session — a plan that is "blocked" purely because an
            // unrelated item needs review must still surface the question,
            // never silently drop it behind Holding's own review-only card
            // (the old dead end this replaces).
            if !self.onboardQuestionAnswered {
                let (ask, review) = Self.personalOnboardQuestion(from: onboard)
                if !ask.isEmpty {
                    self.onboardQuestionItems = ask
                    self.onboardReviewItemsForQuestion = review
                    if self.onboardSelections.isEmpty {
                        self.onboardSelections = Set(ask.map(\.id))
                    }
                    self.phase = .onboardQuestion
                    return
                }
            }

            guard onboard.result != .blocked else {
                self.enterHolding(Self.holdingInfo(forBlockedOnboard: onboard, origin: .detect))
                return
            }

            var lines: [String] = []
            if let login = status.identity?.login {
                self.authorizedLogin = login
                lines.append("GitHub: signed in as \(login).")
            } else {
                lines.append("GitHub: signed in.")
            }
            lines.append("Organization: \(onboard.org).")
            lines.append("Personal spaces: checked against the signed-in GitHub account.")
            if let root = self.copilotRepositoryRoot {
                lines.append("Copilot repositories: \(root).")
            }
            // The gh install/approve mechanics are not built yet (the spec's
            // own NB-13) — this line is honest static state, not a live
            // detection, until that verb exists.
            lines.append("GitHub command line: already here and current.")
            // Reuse the SAME per-status sentence the tray/popover already
            // computes (`RenderState.from`) rather than re-deriving currency
            // wording here — one honest, already-CLI-derived verdict, never
            // a second opinion.
            lines.append(RenderState.from(doctor, joinable: nil).header.sentence)
            for stage in onboard.stages where stage.result == "changes-required" {
                if stage.stage == "personal-packages" {
                    lines.append("Your private spaces need setup; only confirmed-missing spaces will be created.")
                } else if stage.stage == "device-ssh" {
                    lines.append("This Mac needs its own secure GitHub connection.")
                } else if stage.stage == "layer-manifest" {
                    lines.append("Your organization, personal, and foundation layers are ready to be connected.")
                }
            }
            self.detectLines = lines
            self.phase = .detected
        }
    }

    /// Pure: splits an ecosystem plan's ENTIRE inventory (every scope, not
    /// just `"personal"`) into ask rows (adoptable — the CLI's
    /// `reversible: true` is unique to an adoptable/creatable row, see
    /// `onboard.py`'s `_personal_inventory`/`_ssh_inventory`) and review
    /// rows (`action == "review"`), in the CLI's own order. A `static`
    /// function (no instance state) so this exact derivation is shared
    /// between `performDetect` above and the selftest below — never two
    /// slightly-different readings of the same report.
    ///
    /// Previously filtered to `scope == "personal"` only — the CLI's own
    /// SSH offer row is `scope: "machine"` (`_ssh_inventory`'s docstring:
    /// "the same shape as an adoptable personal package"), so that filter
    /// silently dropped it and the offer never rendered at all (copy spec
    /// Appendix D.3, "Bug 1"). The scope word itself never reaches the
    /// screen either way — `onboardQuestionView` groups by scope into two
    /// cards, it does not render it as text.
    ///
    /// DEFENSIVE (forward-looking, no known live case today): a
    /// `reversible: true` row is only ever offered as a real checkbox if
    /// `componentId(fromPersonalInventoryId:)` can translate its `id` into a
    /// real `--adopt-existing` token. If a future CLI change adds a THIRD
    /// ask-row id shape (neither `personal-<component>` nor the fixed
    /// `device-ssh`) before this app's token map is updated to match, that
    /// row is folded into `review` instead of `ask` — never rendered as a
    /// checkbox. This is the exact class of bug `componentId`'s own doc
    /// comment names ("Bug 2"), closed for ANY future id, not just
    /// `device-ssh`: a checkbox whose consent silently never reaches the CLI
    /// is a false choice, and the review-row rendering ("Kept as is") stays
    /// TRUE either way, since this app never attempts to adopt what it
    /// cannot map. `CT_ONBOARD_QUESTION_SELFTEST`'s `unmappedId=` assertion
    /// (`control-tower-tray.swift`) proves this with a synthetic id.
    nonisolated static func personalOnboardQuestion(from report: EcosystemOnboardReport) -> (ask: [EcosystemInventoryItem], review: [EcosystemInventoryItem]) {
        let inventory = report.inventory ?? []
        let ask = inventory.filter { $0.reversible && componentId(fromPersonalInventoryId: $0.id) != nil }
        let review = inventory.filter { $0.action == "review" || ($0.reversible && componentId(fromPersonalInventoryId: $0.id) == nil) }
        return (ask, review)
    }

    /// `EcosystemInventoryItem.id` -> the consent token `ensure_machine_ssh_identity`/
    /// `_personal_inventory` actually check for in `--adopt-existing`.
    /// Personal-space rows are always `"personal-<component>"` (`onboard.py`'s
    /// `_personal_inventory`) and map straight to `<component>`. The device
    /// connection row is the single fixed id `"device-ssh"` (`_ssh_inventory`)
    /// and maps to the fixed token `"ssh"` — `ensure_machine_ssh_identity`'s
    /// own consent check: `"ssh" in {value.strip().lower() for value in
    /// adopt_existing ...}`. Previously returned `nil` for `"device-ssh"`
    /// (no `"personal-"` prefix), which silently dropped the consent token,
    /// made the apply write nothing, and repeated the offer forever (copy
    /// spec Appendix D.3, "Bug 2" — "the single highest-risk line in the
    /// whole change, because it fails silently and looks like the CLI's
    /// fault"). `scripts/tests/smoke-scenarios.sh`'s completion-rule
    /// scenario asserts this mapping directly so a regression here fails
    /// loudly instead of silently.
    nonisolated static func componentId(fromPersonalInventoryId id: String) -> String? {
        if id == "device-ssh" { return "ssh" }
        let prefix = "personal-"
        guard id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count))
    }

    // MARK: §2.10's completion rule — "I stopped, and here's what that
    // means for you". A single shared predicate every terminal confirmation
    // in the wizard is routed through (H4's `Keep what I have` confirmation
    // unconditionally, per that call site's own comment; Verify's
    // `Everything checks out.` conditionally, via `verifyCompletionPasses`
    // below). Resolved language (kept/done/set up/ready/checks out/
    // everything/all) is permitted ONLY when this returns true.

    /// `onboard.schema.json`'s full `ecosystemStage.stage` enum, in its own
    /// declared order, each paired with its §2.3 capability-row copy. Wider
    /// than `SetupProgressState.namedStages` (which deliberately excludes
    /// `materialize`/`doctor` — "Verify's own concern") because the
    /// completion rule's condition 3 is explicit that EVERY schema stage
    /// counts, not just the six Set Up shows a live checklist row for.
    nonisolated static let allReportStages: [(id: String, worksNow: String, notYet: String)] = [
        ("organization-handoff", "Your organization's shared setup came through.", "Your organization's shared setup hasn't come through."),
        ("personal-packages", "Your own spaces on GitHub are ready.", "Your own spaces on GitHub aren't ready yet."),
        ("device-ssh", "This Mac can reach GitHub on its own.", "This Mac can't reach GitHub on its own yet."),
        ("layer-manifest", "Your copilots are connected together.", "Your copilots aren't connected together yet."),
        ("secret-store", "The integrations your team shares are ready.", "The integrations your team shares aren't ready yet."),
        ("codex-plugin", "Codex Copilot is set up on this Mac.", "Codex Copilot isn't set up on this Mac yet."),
        ("materialize", "Your copilots are in place on this Mac.", "Your copilots aren't in place on this Mac yet."),
        ("doctor", "Everything checked out as current.", "I couldn't confirm your copilots are current."),
    ]

    /// The stage ids condition 3 actually holds the report to: every schema
    /// stage EXCEPT `codex-plugin` when the person never asked for Codex
    /// Copilot. `onboard.py` never even attempts that stage in that case
    /// (`if "codex" in normalized`), so "never mentioned" there is not
    /// evidence anything was left undone — it simply doesn't apply. Reading
    /// condition 3 with no exception here would mean a fully successful
    /// claude-only run could NEVER pass the completion rule (`codex-plugin`
    /// would read `.neverReported` forever), which would be a NEW dishonesty
    /// bug in the opposite direction from the one this whole change fixes —
    /// flagged in the implementation report as an extension of the copy
    /// spec's literal condition 3, not a literal reading of it.
    nonisolated static func expectedStageIds(includeCodex: Bool) -> [String] {
        allReportStages.map(\.id).filter { includeCodex || $0 != "codex-plugin" }
    }

    /// Conditions 1-3 of the completion rule. Condition 4 ("the sentence
    /// describes only what the report proves") is not a boolean this
    /// function can check — it is enforced by CONSTRUCTION, by routing
    /// every terminal confirmation through the §2.10 pattern whenever
    /// conditions 1-3 fail, and never inventing a softer wording in between.
    nonisolated static func completionRulePasses(result: OnboardResult, stages: [EcosystemOnboardStage], includeCodex: Bool) -> Bool {
        guard result == .applied || result == .ready else { return false }
        guard !stages.contains(where: { $0.result == "blocked" }) else { return false }
        // The shared credential store is an optional, additive rung. A
        // structured deferral there may finish core setup; no other stage
        // gets that exception.
        guard !stages.contains(where: { $0.result == "deferred" && $0.stage != "secret-store" }) else { return false }
        let mentioned = Set(stages.map(\.stage))
        return expectedStageIds(includeCodex: includeCodex).allSatisfy(mentioned.contains)
    }

    nonisolated static func sharedStoreIsDeferred(_ stages: [EcosystemOnboardStage]) -> Bool {
        stages.contains(where: { $0.stage == "secret-store" && $0.result == "deferred" })
    }

    /// §2.10's two capability lists — "works now" rows first, "doesn't work
    /// yet" rows second, in the schema's own stage order, skipping
    /// `codex-plugin` on the same not-applicable basis as
    /// `expectedStageIds(includeCodex:)` above. A stage that never ran and a
    /// stage that ran and blocked read identically (copy spec §2.3): both
    /// land in "doesn't work yet", never distinguished on screen.
    nonisolated static func honestCapabilityRows(stages: [EcosystemOnboardStage], includeCodex: Bool) -> (worksNow: [String], notYet: [String]) {
        let byId = Dictionary(stages.map { ($0.stage, $0) }, uniquingKeysWith: { _, latest in latest })
        var worksNow: [String] = []
        var notYet: [String] = []
        for entry in allReportStages where includeCodex || entry.id != "codex-plugin" {
            if let stage = byId[entry.id], stage.result != "blocked", stage.result != "deferred" {
                worksNow.append(entry.worksNow)
            } else {
                notYet.append(entry.notYet)
            }
        }
        return (worksNow, notYet)
    }

    /// Task 211/G-4b: the "what was created/changed" half of an honest
    /// partial-apply screen — grouped sensibly into what's done (rendered
    /// as-is) and what was undone (`rolled-back` entries prefixed "Undone:",
    /// per the spec's own "Rolled-back entries render as undone"). Renders
    /// each entry's own CLI-authored `summary` verbatim (already
    /// plain-language prose, e.g. "Created the private GitHub repository
    /// ..." — never a raw Git/stderr string, never a bare SHA — see
    /// `CompletedAction`'s own doc comment in `native/cli-dtos.swift`) and
    /// invents no new claim of its own. `failed` entries are intentionally
    /// excluded: they did not complete, so they belong to "what remains"
    /// (the blocked stage's own message / `resume.detail`), not to "what's
    /// already done".
    nonisolated static func groupedLedgerLines(_ actions: [CompletedAction]) -> (completed: [String], rolledBack: [String]) {
        var completed: [String] = []
        var rolledBack: [String] = []
        for action in actions {
            switch action.outcome {
            case .completed: completed.append(action.summary)
            case .rolledBack: rolledBack.append("Undone: \(action.summary)")
            case .failed: continue
            }
        }
        return (completed, rolledBack)
    }

    /// Pure: maps the aggregate onboarding call's real `stages` onto
    /// `SetupProgressState.namedStages`' six fixed rows — no ordering
    /// knowledge, no invented result, matching every other parser in this
    /// file. A stage the call never mentions reads `.neverReported` (the
    /// spec's own reconciliation rule); `static` so this exact derivation is
    /// shared between `beginMaterialize` below and the selftest in
    /// `native/control-tower-tray.swift`.
    static func resolveStageRows(from stages: [EcosystemOnboardStage]) -> [SetupRow] {
        var rows = SetupProgressState.namedStages.map { SetupRow(id: $0.id, title: $0.title) }
        var mentioned = Set<String>()
        for stage in stages {
            guard let index = rows.firstIndex(where: { $0.id == stage.stage }) else { continue }
            mentioned.insert(stage.stage)
            if stage.result == "blocked" {
                rows[index].state = .couldNotFinish(detail: couldNotFinishStageText(stage.detail))
            } else if stage.result == "deferred" {
                let detail = stage.detail?.isEmpty == false
                    ? stage.detail!
                    : "Not connected on this Mac. Setup continued without this optional capability."
                rows[index].state = .deferred(detail: detail)
            } else {
                let detail = stage.detail?.isEmpty == false ? stage.detail! : "Done."
                rows[index].state = .done(detail: detail)
            }
        }
        for index in rows.indices where !mentioned.contains(rows[index].id) {
            rows[index].state = .neverReported
        }
        return rows
    }

    private static func couldNotFinishStageText(_ engineDetail: String?) -> String {
        let base = "Couldn't finish this one. Everything before it is still in place."
        guard let engineDetail, !engineDetail.isEmpty else { return base }
        return "\(base) \(engineDetail)"
    }

    /// The copy spec's §3 gate table: given a report whose `result` is
    /// already known to be `.blocked`, picks the ONE Holding variant/copy
    /// for it. Pure — no `CliClient` call, no I/O, same discipline as every
    /// other parser above; shared between `performDetect` (plan time) and
    /// `beginMaterialize` (apply time), the two call sites that can receive
    /// a blocked aggregate-onboard report.
    ///
    /// DEFAULTS TO H3 (the fault variant) whenever nothing positively proves
    /// the hold is user-owned — the spec's own rule ("claiming 'this is
    /// yours' without proof is worse than the current screen"). Every
    /// branch that DOES reach H4 does so by reading a CLI-emitted enum
    /// token or count (`action == "review"`, `config == "held"`, `held >
    /// 0`), never by inferring anything from a prose string.
    nonisolated static func holdingInfo(forBlockedOnboard report: EcosystemOnboardReport, origin: WizardStage) -> HoldingInfo {
        // Task 211/G-4b: every H3 branch below threads the SAME ledger
        // through, so a "nothing changed" clause can never be asserted once
        // this run actually completed a mutation. Task 210/G-7:
        // `resumeRetryable` is `resume.safe_to_rerun` (defaulting true only
        // because older/partial payloads may omit `resume` on a result this
        // classifier's own caller already confirmed is `blocked` — never
        // because the app assumes it) — the STARTING point for
        // `retryable`, overridden to `false` ONLY by the one branch below
        // whose block is a Git-history review row that cannot change on a
        // bare retry regardless of what `resume` claims.
        let resumeRetryable = report.resume?.safeToRerun ?? true
        let completedActions = report.completedActions
        let resume = report.resume

        func h3(
            title: String = "I couldn't finish one part of setup",
            intro: String,
            framedDetail: String? = nil,
            stage: EcosystemOnboardStage,
            retryable: Bool = resumeRetryable
        ) -> HoldingInfo {
            HoldingInfo.h3(
                origin: origin,
                title: title,
                intro: intro,
                framedDetail: framedDetail,
                schemaVersion: report.schemaVersion, stage: stage.stage, result: stage.result, message: stage.detail,
                retryable: retryable,
                completedActions: completedActions,
                resume: resume
            )
        }

        guard let stage = report.stages.last(where: { $0.result == "blocked" }) else {
            // Defensive only — `performDetect`/`beginMaterialize` already
            // checked `report.result == .blocked` before calling this, so a
            // report with no individually-blocked stage is unexpected. Still
            // an honest H3, never a fabricated H4.
            return HoldingInfo.h3(
                origin: origin,
                intro: "Your organization's setup could not be confirmed safely.",
                schemaVersion: report.schemaVersion,
                retryable: resumeRetryable,
                completedActions: completedActions,
                resume: resume
            )
        }

        // §3.1's "frame" gates render the CLI's own `detail` inline (under
        // "What setup found:") ONLY once it also passes §2.2 rule 3's
        // presentability test; every gate keeps `stage.detail` in the
        // support block's `Message:` line regardless (rule 5), via the
        // `message:` argument every branch below passes separately.
        func framedIfPresentable(_ detail: String?) -> String? {
            guard let detail, HoldingInfo.isPresentable(detail) else { return nil }
            return detail
        }
        // Task 211/G-4b: the honest replacement for a "nothing was changed"
        // clause — used ONLY when `completedActions` is non-empty, so the
        // stop-clause never claims more than the ledger proves. The ledger
        // itself (what was created/changed, what remains, the safe next
        // step) renders as its own card in `h3View`/`honestIncompleteView`,
        // never re-summarized here.
        func stopClause(whenClean: String, whenPartial: String) -> String {
            completedActions.isEmpty ? whenClean : whenPartial
        }
        let reviewItems = (report.inventory ?? []).filter { $0.action == "review" }

        switch stage.stage {
        case "personal-packages":
            let hasReviewItem = (report.inventory ?? []).contains { $0.scope == "personal" && $0.action == "review" }
            if hasReviewItem {
                return HoldingInfo.h4(
                    origin: origin,
                    intro: "One of your own spaces on GitHub is set up in a way I don't recognize, so I left it exactly as it is.",
                    framedDetail: framedIfPresentable(stage.detail),
                    reviewItems: reviewItems,
                    stages: report.stages,
                    schemaVersion: report.schemaVersion, stage: stage.stage, result: stage.result, message: stage.detail,
                    completedActions: completedActions, resume: resume
                )
            }
            return h3(
                intro: stopClause(
                    whenClean: "GitHub didn't confirm one of your own spaces, so I stopped before changing anything.",
                    whenPartial: "GitHub didn't confirm one of your own spaces, so I stopped there."
                ),
                framedDetail: framedIfPresentable(stage.detail),
                stage: stage
            )

        case "device-ssh":
            // §3.1/Appendix D.2's gate table, checked in this order: a
            // missing GitHub permission is the person's own real fix (H7),
            // checked BEFORE the held-for-you case (H4) — both can present
            // as `result: "blocked"` on this same stage, and only the CLI's
            // own `registration` token tells them apart, never prose.
            if stage.registration == "not-permitted" {
                return HoldingInfo.h7(
                    origin: origin,
                    schemaVersion: report.schemaVersion, stage: stage.stage, result: stage.result, message: stage.detail
                )
            }
            if stage.config == "held" || stage.key == "incomplete" {
                return HoldingInfo.h4(
                    origin: origin,
                    intro: "This Mac already has a GitHub connection I didn't set up. I checked it, couldn't confirm it's safe to build on, and left it exactly as it is.",
                    reviewItems: reviewItems,
                    stages: report.stages,
                    schemaVersion: report.schemaVersion, stage: stage.stage, result: stage.result, message: stage.detail,
                    completedActions: completedActions, resume: resume
                )
            }
            return h3(
                intro: stopClause(
                    whenClean: "I couldn't give this Mac its own key, so I stopped. Nothing that was already here was changed.",
                    whenPartial: "I couldn't give this Mac its own key, so I stopped there."
                ),
                stage: stage
            )

        // Task 210/G-7 (the closed Git-history classifier, claude-copilot
        // task 204): a topology row this Mac cannot safely auto-repair —
        // `ahead`/`diverged`/`diverged-identical`/`local-changes`/
        // `wrong-origin`/`unreadable` — blocks this stage, one row at a
        // time. NONE of those states change on a bare retry: only the
        // repository's own owner, working directly in Git, can move it
        // forward. This used to fall through to the generic `default` fault
        // below (a misleading "couldn't confirm this part of setup, so I
        // stopped" — the SAME shape as a transient failure, offering `Try
        // again` for a block that cannot change). Names the specific
        // repository and its state instead, and is deliberately never
        // retryable, regardless of `resume.safe_to_rerun` — see `retryable`'s
        // own doc comment on `HoldingInfo`.
        case "visible-repositories":
            let blockingLayer = report.layers.first { $0.action == "review" || $0.action == "choose-location" }
            let repositoryPhrase = blockingLayer.map(Self.reviewRepositoryPhrase(for:))
                ?? "One of your Copilot repositories is in a state I can't safely change automatically"
            return h3(
                intro: "\(repositoryPhrase). Resolve it in Git, then run setup again.",
                framedDetail: framedIfPresentable(stage.detail),
                stage: stage,
                retryable: false
            )

        case "layer-manifest":
            if stage.action == "review" {
                return HoldingInfo.h4(
                    origin: origin,
                    intro: "I found settings on this Mac that I didn't set up, so I left them alone.",
                    framedDetail: framedIfPresentable(stage.detail),
                    reviewItems: reviewItems,
                    stages: report.stages,
                    schemaVersion: report.schemaVersion, stage: stage.stage, result: stage.result, message: stage.detail,
                    completedActions: completedActions, resume: resume
                )
            }
            // Not named in the spec's own gate table (only the `review`
            // case is) — defaults to the fault variant per the rule above.
            // NOT VERBATIM SPEC COPY (flagged in the implementation report):
            // no line was given for "layer-manifest blocked, not a review".
            return h3(
                intro: stopClause(
                    whenClean: "I couldn't confirm this part of setup, so I stopped before changing anything.",
                    whenPartial: "I couldn't confirm this part of setup, so I stopped there."
                ),
                stage: stage
            )

        case "secret-store":
            return HoldingInfo.h6(
                origin: origin,
                intro: "Your organization's shared store isn't ready for this Mac yet.",
                stage: stage.stage, result: stage.result, message: stage.detail
            )

        case "codex-plugin":
            let materializeNotBlocked = report.stages.first(where: { $0.stage == "materialize" }).map { $0.result != "blocked" } ?? false
            let intro = "I couldn't finish adding Codex Copilot on this Mac." + (materializeNotBlocked ? " Everything else finished." : "")
            return h3(intro: intro, stage: stage)

        case "materialize":
            let held = stage.held ?? 0
            if held > 0 {
                let countSentence = held == 1 ? "I left one thing of yours untouched." : "I left \(held) things of yours untouched."
                return HoldingInfo.h4(
                    origin: origin,
                    intro: "Some of your own unsaved work is in the way of an update, so I left it alone. \(countSentence)",
                    reviewItems: reviewItems,
                    stages: report.stages,
                    schemaVersion: report.schemaVersion, stage: stage.stage, result: stage.result, message: stage.detail,
                    completedActions: completedActions, resume: resume
                )
            }
            return h3(
                intro: stopClause(
                    whenClean: "Setting things up on this Mac didn't finish. Nothing that was already here was changed.",
                    whenPartial: "Setting things up on this Mac didn't finish."
                ),
                stage: stage
            )

        default:
            // `organization-handoff` never blocks (a handoff failure
            // arrives as exit-2 `onboard-unavailable`, handled separately,
            // per the spec's own note) — a genuinely unrecognized stage id
            // still defaults to the fault variant, never a fabricated H4.
            return h3(
                intro: stopClause(
                    whenClean: "I couldn't confirm this part of setup, so I stopped before changing anything.",
                    whenPartial: "I couldn't confirm this part of setup, so I stopped there."
                ),
                stage: stage
            )
        }
    }

    /// Task 210/G-7: maps a blocked topology row's CLI-computed `sync_state`
    /// (the closed Git-history classifier's own vocabulary — never a raw
    /// Git/stderr string) onto a plain, specific sentence naming which
    /// repository needs the owner's own Git resolution and what state it's
    /// in. Parses ONLY `sync_state` and `repository_name`; invents nothing
    /// else and never renders the CLI's raw `detail` here (that stays in
    /// the support block's `Message:` line, same discipline as every other
    /// H3 branch).
    nonisolated static func reviewRepositoryPhrase(for layer: EcosystemOnboardLayer) -> String {
        let name = (layer.repositoryName?.isEmpty == false) ? layer.repositoryName! : "One of your Copilot repositories"
        switch layer.syncState {
        case "ahead":
            return "\(name) has local work the pinned version doesn't include"
        case "diverged":
            return "\(name)'s history has diverged from the pinned version, and the content is different"
        case "diverged-identical":
            return "\(name)'s history has diverged from the pinned version, though the content is the same"
        case "local-changes":
            return "\(name) has local changes that haven't been saved to GitHub yet"
        case "wrong-origin":
            return "\(name) is connected to a different GitHub repository than expected"
        case "unreadable":
            return "\(name) couldn't be read as a Git repository"
        default:
            return "\(name) is in a state I can't safely change automatically"
        }
    }

    func continueFromDetect() {
        guard case .detected = phase else { return }
        phase = .whatYoureGetting
    }

    // MARK: One question first (adopt-and-project-setup spec)

    func toggleOnboardSelection(_ id: String) {
        if onboardSelections.contains(id) {
            onboardSelections.remove(id)
        } else {
            onboardSelections.insert(id)
        }
    }

    var canIncludeOnboardSelections: Bool { !onboardSelections.isEmpty }

    /// "Include what I have" — sends exactly the checked rows back as
    /// `--adopt-existing`; every cleared row is declined for this run (the
    /// spec's own rule: "no all-or-nothing choice"). Answered once; the
    /// question never reappears this session unless Holding's "Include
    /// what I already have" explicitly reopens it.
    func includeOnboardSelections() {
        onboardQuestionAnswered = true
        let components = onboardSelections.compactMap(Self.componentId(fromPersonalInventoryId:))
        // Defense in depth, not the primary fix: `personalOnboardQuestion(from:)`
        // already excludes any row `componentId` can't map from `ask`, so
        // `onboardSelections` (built only from `onboardQuestionItems`, i.e.
        // `ask`) should never contain an unmappable id by construction. If
        // this ever fires, some OTHER code path put an id here the token map
        // doesn't cover — loud in dev/test builds rather than a silently
        // dropped consent (copy spec Appendix D.3's "Bug 2", for a future id).
        assert(
            components.count == onboardSelections.count,
            "componentId(fromPersonalInventoryId:) returned nil for a selected ask-row id — personalOnboardQuestion(from:) should have kept it out of the ask list entirely"
        )
        adoptExisting.formUnion(components)
        performDetect(replanning: true)
    }

    /// "Not now" — every question row is declined for this run; nothing is
    /// added to `adoptExisting`.
    func declineOnboardQuestion() {
        onboardQuestionAnswered = true
        performDetect(replanning: true)
    }

    /// Holding's "Include what I already have" — returns to the question
    /// "with the previous selections intact" (the spec's own words):
    /// `onboardSelections` is deliberately left untouched.
    func returnToOnboardQuestion() {
        onboardQuestionAnswered = false
        phase = .onboardQuestion
    }

    // MARK: What you're getting (#w4)

    func toggleIncludeCodex() {
        includeCodex.toggle()
    }

    func continueFromWhatYoureGetting() {
        phase = .departments
        loadDepartments()
    }

    // MARK: Departments (#w5)

    /// `layers() -> rows per entry`. A `layers()` call that itself fails is
    /// folded into the same empty-list copy as a genuinely empty
    /// entitlement list (never a Holding interruption or a raw error) —
    /// Departments' own footer already offers "Skip for now", and joining
    /// something you can see essentially always works per the spec; a
    /// transient read failure here is not treated as gravely as Detect's or
    /// Verify's CliErrors.
    private func loadDepartments() {
        Task {
            switch await CliClient.shared.layers() {
            case .success(let report):
                self.departments = report.layers.map { entry in
                    DepartmentRow(id: entry.id, name: entry.name, state: self.joinState(for: entry))
                }
            case .failure:
                self.departments = []
            }
        }
    }

    private func joinState(for entry: LayerEntry) -> DepartmentJoinState {
        if entry.joined { return .joined }
        if entry.entitled == true { return .availableToJoin }
        if entry.reason == .offline { return .waitingForNetwork }
        return .notAvailable(caption: "Not available to you")
    }

    func joinDepartment(_ id: String) {
        guard let index = departments.firstIndex(where: { $0.id == id }) else { return }
        guard departments[index].state == .availableToJoin else { return }
        departments[index].state = .joining
        Task {
            let result = await CliClient.shared.layersJoin(id: id)
            guard let idx = self.departments.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case .success(let join):
                switch join.result {
                case .joined, .alreadyJoined:
                    self.departments[idx].state = .joined
                case .notEntitled:
                    // The quiet revoked-race outcome, per the spec: "isn't
                    // available to you anymore", never rendered as an error.
                    self.departments[idx].state = .notAvailable(caption: "Isn't available to you anymore.")
                case .offline:
                    self.departments[idx].state = .waitingForNetwork
                case .error:
                    self.departments[idx].state = .notAvailable(caption: "Not available to you")
                }
            case .failure:
                self.departments[idx].state = .notAvailable(caption: "Not available to you")
            }
        }
    }

    func continueFromDepartments() {
        phase = .integrations
        loadConnections()
    }

    // MARK: Integrations (#w6)

    /// `connections()` -- real CLI seam (task 221 bridge stage C). A failed
    /// call (including an installed `cc` build that predates the verb) is
    /// folded into `.failed`, never a Holding interruption: the GitHub card
    /// and Continue action both work regardless of this call's outcome, same
    /// non-blocking discipline `loadDepartments()` above already uses for
    /// `layers()`.
    private func loadConnections() {
        connectionsState = .loading
        Task {
            switch await CliClient.shared.connections() {
            case .success(let report):
                self.connectionsState = .loaded(report)
            case .failure(let error):
                self.connectionsState = .failed(error)
            }
        }
    }

    /// Re-reads the roster after the Connect sheet reports the CLI made a
    /// change (task 222). Deliberately the SAME call step 6 made on entry —
    /// never a narrower "just this row" patch — so what the screen shows
    /// after a write is a fresh answer from the CLI, not this app's belief
    /// about what its own write should have done.
    func refreshConnections() {
        loadConnections()
    }

    func skipIntegrations() {
        enterProjectsStep()
    }

    func continueFromIntegrations() {
        enterProjectsStep()
    }

    // MARK: Step 7, Your projects (adopt-and-project-setup spec)

    /// Loads folder-grant state (`workspace roots`) and, if at least one
    /// folder is already granted, the discovered project list
    /// (`workspace --all`) — same read-only calls the menu bar uses,
    /// nothing written here. Runs once per wizard visit to this step
    /// (`hasLoadedProjectsStep`); the sidebar's own "completed rows are
    /// tappable, read-only" review affordance re-enters this phase without
    /// re-fetching.
    func enterProjectsStep() {
        phase = .projects
        guard !hasLoadedProjectsStep else { return }
        hasLoadedProjectsStep = true
        loadProjectsStep()
    }

    private func loadProjectsStep() {
        projectsLoading = true
        Task {
            defer { self.projectsLoading = false }
            guard case .success(let rootsReport) = await CliClient.shared.workspaceRoots() else { return }
            self.projectRoots = rootsReport.roots ?? []
            self.projectRootCandidates = rootsReport.candidates ?? []
            guard !self.projectRoots.isEmpty else { return }
            await self.loadProjectWorkspaces()
        }
    }

    private func loadProjectWorkspaces() async {
        projectMigrationLoading = true
        async let workspacesResult = CliClient.shared.workspaces()
        async let migrationResult = CliClient.shared.workspaceMigrationPlan()
        let (workspaceOutcome, migrationOutcome) = await (workspacesResult, migrationResult)
        defer { projectMigrationLoading = false }

        switch migrationOutcome {
        case .success(let report):
            projectMigrationReport = report
            projectMigrationError = nil
        case .failure:
            projectMigrationReport = nil
            projectMigrationError = "The grouped project update isn't available right now. You can still review projects one at a time."
        }

        guard case .success(let report) = workspaceOutcome else { return }
        self.projectWorkspaces = report.workspaces
        self.projectsSummary = report.summary
        if let category = self.selectedProjectCategory,
           ProjectTriageRender.workspaces(report.workspaces, in: category).isEmpty {
            self.selectedProjectCategory = nil
        }
        // A discovered project is never consent. Start with no selections;
        // the person chooses from rows the CLI says are safe to apply now.
        self.selectedProjectPaths = Self.preselectedProjectPaths(from: report.workspaces)
    }

    /// Pure: project setup is always opt-in. This takes the rows so the
    /// selftest can prove the policy against real decoded input, but no row
    /// starts checked.
    static func preselectedProjectPaths(from workspaces: [WorkspaceEntry]) -> Set<String> {
        _ = workspaces
        return []
    }

    /// Pure: a setup-needed state is only a real action when the CLI's
    /// preflight also says it can be applied now. `setupAvailable` alone is
    /// not permission to ignore `can_apply_now`.
    static func actionableProjectPaths(from workspaces: [WorkspaceEntry]) -> Set<String> {
        Set(workspaces.filter {
            $0.classification == .safeFinish
                && $0.canApplyNow
                && $0.safeAction != nil
        }.map(\.path))
    }

    func reviewProjectIntegration(_ workspace: WorkspaceEntry) {
        projectIntegrationDetail = workspace
        projectIntegrationMessage = nil
        if workspace.planAvailable
            || workspace.classification == .couldNotVerify
            || workspace.classification == .ready {
            Task {
                let result = workspace.planAvailable
                    ? await CliClient.shared.workspaceIntegrationPlan(path: workspace.path)
                    : await CliClient.shared.workspace(path: workspace.path)
                switch result {
                case .success(let report):
                    self.projectIntegrationDetail = report.workspaces.first ?? workspace
                case .failure:
                    self.projectIntegrationMessage = workspace.planAvailable
                        ? "The project plan hasn't come through yet. Nothing was changed."
                        : "The latest project evidence hasn't come through yet. Nothing was changed."
                }
            }
        }
    }

    func dismissProjectIntegrationReview() {
        projectIntegrationDetail = nil
        projectIntegrationMessage = nil
    }

    func showProjectOverview() {
        projectIntegrationDetail = nil
        projectIntegrationMessage = nil
        projectMigrationReviewOpen = false
        selectedProjectCategory = nil
    }

    func showProjectCategory(_ category: ProjectTriageCategory) {
        projectIntegrationDetail = nil
        projectIntegrationMessage = nil
        projectMigrationReviewOpen = false
        selectedProjectCategory = category
    }

    func reviewBulkProjectMigration() {
        guard let report = projectMigrationReport,
              report.summary.eligible > 0,
              !projectMigrationApplying else { return }
        projectMigrationApplyReport = nil
        projectMigrationError = nil
        projectMigrationReviewOpen = true
    }

    func dismissBulkProjectMigrationReview() {
        projectMigrationReviewOpen = false
    }

    func dismissBulkProjectMigrationResult() {
        projectMigrationApplyReport = nil
        projectMigrationReviewOpen = false
    }

    func refreshBulkProjectMigration() {
        guard !projectMigrationApplying else { return }
        projectMigrationApplyReport = nil
        projectMigrationReport = nil
        projectMigrationError = nil
        projectMigrationLoading = true
        Task { await self.loadProjectWorkspaces() }
    }

    func applyBulkProjectMigration() {
        guard let report = projectMigrationReport,
              report.summary.eligible > 0,
              !projectMigrationApplying else { return }
        let reviewedPlanId = report.planId
        projectMigrationApplying = true
        projectMigrationError = nil
        Task {
            defer { self.projectMigrationApplying = false }
            switch await CliClient.shared.applyWorkspaceMigration(planId: reviewedPlanId) {
            case .success(let applied):
                self.projectMigrationApplyReport = applied
                self.projectMigrationReviewOpen = false
                await self.loadProjectWorkspaces()
            case .failure:
                self.projectMigrationError = "Control Tower couldn't start the grouped update. Nothing was confirmed as changed. Check again and review the fresh plan before trying again."
            }
        }
    }

    func includeSafeProject(_ workspace: WorkspaceEntry) {
        guard Self.actionableProjectPaths(from: [workspace]).contains(workspace.path) else { return }
        selectedProjectPaths.insert(workspace.path)
        dismissProjectIntegrationReview()
    }

    func copyProjectIntegrationPrompt(_ workspace: WorkspaceEntry) {
        guard let prompt = workspace.integrationPlan?.prompt?.text else { return }
        projectIntegrationMessage = ProjectIntegrationLauncher.copy(prompt)
            ? "Integration prompt copied. This project remains incomplete until CLI verification passes."
            : "The prompt couldn't be copied. Nothing in the project was changed."
    }

    func copyProjectDiagnosticReport(_ workspace: WorkspaceEntry) {
        projectIntegrationMessage = ProjectIntegrationLauncher.copy(
            ProjectTriageRender.diagnosticReport(workspace)
        )
            ? "Diagnostic report copied. Use Check again after the project setup changes."
            : "The diagnostic report couldn't be copied. Nothing in the project was changed."
    }

    func bringTerminalForward() {
        ProjectIntegrationLauncher.bringTerminalForward()
    }

    func openProjectIntegrationAssistant(
        _ assistant: ProjectIntegrationLauncher.Assistant,
        workspace: WorkspaceEntry
    ) {
        guard let prompt = workspace.integrationPlan?.prompt?.text else { return }
        let result = ProjectIntegrationLauncher.open(
            assistant,
            projectPath: workspace.path,
            prompt: prompt
        )
        switch result {
        case .openedInTerminal:
            pendingProjectVerificationPath = workspace.path
            projectIntegrationMessage = "\(assistant.displayName) is running in Terminal. Watch it there or continue setup; Control Tower will verify the project when you return."
        case .assistantUnavailable:
            projectIntegrationMessage = "\(assistant.displayName) isn't available in Terminal. The guided prompt was copied, and nothing in the project was changed."
        case .projectUnavailable:
            projectIntegrationMessage = "The project folder isn't available anymore. The guided prompt was copied, and nothing was changed."
        case .automationPermissionDenied:
            projectIntegrationMessage = "Control Tower needs permission to run guided setup in Terminal. Allow Terminal under System Settings → Privacy & Security → Automation, then try again. The prompt was copied, and nothing was changed."
        case .terminalUnavailable:
            projectIntegrationMessage = "Terminal couldn't start the guided session. The prompt was copied, and nothing in the project was changed."
        }
    }

    func openProjectDiagnosticAssistant(
        _ assistant: ProjectIntegrationLauncher.Assistant,
        workspace: WorkspaceEntry
    ) {
        guard let diagnostic = workspace.diagnostic,
              diagnostic.mode == "read-only" else { return }
        let result = ProjectIntegrationLauncher.open(
            assistant,
            projectPath: workspace.path,
            prompt: diagnostic.prompt.text
        )
        switch result {
        case .openedInTerminal:
            pendingProjectVerificationPath = workspace.path
            projectIntegrationMessage = "\(assistant.displayName) is diagnosing in read-only mode in Terminal. Nothing may change in the project; Control Tower will check the project when you return."
        case .assistantUnavailable:
            projectIntegrationMessage = "\(assistant.displayName) isn't available in Terminal. The read-only diagnostic prompt was copied, and nothing in the project was changed."
        case .projectUnavailable:
            projectIntegrationMessage = "The project folder isn't available anymore. The read-only diagnostic prompt was copied, and nothing was changed."
        case .automationPermissionDenied:
            projectIntegrationMessage = "Control Tower needs permission to run the diagnosis in Terminal. Allow Terminal under System Settings → Privacy & Security → Automation, then try again. The prompt was copied, and nothing was changed."
        case .terminalUnavailable:
            projectIntegrationMessage = "Terminal couldn't start the read-only diagnostic session. The prompt was copied, and nothing in the project was changed."
        }
    }

    func prepareProjectOwnerHandoff(_ workspace: WorkspaceEntry) {
        guard let plan = workspace.integrationPlan,
              let handoff = plan.ownerHandoff?.text else { return }
        let copied = ProjectIntegrationLauncher.copy(handoff)
        guard copied else {
            projectIntegrationMessage = "The handoff couldn't be copied. Nothing in the project was changed."
            return
        }
        Task {
            _ = await CliClient.shared.holdWorkspaceIntegration(
                path: workspace.path,
                planId: plan.id
            )
            self.projectIntegrationMessage = "Project-owner handoff copied. Nothing in the project was changed."
        }
    }

    func verifyProjectIntegration(_ workspace: WorkspaceEntry) {
        projectIntegrationMessage = "Verifying Claude, Codex, and the preserved project contract…"
        Task {
            switch await CliClient.shared.verifyWorkspace(path: workspace.path) {
            case .success(let report):
                if let updated = report.workspaces.first {
                    self.projectIntegrationDetail = updated
                    self.projectIntegrationMessage = updated.classification == .ready
                        ? "Verified Ready. Claude, Codex, and the project contract passed."
                        : updated.detail
                    await self.loadProjectWorkspaces()
                }
            case .failure:
                self.projectIntegrationMessage = "Verification hasn't come through. The project remains incomplete."
            }
        }
    }

    func verifyPendingProjectOnReturn() {
        guard let path = pendingProjectVerificationPath else { return }
        pendingProjectVerificationPath = nil
        guard let workspace = projectWorkspaces.first(where: { $0.path == path })
                ?? (projectIntegrationDetail?.path == path ? projectIntegrationDetail : nil) else { return }
        verifyProjectIntegration(workspace)
    }

    func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the one folder where your projects live. Control Tower looks only inside that folder, and never anywhere else on this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        approveProjectsRoot(path: url.path)
    }

    func chooseCopilotRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        panel.message = "Choose the visible folder where Knowledge, CLI, Claude, and Codex Copilot repositories should live."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        copilotRepositoryRoot = url.path
        performDetect(replanning: true)
    }

    func approveCandidateRoot(_ candidate: WorkspaceRootCandidate) {
        approveProjectsRoot(path: candidate.path)
    }

    private func approveProjectsRoot(path: String) {
        projectsLoading = true
        projectsFolderBlockedDetail = nil
        Task {
            defer { self.projectsLoading = false }
            switch await CliClient.shared.approveWorkspaceRoot(path: path) {
            case .success(let report) where report.result == .blocked:
                self.projectsFolderBlockedDetail = report.root.detail
                return
            case .failure:
                return
            default:
                break
            }
            self.projectsDeclined = false
            self.projectsDeclineConfirmed = false
            guard case .success(let rootsReport) = await CliClient.shared.workspaceRoots() else { return }
            self.projectRoots = rootsReport.roots ?? []
            self.projectRootCandidates = rootsReport.candidates ?? []
            await self.loadProjectWorkspaces()
        }
    }

    func stopWatchingProjectsRoot(_ root: WorkspaceRootListEntry) {
        projectsLoading = true
        Task {
            defer { self.projectsLoading = false }
            guard case .success = await CliClient.shared.forgetWorkspaceRoot(path: root.path) else { return }
            guard case .success(let rootsReport) = await CliClient.shared.workspaceRoots() else { return }
            self.projectRoots = rootsReport.roots ?? []
            self.projectRootCandidates = rootsReport.candidates ?? []
            if self.projectRoots.isEmpty {
                self.projectWorkspaces = []
                self.projectsSummary = nil
                self.selectedProjectPaths = []
                self.selectedProjectCategory = nil
            } else {
                await self.loadProjectWorkspaces()
            }
        }
    }

    /// "I don't keep projects on this Mac" — records the decline so the
    /// menu bar never offers this again, and confirms inline (never
    /// auto-advances; the person still chooses Continue).
    func declineProjects() {
        Task {
            guard case .success = await CliClient.shared.declineWorkspaces() else { return }
            self.projectsDeclined = true
            self.projectsDeclineConfirmed = true
        }
    }

    func toggleProjectSelection(_ path: String) {
        guard Self.actionableProjectPaths(from: projectWorkspaces).contains(path) else {
            selectedProjectPaths.remove(path)
            return
        }
        if selectedProjectPaths.contains(path) {
            selectedProjectPaths.remove(path)
        } else {
            selectedProjectPaths.insert(path)
        }
    }

    func selectAllProjects() {
        selectedProjectPaths = Self.actionableProjectPaths(from: projectWorkspaces)
    }

    func selectNoProjects() {
        selectedProjectPaths = []
    }

    func backFromProjects() {
        phase = .integrations
    }

    /// "Skip for now" — leaves the offer available in the menu bar; behaves
    /// exactly like Continue with nothing selected, since a folder that was
    /// never granted has nothing to set up regardless.
    func skipProjectsForNow() {
        selectedProjectPaths = []
        beginMaterialize()
    }

    func continueFromProjects() {
        beginMaterialize()
    }

    // MARK: Set up (Step 8 of 9) — honest progress, no timer

    /// Calls `ecosystemOnboardApply()` for real; also calls `updateFanout()`
    /// (fire-and-forget, non-gating) when at least one department was
    /// joined this session, since a fan-out sweep is only warranted once
    /// there is more than the default org layer to reconcile across. Every
    /// row in `setupProgress` is set only from that call's own real result
    /// (`WizardModel.resolveStageRows(from:)`) or from each project's own
    /// real `finishWorkspace` outcome (`applySelectedProjects` below) —
    /// nothing here is ever paced by a sleep (see the progress-and-waiting
    /// spec's own architecture decision, "Advancing the count by elapsed
    /// time... is precisely what is being removed").
    func beginMaterialize() {
        guard !materializeInFlight else { return }
        materializeInFlight = true
        phase = .materializing
        projectSetupNeedsDecision = false
        failedProjectPaths = []

        if projectsDeclined {
            projectsStepOutcome = .declined
        } else if selectedProjectPaths.isEmpty {
            projectsStepOutcome = .skipped
        }

        // The same order and names the person just read in "Your projects"
        // (Step 7) — `projectWorkspaces` is the CLI's own list order,
        // never `selectedProjectPaths`' own (unordered) `Set` iteration
        // order.
        let orderedProjects = projectWorkspaces.filter { selectedProjectPaths.contains($0.path) }

        var progress = SetupProgressState()
        progress.callRow.state = .working(startedAt: Date())
        progress.projectRows = orderedProjects.map { SetupRow(id: $0.path, title: $0.name) }
        let shouldFanOut = !joinedDepartments.isEmpty
        progress.isFanningOut = shouldFanOut
        setupProgress = progress

        Task {
            switch await CliClient.shared.ecosystemOnboardApply(
                products: self.copilotProducts,
                adoptExisting: Array(self.adoptExisting),
                repositoryRoot: self.copilotRepositoryRoot
            ) {
            case .success(let report):
                guard report.result == .ready else {
                    self.materializeInFlight = false
                    self.enterHolding(Self.holdingInfo(forBlockedOnboard: report, origin: .materialize))
                    return
                }
                self.ecosystemInventory = report.inventory ?? self.ecosystemInventory
                self.ecosystemInventorySummary = report.inventorySummary ?? self.ecosystemInventorySummary
                self.ecosystemLayers = report.layers
                self.adoptionRollbackPaths = report.stages.compactMap(\.rollbackPath)
                self.setupProgress.callRow.state = .done(detail: "Done.")
                self.setupProgress.stageRows = Self.resolveStageRows(from: report.stages)
                self.lastOnboardResult = report.result
                self.lastOnboardStages = report.stages
                self.lastCompletedActions = report.completedActions
                self.lastResume = report.resume
            case .failure(let error):
                self.materializeInFlight = false
                self.routeCliError(error, origin: .materialize)
                return
            }
            if shouldFanOut {
                Task { _ = await CliClient.shared.updateFanout() }
            }
            if !orderedProjects.isEmpty {
                let failures = await self.applySelectedProjects(orderedProjects)
                if Self.projectSetupRequiresDecision(failureCount: failures) {
                    self.materializeInFlight = false
                    self.projectSetupNeedsDecision = true
                    return
                }
            }
            self.materializeInFlight = false
            self.beginVerify()
        }
    }

    /// "Per-project failure is collected, never fatal, and never retried
    /// silently" (Step 8's own rule): one project failing to configure never
    /// stops the rest, and Done (below) never claims full success when it
    /// was not. Runs the copilots this project's setup copies from already
    /// exist on this Mac by this point (the ecosystem apply above just
    /// finished), matching `can_apply_now`'s own contract. Genuinely
    /// sequential — `setupProgress.projectRows` is updated live, one row at
    /// a time, as each real call actually resolves (spec §5: "these resolve
    /// one at a time, because the loop really is sequential").
    private func applySelectedProjects(_ projects: [WorkspaceEntry]) async -> Int {
        var succeeded = 0
        var failures = 0

        // Re-read the CLI immediately before any project write. A project
        // can change after the selection screen; stale eligibility never
        // becomes permission to write.
        guard case .success(let freshReport) = await CliClient.shared.workspaces() else {
            for index in projects.indices {
                let workspace = projects[index]
                failedProjectPaths.insert(workspace.path)
                setupProgress.projectRows[index].state = .couldNotFinish(
                    detail: "Control Tower couldn't reread this project's setup, so it did not make a change. Try again when the setup helper is available."
                )
            }
            projectsStepOutcome = .setUp(succeeded: 0, total: projects.count)
            return projects.count
        }
        let freshByPath = Dictionary(uniqueKeysWithValues: freshReport.workspaces.map { ($0.path, $0) })

        for (index, selectedWorkspace) in projects.enumerated() {
            guard let workspace = freshByPath[selectedWorkspace.path] else {
                failures += 1
                failedProjectPaths.insert(selectedWorkspace.path)
                setupProgress.projectRows[index].state = .couldNotFinish(
                    detail: "Control Tower couldn't find this project in the approved folder anymore, so it did not make a change. Return to Your projects and choose again."
                )
                continue
            }
            guard Self.actionableProjectPaths(from: [workspace]).contains(workspace.path) else {
                failures += 1
                failedProjectPaths.insert(workspace.path)
                let reason = workspace.applyBlockedDetail ?? workspace.detail
                setupProgress.projectRows[index].state = .couldNotFinish(
                    detail: "\(reason) Ask the person who manages this project to review its existing Copilot setup."
                )
                continue
            }

            setupProgress.projectRows[index].state = .working(startedAt: Date())
            guard let action = workspace.safeAction else {
                failures += 1
                failedProjectPaths.insert(workspace.path)
                setupProgress.projectRows[index].state = .couldNotFinish(
                    detail: "The setup helper did not provide a safe action for this project, so Control Tower made no change."
                )
                continue
            }
            let result = await CliClient.shared.finishWorkspace(
                path: workspace.path,
                actionId: action.id,
                apply: true
            )
            if case .success(let report) = result,
               let updated = report.workspaces.first(where: { $0.path == workspace.path }),
               updated.classification == .ready {
                succeeded += 1
                setupProgress.projectRows[index].state = .done(detail: updated.detail)
            } else {
                failures += 1
                failedProjectPaths.insert(workspace.path)
                let detail: String
                if case .success(let report) = result,
                   let updated = report.workspaces.first(where: { $0.path == workspace.path }) {
                    detail = "\(updated.detail) Control Tower stopped on this project. Review it with the person who manages its Copilot setup, then try again."
                } else {
                    detail = "Control Tower couldn't read a trustworthy result, so it did not claim this project was set up. Ask your support team to check this project before trying again."
                }
                setupProgress.projectRows[index].state = .couldNotFinish(
                    detail: detail
                )
            }
        }
        self.projectsStepOutcome = .setUp(succeeded: succeeded, total: projects.count)
        return failures
    }

    nonisolated static func projectSetupRequiresDecision(failureCount: Int) -> Bool {
        failureCount > 0
    }

    func retryFailedProjects() {
        guard projectSetupNeedsDecision, !failedProjectPaths.isEmpty else { return }
        selectedProjectPaths = failedProjectPaths
        beginMaterialize()
    }

    func returnToFailedProjects() {
        guard projectSetupNeedsDecision else { return }
        selectedProjectPaths = failedProjectPaths
        projectSetupNeedsDecision = false
        phase = .projects
    }

    func continueWithoutFailedProjects() {
        guard projectSetupNeedsDecision else { return }
        projectSetupNeedsDecision = false
        beginVerify()
    }

    private var copilotProducts: [String] {
        includeCodex ? ["claude", "codex"] : ["claude"]
    }

    // MARK: Verify (#w8)

    /// `doctor() -> healthy: "Everything checks out." + Continue; anything
    /// non-confirmable -> Holding` — never fakes a pass, per the task
    /// contract.
    func beginVerify() {
        phase = .verifying
        Task {
            async let doctorResult = CliClient.shared.doctor()
            async let workspacesResult = CliClient.shared.workspaces()
            let doctorOutcome = await doctorResult
            let workspacesOutcome = await workspacesResult
            if case .success(let report) = workspacesOutcome {
                self.verifiedWorkspacesReport = report
            }
            switch doctorOutcome {
            case .success(let doctor):
                self.verifiedCopilotState = RenderState.from(doctor, joinable: nil)
                if doctor.status == .healthy {
                    self.phase = .verified
                } else {
                    self.enterHolding(Self.holdingInfo(forNonHealthy: doctor, origin: .verify))
                }
            case .failure(let error):
                self.routeCliError(error, origin: .verify)
            }
        }
    }

    /// H5 (offline) or H3 (any other non-healthy status) — never fakes a
    /// pass. `doctor` is not one of `EcosystemOnboardStage`'s stages; this
    /// reads `DoctorReport.status`/`.offline` directly, per the copy spec's
    /// own `doctor` gate row (§3).
    nonisolated static func holdingInfo(forNonHealthy doctor: DoctorReport, origin: WizardStage) -> HoldingInfo {
        if doctor.offline {
            return HoldingInfo.h5Offline(origin: origin)
        }
        // Same reasoning as Detect's currency line above: reuse the
        // already-computed, per-status sentence rather than a second
        // derivation.
        let sentence = RenderState.from(doctor, joinable: nil).header.sentence
        return HoldingInfo.h3(
            origin: origin,
            title: "I couldn't confirm everything's current",
            intro: sentence,
            schemaVersion: doctor.schemaVersion
        )
    }

    /// Finish setup — sets the completed-first-run flag and closes the window
    /// (the actual `window?.close()` is `onClose()`, owned by
    /// `WizardWindowController`).
    func finish(onClose: () -> Void) {
        // See `LocalDefaults`'s own doc comment (`native/models.swift`) on
        // why this isn't `UserDefaults.standard`.
        LocalDefaults.set(true, forKey: "ct.hasCompletedFirstRun")
        onClose()
    }

    // MARK: Holding (#w10)

    func tryAgainAfterHolding() {
        guard case .holding(let info) = phase else { return }
        switch info.origin {
        case .connectGitHub: beginDeviceFlow()
        case .detect: runDetect()
        case .departments:
            phase = .departments
            loadDepartments()
        case .materialize:
            materializeInFlight = false
            beginMaterialize()
        case .verify: beginVerify()
        default: phase = .welcome
        }
    }

    /// H4's `Keep what I have` (§2.9): session-only, no CLI call, no write.
    /// Swaps the CURRENT hold's body for the §2.10 "Here's where that
    /// leaves you" confirmation on this SAME screen (no new window), and
    /// remembers this exact hold so it is not asked again this session
    /// (`acknowledgedHoldingSignatures`).
    func keepWhatIHave() {
        guard case .holding(let info) = phase, info.variant == .yours else { return }
        acknowledgedHoldingSignatures.insert(info.signature)
        holdingConfirmed = true
    }

    private func enterHolding(_ info: HoldingInfo) {
        pollTask?.cancel()
        var info = info
        info.isRepeat = (lastHoldingSignature == info.signature)
        lastHoldingSignature = info.signature
        holdingConfirmed = acknowledgedHoldingSignatures.contains(info.signature)
        phase = .holding(info)
    }

    // MARK: H7 — granting a missing GitHub permission (§2.9.3)

    /// `Grant this on GitHub` (H7's primary): starts the SAME device-flow
    /// ceremony Connect GitHub already uses, against `cc auth grant --json`.
    /// A response this app can't use for real — launch/decode failure
    /// (including the verb not existing at all on this Mac's installed CLI)
    /// — resolves to `.unavailable`
    /// rather than ever leaving the sheet spinning or showing a broken code
    /// (holding-copy-spec H7: "must not render a button that does
    /// nothing"). Called with the sheet ALREADY about to open (`h7View`'s
    /// primary sets `showsGrantSheet = true` in the same action), so
    /// `.pending`'s brief empty state is honest, real "waiting on the CLI"
    /// time, not a fabricated delay.
    func beginGrantFlow() {
        grantPollTask?.cancel()
        grantFlow = GrantFlowState(status: .pending)
        Task {
            switch await CliClient.shared.authGrantInitiate() {
            case .success(let start):
                guard start.kind == "grant-device-code",
                      start.permission == "write:public_key"
                else {
                    self.handleGrantUnavailable()
                    return
                }
                self.grantFlow.userCode = start.userCode
                self.grantFlow.verificationUri = start.verificationUri
                self.grantFlow.deviceCode = start.deviceCode
                self.grantFlow.interval = start.interval
                self.startGrantPolling(
                    deviceCode: start.deviceCode,
                    interval: start.interval,
                    expiresIn: start.expiresIn
                )
            case .failure:
                self.handleGrantUnavailable()
            }
        }
    }

    private func handleGrantUnavailable() {
        grantFlow.status = .unavailable
        grantUnavailableKnown = true
    }

    private func startGrantPolling(
        deviceCode: String,
        interval: Int,
        expiresIn: Int
    ) {
        let deadline = Date().addingTimeInterval(
            TimeInterval(max(expiresIn, 1))
        )
        let waitSeconds = UInt64(max(interval, 1))
        grantPollTask = Task { [weak self] in
            while true {
                if Task.isCancelled { return }
                guard let self else { return }
                if Date() >= deadline {
                    self.grantFlow.status = .timedOut
                    return
                }
                try? await Task.sleep(nanoseconds: waitSeconds * 1_000_000_000)
                if Task.isCancelled { return }
                switch await CliClient.shared.authGrantPoll(deviceCode: deviceCode) {
                case .success(let poll):
                    guard poll.kind == "grant-poll" else {
                        self.handleGrantUnavailable()
                        return
                    }
                    switch poll.status {
                    case .granted:
                        self.grantFlow.status = .granted
                        return
                    case .denied:
                        self.grantFlow.status = .denied
                        return
                    case .expired:
                        self.grantFlow.status = .expired
                        return
                    case .identityMismatch:
                        self.grantFlow.status = .identityMismatch
                        return
                    case .insufficientScope:
                        self.grantFlow.status = .insufficientScope
                        return
                    case .pending:
                        continue
                    }
                case .failure:
                    self.handleGrantUnavailable()
                    return
                }
            }
        }
    }

    func openGrantGitHubPage() {
        guard let raw = grantFlow.verificationUri, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyGrantCode() {
        guard let code = grantFlow.userCode else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
    }

    /// `Try again` (denied) / `Get a new code` (expired/timed out) — same
    /// action, different label per the copy spec's own table.
    func retryGrantFlow() {
        beginGrantFlow()
    }

    func cancelGrantFlow() {
        grantPollTask?.cancel()
        grantFlow = GrantFlowState()
    }

    /// Every `CliError` call site routes through here. Builds the matching
    /// Holding variant and enters it, EXCEPT exit-2 `signed-out`
    /// (`holdingInfo(for:origin:)` returns `nil`) — that one code is not a
    /// hold at all (§2.1: "Do not enter Holding"); this returns to Connect
    /// GitHub's own existing device-flow screen instead.
    private func routeCliError(_ error: CliError, origin: WizardStage) {
        guard let info = Self.holdingInfo(for: error, origin: origin) else {
            pollTask?.cancel()
            phase = .connectGitHub
            beginDeviceFlow()
            return
        }
        enterHolding(info)
    }

    /// The shared `CliError` -> Holding routing used by every call site
    /// (copy spec §2): most decode/launch failures are H1/H2 (nobody's
    /// fault, retry); `exit2`'s CODE selects among H2/H5/H6 (§2.1), or
    /// signals "not a hold" (`nil`, `signed-out`).
    nonisolated static func holdingInfo(for error: CliError, origin: WizardStage) -> HoldingInfo? {
        switch error {
        case .notFound:
            return HoldingInfo.h1(origin: origin)
        case .launchFailed:
            return HoldingInfo.h2(origin: origin, intro: "The setup helper is on this Mac, but it wouldn't start just now, so I won't guess.")
        case .parse:
            return HoldingInfo.h2(origin: origin, intro: "I can't read what's already on this Mac right now, so I won't guess.")
        case .schemaOutOfRange:
            return HoldingInfo.h2(origin: origin, intro: "Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up.")
        case .missingSecurityField:
            // Never offers a way past itself (invariant #4) — same H2
            // shell, no consent-style action is ever added to this one.
            return HoldingInfo.h2(origin: origin, intro: "I can't confirm your setup is safe right now, so I'm holding off rather than guess.")
        case .exit2(let code, let message):
            return holdingInfo(forExit2Code: code, message: message, origin: origin)
        }
    }

    /// §2.1's routing table. The code string itself never appears outside
    /// the support block (never in the title, body, or a caption).
    private nonisolated static func holdingInfo(forExit2Code code: String, message: String, origin: WizardStage) -> HoldingInfo? {
        switch code {
        case "signed-out":
            return nil
        case "lock-contention":
            return HoldingInfo.h5Busy(origin: origin)
        case "onboard-unavailable":
            return HoldingInfo.h6(
                origin: origin,
                intro: "I couldn't read your organization's setup from GitHub, so I've paused.",
                code: code, message: message
            )
        case "no-company-app":
            // The one H6 cause with a known, already-verified self-serve fix
            // (Defect 1b): when this Mac's own admin standup already ran
            // here, `selfServeOrgSignInCommand()` reads the exact command
            // back from what that standup already wrote, and the owner test
            // (§2.9) reclassifies this from H6 ("the organization; nothing
            // for you to do") to H7 ("yours, real, doable right here").
            // Every OTHER end user, and an admin brief without a readable
            // client id, stays the ordinary H6 below.
            if let command = HoldingInfo.selfServeOrgSignInCommand() {
                return HoldingInfo.h7ForOrgSignIn(origin: origin, command: command, code: code, message: message)
            }
            return HoldingInfo.h6(
                origin: origin,
                intro: "Your organization hasn't finished setting up sign-in yet.",
                code: code, message: message
            )
        case "invalid-manifest":
            return HoldingInfo.h2(origin: origin, intro: "The list of what you get can't be read right now, so I won't guess.", code: code, message: message)
        case "environment-error":
            return HoldingInfo.h2(origin: origin, intro: "Something on this Mac stopped the setup helper, so I've paused.", code: code, message: message)
        case "not-implemented", "unsupported-scope", "invalid-argument":
            return HoldingInfo.h2(
                origin: origin,
                intro: "Control Tower asked your setup for something it doesn't offer. An update should line them back up.",
                code: code, message: message
            )
        default:
            return HoldingInfo.h2(origin: origin, intro: "Something stopped me from reading your setup, so I won't guess.", code: code, message: message)
        }
    }

    // MARK: Roadmap review (completed rows are tappable, read-only)

    func reviewStage(_ stage: WizardStage) {
        switch stage {
        case .welcome: phase = .welcome
        case .connectGitHub: phase = .connectGitHub
        case .detect: phase = .detected
        case .whatYoureGetting: phase = .whatYoureGetting
        case .departments: phase = .departments
        case .integrations: phase = .integrations
        case .projects: phase = .projects
        case .materialize: phase = .materializing
        case .verify: phase = .verified
        }
    }
}

/// Applies a VoiceOver focus binding to its content when one is supplied,
/// and a no-op otherwise — lets `StepShell` take an OPTIONAL
/// `AccessibilityFocusState<Bool>.Binding` (only the Holding views pass one,
/// per `holding-copy-spec.md` §7) without every other step having to opt in
/// or out explicitly.
private struct TitleAccessibilityFocus: ViewModifier {
    let binding: AccessibilityFocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let binding {
            content
                .accessibilityFocused(binding)
                .onAppear { binding.wrappedValue = true }
        } else {
            content
        }
    }
}

// MARK: - Shared step shell (reused grammar from scripts/publisher_setup.swift's
// StepShell: eyebrow -> title -> intro -> content -> pinned footer action bar)
//
// UNCHANGED PUBLIC SHAPE: `native/admin.swift`/`native/admin-support.swift`
// are heavy consumers of this exact `StepShell(eyebrow:title:intro:content:
// leadingActions:primaryAction:)` init and `.headerTint(_:)` — do not alter
// its signature. The new `focusTitle` param (Holding-only, `holding-copy-spec.md`
// §7) is appended with a default of `nil`, so every existing call site in
// those two files is unaffected.

struct StepShell<Content: View, Leading: View, Trailing: View>: View {
    let eyebrow: String
    let title: String
    let intro: String?
    @ViewBuilder let content: Content
    @ViewBuilder let leadingActions: Leading
    @ViewBuilder let primaryAction: Trailing
    var tint: Color = CTColor.state(.actionable)
    /// VoiceOver focus binding for the title (`holding-copy-spec.md` §7:
    /// "focus moves to the title on entering Holding"). `nil` for every
    /// caller except the Holding views — the other nine steps have no
    /// focus-follows-phase pattern and deliberately keep that (pre-existing,
    /// out-of-scope) behavior unchanged.
    var focusTitle: AccessibilityFocusState<Bool>.Binding?

    init(
        eyebrow: String,
        title: String,
        intro: String?,
        focusTitle: AccessibilityFocusState<Bool>.Binding? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder leadingActions: () -> Leading,
        @ViewBuilder primaryAction: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.intro = intro
        self.focusTitle = focusTitle
        self.content = content()
        self.leadingActions = leadingActions()
        self.primaryAction = primaryAction()
    }

    func headerTint(_ color: Color) -> StepShell {
        var copy = self
        copy.tint = color
        return copy
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: CTSpace.section) {
                        Color.clear
                            .frame(height: 0)
                            .id("step-shell-top")

                        Text(eyebrow)
                            .ctText(CTType.eyebrow, color: tint)
                            .accessibilityAddTraits(.isHeader)

                        Text(title)
                            .ctText(CTType.stepTitle)
                            .fixedSize(horizontal: false, vertical: true)
                            .modifier(TitleAccessibilityFocus(binding: focusTitle))

                        if let intro {
                            Text(intro)
                                .ctText(CTType.lead)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        content
                    }
                    .frame(maxWidth: 600, alignment: .leading)
                    .padding(.horizontal, CTSpace.pane)
                    .padding(.top, CTSpace.paneTop)
                    .padding(.bottom, CTSpace.section)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    proxy.scrollTo("step-shell-top", anchor: .top)
                }
                .onChange(of: title) { _ in
                    proxy.scrollTo("step-shell-top", anchor: .top)
                }
            }

            Divider()

            HStack(spacing: 12) {
                leadingActions
                Spacer()
                primaryAction
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The persistent roadmap sidebar — always shows all 9 stages with done /
/// current / upcoming state (#w1-#w9's `.sb-list`). Nothing downstream is
/// ever locked from proceeding via the footer's own Continue/Skip; only the
/// sidebar's own tap-to-review affordance is restricted to completed rows.
struct WizardRoadmapSidebar: View {
    @ObservedObject var model: WizardModel

    var body: some View {
        List {
            Section {
                // Owner directive: the aviators glyph is menu-bar-tray-ONLY (see
                // `AviatorGlyph`'s doc comment in `native/models.swift`) — this
                // sidebar eyebrow must never draw it. `ControlTowerGlyph`, the
                // full-color illustration used elsewhere in the wizard, was
                // tried and rejected here too: at this row's ~16pt icon scale
                // it collapses into an unreadable colored blob (same finding
                // as the popover header's `GlyphView`), so no brand image is
                // drawn here — the text alone is the eyebrow.
                Text("Set Up Copilot Control Tower")
                    .font(.headline)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .padding(.vertical, 4)
            }

            Section {
                ForEach(WizardStage.allCases) { stage in
                    roadmapRow(stage)
                }
            } header: {
                Text("Setup")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .textCase(.uppercase)
            }
        }
        .listStyle(.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
    }

    private func roadmapRow(_ stage: WizardStage) -> some View {
        let current = model.currentStage
        let isDone = stage.rawValue < current.rawValue
        let isCurrent = stage.rawValue == current.rawValue
        let statusWord = isDone ? "completed" : (isCurrent ? "current" : "not started")

        return Button {
            guard isDone else { return }
            model.reviewStage(stage)
        } label: {
            HStack(spacing: 8) {
                statusGlyph(isDone: isDone, isCurrent: isCurrent)
                Text(stage.title)
                    .font(.body.weight(isCurrent ? .medium : .regular))
                    .foregroundColor(isCurrent ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isCurrent ? Color(nsColor: .controlAccentColor).opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isDone)
        .opacity(isDone || isCurrent ? 1.0 : 0.5)
        .accessibilityLabel("Step \(stage.rawValue + 1) of \(WizardStage.allCases.count), \(stage.title), \(statusWord)")
    }

    private func statusGlyph(isDone: Bool, isCurrent: Bool) -> some View {
        Group {
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(nsColor: .systemGreen))
            } else if isCurrent {
                Image(systemName: "circle.inset.filled")
                    .foregroundColor(Color(nsColor: .controlAccentColor))
            } else {
                Image(systemName: "circle")
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Wizard root view

struct WizardRootView: View {
    @ObservedObject var model: WizardModel
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// H1's forward step (§4.1) — a sheet over the wizard, not a new window.
    /// Lives here (not on `WizardModel`) because it is purely a presentation
    /// detail with no CLI-facing state of its own.
    @State private var showsInstallSheet = false
    /// H7's forward steps (§2.9.3) — same presentation-only pattern as
    /// `showsInstallSheet` above. `showsGrantSheet` opens BEFORE the CLI
    /// call resolves (`model.beginGrantFlow()` sets `.pending` synchronously)
    /// so the sheet can show its own "waiting" state honestly; it closes
    /// itself (never left open) the moment `model.grantFlow.status` becomes
    /// `.unavailable` — see `GrantPermissionSheet`'s own doc comment.
    @State private var showsGrantSheet = false
    @State private var showsGrantFallbackSheet = false
    /// H7's self-serve org-sign-in flavor (Defect 1b) — same
    /// presentation-only pattern as `showsInstallSheet` above: the command
    /// itself lives on `HoldingInfo.selfServeCommand` (read back from
    /// `model.phase` at presentation time, `currentSelfServeCommand` below),
    /// never duplicated into a second piece of state.
    @State private var showsOrgSignInSheet = false
    /// §2.1.2's own sheet, behind the organization question's `Help me find
    /// it` — unlike the Holding sheets above, closing it never re-checks
    /// anything: it just returns focus to the field on the SAME screen.
    @State private var showsOrgHelpSheet = false
    /// Step 6's Connect sheet (task 222). Presentation-only, same pattern as
    /// the sheets above — the row it carries is the CLI's own
    /// `needs-connect` row, never one this view assembled, and it is dropped
    /// the moment the sheet closes.
    @State private var connectingRow: ConnectionRow?
    /// Presentation-only list controls for Step 7. The selected category
    /// itself lives on `WizardModel` so sidebar review preserves the route;
    /// search and pagination are ephemeral and never affect CLI truth.
    @State private var projectSearchText = ""
    @State private var projectPage = 0
    @State private var showsBulkMigrationConfirmation = false
    /// Copy spec §7: "focus moves to the title on entering Holding." Scoped
    /// to the Holding phase only (`h1View`...`h7View`, `honestIncompleteView`
    /// — see `StepShell.focusTitle`) — the wizard's other nine steps have no
    /// focus-follows-phase pattern and this deliberately does not fan out
    /// into them.
    @AccessibilityFocusState private var holdingTitleFocused: Bool

    var body: some View {
        NavigationSplitView {
            WizardRoadmapSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 280)
        } detail: {
            Group {
                content
            }
            .id(phaseIdentity)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: phaseIdentity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, idealWidth: 960, minHeight: 620, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.verifyPendingProjectOnReturn()
        }
        .onChange(of: model.selectedProjectCategory) { _ in
            projectSearchText = ""
            projectPage = 0
        }
        .sheet(isPresented: $showsInstallSheet) {
            InstallHelperSheet {
                showsInstallSheet = false
                model.tryAgainAfterHolding()
            }
        }
        .sheet(isPresented: $showsGrantSheet) {
            GrantPermissionSheet(model: model) {
                showsGrantSheet = false
            } onGranted: {
                showsGrantSheet = false
                model.tryAgainAfterHolding()
            }
        }
        .sheet(isPresented: $showsGrantFallbackSheet) {
            GrantFallbackSheet {
                showsGrantFallbackSheet = false
                model.tryAgainAfterHolding()
            }
        }
        .sheet(isPresented: $showsOrgSignInSheet) {
            OrgSignInIDSheet(command: currentSelfServeCommand ?? "") {
                showsOrgSignInSheet = false
                model.tryAgainAfterHolding()
            }
        }
        .sheet(isPresented: $showsOrgHelpSheet) {
            OrgHelpSheet {
                showsOrgHelpSheet = false
            }
        }
        .sheet(item: $connectingRow) { row in
            ConnectSheet(row: row) { _ in
                // Re-read the whole roster from the CLI rather than patching
                // the one row this app just changed: the verb already
                // re-checked, and a second, independent read is what proves
                // the screen and the machine agree (invariant #1 — the app
                // never decides that a write took).
                connectingRow = nil
                model.refreshConnections()
            } onCancel: {
                connectingRow = nil
            }
        }
    }

    /// The exact command `h7OrgSignInView`'s primary is showing a sheet
    /// for — read live from `model.phase` rather than duplicated into its
    /// own `@State`, so it can never drift from what the Holding screen
    /// itself is displaying. `??  ""` is unreachable in practice (the sheet
    /// is only ever opened from `h7OrgSignInView`, which only exists when
    /// `selfServeCommand` is non-nil) but keeps this a total, crash-free
    /// read rather than a force-unwrap.
    private var currentSelfServeCommand: String? {
        if case .holding(let info) = model.phase {
            return info.selfServeCommand
        }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .welcome: welcomeView
        case .connectGitHub: connectGitHubView
        case .orgQuestion: orgQuestionView
        case .detecting, .replanningAfterDecision, .detected: detectView
        case .onboardQuestion: onboardQuestionView
        case .whatYoureGetting: whatYoureGettingView
        case .departments: departmentsView
        case .integrations: integrationsView
        case .projects: projectsView
        case .materializing: materializeView
        case .verifying, .verified: verifyView
        case .holding(let info): holdingView(info)
        }
    }

    private func showInstallSheet() {
        showsInstallSheet = true
    }

    private var phaseIdentity: String {
        switch model.phase {
        case .welcome: return "welcome"
        case .connectGitHub: return "connectGitHub-\(model.deviceFlow.status)"
        case .orgQuestion: return "orgQuestion"
        case .detecting: return "detecting"
        case .replanningAfterDecision: return "replanningAfterDecision"
        case .detected: return "detected"
        case .onboardQuestion: return "onboardQuestion"
        case .whatYoureGetting: return "whatYoureGetting"
        case .departments: return "departments"
        case .integrations: return "integrations"
        case .projects: return "projects"
        // Constant for the whole run, unlike the old fabricated
        // `"materializing-\(index)"`: rows fill in via normal SwiftUI
        // diffing on `model.setupProgress`, never by re-mounting the whole
        // step (that per-tick identity churn was itself part of the
        // fabrication this task removes — a real update doesn't arrive on
        // a 500ms cadence, so the view shouldn't transition like one does).
        case .materializing: return "materializing"
        case .verifying: return "verifying"
        case .verified: return "verified"
        case .holding(let info): return "holding-\(info.origin.rawValue)"
        }
    }

    // MARK: 1. Welcome (#w1)

    // Owner directive: the aviators glyph is menu-bar-tray-ONLY (see
    // `AviatorGlyph`'s doc comment in `native/models.swift`) — this welcome
    // hero must render the full-color Control Tower illustration instead
    // (`ControlTowerGlyph`, `docs/10-reference/control-tower.svg`), never tinted.
    private var welcomeHeroImage: some View {
        Image(nsImage: ControlTowerGlyph.load(targetHeight: 40))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 40, height: 40)
            .accessibilityLabel("Copilot Control Tower")
    }

    private var welcomeView: some View {
        stepShell(
            eyebrow: "Step 1 of 9",
            title: "Welcome to your copilots.",
            intro: "Your company just gave you a set of AI copilots to help with your everyday work. This app, Copilot Control Tower, is how they land on your Mac and how they stay current."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                welcomeHeroImage

                Text("You don't need to be technical for any of this. Control Tower sets everything up for you, then keeps it up to date quietly in the background. It lives as a small icon in your menu bar. When the icon is quiet, everything's ready.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)

                sectionCard("Here's what you're getting:") {
                    VStack(alignment: .leading, spacing: 0) {
                        confirmRow(name: "Knowledge Copilot", desc: "Your company's knowledge, ready to ask. Get a straight answer without hunting through documents.")
                        Divider()
                        confirmRow(name: "CLI Copilot", desc: "The quiet engine that keeps your copilots running behind the scenes.")
                        Divider()
                        confirmRow(name: "Claude Copilot", desc: "Your AI copilot for everyday work, from writing and checking numbers to building things.")
                    }
                }

                sectionCard("Before you start") {
                    VStack(alignment: .leading, spacing: 12) {
                        bulletRow("A GitHub account. It's how your company shares your copilots with you, and where your own space lives. Don't have one yet? Create one first, it's free.")
                        bulletRow("The GitHub command line. A small tool Control Tower uses to bring in what your team shares. If it's not on this Mac, Control Tower sets it up. You'll approve it once, in your browser.")
                        Text("That's it. Have your GitHub sign-in handy and everything else is handled for you.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                }

                videoLinkRow("Watch a short welcome video")
            }
        } leadingActions: {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
            }
            .buttonStyle(.bordered)
        } primaryAction: {
            Button {
                model.getStarted()
            } label: {
                Text("Get Started")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: 2. Connect GitHub (#w2)

    private var connectGitHubView: some View {
        stepShell(
            eyebrow: "Step 2 of 9",
            title: "Connect GitHub",
            intro: "GitHub comes first. It's how Control Tower knows what your team shares with you, and where your own space lives. Signing in happens in your browser, on GitHub's own page. Control Tower never asks for your password."
        ) {
            switch model.deviceFlow.status {
            case .idle, .pending:
                if let userCode = model.deviceFlow.userCode {
                    sectionCard("Your code") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(userCode)
                                    .font(.title3.monospaced())
                                    .textSelection(.enabled)
                                    .foregroundColor(Color(nsColor: .labelColor))
                                Spacer()
                                Button {
                                    model.copyDeviceCode()
                                } label: {
                                    Text("Copy code")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            Button {
                                model.openGitHubSignIn()
                            } label: {
                                Text("Open GitHub")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.deviceFlow.verificationUri == nil)

                            Text("Waiting for you to finish in your browser…")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))

                            // P5 (progress-and-waiting spec §7): "One addition,
                            // because a lost browser window is the common
                            // failure" — no timer, no count, just the way back
                            // in, beside the existing wait sentence above.
                            HStack(spacing: 6) {
                                Text("Didn't see the browser?")
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                Button("Open it again") {
                                    model.openGitHubSignIn()
                                }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(nsColor: .linkColor))
                                .disabled(model.deviceFlow.verificationUri == nil)
                            }
                        }
                    }
                } else {
                    sectionCard("Getting your code") {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Connecting securely to GitHub…")
                                    .font(.body)
                                    .foregroundColor(Color(nsColor: .labelColor))
                                Text("This can take a few seconds.")
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Getting your GitHub sign-in code")
                    }
                }
            case .authorized:
                sectionCard("") {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(nsColor: .systemGreen))
                        Text("Signed in as \(model.authorizedLogin ?? "you").")
                            .font(.body)
                            .foregroundColor(Color(nsColor: .labelColor))
                    }
                }
            case .expired, .denied:
                EmptyView()
            }
        } leadingActions: {
            Button { model.backToWelcome() } label: { Text("Back") }
                .buttonStyle(.bordered)
        } primaryAction: {
            Button { model.continueFromConnectGitHub() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.deviceFlow.status != .authorized)
        }
    }

    // MARK: 2.1.1 Which organization are you with? (inline over Connect
    // GitHub, entered on `org-required` — copy spec §2.1.1). Same
    // no-sidebar-row/`accent` blue mechanism `onboardQuestionView` already
    // uses over Detect; `stepShell`'s default tint IS `CTColor.state(.actionable)`
    // (task 222 P1-5 — the appearance-corrected accent, still the user's own
    // chosen accent colour, per `docs/03-design/native-visual-refresh-spec.md`
    // §2.3), so this view never calls `.headerTint(_:)` either — this is a
    // question, never a Holding variant.

    private var orgQuestionView: some View {
        stepShell(
            eyebrow: "BEFORE YOU SIGN IN",
            title: "Which organization are you with?",
            intro: model.orgQuestionIntro
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your organization's name on GitHub")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                TextField("Acme-Co", text: $model.orgNameInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onChange(of: model.orgNameInput) { _ in model.orgNameInputChanged() }
                    .accessibilityLabel("Your organization's name on GitHub")
                Text("The short name in your organization's GitHub address, like the Acme-Co in github.com/Acme-Co.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)

                orgValidationView

                if let notFound = model.orgNotFoundMessage {
                    Text(notFound)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .systemRed))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        } leadingActions: {
            Button { showsOrgHelpSheet = true } label: { Text("Help me find it") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            VStack(alignment: .trailing, spacing: 4) {
                Button { model.continueToSignInFromOrgQuestion() } label: { Text("Continue to sign in") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinueToSignIn || model.orgQuestionSubmitting)
                    // Accessibility: "the disabled primary always carries its
                    // hint as help text" — same discipline `onboardQuestionView`
                    // already follows.
                    .help(model.canContinueToSignIn ? "" : "Add your organization's name, or select Help me find it.")
                if !model.canContinueToSignIn {
                    Text("Add your organization's name, or select Help me find it.")
                        .font(.caption2)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
            }
        }
    }

    /// The closed three-condition validation table (copy spec §3), shown
    /// only once `WizardModel.orgFieldValidation` itself is non-`.none`
    /// (which already gates on `orgFieldTouched`/non-empty) — never while
    /// the first characters are being typed.
    @ViewBuilder
    private var orgValidationView: some View {
        switch model.orgFieldValidation {
        case .none:
            EmptyView()
        case .containsSpaces(let suggestion):
            VStack(alignment: .leading, spacing: 6) {
                Text("Your organization's name on GitHub is one word, with dashes instead of spaces. \(model.orgNameInput) is usually \(suggestion).")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Use \(suggestion)") {
                    model.applyOrgSpacesFix(suggestion)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
        case .containsAt:
            Text("That's an email address. I need your organization's name on GitHub, which is usually one word with dashes.")
                .font(.caption)
                .foregroundColor(Color(nsColor: .systemRed))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        case .invalidCharacters:
            Text("Names on GitHub use letters, numbers, and single dashes, and nothing else.")
                .font(.caption)
                .foregroundColor(Color(nsColor: .systemRed))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    // MARK: 3. Detect (#w3)

    private var detectView: some View {
        stepShell(
            eyebrow: "Step 3 of 9",
            title: "Checking what's already here",
            intro: "Control Tower keeps the parts that are already right, safely moves or repairs recognized earlier setup, and leaves anything unfamiliar untouched."
        ) {
            if case .detecting = model.phase {
                VStack(alignment: .leading, spacing: 16) {
                    verifyingCard("Checking what's already here…")
                    sectionCard("Your Copilot setup") {
                        wizardCopilotRoster(nil, checking: true)
                    }
                }
            } else if case .replanningAfterDecision = model.phase {
                // "One question first", Detect's own spec section: "the
                // feedback is the shared progress card with **Checking what
                // that means…**" — distinct copy from the first Detect pass
                // above, same shared progress card.
                VStack(alignment: .leading, spacing: 16) {
                    verifyingCard("Checking what that means…")
                    sectionCard("Your Copilot setup") {
                        wizardCopilotRoster(nil, checking: true)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    copilotRepositoryLocationCard
                    sectionCard("Your Copilot setup") {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(topologySummary)
                                .font(.callout)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 8)
                            ForEach(copilotTopologyComponents, id: \.id) { component in
                                copilotTopologyDisclosure(component)
                            }
                        }
                    }
                    Text("Review what Control Tower will keep, create, download, or update. Existing local work is preserved. Nothing is called Ready until every expected layer is visible, connected, synchronized, and verified.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } leadingActions: {
            Button { model.phase = .connectGitHub } label: { Text("Back") }
                .buttonStyle(.bordered)
        } primaryAction: {
            Button { model.continueFromDetect() } label: { Text("Review setup") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isDetecting || model.copilotRepositoryRoot == nil)
        }
    }

    private struct CopilotTopologyComponent: Identifiable {
        let id: String
        let title: String
        let symbol: String
    }

    private var copilotTopologyComponents: [CopilotTopologyComponent] {
        [
            .init(id: "knowledge", title: "Knowledge Copilot", symbol: "book.closed.fill"),
            .init(id: "cli", title: "CLI Copilot", symbol: "terminal.fill"),
            .init(id: "claude", title: "Claude Copilot", symbol: "sparkles"),
            .init(id: "codex", title: "Codex Copilot", symbol: "chevron.left.forwardslash.chevron.right"),
        ]
    }

    private var topologySummary: String {
        let total = model.ecosystemLayers.count
        let visible = model.ecosystemLayers.filter { $0.localState == "visible" }.count
        let changes = model.ecosystemLayers.filter { ($0.action ?? "reuse") != "reuse" }.count
        guard total > 0 else { return "Control Tower is waiting for a complete repository inventory." }
        return "\(total) expected layers across four copilots. \(visible) are visible now; \(changes) need a setup action."
    }

    private var copilotRepositoryLocationCard: some View {
        sectionCard("Your Copilot repository folder") {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundColor(Color(nsColor: .controlAccentColor))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.copilotRepositoryRoot ?? "Choose a visible folder")
                        .font(.callout.weight(.semibold))
                        .textSelection(.enabled)
                    Text("New Copilot repositories will be created or downloaded here, beside the ones you already have.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(model.copilotRepositoryRoot == nil ? "Choose folder…" : "Choose another folder…") {
                    model.chooseCopilotRepositoryFolder()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func copilotTopologyDisclosure(_ component: CopilotTopologyComponent) -> some View {
        let layers = model.ecosystemLayers
            .filter { $0.product == component.id }
            .sorted { $0.rank > $1.rank }
        let needsAction = layers.contains { ($0.action ?? "review") != "reuse" }
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(layers, id: \.id) { layer in
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: topologyLayerSymbol(layer))
                            .foregroundColor(topologyLayerColor(layer))
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(topologyRoleLabel(layer))
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Text(topologyActionLabel(layer))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(topologyLayerColor(layer))
                            }
                            if let name = layer.repositoryName, !name.isEmpty {
                                Text(name)
                                    .font(.caption.monospaced())
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            }
                            if let detail = layer.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: component.symbol)
                    .foregroundColor(needsAction ? Color(nsColor: .controlAccentColor) : Color(nsColor: .systemGreen))
                    .frame(width: 22)
                Text(component.title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(needsAction ? "Needs setup" : "Found")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(needsAction ? Color(nsColor: .controlAccentColor) : Color(nsColor: .systemGreen))
            }
            .padding(.vertical, 9)
        }
    }

    private func topologyRoleLabel(_ layer: EcosystemOnboardLayer) -> String {
        switch layer.role {
        case "foundation": return "Foundation"
        case "organization": return "Organization"
        case "department": return layer.unit?.capitalized ?? "Department"
        case "personal": return "Personal"
        default: return layer.role.capitalized
        }
    }

    private func topologyActionLabel(_ layer: EcosystemOnboardLayer) -> String {
        switch layer.action {
        case "reuse": return layer.syncState == "local-changes" ? "Local work preserved" : "Found"
        case "create": return "Will create"
        case "download": return "Will download"
        case "initialize": return "Will initialize"
        case "repair": return "Will update"
        case "choose-location": return "Choose folder"
        default: return "Needs review"
        }
    }

    private func topologyLayerSymbol(_ layer: EcosystemOnboardLayer) -> String {
        switch layer.action {
        case "reuse": return layer.syncState == "local-changes" ? "pencil.circle.fill" : "checkmark.circle.fill"
        case "create": return "plus.circle.fill"
        case "download": return "arrow.down.circle.fill"
        case "initialize": return "shippingbox.circle.fill"
        case "repair": return "arrow.triangle.2.circlepath.circle.fill"
        case "choose-location": return "folder.badge.plus"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private func topologyLayerColor(_ layer: EcosystemOnboardLayer) -> Color {
        switch layer.action {
        case "reuse" where layer.syncState != "local-changes": return Color(nsColor: .systemGreen)
        case "create", "download", "initialize": return Color(nsColor: .controlAccentColor)
        case "repair", "reuse": return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemRed)
        }
    }

    private var isDetecting: Bool {
        switch model.phase {
        case .detecting, .replanningAfterDecision: return true
        default: return false
        }
    }

    private func inventoryActionLabel(_ action: String) -> String {
        switch action {
        case "reuse": return "Keep"
        case "create": return "Add"
        case "migrate": return "Move safely"
        case "repair": return "Complete"
        case "review": return "Needs review"
        default: return action.capitalized
        }
    }

    private func inventoryGlyph(_ action: String) -> String {
        switch action {
        case "reuse": return "checkmark.circle.fill"
        case "create": return "plus.circle.fill"
        case "migrate": return "arrow.right.circle.fill"
        case "repair": return "wrench.and.screwdriver.fill"
        case "review": return "hand.raised.circle.fill"
        default: return "circle.fill"
        }
    }

    private func inventoryColor(_ action: String) -> Color {
        switch action {
        case "reuse": return Color(nsColor: .systemGreen)
        case "review": return Color(nsColor: .systemRed)
        default: return Color(nsColor: .controlAccentColor)
        }
    }

    // MARK: One question first (adopt-and-project-setup spec, inline over
    // Detect — same no-sidebar-row mechanism Holding uses below, accent
    // blue, never Holding's orange: `stepShell`'s default `tint` already IS
    // `CTColor.state(.actionable)` (task 222 P1-5), so this view never calls
    // `.headerTint(_:)` at all).

    private enum OnboardCardRow: Identifiable {
        case ask(EcosystemInventoryItem)
        case review(EcosystemInventoryItem)
        var id: String {
            switch self {
            case .ask(let item): return item.id
            case .review(let item): return item.id
            }
        }
        var scope: String {
            switch self {
            case .ask(let item): return item.scope
            case .review(let item): return item.scope
            }
        }
    }

    /// Groups a list of ask/review items into the two scope cards, in the
    /// CLI's own order, `scope: "personal"` first (adopt-and-project-setup
    /// spec's existing card) then `scope: "machine"` (new). Every other
    /// scope (`"project"`) is never asked here at all — this screen is
    /// Detect-time only, before any project has even been discovered.
    private func onboardCardRows<T>(_ items: [T], scope: (T) -> String) -> (personal: [T], machine: [T]) {
        (items.filter { scope($0) == "personal" }, items.filter { scope($0) == "machine" })
    }

    private var onboardQuestionView: some View {
        // "One row per question item, in the CLI's order" THEN "one row per
        // item the CLI marked for review instead of a question" — two
        // sequential lists, per the spec's own reading order, not
        // interleaved by the underlying inventory's mixed ordering. THEN
        // split by scope into the two cards — the scope word itself never
        // reaches the screen, only which card a row lands in.
        let allRows: [OnboardCardRow] = model.onboardQuestionItems.map(OnboardCardRow.ask)
            + model.onboardReviewItemsForQuestion.map(OnboardCardRow.review)
        let (personalRows, machineRows) = onboardCardRows(allRows) { $0.scope }

        let hasPersonal = !personalRows.isEmpty
        let hasMachine = !machineRows.isEmpty
        let intro: String
        if hasPersonal && hasMachine {
            intro = "You already have some of this: spaces of your own on GitHub, and a working connection on this Mac. I can build on what's here, or leave it alone and set up the rest around it."
        } else if hasMachine {
            intro = "This Mac is already set up to reach GitHub, and I checked that what's here works. I can build on it, or leave it alone and set the rest up around it."
        } else {
            intro = "Your GitHub account already has private spaces of your own, with your own content in them. I can include them so your copilots use what you already have, or leave them alone."
        }

        return stepShell(
            eyebrow: "ONE QUESTION FIRST",
            title: "Want me to include what you already have?",
            intro: intro
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if hasPersonal {
                    sectionCard("Already in your GitHub account") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(personalRows.enumerated()), id: \.element.id) { index, row in
                                onboardCardRow(row)
                                if index < personalRows.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                if hasMachine {
                    sectionCard("Already on this Mac") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(machineRows.enumerated()), id: \.element.id) { index, row in
                                onboardCardRow(row)
                                if index < machineRows.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                // The app-authored general guarantee (copy spec §1.4):
                // structurally true for every `action: "create"` +
                // `reversible: true` row, so it can never drift from what
                // the CLI actually does — held apart, on purpose, from each
                // row's own CLI-authored specific found fact above it.
                Text("Nothing you already have is changed. Setup only adds what's missing.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        } leadingActions: {
            Button { model.declineOnboardQuestion() } label: { Text("Not now") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            VStack(alignment: .trailing, spacing: 4) {
                Button { model.includeOnboardSelections() } label: { Text("Include what I have") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canIncludeOnboardSelections)
                    // Accessibility: "the disabled primary always carries
                    // its hint as help text" — never a hint the person can
                    // only discover by hovering.
                    .help(model.canIncludeOnboardSelections ? "" : "Choose something to include, or select Not now.")
                if !model.canIncludeOnboardSelections {
                    Text("Choose something to include, or select Not now.")
                        .font(.caption2)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
            }
        }
    }

    @ViewBuilder
    private func onboardCardRow(_ row: OnboardCardRow) -> some View {
        switch row {
        case .ask(let item): onboardQuestionRow(item)
        case .review(let item): onboardReviewRow(item)
        }
    }

    private func onboardQuestionRow(_ item: EcosystemInventoryItem) -> some View {
        let isSelected = model.onboardSelections.contains(item.id)
        return Toggle(isOn: Binding(
            get: { isSelected },
            set: { _ in model.toggleOnboardSelection(item.id) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
                // Microinteraction: "a cleared row is declined; the feedback
                // is the CLI's decline sentence appearing under that row in
                // 150ms with no layout jump elsewhere". `item.declineDetail`
                // (B3, `onboard.schema.json`'s `inventoryItem.decline_detail`)
                // is rendered VERBATIM, never invented — per the spec's own
                // failure/recovery row, "A missing decline sentence renders
                // the row with no caption rather than invented copy", so an
                // absent `declineDetail` still shows no caption at all.
                if isSelected {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                } else if let declineDetail = item.declineDetail {
                    Text(declineDetail)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 9)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isSelected
                ? "\(item.title), will be included, \(item.detail)"
                : "\(item.title), will be left alone" + (item.declineDetail.map { ", \($0)" } ?? "")
        )
    }

    private func onboardReviewRow(_ item: EcosystemInventoryItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("Kept as is")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), kept as is, \(item.detail)")
    }

    // MARK: 4. What you're getting (#w4)

    private var whatYoureGettingView: some View {
        stepShell(
            eyebrow: "Step 4 of 9",
            title: "Here's what you're getting",
            intro: "Everyone on your team gets all of this. There's nothing to pick. Control Tower sets it up and keeps it current for you."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                sectionCard("Your copilots") {
                    VStack(alignment: .leading, spacing: 0) {
                        confirmRow(name: "Knowledge Copilot", desc: "Your company's knowledge, ready to ask.")
                        Divider()
                        confirmRow(name: "CLI Copilot", desc: "The quiet engine that keeps everything running.")
                        Divider()
                        confirmRow(name: "Claude Copilot, your company's pick", desc: "Your AI copilot for everyday work.")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Use the other one too?")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    Toggle(isOn: Binding(
                        get: { model.includeCodex },
                        set: { _ in model.toggleIncludeCodex() }
                    )) {
                        Text("I also use Codex. Include Codex Copilot too.")
                            .font(.body)
                            .foregroundColor(Color(nsColor: .labelColor))
                    }
                    .toggleStyle(.checkbox)
                }
            }
        } leadingActions: {
            Button { model.phase = .detected } label: { Text("Back") }
                .buttonStyle(.bordered)
        } primaryAction: {
            Button { model.continueFromWhatYoureGetting() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: 5. Departments (#w5)

    private var departmentsView: some View {
        stepShell(
            eyebrow: "Step 5 of 9",
            title: "Departments you can join",
            intro: "Joining a department brings in everything your team shares there. You can join now, or come back to this later from Settings or the menu bar."
        ) {
            if model.departments.isEmpty {
                Text("No departments are available to you yet. When someone adds you to one, it'll show up here.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                sectionCard("Departments you can join") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.departments.enumerated()), id: \.element.id) { index, department in
                            departmentRow(department)
                            if index < model.departments.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        } leadingActions: {
            Button { model.phase = .whatYoureGetting } label: { Text("Back") }
                .buttonStyle(.bordered)
            Button { model.continueFromDepartments() } label: { Text("Skip for now") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            Button { model.continueFromDepartments() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func departmentRow(_ department: DepartmentRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(department.name)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                departmentStateCaption(department.state)
            }
            Spacer()
            departmentAction(department)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(department.name), \(departmentAccessibilityWord(department.state))")
    }

    @ViewBuilder
    private func departmentStateCaption(_ state: DepartmentJoinState) -> some View {
        switch state {
        case .joined:
            Text("Joined").font(.caption).foregroundColor(Color(nsColor: .secondaryLabelColor))
        case .availableToJoin:
            Text("Available to join").font(.caption).foregroundColor(Color(nsColor: .secondaryLabelColor))
        case .joining:
            Text("Joining…").font(.caption).foregroundColor(Color(nsColor: .secondaryLabelColor))
        case .waitingForNetwork:
            Text("Waiting for the network.").font(.caption).foregroundColor(Color(nsColor: .tertiaryLabelColor))
        case .notAvailable(let caption):
            Text(caption).font(.caption).foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
    }

    private func departmentAccessibilityWord(_ state: DepartmentJoinState) -> String {
        switch state {
        case .joined: return "joined"
        case .availableToJoin: return "available to join"
        case .joining: return "joining"
        case .waitingForNetwork: return "waiting for the network"
        case .notAvailable(let caption): return caption
        }
    }

    @ViewBuilder
    private func departmentAction(_ department: DepartmentRow) -> some View {
        switch department.state {
        case .availableToJoin:
            Button { model.joinDepartment(department.id) } label: { Text("Join") }
                .buttonStyle(.bordered)
        case .joining:
            CTNamedWaitSpinner(subject: "Joining \(department.name)…")
        case .joined, .waitingForNetwork, .notAvailable:
            EmptyView()
        }
    }

    // MARK: 6. Your connections

    private var integrationsView: some View {
        stepShell(
            eyebrow: "Step 6 of 9",
            title: "Your connections",
            intro: "These are the connections Control Tower can prove are ready for you. If your organization makes another connection available, it will appear here with a working Connect button."
        ) {
            VStack(alignment: .leading, spacing: CTSpace.xl) {
                sectionCard("Ready to use") {
                    VStack(alignment: .leading, spacing: 0) {
                        CTStatusRow(
                            glyph: .filledDot(.neutral),
                            title: "GitHub",
                            detail: "Signed in as \(model.authorizedLogin ?? "your GitHub account").",
                            trailing: .status("Ready", .neutral),
                            accessibilityLabelOverride: "GitHub, ready, signed in as \(model.authorizedLogin ?? "your GitHub account")"
                        )

                        if case .loaded(let report) = model.connectionsState {
                            let ready = ConnectionsRender.readyRows(report)
                            if !ready.isEmpty {
                                Divider()
                                ForEach(Array(ready.enumerated()), id: \.element.id) { index, row in
                                    connectionReadyRow(row)
                                    if index < ready.count - 1 { Divider() }
                                }
                            }
                        }
                    }
                }

                // The "Available to connect" card disappears entirely once
                // nothing is pending (spec §5.3's row-transition correction:
                // "the 'Available to your team' heading is gone, because
                // nothing under it is pending any more") -- never shown as an
                // empty shell once the CLI has confirmed there is nothing
                // left to connect.
                if showsAvailableToConnectCard {
                    sectionCard("Available to connect") {
                        availableToConnectContent
                    }
                }
            }
        } leadingActions: {
            Button { model.phase = .departments } label: { Text("Back") }
                .buttonStyle(.bordered)
        } primaryAction: {
            Button { model.continueFromIntegrations() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// The "Available to connect" card is shown while loading/failed (an
    /// honest in-flight or unreadable state), whenever the whole roster
    /// couldn't be resolved at all (`connections.isEmpty`, `copilot-unavailable`
    /// -- a distinct unavailable-store explanation, not "nothing pending"),
    /// and whenever at least one row is actually `needs-connect`/`no-store`.
    /// It disappears ONLY in the one case spec §5.3 names: the CLI answered
    /// fine and nothing is outstanding.
    private var showsAvailableToConnectCard: Bool {
        switch model.connectionsState {
        case .waiting, .loading, .failed:
            return true
        case .loaded(let report):
            if report.connections.isEmpty { return true }
            let needsConnect = ConnectionsRender.needsConnectRows(report)
            let noStore = ConnectionsRender.noStoreRows(report)
            return !(needsConnect.isEmpty && noStore.isEmpty)
        }
    }

    /// `secret_state == ready` org row -- same anatomy as the GitHub row
    /// above it (quiet dot, name, description, quiet trailing "Ready"
    /// label), no tier/mode jargon.
    private func connectionReadyRow(_ row: ConnectionRow) -> some View {
        CTStatusRow(
            glyph: .filledDot(.neutral),
            title: row.name.capitalized,
            detail: row.description,
            trailing: .status("Ready", .neutral),
            accessibilityLabelOverride: "\(row.name.capitalized), ready, \(row.description)"
        )
    }

    /// `secret_state == needs-connect` org row -- names what is actually
    /// missing, in plain language, never tier/mode jargon, and carries the
    /// Connect button this step's own intro has always promised (task 222).
    ///
    /// The button appears on `needs-connect` rows ONLY. Those are the rows
    /// where the CLI has actually reached the store and found named
    /// credentials absent — i.e. the one case a person on this Mac can
    /// resolve. `no-store` rows deliberately keep no affordance at all
    /// (`connectionsNoStoreGroup` below): nothing about them was verified, so
    /// they are rendered as facts rather than as actions.
    ///
    /// `footnote` (not `detail`) carries `needsConnectDetail` -- the sentence
    /// a person must actually read to act. It used to live in
    /// `.tertiaryLabelColor` (1.88:1, G-4); `CTStatusRow.footnote` renders it
    /// in `CTType.caption`/`CTColor.faint` (4.95:1 light / 6.07:1 dark)
    /// instead, clearing this product's own 4.5:1 floor.
    private func connectionNeedsConnectRow(_ row: ConnectionRow) -> some View {
        let missingDetail = ConnectionsRender.needsConnectDetail(row)
        return CTStatusRow(
            glyph: .ring,
            title: row.name.capitalized,
            detail: row.description,
            footnote: missingDetail,
            trailing: .button("Connect…", accessibilityLabel: "Connect \(row.name.capitalized)") {
                connectingRow = row
            }
        )
    }

    /// `secret_state == no-store` rows -- grouped under one honest
    /// explanation (`store.detail`) rather than one line per row, since
    /// nothing about them was individually verified.
    private func connectionsNoStoreGroup(_ rows: [ConnectionRow], storeDetail: String?) -> some View {
        VStack(alignment: .leading, spacing: CTSpace.xs) {
            Text(storeDetail ?? "Your organization's shared secret store could not be checked on this Mac.")
                .ctText(CTType.rowDetail)
                .fixedSize(horizontal: false, vertical: true)
            Text(rows.map { $0.name.capitalized }.joined(separator: ", "))
                .ctText(CTType.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, CTSpace.sm)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var availableToConnectContent: some View {
        switch model.connectionsState {
        case .waiting, .loading:
            HStack(spacing: CTSpace.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking your organization's connections…")
                    .ctText(CTType.rowDetail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Checking your organization's connections")

        case .loaded(let report):
            let needsConnect = ConnectionsRender.needsConnectRows(report)
            let noStore = ConnectionsRender.noStoreRows(report)
            if report.connections.isEmpty {
                Text(ConnectionsRender.unavailableDetail(report))
                    .ctText(CTType.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(needsConnect.enumerated()), id: \.element.id) { index, row in
                        connectionNeedsConnectRow(row)
                        if index < needsConnect.count - 1 || !noStore.isEmpty { Divider() }
                    }
                    if !noStore.isEmpty {
                        connectionsNoStoreGroup(noStore, storeDetail: report.store.detail)
                    }
                }
            }

        case .failed(let error):
            VStack(alignment: .leading, spacing: CTSpace.xs) {
                Text("No additional organization connections are available in Control Tower right now.")
                    .ctText(CTType.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
                if error.looksLikeMissingConnectionsVerb {
                    Text(ConnectionsRender.updateHint)
                        .ctText(CTType.caption)
                }
            }
        }
    }

    // MARK: 7. Your projects (adopt-and-project-setup spec) — a real step,
    // never conditional on Codex, positioned immediately before Set up so
    // every write still happens there.

    private var projectsView: some View {
        stepShell(
            eyebrow: "Step 7 of 9",
            title: projectsStepTitle,
            intro: projectsStepIntro
        ) {
            if model.projectsLoading && model.projectRoots.isEmpty && model.projectWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Checking only the folders you selected…")
                        .font(.callout.weight(.semibold))
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Checking your projects")
                    Text("Control Tower is checking Claude and Codex setup. You can continue when the results are ready.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(height: 72)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    projectsFolderCard
                    if !model.projectRoots.isEmpty {
                        projectsListCard
                    }
                    projectsDeferredAftercareNote
                }
            }
        } leadingActions: {
            if !model.projectMigrationReviewOpen
                && model.projectMigrationApplyReport == nil
                && !model.projectMigrationApplying {
                Button { model.backFromProjects() } label: { Text("Back") }
                    .buttonStyle(.bordered)
            }
        } primaryAction: {
            if !model.projectMigrationReviewOpen
                && model.projectMigrationApplyReport == nil
                && !model.projectMigrationApplying {
                Button { model.continueFromProjects() } label: {
                    Text(
                        model.selectedProjectPaths.isEmpty
                            ? "Continue setup"
                            : "Set up \(model.selectedProjectPaths.count) and continue"
                    )
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .help("Unfinished project work stays available from Control Tower.")
            }
        }
        .alert(
            "Update \(model.projectMigrationReport?.summary.eligible ?? 0) projects?",
            isPresented: $showsBulkMigrationConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Update projects") { model.applyBulkProjectMigration() }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Control Tower will apply only the reviewed CLI plan, preserve project-owned instructions and tools, and verify every updated project independently.")
        }
    }

    private var projectsStepTitle: String {
        if let detail = model.projectIntegrationDetail {
            switch detail.classification {
            case .ready: return "\(detail.name) is ready"
            case .safeFinish: return "\(detail.name) can finish automatically"
            case .guidedIntegration: return "\(detail.name) needs a coding assistant"
            case .ownerDecision: return "\(detail.name) needs its project owner"
            case .couldNotVerify: return "Control Tower couldn't confirm \(detail.name)"
            }
        }
        if model.selectedProjectCategory == .guidedSetup {
            if model.projectMigrationApplying {
                return "Updating \(model.projectMigrationReport?.summary.eligible ?? 0) projects"
            }
            if model.projectMigrationApplyReport != nil {
                return "Project update results"
            }
            if model.projectMigrationReviewOpen {
                return "Review \(model.projectMigrationReport?.summary.eligible ?? 0) project updates"
            }
        }
        if let category = model.selectedProjectCategory {
            return category.title
        }
        if !model.projectWorkspaces.isEmpty {
            return "\(model.projectWorkspaces.count) projects found"
        }
        return "Where do you keep your projects?"
    }

    private var projectsStepIntro: String {
        if let detail = model.projectIntegrationDetail {
            switch detail.classification {
            case .ready:
                return "Claude and Codex passed authoritative verification. Nothing else is needed."
            case .safeFinish:
                return "Review the exact additions and preservation boundaries before including this project."
            case .guidedIntegration:
                return "This project has its own instructions or tools. Run the CLI-generated plan in a visible Terminal session, then Control Tower will verify the result independently."
            case .ownerDecision:
                return "The helper found a decision only the project owner can make. Nothing has been changed."
            case .couldNotVerify:
                return "Setup was found, but the helper could not prove that it matches the current Claude and Codex contract. Nothing has been changed."
            }
        }
        if model.selectedProjectCategory == .guidedSetup {
            if model.projectMigrationApplying {
                return "Control Tower is applying the exact reviewed plan and verifying each project independently."
            }
            if model.projectMigrationApplyReport != nil {
                return "This receipt comes from the CLI's completed-action ledger, including projects it left unchanged or rolled back."
            }
            if model.projectMigrationReviewOpen {
                return "Review every project in the proven automatic cohort once. Control Tower will preserve project-owned instructions and tools."
            }
        }
        if let category = model.selectedProjectCategory {
            switch category {
            case .ready:
                return "These projects already passed Claude and Codex verification. Review them only if you want reassurance."
            case .safeFinish:
                return "The helper found bounded, reversible work. Choose only the projects you want to finish during this setup."
            case .guidedSetup:
                return "Control Tower can update the proven standard cases together. Projects with active changes or tailored setup stay separate and untouched."
            case .ownerDecision:
                return "Each project needs one named decision before guided setup can continue."
            case .couldNotConfirm:
                return "Control Tower found setup, but could not prove that it matches the current contract. Review the exact evidence before deciding what to do."
            }
        }
        if !model.projectWorkspaces.isEmpty {
            return ProjectTriageRender.summary(model.projectWorkspaces)
        }
        return "If you build things on this Mac, Control Tower can set your copilots up inside each project too. Choose the folder where your projects live. Control Tower looks only inside folders you approve."
    }

    private var projectsDeferredAftercareNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(Color(nsColor: .linkColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Do as much or as little project setup as you want now")
                    .font(.callout.weight(.semibold))
                Text("Set up one or two projects, or continue right away. Every unfinished route stays available under Your projects in Copilot Control Tower, so you can come back later.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var projectsFolderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionCard("Your projects folder") {
                VStack(alignment: .leading, spacing: 10) {
                    if model.projectRoots.isEmpty {
                        Text("No folder chosen yet. Nothing is being watched.")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Button("Choose folder…") { model.chooseProjectsFolder() }
                            .buttonStyle(.bordered)
                        Button("I don't keep projects on this Mac") { model.declineProjects() }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        if let blocked = model.projectsFolderBlockedDetail {
                            Text(blocked)
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .systemRed))
                        }
                        if !model.projectRootCandidates.isEmpty {
                            Divider()
                            Text("Control Tower found a folder on this Mac that looks like it already holds your projects:")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(model.projectRootCandidates) { candidate in
                                HStack {
                                    Text(candidate.label)
                                        .font(.callout)
                                        .foregroundColor(Color(nsColor: .labelColor))
                                    Spacer()
                                    Button("Use this folder") { model.approveCandidateRoot(candidate) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.projectRoots.enumerated()), id: \.element.id) { index, root in
                                HStack {
                                    Text(root.name)
                                        .font(.callout)
                                        .foregroundColor(Color(nsColor: .labelColor))
                                    Spacer()
                                    Button("Stop watching") { model.stopWatchingProjectsRoot(root) }
                                        .buttonStyle(.plain)
                                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                }
                                .padding(.vertical, 6)
                                if index < model.projectRoots.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        Button("Add another folder…") { model.chooseProjectsFolder() }
                            .buttonStyle(.bordered)
                        if let blocked = model.projectsFolderBlockedDetail {
                            Text(blocked)
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .systemRed))
                        }
                    }
                }
            }
            if !model.projectRoots.isEmpty {
                Text("Control Tower looks only inside the folders listed here.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
            if model.projectsDeclineConfirmed {
                Text("Got it. I won't ask about projects again. You can turn this on any time from the menu bar.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
    }

    private var projectsListCard: some View {
        Group {
            if let detail = model.projectIntegrationDetail {
                wizardProjectIntegrationDetail(detail)
            } else if model.projectWorkspaces.isEmpty {
                sectionCard("No projects found") {
                    Text("Control Tower checked the folders above and did not find projects with Claude or Codex setup. Choose another folder, or continue setup and add one later.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let category = model.selectedProjectCategory {
                wizardProjectCategoryList(category)
            } else {
                wizardProjectOverview
            }
        }
    }

    private var wizardProjectOverview: some View {
        let categories = ProjectTriageRender.nonEmptyCategories(model.projectWorkspaces)
        return VStack(alignment: .leading, spacing: 14) {
            Text(ProjectTriageRender.summary(model.projectWorkspaces))
                .font(.callout.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(
                    "\(model.projectWorkspaces.count) projects found. "
                        + ProjectTriageRender.summary(model.projectWorkspaces)
                )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(categories) { category in
                    wizardProjectCategoryCard(category)
                }
            }

            DisclosureGroup("How this is classified") {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(ProjectTriageCategory.allCases) { category in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: category.systemImage)
                                .foregroundColor(wizardProjectCategoryColor(category))
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.title)
                                    .font(.caption.weight(.semibold))
                                Text(category.shortMeaning)
                                    .font(.caption2)
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            }
                        }
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
    }

    private func wizardProjectCategoryCard(
        _ category: ProjectTriageCategory
    ) -> some View {
        let workspaces = ProjectTriageRender.workspaces(model.projectWorkspaces, in: category)
        return Button {
            model.showProjectCategory(category)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: category.systemImage)
                        .foregroundColor(wizardProjectCategoryColor(category))
                        .accessibilityHidden(true)
                    Spacer()
                    Text("\(workspaces.count)")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                }
                Text(category.title)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                Text(category.shortMeaning)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                if category == .guidedSetup,
                   let summary = model.projectMigrationReport?.summary,
                   summary.eligible > 0 {
                    Text("\(summary.eligible) can update together · \(summary.held) held · \(summary.residualGuidance) tailored")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Color(nsColor: .linkColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if category == .safeFinish {
                    let selected = workspaces.filter {
                        model.selectedProjectPaths.contains($0.path)
                    }.count
                    if selected > 0 {
                        Text("\(selected) selected")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(Color(nsColor: .systemGreen))
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(workspaces.count), \(category.title), \(category.shortMeaning)"
        )
        .accessibilityHint("Shows only projects in this category.")
    }

    private func wizardProjectCategoryList(
        _ category: ProjectTriageCategory
    ) -> some View {
        Group {
            if category == .guidedSetup,
               model.projectMigrationReport != nil
                    || model.projectMigrationLoading
                    || model.projectMigrationError != nil {
                wizardBulkProjectMigration
            } else {
                wizardGenericProjectCategoryList(category)
            }
        }
    }

    @ViewBuilder
    private var wizardBulkProjectMigration: some View {
        if model.projectMigrationApplying {
            VStack(alignment: .leading, spacing: 14) {
                Button("‹ Back to guided setup") {}
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .disabled(true)
                sectionCard("Updating and checking every project") {
                    HStack(alignment: .top, spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Keep Control Tower open while this finishes.")
                                .font(.callout.weight(.semibold))
                            Text("Each project is updated separately. If one cannot pass verification, its completed writes are rolled back and the other projects keep going.")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Updating and independently checking the reviewed projects")
                }
            }
        } else if let applied = model.projectMigrationApplyReport {
            wizardBulkMigrationResult(applied)
        } else if model.projectMigrationReviewOpen,
                  let report = model.projectMigrationReport {
            wizardBulkMigrationReview(report)
        } else if let report = model.projectMigrationReport {
            wizardBulkMigrationOverview(report)
        } else {
            if let error = model.projectMigrationError {
                VStack(alignment: .leading, spacing: 14) {
                    sectionCard("Grouped updates aren't available") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error)
                                .font(.callout)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Check again") { model.refreshBulkProjectMigration() }
                                .buttonStyle(.bordered)
                        }
                    }
                    wizardGenericProjectCategoryList(.guidedSetup)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Button("‹ All project results") { model.showProjectOverview() }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Checking which projects can update together…")
                            .font(.callout)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func wizardBulkMigrationOverview(
        _ report: WorkspaceMigrationReport
    ) -> some View {
        let eligible = report.candidates.filter { $0.state == .eligible }
        let held = report.candidates.filter { $0.state == .held }
        let tailored = report.candidates.filter { $0.state == .residualGuidance }
        return VStack(alignment: .leading, spacing: 14) {
            Button("‹ All project results") { model.showProjectOverview() }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))

            if report.summary.eligible > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundColor(Color(nsColor: .linkColor))
                            .font(.title3)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(report.summary.eligible) projects can be updated together")
                                .font(.headline)
                            Text("Control Tower found the same proven older setup in these projects. Review the complete group once before anything changes.")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button("Review \(report.summary.eligible) updates") {
                        model.reviewBulkProjectMigration()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Opens the full project list and preservation promise. Nothing changes yet.")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .selectedContentBackgroundColor).opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(nsColor: .linkColor).opacity(0.45), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                sectionCard("No standard updates are ready") {
                    Text("Control Tower did not find a proven automatic update in this group. Every project below remains unchanged and keeps its individual setup route.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                wizardMigrationMetric(report.summary.eligible, title: "Can update together", color: .linkColor)
                wizardMigrationMetric(report.summary.held, title: "Held for now", color: .systemOrange)
                wizardMigrationMetric(report.summary.residualGuidance, title: "Tailored setup", color: .secondaryLabelColor)
            }

            wizardMigrationCandidateGroup(
                title: "Can update together (\(eligible.count))",
                detail: "The CLI found a proven, reversible update and a clean project state.",
                candidates: eligible,
                allowsIndividualReview: false
            )
            wizardMigrationCandidateGroup(
                title: "Held for now (\(held.count))",
                detail: "Control Tower found a possible standard update but left these projects alone because a safety condition needs attention first.",
                candidates: held,
                allowsIndividualReview: true
            )
            wizardMigrationCandidateGroup(
                title: "Tailored setup (\(tailored.count))",
                detail: "These projects do not match a proven automatic route. Their existing guided setup remains available.",
                candidates: tailored,
                allowsIndividualReview: true
            )

            if let error = model.projectMigrationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Check again") { model.refreshBulkProjectMigration() }
                .buttonStyle(.bordered)
                .disabled(model.projectMigrationLoading)
        }
    }

    private func wizardMigrationMetric(
        _ count: Int,
        title: String,
        color: NSColor
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(count)")
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(nsColor: color))
            Text(title)
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count), \(title)")
    }

    private func wizardMigrationCandidateGroup(
        title: String,
        detail: String,
        candidates: [WorkspaceMigrationCandidate],
        allowsIndividualReview: Bool
    ) -> some View {
        DisclosureGroup(title) {
            VStack(alignment: .leading, spacing: 0) {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    if index > 0 { Divider() }
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name)
                                .font(.callout.weight(.semibold))
                            Text(candidate.detail)
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if allowsIndividualReview,
                           let workspace = model.projectWorkspaces.first(where: { $0.path == candidate.path }) {
                            Button("Review setup") { model.reviewProjectIntegration(workspace) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .font(.callout.weight(.semibold))
    }

    private func wizardBulkMigrationReview(
        _ report: WorkspaceMigrationReport
    ) -> some View {
        let eligible = report.candidates.filter { $0.state == .eligible }
        return VStack(alignment: .leading, spacing: 14) {
            Button("‹ Back to guided setup") { model.dismissBulkProjectMigrationReview() }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))

            sectionCard("What Control Tower will protect") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Project instructions, agents, skills, commands, and plugins stay in place.", systemImage: "checkmark.shield")
                    Label("Only the recognized older Copilot wiring in the reviewed plan can change.", systemImage: "checkmark.shield")
                    Label("Every updated component must pass a fresh CLI verification or its writes are rolled back.", systemImage: "checkmark.shield")
                }
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
            }

            sectionCard("Projects in this update") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(eligible.enumerated()), id: \.element.id) { index, candidate in
                        if index > 0 { Divider() }
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(nsColor: .systemGreen))
                                .accessibilityHidden(true)
                            Text(candidate.name)
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text("Ready to update")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Text("Nothing changes until you confirm the complete \(eligible.count)-project update.")
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") { model.dismissBulkProjectMigrationReview() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Update \(eligible.count) projects…") {
                    showsBulkMigrationConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func wizardBulkMigrationResult(
        _ report: WorkspaceMigrationReport
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("‹ All project results") {
                model.dismissBulkProjectMigrationResult()
                model.showProjectOverview()
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))

            if let summary = report.applySummary {
                HStack(spacing: 10) {
                    wizardMigrationMetric(summary.applied, title: "Updated", color: .systemGreen)
                    wizardMigrationMetric(summary.failed, title: "Needs attention", color: .systemRed)
                    wizardMigrationMetric(summary.remainingGuided, title: "Still guided", color: .secondaryLabelColor)
                }
                sectionCard(summary.failed == 0 ? "The reviewed updates finished" : "Some projects need attention") {
                    Text(summary.failed == 0
                        ? "\(summary.applied) projects passed independent verification. \(summary.unchanged) projects outside the automatic cohort were left unchanged."
                        : "\(summary.applied) projects passed verification. \(summary.failed) could not finish and were either left unchanged or rolled back.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                sectionCard("The reviewed plan is no longer current") {
                    Text(report.detail ?? "Control Tower rechecked every project and left the reviewed group unchanged. Review the fresh plan before trying again.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !report.ledger.isEmpty {
                DisclosureGroup("Full project receipt (\(report.ledger.count))") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(report.ledger.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider() }
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: wizardMigrationLedgerIcon(entry.status))
                                    .foregroundColor(wizardMigrationLedgerColor(entry.status))
                                    .frame(width: 16)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(.callout.weight(.semibold))
                                    Text(entry.detail)
                                        .font(.caption)
                                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Text(wizardMigrationLedgerLabel(entry.status))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(wizardMigrationLedgerColor(entry.status))
                            }
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .font(.callout.weight(.semibold))
            }

            if let error = model.projectMigrationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Check again") { model.refreshBulkProjectMigration() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Done") { model.dismissBulkProjectMigrationResult() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func wizardMigrationLedgerLabel(_ status: WorkspaceMigrationLedgerStatus) -> String {
        switch status {
        case .applied: return "Updated"
        case .blocked: return "Unchanged"
        case .rolledBack: return "Rolled back"
        case .unchanged: return "Unchanged"
        }
    }

    private func wizardMigrationLedgerIcon(_ status: WorkspaceMigrationLedgerStatus) -> String {
        switch status {
        case .applied: return "checkmark.circle.fill"
        case .blocked: return "exclamationmark.circle.fill"
        case .rolledBack: return "arrow.uturn.backward.circle.fill"
        case .unchanged: return "minus.circle"
        }
    }

    private func wizardMigrationLedgerColor(_ status: WorkspaceMigrationLedgerStatus) -> Color {
        switch status {
        case .applied: return Color(nsColor: .systemGreen)
        case .blocked, .rolledBack: return Color(nsColor: .systemRed)
        case .unchanged: return Color(nsColor: .secondaryLabelColor)
        }
    }

    private func wizardGenericProjectCategoryList(
        _ category: ProjectTriageCategory
    ) -> some View {
        let all = ProjectTriageRender.workspaces(model.projectWorkspaces, in: category)
        let filtered = projectSearchText.isEmpty
            ? all
            : all.filter {
                $0.name.localizedCaseInsensitiveContains(projectSearchText)
                    || ProjectTriageRender.reason($0)
                        .localizedCaseInsensitiveContains(projectSearchText)
            }
        let pageCount = max(1, Int(ceil(Double(filtered.count) / Double(ProjectTriageRender.pageSize))))
        let currentPage = min(projectPage, pageCount - 1)
        let start = min(currentPage * ProjectTriageRender.pageSize, filtered.count)
        let end = min(start + ProjectTriageRender.pageSize, filtered.count)
        let pageRows = Array(filtered[start..<end])

        return VStack(alignment: .leading, spacing: 12) {
            Button("‹ All project results") {
                model.showProjectOverview()
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))

            HStack(alignment: .firstTextBaseline) {
                Text("\(all.count) \(all.count == 1 ? "project" : "projects")")
                    .font(.callout.weight(.semibold))
                Spacer()
                if category == .safeFinish {
                    let selected = all.filter {
                        model.selectedProjectPaths.contains($0.path)
                    }.count
                    if selected > 0 {
                        Text("\(selected) selected for this setup")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .systemGreen))
                    }
                }
            }

            TextField("Search these \(all.count) projects", text: $projectSearchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search \(category.title) projects")

            if filtered.isEmpty {
                Text("No projects in this category match “\(projectSearchText)”.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .padding(.vertical, 18)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(pageRows.enumerated()), id: \.element.id) { index, workspace in
                        if index > 0 { Divider() }
                        wizardProjectRow(workspace)
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack {
                    Text("Showing \(start + 1)–\(end) of \(filtered.count)")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .accessibilityLabel(
                            "Showing projects \(start + 1) through \(end) of \(filtered.count)"
                        )
                    Spacer()
                    Button("Previous") {
                        projectPage = max(0, currentPage - 1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(currentPage == 0)
                    Button("Next") {
                        projectPage = min(pageCount - 1, currentPage + 1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(currentPage >= pageCount - 1)
                }
            }
        }
    }

    private func wizardProjectRow(_ workspace: WorkspaceEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workspace.name)
                        .font(.callout.weight(.semibold))
                    if model.selectedProjectPaths.contains(workspace.path) {
                        Text("SELECTED")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(Color(nsColor: .systemGreen))
                    }
                }
                Text(ProjectTriageRender.reason(workspace))
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                Text(wizardCapabilitySummary(workspace.capabilities))
                    .font(.caption2)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(wizardProjectControlLabel(workspace.classification)) {
                model.reviewProjectIntegration(workspace)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func wizardProjectControlLabel(_ classification: WorkspaceIntegrationClassification) -> String {
        switch classification {
        case .safeFinish: return "Review"
        case .guidedIntegration: return "Review setup"
        case .ownerDecision: return "Review decision"
        case .couldNotVerify: return "Review evidence"
        case .ready: return "View details"
        }
    }

    private func wizardProjectCategoryColor(
        _ category: ProjectTriageCategory
    ) -> Color {
        switch category {
        case .ready:
            return Color(nsColor: .systemGreen)
        case .safeFinish, .guidedSetup:
            return Color(nsColor: .linkColor)
        case .ownerDecision, .couldNotConfirm:
            return Color(nsColor: .secondaryLabelColor)
        }
    }

    private func wizardProjectIntegrationDetail(_ workspace: WorkspaceEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(
                model.selectedProjectCategory == nil
                    ? "‹ All project results"
                    : "‹ Back to \(model.selectedProjectCategory?.title.lowercased() ?? "projects")"
            ) {
                model.dismissProjectIntegrationReview()
            }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(.callout.weight(.semibold))
                    Text(wizardProjectClassificationTitle(workspace.classification))
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                Spacer()
                Text(wizardCapabilitySummary(workspace.capabilities))
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            Text(workspace.detail)
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            if let action = workspace.safeAction {
                wizardProjectNextStep(
                    title: "Review the exact additions",
                    detail: "Control Tower can add only the missing integration files. Nothing is selected until you include this project."
                )
                wizardProjectContractPanel(
                    detected: action.willPreserve.map(\.detail),
                    required: action.willAdd.map(\.detail),
                    preserve: action.willPreserve.map(\.detail),
                    prohibited: action.willNotChange.map(\.detail)
                )
                Button(model.selectedProjectPaths.contains(workspace.path) ? "Selected for safe finish" : "Include this safe finish") {
                    model.includeSafeProject(workspace)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedProjectPaths.contains(workspace.path))
            }

            if let plan = workspace.integrationPlan {
                if workspace.classification == .guidedIntegration {
                    wizardProjectNextStep(
                        title: "\(workspace.name) needs a coding assistant",
                        detail: "Review what was found, then run the guided setup in a visible Terminal session. Control Tower will verify Claude and Codex independently when you return."
                    )
                } else if workspace.classification == .ownerDecision {
                    wizardProjectNextStep(
                        title: "The project owner needs to decide",
                        detail: "Review the exact conflict below, then copy or share the prepared handoff. Control Tower will not change this project without that decision."
                    )
                }
                wizardProjectContractPanel(
                    detected: plan.detected,
                    required: plan.missing,
                    preserve: plan.preserve,
                    prohibited: plan.prohibited
                )
                if let prompt = plan.prompt?.text {
                    DisclosureGroup("Full guided prompt") {
                        Text(prompt)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Button("Run in Codex") { model.openProjectIntegrationAssistant(.codex, workspace: workspace) }
                            .buttonStyle(.borderedProminent)
                        Button("Run in Claude Code") { model.openProjectIntegrationAssistant(.claudeCode, workspace: workspace) }
                            .buttonStyle(.bordered)
                        Button("Copy prompt") { model.copyProjectIntegrationPrompt(workspace) }
                            .buttonStyle(.bordered)
                    }
                }
                if plan.ownerHandoff != nil {
                    Button("Copy project-owner handoff") { model.prepareProjectOwnerHandoff(workspace) }
                        .buttonStyle(.bordered)
                }
                wizardProjectVerificationPanel(plan.verification, stopConditions: plan.stopConditions)
                if model.pendingProjectVerificationPath == workspace.path {
                    HStack {
                        Button("Bring Terminal forward") { model.bringTerminalForward() }
                            .buttonStyle(.bordered)
                        Button("Check project now") { model.verifyProjectIntegration(workspace) }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button("Check project now") { model.verifyProjectIntegration(workspace) }
                        .buttonStyle(.bordered)
                }
            }

            if workspace.classification == .ready {
                wizardProjectNextStep(
                    title: "Nothing else is needed",
                    detail: "Claude and Codex both passed authoritative verification. This project is ready."
                )
                wizardProjectEvidencePanel(workspace)
            }
            if workspace.classification == .couldNotVerify {
                wizardProjectNextStep(
                    title: workspace.diagnostic == nil
                        ? "Review what could not be confirmed"
                        : "Start a read-only diagnostic session",
                    detail: workspace.diagnostic == nil
                        ? "Control Tower found project setup, but could not prove that it matches the current Claude and Codex integration contract. Nothing has been changed."
                        : "A coding assistant can explain the mismatch using the helper's evidence. It cannot change project files; only Control Tower can reclassify the project afterward."
                )
                wizardProjectCouldNotConfirmEvidence(workspace)
                if workspace.diagnostic != nil {
                    HStack {
                        Button("Diagnose in Codex") {
                            model.openProjectDiagnosticAssistant(.codex, workspace: workspace)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Diagnose in Claude Code") {
                            model.openProjectDiagnosticAssistant(.claudeCode, workspace: workspace)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                HStack {
                    Button("Copy diagnostic report") {
                        model.copyProjectDiagnosticReport(workspace)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Check again") { model.verifyProjectIntegration(workspace) }
                        .buttonStyle(.bordered)
                        .help("Use after the project setup changes.")
                }
            }
            if let message = model.projectIntegrationMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .accessibilityHidden(true)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func wizardProjectNextStep(
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundColor(Color(nsColor: .linkColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func wizardProjectCouldNotConfirmEvidence(
        _ workspace: WorkspaceEntry
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(workspace.components, id: \.component.rawValue) { component in
                VStack(alignment: .leading, spacing: 4) {
                    Text(component.component == .claude ? "Claude" : "Codex")
                        .font(.caption.weight(.semibold))
                    if component.missingRequirements.isEmpty {
                        Text("No missing requirement was reported.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    } else {
                        ForEach(component.missingRequirements, id: \.detail) { requirement in
                            Text("• \(requirement.detail)")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let recognized = component.recognizedSetup,
                       !recognized.evidence.isEmpty {
                        DisclosureGroup("Setup Control Tower recognized") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(recognized.evidence, id: \.path) { evidence in
                                    Text("\(evidence.path): \(evidence.detail)")
                                        .font(.caption2)
                                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.top, 3)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func wizardProjectContractPanel(
        detected: [String],
        required: [String],
        preserve: [String],
        prohibited: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            wizardProjectFactRow("Detected", detected)
            wizardProjectFactRow("Required", required)
            wizardProjectFactRow("Preserve", preserve)
            wizardProjectFactRow("Must not", prohibited)
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func wizardProjectFactRow(_ label: String, _ values: [String]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 64, alignment: .leading)
            Text(values.isEmpty ? "Nothing" : values.joined(separator: " · "))
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func wizardProjectVerificationPanel(
        _ verification: WorkspaceVerification,
        stopConditions: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Verification")
                .font(.caption.weight(.semibold))
            Text(verification.expected)
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Text(verification.command.joined(separator: " "))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            let allStopConditions = stopConditions + verification.stopConditions
            if !allStopConditions.isEmpty {
                Text("Stop if: \(allStopConditions.joined(separator: " · "))")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .systemRed))
            }
        }
    }

    private func wizardProjectEvidencePanel(_ workspace: WorkspaceEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Verified evidence")
                .font(.caption.weight(.semibold))
            ForEach(workspace.components, id: \.component.rawValue) { component in
                Text("\(component.component == .claude ? "Claude" : "Codex"): \(wizardProjectClassificationTitle(component.classification))")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            Text("Project setup preserved and verified.")
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
    }

    private func wizardCapabilitySummary(_ capabilities: WorkspaceCapabilities) -> String {
        "\(capabilities.instructions) instructions · \(capabilities.agents) agents · \(capabilities.skills) skills · \(capabilities.commands) commands · \(capabilities.plugins) plugins"
    }

    private func wizardProjectClassificationTitle(_ classification: WorkspaceIntegrationClassification) -> String {
        switch classification {
        case .ready: return "Ready"
        case .safeFinish: return "Can finish automatically"
        case .guidedIntegration: return "Needs guided setup"
        case .ownerDecision: return "Needs the project owner"
        case .couldNotVerify: return "Couldn't confirm"
        }
    }

    // MARK: 8. Set up (#w7) — honest progress, from real CLI results only
    //
    // P1 (progress-and-waiting spec §5): one call row (with a nested P2
    // stage disclosure) plus one row per chosen project. The heading is
    // fixed for the whole run — it never rotates through fake labels, which
    // is the exact defect this replaces (`docs/40-initiatives/
    // 02-enac-self-onboarding/walkthroughs/progress-and-waiting-spec.md`).

    private var materializeView: some View {
        stepShell(
            eyebrow: "Step 8 of 9",
            title: model.projectSetupNeedsDecision ? "Some projects need another look" : "Setting up your copilots",
            intro: model.projectSetupNeedsDecision
                ? "Control Tower finished the safe work and stopped on the projects listed below. Each row explains why nothing was changed and what to do next."
                : "This part runs on its own. Keep this window open, or close it and let Control Tower finish in the menu bar."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let countLine = model.setupProgress.countLine {
                    Text(countLine)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Setting up your copilots. \(countLine)")
                }
                sectionCard("") {
                    VStack(alignment: .leading, spacing: 6) {
                        setupRow(model.setupProgress.callRow)
                        DisclosureGroup("What this includes") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(model.setupProgress.stageRows) { row in
                                    setupRow(row)
                                }
                            }
                            .padding(.top, 6)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .padding(.leading, 26)
                    }
                }
                if !model.setupProgress.projectRows.isEmpty {
                    sectionCard("Your projects") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.setupProgress.projectRows) { row in
                                setupRow(row)
                            }
                        }
                    }
                }
                if model.setupProgress.isFanningOut {
                    Text("Also checking your other projects in the background. You don't have to wait for that.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
            }
            .padding(4)
        } leadingActions: {
            if model.projectSetupNeedsDecision {
                Button("Review projects") { model.returnToFailedProjects() }
                    .buttonStyle(.bordered)
                Button("Try again") { model.retryFailedProjects() }
                    .buttonStyle(.plain)
            }
        } primaryAction: {
            if model.projectSetupNeedsDecision {
                Button("Continue without projects") { model.continueWithoutFailedProjects() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button {} label: {
                    Text("Setting up…")
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)
                .help("Setup is running. This finishes on its own.")
            }
        }
    }

    /// Every row in every Set up checklist (the call row, its nested stage
    /// disclosure, and every project row) draws through this one function —
    /// the spec's own "six distinct shapes, six distinct sentences" (§3),
    /// never colour alone. `notStarted` has no branch that reaches
    /// `CTNamedWaitSpinner`, so a never-started row can never animate.
    private func setupRow(_ row: SetupRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            setupRowGlyph(row.state)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
                Text(setupRowStateText(row.state))
                    .font(.caption)
                    .foregroundColor(setupRowStateColor(row.state))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if case .working = row.state {
                CTNamedWaitSpinner(subject: row.title)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(setupRowStateText(row.state))")
    }

    private func setupRowStateText(_ state: SetupRowState) -> String {
        switch state {
        case .notStarted: return "Not started yet."
        case .working: return "Working on it now."
        case .done(let detail): return detail
        case .deferred(let detail): return detail
        case .couldNotFinish(let detail): return detail
        case .neverReported: return "Setup didn't say what happened here."
        }
    }

    private func setupRowStateColor(_ state: SetupRowState) -> Color {
        switch state {
        case .notStarted: return Color(nsColor: .tertiaryLabelColor)
        case .working, .done, .deferred, .neverReported: return Color(nsColor: .secondaryLabelColor)
        case .couldNotFinish: return Color(nsColor: .systemOrange)
        }
    }

    @ViewBuilder
    private func setupRowGlyph(_ state: SetupRowState) -> some View {
        switch state {
        case .notStarted:
            Image(systemName: "circle")
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        case .working:
            Image(systemName: "circle.inset.filled")
                .foregroundColor(Color(nsColor: .controlAccentColor))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(nsColor: .systemGreen))
        case .deferred:
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(Color(nsColor: .systemOrange))
        case .couldNotFinish:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(nsColor: .systemOrange))
        case .neverReported:
            Image(systemName: "questionmark.circle")
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
    }

    // MARK: 9. Verify (#w8)

    /// §2.10's gate on Verify's own result (copy spec §2.6: "permitted only
    /// when the completion rule passes. If it does not, Verify renders this
    /// pattern instead. There is no hedged middle wording."). By
    /// construction, EVERY earlier stage failure already routed to Holding
    /// before Verify could ever be reached (`beginMaterialize`'s own
    /// `guard report.result == .ready`), so this is a safety net, not the
    /// common case — the one real path where it can still fail is the
    /// `codex-plugin`-excluded-when-declined edge `expectedStageIds(includeCodex:)`
    /// exists for (see that function's own doc comment).
    private var verifyCompletionPasses: Bool {
        guard let result = model.lastOnboardResult else { return false }
        return WizardModel.completionRulePasses(result: result, stages: model.lastOnboardStages, includeCodex: model.includeCodex)
    }

    private var sharedStoreIsDeferred: Bool {
        WizardModel.sharedStoreIsDeferred(model.lastOnboardStages)
    }

    /// A real (never `nil`) support block for Verify's own §2.10 fallback —
    /// unlike Holding, Verify has no single "the blocked stage that
    /// triggered this", so this picks the last stage that DID block (if
    /// any) for `stage`/`message`, and always carries app identity + CLI
    /// path + `Recorded:` regardless (`HoldingInfo.supportLines` never
    /// renders those as empty). §2.5's action table always shows `Copy
    /// details for support` somewhere on this screen, so this is never
    /// optional the way it is for H1/H5 (which show no disclosure at all).
    private var verifySupportInfo: HoldingSupportInfo {
        let blocked = model.lastOnboardStages.last(where: { $0.result == "blocked" })
        return HoldingSupportInfo(
            schemaVersion: nil,
            stage: blocked?.stage,
            result: model.lastOnboardResult?.rawValue,
            code: nil,
            message: blocked?.detail,
            recordedAt: Date()
        )
    }

    @ViewBuilder
    private var verifyView: some View {
        if case .verifying = model.phase {
            stepShell(
                eyebrow: "Step 9 of 9",
                title: "Making sure everything's current",
                intro: "The only success here is everything actually being up to date."
            ) {
                verifyingCard("Checking your setup…")
            } leadingActions: {
                EmptyView()
            } primaryAction: {
                Button {} label: { Text("Checking…") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(true)
            }
        } else if verifyCompletionPasses {
            stepShell(
                eyebrow: "Setup verified · Step 9 of 9",
                title: "Your copilots are ready",
                intro: "Control Tower checked the setup it completed. Here is what is ready now and where to go next."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionCard("Ready now") {
                        VStack(alignment: .leading, spacing: 10) {
                            completionReadyRow("Your GitHub connection")
                            wizardCopilotRoster(model.verifiedCopilotState)
                        }
                    }

                    if sharedStoreIsDeferred {
                        sectionCard("Still to do") {
                            Text("Shared team connections are not available on this Mac yet. Your existing credentials were kept, and you can check again later from Control Tower.")
                                .font(.callout)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !model.adoptionRollbackPaths.isEmpty {
                        Text("Your previous setup was preserved in a rollback copy.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }

                    if let body = doneProjectsCardBody {
                        sectionCard("Your projects") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(body)
                                    .font(.callout)
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let report = model.verifiedWorkspacesReport {
                                    Text(wizardVerifiedProjectSummary(report))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(Color(nsColor: .labelColor))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    sectionCard("What happens next") {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "menubar.rectangle")
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .accessibilityHidden(true)
                            Text("Control Tower now lives in your menu bar. Look for the aviators: a quiet icon means there is nothing you need to do. If something needs you, Control Tower will show a small status badge and explain the next step.")
                                .font(.callout)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    videoLinkRow("See what you can build")
                }
            } leadingActions: {
                EmptyView()
            } primaryAction: {
                Button { model.finish(onClose: onClose) } label: { Text("Finish setup") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            // The completion rule failed on a HEALTHY doctor result (the
            // only way to reach `.verified` at all) — §2.10, never a
            // resolved-sounding "Everything checks out." `Done` (step 10)
            // is unreachable from here on purpose: this screen's own action
            // set (§2.5) replaces `Continue` entirely, so a person can never
            // click through to "You have the tools, go change the world"
            // on the strength of a report that does not prove it.
            honestIncompleteView(
                reachedFromDecision: false,
                stages: model.lastOnboardStages,
                includeCodex: model.includeCodex,
                support: verifySupportInfo,
                isRepeat: false,
                hasAskRows: !model.onboardQuestionItems.isEmpty,
                completedActions: model.lastCompletedActions,
                resume: model.lastResume,
                onTryAgain: { model.beginVerify() }
            )
        }
    }

    private func completionReadyRow(_ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(nsColor: .systemGreen))
                .accessibilityHidden(true)
            Text(title)
                .font(.callout)
                .foregroundColor(Color(nsColor: .labelColor))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), verified")
    }

    private func wizardCopilotRoster(_ state: RenderState?, checking: Bool = false) -> some View {
        let names = ["Knowledge Copilot", "CLI Copilot", "Claude Copilot", "Codex Copilot"]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(names.enumerated()), id: \.element) { index, name in
                let component = state?.components.first(where: {
                    $0.component.lowercased().contains(name.replacingOccurrences(of: " Copilot", with: "").lowercased())
                })
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: checking ? "circle.dotted" : component?.worstSeverity == .pass ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundColor(
                            checking
                                ? Color(nsColor: .secondaryLabelColor)
                                : component?.worstSeverity == .pass
                                    ? Color(nsColor: .systemGreen)
                                    : Color(nsColor: .secondaryLabelColor)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.callout.weight(.semibold))
                        Text(wizardCopilotStatus(name: name, component: component, checking: checking))
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.vertical, 7)
                if index < names.count - 1 { Divider() }
            }
        }
    }

    private func wizardCopilotStatus(
        name: String,
        component: ComponentView?,
        checking: Bool
    ) -> String {
        if checking { return "Checking this Mac and its inherited layers…" }
        if name == "Codex Copilot", !model.includeCodex { return "Not included by your choice." }
        guard let component else { return "Not reported by the setup check." }
        let verdict = component.worstSeverity == .pass
            ? "Ready"
            : component.worstSeverity == .warn ? "Needs review" : "Needs attention"
        let layers = component.layers.map { "\($0.layer.label): \($0.severity.rawValue)" }.joined(separator: " · ")
        return layers.isEmpty ? verdict : "\(verdict) · \(layers)"
    }

    private func wizardVerifiedProjectSummary(_ report: WorkspacesReport) -> String {
        let ready = report.workspaces.filter { $0.classification == .ready }.count
        let safe = report.workspaces.filter { $0.classification == .safeFinish }.count
        let guided = report.workspaces.filter { $0.classification == .guidedIntegration }.count
        let owner = report.workspaces.filter { $0.classification == .ownerDecision }.count
        let unverified = report.workspaces.filter { $0.classification == .couldNotVerify }.count
        return "\(report.workspaces.count) total · \(ready) ready · \(safe) safe finish · \(guided) guided · \(owner) owner decision · \(unverified) couldn't verify"
    }

    /// Completion's project variants — the card is absent entirely for
    /// `.declined`, per the spec's own table.
    private var doneProjectsCardBody: String? {
        switch model.projectsStepOutcome {
        case .declined:
            return nil
        case .skipped:
            return "You skipped projects for now. Point Control Tower at your projects folder any time from the menu bar."
        case .setUp(let succeeded, let total) where succeeded == total && total > 0:
            return "Your copilots are set up in \(total) of your \(total) project\(total == 1 ? "" : "s"). Any new project you create in that folder gets them automatically."
        case .setUp(let succeeded, let total) where total > 0:
            let failed = total - succeeded
            let failedClause = failed == 1
                ? "One needs another look, and it's waiting for you in the menu bar."
                : "\(failed) need another look, and they're waiting for you in the menu bar."
            return "Your copilots are set up in \(succeeded) of your \(total) project\(total == 1 ? "" : "s"). \(failedClause) Nothing existing was changed."
        case .setUp, .notReached:
            return nil
        }
    }

    // MARK: Holding (#w10) — seven variants (`control-tower-copy-deck.md`
    // §2.9), chosen by WHO OWNS THE FIX (invariant #5), never by what went
    // wrong. Every variant reuses the SAME `StepShell` anatomy; only
    // eyebrow/title/intro/content/actions/tint differ per `HoldingInfo`
    // (built in `WizardModel`'s Holding section above — this is render-only,
    // no decision-making).

    @ViewBuilder
    private func holdingView(_ info: HoldingInfo) -> some View {
        if info.variant == .yours && model.holdingConfirmed {
            // H4's confirmation is ALWAYS §2.10, never a resolved-sounding
            // screen: H4 is reachable only from `result: "blocked"`, so the
            // completion rule can never pass at this moment — there is no
            // boolean left to check, and conditioning one would imply a
            // passing case exists (copy spec §2.1/§2.6). The withdrawn
            // `Kept as it is` confirmation used to render here instead.
            honestIncompleteView(
                reachedFromDecision: true,
                stages: info.stages,
                includeCodex: model.includeCodex,
                support: info.support,
                isRepeat: info.isRepeat,
                hasAskRows: !model.onboardQuestionItems.isEmpty,
                completedActions: info.completedActions,
                resume: info.resume,
                onTryAgain: { model.tryAgainAfterHolding() }
            )
        } else {
            switch info.variant {
            case .notInstalled: h1View(info)
            case .unreadable: h2View(info)
            case .fault: h3View(info)
            case .yours: h4View(info)
            case .waitingOffline, .waitingBusy: h5View(info)
            case .waitingOnOrg: h6View(info)
            case .needsPermission: h7View(info)
            }
        }
    }

    /// H1 — not installed. Deliberately not red (§1): neutral tint, no
    /// "Details for support" disclosure at all (there is nothing on this
    /// Mac yet to report on), no command/path in the body (`showInstallSheet()`
    /// is the one deliberate tap that reveals it, §4.1).
    private func h1View(_ info: HoldingInfo) -> some View {
        stepShell(eyebrow: info.eyebrow, title: info.title, intro: info.intro, focusTitle: $holdingTitleFocused) {
            if info.isRepeat {
                stillTheSameCaption
            }
        } leadingActions: {
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Button { model.tryAgainAfterHolding() } label: { Text("Check again") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            Button { showInstallSheet() } label: { Text("Show me how to install it") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .headerTint(info.variant.tint)
    }

    /// H2 — can't read your setup. Content is the support disclosure and
    /// nothing else (§1: no framed CLI line for a call-level failure). A
    /// bare `CliError` carries no ledger/resume evidence of its own (it
    /// never reached a decodable report), so `info.retryable` is always its
    /// default `true` here — this is a genuine call-level failure, always
    /// worth another try — but the primary still reads it rather than
    /// hardcoding `Try again`, so H2 and H3 share one rule (task 210/G-7).
    private func h2View(_ info: HoldingInfo) -> some View {
        stepShell(eyebrow: info.eyebrow, title: info.title, intro: info.intro, focusTitle: $holdingTitleFocused) {
            VStack(alignment: .leading, spacing: 16) {
                if info.isRepeat {
                    stillTheSameCaption
                }
                if let support = info.support {
                    HoldingSupportDisclosureView(lines: HoldingInfo.supportLines(support))
                }
            }
        } leadingActions: {
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            if info.retryable {
                Button { model.tryAgainAfterHolding() } label: { Text("Try again") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { onClose() } label: { Text("Continue in the menu bar") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .headerTint(info.variant.tint)
    }

    /// H3 — couldn't finish a part of setup. The framed CLI line appears
    /// only for the one gate (`personal-packages`, no review item) the spec
    /// marks "frame"; every other H3 gate's `framedDetail` is `nil`.
    ///
    /// Task 210/G-7: `Try again` renders ONLY when `info.retryable` — a
    /// Git-history review block (the `visible-repositories` classifier,
    /// `WizardModel.holdingInfo(forBlockedOnboard:)`) sets this `false`
    /// because retrying cannot change it; every other H3 cause keeps the
    /// prior unconditional `true`. When `false`, the primary falls back to
    /// `Continue in the menu bar` (the same fallback H6 already uses when
    /// it has no support disclosure to lead with) rather than an empty slot.
    ///
    /// Task 211/G-4b: a non-empty ledger renders its own card (what's
    /// already done, and the safe next step from `resume`) — this is the
    /// SAME screen four of the five now-conditional "nothing changed"
    /// intros land on, so this is where that evidence actually needs to
    /// show, not just where the false claim needed removing.
    private func h3View(_ info: HoldingInfo) -> some View {
        let ledger = WizardModel.groupedLedgerLines(info.completedActions)
        return stepShell(eyebrow: info.eyebrow, title: info.title, intro: info.intro, focusTitle: $holdingTitleFocused) {
            VStack(alignment: .leading, spacing: 16) {
                if info.isRepeat {
                    stillTheSameCaption
                }
                if let framedDetail = info.framedDetail {
                    FramedCliDetailView(detail: framedDetail)
                }
                if info.hasCompletedWork {
                    sectionCard("What's already done") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ledger.completed, id: \.self) { bulletRow($0) }
                            ForEach(ledger.rolledBack, id: \.self) { bulletRow($0) }
                            if let resume = info.resume {
                                Text(resume.detail)
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let support = info.support {
                    HoldingSupportDisclosureView(lines: HoldingInfo.supportLines(support))
                }
            }
        } leadingActions: {
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            if info.retryable {
                Button { model.tryAgainAfterHolding() } label: { Text("Try again") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { onClose() } label: { Text("Continue in the menu bar") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .headerTint(info.variant.tint)
    }

    /// H4 — something here is already yours: the "ask" body, before `Keep
    /// what I have`. `honestIncompleteView` (§2.10) is the body after,
    /// rendered by `holdingView`'s own `model.holdingConfirmed` branch.
    private func h4View(_ info: HoldingInfo) -> some View {
        stepShell(eyebrow: info.eyebrow, title: info.title, intro: info.intro, focusTitle: $holdingTitleFocused) {
            VStack(alignment: .leading, spacing: 16) {
                if info.isRepeat {
                    stillTheSameCaption
                }
                if let framedDetail = info.framedDetail {
                    FramedCliDetailView(detail: framedDetail)
                }
                if !info.reviewItems.isEmpty {
                    sectionCard("What I left alone") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(info.reviewItems) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.callout.weight(.semibold))
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                Text("Nothing was changed, moved, or removed.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                if let support = info.support {
                    HoldingSupportDisclosureView(lines: HoldingInfo.supportLines(support))
                }
            }
        } leadingActions: {
            // "Holding stops being reachable by refusal and becomes
            // reachable only by the person's own choice or by a genuine
            // outside failure" — this leading action only appears when
            // there is an actual question to return to (cached from the
            // last plan that carried one); it is never fabricated for a
            // Holding reached some other way.
            if !model.onboardQuestionItems.isEmpty {
                Button { model.returnToOnboardQuestion() } label: { Text("Include what I already have") }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            // `Let setup manage it` renders NOWHERE today (§4: "today
            // exactly one consent path exists ... consumed before the
            // block, by the existing 'One question first' screen") — this
            // slot always shows `Check again` instead. Never wire a
            // speculative consent button here; offering a permission the
            // CLI will not honor is the same lie this change removes.
            Button { model.tryAgainAfterHolding() } label: { Text("Check again") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            Button { model.keepWhatIHave() } label: { Text("Keep what I have") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .headerTint(info.variant.tint)
    }

    /// §2.10, "I stopped, and here's what that means for you" — the pattern
    /// EVERY terminal confirmation in the wizard falls back to whenever
    /// `WizardModel.completionRulePasses` fails (H4's confirmation renders
    /// this UNCONDITIONALLY — see that call site's own comment for why no
    /// check is needed there). Replaces the withdrawn `Kept as it is`
    /// confirmation, which was true about the decision and false about
    /// setup, and printed only the true half.
    ///
    /// Never reached with an empty "doesn't work yet" card in practice —
    /// every call site above only renders this when the completion rule has
    /// already failed, which by construction means at least one capability
    /// row landed in `notYet` (copy spec: "If this card would be empty, the
    /// rule passed and this screen must not render at all" is therefore the
    /// CALLER's gate, not a check repeated here).
    private func honestIncompleteView(
        reachedFromDecision: Bool,
        stages: [EcosystemOnboardStage],
        includeCodex: Bool,
        support: HoldingSupportInfo?,
        isRepeat: Bool,
        hasAskRows: Bool,
        completedActions: [CompletedAction] = [],
        resume: ResumeHint? = nil,
        onTryAgain: @escaping () -> Void
    ) -> some View {
        let rows = WizardModel.honestCapabilityRows(stages: stages, includeCodex: includeCodex)
        // Task 211/G-4b: a blanket "nothing was changed" claim is false the
        // moment this run's own `completed_actions` ledger is non-empty —
        // this screen used to assert it unconditionally. The alternative
        // intro makes no claim of its own; the ledger card below (added
        // only when non-empty) is what actually says what happened.
        let hasCompletedWork = !completedActions.isEmpty
        let ledger = WizardModel.groupedLedgerLines(completedActions)
        return stepShell(
            eyebrow: "SETUP ISN'T FINISHED",
            title: "Here's where that leaves you",
            intro: reachedFromDecision
                ? "I left your own things exactly as they were. Setup stopped there, though, so some of this isn't set up yet."
                : (
                    hasCompletedWork
                        ? "Setup stopped partway, so some of this isn't set up yet. Here's what's already done, and what's next."
                        : "Setup stopped partway, so some of this isn't set up yet. Nothing that was already on this Mac was changed."
                ),
            focusTitle: $holdingTitleFocused
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if isRepeat {
                    stillTheSameCaption
                }
                sectionCard("What works now") {
                    if rows.worksNow.isEmpty {
                        Text("Nothing yet. Setup stopped before anything was put in place.")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(rows.worksNow, id: \.self) { bulletRow($0) }
                        }
                    }
                }
                sectionCard("What doesn't work yet") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows.notYet, id: \.self) { bulletRow($0) }
                    }
                }
                // Task 211/G-4b: what this run actually created or changed
                // before it stopped — rendered from the CLI's own
                // `completed_actions` ledger summaries (never a raw Git
                // error, never a bare SHA), grouped into what's done and
                // what was undone. Only appears when there is something to
                // say; an empty ledger keeps the plain "nothing changed"
                // footer below instead of an empty card.
                if hasCompletedWork {
                    sectionCard("What's already done") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ledger.completed, id: \.self) { bulletRow($0) }
                            ForEach(ledger.rolledBack, id: \.self) { bulletRow($0) }
                            if let resume {
                                Text(resume.detail)
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                // Never-destroy holds regardless of the ledger (this claim
                // is about content the person ALREADY had before this run,
                // which this app never touches either way, unlike the
                // ledger-conditional intro above) — stays unconditional.
                Text("Nothing you already had was changed, moved, or removed.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                if let support {
                    HoldingSupportDisclosureView(lines: HoldingInfo.supportLines(support))
                }
            }
        } leadingActions: {
            // §2.5's "one branch": an ask row still on the table always
            // outranks a handoff, so `Include what I already have` takes
            // the primary slot and `Copy details for support` moves here.
            if hasAskRows {
                Button { model.returnToOnboardQuestion() } label: { Text("Include what I already have") }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            } else if let support {
                CopyDetailsForSupportButton(lines: HoldingInfo.supportLines(support))
            }
            Button { onTryAgain() } label: { Text("Try again") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            if hasAskRows {
                Button { model.returnToOnboardQuestion() } label: { Text("Include what I already have") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else if let support {
                CopyDetailsForSupportButton(lines: HoldingInfo.supportLines(support), prominent: true)
            }
        }
    }

    /// H5 — waiting (offline / busy). No content besides the repeat
    /// caption, no disclosure (§1: "there is nothing for IT to act on").
    private func h5View(_ info: HoldingInfo) -> some View {
        stepShell(eyebrow: info.eyebrow, title: info.title, intro: info.intro, focusTitle: $holdingTitleFocused) {
            if info.isRepeat {
                stillTheSameCaption
            }
        } leadingActions: {
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            Button { model.tryAgainAfterHolding() } label: { Text("Try again") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .headerTint(info.variant.tint)
    }

    /// H6 — waiting on your organization. The one variant whose primary is
    /// not a retry (§1: "retrying cannot change the outcome"). Defect 1a: a
    /// genuine end user reading H6 has exactly one real action (tell their
    /// admin, with the details attached), so — the same call §2.10 already
    /// made for "Here's where that leaves you" — `Copy details for support`
    /// is the PROMINENT primary here too, never a buried disclosure, and the
    /// footer caption names who picks this up, instead of implying (falsely,
    /// for whoever actually IS that admin — Defect 1b, `h7ForOrgSignIn`
    /// above) that there is nothing anyone can do yet.
    private func h6View(_ info: HoldingInfo) -> some View {
        stepShell(eyebrow: info.eyebrow, title: info.title, intro: info.intro, focusTitle: $holdingTitleFocused) {
            VStack(alignment: .leading, spacing: 16) {
                if info.isRepeat {
                    stillTheSameCaption
                }
                if let support = info.support {
                    HoldingSupportDisclosureView(
                        lines: HoldingInfo.supportLines(support),
                        expandedCaption: "Send this to whoever looks after your Mac."
                    )
                }
                Text("Whoever looks after your Mac can pick this up from here.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        } leadingActions: {
            // Copy spec §5's "escape from H6": only shown when this hold was
            // reached as the direct consequence of an organization name just
            // supplied at §2.1.1 — never fabricated for a `no-company-app`
            // reached any other way (e.g. an already-configured Mac).
            if info.orgNameForReturn != nil {
                Button { model.useADifferentOrganization() } label: { Text("Use a different organization") }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            Button { model.tryAgainAfterHolding() } label: { Text("Check again") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            if let support = info.support {
                CopyDetailsForSupportButton(lines: HoldingInfo.supportLines(support), prominent: true)
            } else {
                Button { onClose() } label: { Text("Continue in the menu bar") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .headerTint(info.variant.tint)
    }

    /// H7 — something only you can do. Two flavors of the SAME variant
    /// (§2.9's owner test, not two different taxonomy entries): the existing
    /// GitHub-permission grant (`h7GitHubPermissionView`) when
    /// `info.selfServeCommand` is `nil`, and the self-serve org-sign-in
    /// command (`h7OrgSignInView`, Defect 1b) when it isn't.
    @ViewBuilder
    private func h7View(_ info: HoldingInfo) -> some View {
        if let command = info.selfServeCommand {
            h7OrgSignInView(info, command: command)
        } else {
            h7GitHubPermissionView(info)
        }
    }

    /// H7, self-serve org-sign-in flavor (Defect 1b): unlike the GitHub
    /// permission grant below, there is no interactive flow the app can
    /// drive here — the fix is a terminal command this Mac's own admin can
    /// run. Follows H1's own discipline instead (§2.9.2: "The H1 body itself
    /// never contains a command... only the sheet does"): the body never
    /// shows the raw command, and the primary opens a sheet that does,
    /// exactly like `showInstallSheet()`/`InstallHelperSheet` above.
    private func h7OrgSignInView(_ info: HoldingInfo, command: String) -> some View {
        stepShell(eyebrow: info.eyebrow, title: info.title, intro: info.intro, focusTitle: $holdingTitleFocused) {
            VStack(alignment: .leading, spacing: 16) {
                if info.isRepeat {
                    stillTheSameCaption
                }
                if let support = info.support {
                    HoldingSupportDisclosureView(lines: HoldingInfo.supportLines(support))
                }
            }
        } leadingActions: {
            // Copy spec §5's "escape from H6" — see `h6View`'s identical
            // comment; this self-serve H7 flavor is only ever reached via
            // the same `no-company-app` code, so it carries the same escape.
            if info.orgNameForReturn != nil {
                Button { model.useADifferentOrganization() } label: { Text("Use a different organization") }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Button { model.tryAgainAfterHolding() } label: { Text("Check again") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            Button { showsOrgSignInSheet = true } label: { Text("Show me the command") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .headerTint(info.variant.tint)
    }

    /// H7, the existing GitHub-permission-grant flavor (copy spec §3,
    /// Appendix D.2). The owner of this fix is the person and can be nobody
    /// else — it is a permission on his own GitHub sign-in, so `Grant this
    /// on GitHub` is a PRIMARY that actually drives the flow
    /// (`model.beginGrantFlow()`), never a copyable command. `Show me how to
    /// grant it` renders ONLY once `model.grantUnavailableKnown` is true —
    /// a real state the CLI (or its own absence on this Mac) reported this
    /// session, never a speculative "just in case" fallback shown up front
    /// (§3.4: "that state is the only thing that reveals the fallback").
    private func h7GitHubPermissionView(_ info: HoldingInfo) -> some View {
        stepShell(eyebrow: info.eyebrow, title: info.title, intro: info.intro, focusTitle: $holdingTitleFocused) {
            VStack(alignment: .leading, spacing: 16) {
                if info.isRepeat {
                    stillTheSameCaption
                }
                if let support = info.support {
                    HoldingSupportDisclosureView(lines: HoldingInfo.supportLines(support))
                }
                // §3.3's quiet caption, "above the footer" — the last thing
                // in `content`, which sits immediately above `StepShell`'s
                // footer divider.
                Text("I'll take you to GitHub to grant it. Nothing on this Mac changes.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        } leadingActions: {
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            if model.grantUnavailableKnown {
                Button { showsGrantFallbackSheet = true } label: { Text("Show me how to grant it") }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        } primaryAction: {
            Button {
                model.beginGrantFlow()
                showsGrantSheet = true
            } label: {
                Text("Grant this on GitHub")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .headerTint(info.variant.tint)
    }

    /// §4's own words: "On a repeat of the identical hold, add one
    /// caption" — shown only from the second consecutive identical hold
    /// onward (`HoldingInfo.isRepeat`), under the intro, above everything
    /// else in `content`.
    private var stillTheSameCaption: some View {
        Text("Still the same. Nothing changed.")
            .font(.caption)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
    }

    // MARK: Shared shell + components (same anatomy as publisher_setup.swift)

    private func stepShell<Content: View, Leading: View, Trailing: View>(
        eyebrow: String,
        title: String,
        intro: String? = nil,
        focusTitle: AccessibilityFocusState<Bool>.Binding? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder leadingActions: () -> Leading,
        @ViewBuilder primaryAction: () -> Trailing
    ) -> StepShell<Content, Leading, Trailing> {
        StepShell(eyebrow: eyebrow, title: title, intro: intro, focusTitle: focusTitle, content: content, leadingActions: leadingActions, primaryAction: primaryAction)
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CTSpace.md) {
            if !title.isEmpty {
                CTCardTitle(title)
            }
            content()
        }
        .ctCard()
    }

    /// The Welcome/What-you're-getting read-only rows (`.confirm-row`).
    private func confirmRow(name: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.callout.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
            Text(desc)
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Text(text)
                .font(.callout)
                .foregroundColor(Color(nsColor: .labelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func verifyingCard(_ status: String) -> some View {
        VStack(spacing: 12) {
            CTNamedWaitSpinner(subject: status)
            Text(status)
                .font(.callout)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Every video affordance in this file is an inert link-out placeholder
    /// (no real URL exists yet, per the task contract) — a small "YouTube"
    /// hint chip, never an embedded player.
    private func videoLinkRow(_ caption: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "play.circle")
                .foregroundColor(Color(nsColor: .controlAccentColor))
            Text(caption)
                .font(.callout.weight(.semibold))
                .foregroundColor(Color(nsColor: .controlAccentColor))
            Text("YouTube")
                .font(.caption2.monospaced())
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption), placeholder link, opens YouTube")
    }
}

// MARK: - Holding support views (`holding-copy-spec.md` §2.2, §5, §4.1)
//
// Four small, self-contained views used only by `WizardRootView`'s Holding
// section above. Kept top-level (not nested) so their bodies stay flat and
// each is independently previewable/testable, same convention as
// `CTNamedWaitSpinner`/`StepShell` elsewhere in this file.

/// §2.2 rule 2: the CLI's own (already-presentable, non-technical) stage
/// `detail`, framed under its own label, capped at three lines with a
/// `Show more` toggle, never interpolated into an app sentence (rule 4).
private struct FramedCliDetailView: View {
    let detail: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What setup found:")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .textCase(.uppercase)
            Text(detail)
                .font(.body)
                .foregroundColor(Color(nsColor: .labelColor))
                .textSelection(.enabled)
                .lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if !expanded {
                Button("Show more") { expanded = true }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .linkColor))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// §2.9.1's "Details for support" — one component, collapsed by default,
/// never self-expanding, on H2/H3/H4/H6/H7/§2.10. `expandedCaption` defaults
/// to §2.9.1's own line; H6 overrides it with its own shorter one (§1:
/// "expanded label caption reads `Send this to whoever looks after your
/// Mac.`").
private struct HoldingSupportDisclosureView: View {
    let lines: [String]
    var expandedCaption = "Send this to whoever looks after your Mac. It has nothing private in it."
    @State private var copied = false

    var body: some View {
        DisclosureGroup("Details for support") {
            VStack(alignment: .leading, spacing: 10) {
                Text(expandedCaption)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Text(lines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    Text(copied ? "Copied" : "Copy details")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(copied ? "Copied" : "Copy details")
            }
            .padding(.top, 8)
        }
        .font(.callout.weight(.semibold))
        .accessibilityLabel("Details for support")
    }
}

/// §2.10's own prominent "Copy details for support" button (§2.5: "Prominence
/// comes from the button, not from forcing the block open") — the SAME
/// clipboard write `HoldingSupportDisclosureView`'s inner "Copy details"
/// button does, just directly reachable without expanding the disclosure
/// first, so whoever needs to hand it over copies it in one click.
private struct CopyDetailsForSupportButton: View {
    let lines: [String]
    var prominent = false
    @State private var copied = false

    private var label: String { copied ? "Copied" : "Copy details for support" }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    var body: some View {
        if prominent {
            Button { copy() } label: { Text(label) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(label)
        } else {
            Button { copy() } label: { Text(label) }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .accessibilityLabel(label)
        }
    }
}

/// The mono code-block-plus-copy-affordance pattern (visual-system §2.1),
/// scoped to the User build's Holding surface. `native/admin.swift` defines
/// its OWN `CopyableCodeBlock` for the SAME pattern, but that file is
/// Admin-only (`scripts/build-admin.command`) while this one — Holding's H1
/// install sheet — must also link into the User build
/// (`scripts/build-user.command`, which never includes `admin.swift`); a
/// shared name would collide when both files ARE compiled together for the
/// Admin binary, so this is deliberately its own, differently-named type
/// rather than a cross-target reference.
private struct WizardCopyableCodeBlock: View {
    let text: String
    var copyLabel = "Copy these steps"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundColor(Color(nsColor: .labelColor))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                Text(copied ? "Copied" : copyLabel)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(copied ? "Copied" : copyLabel)
        }
    }
}

/// H1's forward step (§4.1) — a sheet over the wizard, not a new window.
/// The install steps are the four lines from
/// `docs/06-deployment/ground-up-claude-codex-installation.md:48-53`, in a
/// mono block, never wrapped into prose; the body of H1 itself (`h1View`
/// above) never contains a command, a path, or the word `cc` — the command
/// lives behind this one deliberate tap.
private struct InstallHelperSheet: View {
    /// Fires once, automatically, when `Done` closes the sheet ("the user
    /// should not have to find the button that proves the thing they just
    /// did") — the caller both dismisses the sheet and fires `Check again`.
    let onDone: () -> Void

    private static let steps = """
    mkdir -p "$HOME/.claude"
    git clone https://github.com/Everyone-Needs-A-Copilot/claude-copilot.git "$HOME/.claude/copilot"
    bash "$HOME/.claude/copilot/tools/cc/install.sh"
    "$HOME/.local/bin/cc" --version
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Installing the setup helper")
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))

            Text("This is one command for whoever set up this Mac. If that's you, paste it into Terminal. If it isn't, copy it and send it to them.")
                .font(.body)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("The steps")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .textCase(.uppercase)
                WizardCopyableCodeBlock(text: Self.steps)
            }

            Link("Open the install guide ›", destination: URL(string: "https://github.com/Everyone-Needs-A-Copilot/claude-copilot")!)
                .font(.callout.weight(.semibold))

            Spacer()

            HStack {
                Spacer()
                Button {
                    onDone()
                } label: {
                    Text("Done")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 420)
    }
}

/// H7's forward step (§2.9.3) — verbatim reuse of §2.5.1's device-flow
/// grammar (the same shape `connectGitHubView` already renders), just a
/// sheet instead of a wizard step, since the person is already mid-Holding.
/// Opens the instant `Grant this on GitHub` is tapped, while
/// `model.grantFlow.status` is still `.pending` — so `.idle`/`.pending`
/// render the same "waiting for a code" shape `connectGitHubView` does
/// rather than a blank sheet. The `.unavailable` case renders NOTHING and
/// dismisses itself on appearance: no code was ever issued for that state,
/// and closing immediately is what reveals H7's `Show me how to grant it`
/// leading action (`model.grantUnavailableKnown` — copy spec §3.4, "that
/// state is the only thing that reveals the fallback").
private struct GrantPermissionSheet: View {
    @ObservedObject var model: WizardModel
    let onDismiss: () -> Void
    let onGranted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch model.grantFlow.status {
            case .idle, .pending:
                pendingBody
            case .granted:
                grantedBody
            case .denied:
                terminalBody(message: "That was declined.", actionLabel: "Try again")
            case .expired:
                terminalBody(message: "That code expired.", actionLabel: "Get a new code")
            case .identityMismatch:
                terminalBody(
                    message: "GitHub confirmed a different account, so nothing changed.",
                    actionLabel: "Try again"
                )
            case .insufficientScope:
                terminalBody(
                    message: "GitHub did not grant the permission this Mac needs.",
                    actionLabel: "Try again"
                )
            case .timedOut:
                terminalBody(message: "That took too long.", actionLabel: "Get a new code")
            case .unavailable:
                Color.clear
                    .onAppear { onDismiss() }
            }
        }
        .padding(28)
        .frame(width: 460, height: 360)
    }

    private var pendingBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Grant the permission")
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
            Text("GitHub will ask you to confirm this. Copy the code below, open the page, and paste it in.")
                .font(.body)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Your code")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .textCase(.uppercase)
                HStack {
                    Text(model.grantFlow.userCode ?? "")
                        .font(.title3.monospaced())
                        .textSelection(.enabled)
                        .foregroundColor(Color(nsColor: .labelColor))
                    Spacer()
                    Button { model.copyGrantCode() } label: { Text("Copy code") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.grantFlow.userCode == nil)
                }
            }

            Button { model.openGrantGitHubPage() } label: { Text("Open the GitHub page") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.grantFlow.verificationUri == nil)

            Text("Waiting for you to finish in your browser…")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))

            Spacer()

            HStack {
                Spacer()
                Button { model.cancelGrantFlow(); onDismiss() } label: { Text("Cancel") }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var grantedBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(nsColor: .systemGreen))
                Text("Granted. Picking up where I left off.")
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
            }
            Spacer()
            HStack {
                Spacer()
                Button { onGranted() } label: { Text("Done") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func terminalBody(message: String, actionLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(message)
                .font(.body)
                .foregroundColor(Color(nsColor: .labelColor))
            Spacer()
            HStack {
                Button { onDismiss() } label: { Text("Cancel") }
                    .buttonStyle(.bordered)
                Spacer()
                Button { model.retryGrantFlow() } label: { Text(actionLabel) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// The fallback sheet behind H7's `Show me how to grant it` (§2.9.3,
/// shaped after §2.9.2's install sheet) — shown only when the CLI reports
/// (or its own absence on this Mac implies) it cannot drive the grant flow
/// itself. Never contains a path or the phrase "permission scope".
private struct GrantFallbackSheet: View {
    /// Closes the sheet AND re-checks once, automatically ("the user should
    /// not have to find the button that proves the thing they just did") —
    /// same contract as `InstallHelperSheet.onDone` above.
    let onDone: () -> Void

    private static let step = "gh auth refresh -h github.com -s write:public_key"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Granting the permission by hand")
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))

            Text("This is one command. If you're comfortable in Terminal, paste it there. If you're not, copy it and send it to whoever looks after your Mac.")
                .font(.body)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("The step")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .textCase(.uppercase)
                WizardCopyableCodeBlock(text: Self.step, copyLabel: "Copy this step")
            }

            Spacer()

            HStack {
                Spacer()
                Button { onDone() } label: { Text("Done") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 320)
    }
}

/// H7's self-serve org-sign-in forward step (Defect 1b) — the sheet behind
/// `h7OrgSignInView`'s primary, same shape as `GrantFallbackSheet` above
/// (one command, "The step" label): unlike the GitHub-permission grant,
/// there is no interactive flow to drive, so this IS the fix, not a
/// fallback. `command` is always the exact, already-verified value read
/// back from this Mac's own admin brief (`HoldingInfo.selfServeCommand`,
/// `LocalAdminSignal.standupGitHubAppClientID`) — never a placeholder.
private struct OrgSignInIDSheet: View {
    let command: String
    /// Closes the sheet AND re-checks once, automatically — same contract
    /// as `InstallHelperSheet.onDone`/`GrantFallbackSheet.onDone` above.
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Giving this Mac your organization's sign-in ID")
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))

            Text("This is one command for whoever set up this Mac. If that's you, paste it into Terminal. It only tells this Mac the ID your organization's sign-in already has; it changes nothing else.")
                .font(.body)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("The step")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .textCase(.uppercase)
                WizardCopyableCodeBlock(text: command, copyLabel: "Copy this step")
            }

            Spacer()

            HStack {
                Spacer()
                Button { onDone() } label: { Text("Done") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 320)
    }
}

/// §2.1.2, the sheet behind the organization question's `Help me find it` —
/// §2.9.2's pattern inverted (copy spec §4): there the block holds a command
/// for a technical person to run; here the person is missing a fact that
/// belongs to their admin, so the copyable block IS the message that asks
/// for it, already written. Never links to GitHub — opening the
/// organization's own page requires the very thing they don't have. Unlike
/// every Holding sheet above, `onDone` never re-checks anything: it just
/// returns focus to the field on the same, still-active screen.
private struct OrgHelpSheet: View {
    let onDone: () -> Void

    private static let message = "Hi, I'm setting up Copilot Control Tower on my Mac. It's asking for our organization's name on GitHub, the short name in our GitHub address. Can you send it to me?"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Finding your organization's name")
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))

            Text("It's on the page you downloaded Control Tower from, and in the email that sent you there. If you can't find either, send this to whoever looks after your Mac.")
                .font(.body)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("The message")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .textCase(.uppercase)
                WizardCopyableMessageBlock(text: Self.message, copyLabel: "Copy this message")
            }

            Spacer()

            HStack {
                Spacer()
                Button { onDone() } label: { Text("Done") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480, height: 320)
    }
}

/// The prose counterpart to `WizardCopyableCodeBlock` — same copy-button
/// plumbing, but `.body`/non-monospaced, since the copyable content here is
/// a sentence a person reads and sends, never a command.
private struct WizardCopyableMessageBlock: View {
    let text: String
    var copyLabel = "Copy this message"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .foregroundColor(Color(nsColor: .labelColor))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                Text(copied ? "Copied" : copyLabel)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(copied ? "Copied" : copyLabel)
        }
    }
}

// MARK: - Wizard window controller

/// Owns the wizard's single `NSWindow` + its `WizardModel` for the lifetime of
/// the app. A singleton (`shared`) so both entry points — the popover's
/// "Set up" action and the tray's dev-only "Open Wizard (dev)" menu item
/// (`control-tower-tray.swift`) — reuse the SAME window/model instead of
/// spawning a second wizard. `isReleasedWhenClosed = false` so closing the
/// window (Done / the titlebar close button) never deallocates it — the next
/// `show()` reopens the same window with whatever state it was last in.
final class WizardWindowController: NSWindowController {
    static let shared = WizardWindowController()

    private let model = WizardModel()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Copilot Control Tower"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: WizardRootView(model: model, onClose: { [weak window] in window?.close() })
        )
    }

    func show() {
        #if CT_VISUAL_TEST_BUILD
        if let scenario = ProcessInfo.processInfo.environment["CT_VISUAL_SCENARIO"] {
            model.loadVisualScenario(scenario)
        }
        #endif
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // SELFTEST HOOK (harness contract) — see `WizardSelftest`'s own doc.
        // `AppDelegate.applicationDidFinishLaunching` (`control-tower-tray.swift`)
        // already calls `show()` when `CT_OPEN_WIZARD=1`; this only ever adds
        // work when `CT_SELFTEST=1` is ALSO set, so a normal launch (or a
        // dev "Open Wizard" click) is unaffected.
        WizardSelftest.runIfRequested()
    }

    /// Settings' explicit "Choose projects to set up…" route. This does not
    /// reset the completed-first-run flag or replay Welcome; it opens the
    /// existing project step, which performs its normal read-only load and
    /// asks before every project write.
    func reopenForProjects(category: ProjectTriageCategory? = nil) {
        model.enterProjectsStep()
        if let category {
            model.showProjectCategory(category)
        } else {
            model.showProjectOverview()
        }
        show()
    }

    /// Settings' "Finish Personal Setup" route. Re-run Detect so the helper
    /// produces a fresh all-four-component plan; opening Settings itself
    /// remains read-only and no repository is created until the person
    /// reviews and runs the normal Set up transaction.
    func reopenForPersonalSetup() {
        model.runDetect()
        show()
    }

    /// Region 6's `connection-offer` notice (`native/control-tower-tray.swift`):
    /// reopens this SAME wizard singleton positioned at the onboarding
    /// question. If this session already answered it once (`Not now` from
    /// an earlier visit this launch), `onboardQuestionItems` still holds the
    /// cached ask row, and `returnToOnboardQuestion()` — the exact same
    /// return path H4's `Include what I already have` already uses — lands
    /// on it directly with no re-fetch. Otherwise (a fresh launch, or the
    /// offer was never seen this session at all), there is nothing cached
    /// to return to, so this re-runs Detect fresh; D.4's own ordering note
    /// ("the question is asked BEFORE the blocked-guard") is what
    /// guarantees THAT path also lands on the identical screen rather than
    /// skipping past it.
    func reopenForConnectionOffer() {
        if !model.onboardQuestionItems.isEmpty {
            model.returnToOnboardQuestion()
        } else {
            model.runDetect()
        }
        show()
    }

    /// Region 6's `permission-needed` PROMPT (`native/control-tower-tray.swift`,
    /// `control-tower-copy-deck.md` §1.8): reopens this SAME wizard singleton
    /// positioned at Holding's H7 variant (a missing GitHub permission, copy
    /// spec §3). `Continue in the menu bar` only ever closes the window
    /// (every Holding view's `onClose`) — it never resets `model.phase` — so
    /// if this session already reached H7 once, the model is STILL sitting
    /// on that exact `HoldingInfo`, and this reopens directly onto it with no
    /// re-fetch: the same "return to what's already there" shape
    /// `reopenForConnectionOffer()` above uses for its own cached ask-row
    /// case. Otherwise (a fresh launch, or the wizard was never opened this
    /// session at all), there is nothing cached to return to, so this
    /// re-runs Detect fresh — `holdingInfo(forBlockedOnboard:)`'s own
    /// `registration == "not-permitted"` branch (Appendix D.2's gate table,
    /// checked BEFORE the held-for-you H4 case on the same `device-ssh`
    /// stage) is what re-derives H7 from the live CLI, never guessed here.
    /// H7's own screen already degrades honestly to the manual fallback
    /// sheet when `cc auth grant` is absent/`unavailable` (`beginGrantFlow`/
    /// `grantUnavailableKnown`) — this method only ever navigates to that
    /// screen, so the tray action inherits that same honesty for free
    /// rather than needing its own copy of it.
    func reopenForPermissionNeeded() {
        if case .holding(let info) = model.phase, info.variant == .needsPermission {
            // Already there — nothing to re-fetch.
        } else {
            model.runDetect()
        }
        show()
    }
}

// MARK: - Selftest hook (harness contract)

/// Drives the step-2 device flow (and, when `CT_SELFTEST_STEP=departments`,
/// the Departments read) directly through `CliClient`, independent of
/// `WizardModel`'s own UI-facing device-flow polling (`WizardModel.
/// beginDeviceFlow`/`startPolling`, which has no fixed poll cap and is paced
/// for a person watching the window, not a test harness). This exists purely
/// so a headless run can prove the auth/departments CLI seam works end to end
/// without clicking through the wizard UI. Terminates the process itself
/// (`exit(0)`/`exit(1)`) per the harness contract — never returns control to
/// the running app.
enum WizardSelftest {
    private static var hasRun = false

    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["CT_SELFTEST"] == "1", env["CT_OPEN_WIZARD"] == "1" else { return }
        guard !hasRun else { return }
        hasRun = true
        Task { await run() }
    }

    private static func run() async {
        if ProcessInfo.processInfo.environment["CT_SELFTEST_STEP"] == "auth-reuse" {
            await runAuthReuseSelftest()
            exit(0)
        }

        // CT_SELFTEST_STEP=org-question — the §2.1.1 organization question
        // and its `org-required`/`org-not-found`/`no-company-app`/
        // `network-unavailable` routing (org-question copy spec §2.1.1/§6).
        // Exits early, bypassing the direct-`CliClient` auth dance below
        // entirely: this step drives a REAL `WizardModel` instance instead,
        // because the routing under test (`handleOrgRequired`/
        // `handleConnectGitHubError`/`useADifferentOrganization`) lives on
        // that type, not on `CliClient` — the same "prove the routing isn't
        // vacuous" bar `CT_SELFTEST_STEP=holding` already holds itself to,
        // just against `WizardModel`'s instance behavior instead of its pure
        // static classifiers.
        if ProcessInfo.processInfo.environment["CT_SELFTEST_STEP"] == "org-question" {
            await runOrgQuestionSelftest()
            exit(0)
        }

        guard case .success(let code) = await CliClient.shared.authLoginInitiate() else {
            print("SELFTEST auth=error")
            exit(1)
        }

        var authState = "pending"
        var login = "none"
        let waitSeconds = UInt64(max(code.interval, 1))

        pollLoop: for attempt in 1...6 {
            switch await CliClient.shared.authLoginPoll(deviceCode: code.deviceCode) {
            case .success(let poll):
                switch poll.status {
                case .authorized:
                    authState = "authorized"
                    if case .success(let status) = await CliClient.shared.authStatus(), let identityLogin = status.identity?.login {
                        login = identityLogin
                    }
                    break pollLoop
                case .denied:
                    authState = "denied"
                    break pollLoop
                case .expired:
                    authState = "expired"
                    break pollLoop
                case .pending:
                    authState = "pending"
                    if attempt < 6 {
                        try? await Task.sleep(nanoseconds: waitSeconds * 1_000_000_000)
                    }
                }
            case .failure:
                print("SELFTEST auth=error")
                exit(1)
            }
        }

        print("SELFTEST auth=\(authState) signedInAs=\(login)")

        if ProcessInfo.processInfo.environment["CT_SELFTEST_STEP"] == "departments" {
            switch await CliClient.shared.layers() {
            case .success(let report):
                let parts = report.layers.map { entry -> String in
                    let availability: String
                    if entry.joined {
                        availability = "joined"
                    } else if entry.entitled == true {
                        availability = "available"
                    } else {
                        availability = "not-available"
                    }
                    return "\(entry.id):\(availability)"
                }
                print("SELFTEST departments=\(parts.joined(separator: ","))")
            case .failure:
                print("SELFTEST auth=error")
                exit(1)
            }
        }

        // CT_SELFTEST_STEP=connections — step 6's `connections()` read
        // (task 221 bridge stage C), independent of `WizardModel`'s own
        // `loadConnections()` for the same reason the departments step
        // above is: this drives `CliClient` directly so a headless run can
        // prove the CLI seam decodes a real payload (including against the
        // real SOURCE `cc`, not just `mock-cc`) without clicking through
        // the wizard UI.
        if ProcessInfo.processInfo.environment["CT_SELFTEST_STEP"] == "connections" {
            switch await CliClient.shared.connections() {
            case .success(let report):
                let resultToken: String
                switch report.result {
                case .ok: resultToken = "ok"
                case .copilotUnavailable: resultToken = "copilot-unavailable"
                case .orgConfigUnavailable: resultToken = "org-config-unavailable"
                case .unknown: resultToken = "unknown"
                }
                let rows = report.connections.map { row -> String in
                    let state: String
                    switch row.secretState {
                    case .ready: state = "ready"
                    case .needsConnect: state = "needs-connect"
                    case .noStore: state = "no-store"
                    case .unknown: state = "unknown"
                    }
                    return "\(row.id):\(state)"
                }
                print("SELFTEST connectionsResult=\(resultToken) connections=\(rows.joined(separator: ","))")
            case .failure(let error):
                print("SELFTEST connections=error(\(error)) missingVerb=\(error.looksLikeMissingConnectionsVerb)")
                exit(1)
            }
        }

        // CT_SELFTEST_STEP=connect — the Connect sheet's CLI seam (task 222),
        // driven directly for the same reason every step above is: a headless
        // run proves the seam decodes `connect.schema.json` (including against
        // the real SOURCE `cc`) without a person typing into a SecureField.
        //
        // `CT_SELFTEST_CONNECT_VALUES` is the ONLY way this path ever writes,
        // and it exists so the fixture harness can prove the stdin channel
        // end to end against `mock-cc`. Without it this runs `--check`, which
        // reads and never writes — that is what makes this selftest safe to
        // point at a real machine's real keychain, and the packaged-app
        // release check does exactly that.
        if ProcessInfo.processInfo.environment["CT_SELFTEST_STEP"] == "connect" {
            let environment = ProcessInfo.processInfo.environment
            let serviceId = environment["CT_SELFTEST_SERVICE"] ?? "infisical"
            let result: Result<ConnectReport, CliError>
            if let rawValues = environment["CT_SELFTEST_CONNECT_VALUES"] {
                if let data = rawValues.data(using: .utf8),
                   let values = try? JSONDecoder().decode([String: String].self, from: data) {
                    result = await CliClient.shared.connect(serviceId: serviceId, values: values)
                } else {
                    // `CT_SELFTEST_CONNECT_VALUES` was set but is not a
                    // well-formed `{"NAME":"value"}` object -- exercises
                    // `invalid-input` end to end (task 222) rather than
                    // silently downgrading to `--check`.
                    result = await CliClient.shared.rawConnectForSelftest(serviceId: serviceId, rawStdin: rawValues)
                }
            } else {
                result = await CliClient.shared.connectCheck(serviceId: serviceId)
            }

            switch result {
            case .success(let report):
                let resultToken: String
                switch report.result {
                case .ok: resultToken = "ok"
                case .unknownService: resultToken = "unknown-service"
                case .invalidInput: resultToken = "invalid-input"
                case .copilotUnavailable: resultToken = "copilot-unavailable"
                case .orgConfigUnavailable: resultToken = "org-config-unavailable"
                case .unknown: resultToken = "unknown"
                }
                let modeToken: String
                switch report.mode {
                case .connect: modeToken = "connect"
                case .check: modeToken = "check"
                case .unknown: modeToken = "unknown"
                }
                let stateToken: String
                switch report.service?.secretState {
                case .some(.ready): stateToken = "ready"
                case .some(.needsConnect): stateToken = "needs-connect"
                case .some(.noStore): stateToken = "no-store"
                case .some(.unknown): stateToken = "unknown"
                case nil: stateToken = "none"
                }
                let credentials = (report.credentials ?? []).map { credential -> String in
                    let outcome: String
                    switch credential.outcome {
                    case .stored: outcome = "stored"
                    case .alreadyPresent: outcome = "already-present"
                    case .failed: outcome = "failed"
                    }
                    return "\(credential.name):\(outcome)"
                }
                // Prints NAMES and OUTCOMES only. There is no code path here
                // that could print a value: the reply carries none.
                print("SELFTEST connectResult=\(resultToken) mode=\(modeToken) service=\(stateToken) credentials=\(credentials.joined(separator: ","))")
            case .failure(let error):
                // `missingVerb` is printed for the SAME reason the
                // connections step above prints it: every released build
                // before this one bundles a helper with no `connect` verb, so
                // "this helper is too old" has to be distinguishable from any
                // other failure, and the sheet appends the update hint on
                // exactly this classification.
                print("SELFTEST connect=error(\(error)) missingVerb=\(error.looksLikeMissingConnectionsVerb)")
                exit(1)
            }
        }

        // CT_SELFTEST_STEP=holding — the Detect->Holding transition
        // (`holding-copy-spec.md`), independent of `WizardModel`'s own
        // Detect flow for the SAME reason the auth/departments steps above
        // are: this drives `CliClient` directly so a headless run can prove
        // the classifier end to end without clicking through the wizard UI.
        // Calls the SAME `ecosystemOnboardPlan` verb `performDetect` calls,
        // then feeds its result through the SAME pure classifiers
        // (`WizardModel.holdingInfo(forBlockedOnboard:origin:)` /
        // `WizardModel.holdingInfo(for:origin:)`) the real wizard uses —
        // never a bespoke, potentially-drifted second reading of the same
        // report.
        if ProcessInfo.processInfo.environment["CT_SELFTEST_STEP"] == "holding" {
            switch await CliClient.shared.ecosystemOnboardPlan(products: ["claude"]) {
            case .success(let report):
                // "One question first" (D.4's own ordering note: asked
                // BEFORE the blocked-guard) — printed for EVERY plan, blocked
                // or not, through the SAME pure classifier
                // `personalOnboardQuestion(from:)` the real wizard uses, so a
                // regression there (Bug 1: the dropped `scope == "machine"`
                // filter) fails this line, not just the eventual UI.
                let (ask, review) = WizardModel.personalOnboardQuestion(from: report)
                printOnboardQuestionSelftestLine(ask: ask, review: review)
                if report.result == .blocked {
                    printHoldingSelftestLine(WizardModel.holdingInfo(forBlockedOnboard: report, origin: .detect))
                } else {
                    print("SELFTEST holding=none result=\(report.result.rawValue)")
                }
            case .failure(let error):
                if let info = WizardModel.holdingInfo(for: error, origin: .detect) {
                    printHoldingSelftestLine(info)
                } else {
                    print("SELFTEST holding=not-a-hold")
                }
            }
        }

        // CT_SELFTEST_STEP=completion-rule — copy spec §2.10's completion
        // rule, exercised directly as a pure function against a handful of
        // constructed reports (`EcosystemOnboardStage` decoded from small
        // literal JSON, same discipline every other DTO in this app uses,
        // rather than a bespoke test-only initializer). No CLI call: this
        // proves the BOOLEAN the real screens key off, which is the
        // load-bearing thing to test — neither this suite nor any other
        // mechanism in this codebase asserts on a rendered SwiftUI tree.
        if ProcessInfo.processInfo.environment["CT_SELFTEST_STEP"] == "completion-rule" {
            printCompletionRuleSelftestLine()
        }

        exit(0)
    }

    /// `SELFTEST holding=` must print one of the eight stable variant
    /// tokens below (`HoldingVariant`'s own case names), plus every field
    /// `control-tower-copy-deck.md` §2.9 says must reach the support block —
    /// this is exactly what `scripts/tests/smoke-scenarios.sh`'s holding
    /// scenarios assert against (H3-vs-H4-vs-H7 distinction, and that
    /// `.exit2`'s bound `code`/`message` actually arrive here, never
    /// "unknown"/dropped).
    ///
    /// This first line prints `HoldingInfo.support`'s raw fields directly
    /// (`?? "none"` only distinguishes "field absent" for THIS diagnostic
    /// line, not the app's own rendering) — it does NOT exercise
    /// `HoldingInfo.supportLines(_:)`, the function the actual support
    /// disclosure view renders from. The second `SELFTEST supportLines=`
    /// line below prints THAT function's real output (§2.9.1's own guard
    /// against a dangling bare label, e.g. `Message: ` with nothing after
    /// it, for a field the CLI sent as `""` rather than omitting) — S21 in
    /// `smoke-scenarios.sh` asserts against this second line.
    private static func printHoldingSelftestLine(_ info: HoldingInfo) {
        let token: String
        switch info.variant {
        case .notInstalled: token = "notInstalled"
        case .unreadable: token = "unreadable"
        case .fault: token = "fault"
        case .yours: token = "yours"
        case .waitingOffline: token = "waitingOffline"
        case .waitingBusy: token = "waitingBusy"
        case .waitingOnOrg: token = "waitingOnOrg"
        case .needsPermission: token = "needsPermission"
        }
        print(
            "SELFTEST holding=\(token) stage=\(info.support?.stage ?? "none")"
                + " result=\(info.support?.result ?? "none") code=\(info.support?.code ?? "none")"
                + " message=\(info.support?.message ?? "none")"
                + " selfServeCommand=\(info.selfServeCommand ?? "none")"
                // Task 210/G-7: whether `Try again` renders at all
                // (`h2View`/`h3View`'s own gate). Task 211/G-4b:
                // `completedActions` proves the ledger actually reached this
                // classifier (never re-derived from `intro` prose, which is
                // free-text and not meant for assertions).
                + " retryable=\(info.retryable) completedActions=\(info.completedActions.count)"
        )
        print("SELFTEST introLine=\(info.intro)")
        if let support = info.support {
            print("SELFTEST supportLines=\(HoldingInfo.supportLines(support).joined(separator: "|"))")
        } else {
            print("SELFTEST supportLines=none")
        }
    }

    /// Bug 1 (Appendix D.3) and the `device-ssh` -> `ssh` consent token
    /// (Bug 2) in one line: `id:scope` for every ask/review row, in order,
    /// PLUS the exact `componentId(fromPersonalInventoryId:)` mapping for a
    /// fixed probe set including `device-ssh` — a regression in either
    /// silently-failing bug changes this printed line, so
    /// `scripts/tests/smoke-scenarios.sh` can assert on it directly.
    private static func printOnboardQuestionSelftestLine(ask: [EcosystemInventoryItem], review: [EcosystemInventoryItem]) {
        func describe(_ items: [EcosystemInventoryItem]) -> String {
            items.isEmpty ? "none" : items.map { "\($0.id):\($0.scope)" }.joined(separator: ",")
        }
        print("SELFTEST askItems=\(describe(ask)) reviewItems=\(describe(review))")
        let mapped = ["device-ssh", "personal-claude", "personal-codex", "not-a-known-id"]
            .map { WizardModel.componentId(fromPersonalInventoryId: $0) ?? "nil" }
        print("SELFTEST componentIds=\(mapped.joined(separator: ","))")
    }

    /// See `CT_SELFTEST_STEP == "completion-rule"` above. Five constructed
    /// cases, each isolating exactly one of the completion rule's three
    /// checkable conditions.
    private static func printCompletionRuleSelftestLine() {
        func stage(_ id: String, _ result: String) -> EcosystemOnboardStage {
            let json = Data(#"{"stage":"\#(id)","result":"\#(result)"}"#.utf8)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            // Force-unwrap is deliberate here: `json` is a hardcoded,
            // always-valid literal, so a decode failure could only mean a
            // bug in THIS test helper, not in anything under test.
            return try! decoder.decode(EcosystemOnboardStage.self, from: json)
        }
        let eightIds = WizardModel.allReportStages.map(\.id)
        let allApplied = eightIds.map { stage($0, "applied") }
        let sevenNoDoctor = allApplied.filter { $0.stage != "doctor" }
        let oneBlocked = allApplied.map { $0.stage == "device-ssh" ? stage("device-ssh", "blocked") : $0 }
        let deferredStore = allApplied.map { $0.stage == "secret-store" ? stage("secret-store", "deferred") : $0 }
        let deferredRequired = allApplied.map { $0.stage == "device-ssh" ? stage("device-ssh", "deferred") : $0 }
        let claudeOnlySeven = allApplied.filter { $0.stage != "codex-plugin" }

        let full = WizardModel.completionRulePasses(result: .ready, stages: allApplied, includeCodex: true)
        let missingStage = WizardModel.completionRulePasses(result: .ready, stages: sevenNoDoctor, includeCodex: true)
        let blockedStage = WizardModel.completionRulePasses(result: .ready, stages: oneBlocked, includeCodex: true)
        let optionalDeferred = WizardModel.completionRulePasses(result: .ready, stages: deferredStore, includeCodex: true)
        let requiredDeferred = WizardModel.completionRulePasses(result: .ready, stages: deferredRequired, includeCodex: true)
        let deferredRows = WizardModel.honestCapabilityRows(stages: deferredStore, includeCodex: true)
        let blockedResult = WizardModel.completionRulePasses(result: .blocked, stages: allApplied, includeCodex: true)
        let claudeOnlyNoCodex = WizardModel.completionRulePasses(result: .ready, stages: claudeOnlySeven, includeCodex: false)

        print(
            "SELFTEST completionRule full=\(full) missingStage=\(missingStage)"
                + " blockedStage=\(blockedStage) optionalDeferred=\(optionalDeferred)"
                + " requiredDeferred=\(requiredDeferred) deferredNotYet=\(deferredRows.notYet.count)"
                + " blockedResult=\(blockedResult) claudeOnlyNoCodex=\(claudeOnlyNoCodex)"
        )
    }

    // MARK: CT_SELFTEST_STEP=org-question — §2.1.1's organization question

    /// Pure-function proof first (no CLI, no `WizardModel`): the exact paste-
    /// normalization and validation examples the copy spec itself names
    /// (§2.1.1/§3), so a regression in either fails this line even if every
    /// downstream screen still happened to render something plausible.
    private static func printOrgPureFunctionSelftestLines() {
        let normalizeCases: [(input: String, expected: String)] = [
            ("https://github.com/Acme-Co", "Acme-Co"),
            ("github.com/Acme-Co/copilot-bootstrap", "Acme-Co"),
            ("github.com/orgs/Acme-Co/repositories", "Acme-Co"),
            ("Acme-Co", "Acme-Co"),
        ]
        let normalizeResults = normalizeCases.map { WizardModel.normalizedOrgInput($0.input) == $0.expected ? "pass" : "fail" }
        print("SELFTEST orgNormalize=\(normalizeResults.joined(separator: ","))")

        func validationToken(_ value: OrgFieldValidation) -> String {
            switch value {
            case .none: return "none"
            case .containsSpaces(let suggestion): return "spaces:\(suggestion)"
            case .containsAt: return "at"
            case .invalidCharacters: return "invalid"
            }
        }
        let validateCases: [(input: String, expected: String)] = [
            ("Acme Corporation", "spaces:Acme-Corporation"),
            ("acme@x", "at"),
            ("-acme-", "invalid"),
            ("Acme-Co", "none"),
        ]
        let validateResults = validateCases.map { validationToken(WizardModel.validateOrgInput($0.input)) == $0.expected ? "pass" : "fail" }
        print("SELFTEST orgValidate=\(validateResults.joined(separator: ","))")
    }

    private static func holdingVariantToken(_ variant: HoldingVariant) -> String {
        switch variant {
        case .notInstalled: return "notInstalled"
        case .unreadable: return "unreadable"
        case .fault: return "fault"
        case .yours: return "yours"
        case .waitingOffline: return "waitingOffline"
        case .waitingBusy: return "waitingBusy"
        case .waitingOnOrg: return "waitingOnOrg"
        case .needsPermission: return "needsPermission"
        }
    }

    @MainActor
    private static func orgPhaseToken(_ phase: WizardPhase) -> String {
        switch phase {
        case .welcome: return "welcome"
        case .connectGitHub: return "connectGitHub"
        case .orgQuestion: return "orgQuestion"
        case .holding: return "holding"
        case .detecting, .replanningAfterDecision, .detected, .onboardQuestion: return "detect"
        default: return "other"
        }
    }

    // MARK: CT_SELFTEST_STEP=auth-reuse — existing GitHub connection

    /// Waits for `getStarted()` to make its first trustworthy authorization
    /// decision. The test stops at the decision boundary: Detect may keep
    /// progressing after a reused session, while a signed-out session stops
    /// once the real device code has arrived.
    @MainActor
    private static func waitForAuthReuseDecision(_ model: WizardModel) async {
        for _ in 0..<50 {
            if model.authorizedLogin != nil || model.deviceFlow.userCode != nil {
                return
            }
            if case .holding = model.phase { return }
            if case .orgQuestion = model.phase { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Drives the real Welcome -> GitHub transition so the shell harness can
    /// pair the resulting state with `CT_MOCK_INVOCATION_LOG` and prove both
    /// halves of the contract: reuse an authorized session without invoking
    /// `auth login`, but initiate device flow when status is signed out.
    @MainActor
    private static func runAuthReuseSelftest() async {
        let model = WizardModel()
        model.getStarted()
        await waitForAuthReuseDecision(model)

        if model.authorizedLogin != nil {
            print("SELFTEST authReuse=reused login=\(model.authorizedLogin ?? "none") phase=\(orgPhaseToken(model.phase))")
            return
        }
        if model.deviceFlow.userCode != nil {
            print("SELFTEST authReuse=deviceFlow phase=\(orgPhaseToken(model.phase))")
            return
        }
        if case .holding(let info) = model.phase {
            print("SELFTEST authReuse=holding variant=\(holdingVariantToken(info.variant)) phase=\(orgPhaseToken(model.phase))")
            return
        }
        if case .orgQuestion = model.phase {
            print("SELFTEST authReuse=orgQuestion phase=orgQuestion")
            return
        }
        print("SELFTEST authReuse=timeout phase=\(orgPhaseToken(model.phase))")
    }

    /// Polls a real `WizardModel` instance until whatever it's currently
    /// doing (the very first `authLoginInitiate()`, or a submission from the
    /// organization screen) actually resolves — bounded, never infinite, the
    /// same discipline `run()`'s own auth poll loop above already uses.
    @MainActor
    private static func waitForOrgSelftestSettled(_ model: WizardModel) async {
        for _ in 0..<50 {
            let stillConnecting = { () -> Bool in
                if case .connectGitHub = model.phase, model.deviceFlow.status == .pending { return true }
                return false
            }()
            if stillConnecting || model.orgQuestionSubmitting {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }
            return
        }
    }

    /// Drives a REAL `WizardModel` instance through its own real entry
    /// points (`getStarted()`, `continueToSignInFromOrgQuestion()`,
    /// `useADifferentOrganization()`) against the mock CLI's four
    /// `org-required-then-*` scenarios (`CT_AUTH_SCENARIO`) — this is what
    /// makes the routing proof non-vacuous: a deleted or short-circuited
    /// `org-required` case in `handleConnectGitHubError` changes what THIS
    /// prints, not just what a person clicking through the UI would see.
    @MainActor
    private static func runOrgQuestionSelftest() async {
        printOrgPureFunctionSelftestLines()

        let model = WizardModel()
        model.getStarted()
        await waitForOrgSelftestSettled(model)

        switch model.phase {
        case .orgQuestion:
            let sawStandupIntro = model.orgQuestionIntro.contains("already set up")
            print("SELFTEST orgPhase=orgQuestion prefill=\(model.orgNameInput.isEmpty ? "none" : model.orgNameInput) introNamesStandup=\(sawStandupIntro)")
        case .holding(let info):
            print("SELFTEST orgPhase=holding variant=\(holdingVariantToken(info.variant)) orgNameForReturn=\(info.orgNameForReturn ?? "none")")
        default:
            print("SELFTEST orgPhase=\(orgPhaseToken(model.phase))")
        }

        // Only the organization screen has anything left to submit — every
        // other landing state (a silent-brief success, or a hold) is
        // already this scenario's whole story.
        guard case .orgQuestion = model.phase else { return }

        model.orgNameInput = "Acme-Co"
        model.orgNameInputChanged()
        model.continueToSignInFromOrgQuestion()
        await waitForOrgSelftestSettled(model)

        switch model.phase {
        case .connectGitHub:
            print("SELFTEST orgSubmitResult=connectGitHub deviceFlowStatus=\(model.deviceFlow.status)")
        case .orgQuestion:
            print("SELFTEST orgSubmitResult=orgQuestion orgNotFoundMessage=\(model.orgNotFoundMessage ?? "none")")
        case .holding(let info):
            print("SELFTEST orgSubmitResult=holding variant=\(holdingVariantToken(info.variant)) orgNameForReturn=\(info.orgNameForReturn ?? "none")")
        default:
            print("SELFTEST orgSubmitResult=\(orgPhaseToken(model.phase))")
        }

        // `Use a different organization` (§5's "escape from H6") — only
        // reachable when the hold actually carries a return value; proves
        // the return trip lands back on the organization screen with the
        // field populated, never a fresh blank one.
        if case .holding(let info) = model.phase, info.orgNameForReturn != nil {
            model.useADifferentOrganization()
            print("SELFTEST orgUseADifferentOrg phase=\(orgPhaseToken(model.phase)) field=\(model.orgNameInput)")
        }
    }
}
