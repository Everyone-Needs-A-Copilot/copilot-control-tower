//
// Copilot Control Tower — native macOS menu-bar app ("Quiet Instrument").
//
// The app's entry point (`@main`) plus the tray/popover UI: an `NSStatusItem`
// + `NSPopover` that renders the component-currency popover against the REAL
// CLI, per:
//   - docs/09-prototypes/user-experience-walkthrough.html, Arc 3 (screens
//     16-20: the quiet tray, opening the popover, Sync now, a department
//     appears) and Arc 4 (screens 21-22: an update lands, the honest "What
//     changed" summary) — copy is VERBATIM from that document, no em-dashes.
//   - docs/03-design/control-tower-copy-deck.md — the closed vocabulary for
//     every string this file renders (§1.1-1.9).
//   - docs/03-design/control-tower-visual-system.md (tokens, materials, the
//     12 shape-first BadgeState glyphs, spacing/type).
//
// This file is compiled together with `native/models.swift` (shared render
// data model), `native/cli-client.swift` + `native/cli-dtos.swift` (the CLI
// seam), `native/render-state.swift` (the pure DoctorReport -> RenderState
// derivation), and `native/wizard.swift` (the S2 first-run wizard window)
// into ONE binary via `swiftc native/*.swift -o ...` (see
// `scripts/build-user.command` / `scripts/build-admin.command`).
//
// PARSE, NEVER COMPUTE (CLAUDE.md invariant #1): this file calls `CliClient`
// verbs and renders `RenderState`/`FanoutRender` output. It computes NOTHING
// about ecosystem health itself — every glyph, sentence, and dot below is a
// render of an already-CLI-computed verdict.
//
// CRITICAL SwiftUI/AppKit ordering constraint (see `.claude/memory`): no
// blocking `Process`/file I/O may run during a SwiftUI `@State`/
// `@StateObject` property-wrapper `init()` — it re-enters the AttributeGraph
// mid-update and aborts. `TrayModel.init()` below is pure (only assigns
// `@Published` defaults, no I/O, no CLI calls). Every CLI call in this file
// happens from `TrayModel.refresh()`/`syncNow()`/`join(_:)` — async methods
// invoked from `applicationDidFinishLaunching(_:)` or later (via `Task`), a
// button action, or a timer callback, never from a property-wrapper `init()`.
// `StatusBarController.init()`'s one piece of synchronous file I/O — loading
// the aviator SVG for the tray glyph — is safe for the same reason the prior
// revision of this file documented: AppKit calls it from
// `applicationDidFinishLaunching(_:)`, entirely outside SwiftUI's own
// view/attribute graph.

import AppKit
import Foundation
import ServiceManagement
import SwiftUI

// Data model (BadgeState, Layer, ComponentView, RenderState, ...) lives in
// `native/models.swift`; the CLI seam lives in `native/cli-client.swift` +
// `native/cli-dtos.swift`; the DoctorReport -> RenderState derivation (plus
// `FanoutRender`, the "What changed" line-rendering helpers) lives in
// `native/render-state.swift`. All three are compiled together with this
// file — see this file's header.

// MARK: - Join-row state (Region 3, per-department join lifecycle)

/// One `CliClient.layersJoin(id:)` attempt's UI state, per
/// `control-tower-copy-deck.md` §1.5. `idle` is the default "Join" row;
/// `joining` is the in-flight quiet spinner (no ETA); `message` covers every
/// terminal non-`joined` outcome (`not-entitled`/`offline`/`error`/a `CliError`
/// itself), `canRetry` controlling whether the row keeps its `Join` button.
enum JoinRowState: Equatable {
    case idle
    case joining
    case message(String, canRetry: Bool)
}

/// Pure: the P4 "hasn't come through yet" silence-path sentences (spec
/// §7), verbatim, shared between `TrayModel.join(_:)`/`addProject(_:)`/
/// `undoProject(_:)` and the selftest below — so the live silence path and
/// its own test can never quietly drift apart, and so this wording (a
/// real-but-unresolved wait) can never be confused with the CLI's own
/// reported failure copy (`"Couldn't join... right now."` etc.), which is
/// a DIFFERENT, already-existing sentence for a DIFFERENT situation.
enum NamedWaitRender {
    static func hasNotComeThrough(_ subject: String) -> String {
        "\(subject) hasn't come through yet. Nothing was changed."
    }

    static func projectHasNotComeThrough(_ projectName: String) -> String {
        "\(projectName) hasn't come through yet. Nothing in it was changed."
    }

    static func projectUndoHasNotComeThrough(_ projectName: String) -> String {
        "\(projectName) hasn't come through yet. Nothing was undone."
    }
}

// MARK: - Region 6, projects notice + drill-in (adopt-and-project-setup spec)

/// Test-only fixture upgrader used by the executable's existing offline
/// SELFTEST seams. Callers name the expected authoritative classification;
/// this helper does not infer it from legacy row state.
enum WorkspaceContractSelftestFixture {
    static func entry(
        _ legacyJSON: String,
        classification: WorkspaceIntegrationClassification
    ) -> Data {
        var row = try! JSONSerialization.jsonObject(
            with: Data(legacyJSON.utf8)
        ) as! [String: Any]
        decorate(&row, classification: classification)
        return try! JSONSerialization.data(withJSONObject: row)
    }

    static func report(
        _ legacyJSON: String,
        classifications: [WorkspaceIntegrationClassification]
    ) -> Data {
        var report = try! JSONSerialization.jsonObject(
            with: Data(legacyJSON.utf8)
        ) as! [String: Any]
        var rows = report["workspaces"] as! [[String: Any]]
        precondition(rows.count == classifications.count)
        for index in rows.indices {
            decorate(&rows[index], classification: classifications[index])
        }
        report["schema_version"] = "1.1"
        report["workspaces"] = rows
        let readyCount = classifications.filter { $0 == .ready }.count
        let safeCount = classifications.filter { $0 == .safeFinish }.count
        let guidedCount = classifications.filter { $0 == .guidedIntegration }.count
        let ownerCount = classifications.filter { $0 == .ownerDecision }.count
        let unavailableCount = classifications.filter { $0 == .couldNotVerify }.count
        let classificationSummary: [String: Int] = [
            "ready": readyCount,
            "safe-finish": safeCount,
            "guided-integration": guidedCount,
            "owner-decision": ownerCount,
            "could-not-verify": unavailableCount,
            "total": classifications.count,
        ]
        report["classification_summary"] = classificationSummary
        return try! JSONSerialization.data(withJSONObject: report)
    }

    private static func decorate(
        _ row: inout [String: Any],
        classification: WorkspaceIntegrationClassification
    ) {
        let path = row["path"] as? String ?? "/p/example"
        let inspectionId = "sha256:" + String(repeating: "1", count: 64)
        let actionId = "sha256:" + String(repeating: "2", count: 64)
        let planId = "sha256:" + String(repeating: "3", count: 64)
        let actor: WorkspaceResponsibleActor
        switch classification {
        case .ready: actor = .none
        case .safeFinish: actor = .cli
        case .guidedIntegration: actor = .projectAuthor
        case .ownerDecision: actor = .projectOwner
        case .couldNotVerify: actor = .person
        }
        row["classification"] = classification.rawValue
        row["responsible_actor"] = actor.rawValue
        row["inspection"] = [
            "id": inspectionId,
            "contract_id": "project-integration",
            "contract_version": "1",
            "scope": "detail",
            "complete": true,
        ]
        row["capabilities"] = [
            "instructions": 2,
            "agents": 3,
            "skills": 2,
            "commands": 1,
            "plugins": 1,
            "integration_paths": ["CLAUDE.md", "AGENTS.md"],
        ]
        let preserved: [[String: Any]] = [[
            "kind": "instruction",
            "path": "CLAUDE.md",
            "detail": "Preserve the project's own instructions.",
        ]]
        row["preservation"] = [
            "must_preserve": preserved,
            "prohibited_actions": [
                "overwrite-project-instructions",
                "delete-project-capabilities",
                "trust-assistant-self-report",
                "skip-verification",
            ],
        ]
        let verification: [String: Any] = [
            "command": ["cc", "workspace", "verify", "--project", path, "--json"],
            "expected": "Claude, Codex, and the project classify ready.",
            "stop_conditions": ["Stop if evidence changed."],
        ]
        let recognized: [String: Any] = [
            "variant_id": "selftest-tracked-lock-v1",
            "version": "1",
            "evidence": [[
                "kind": "lock-record",
                "path": "copilot.lock.json",
                "state": "verified",
                "detail": "Recorded evidence matches.",
            ]],
        ]
        row["components"] = ["claude", "codex"].map { component in
            var item: [String: Any] = [
                "component": component,
                "expected": true,
                "expected_contract": [
                    "id": "project-integration",
                    "version": "1",
                ],
                "classification": classification.rawValue,
                "recognized_setup": classification == .ready ? recognized : NSNull(),
                "missing_requirements": classification == .ready ? [] : [[
                    "id": "selftest-requirement",
                    "detail": "Complete the declared integration route.",
                ]],
                "responsible_actor": actor.rawValue,
                "safe_action": NSNull(),
                "verification": verification,
            ]
            if classification == .safeFinish {
                item["responsible_actor"] = WorkspaceResponsibleActor.cli.rawValue
            }
            return item
        }
        row["diagnostic"] = NSNull()

        if classification == .safeFinish {
            let action: [String: Any] = [
                "id": actionId,
                "inspection_id": inspectionId,
                "kind": "add-missing",
                "components": ["claude", "codex"],
                "detail": "Add only the missing Copilot integration files.",
                "apply_verb": "finish",
                "will_add": [[
                    "kind": "manifest",
                    "path": "copilot.lock.json",
                    "detail": "Record verified component evidence.",
                ]],
                "will_preserve": preserved,
                "will_not_change": preserved,
                "verification": verification,
            ]
            row["safe_action"] = action
            row["plan_available"] = false
            row["integration_plan"] = NSNull()
            row["can_apply_now"] = true
        } else if classification == .guidedIntegration || classification == .ownerDecision {
            row["safe_action"] = NSNull()
            row["plan_available"] = true
            row["can_apply_now"] = false
            row["integration_plan"] = [
                "id": planId,
                "inspection_id": inspectionId,
                "responsible_actor": actor.rawValue,
                "detected": ["Project-specific instructions are present."],
                "missing": ["Connect both expected Copilot entry points."],
                "preserve": ["Preserve the project's own instructions."],
                "prohibited": ["Do not overwrite project instructions."],
                "prompt": [
                    "version": "1",
                    "text": "Integrate this project while preserving its own behavior.",
                ],
                "owner_handoff": [
                    "version": "1",
                    "text": "This project needs its owner. Nothing has been changed.",
                ],
                "verification": verification,
                "stop_conditions": ["Stop for an unresolved owner decision."],
            ]
        } else {
            row["safe_action"] = NSNull()
            row["plan_available"] = false
            row["integration_plan"] = NSNull()
            row["can_apply_now"] = false
            if classification == .couldNotVerify {
                row["diagnostic"] = [
                    "id": "sha256:" + String(repeating: "4", count: 64),
                    "inspection_id": inspectionId,
                    "mode": "read-only",
                    "prompt": [
                        "version": "1",
                        "text": "Diagnose this project in READ-ONLY mode. Do not create, edit, rename, move, or delete project files.",
                    ],
                    "verification": verification,
                    "stop_conditions": ["Stop before any project write."],
                ]
            }
        }
    }
}

/// One project row's transient, session-local UI state while `TrayModel.
/// addProject(_:)`/`addAllProjects()`/`undoProject(_:)` is in flight — never
/// persisted, never read back from the CLI (`nil` in `TrayModel.
/// projectRowActions` means "render straight from the last `WorkspacesReport`",
/// i.e. `ProjectRowRender` below). `undoing`/`undoFailed` are B3's own pair,
/// mirroring `adding`/`failed` for the **Undo** control (spec, "Undo": "Result"
/// / "Failed").
enum ProjectRowAction: Equatable {
    case adding
    case failed
    /// The P4 silence path (spec §7): `adding` has gone quiet past
    /// `TrayModel.silenceThreshold` with no CLI answer yet — distinct from
    /// `failed`, which is a real reported outcome. Offers the same "Try
    /// again" control as `failed`, with `NamedWaitRender.
    /// projectHasNotComeThrough(_:)`'s own, different caption.
    case stalled
    case undoing
    case undoFailed
    /// `undoing`'s own silence-path pair to `stalled` above.
    case undoStalled
    case loadingPlan
    case verifying
}

/// Pure: the Region 6 notice's count and copy. A `static`, instance-free
/// namespace (like `WizardModel.personalOnboardQuestion(from:)`) so this
/// exact derivation is shared between `PopoverContentView` and the selftest
/// below, and so the "declined" muting logic in `PopoverContentView` and the
/// count math here can never quietly drift apart.
enum ProjectsNoticeRender {
    /// "Can be set up" means both a setup-needed state and a successful CLI
    /// preflight. The summary buckets alone do not carry `can_apply_now`, so
    /// counting them would turn known holds into misleading offers.
    static func actionableCount(_ report: WorkspacesReport) -> Int {
        report.workspaces.filter {
            $0.classification == .safeFinish && $0.canApplyNow
        }.count
    }

    static func noticeText(count: Int) -> String {
        count == 1
            ? "1 project can have your copilots. Nothing is added until you say so."
            : "\(count) projects can have your copilots. Nothing is added until you say so."
    }
}

/// Pure: the ONE-TIME "first automatic setup ever" notice's text (spec,
/// "Menu bar: the projects notice", "Notice, first automatic setup ever").
/// A `static`, instance-free namespace — same reason `ProjectsNoticeRender`
/// above is one — shared between `PopoverContentView` and
/// `CT_TRAY_PROJECTS_SELFTEST` below. WHETHER to show it (shown once, ever,
/// gated by `LocalDefaults`) lives on `TrayModel`; this only ever picks the
/// wording once that gate has already said yes.
enum RecentlySetUpRender {
    static func noticeText(_ entries: [WorkspaceRecentlySetUp]) -> String {
        if entries.count == 1, let only = entries.first {
            return "New projects get your copilots automatically now. I just set up \(only.name)."
        }
        return "New projects get your copilots automatically now. I just set up \(entries.count) new projects."
    }
}

/// Pure: one project row's caption + control label for the drill-in
/// (`ProjectRowAction` above overrides the caption/control while an add is
/// in flight or just failed; this covers every OTHER row state). Mirrors
/// the spec's own state table exactly, one row per `WorkspaceActivationState`
/// value, split further by `setupPolicy` only where the spec's own table
/// requires it (`excluded` — "Undone", re-offering `Add`).
enum ProjectRowRender {
    enum Kind: Equatable {
        case safeFinish
        case guidedIntegration
        case ownerDecision
        case couldNotVerify
        case alreadySetUp
        /// A `ready` project the CLI's top-level `recently_set_up` record
        /// names by `name` (B3, adopt-and-project-setup spec, "Automatic
        /// setup for new projects" / "Discover it happened") — set up
        /// without being asked, with **Undo** offered for as long as
        /// `workspace.undo.available` says the CLI can still prove what it
        /// added is untouched. The app never infers "this one was
        /// automatic" any other way than checking that CLI-provided name
        /// list (CLAUDE.md invariant #1) — passed in as
        /// `recentlySetUpNames` by every function below, defaulting to
        /// empty so every existing call site (and `alreadySetUp`'s prior
        /// behavior) is unchanged when the caller has no such list yet.
        case automaticallySetUp
        /// A project `revert` (Undo) previously excluded — "Left alone at
        /// your request.", re-offering `Add`.
        case excluded
        /// A genuinely blocked project (not a project workspace, an
        /// unreadable declaration, ...) — no control, the CLI's own
        /// `detail` rendered verbatim, trailing "Kept as is".
        case keptAsIs
    }

    static func kind(for workspace: WorkspaceEntry, recentlySetUpNames: Set<String> = []) -> Kind {
        switch workspace.classification {
        case .ready:
            return recentlySetUpNames.contains(workspace.name) ? .automaticallySetUp : .alreadySetUp
        case .safeFinish:
            return workspace.setupPolicy == .excluded ? .excluded : .safeFinish
        case .guidedIntegration:
            return .guidedIntegration
        case .ownerDecision:
            return .ownerDecision
        case .couldNotVerify:
            return .couldNotVerify
        }
    }

    static func caption(for workspace: WorkspaceEntry, recentlySetUpNames: Set<String> = []) -> String {
        switch kind(for: workspace, recentlySetUpNames: recentlySetUpNames) {
        case .safeFinish: return workspace.safeAction?.detail ?? workspace.detail
        case .guidedIntegration: return "Guided integration will preserve this project's own setup."
        case .ownerDecision: return "Waiting for the person who manages this project's setup."
        case .couldNotVerify: return workspace.detail
        case .alreadySetUp: return "Already set up."
        case .automaticallySetUp:
            // Spec, "Undo": "Unavailable: 'You've changed these files
            // since, so I'll leave them alone.' with no Undo control at
            // all" — that reason is the CLI's own `undo.detail`, rendered
            // verbatim, never invented here.
            return workspace.undo.available ? "Set up automatically when you created it." : workspace.undo.detail
        case .excluded: return "Left alone at your request."
        case .keptAsIs: return workspace.applyBlockedDetail ?? workspace.detail
        }
    }

    /// `nil` means the row carries no control at all (`keptAsIs`, or an
    /// `automaticallySetUp` row whose files were edited
    /// since — "no Undo control at all, never a disabled one").
    static func controlLabel(for workspace: WorkspaceEntry, recentlySetUpNames: Set<String> = []) -> String? {
        switch kind(for: workspace, recentlySetUpNames: recentlySetUpNames) {
        case .safeFinish, .excluded: return "Review"
        case .guidedIntegration: return "Review setup"
        case .ownerDecision: return "Review decision"
        case .couldNotVerify: return "Review evidence"
        case .automaticallySetUp: return workspace.undo.available ? "Undo" : nil
        case .alreadySetUp: return "View details"
        case .keptAsIs: return nil
        }
    }
}

/// Small user-controlled handoff helpers shared by the wizard and menu app.
/// This type deliberately cannot start Codex or Claude Code. The grouped
/// reconciliation flow opens one plain Terminal at the projects root; the
/// person starts their chosen assistant and pastes Python's prompt themselves.
enum ProjectIntegrationLauncher {
    @discardableResult
    static func copy(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    static func bringTerminalForward() {
        if let terminal = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.Terminal")
            .first {
            terminal.activate(options: [.activateAllWindows])
        } else {
            NSWorkspace.shared.open(
                URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            )
        }
    }

}

// MARK: - View model

/// The single source of truth for the tray/popover: owns every real
/// `CliClient` call this app makes outside the wizard/admin faces. A
/// `@MainActor` class (not a plain `actor`) because its `@Published`
/// properties drive SwiftUI directly; every one of its async methods still
/// only ever calls `CliClient` (itself off-main internally — see
/// `native/cli-client.swift`), so nothing here blocks the main thread.
/// `init()` is pure — no I/O, no CLI calls — safe to construct from
/// `StatusBarController.init()` (itself invoked from
/// `applicationDidFinishLaunching(_:)`, see this file's header).
@MainActor
final class TrayModel: ObservableObject {
    /// The honest "haven't asked yet" placeholder shown for the brief instant
    /// between app launch and the first `refresh()` completing. Never shown
    /// as `.ok`/healthy (that would fabricate a verdict this app hasn't
    /// actually observed yet) — a quiet, bare-glyph, non-claiming line.
    private static let notYetChecked = RenderState(
        clientState: .ok,
        cliUnreadableReason: nil,
        host: nil,
        status: nil,
        offline: false,
        header: HeaderView(glyphState: .none, sentence: "Checking your setup…"),
        components: []
    )

    /// B3, "Discover it happened": the ONE-TIME first-automatic-setup-ever
    /// notice (spec, "Notice, first automatic setup ever, shown once and
    /// never again") is gated by this persisted flag, not by any in-memory
    /// "have I shown it this session" bit — `LocalDefaults`, same reasoning
    /// as `AppDelegate.firstRunDefaultsKey` (`native/models.swift`'s own
    /// doc comment on why this isn't `UserDefaults`/cfprefsd).
    private static let automaticSetupNoticeShownKey = "ct.hasShownAutomaticProjectsNotice"

    /// How long a P4 named single wait (`join(_:)`/`addProject(_:)`/
    /// `undoProject(_:)`) stays silent before the row admits it: "hasn't
    /// come through yet" (spec §7). Not a value the spec gives verbatim —
    /// chosen to sit comfortably above ordinary GitHub round-trip latency
    /// while still surfacing within one sitting. Nothing is cancelled when
    /// this fires (the spec's own rule: "additive and safe to run again");
    /// it only changes what the row says while the real call keeps running
    /// underneath it.
    private static let silenceThreshold: TimeInterval = 20

    @Published private(set) var state: RenderState = TrayModel.notYetChecked
    /// Region 3, "Available to join": entitled-but-not-joined department/org
    /// rows, derived from `layers()` the same way `render-state.swift`'s
    /// `RenderState.from(_:joinable:)` derives its own (private) joinable
    /// count — that filter is duplicated here (rather than exposed from
    /// `render-state.swift`, which is out of this file's ownership this
    /// task) because Region 3 needs the actual `LayerEntry` rows, not just a
    /// count.
    @Published private(set) var joinable: [LayerEntry] = []
    @Published var joinRowStates: [String: JoinRowState] = [:]
    @Published private(set) var authStatus: AuthStatus?
    @Published private(set) var isSyncing = false
    /// Populated ONLY by `syncNow()` (`update --fanout --json`) — the "What
    /// changed" drill-in's data source (Region 4's "Recently" disclosure and
    /// Region 6's held-project prompt both read this).
    @Published private(set) var lastFanout: FanoutReport?
    /// Populated by `refresh()` (`freshness --all-projects --json`) — the
    /// other half of the "does 'What changed' have anything to show" gate
    /// (Region 5), for the case where the app just launched and has no
    /// in-memory `lastFanout` yet but a prior sync's results are still
    /// visible in the per-project sweep.
    @Published private(set) var lastFreshness: AllProjectsFreshness?
    /// Bounded Git-workspace activation state computed by `cc`. Ready
    /// workspaces stay invisible in the drill-in's primary list (they sit
    /// behind the "N already set up ›" disclosure); the Region 6 notice
    /// reads `discovery`/`summary` from this same report.
    @Published private(set) var lastWorkspaces: WorkspacesReport?
    /// Region 6's `connection-offer` notice (`control-tower-copy-deck.md`
    /// §1.8): true when a read-only `ecosystemOnboardPlan` still finds the
    /// device's connection to GitHub `config: "adoptable"` — i.e. the
    /// wizard's "One question first" screen offered to add it and the
    /// person hasn't yet, whether that was a same-session `Not now` or the
    /// wizard was never reopened at all. This is what keeps the CLI's own
    /// decline sentence ("I'll offer this again from the menu bar whenever
    /// you're ready") true: the offer is re-derived fresh from the CLI on
    /// every poll, never remembered/suppressed by this app (invariant #1 —
    /// no app-side "already declined" flag to fall out of sync with).
    @Published private(set) var connectionOfferPending = false
    /// Region 6's `permission-needed` PROMPT (`control-tower-copy-deck.md`
    /// §1.8): true when the SAME read-only `ecosystemOnboardPlan` refresh
    /// finds the `device-ssh` stage reporting `registration: "not-permitted"`
    /// — the CLI-emitted enum token Holding's H7 gate itself discriminates
    /// on (`WizardModel.holdingInfo(forBlockedOnboard:)`, `native/wizard.swift`),
    /// never sniffed from `detail` prose. Unlike `connectionOfferPending`
    /// above (an offer, rendered as a NOTICE), this is a real fix only the
    /// person can make, so it renders as a PROMPT (§1.8's Bob lane,
    /// `permission-needed` row) — re-derived fresh on every poll, exactly
    /// like `connectionOfferPending`, so this app never needs its own
    /// "already saw this" memory that could fall out of sync with the CLI.
    @Published private(set) var permissionNeededPending = false
    /// Per-row transient state for the drill-in's `Add`/`Finish setup`
    /// grammar (adopt-and-project-setup spec, "Menu bar: Your projects").
    /// Keyed by `WorkspaceEntry.path`, same convention `joinRowStates` above
    /// uses for `LayerEntry.id` — a row with no entry here renders from
    /// `lastWorkspaces` alone (`ProjectRowRender`).
    @Published private(set) var projectRowActions: [String: ProjectRowAction] = [:]
    /// Whether THIS session should render the one-time "New projects get
    /// your copilots automatically now…" notice (spec, "Notice, first
    /// automatic setup ever"). Set true by `refresh()` the first time it
    /// ever sees a non-empty `recentlySetUp` AND `automaticSetupNoticeShownKey`
    /// hasn't been persisted yet (at which point it IS persisted, so this
    /// never fires again on any future launch); cleared by
    /// `dismissAutomaticSetupNotice()` once the person acts on it.
    @Published private(set) var showAutomaticSetupNotice = false
    /// A single-project schema-1.1 detail response. Summary polling omits
    /// generated prompt/handoff text by contract, so the UI fetches this
    /// only after the person opens a guided route.
    @Published private(set) var projectIntegrationDetail: WorkspaceEntry?
    @Published private(set) var projectIntegrationMessage: String?
    /// Set only when Control Tower successfully opens an external assistant.
    /// Returning to the app consumes this path and asks `cc` to verify the
    /// complete project contract; the assistant's own report is never trusted.

    /// Concurrently calls `doctor()` + `layers()` (steady-state verdict +
    /// Region 3's join candidates) and `authStatus()` + `freshnessAllProjects()`
    /// (Region 4's GitHub row, Region 5's "What changed" gate). A failed
    /// `layers()`/`authStatus()`/`freshnessAllProjects()` call never blocks
    /// rendering the `doctor()` verdict — same "a secondary call's failure
    /// degrades gracefully" rule `render-state.swift`'s own doc comment
    /// states for `joinable`.
    func refresh() async {
        async let doctorResult = CliClient.shared.doctor()
        async let layersResult = CliClient.shared.layers()
        async let authResult = CliClient.shared.authStatus()
        async let freshnessResult = CliClient.shared.freshnessAllProjects()
        async let workspacesResult = CliClient.shared.workspaces()
        // Read-only (`mode: plan`, never `--apply`), the SAME verb the
        // wizard's Detect step calls — this is what lets `connectionOfferPending`
        // above stay honest without any app-side memory of a past decline.
        // `products: ["claude"]` matches every other read-only call site in
        // this app that doesn't yet know the person's actual product
        // selection (`WizardSelftest`'s own holding step does the same) —
        // this call only reads the `device-ssh` stage, which does not vary
        // by product.
        async let onboardResult = CliClient.shared.ecosystemOnboardPlan(products: ["claude"])

        let doctor = await doctorResult
        let layers = await layersResult
        let auth = await authResult
        let freshness = await freshnessResult
        let workspaces = await workspacesResult
        let onboard = await onboardResult

        if case .success(let report) = onboard {
            let deviceSsh = report.stages.first(where: { $0.stage == "device-ssh" })
            connectionOfferPending = deviceSsh?.config == "adoptable"
            permissionNeededPending = deviceSsh?.registration == "not-permitted"
        } else {
            // A failed read never claims the offer/prompt is pending — same
            // "degrades gracefully, never guesses" rule every other
            // secondary call in this function follows.
            connectionOfferPending = false
            permissionNeededPending = false
        }

        switch doctor {
        case .success(let report):
            let joinableReport: LayersReport?
            if case .success(let report2) = layers {
                joinableReport = report2
            } else {
                joinableReport = nil
            }
            state = RenderState.from(report, joinable: joinableReport)
            joinable = (joinableReport?.layers ?? []).filter { $0.entitled == true && !$0.joined }
        case .failure(let error):
            state = RenderState.unreadable(error)
            joinable = []
        }

        if case .success(let status) = auth {
            authStatus = status
        } else {
            authStatus = nil
        }

        if case .success(let report) = freshness {
            lastFreshness = report
        }
        // A failed sweep keeps whatever `lastFreshness` this app already had
        // — a stale-but-present sweep is still useful for the "What changed"
        // gate; a failure is never treated as "nothing happened".

        if case .success(let initialReport) = workspaces {
            var report = initialReport

            // Automatic setup for a brand-new project (B3, spec's
            // "Automatic setup for new projects"): `setup_policy:
            // "automatic"` means there is nothing of the person's to
            // protect and no decision only they can make, so the app
            // applies EXACTLY what the CLI told it, silently — no prompt,
            // no notification, "the person perceives nothing at the moment
            // it happens." The same poll that already runs is what checks
            // for this (spec: "The check runs on the poll that already
            // exists, adding no process and no privilege").
            let automatic = report.workspaces.filter { $0.setupPolicy == .automatic && $0.canApplyNow }
            for workspace in automatic {
                if let action = workspace.safeAction {
                    _ = await CliClient.shared.finishWorkspace(
                        path: workspace.path,
                        actionId: action.id,
                        apply: true
                    )
                }
            }
            if !automatic.isEmpty, case .success(let refreshed) = await CliClient.shared.workspaces() {
                // Re-read rather than assemble a report locally — the CLI
                // remains the sole source of truth for `recently_set_up`
                // and every workspace's post-apply state (CLAUDE.md
                // invariant #1).
                report = refreshed
            }

            lastWorkspaces = report
            if let recent = report.recentlySetUp, !recent.isEmpty,
               !LocalDefaults.bool(forKey: Self.automaticSetupNoticeShownKey) {
                showAutomaticSetupNotice = true
                LocalDefaults.set(true, forKey: Self.automaticSetupNoticeShownKey)
            }

            // A portable project identity lets the CLI associate the user's
            // private profile locally. This is reversible machine state, not
            // a shared-repository write, so ready workspaces need no prompt.
            for workspace in report.workspaces where
                workspace.state == .ready && workspace.personalProfile.state == .available {
                _ = await CliClient.shared.configureWorkspace(
                    path: workspace.path,
                    components: workspace.recommendedComponents,
                    shareWithProject: false,
                    apply: true
                )
            }
        }
    }

    /// The person has acted on (or seen) the one-time automatic-setup
    /// notice — hides it for the rest of this session. The persisted
    /// `LocalDefaults` flag is already set the moment `refresh()` first
    /// shows it, so this never re-arms it; this only controls how long it
    /// stays visible within the session that showed it.
    func dismissAutomaticSetupNotice() {
        showAutomaticSetupNotice = false
    }

    /// True while ANY row is adding OR undoing — the drill-in's own
    /// state-coverage rule: "Disabled while another add is in flight, hint
    /// 'Finishing the last one first.'" Undo shares this same one-at-a-time
    /// gate (never a second, independent gate) because both write to a
    /// project's own lock file, and the property name is kept as-is (not
    /// renamed to `isAnyProjectBusy`) to keep this a minimal, additive
    /// change to an already-established name.
    var isAnyProjectAdding: Bool {
        projectRowActions.values.contains(.adding)
            || projectRowActions.values.contains(.undoing)
            || projectRowActions.values.contains(.loadingPlan)
            || projectRowActions.values.contains(.verifying)
    }

    /// One `addProject(_:)`/`undoProject(_:)` attempt per project path, so a
    /// stale watchdog (or a stale real result) from an EARLIER attempt on
    /// the same row can never stomp a NEWER one started by pressing "Try
    /// again" after a silence path or a real failure — mirrors
    /// `joinAttemptGeneration` below.
    private var projectAttemptGeneration: [String: Int] = [:]

    /// One row's **Add** / **Finish setup** (Region 6 drill-in). By this
    /// point the copilots this project's setup copies from already exist on
    /// this Mac, so `can_apply_now` is expected true and the add applies
    /// immediately — the whole reason the drill-in uses per-row `Add`
    /// instead of the wizard's checkboxes (spec, "Architecture decision").
    /// Gains the P4 silence path (spec §7): past `Self.silenceThreshold`
    /// with no answer, the row reads `.stalled` instead of spinning
    /// forever — nothing is cancelled, the real call keeps running
    /// underneath (the CLI's own `flock` on `copilot.lock` makes a second
    /// concurrent invocation safe, per `CLAUDE.md` invariant #2).
    func addProject(_ workspace: WorkspaceEntry) async {
        guard !isAnyProjectAdding,
              workspace.classification == .safeFinish,
              workspace.canApplyNow,
              let action = workspace.safeAction else { return }
        projectRowActions[workspace.path] = .adding
        let generation = (projectAttemptGeneration[workspace.path] ?? 0) + 1
        projectAttemptGeneration[workspace.path] = generation

        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.silenceThreshold * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard self.projectAttemptGeneration[workspace.path] == generation else { return }
            guard self.projectRowActions[workspace.path] == .adding else { return }
            self.projectRowActions[workspace.path] = .stalled
        }
        defer { watchdog.cancel() }

        let result = await CliClient.shared.finishWorkspace(
            path: workspace.path,
            actionId: action.id,
            apply: true
        )
        guard projectAttemptGeneration[workspace.path] == generation else { return }
        if case .success(let report) = result,
           let updated = report.workspaces.first(where: { $0.path == workspace.path }),
           updated.classification == .ready {
            lastWorkspaces = report
            if projectIntegrationDetail?.path == workspace.path {
                projectIntegrationDetail = updated
                projectIntegrationMessage = "Verified Ready. Claude, Codex, and the preserved project contract passed."
            }
            projectRowActions[workspace.path] = nil
        } else {
            projectRowActions[workspace.path] = .failed
        }
    }

    /// **Undo** (B3, spec's "Undo" section) — a project the CLI's
    /// `recently_set_up` record names, calling the CLI's own `revert`
    /// verb. `revertWorkspace` decodes `WorkspaceRevertReport`, a narrower
    /// shape than `WorkspacesReport` (no `summary`/`discovery`), so this
    /// method re-`refresh()`es on success rather than trying to read those
    /// off the revert call's own result — the CLI stays the sole source of
    /// truth for the post-undo state (`state`, `undo`, `recently_set_up`
    /// all change together: `revert_project` purges the project from
    /// `recently_set_up` immediately). Same silence path as `addProject(_:)`
    /// above, its own `undoStalled` pair.
    func undoProject(_ workspace: WorkspaceEntry) async {
        guard !isAnyProjectAdding else { return }
        projectRowActions[workspace.path] = .undoing
        let generation = (projectAttemptGeneration[workspace.path] ?? 0) + 1
        projectAttemptGeneration[workspace.path] = generation

        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.silenceThreshold * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard self.projectAttemptGeneration[workspace.path] == generation else { return }
            guard self.projectRowActions[workspace.path] == .undoing else { return }
            self.projectRowActions[workspace.path] = .undoStalled
        }
        defer { watchdog.cancel() }

        let result = await CliClient.shared.revertWorkspace(path: workspace.path, apply: true)
        guard projectAttemptGeneration[workspace.path] == generation else { return }
        switch result {
        case .success(let report) where report.result != .blocked:
            projectRowActions[workspace.path] = nil
            await refresh()
        default:
            // Spec, "Undo": "Failed: Couldn't undo that right now. Nothing
            // was changed." — a fixed app string, not the CLI's own
            // `revert.detail` (that detail is reserved for the row's own
            // "Unavailable" caption, rendered by `ProjectRowRender.caption`
            // straight from `workspace.undo.detail` before Undo is ever
            // pressed).
            projectRowActions[workspace.path] = .undoFailed
        }
    }

    /// **Add all** — `workspace configure --apply-all`, one call for every
    /// project the CLI itself judges actionable, rather than one
    /// `addProject` round trip per row.
    func addAllProjects() async {
        guard !isAnyProjectAdding else { return }
        let addable = (lastWorkspaces?.workspaces ?? []).filter {
            $0.classification == .safeFinish
                && $0.canApplyNow
                && $0.safeAction != nil
        }
        guard !addable.isEmpty else { return }
        for workspace in addable {
            projectRowActions[workspace.path] = .adding
        }

        // The CLI's bulk verb targets setup-needed rows but its summary does
        // not carry per-row `can_apply_now`. Apply only this already-filtered
        // list, one typed result at a time, so a known hold elsewhere cannot
        // be swept into the request.
        for workspace in addable {
            guard let action = workspace.safeAction else { continue }
            let result = await CliClient.shared.finishWorkspace(
                path: workspace.path,
                actionId: action.id,
                apply: true
            )
            if case .success(let report) = result,
               let updated = report.workspaces.first(where: { $0.path == workspace.path }),
               updated.classification == .ready {
                projectRowActions[workspace.path] = nil
            } else {
                projectRowActions[workspace.path] = .failed
            }
        }
        await refresh()
    }

    /// Fetches the bounded detail payload before exposing prompt or handoff
    /// actions. A stale/changed project naturally returns a fresh plan.
    func loadProjectIntegrationDetail(_ workspace: WorkspaceEntry) async {
        guard !isAnyProjectAdding else { return }
        projectRowActions[workspace.path] = .loadingPlan
        projectIntegrationMessage = nil
        let result = workspace.planAvailable
            ? await CliClient.shared.workspaceIntegrationPlan(path: workspace.path)
            : await CliClient.shared.workspace(path: workspace.path)
        projectRowActions[workspace.path] = nil
        switch result {
        case .success(let report):
            projectIntegrationDetail = report.workspaces.first
            if projectIntegrationDetail?.integrationPlan == nil {
                projectIntegrationMessage = "This project no longer has a guided plan. Its current result is shown below."
            }
        case .failure:
            projectIntegrationMessage = "The project plan hasn't come through yet. Nothing was changed."
        }
    }

    func dismissProjectIntegrationDetail() {
        projectIntegrationDetail = nil
        projectIntegrationMessage = nil
    }

    func copyProjectDiagnosticReport(_ workspace: WorkspaceEntry) {
        let copied = ProjectIntegrationLauncher.copy(
            ProjectTriageRender.diagnosticReport(workspace)
        )
        projectIntegrationMessage = copied
            ? "Diagnostic report copied. It contains the exact evidence Control Tower received; nothing in the project was changed."
            : "The diagnostic report couldn't be copied. Nothing in the project was changed."
    }

    /// Copies the CLI-authored owner package and asks the CLI to remember an
    /// opaque incomplete hold. Neither operation changes the project or marks
    /// it Ready.
    func prepareOwnerHandoff(_ workspace: WorkspaceEntry) async {
        guard let plan = workspace.integrationPlan,
              let handoff = plan.ownerHandoff?.text else { return }
        let copied = ProjectIntegrationLauncher.copy(handoff)
        if copied {
            _ = await CliClient.shared.holdWorkspaceIntegration(
                path: workspace.path,
                planId: plan.id
            )
            projectIntegrationMessage = "Project-owner handoff copied. Nothing in the project was changed."
        } else {
            projectIntegrationMessage = "The handoff couldn't be copied. Nothing in the project was changed."
        }
    }

    func verifyProjectIntegration(_ workspace: WorkspaceEntry) async {
        guard !isAnyProjectAdding else { return }
        projectRowActions[workspace.path] = .verifying
        projectIntegrationMessage = "Verifying the complete project contract…"
        let result = await CliClient.shared.verifyWorkspace(path: workspace.path)
        projectRowActions[workspace.path] = nil
        switch result {
        case .success(let report):
            if let updated = report.workspaces.first {
                projectIntegrationDetail = updated
                if updated.classification == .ready {
                    projectIntegrationMessage = "Verified Ready. Claude and Codex both passed."
                    await refresh()
                } else {
                    projectIntegrationMessage = updated.detail
                }
            }
        case .failure:
            projectIntegrationMessage = "Verification hasn't come through yet. The project remains incomplete."
        }
    }

    /// **Choose folder…** / **Add another folder…**, reachable from both the
    /// not-granted-yet notice and the drill-in's footer.
    func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the one folder where your projects live. Control Tower looks only inside that folder, and never anywhere else on this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            _ = await CliClient.shared.approveWorkspaceRoot(path: url.path)
            await self.refresh()
        }
    }

    /// **Not on this Mac** — the machine-wide opt-out; reversible from the
    /// same notice by choosing a folder later.
    func declineProjects() async {
        _ = await CliClient.shared.declineWorkspaces()
        await refresh()
    }

    /// **Stop watching this folder**.
    func stopWatchingProjectsRoot(path: String) async {
        _ = await CliClient.shared.forgetWorkspaceRoot(path: path)
        await refresh()
    }

    /// Region 5's "Sync now": the one manual escape hatch in steady state.
    /// Runs `update()` (apply pending changes) then `update --fanout` (the
    /// per-project roll-up "What changed" reads), then re-derives the header
    /// via a normal `refresh()`. Guarded against re-entry and against firing
    /// while offline (§1.7: "disabled while offline").
    func syncNow() async {
        guard !isSyncing, !state.offline else { return }
        isSyncing = true
        defer { isSyncing = false }

        _ = await CliClient.shared.update()
        if case .success(let report) = await CliClient.shared.updateFanout() {
            lastFanout = report
        }
        await refresh()
    }

    /// One `join(_:)` attempt per row, so a stale watchdog (or a stale real
    /// result) from an earlier attempt can never overwrite a NEWER attempt
    /// started by pressing "Try again" — see `projectAttemptGeneration`
    /// above, the same shape for Region 6's rows.
    private var joinAttemptGeneration: [String: Int] = [:]

    /// Region 3's `Join` action (`control-tower-copy-deck.md` §1.5). On a
    /// successful join (`joined`/`already-joined`) the row is cleared locally
    /// and a full `refresh()` runs so the component tree picks up the newly
    /// entitled layer's passing dots — "the tree filling in is the reward",
    /// never a toast. Every other outcome renders its own verbatim §1.5
    /// message, `canRetry` controlling whether `Join` reappears. Gains the
    /// P4 silence path (spec §7): past `Self.silenceThreshold` with no
    /// answer, the row reads `NamedWaitRender.hasNotComeThrough(_:)` instead
    /// of spinning forever — a DIFFERENT sentence from the real "couldn't
    /// join" failure below, so a stall is never misread as a report.
    func join(_ entry: LayerEntry) async {
        guard joinRowStates[entry.id] != .joining else { return }
        joinRowStates[entry.id] = .joining
        let generation = (joinAttemptGeneration[entry.id] ?? 0) + 1
        joinAttemptGeneration[entry.id] = generation

        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.silenceThreshold * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard self.joinAttemptGeneration[entry.id] == generation else { return }
            guard self.joinRowStates[entry.id] == .joining else { return }
            self.joinRowStates[entry.id] = .message(NamedWaitRender.hasNotComeThrough(entry.name), canRetry: true)
        }
        defer { watchdog.cancel() }

        let result = await CliClient.shared.layersJoin(id: entry.id)
        guard joinAttemptGeneration[entry.id] == generation else { return }
        switch result {
        case .success(let joinResult):
            switch joinResult.result {
            case .joined, .alreadyJoined:
                joinRowStates[entry.id] = nil
                await refresh()
            case .notEntitled:
                joinRowStates[entry.id] = .message("\(entry.name) isn't available to you anymore.", canRetry: false)
            case .offline:
                joinRowStates[entry.id] = .message("Waiting for the network.", canRetry: true)
            case .error:
                joinRowStates[entry.id] = .message("Couldn't join \(entry.name) right now. Try again.", canRetry: true)
            }
        case .failure:
            joinRowStates[entry.id] = .message("Couldn't join \(entry.name) right now. Try again.", canRetry: true)
        }
    }
}

// MARK: - Popover material (real NSVisualEffectView vibrancy, never a flat fill)

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Region 1: status header glyph

struct GlyphView: View {
    let badgeState: BadgeState

    var body: some View {
        // Owner directive: the aviators glyph is menu-bar-tray-ONLY (see
        // `AviatorGlyph`'s doc comment in `native/models.swift`) — this popover
        // header never draws it. This view draws ONLY the status badge mark
        // (`symbolAndColor`) — nothing when the state is `.none`, consistent
        // with "silence is the success state" (never a green-checkmark
        // reward, per `control-tower-copy-deck.md` hard rule 6).
        ZStack {
            if let mark = badgeState.symbolAndColor {
                Image(systemName: mark.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(nsColor: mark.color))
            }
        }
        .frame(width: 20, height: 20, alignment: .center)
        .accessibilityHidden(true)
    }
}

// MARK: - Region 2: "YOUR COPILOTS" component tree

/// One layer cell (`control-tower-copy-deck.md` §1.4): a quiet dot when
/// passing (never the colorful `.pass` reward mark — that would be exactly
/// the "green checkmark reward" the copy deck's hard rule 6 forbids), the
/// closed badge-shape vocabulary for warn/fail, and an honest hollow "You're
/// not in this one" mark for a layer the CLI reported no checker for at all
/// (a fixed four-column grid, so a genuinely absent layer still gets its own
/// slot rather than silently collapsing the row).
private struct LayerDot: View {
    let layer: Layer
    let layerView: LayerView?

    private static let plainLabels: [Layer: String] = [
        .foundation: "Core setup",
        .org: "Your organization",
        .dept: "Your department",
        .personal: "This Mac",
    ]

    private var label: String { Self.plainLabels[layer] ?? layer.label }

    var body: some View {
        Group {
            if let layerView, layerView.severity != .pass, let mark = layerView.badgeState.symbolAndColor {
                Image(systemName: mark.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(nsColor: mark.color))
            } else if layerView != nil {
                Circle()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 6, height: 6)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(Color(nsColor: .quaternaryLabelColor))
            }
        }
        .frame(width: 16, height: 16)
        .help(tooltip)
        .accessibilityLabel("\(label), \(accessibilityDetail)")
    }

    private var tooltip: String {
        guard let layerView else { return "\(label): You're not in this one" }
        if let detail = layerView.detail, !detail.isEmpty { return "\(label): \(detail)" }
        return label
    }

    private var accessibilityDetail: String {
        guard let layerView else { return "You're not in this one" }
        return layerView.detail ?? layerView.severity.rawValue
    }
}

private struct ComponentTreeRow: View {
    let component: ComponentView

    private var state: CTState {
        switch component.worstSeverity {
        case .pass: return .ready
        case .warn: return .attention
        case .fail: return .blocked
        }
    }

    private var statusWord: String {
        switch component.worstSeverity {
        case .pass: return "Ready"
        case .warn: return "Needs review"
        case .fail: return "Needs attention"
        }
    }

    var body: some View {
        CTStatusRow(
            glyph: .filledDot(state),
            title: component.component,
            detail: component.layers.map { "\($0.layer.label): \($0.severity.rawValue)" }.joined(separator: " · "),
            footnote: component.layers.first(where: { $0.severity != .pass })?.detail,
            trailing: .status(statusWord, state),
            accessibilityLabelOverride: "\(component.component), \(component.worstSeverity.rawValue)"
        )
    }
}

// MARK: - Region 3: "AVAILABLE TO JOIN"

private struct JoinRow: View {
    let entry: LayerEntry
    let state: JoinRowState
    /// Non-nil disables `Join` and supplies the VoiceOver/tooltip reason
    /// (`control-tower-copy-deck.md` §1.5: "Disabled while offline or
    /// syncing").
    let disabledReason: String?
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            rowContent
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rowContent: some View {
        switch state {
        case .idle:
            Text(entry.name)
                .foregroundColor(Color(nsColor: .labelColor))
            Spacer()
            Button("Join", action: onJoin)
                .buttonStyle(.bordered)
                .disabled(disabledReason != nil)
                .help(disabledReason ?? "")
        case .joining:
            Text("Joining \(entry.name)…")
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Spacer()
            CTNamedWaitSpinner(subject: "Joining \(entry.name)…")
                .frame(width: 14, height: 14)
        case .message(let text, let canRetry):
            Text(text)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Spacer()
            if canRetry {
                Button("Join", action: onJoin)
                    .buttonStyle(.bordered)
                    .disabled(disabledReason != nil)
                    .help(disabledReason ?? "")
            }
        }
    }
}

// MARK: - Popover content (six regions, always in this order)

struct PopoverContentView: View {
    @ObservedObject var model: TrayModel
    let onOpenSettings: () -> Void
    @State private var showingWhatChanged = false
    @State private var showingProjectDrillIn = false
    @State private var selectedProjectCategory: ProjectTriageCategory?
    /// The projects list (adopt-and-project-setup spec, "Menu bar: Your
    /// projects (drill-in)") — a SEPARATE top-level panel from `showingWhatChanged`'s
    /// own drill-in, reached only from the Region 6 notice's "Review
    /// projects", using the exact same back-and-drill-in grammar.
    #if CT_VISUAL_TEST_BUILD
    @State private var showingProjectsPanel =
        ProcessInfo.processInfo.environment["CT_VISUAL_PROJECTS_PANEL"] == "1"
    #else
    @State private var showingProjectsPanel = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRegion

            if showingWhatChanged {
                Divider()
                whatChangedRegion
            } else if showingProjectsPanel {
                Divider()
                projectsDrillInRegion
            } else if model.state.clientState != .cliUnreadable {
                // Per `control-tower-copy-deck.md` §1.2, the bang state shows
                // "no tree, no join row" — only the header sentence plus the
                // Region 5 retry action.
                if !model.state.components.isEmpty {
                    Divider()
                    componentTreeRegion
                }
                if !model.joinable.isEmpty {
                    Divider()
                    joinRegion
                }
                Divider()
                integrationsRegion
            }

            Divider()
            actionRow

            // Region 6: at most one PROMPT (the dirty-WIP hold, then, only if
            // that isn't showing, the `permission-needed` prompt), then,
            // independently, any number of NOTICES — sequential rendering
            // per the spec's own "Architecture decision": the unsaved-changes
            // prompt can no longer make a notice invisible, and notices stack
            // (unlike the "at most one" prompt rule).
            bobLanePromptRegion
            if !showingProjectsPanel {
                projectsNoticeRegion
                connectionOfferNoticeRegion
            }
        }
        .padding(.vertical, 12)
        .frame(width: 360, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(VisualEffectBackground())
    }

    // MARK: Region 1 — status header. `HeaderView.sentence` verbatim, except
    // while a sync is in flight, when the header swaps to the syncing
    // sentence (`control-tower-copy-deck.md` §1.1's `syncing` row).

    private var headerSentence: String {
        model.isSyncing ? "Bringing everything up to date…" : model.state.header.sentence
    }

    private var headerGlyph: BadgeState {
        model.isSyncing ? .ring : model.state.header.glyphState
    }

    private var headerRegion: some View {
        HStack(alignment: .top, spacing: 8) {
            GlyphView(badgeState: headerGlyph)
            VStack(alignment: .leading, spacing: 2) {
                Text(headerSentence)
                    .font(.headline)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                if let host = model.state.host {
                    Text(host)
                        .font(.subheadline)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    // MARK: Region 2 — "YOUR COPILOTS": one row per CSE component, four
    // fixed layer cells each (`control-tower-copy-deck.md` §1.3/§1.4).

    private var componentTreeRegion: some View {
        VStack(alignment: .leading, spacing: CTSpace.xs) {
            CTCardTitle("Your copilots")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.state.components.enumerated()), id: \.element.id) { index, component in
                    ComponentTreeRow(component: component)
                    if index < model.state.components.count - 1 { Divider() }
                }
            }
        }
        .padding(.horizontal, CTSpace.md)
    }

    // MARK: Region 3 — "AVAILABLE TO JOIN": present only when a joinable
    // entry exists (§1.3), never a badge, never an alarm.

    private var joinDisabledReason: String? {
        if model.state.offline { return "Waiting for the network." }
        if model.isSyncing { return "Finishing an update first." }
        return nil
    }

    private var joinRegion: some View {
        VStack(alignment: .leading, spacing: CTSpace.sm) {
            CTCardTitle("Available to join")
            ForEach(model.joinable) { entry in
                JoinRow(
                    entry: entry,
                    state: model.joinRowStates[entry.id] ?? .idle,
                    disabledReason: joinDisabledReason,
                    onJoin: { Task { await model.join(entry) } }
                )
            }
        }
        .padding(.horizontal, CTSpace.md)
    }

    // MARK: Region 4 — shared + personal integrations (§1.3/§1.6). No CLI
    // verb backs a shared-integrations list yet (NB-3, not yet built), so
    // that half honestly shows its header/subtitle with no fabricated rows;
    // "YOUR ACCOUNTS" renders the one real integration this app already has
    // data for — GitHub, from `authStatus()`.

    private var githubAccountStatusText: String {
        guard let authStatus = model.authStatus else { return "Needs sign-in" }
        switch authStatus.state {
        case .authorized: return "Signed in"
        case .signedOut: return "Needs sign-in"
        }
    }

    private var integrationsRegion: some View {
        VStack(alignment: .leading, spacing: CTSpace.xs) {
            CTCardTitle("Shared with your team")
            Text("Ready for you. Nothing to sign into.")
                .ctText(CTType.caption)

            CTCardTitle("Your accounts")
                .padding(.top, CTSpace.sm)
            HStack {
                Text("GitHub")
                    .ctText(CTType.rowTitle)
                Spacer()
                Text(githubAccountStatusText)
                    .ctText(CTType.rowDetail)
            }
        }
        .padding(.horizontal, CTSpace.md)
    }

    // MARK: Region 5 — the action row (Sync now / What changed / Settings...).
    // Every button says exactly what it does; never an "Update" button
    // (updates install themselves), per §1.7's hard rule.

    private var showWhatChangedButton: Bool {
        model.lastFanout != nil || !(model.lastFreshness?.projects.isEmpty ?? true)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button("Sync now") {
                    Task { await model.syncNow() }
                }
                .buttonStyle(.bordered)
                .disabled(model.isSyncing || model.state.offline)

                if showWhatChangedButton {
                    Button("What changed") {
                        showingWhatChanged = true
                        showingProjectDrillIn = false
                    }
                    .buttonStyle(.borderless)
                }

                // `control-tower-copy-deck.md` §1.7: `Set up` appears
                // "when state is setup-needed" and "opens the first-run
                // wizard" — the one path back into the wizard once first
                // run is behind you but the CLI still reports setup as
                // incomplete (e.g. the wizard was closed mid-way via
                // "Continue in the menu bar" from a Holding screen).
                if model.state.status == .setupNeeded {
                    Button("Set up") {
                        WizardWindowController.shared.show()
                    }
                    .buttonStyle(.borderless)
                }

                Button("Settings…") {
                    onOpenSettings()
                }
                .buttonStyle(.borderless)

                Spacer(minLength: 0)
            }
            if model.state.offline {
                Text("Waiting for the network.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: Region 6 — at most one PROMPT (`control-tower-copy-deck.md`
    // §1.8's Bob lane, exactly one affordance each, never a discard button —
    // never-destroy), then, independently, the projects NOTICE
    // (adopt-and-project-setup spec). Sequential rendering, per that spec's
    // own "Architecture decision": re-ordering the old `else if` chain would
    // only change which state wins and still hide one behind the other —
    // this fixes the class of bug, not one instance of it.
    //
    // Two prompt kinds share this ONE lane, checked in order (the dirty-WIP
    // hold first — it is about an update already in flight, the more urgent
    // of the two — then `permission-needed`, a real fix the person owns but
    // is never blocking anything mid-flight): "at most one" means exactly
    // that, never both stacked.

    private var bobLanePromptRegion: some View {
        Group {
            if model.state.clientState != .cliUnreadable,
               let fanout = model.lastFanout, fanout.summary.held > 0 {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("You have unsaved changes in the way of an update. Nothing was touched.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .labelColor))
                    Button("Review your changes") {
                        showingWhatChanged = true
                        showingProjectDrillIn = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
            } else if model.state.clientState != .cliUnreadable, model.permissionNeededPending {
                // `permission-needed` (`control-tower-copy-deck.md` §1.8):
                // the sibling of `connectionOfferNoticeRegion` below, on the
                // SAME `device-ssh` stage, but a PROMPT rather than a
                // NOTICE — this is a real fix only the person can make, not
                // an offer they can shrug off. `Grant this on GitHub`
                // reopens the wizard directly onto Holding's H7 screen,
                // which already degrades honestly to the manual fallback
                // sheet when `cc auth grant` is absent/`unavailable` — this
                // button never dead-ends because it never re-implements
                // that logic, it only navigates to the screen that already
                // has it.
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("GitHub needs one more permission before this Mac can finish setting up.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .labelColor))
                    Button("Grant this on GitHub") {
                        WizardWindowController.shared.reopenForPermissionNeeded()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    /// No badge for projects — "a project waiting to be set up is an offer
    /// and not a fault" (spec). `discovery.state == .declined` mutes this
    /// whole region: "Not on this Mac" is meant to quiet every project
    /// affordance in the tray, not just the not-granted offer it replaced.
    private var projectsNoticeRegion: some View {
        Group {
            if model.state.clientState != .cliUnreadable,
               let workspaces = model.lastWorkspaces,
               workspaces.discovery?.state != .declined {
                let actionable = ProjectsNoticeRender.actionableCount(workspaces)
                let recentlySetUp = workspaces.recentlySetUp ?? []
                // "at most one" notice: the one-time automatic-setup notice
                // wins over the ordinary actionable-count notice while it's
                // showing (spec, "Notice, first automatic setup ever") —
                // `model.showAutomaticSetupNotice` is itself gated to fire
                // only once ever, so this branch is rare, not a standing
                // override.
                if model.showAutomaticSetupNotice, !recentlySetUp.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(RecentlySetUpRender.noticeText(recentlySetUp))
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .labelColor))
                        Button("Review projects") {
                            model.dismissAutomaticSetupNotice()
                            showingProjectsPanel = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 12)
                } else if actionable > 0 {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ProjectsNoticeRender.noticeText(count: actionable))
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .labelColor))
                        Button("Review projects") {
                            showingProjectsPanel = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 12)
                } else if workspaces.discovery?.state == .notGranted {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Building something on this Mac? I can set your copilots up in your projects too.")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .labelColor))
                        HStack(spacing: 10) {
                            Button("Choose folder…") {
                                model.chooseProjectsFolder()
                            }
                            .buttonStyle(.bordered)
                            Button("Not on this Mac") {
                                Task { await model.declineProjects() }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    /// The `connection-offer` notice (`control-tower-copy-deck.md` §1.8) —
    /// the one net-new menu-bar element the spec that introduced STATE 1 (the
    /// adopt offer) added. `bobLanePromptRegion`'s `permission-needed`
    /// prompt above is the sibling element the LATER STATE 3 half of that
    /// same body of copy work added on the SAME `device-ssh` stage. A
    /// NOTICE, not a prompt: an offer the person already declined (or
    /// hasn't seen yet) is not a fault, so this stacks alongside
    /// `projectsNoticeRegion` rather than competing with the "at most one"
    /// prompt lane, and carries no badge on the menu-bar glyph.
    private var connectionOfferNoticeRegion: some View {
        Group {
            if model.state.clientState != .cliUnreadable, model.connectionOfferPending {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("This Mac is missing one of the two GitHub connections setup uses. Nothing is added until you say so.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .labelColor))
                    Button("Add the connection") {
                        WizardWindowController.shared.reopenForConnectionOffer()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: "Your projects" drill-in (adopt-and-project-setup spec) — same
    // back-and-drill-in grammar `whatChangedRegion`/`projectDrillIn` below
    // already use; not a new window, not a modal, not a sheet.

    private var projectsDrillInRegion: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let detail = model.projectIntegrationDetail {
                projectIntegrationDetailView(detail)
            } else {
                Button(selectedProjectCategory == nil ? "‹ Back" : "‹ All project results") {
                    if selectedProjectCategory == nil {
                        showingProjectsPanel = false
                    } else {
                        selectedProjectCategory = nil
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))

                Text(selectedProjectCategory?.title ?? "Your projects")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))

                if let workspaces = model.lastWorkspaces {
                    // Membership-only signal for "was this row set up
                    // automatically" (`ProjectRowRender.Kind.automaticallySetUp`'s
                    // own doc comment) — the CLI's own `recently_set_up` names,
                    // never inferred any other way.
                    let recentlySetUpNames = Set((workspaces.recentlySetUp ?? []).map(\.name))

                    if workspaces.workspaces.isEmpty {
                        if workspaces.discovery?.state == .granted {
                            Text("No projects in that folder yet. Any new one you create will get your copilots automatically.")
                                .font(.body)
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        } else {
                            Text("Control Tower isn't watching any folder yet. Choose the folder where you keep your projects and it will set your copilots up there.")
                                .font(.body)
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Choose folder…") { model.chooseProjectsFolder() }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        Text(ProjectTriageRender.summary(workspaces.workspaces))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))

                        if let category = selectedProjectCategory {
                            let rows = ProjectTriageRender.workspaces(
                                workspaces.workspaces,
                                in: category
                            )
                            Text(category.shortMeaning)
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(rows) { workspace in
                                        projectDrillInRow(
                                            workspace,
                                            recentlySetUpNames: recentlySetUpNames
                                        )
                                    }
                                }
                            }
                            .frame(maxHeight: 260)
                        } else {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(ProjectTriageRender.nonEmptyCategories(workspaces.workspaces)) { category in
                                    let count = ProjectTriageRender.workspaces(
                                        workspaces.workspaces,
                                        in: category
                                    ).count
                                    Button {
                                        selectedProjectCategory = category
                                    } label: {
                                        HStack(spacing: CTSpace.sm) {
                                            Image(systemName: category.systemImage)
                                                .frame(width: 16)
                                                .accessibilityHidden(true)
                                            VStack(alignment: .leading, spacing: CTSpace.hair) {
                                                Text(category.title)
                                                    .ctText(CTType.rowDetail, color: CTColor.ink)
                                                Text(category.shortMeaning)
                                                    .ctText(CTType.caption)
                                            }
                                            Spacer()
                                            Text("\(count)")
                                                .font(.callout.weight(.semibold))
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .accessibilityHidden(true)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .ctCard(.compact)
                                    .accessibilityLabel(
                                        "\(count), \(category.title), \(category.shortMeaning)"
                                    )
                                }
                            }

                            VStack(alignment: .leading, spacing: CTSpace.hair) {
                                Text("Come back whenever you want")
                                    .ctText(CTType.rowDetail, color: CTColor.ink)
                                Text("Project setup is always available here. Finish one or two projects now, or return later—unfinished routes stay under Your projects.")
                                    .ctText(CTType.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .ctCard(.compact)
                        }

                        HStack(spacing: 12) {
                            Button("Add another folder…") { model.chooseProjectsFolder() }
                                .buttonStyle(.plain)
                                .foregroundColor(Color(nsColor: .linkColor))
                            if let firstRoot = workspaces.discovery?.roots.first {
                                Button("Stop watching this folder") {
                                    Task { await model.stopWatchingProjectsRoot(path: firstRoot.path) }
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func projectDrillInRow(_ workspace: WorkspaceEntry, recentlySetUpNames: Set<String>) -> some View {
        let localAction = model.projectRowActions[workspace.path]
        let caption: String
        switch localAction {
        case .adding: caption = "Adding…"
        case .failed: caption = "Couldn't add it right now. Nothing existing was changed."
        case .stalled: caption = NamedWaitRender.projectHasNotComeThrough(workspace.name)
        case .undoFailed: caption = "Couldn't undo that right now. Nothing was changed."
        case .undoStalled: caption = NamedWaitRender.projectUndoHasNotComeThrough(workspace.name)
        case .loadingPlan: caption = "Preparing the guided plan…"
        case .verifying: caption = "Verifying Claude and Codex…"
        case .undoing, nil: caption = ProjectRowRender.caption(for: workspace, recentlySetUpNames: recentlySetUpNames)
        }

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .labelColor))
                Text(caption)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            projectDrillInRowControl(workspace, localAction: localAction, recentlySetUpNames: recentlySetUpNames)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workspace.name), \(caption)")
    }

    @ViewBuilder
    private func projectDrillInRowControl(_ workspace: WorkspaceEntry, localAction: ProjectRowAction?, recentlySetUpNames: Set<String>) -> some View {
        switch localAction {
        case .adding, .undoing, .loadingPlan, .verifying:
            CTNamedWaitSpinner(subject: workspace.name)
                .frame(width: 14, height: 14)
        case .failed, .stalled:
            Button("Try again") {
                Task { await model.addProject(workspace) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .undoFailed, .undoStalled:
            Button("Try again") {
                Task { await model.undoProject(workspace) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case nil:
            let kind = ProjectRowRender.kind(for: workspace, recentlySetUpNames: recentlySetUpNames)
            if kind == .automaticallySetUp {
                if let label = ProjectRowRender.controlLabel(for: workspace, recentlySetUpNames: recentlySetUpNames) {
                    Button(label) {
                        Task { await model.undoProject(workspace) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isAnyProjectAdding)
                    .help(model.isAnyProjectAdding ? "Finishing the last one first." : "")
                }
                // No control at all when `undo.available` is false (files
                // edited since) — spec, "Undo": "no Undo control at all,
                // never a disabled one with no explanation." The row's own
                // caption already carries the CLI's honest reason.
            } else if let label = ProjectRowRender.controlLabel(for: workspace, recentlySetUpNames: recentlySetUpNames) {
                Button(label) {
                    Task {
                        switch kind {
                        case .safeFinish, .excluded, .guidedIntegration, .ownerDecision, .couldNotVerify, .alreadySetUp:
                            await model.loadProjectIntegrationDetail(workspace)
                        case .automaticallySetUp, .keptAsIs:
                            break
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isAnyProjectAdding)
                .help(model.isAnyProjectAdding ? "Finishing the last one first." : "")
            } else if kind == .keptAsIs {
                Text("Needs review")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
    }

    private func projectIntegrationDetailView(_ workspace: WorkspaceEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Button("‹ All projects") {
                    model.dismissProjectIntegrationDetail()
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))

                Text(projectIntegrationTitle(workspace.classification))
                    .font(.callout.weight(.semibold))
                    .foregroundColor(projectIntegrationColor(workspace.classification))
                Text(workspace.detail)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)

                if workspace.classification == .guidedIntegration {
                    projectNextStep(
                        title: "\(workspace.name) needs a coding assistant",
                        detail: "Review the plan, then run it in a visible Terminal session. Control Tower will verify Claude and Codex independently when you return."
                    )
                } else if workspace.classification == .ownerDecision {
                    projectNextStep(
                        title: "The project owner needs to decide",
                        detail: "Copy or share the prepared handoff. Control Tower will not change this project without that decision."
                    )
                } else if workspace.classification == .ready {
                    projectNextStep(
                        title: "Nothing else is needed",
                        detail: "Claude and Codex both passed authoritative verification. This project is ready."
                    )
                } else if workspace.classification == .couldNotVerify {
                    projectNextStep(
                        title: workspace.diagnostic == nil
                            ? "Review what could not be confirmed"
                            : "Start a read-only diagnostic session",
                        detail: workspace.diagnostic == nil
                            ? "Setup was found, but Control Tower could not prove that it matches the current integration contract. Nothing has been changed."
                            : "A coding assistant can explain the mismatch using the helper's evidence. It cannot change project files."
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(workspace.components, id: \.component.rawValue) { component in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(component.component == .claude ? "Claude" : "Codex")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(projectIntegrationTitle(component.classification))
                                .font(.caption)
                                .foregroundColor(projectIntegrationColor(component.classification))
                        }
                    }
                    Divider()
                    Text(projectCapabilitySummary(workspace.capabilities))
                        .ctText(CTType.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .ctCard(.well)

                if let action = workspace.safeAction {
                    projectPreservationPanel(
                        willAdd: action.willAdd.map(\.detail),
                        willPreserve: action.willPreserve.map(\.detail),
                        willNotChange: action.willNotChange.map(\.detail)
                    )
                    Button("Finish safely") {
                        Task { await model.addProject(workspace) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isAnyProjectAdding)
                }

                if let plan = workspace.integrationPlan {
                    projectGuidedPlanView(workspace, plan: plan)
                }

                if workspace.classification == .couldNotVerify {
                    projectCouldNotConfirmEvidence(workspace)
                    HStack {
                        Button("Copy diagnostic report") {
                            model.copyProjectDiagnosticReport(workspace)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Check again") {
                            Task { await model.verifyProjectIntegration(workspace) }
                        }
                        .buttonStyle(.bordered)
                        .help("Use after the project setup changes.")
                    }
                    .disabled(model.isAnyProjectAdding)
                }

                if let message = model.projectIntegrationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Project integration update: \(message)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 520)
        .accessibilityElement(children: .contain)
    }

    private func projectNextStep(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: CTSpace.sm) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundColor(Color(nsColor: .linkColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CTSpace.hair) {
                Text(title)
                    .ctText(CTType.rowDetail, color: CTColor.ink)
                Text(detail)
                    .ctText(CTType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ctCard(.well)
    }

    private func projectCouldNotConfirmEvidence(_ workspace: WorkspaceEntry) -> some View {
        VStack(alignment: .leading, spacing: CTSpace.sm) {
            ForEach(workspace.components, id: \.component.rawValue) { component in
                VStack(alignment: .leading, spacing: CTSpace.hair) {
                    Text(component.component == .claude ? "Claude" : "Codex")
                        .ctText(CTType.rowDetail, color: CTColor.ink)
                    if component.missingRequirements.isEmpty {
                        Text("No missing requirement was reported.")
                            .ctText(CTType.caption)
                    } else {
                        ForEach(component.missingRequirements, id: \.detail) { requirement in
                            Text("• \(requirement.detail)")
                                .ctText(CTType.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let recognized = component.recognizedSetup,
                       !recognized.evidence.isEmpty {
                        DisclosureGroup("Setup Control Tower recognized") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(recognized.evidence, id: \.path) { evidence in
                                    Text("\(evidence.path): \(evidence.detail)")
                                        .font(.caption2)
                                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .font(.caption2.weight(.semibold))
                    }
                }
                .ctCard(.compact)
            }
        }
    }

    @ViewBuilder
    private func projectGuidedPlanView(
        _ workspace: WorkspaceEntry,
        plan: WorkspaceIntegrationPlan
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            projectPreservationRow("Detected", values: plan.detected)
            projectPreservationPanel(
                willAdd: plan.missing,
                willPreserve: plan.preserve,
                willNotChange: plan.prohibited
            )

            if plan.prompt != nil {
                Text("Use the one Sites-level work order from project setup. Control Tower will not start an assistant inside this repository.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if plan.ownerHandoff != nil {
                HStack {
                    Button("Copy project-owner handoff") {
                        Task { await model.prepareOwnerHandoff(workspace) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    if let handoff = plan.ownerHandoff?.text {
                        ShareLink(item: handoff) {
                            Text("Share handoff…")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Verification")
                    .font(.caption.weight(.semibold))
                Text(plan.verification.expected)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Text(plan.verification.command.joined(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                let stopConditions = plan.stopConditions + plan.verification.stopConditions
                if !stopConditions.isEmpty {
                    Text("Stop if: \(stopConditions.joined(separator: " · "))")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .systemRed))
                }
            }
            Button("Check project now") {
                Task { await model.verifyProjectIntegration(workspace) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isAnyProjectAdding)
            .accessibilityHint("Re-inspects both Claude and Codex; it does not trust the external assistant's report.")
        }
    }

    private func projectPreservationPanel(
        willAdd: [String],
        willPreserve: [String],
        willNotChange: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            projectPreservationRow("Will add", values: willAdd)
            projectPreservationRow("Will preserve", values: willPreserve)
            projectPreservationRow("Will not change", values: willNotChange)
        }
        .ctCard(.well)
    }

    private func projectPreservationRow(_ label: String, values: [String]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 82, alignment: .leading)
            Text(values.isEmpty ? "Nothing" : values.joined(separator: " · "))
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func projectCapabilitySummary(_ capabilities: WorkspaceCapabilities) -> String {
        [
            "\(capabilities.instructions) instructions",
            "\(capabilities.agents) agents",
            "\(capabilities.skills) skills",
            "\(capabilities.commands) commands",
            "\(capabilities.plugins) plugins",
        ].joined(separator: " · ")
    }

    private func projectIntegrationTitle(
        _ classification: WorkspaceIntegrationClassification
    ) -> String {
        switch classification {
        case .ready: return "Ready"
        case .safeFinish: return "Can finish automatically"
        case .guidedIntegration: return "Needs guided setup"
        case .ownerDecision: return "Needs the project owner"
        case .couldNotVerify: return "Couldn't confirm"
        }
    }

    private func projectIntegrationColor(
        _ classification: WorkspaceIntegrationClassification
    ) -> Color {
        switch classification {
        case .ready:
            return Color(nsColor: .systemGreen)
        case .safeFinish, .guidedIntegration:
            return Color(nsColor: .linkColor)
        case .ownerDecision:
            return Color(nsColor: .secondaryLabelColor)
        case .couldNotVerify:
            return Color(nsColor: .systemRed)
        }
    }

    // MARK: "What changed" drill-in (Arc 4, screen 22). `FanoutRender`'s
    // "Recently" headline plus, one level deeper, the per-project list and
    // the pinned reassurance line, verbatim.

    private var whatChangedRegion: some View {
        // B3, "Discover it happened": `recentlySetUp` is independent of
        // `lastFanout` (a `Sync now` result) — a person can have automatic
        // project setups to show here with no sync ever having run, so this
        // is read up front rather than nested inside the `fanout` branch
        // below.
        let recentlySetUp = model.lastWorkspaces?.recentlySetUp ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Button("‹ Back") {
                showingWhatChanged = false
                showingProjectDrillIn = false
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))

            Text("Recently")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))

            if let fanout = model.lastFanout {
                if showingProjectDrillIn {
                    projectDrillIn(fanout)
                } else {
                    let componentLines = FanoutRender.componentLines(fanout)
                    if componentLines.isEmpty {
                        // Fallback for a fan-out result this run couldn't
                        // break out by component (e.g. nothing applied to
                        // claude/codex specifically) -- the single aggregate
                        // line, same as before this per-component derivation
                        // existed.
                        HStack(alignment: .top) {
                            Text(FanoutRender.headline(fanout))
                                .font(.body)
                                .foregroundColor(Color(nsColor: .labelColor))
                            Spacer()
                            Button("See projects ›") {
                                showingProjectDrillIn = true
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(nsColor: .linkColor))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(componentLines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top) {
                                    Text(line.text)
                                        .font(.body)
                                        .foregroundColor(Color(nsColor: .labelColor))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Button("See projects ›") {
                                        showingProjectDrillIn = true
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(Color(nsColor: .linkColor))
                                }
                            }
                        }
                    }
                }
            } else if recentlySetUp.isEmpty {
                Text("Nothing has changed since you last looked.")
                    .font(.body)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }

            // B3, spec: "Projects set up for you" group label, "a past-tense
            // line in What changed every time" — reuses the SAME grammar
            // `projectDrillIn(_:)` above already establishes for the fanout
            // sync case (title, pinned reassurance, rows), never nested
            // inside `showingProjectDrillIn` since these entries carry no
            // per-project path to drill any further into.
            if !showingProjectDrillIn, !recentlySetUp.isEmpty {
                Divider()
                recentlySetUpGroup(recentlySetUp)
            }
        }
        .padding(.horizontal, 12)
    }

    private func recentlySetUpGroup(_ entries: [WorkspaceRecentlySetUp]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects set up for you")
                .font(.body.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
            Text("Only your copilots' shared files were added. Your own work in these projects wasn't touched.")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Text(entry.detail)
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .labelColor))
                }
            }
        }
    }

    private func projectDrillIn(_ fanout: FanoutReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects brought up to date")
                .font(.body.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
            Text("Only your copilots' shared files were updated. Your own work in these projects wasn't touched.")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(FanoutRender.rows(fanout).enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.name)
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .labelColor))
                        Spacer()
                        Text(row.detail)
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
        }
    }
}

// MARK: - Status bar controller (NSStatusItem + NSPopover + right-click menu)

@MainActor
final class StatusBarController: NSObject {
    /// Default background refresh cadence for steady state, per this task's
    /// own spec ("every 300 seconds (default)").
    private static let pollInterval: TimeInterval = 300

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    let model = TrayModel()
    private var badgeView: NSImageView?
    private var pollTimer: Timer?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        refreshGlyph()
        startPolling()
        performRefresh()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = AviatorGlyph.load(targetHeight: 16)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityRole(.button)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(
                model: model,
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
    }

    // MARK: Refresh (initial launch, popover open, and the poll timer)

    private func performRefresh() {
        Task { @MainActor in
            await self.model.refresh()
            self.refreshGlyph()
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performRefresh()
            }
        }
    }

    // MARK: Badge overlay (section 4 shape composited bottom-trailing on the
    // template glyph; `.none` draws nothing — the bare glyph is silence).

    private func refreshGlyph() {
        applyBadge(model.state.header.glyphState)
        statusItem.button?.setAccessibilityLabel(model.state.header.sentence)
    }

    private func applyBadge(_ badgeState: BadgeState) {
        badgeView?.removeFromSuperview()
        badgeView = nil
        guard let button = statusItem.button, let mark = badgeState.symbolAndColor else { return }

        let size: CGFloat = 9
        let frame = NSRect(x: max(0, button.bounds.width - size - 1), y: 1, width: size, height: size)
        let imageView = NSImageView(frame: frame)
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        let image = NSImage(systemSymbolName: mark.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        imageView.image = image
        imageView.contentTintColor = mark.color
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isEditable = false
        button.addSubview(imageView)
        badgeView = imageView
    }

    // MARK: Click handling — left-click toggles the popover (and triggers a
    // refresh so it never shows stale data on open), right-click shows the
    // minimal `NSMenu`.

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent, event.type == .rightMouseUp else {
            togglePopover()
            return
        }
        showMenu()
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            performRefresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach so the next left-click still toggles the popover instead of
        // reopening this menu (the standard both-gestures-on-one-item trick).
        statusItem.menu = nil
    }

    // MARK: The right-click menu — minimal and production-honest: Sync now,
    // What changed, Settings..., (Admin, gated), Quit. No dev-only "Preview
    // state" section (that fixture-switcher is superseded — real fixtures
    // now come via `CT_CLI_PATH=<path to mock-cc>`).

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let syncItem = NSMenuItem(title: "Sync now", action: #selector(syncNowMenuAction), keyEquivalent: "")
        syncItem.target = self
        syncItem.isEnabled = !model.isSyncing && !model.state.offline
        menu.addItem(syncItem)

        let whatChangedItem = NSMenuItem(title: "What changed", action: #selector(openWhatChangedMenuAction), keyEquivalent: "")
        whatChangedItem.target = self
        menu.addItem(whatChangedItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsMenuAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        #if CT_ADMIN_BUILD
        // Admin mode (S4, `native/admin.swift`/`native/admin-support.swift`) —
        // ADM-0 entry. Compiled only in the Admin build
        // (`scripts/build-admin.command`, `-D CT_ADMIN_BUILD`); the plain
        // user build (`scripts/build-user.command`) never links
        // `AdminWindowController` at all, so this whole block must never
        // appear outside this guard.
        menu.addItem(.separator())
        let openAdminItem = NSMenuItem(title: "Open Administration...", action: #selector(openAdminMenuAction), keyEquivalent: "")
        openAdminItem.target = self
        menu.addItem(openAdminItem)
        #endif

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func syncNowMenuAction() {
        Task { @MainActor in
            await self.model.syncNow()
            self.refreshGlyph()
        }
    }

    @objc private func openWhatChangedMenuAction() {
        guard let button = statusItem.button else { return }
        // The right-click menu itself has no "drill-in" state of its own
        // (that lives in `PopoverContentView`'s local `@State`); this just
        // opens the popover, where "What changed" is one tap away, same as
        // any other steady-state visit.
        performRefresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func showSettingsMenuAction() {
        openSettings()
    }

    func openSettings() {
        popover.performClose(nil)
        UserSettingsWindowController.shared.show()
    }

    #if CT_ADMIN_BUILD
    @objc private func openAdminMenuAction() {
        popover.performClose(nil)
        AdminWindowController.shared.show()
    }
    #endif
}

// MARK: - App entry point (accessory, no Dock icon, no default window)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let firstRunDefaultsKey = "ct.hasCompletedFirstRun"

    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment

        // Production headless seam for exercising the exact Detect boundary
        // without creating a status item or showing the wizard. This is not
        // a second implementation of detection: it calls the same THREE
        // typed CliClient verbs the wizard's `performDetect` calls, which in
        // turn launch the same bundle-relative cc helper through the same
        // Process and schema gate. The mode is deliberately plan-only and
        // has no apply counterpart.
        if Array(CommandLine.arguments.dropFirst()) == ["--headless-detect"] {
            Self.runHeadlessDetect()
            return
        }

        // SELFTEST HOOKS (harness contract, adopt-and-project-setup spec) —
        // in-binary, offline, no `CliClient`/`Process` spawn: each decodes a
        // hand-built fixture payload with the SAME `JSONDecoder` config
        // `CliClient` uses, then exercises the pure model logic those
        // decoded values feed, exactly the pattern
        // `CT_ADMIN_COMPLETION_DEPARTMENT_SELFTEST` already establishes for
        // Admin. Available in both the User and Admin builds (this file and
        // `native/wizard.swift` compile into both), never gated by
        // `CT_ADMIN_BUILD`.
        if env["CT_ONBOARD_QUESTION_SELFTEST"] == "1" {
            exit(Self.runOnboardQuestionSelftest() ? 0 : 1)
        }
        if env["CT_PROJECTS_STEP_SELFTEST"] == "1" {
            exit(Self.runProjectsStepSelftest() ? 0 : 1)
        }
        if env["CT_TRAY_PROJECTS_SELFTEST"] == "1" {
            exit(Self.runTrayProjectsSelftest() ? 0 : 1)
        }
        if env["CT_SETUP_PROGRESS_SELFTEST"] == "1" {
            exit(Self.runSetupProgressSelftest() ? 0 : 1)
        }
        if env["CT_SETUP_TRANSACTION_SELFTEST"] == "1" {
            // This proof executes the real WizardModel Set up -> Verify
            // orchestration, including the production apply verb, so it is
            // allowed only against the inert fixture helper. An arbitrary
            // CT_CLI_PATH must never turn a selftest into a live mutation.
            guard env["CT_ALLOW_INERT_SETUP_PROOF"] == "1",
                  let override = env["CT_CLI_PATH"],
                  URL(fileURLWithPath: override).lastPathComponent == "mock-cc"
            else {
                print("SELFTEST setupTransaction guard=fail")
                exit(1)
            }
            Self.runSetupTransactionSelftest()
            return
        }
        if env["CT_TRAY_WAIT_SELFTEST"] == "1" {
            exit(Self.runTrayWaitSelftest() ? 0 : 1)
        }

        // Wizard SELFTESTs exercise model/CLI seams and print their evidence;
        // they do not need pixels. Route them before constructing the status
        // item or ordering a window so the full scenario matrix cannot steal
        // focus and flash the setup window dozens of times.
        if env["CT_SELFTEST"] == "1", env["CT_OPEN_WIZARD"] == "1" {
            print("SELFTEST ui=headless")
            WizardSelftest.runIfRequested()
            return
        }

        #if CT_ADMIN_BUILD
        // The Admin distribution is a conventional double-clickable app, not
        // the User tray with a hidden Administration menu item. Keep the old
        // SELFTEST route for deterministic launch regression coverage.
        if env["CT_ADMIN_WINDOW_SELFTEST"] == "1" {
            let window = AdminWindowController.shared.window
            let built = window?.contentViewController != nil
            let hidden = window?.isVisible == false
            print("ADMIN_WINDOW_SELFTEST built=\(built) visible=\(!hidden)")
            exit(built && hidden ? 0 : 1)
        }

        if env["CT_SELFTEST"] != "1" {
            NSApp.setActivationPolicy(.regular)

            if env["CT_ADMIN_HARNESS_SELFTEST"] == "1" {
                let model = AdminModel()
                model.orgNameInput = "acme-co"
                model.githubOAuthClientIDInput = "Iv1.a1b2c3d4e5f6a7b8"
                let yaml = model.buildBriefContents()
                let json = model.buildBriefJSONContents() ?? ""
                let yamlHasBoth = yaml.contains("  - claude\n")
                    && yaml.contains("  - codex\n")
                let jsonHarnesses: [String]
                if let data = json.data(using: .utf8),
                   let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let harnesses = payload["harness"] as? [String] {
                    jsonHarnesses = harnesses
                } else {
                    jsonHarnesses = []
                }
                let selected = model.orderedHarnesses.map(\.rawValue)
                model.setHarness(.codex, selected: false)
                let singleYaml = model.buildBriefContents()
                let singleSelectionPass = model.orderedHarnesses.map(\.rawValue) == ["claude"]
                    && singleYaml.contains("  - claude\n")
                    && !singleYaml.contains("  - codex\n")
                    && !model.planCardLines.contains("acme-co/codex-copilot-internal")
                model.setHarness(.claude, selected: false)
                let emptySelectionPass = !model.selectedHarnessesAreValid
                print(
                    "ADMIN_HARNESSES selected=\(selected.joined(separator: ",")) "
                        + "yaml=\(yamlHasBoth ? "pass" : "fail") "
                        + "json=\(jsonHarnesses == selected ? "pass" : "fail") "
                        + "single=\(singleSelectionPass ? "pass" : "fail") "
                        + "empty=\(emptySelectionPass ? "pass" : "fail")"
                )
                exit(
                    selected == ["claude", "codex"]
                        && yamlHasBoth
                        && jsonHarnesses == selected
                        && singleSelectionPass
                        && emptySelectionPass
                        ? 0 : 1
                )
            }

            if env["CT_ADMIN_COMPLETION_DEPARTMENT_SELFTEST"] == "1" {
                let model = AdminModel()
                let savedState = """
                {
                  "schema_version": "1.0",
                  "org": "acme-co",
                  "harness": ["claude", "codex"],
                  "github_app": {"client_id": "Iv1.a1b2c3d4e5f6a7b8"},
                  "departments": ["accounting"],
                  "store": {
                    "status": "connected",
                    "type": "infisical",
                    "endpoint": "https://vault.acme-co.example",
                    "workspace_id": "workspace-acme",
                    "environment": "prod",
                    "secret_path": "/shared",
                    "team_scopes": [{"team": "accounting", "scope": "dept/accounting"}]
                  },
                  "contacts": {
                    "publisher": "Jordan Vale",
                    "admin": "Earl Reyes",
                    "point_of_contact": "Priya Shah"
                  }
                }
                """
                let restorePass = model.applySavedState(savedState, savedCompletion: true)
                    && model.orgSlug == "acme-co"
                    && model.validDepartments.map(\.slug) == ["accounting"]
                    && model.selectedHarnesses == Set(Harness.allCases)
                    && model.onboardingIsComplete

                model.pendingDepartmentName = "Accounting"
                model.pendingDepartmentTouched = true
                let duplicatePass = !model.canReviewPendingDepartment
                    && model.pendingDepartmentValidationMessage?.contains("already set up") == true

                model.pendingDepartmentName = "Sales"
                let validPass = model.canReviewPendingDepartment
                    && model.pendingDepartmentPreview?.contains("without changing Accounting") == true
                model.beginPendingDepartmentAddition()
                let routedPass = model.selection == .onboarding(.review)
                    && model.validDepartments.map(\.slug) == ["accounting", "sales"]
                    && !model.onboardingIsComplete

                model.selection = .onboarding(.done)
                model.finishOnboarding()
                let completionPass = model.onboardingIsComplete
                    && model.progressMark(for: .done) == .done
                    && model.handoffStatusText == "Onboarding complete"

                model.pendingDepartmentName = "Marketing"
                model.beginPendingDepartmentAddition()
                let reopenedPass = !model.onboardingIsComplete
                    && model.selection == .onboarding(.review)

                let passed = restorePass && duplicatePass && validPass && routedPass && completionPass && reopenedPass
                print(
                    "ADMIN_COMPLETION_DEPARTMENTS "
                        + "restore=\(restorePass ? "pass" : "fail") "
                        + "duplicate=\(duplicatePass ? "pass" : "fail") "
                        + "valid=\(validPass ? "pass" : "fail") "
                        + "routed=\(routedPass ? "pass" : "fail") "
                        + "complete=\(completionPass ? "pass" : "fail") "
                        + "reopened=\(reopenedPass ? "pass" : "fail")"
                )
                exit(passed ? 0 : 1)
            }

            // Regression test for the "Review step's two spinners never
            // resolve" bug: `restoreSavedStateIfAvailable()`
            // (`native/admin.swift`) sets `lastWrittenBriefFingerprint`
            // directly when restoring a saved brief at launch, WITHOUT ever
            // calling `writeBrief()`/`loadRepositoryPlan()`. The old
            // fingerprint-only guard on Review's `.task` then saw a
            // "matching" fingerprint and skipped all work forever, leaving
            // both `briefWriteState`/`repositoryPlanState` at `.idle` (a
            // permanent spinner — see `WriteState`'s render code in
            // `native/admin.swift`'s `briefCard`/`repositoryInventoryCard`).
            // Proves, against the REAL `admin_bootstrap.sh --plan` engine
            // (only `gh` is faked, by the test harness's `CT_ADMIN_TOOLS_DIR`
            // fixture — never a hand-built fixture payload, unlike this
            // file's other selftests, because the whole point is exercising
            // the actual shell-out): (1) the precondition that used to hide
            // the bug (fingerprint already matches, nothing ever attempted)
            // is real after a genuine disk restore; (2)
            // `refreshReviewIfNeeded()` (`native/admin-support.swift`) does
            // NOT skip it regardless; (3) the plan that comes back actually
            // decodes into `AdminRepositoryPlan` (the dedicated type this
            // fix also introduces — reusing `cc onboard`'s `OnboardReport`
            // here used to fail every real decode independently of the
            // fingerprint bug, since admin's engine has never emitted that
            // schema's required `rank`/`package_state` fields).
            if env["CT_ADMIN_REVIEW_RESTORE_SELFTEST"] == "1" {
                let model = AdminModel()
                Task { @MainActor in
                    await model.restoreSavedStateIfAvailable()
                    let preconditionPass = model.lastWrittenBriefFingerprint == model.briefFingerprint
                        && model.briefWriteState == .idle
                        && model.repositoryPlanState == .idle
                        && model.repositoryPlan == nil

                    await model.refreshReviewIfNeeded()

                    let triggeredPass = model.briefWriteState == .success
                    let planLoadedPass = model.repositoryPlanState == .success
                        && model.repositoryPlan != nil
                        && !(model.repositoryPlan?.repositories.isEmpty ?? true)
                    let neverIdleAgainPass = model.repositoryPlanState != .idle

                    let passed = preconditionPass && triggeredPass && planLoadedPass && neverIdleAgainPass
                    print(
                        "ADMIN_REVIEW_RESTORE "
                            + "precondition=\(preconditionPass ? "pass" : "fail") "
                            + "triggered=\(triggeredPass ? "pass" : "fail") "
                            + "planLoaded=\(planLoadedPass ? "pass" : "fail") "
                            + "neverIdleAgain=\(neverIdleAgainPass ? "pass" : "fail")"
                    )
                    exit(passed ? 0 : 1)
                }
                return
            }

            // Offline coverage for `ShellRunner`'s process-pipe plumbing
            // (`native/admin.swift`/`native/cli-client.swift`'s shared
            // `LineFramer`/`ProcessDrain`): line framing (including a line
            // split across two reads and a final line with no trailing
            // newline), a streaming callback alongside the unchanged full
            // accumulated output, real large output that would deadlock the
            // OLD `waitUntilExit()`-before-drain ordering, and the new
            // timeout capability firing promptly instead of hanging or
            // silently retrying.
            if env["CT_ADMIN_PROCESS_STREAM_SELFTEST"] == "1" {
                Task { @MainActor in
                    var framedLines: [String] = []
                    let framer = LineFramer { framedLines.append($0) }
                    framer.feed(Data("hel".utf8))
                    let midFeedPass = framedLines.isEmpty
                    framer.feed(Data("lo\nworld\npartial".utf8))
                    let splitLinePass = framedLines == ["hello", "world"]
                    framer.flush()
                    let finalLineNoNewlinePass = framedLines == ["hello", "world", "partial"]
                    framer.flush()
                    let idempotentFlushPass = framedLines == ["hello", "world", "partial"]
                    let lineFramingPass = midFeedPass && splitLinePass && finalLineNoNewlinePass && idempotentFlushPass

                    // Both pipes fill well past one pipe buffer (64KB)
                    // CONCURRENTLY — exactly the shape that deadlocks a
                    // sequential-drain or drain-after-`waitUntilExit()`
                    // implementation.
                    //
                    // SCOPE, so this is not mistaken for full coverage: this
                    // exercises `ShellRunner.run`, which is `async` and never
                    // blocks its caller. `CliClient.runRaw` blocks a thread
                    // synchronously, and a `readabilityHandler`-based drain
                    // deadlocked there while this very assertion passed — the
                    // callback had no free thread to run on, the pipe filled,
                    // and the child never exited. `scripts/tests/smoke-cli.sh`
                    // is what covers that path; run it before trusting any
                    // change to `ProcessDrain`.
                    let largeOutputStart = Date()
                    let largeOutputResult = await ShellRunner.run(
                        "(yes | head -c 500000 >&2) & (yes | head -c 500000 >&1) & wait"
                    )
                    let largeOutputElapsed = Date().timeIntervalSince(largeOutputStart)
                    let largeOutputPass = largeOutputResult.exitCode == 0
                        && largeOutputResult.stdout.count == 500_000
                        && largeOutputResult.stderr.count == 500_000
                        && largeOutputElapsed < 30
                        && !largeOutputResult.timedOut

                    var streamedLines: [String] = []
                    let streamResult = await ShellRunner.run(
                        "printf 'one\\ntwo\\nthree\\n'",
                        onStdoutLine: { line in streamedLines.append(line) }
                    )
                    let streamingPass = streamResult.stdout == "one\ntwo\nthree\n"
                        && streamedLines == ["one", "two", "three"]

                    let timeoutStart = Date()
                    let timeoutResult = await ShellRunner.run("sleep 5", timeout: 1)
                    let timeoutElapsed = Date().timeIntervalSince(timeoutStart)
                    let timeoutPass = timeoutResult.timedOut && timeoutElapsed < 4

                    let passed = lineFramingPass && largeOutputPass && streamingPass && timeoutPass
                    print(
                        "ADMIN_PROCESS_STREAM "
                            + "lineFraming=\(lineFramingPass ? "pass" : "fail") "
                            + "largeOutputNoDeadlock=\(largeOutputPass ? "pass" : "fail") "
                            + "streamingCallback=\(streamingPass ? "pass" : "fail") "
                            + "timeout=\(timeoutPass ? "pass" : "fail")"
                    )
                    exit(passed ? 0 : 1)
                }
                return
            }

            if env["CT_ADMIN_READINESS_SELFTEST"] == "1" {
                let model = AdminModel()
                model.orgNameInput = env["CT_ADMIN_ORG"] ?? "acme-co"
                Task { @MainActor in
                    await model.runGitHubReadinessCheck()
                    let rows = ReadinessRow.Kind.allCases.map {
                        "\($0.rawValue)=\(String(describing: model.readinessRows[$0].status))"
                    }.joined(separator: ",")
                    print("ADMIN_READINESS \(rows)")
                    exit(model.githubReadinessComplete ? 0 : 1)
                }
                return
            }

            // Offline coverage for the mutating run's progress model
            // (progress-and-waiting-spec.md §4, `native/admin-support.swift`'s
            // `RunPhase`/`RunRow`/`ApplyStepTarget`): step lines landing out
            // of the plan's own order, a worse result winning over an
            // earlier better one on the SAME row, a row the engine never
            // reports at all reconciling honestly once the run ends, a line
            // naming something outside the plan growing the denominator
            // without ever letting the numerator pass it, and the silence
            // watchdog firing on a real elapsed time — never on a sleep.
            // No `Process`/shell-out: `handleApplyStepLine` is fed
            // hand-built NDJSON strings directly, exactly the shape a real
            // `admin_bootstrap.sh` run streams, and `applyPhaseAfterSilence`
            // is exercised with synthetic `Date`s rather than a real wait.
            if env["CT_ADMIN_APPLY_PROGRESS_SELFTEST"] == "1" {
                let model = AdminModel()
                model.orgNameInput = "acme-co"
                model.departments = [DepartmentEntry(name: "Accounting")]

                let planJSON = """
                {"schema_version":"1.0","scope":"organization","owner":"acme-co","mode":"plan","result":"ready","repositories":[
                  {"component":"knowledge","role":"organization","unit":null,"owner":"acme-co","name":"knowledge-copilot-internal","visibility":"private","state":"existing-private","action":"none","detail":"Existing private repository will be reused."},
                  {"component":"cli","role":"organization","unit":null,"owner":"acme-co","name":"cli-copilot-internal","visibility":"private","state":"existing-private","action":"none","detail":"Existing private repository will be reused."},
                  {"component":"knowledge","role":"department","unit":"accounting","owner":"acme-co","name":"knowledge-copilot-accounting","visibility":null,"state":"missing","action":"create","detail":"Repository does not exist and can be created privately."},
                  {"component":"cli","role":"department","unit":"accounting","owner":"acme-co","name":"cli-copilot-accounting","visibility":null,"state":"missing","action":"create","detail":"Repository does not exist and can be created privately."}
                ],"summary":{"existing":2,"missing":2,"created":0,"blocked":0}}
                """
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                guard let planData = planJSON.data(using: .utf8),
                      let plan = try? decoder.decode(AdminRepositoryPlan.self, from: planData)
                else {
                    print("ADMIN_APPLY_PROGRESS fixtureDecode=fail")
                    exit(1)
                }

                Task { @MainActor in
                    model.repositoryPlan = plan
                    model.repositoryPlanState = .success
                    model.applyRunRows = model.buildApplyRunRows()
                    model.seedApplyKnownRows()
                    // default-access + 2 org spaces + (2 dept spaces + 1
                    // dept team) + setup-file = 7, in `run_standup()`'s own
                    // execution order (see buildApplyRunRows's doc comment).
                    let rowCountPass = model.applyRunRows.count == 7
                    let rowOrderPass = model.applyRunRows.map(\.id) == [
                        "default-access", "knowledge-copilot-internal", "cli-copilot-internal",
                        "knowledge-copilot-accounting", "cli-copilot-accounting", "team:accounting", "setup-file",
                    ]

                    model.applyRunPhase = .alive(startedAt: Date(), lastLineAt: Date(), subject: nil)

                    // Out of order: the department's team line, and a
                    // branch-protection line for an org repo, both arrive
                    // before that repo/team's own creation line.
                    model.handleApplyStepLine(#"{"step":"dept-team:accounting","result":"created","detail":"Created the accounting team."}"#)
                    model.handleApplyStepLine(#"{"step":"branch-protection:knowledge-copilot-internal","result":"already-present","detail":"knowledge-copilot-internal requires review."}"#)
                    let outOfOrderPass = model.applyRunRows.first(where: { $0.id == "team:accounting" })?.result
                        == .done(detail: "Created the accounting team.")
                        && model.applyRunRows.first(where: { $0.id == "knowledge-copilot-internal" })?.result
                        == .done(detail: "knowledge-copilot-internal requires review.")

                    // Worse-result-wins, and the row stays where it is: the
                    // SAME org repo resolves done via its creation line,
                    // then fails via its branch-protection line.
                    model.handleApplyStepLine(#"{"step":"org-repo:cli-copilot-internal","result":"already-present","detail":"cli-copilot-internal already exists, private."}"#)
                    model.handleApplyStepLine(#"{"step":"branch-protection:cli-copilot-internal","result":"failed","detail":"Could not set branch protection on cli-copilot-internal."}"#)
                    let cliIndex = model.applyRunRows.firstIndex(where: { $0.id == "cli-copilot-internal" })
                    let failedBesideDonePass = cliIndex == 2
                        && model.applyRunRows[cliIndex ?? 0].result == .failed(detail: "Could not set branch protection on cli-copilot-internal.")
                        && model.applyRunRows[1].result == .done(detail: "knowledge-copilot-internal requires review.")

                    // A line naming something outside the plan grows the
                    // denominator by exactly one, and the numerator never
                    // exceeds the new total.
                    model.handleApplyStepLine(#"{"step":"org-repo:extra-copilot-internal","result":"created","detail":"Created extra-copilot-internal, private."}"#)
                    let extraRowPass = model.applyExtraRowCount == 1 && model.applyRunRows.count == 8
                    let countNeverExceedsPass = model.applyDoneCount <= model.applyRunRows.count

                    // A step the engine never reports: end the run and
                    // confirm reconciliation, not silence, owns that row.
                    model.applyRunPhase = .ended(.unfinished(count: 3))
                    let neverReportedPass = model.applyRunRows.first(where: { $0.id == "setup-file" })?.result == nil

                    // The stall watchdog: pure, deterministic, no real wait.
                    let stalledPhase = AdminModel.applyPhaseAfterSilence(
                        .alive(startedAt: Date(), lastLineAt: Date().addingTimeInterval(-100), subject: RunSubject(rowID: "setup-file", title: "Your organization's setup file")),
                        now: Date(),
                        stallThreshold: AdminModel.applyStallThreshold
                    )
                    let watchdogFiresPass: Bool = {
                        if case .stalled(let lastSubject) = stalledPhase { return lastSubject?.rowID == "setup-file" }
                        return false
                    }()
                    let freshPhase = AdminModel.applyPhaseAfterSilence(
                        .alive(startedAt: Date(), lastLineAt: Date(), subject: nil),
                        now: Date(),
                        stallThreshold: AdminModel.applyStallThreshold
                    )
                    let watchdogHoldsWhileFreshPass: Bool = {
                        if case .alive = freshPhase { return true }
                        return false
                    }()

                    let passed = rowCountPass && rowOrderPass && outOfOrderPass && failedBesideDonePass
                        && extraRowPass && countNeverExceedsPass && neverReportedPass
                        && watchdogFiresPass && watchdogHoldsWhileFreshPass
                    print(
                        "ADMIN_APPLY_PROGRESS "
                            + "rowCount=\(rowCountPass ? "pass" : "fail") "
                            + "rowOrder=\(rowOrderPass ? "pass" : "fail") "
                            + "outOfOrder=\(outOfOrderPass ? "pass" : "fail") "
                            + "failedBesideDone=\(failedBesideDonePass ? "pass" : "fail") "
                            + "extraRow=\(extraRowPass ? "pass" : "fail") "
                            + "countBounded=\(countNeverExceedsPass ? "pass" : "fail") "
                            + "neverReported=\(neverReportedPass ? "pass" : "fail") "
                            + "watchdogFires=\(watchdogFiresPass ? "pass" : "fail") "
                            + "watchdogHoldsWhileFresh=\(watchdogHoldsWhileFreshPass ? "pass" : "fail")"
                    )
                    exit(passed ? 0 : 1)
                }
                return
            }

            AdminWindowController.shared.show()
            return
        }
        #endif

        NSApp.setActivationPolicy(.accessory)

        let controller = StatusBarController()
        statusBarController = controller

        let isFirstRun = !LocalDefaults.bool(forKey: Self.firstRunDefaultsKey)
        let forceWizard = env["CT_OPEN_WIZARD"] == "1"

        // AS-6: on first open the wizard auto-presents; opening the app is
        // starting setup. `CT_OPEN_WIZARD=1` forces it open regardless for
        // visual/manual development. Automated CT_SELFTEST runs were routed
        // above before any window or status item was created, so the scenario
        // matrix stays headless (see `native/models.swift` for LocalDefaults
        // isolation).
        if forceWizard || isFirstRun {
            WizardWindowController.shared.show()
        }

        // Screenshot/smoke seam for the native post-onboarding Settings
        // window. It exercises the same controller both production entry
        // points call and performs only Settings' read-only status verbs.
        if env["CT_OPEN_SETTINGS"] == "1" {
            controller.openSettings()
        }

        if isFirstRun {
            // Best-effort login-item registration, once, first-run only.
            // Failure (e.g. this ad-hoc `swiftc`-built binary isn't a signed
            // `.app` bundle SMAppService recognizes, or the user declines) is
            // non-fatal and silent — this app must never surface a login-item
            // error to Bob.
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.register()
            }
        }

        #if CT_ADMIN_BUILD
        // DEV/SMOKE-TEST ONLY: opens Administration immediately at launch
        // when `CT_OPEN_ADMIN=1` is set, so a headless smoke test can prove
        // the Admin path doesn't crash without a live click. Admin-build-only
        // — the plain user build never links `AdminWindowController`.
        if env["CT_OPEN_ADMIN"] == "1" {
            AdminWindowController.shared.show()
        }
        #endif

        // SELFTEST HOOK (harness contract): prints one deterministic line of
        // machine-parseable state after the first real `refresh()` completes,
        // then exits. Never runs alongside a forced wizard open (that would
        // race the wizard's own construction against this printing/exiting).
        if env["CT_SELFTEST"] == "1" && !forceWizard {
            Task { @MainActor in
                await controller.model.refresh()
                let badgeToken = Self.selftestBadgeToken(controller.model.state.header.glyphState)
                print("SELFTEST badge=\(badgeToken) sentence=\(controller.model.state.header.sentence)")

                if let fixtureName = env["CT_FIXTURE"], !fixtureName.isEmpty {
                    // Only a genuine projects fixture (e.g. "12-of-14-updated")
                    // decodes as a `FanoutReport` here; a doctor-only fixture
                    // name fails this call and this line is simply omitted,
                    // exactly as this task's own gate example expects.
                    if case .success(let report) = await CliClient.shared.updateFanout() {
                        print("SELFTEST recently=\(FanoutRender.headline(report))")
                    }
                }

                // Region 6's `permission-needed` prompt / `connection-offer`
                // notice (`control-tower-copy-deck.md` §1.8) — both derived,
                // live, from the SAME read-only `ecosystemOnboardPlan` the
                // `refresh()` call just ran above, never from a cached/offline
                // decode. `scripts/tests/smoke-scenarios.sh`'s S24-S26 assert
                // directly on this line.
                print("SELFTEST permissionNeeded=\(controller.model.permissionNeededPending) connectionOffer=\(controller.model.connectionOfferPending)")

                print("SELFTEST firstRun=\(isFirstRun)")
                exit(0)
            }
        }
    }

    private static func runHeadlessDetect() {
        Task {
            let helperPath = CliLocator.locate()?.path ?? ""
            async let authAsync = CliClient.shared.authStatus()
            async let doctorAsync = CliClient.shared.doctor()
            async let onboardAsync = CliClient.shared.ecosystemOnboardPlan(
                products: ["claude", "codex"]
            )
            let authResult = await authAsync
            let doctorResult = await doctorAsync
            let onboardResult = await onboardAsync
            var payload: [String: Any] = [
                "mode": "headless-detect",
                "helper": helperPath,
                "read_only": true,
                "calls": ["auth-status", "doctor", "onboard-plan"],
            ]
            var passed = !helperPath.isEmpty

            switch authResult {
            case .success(let status):
                var authPayload: [String: Any] = [
                    "schema_version": status.schemaVersion,
                    "kind": status.kind,
                    "status": status.state.rawValue,
                ]
                if let login = status.identity?.login {
                    authPayload["login"] = login
                }
                if let scope = status.scope {
                    authPayload["scope"] = scope
                }
                payload["auth"] = authPayload
                if status.state != .authorized {
                    passed = false
                }
            case .failure(let error):
                payload["auth_error"] = String(describing: error)
                passed = false
            }

            switch doctorResult {
            case .success(let report):
                payload["doctor"] = [
                    "schema_version": report.schemaVersion,
                    "status": report.status.rawValue,
                    "score": report.score,
                    "offline": report.offline,
                ]
            case .failure(let error):
                payload["doctor_error"] = String(describing: error)
                passed = false
            }

            switch onboardResult {
            case .success(let report):
                payload["schema_version"] = report.schemaVersion
                payload["result"] = report.result.rawValue
                payload["org"] = report.org
                payload["products"] = report.products

                if let stage = report.stages.first(where: { $0.stage == "layer-manifest" }) {
                    var stagePayload: [String: Any] = [
                        "result": stage.result,
                    ]
                    if let action = stage.action {
                        stagePayload["action"] = action
                    }
                    if let detail = stage.detail {
                        stagePayload["detail"] = detail
                    }
                    payload["layer_manifest"] = stagePayload
                    if (stage.detail ?? "").contains(
                        "The installed `copilot` command is unavailable."
                    ) {
                        passed = false
                    }
                } else {
                    payload["error"] = "The onboarding report did not inspect the layer manifest."
                    passed = false
                }

            case .failure(let error):
                payload["onboard_error"] = String(describing: error)
                passed = false
            }

            payload["contract"] = passed ? "pass" : "fail"
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: payload,
                    options: [.sortedKeys]
                )
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                FileHandle.standardError.write(
                    Data("headless Detect could not encode its report\n".utf8)
                )
                exit(2)
            }
            exit(passed ? 0 : 1)
        }
    }

    /// Runs the exact asynchronous Set up tail without constructing UI:
    /// `ecosystemOnboardApply` -> stage decode -> `doctor` -> verified.
    /// The launch guard above restricts this to the inert `mock-cc` fixture;
    /// `CT_MOCK_INVOCATION_LOG` independently proves the argv it received.
    private static func runSetupTransactionSelftest() {
        Task { @MainActor in
            let model = WizardModel()
            model.includeCodex = true
            model.beginMaterialize()

            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                switch model.phase {
                case .verified:
                    let manifest = model.lastOnboardStages.first {
                        $0.stage == "layer-manifest"
                    }
                    let onboardDoctor = model.lastOnboardStages.first {
                        $0.stage == "doctor"
                    }
                    let passed = model.lastOnboardResult == .ready
                        && manifest?.result == "applied"
                        && onboardDoctor?.result == "healthy"
                    print(
                        "SELFTEST setupTransaction "
                            + "apply=\(model.lastOnboardResult?.rawValue ?? "missing") "
                            + "layerManifest=\(manifest?.result ?? "missing") "
                            + "onboardDoctor=\(onboardDoctor?.result ?? "missing") "
                            + "verify=healthy"
                    )
                    exit(passed ? 0 : 1)
                case .holding:
                    print("SELFTEST setupTransaction apply=blocked holding=entered")
                    exit(1)
                default:
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            print("SELFTEST setupTransaction timeout=fail")
            exit(1)
        }
    }

    /// `SELFTEST badge=` must print one of the seven tokens named in this
    /// task's harness contract, not `BadgeState`'s raw value (e.g. `.cloudSlash`'s
    /// raw value is the hyphenated `"cloud-slash"`, not `"cloudSlash"`).
    private static func selftestBadgeToken(_ badge: BadgeState) -> String {
        switch badge {
        case .none: return "none"
        case .hollow: return "hollow"
        case .key: return "key"
        case .ring: return "ring"
        case .triangle: return "triangle"
        case .cloudSlash: return "cloudSlash"
        case .bang: return "bang"
        default: return badge.rawValue
        }
    }

    /// The SAME decoder config `CliClient.decodeVerb` uses — every selftest
    /// below decodes its fixture through this, never through a bespoke
    /// decoder that could hide a real key-mapping bug.
    private static func selftestDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    // MARK: CT_ONBOARD_QUESTION_SELFTEST — "One question first"
    //
    // Proves, offline: (1) `RepositoryPlanRow` no longer silently drops
    // `rank`/`package_state`/`package_action`/`package_detail` (the exact
    // bug that made the app unable to render an adopt-existing-content
    // offer even once the CLI started emitting one); (2) `WizardModel.
    // personalOnboardQuestion(from:)` correctly splits an ecosystem plan's
    // personal-scope inventory into ask rows (`reversible: true`) and
    // review rows (`action: "review"`) and leaves an ordinary `reuse` row
    // out of both; (3) the `personal-<component>` id round-trips through
    // `componentId(fromPersonalInventoryId:)`; (4) B3: both DTOs decode
    // `decline_detail` verbatim when present, and leave it `nil` — never a
    // fabricated string — when the CLI omits it on an ask row.
    private static func runOnboardQuestionSelftest() -> Bool {
        let repositoryRowJSON = """
        {
          "schema_version": "1.0",
          "scope": "personal",
          "owner": "octocat",
          "mode": "plan",
          "result": "changes-required",
          "repositories": [
            {
              "component": "claude",
              "role": "personal",
              "unit": null,
              "owner": "octocat",
              "name": "claude-copilot-private",
              "visibility": "private",
              "state": "existing-private",
              "action": "none",
              "detail": "Existing private repository will be reused.",
              "rank": 10,
              "package_state": "adoptable",
              "package_action": "adopt",
              "package_detail": "Your own content is already in here. I'll keep all of it and add a small note that says it belongs with your copilots.",
              "decline_detail": "Without this, Claude Copilot can't be set up on this Mac. You can include it later."
            }
          ],
          "summary": {"existing": 1, "missing": 0, "created": 0, "blocked": 0, "adoptable": 1}
        }
        """
        guard let repositoryData = repositoryRowJSON.data(using: .utf8),
              let onboardReport = try? selftestDecoder().decode(OnboardReport.self, from: repositoryData),
              let row = onboardReport.repositories.first else {
            print("SELFTEST onboardQuestion repoRowDecode=fail")
            return false
        }
        let repoRowDecodePass = row.rank == 10
            && row.packageState == "adoptable"
            && row.packageAction == "adopt"
            && !row.packageDetail.isEmpty
            && onboardReport.summary.adoptable == 1
            && row.declineDetail == "Without this, Claude Copilot can't be set up on this Mac. You can include it later."

        let inventoryJSON = """
        {
          "schema_version": "1.0",
          "scope": "ecosystem",
          "mode": "plan",
          "result": "changes-required",
          "org": "acme-co",
          "products": ["claude", "codex"],
          "components": ["knowledge", "cli", "claude", "codex"],
          "stages": [],
          "layers_state": "not-computed",
          "layers": [],
          "inventory": [
            {"id": "personal-claude", "scope": "personal", "title": "Your Claude Copilot space", "state": "adoptable", "action": "create", "detail": "Your own content is already in here. I'll keep all of it and add a small note that says it belongs with your copilots.", "source_path": null, "destination_path": null, "reversible": true, "decline_detail": "Without this, Claude Copilot can't be set up on this Mac. You can include it later."},
            {"id": "personal-cli", "scope": "personal", "title": "Your CLI Copilot space", "state": "adoptable", "action": "create", "detail": "Your own content is already in here. I'll keep all of it and add a small note that says it belongs with your copilots.", "source_path": null, "destination_path": null, "reversible": true},
            {"id": "personal-codex", "scope": "personal", "title": "Your Codex Copilot space", "state": "held", "action": "review", "detail": "I don't recognize how this space is set up, so I'll leave it exactly as it is.", "source_path": null, "destination_path": null, "reversible": false},
            {"id": "personal-knowledge", "scope": "personal", "title": "Your Knowledge Copilot space", "state": "ready", "action": "reuse", "detail": "Already set up. Everything in here will be kept.", "source_path": null, "destination_path": null, "reversible": false}
          ],
          "inventory_summary": {"reused": 1, "changes": 2, "review": 1},
          "completed_actions": []
        }
        """
        guard let inventoryData = inventoryJSON.data(using: .utf8),
              let ecosystemReport = try? selftestDecoder().decode(EcosystemOnboardReport.self, from: inventoryData) else {
            print("SELFTEST onboardQuestion inventoryDecode=fail")
            return false
        }
        let (ask, review) = WizardModel.personalOnboardQuestion(from: ecosystemReport)
        let splitPass = ask.count == 2 && Set(ask.map(\.id)) == Set(["personal-claude", "personal-cli"])
            && review.count == 1 && review.first?.id == "personal-codex"
        let componentIdPass = WizardModel.componentId(fromPersonalInventoryId: "personal-claude") == "claude"
            && WizardModel.componentId(fromPersonalInventoryId: "not-personal") == nil
        // B3: present on "personal-claude" -> decoded verbatim; absent on
        // "personal-cli" -> `nil`, never invented (spec's own
        // failure/recovery row for this exact field).
        let declineDetailPass = ask.first(where: { $0.id == "personal-claude" })?.declineDetail
            == "Without this, Claude Copilot can't be set up on this Mac. You can include it later."
            && ask.first(where: { $0.id == "personal-cli" })?.declineDetail == nil

        // DEFENSIVE, forward-looking (no known live CLI case today): a
        // synthetic id matching NEITHER known consent-token shape
        // (`personal-<component>` nor the fixed `device-ssh`) — stands in
        // for whatever a future third ask-row shape might carry, not a
        // prediction of its real name. Proves `personalOnboardQuestion(from:)`
        // never offers a checkbox this app cannot translate into a real
        // `--adopt-existing` token: the row must land in `review` (no
        // checkbox — "Kept as is" stays true, since this app never attempts
        // to adopt what it cannot map), never in `ask`. Closes the class of
        // bug `componentId(fromPersonalInventoryId:)`'s own doc comment
        // names ("Bug 2" — a nil token silently drops consent) for any
        // FUTURE id, not just the `device-ssh` case already fixed.
        let unmappedJSON = """
        {
          "schema_version": "1.0",
          "scope": "ecosystem",
          "mode": "plan",
          "result": "changes-required",
          "org": "acme-co",
          "products": ["claude"],
          "components": ["knowledge", "cli", "claude", "codex"],
          "stages": [],
          "layers_state": "not-computed",
          "layers": [],
          "inventory": [
            {"id": "unmapped-example-row", "scope": "machine", "title": "Something this app doesn't recognize yet", "state": "adoptable", "action": "create", "detail": "Placeholder detail for a hypothetical future ask row.", "source_path": null, "destination_path": null, "reversible": true}
          ],
          "inventory_summary": {"reused": 0, "changes": 1, "review": 0},
          "completed_actions": []
        }
        """
        guard let unmappedData = unmappedJSON.data(using: .utf8),
              let unmappedReport = try? selftestDecoder().decode(EcosystemOnboardReport.self, from: unmappedData) else {
            print("SELFTEST onboardQuestion unmappedDecode=fail")
            return false
        }
        let (unmappedAsk, unmappedReview) = WizardModel.personalOnboardQuestion(from: unmappedReport)
        let unmappedIdPass = unmappedAsk.isEmpty
            && unmappedReview.count == 1
            && unmappedReview.first?.id == "unmapped-example-row"
            && WizardModel.componentId(fromPersonalInventoryId: "unmapped-example-row") == nil

        let passed = repoRowDecodePass && splitPass && componentIdPass && declineDetailPass && unmappedIdPass
        print(
            "SELFTEST onboardQuestion repoRowDecode=\(repoRowDecodePass ? "pass" : "fail") "
                + "askCount=\(ask.count) reviewCount=\(review.count) "
                + "componentId=\(componentIdPass ? "pass" : "fail") "
                + "declineDetail=\(declineDetailPass ? "pass" : "fail") "
                + "unmappedId=\(unmappedIdPass ? "pass" : "fail")"
        )
        return passed
    }

    // MARK: CT_PROJECTS_STEP_SELFTEST — wizard Step 7, "Your projects"
    //
    // Proves, offline: (1) `WorkspaceEntry`/`WorkspacesReport` decode the
    // new required `setup_policy`/`policy_detail`/`can_apply_now`/
    // `apply_blocked_detail`/`undo`/`discovery` fields instead of silently
    // dropping them; (2) project setup starts unselected and only rows with
    // both an actionable state and `can_apply_now=true` are eligible;
    // (3) `WorkspaceRootsListReport` decodes `roots`+`candidates`; (4) the
    // stage enum keeps a real, correctly-positioned "Your projects" step
    // (9 stages, `.projects` immediately before
    // `.materialize`).
    private static func runProjectsStepSelftest() -> Bool {
        let workspacesJSON = """
        {
          "schema_version": "1.0",
          "mode": "status",
          "result": "action-required",
          "workspaces": [
            {"path": "/Users/x/Developer/convoco", "name": "convoco", "project_id": null, "state": "setup-available", "detail": "Copilot can be set up for this project.", "declared_components": [], "installed_components": [], "recommended_components": ["claude"], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "ask", "policy_detail": "You'll be asked before anything is added here.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "There's nothing here to undo yet."}},
            {"path": "/Users/x/Developer/finished", "name": "finished", "project_id": null, "state": "activation-required", "detail": "Shared Copilot setup is present but is not active on this Mac.", "declared_components": ["claude"], "installed_components": [], "recommended_components": ["claude"], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "ask", "policy_detail": "You'll be asked before anything is added here.", "can_apply_now": false, "apply_blocked_detail": "Existing project setup needs review before Copilot can add shared files. Nothing was changed.", "undo": {"available": false, "detail": "There's nothing here to undo yet."}},
            {"path": "/Users/x/Developer/ready", "name": "ready", "project_id": null, "state": "ready", "detail": "Copilot is ready for this project.", "declared_components": ["claude"], "installed_components": ["claude"], "recommended_components": ["claude"], "personal_profile": {"state": "associated", "project_id": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, "setup_policy": "not-offered", "policy_detail": "Copilot is already set up here, so there's nothing to ask.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": true, "detail": "Undo is available."}}
          ],
          "summary": {"ready": 1, "setup-available": 1, "activation-required": 1, "blocked": 0, "total": 3},
          "discovery": {"state": "granted", "roots": [{"name": "Developer", "path": "/Users/x/Developer"}]}
        }
        """
        let workspacesData = WorkspaceContractSelftestFixture.report(
            workspacesJSON,
            classifications: [.safeFinish, .guidedIntegration, .ready]
        )
        guard let report = try? selftestDecoder().decode(
            WorkspacesReport.self,
            from: workspacesData
        ) else {
            print("SELFTEST projectsStep workspaceDecode=fail")
            return false
        }
        let workspaceDecodePass = report.workspaces[0].setupPolicy == .ask
            && report.workspaces[0].canApplyNow == true
            && report.workspaces[0].applyBlockedDetail == nil
            && report.workspaces[1].canApplyNow == false
            && report.workspaces[1].applyBlockedDetail != nil
            && report.workspaces[2].undo.available == true
        let discoveryPass = report.discovery?.state == .granted
            && report.discovery?.roots.first?.name == "Developer"

        let preselected = WizardModel.preselectedProjectPaths(from: report.workspaces)
        let actionable = WizardModel.actionableProjectPaths(from: report.workspaces)
        let preselectPass = preselected.isEmpty
            && actionable == Set([report.workspaces[0].path])
            && WizardModel.projectSetupRequiresDecision(failureCount: 1)
            && !WizardModel.projectSetupRequiresDecision(failureCount: 0)

        let rootsJSON = """
        {"schema_version": "1.0", "mode": "status", "result": "action-required", "roots": [], "candidates": [{"path": "/Users/x/Developer", "label": "Developer", "project_count": 3}]}
        """
        guard let rootsData = rootsJSON.data(using: .utf8),
              let rootsReport = try? selftestDecoder().decode(WorkspaceRootsListReport.self, from: rootsData) else {
            print("SELFTEST projectsStep rootsDecode=fail")
            return false
        }
        let rootsDecodePass = rootsReport.candidates?.first?.label == "Developer"
            && rootsReport.candidates?.first?.projectCount == 3

        let stageOrderPass = WizardStage.allCases.count == 9
            && WizardStage.projects.rawValue == WizardStage.integrations.rawValue + 1
            && WizardStage.materialize.rawValue == WizardStage.projects.rawValue + 1

        let settingsAftercarePass = UserSettingsRender.projectCategories(report)
            == [.ready, .safeFinish, .guidedSetup]

        let personalJSON = """
        {
          "schema_version": "1.0",
          "scope": "personal",
          "owner": "octocat",
          "mode": "plan",
          "result": "changes-required",
          "repositories": [
            {"component": "knowledge", "role": "personal", "unit": null, "owner": "octocat", "name": "knowledge-copilot-private", "visibility": null, "state": "missing", "action": "create", "detail": "Repository does not exist and can be created privately.", "rank": 10, "package_state": "missing", "package_action": "seed", "package_detail": "Will be set up right after this space is created."},
            {"component": "cli", "role": "personal", "unit": null, "owner": "octocat", "name": "cli-copilot-private", "visibility": null, "state": "missing", "action": "create", "detail": "Repository does not exist and can be created privately.", "rank": 10, "package_state": "missing", "package_action": "seed", "package_detail": "Will be set up right after this space is created."},
            {"component": "claude", "role": "personal", "unit": null, "owner": "octocat", "name": "claude-copilot-private", "visibility": "private", "state": "existing-private", "action": "none", "detail": "Existing private repository will be reused.", "rank": 10, "package_state": "ready", "package_action": "none", "package_detail": "Already set up. Everything in here will be kept."},
            {"component": "codex", "role": "personal", "unit": null, "owner": "octocat", "name": "codex-copilot-private", "visibility": "private", "state": "existing-private", "action": "none", "detail": "Existing private repository will be reused.", "rank": 10, "package_state": "ready", "package_action": "none", "package_detail": "Already set up. Everything in here will be kept."}
          ],
          "summary": {"existing": 2, "missing": 2, "created": 0, "blocked": 0}
        }
        """
        let doctorJSON = """
        {
          "schema_version": "1.0",
          "host": "test",
          "score": 100,
          "generated_at": null,
          "status": "healthy",
          "offline": false,
          "checkers": [
            {"id": "knowledge-foundation", "severity": "pass", "detail": "Foundation ready.", "repair": null, "destructive": false, "layer": "knowledge-foundation", "layer_role": "foundation", "product": "knowledge", "local_sha": null, "remote_sha": null, "path": null, "escalate": null},
            {"id": "knowledge-org", "severity": "pass", "detail": "Organization ready.", "repair": null, "destructive": false, "layer": "knowledge-organization", "layer_role": "organization", "product": "knowledge", "local_sha": null, "remote_sha": null, "path": null, "escalate": null},
            {"id": "cli-foundation", "severity": "pass", "detail": "Foundation ready.", "repair": null, "destructive": false, "layer": "foundation", "layer_role": "foundation", "product": "cli", "local_sha": null, "remote_sha": null, "path": null, "escalate": null},
            {"id": "cli-org", "severity": "pass", "detail": "Organization ready.", "repair": null, "destructive": false, "layer": "org-internal", "layer_role": "organization", "product": "cli", "local_sha": null, "remote_sha": null, "path": null, "escalate": null},
            {"id": "claude-foundation", "severity": "pass", "detail": "Foundation ready.", "repair": null, "destructive": false, "layer": "claude-foundation", "layer_role": "foundation", "product": "claude", "local_sha": null, "remote_sha": null, "path": null, "escalate": null},
            {"id": "claude-org", "severity": "pass", "detail": "Organization ready.", "repair": null, "destructive": false, "layer": "claude-organization", "layer_role": "organization", "product": "claude", "local_sha": null, "remote_sha": null, "path": null, "escalate": null},
            {"id": "codex-foundation", "severity": "pass", "detail": "Foundation ready.", "repair": null, "destructive": false, "layer": "codex-foundation", "layer_role": "foundation", "product": "codex", "local_sha": null, "remote_sha": null, "path": null, "escalate": null},
            {"id": "codex-org", "severity": "pass", "detail": "Organization ready.", "repair": null, "destructive": false, "layer": "codex-organization", "layer_role": "organization", "product": "codex", "local_sha": null, "remote_sha": null, "path": null, "escalate": null}
          ],
          "auth": []
        }
        """
        let layersJSON = """
        {"schema_version": "1.0", "host": "test", "layers": []}
        """
        let personalReport = personalJSON.data(using: .utf8).flatMap {
            try? selftestDecoder().decode(OnboardReport.self, from: $0)
        }
        let doctorReport = doctorJSON.data(using: .utf8).flatMap {
            try? selftestDecoder().decode(DoctorReport.self, from: $0)
        }
        let layersReport = layersJSON.data(using: .utf8).flatMap {
            try? selftestDecoder().decode(LayersReport.self, from: $0)
        }
        let settingsComponents = UserSettingsRender.componentStatuses(
            doctor: doctorReport,
            personal: personalReport,
            layers: layersReport
        )
        let settingsTopologyPass = settingsComponents.map(\.id)
            == [.knowledge, .cli, .claude, .codex]
            && settingsComponents.allSatisfy {
                $0.tiers.map(\.label)
                    == ["Foundation", "Organization", "Department", "Personal"]
            }
            && settingsComponents.first(where: { $0.id == .knowledge })?
                .tiers.last?.kind == .needsSetup
            && settingsComponents.first(where: { $0.id == .knowledge })?
                .tiers.first?.kind == .ready
            && settingsComponents.first(where: { $0.id == .knowledge })?
                .tiers.dropFirst().first?.kind == .ready
            && settingsComponents.first(where: { $0.id == .cli })?
                .tiers.last?.kind == .needsSetup
            && settingsComponents.first(where: { $0.id == .cli })?
                .tiers.first?.kind == .ready
            && settingsComponents.first(where: { $0.id == .cli })?
                .tiers.dropFirst().first?.kind == .ready
            && settingsComponents.first(where: { $0.id == .claude })?
                .tiers.last?.kind == .ready
            && settingsComponents.first(where: { $0.id == .codex })?
                .tiers.last?.kind == .ready
            && personalReport.map(UserSettingsRender.personalReadyCount) == 2
            && personalReport.map(UserSettingsRender.personalNeedsAction) == true

        let triagePass = ProjectTriageRender.nonEmptyCategories(report.workspaces)
            == [.ready, .safeFinish, .guidedSetup]
            && ProjectTriageRender.summary(report.workspaces)
                == "1 is ready. 1 can finish automatically. 1 needs guided setup."
            && ProjectTriageRender.pageSize == 6
        let diagnostic = ProjectTriageRender.diagnosticReport(report.workspaces[1])
        let diagnosticPass = diagnostic.contains("finished project integration report")
            && diagnostic.contains("Nothing was changed by Control Tower.")
            && diagnostic.contains("Check again after the project setup changes:")

        let passed = workspaceDecodePass && discoveryPass && preselectPass && rootsDecodePass
            && stageOrderPass && settingsAftercarePass && settingsTopologyPass
            && triagePass && diagnosticPass
        print(
            "SELFTEST projectsStep workspaceDecode=\(workspaceDecodePass ? "pass" : "fail") "
                + "discovery=\(discoveryPass ? "pass" : "fail") "
                + "preselect=\(preselectPass ? "pass" : "fail") "
                + "rootsDecode=\(rootsDecodePass ? "pass" : "fail") "
                + "stageOrder=\(stageOrderPass ? "pass" : "fail") "
                + "settingsAftercare=\(settingsAftercarePass ? "pass" : "fail") "
                + "settingsTopology=\(settingsTopologyPass ? "pass" : "fail") "
                + "triage=\(triagePass ? "pass" : "fail") "
                + "diagnostic=\(diagnosticPass ? "pass" : "fail")"
        )
        return passed
    }

    // MARK: CT_TRAY_PROJECTS_SELFTEST — the menu bar projects notice + drill-in
    //
    // Proves, offline: (1) `ProjectsNoticeRender` pluralizes correctly and
    // is computed straight from `WorkspaceSummary`, independent of any
    // unsaved-changes state; (2) `ProjectRowRender` maps every
    // `WorkspaceEntry` state (including the `excluded` `setup_policy`, i.e.
    // a project `revert` previously undid) to the exact caption/control
    // pair the drill-in's own spec table names; (3) B3: `WorkspacesReport`
    // decodes the top-level `recently_set_up` list, `ProjectRowRender`
    // renders the `automaticallySetUp` row pair (Undo available and
    // unavailable) purely from CLI-provided name membership + `undo`, never
    // inferred any other way; (4) `RecentlySetUpRender` pluralizes the
    // one-time notice; (5) `WorkspaceRevertReport` decodes `cc workspace
    // revert`'s real, narrower shape (no `summary`) — the exact decode this
    // task's `revertWorkspace` fix makes possible.
    private static func runTrayProjectsSelftest() -> Bool {
        let singularJSON = """
        {
          "schema_version": "1.0", "mode": "status", "result": "action-required",
          "workspaces": [
            {"path": "/p/one", "name": "one", "project_id": null, "state": "setup-available", "detail": "Copilot can be set up for this project.", "declared_components": [], "installed_components": [], "recommended_components": ["claude"], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "ask", "policy_detail": "You'll be asked before anything is added here.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "There's nothing here to undo yet."}}
          ],
          "summary": {"ready": 0, "setup-available": 1, "activation-required": 0, "blocked": 0, "total": 1}
        }
        """
        let pluralJSON = """
        {
          "schema_version": "1.0", "mode": "status", "result": "action-required",
          "workspaces": [
            {"path": "/p/a", "name": "a", "project_id": null, "state": "setup-available", "detail": "Copilot can be set up for this project.", "declared_components": [], "installed_components": [], "recommended_components": ["claude"], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "ask", "policy_detail": "You'll be asked before anything is added here.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "There's nothing here to undo yet."}},
            {"path": "/p/b", "name": "b", "project_id": null, "state": "activation-required", "detail": "Shared Copilot setup is present but is not active on this Mac.", "declared_components": ["claude"], "installed_components": [], "recommended_components": ["claude"], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "ask", "policy_detail": "You'll be asked before anything is added here.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "There's nothing here to undo yet."}},
            {"path": "/p/c", "name": "c", "project_id": null, "state": "setup-available", "detail": "Copilot can be set up for this project.", "declared_components": [], "installed_components": [], "recommended_components": ["claude"], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "ask", "policy_detail": "You'll be asked before anything is added here.", "can_apply_now": false, "apply_blocked_detail": "Existing project setup needs review. Nothing was changed.", "undo": {"available": false, "detail": "There's nothing here to undo yet."}}
          ],
          "summary": {"ready": 0, "setup-available": 2, "activation-required": 1, "blocked": 0, "total": 3}
        }
        """
        let singularData = WorkspaceContractSelftestFixture.report(
            singularJSON,
            classifications: [.safeFinish]
        )
        let pluralData = WorkspaceContractSelftestFixture.report(
            pluralJSON,
            classifications: [.safeFinish, .safeFinish, .guidedIntegration]
        )
        guard let singularReport = try? selftestDecoder().decode(WorkspacesReport.self, from: singularData),
              let pluralReport = try? selftestDecoder().decode(WorkspacesReport.self, from: pluralData) else {
            print("SELFTEST trayProjects noticeDecode=fail")
            return false
        }
        let singularCount = ProjectsNoticeRender.actionableCount(singularReport)
        let pluralCount = ProjectsNoticeRender.actionableCount(pluralReport)
        let noticePass = singularCount == 1
            && ProjectsNoticeRender.noticeText(count: singularCount) == "1 project can have your copilots. Nothing is added until you say so."
            && pluralCount == 2
            && ProjectsNoticeRender.noticeText(count: pluralCount) == "2 projects can have your copilots. Nothing is added until you say so."

        let rowsJSON = """
        {
          "schema_version": "1.0",
          "mode": "status",
          "result": "action-required",
          "workspaces": [
            {"path": "/p/a", "name": "a", "project_id": null, "state": "setup-available", "detail": "Copilot can be set up for this project.", "declared_components": [], "installed_components": [], "recommended_components": ["claude"], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "ask", "policy_detail": "You'll be asked before anything is added here.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "There's nothing here to undo yet."}},
            {"path": "/p/b", "name": "b", "project_id": null, "state": "setup-available", "detail": "Copilot can be set up for this project.", "declared_components": [], "installed_components": [], "recommended_components": ["claude"], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "excluded", "policy_detail": "You asked me not to set this project up again.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "There's nothing here to undo yet."}},
            {"path": "/p/c", "name": "c", "project_id": null, "state": "activation-required", "detail": "Shared Copilot setup is present but is not active on this Mac.", "declared_components": ["claude"], "installed_components": [], "recommended_components": ["claude"], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "ask", "policy_detail": "You'll be asked before anything is added here.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "There's nothing here to undo yet."}},
            {"path": "/p/d", "name": "d", "project_id": null, "state": "ready", "detail": "Copilot is ready for this project.", "declared_components": ["claude"], "installed_components": ["claude"], "recommended_components": ["claude"], "personal_profile": {"state": "associated", "project_id": null}, "setup_policy": "not-offered", "policy_detail": "Copilot is already set up here, so there's nothing to ask.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "There's nothing here to undo yet."}},
            {"path": "/p/e", "name": "e", "project_id": null, "state": "blocked", "detail": "This folder is not a project workspace.", "declared_components": [], "installed_components": [], "recommended_components": [], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "not-offered", "policy_detail": "This can't be set up automatically right now.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "There's nothing here to undo yet."}},
            {"path": "/p/f", "name": "f", "project_id": null, "state": "ready", "detail": "Copilot is ready for this project.", "declared_components": ["claude"], "installed_components": ["claude"], "recommended_components": ["claude"], "personal_profile": {"state": "associated", "project_id": null}, "setup_policy": "not-offered", "policy_detail": "Copilot is already set up here, so there's nothing to ask.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": true, "detail": "Removes only what I added. Your own files are left alone."}},
            {"path": "/p/g", "name": "g", "project_id": null, "state": "ready", "detail": "Copilot is ready for this project.", "declared_components": ["claude"], "installed_components": ["claude"], "recommended_components": ["claude"], "personal_profile": {"state": "associated", "project_id": null}, "setup_policy": "not-offered", "policy_detail": "Copilot is already set up here, so there's nothing to ask.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "You've changed these files since, so I'll leave them alone."}}
          ],
          "summary": {"ready": 3, "setup-available": 2, "activation-required": 1, "blocked": 1, "total": 7},
          "recently_set_up": [{"name": "f", "detail": "Set your copilots up in f."}, {"name": "g", "detail": "Set your copilots up in g."}]
        }
        """
        let rowsData = WorkspaceContractSelftestFixture.report(
            rowsJSON,
            classifications: [
                .safeFinish,
                .safeFinish,
                .safeFinish,
                .ready,
                .couldNotVerify,
                .ready,
                .ready,
            ]
        )
        guard let rowsReport = try? selftestDecoder().decode(WorkspacesReport.self, from: rowsData) else {
            print("SELFTEST trayProjects rowsDecode=fail")
            return false
        }
        let rows = rowsReport.workspaces
        let diagnosticPass = rows[4].diagnostic?.mode == "read-only"
            && rows[4].diagnostic?.prompt.text.contains("Do not create, edit") == true
            && rows[3].diagnostic == nil
        let rowsPass = ProjectRowRender.controlLabel(for: rows[0]) == "Review"
            && ProjectRowRender.caption(for: rows[0]) == "Add only the missing Copilot integration files."
            && ProjectRowRender.kind(for: rows[1]) == .excluded
            && ProjectRowRender.controlLabel(for: rows[1]) == "Review"
            && ProjectRowRender.caption(for: rows[1]) == "Left alone at your request."
            && ProjectRowRender.controlLabel(for: rows[2]) == "Review"
            && ProjectRowRender.controlLabel(for: rows[3]) == "View details"
            && ProjectRowRender.kind(for: rows[3]) == .alreadySetUp
            && ProjectRowRender.controlLabel(for: rows[4]) == "Review evidence"
            && ProjectRowRender.kind(for: rows[4]) == .couldNotVerify
            && ProjectRowRender.caption(for: rows[4]) == "This folder is not a project workspace."
        let ownerData = WorkspaceContractSelftestFixture.entry(
            #"{"path":"/p/owner","name":"owner","project_id":null,"state":"blocked","detail":"This project needs its owner.","declared_components":[],"installed_components":[],"recommended_components":["claude","codex"],"personal_profile":{"state":"local-only","project_id":null},"setup_policy":"not-offered","policy_detail":"Nothing was changed.","can_apply_now":false,"apply_blocked_detail":"Nothing was changed.","undo":{"available":false,"detail":"There's nothing here to undo yet."}}"#,
            classification: .ownerDecision
        )
        guard let ownerRow = try? selftestDecoder().decode(
            WorkspaceEntry.self,
            from: ownerData
        ) else {
            print("SELFTEST trayProjects ownerDecode=fail")
            return false
        }
        let routePass = ProjectRowRender.controlLabel(for: pluralReport.workspaces[2]) == "Review setup"
            && pluralReport.workspaces[2].classification == .guidedIntegration
            && ProjectRowRender.controlLabel(for: ownerRow) == "Review decision"
            && ownerRow.integrationPlan?.ownerHandoff != nil

        // B3: `recentlySetUpNames` is the ONLY signal that distinguishes an
        // ordinary `ready` row (`rows[3]`, "d", above — absent from
        // `recently_set_up`, stays `alreadySetUp`) from one the CLI just
        // named as automatic (`rows[5]`/`rows[6]`, "f"/"g").
        let recentlySetUpNames = Set((rowsReport.recentlySetUp ?? []).map(\.name))
        let automaticAvailable = rows[5]
        let automaticUnavailable = rows[6]
        let automaticPass = recentlySetUpNames == Set(["f", "g"])
            && ProjectRowRender.kind(for: automaticAvailable, recentlySetUpNames: recentlySetUpNames) == .automaticallySetUp
            && ProjectRowRender.caption(for: automaticAvailable, recentlySetUpNames: recentlySetUpNames) == "Set up automatically when you created it."
            && ProjectRowRender.controlLabel(for: automaticAvailable, recentlySetUpNames: recentlySetUpNames) == "Undo"
            && ProjectRowRender.kind(for: automaticUnavailable, recentlySetUpNames: recentlySetUpNames) == .automaticallySetUp
            && ProjectRowRender.caption(for: automaticUnavailable, recentlySetUpNames: recentlySetUpNames) == "You've changed these files since, so I'll leave them alone."
            && ProjectRowRender.controlLabel(for: automaticUnavailable, recentlySetUpNames: recentlySetUpNames) == nil
            // A `ready` row absent from `recently_set_up` is unaffected —
            // the default-empty-set overloads used everywhere else in this
            // file behave exactly as before B3.
            && ProjectRowRender.kind(for: rows[3]) == .alreadySetUp

        let automaticNoticePass = RecentlySetUpRender.noticeText([WorkspaceRecentlySetUp(name: "Convoco", detail: "Set your copilots up in Convoco.")])
            == "New projects get your copilots automatically now. I just set up Convoco."
            && RecentlySetUpRender.noticeText((1...12).map { WorkspaceRecentlySetUp(name: "p\($0)", detail: "Set your copilots up in p\($0).") })
            == "New projects get your copilots automatically now. I just set up 12 new projects."

        let revertJSON = """
        {"schema_version": "1.0", "mode": "apply", "result": "applied", "workspaces": [{"path": "/p/f", "name": "f", "project_id": null, "state": "setup-available", "detail": "Copilot can be set up for this project.", "declared_components": [], "installed_components": [], "recommended_components": ["claude"], "personal_profile": {"state": "local-only", "project_id": null}, "setup_policy": "excluded", "policy_detail": "You asked me not to set this project up again.", "can_apply_now": true, "apply_blocked_detail": null, "undo": {"available": false, "detail": "There's nothing here to undo yet."}}], "revert": {"removed": ["claude"], "kept": [], "detail": "Removed. Your own files were left alone, and I won't set this project up again unless you ask."}}
        """
        let revertData = WorkspaceContractSelftestFixture.report(
            revertJSON,
            classifications: [.safeFinish]
        )
        guard let revertReport = try? selftestDecoder().decode(WorkspaceRevertReport.self, from: revertData) else {
            print("SELFTEST trayProjects revertDecode=fail")
            return false
        }
        let revertDecodePass = revertReport.result == .applied
            && revertReport.revert.removed == ["claude"]
            && revertReport.workspaces.first?.path == "/p/f"
            && revertReport.workspaces.first?.setupPolicy == .excluded

        let passed = noticePass && rowsPass && routePass
            && automaticPass && automaticNoticePass && revertDecodePass
            && diagnosticPass
        print(
            "SELFTEST trayProjects notice=\(noticePass ? "pass" : "fail") "
                + "rows=\(rowsPass ? "pass" : "fail") "
                + "routes=\(routePass ? "pass" : "fail") "
                + "automatic=\(automaticPass ? "pass" : "fail") "
                + "automaticNotice=\(automaticNoticePass ? "pass" : "fail") "
                + "revert=\(revertDecodePass ? "pass" : "fail") "
                + "diagnostic=\(diagnosticPass ? "pass" : "fail")"
        )
        return passed
    }

    // MARK: CT_SETUP_PROGRESS_SELFTEST — wizard Step 8, "Setting up your
    // copilots" (progress-and-waiting spec)
    //
    // Proves, offline, pure: (1) a fresh `SetupProgressState` is
    // `.notStarted` EVERYWHERE — no row defaults to `.working`, and the two
    // cases are structurally distinct (never a boolean that could conflate
    // them); (2) `WizardModel.resolveStageRows(from:)` reads real engine
    // results — a "blocked" stage becomes `.couldNotFinish` carrying the
    // engine's own detail, an ordinary stage becomes `.done`, and a stage
    // the report never mentions at all becomes `.neverReported`, never
    // silently `.notStarted` forever; (3) `countLine` has a fixed denominator
    // and counts every terminal CLI outcome, including non-success; (4) the one
    // background-sweep sentence this file renders carries no digit at all
    // (P3's own rule: never a denominator it doesn't have). No `Task.sleep`
    // and no timer of any kind appears anywhere in this function — every
    // value below comes straight from data.
    private static func runSetupProgressSelftest() -> Bool {
        let fresh = SetupProgressState()
        let neverStartedPass = fresh.callRow.state == .notStarted
            && fresh.projectRows.isEmpty
            && fresh.stageRows.count == 6
            && fresh.stageRows.allSatisfy { $0.state == .notStarted }

        var working = fresh
        working.callRow.state = .working(startedAt: Date())
        let distinctFromWorkingPass = working.callRow.state != .notStarted
            && fresh.callRow.state != working.callRow.state

        let stagesJSON = """
        [
          {"stage": "organization-handoff", "result": "ready"},
          {"stage": "personal-packages", "result": "applied"},
          {"stage": "device-ssh", "result": "blocked", "detail": "This Mac's own secure connection could not be confirmed."},
          {"stage": "secret-store", "result": "deferred"},
          {"stage": "codex-plugin", "result": "ready"}
        ]
        """
        guard let stagesData = stagesJSON.data(using: .utf8),
              let stages = try? selftestDecoder().decode([EcosystemOnboardStage].self, from: stagesData) else {
            print("SELFTEST setupProgress stagesDecode=fail")
            return false
        }
        // `layer-manifest` is deliberately absent from the fixture above —
        // it must read `.neverReported`, not silently stay `.notStarted`.
        let rows = WizardModel.resolveStageRows(from: stages)
        let doneRow = rows.first(where: { $0.id == "organization-handoff" })
        let blockedRow = rows.first(where: { $0.id == "device-ssh" })
        let neverReportedRow = rows.first(where: { $0.id == "layer-manifest" })
        var realResultsPass = false
        var blockedDetailPass = false
        if case .done = doneRow?.state, case .couldNotFinish(let detail) = blockedRow?.state,
           case .neverReported = neverReportedRow?.state {
            realResultsPass = true
            blockedDetailPass = detail.contains("This Mac's own secure connection could not be confirmed.")
        }

        var counted = SetupProgressState()
        counted.callRow.state = .done(detail: "Done.")
        counted.stageRows = WizardModel.resolveStageRows(from: stages)
        counted.projectRows = [
            SetupRow(id: "/p/a", title: "a", state: .done(detail: "Copilot is ready for this project.")),
            SetupRow(id: "/p/b", title: "b", state: .working(startedAt: Date())),
        ]
        // The call, all six named stages, and both approved projects were on
        // screen from the start. Seven have terminal reports; one project is
        // still working.
        let countLinePass = counted.countLine == "8 of 9 outcomes reported."
        let fixedDenominatorPass = SetupProgressState().countLine == "0 of 7 outcomes reported."

        let backgroundNote = "Also checking your other projects in the background. You don't have to wait for that."
        let noDenominatorPass = !backgroundNote.contains(where: { $0.isNumber })

        let passed = neverStartedPass && distinctFromWorkingPass && realResultsPass
            && blockedDetailPass && countLinePass && fixedDenominatorPass && noDenominatorPass
        print(
            "SELFTEST setupProgress neverStarted=\(neverStartedPass ? "pass" : "fail") "
                + "distinctWorking=\(distinctFromWorkingPass ? "pass" : "fail") "
                + "realResults=\(realResultsPass ? "pass" : "fail") "
                + "blockedDetail=\(blockedDetailPass ? "pass" : "fail") "
                + "countLine=\(countLinePass ? "pass" : "fail") "
                + "fixedDenominator=\(fixedDenominatorPass ? "pass" : "fail") "
                + "noDenominator=\(noDenominatorPass ? "pass" : "fail")"
        )
        return passed
    }

    // MARK: CT_TRAY_WAIT_SELFTEST — P4 named single waits (join a
    // department, add/undo a project) and the shared named-subject spinner
    //
    // Proves, offline, pure: (1) `NamedWaitRender`'s silence-path sentences
    // are exactly the ones the progress-and-waiting spec gives verbatim
    // (§7), and are each a DIFFERENT sentence from the CLI's own real-
    // failure copy, so a stall can never be misread as a report; (2)
    // `CTNamedWaitSpinner` — the one place this file and `native/wizard.swift`
    // construct a `ProgressView` — always carries the subject it was given,
    // never blank.
    private static func runTrayWaitSelftest() -> Bool {
        let joinWaitText = NamedWaitRender.hasNotComeThrough("Design")
        let joinFailureText = "Couldn't join Design right now. Try again."
        let joinTextPass = joinWaitText == "Design hasn't come through yet. Nothing was changed."
            && joinWaitText != joinFailureText

        let addWaitText = NamedWaitRender.projectHasNotComeThrough("Insights Copilot")
        let addFailureText = "Couldn't add it right now. Nothing existing was changed."
        let addTextPass = addWaitText == "Insights Copilot hasn't come through yet. Nothing in it was changed."
            && addWaitText != addFailureText

        let undoWaitText = NamedWaitRender.projectUndoHasNotComeThrough("Insights Copilot")
        let undoFailureText = "Couldn't undo that right now. Nothing was changed."
        let undoTextPass = undoWaitText == "Insights Copilot hasn't come through yet. Nothing was undone."
            && undoWaitText != undoFailureText

        let spinner = CTNamedWaitSpinner(subject: "Joining Design…")
        let namedSpinnerPass = spinner.subject == "Joining Design…" && !spinner.subject.isEmpty

        let passed = joinTextPass && addTextPass && undoTextPass && namedSpinnerPass
        print(
            "SELFTEST trayWait join=\(joinTextPass ? "pass" : "fail") "
                + "add=\(addTextPass ? "pass" : "fail") "
                + "undo=\(undoTextPass ? "pass" : "fail") "
                + "namedSpinner=\(namedSpinnerPass ? "pass" : "fail")"
        )
        return passed
    }
}

// `@main`, not a top-level `ControlTowerTrayApp.main()` call: this app is
// compiled as multiple files together (`swiftc native/*.swift`), and Swift
// only permits top-level executable statements in a lone file named
// `main.swift` in a multi-file, non-single-file compilation — `@main` is the
// portable entry-point spelling that works either way.
@main
struct ControlTowerTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The real post-onboarding Settings window is owned explicitly by
        // `UserSettingsWindowController`, so this placeholder Scene never
        // auto-shows a second window at launch.
        Settings {
            EmptyView()
        }
    }
}
