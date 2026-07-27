//
// Copilot Control Tower — CLI `--json` response DTOs.
//
// One `Decodable` type per shape in `docs/01-architecture/schemas/`
// (auth/doctor/layers/freshness/update/projects.schema.json). `native/cli-client.swift`
// decodes into these with `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`,
// so every property below is spelled camelCase and relies on that strategy to match
// the wire format's `snake_case` keys — EXCEPT where a schema field is itself a
// hyphenated string enum (e.g. `"signed-out"`), which `.convertFromSnakeCase` cannot
// touch (it only rewrites underscores in KEYS, never the string VALUES), so those are
// spelled out as explicit `String` raw values below, same convention `native/models.swift`
// already uses for `CliStatus`.
//
// FAIL-CLOSED, PARSE NEVER COMPUTE (CLAUDE.md invariants #1 and #4):
//   - Every struct here mirrors its schema's `required` list with non-optional Swift
//     properties. A required field that is absent from the wire payload is a decode
//     FAILURE, not a default value — `native/cli-client.swift`'s `decodeVerb` maps that
//     failure to `.missingSecurityField` (when the missing key is `destructive`/`signed`/
//     `severity`) or `.parse` (everything else), never to a fabricated default.
//   - `additionalProperties: true` fields (`doctor.checkers[]`, `doctor.auth[]`,
//     `update.held_for_approval[]`) need no special handling: Swift's synthesized
//     `Decodable` conformance already IGNORES any JSON key that has no matching Swift
//     property. This is also the mechanism that makes the app immune to an adversarial
//     leaked-field payload (e.g. a stray `access_token` key smuggled onto an otherwise
//     normal response) — an unknown field is silently dropped at the decode boundary,
//     never forwarded into any DTO this app holds. See `auth.schema.json`'s NO-SECRET
//     fitness invariant and `fixtures/wizard/README.md`'s `authorized-leaked-field-adversarial`
//     negative-test fixture, which exercises exactly this on the wizard's own (separate,
//     Rust-side) seam — this file is the native app's analogous guarantee.
//   - `oneOf`-shaped schemas (auth's `device-code|poll|status|errorEnvelope`; layers'
//     `list_report|join_result`; projects' `all_projects_freshness|fanout_report`) are
//     NEVER discriminated by inspecting a raw JSON blob's shape ahead of time here.
//     Every `CliClient` typed verb already knows which branch it is calling (the verb/
//     subcommand invoked IS the discriminant — `auth login` vs. `auth login --poll` vs.
//     `auth status`; `layers` vs. `layers join`; `freshness --all-projects` vs.
//     `update --fanout`), so it decodes directly into that one expected type. `OneOf2`
//     below exists for the general case (a caller that genuinely does not know which
//     branch it received) and discriminates by attempted-decode-with-fallback: try the
//     first branch, fall back to the second. This is safe specifically because every
//     `oneOf` branch in these schemas sets `additionalProperties: false`, so at most one
//     branch can ever successfully decode a given payload.

import Foundation

// MARK: - Generic oneOf helper (attempted-decode-with-fallback)

/// Decodes as `A` if possible, else `B`. Only sound because every schema this app
/// consumes marks each `oneOf` branch `additionalProperties: false` — a payload
/// structurally shaped like `B` can never successfully decode as `A` by accident.
enum OneOf2<A: Decodable, B: Decodable>: Decodable {
    case first(A)
    case second(B)

    init(from decoder: Decoder) throws {
        if let a = try? A(from: decoder) {
            self = .first(a)
            return
        }
        self = .second(try B(from: decoder))
    }
}

// MARK: - auth.schema.json

struct AuthDeviceCode: Decodable {
    let schemaVersion: String
    let kind: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int
    let deviceCode: String
}

enum AuthPollStatus: String, Decodable {
    case pending
    case authorized
    case expired
    case denied
}

struct AuthPoll: Decodable {
    let schemaVersion: String
    let kind: String
    let status: AuthPollStatus
}

// MARK: - auth grant --json (H7's least-privilege permission upgrade)

struct AuthGrantStart: Decodable {
    let schemaVersion: String
    let kind: String
    let permission: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int
    let deviceCode: String
}

enum AuthGrantPollStatus: String, Decodable {
    case pending
    case granted
    case denied
    case expired
    case identityMismatch = "identity-mismatch"
    case insufficientScope = "insufficient-scope"
}

struct AuthGrantPoll: Decodable {
    let schemaVersion: String
    let kind: String
    let status: AuthGrantPollStatus
}

enum AuthState: String, Decodable {
    case authorized
    case signedOut = "signed-out"
}

struct AuthIdentity: Decodable {
    let login: String
}

struct AuthStatus: Decodable {
    let schemaVersion: String
    let kind: String
    /// Wire key is `status` (offline-safe "who is signed in"); named `state`
    /// here to avoid colliding with `AuthPoll.status`'s different vocabulary
    /// (`pending|authorized|expired|denied` vs. this field's `authorized|signed-out`).
    let state: AuthState
    let identity: AuthIdentity?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, identity, scope
        case state = "status"
    }
}

// MARK: - doctor.schema.json

/// The authoritative ~10-state enum `doctor --json` emits (`doctor.schema.json`'s
/// `status` property). Deliberately a SEPARATE type from `native/models.swift`'s
/// `CliStatus` (same raw values) rather than reusing it: `CliStatus` belongs to the
/// mock-fixture-era render model that `models.swift` documents as `// PHASE-I-REMOVE`,
/// while this one is the real wire DTO `native/cli-client.swift` decodes into. Keeping
/// them distinct means this phase adds no edits to the old mock file (compat rule).
enum DoctorStatus: String, Decodable {
    case setupNeeded = "setup-needed"
    case itConfigIncomplete = "it-config-incomplete"
    case healthy
    case syncing
    case updateAvailable = "update-available"
    case needsAttention = "needs-attention"
    case signedOut = "signed-out"
    case offline
    case waitingForNetwork = "waiting-for-network"
    case updatingApp = "updating-app"
}

/// Per-checker verdict (`pass|warn|fail`). A DISTINCT type from `native/models.swift`'s
/// `Severity` (same raw values, same reason as `DoctorStatus` above): that type already
/// carries a `displayBadge` computed property tied to the old mock render path, and this
/// phase must not touch it (compat rule) — `native/render-state.swift` is what bridges
/// this wire-level `CliSeverity` onto the render-level `Severity`/`BadgeState`.
enum CliSeverity: String, Decodable {
    case pass
    case warn
    case fail
}

/// `checkers[]` items are `additionalProperties: true` (the schema's own `$comment`
/// calls this "intentionally open/extensible") — no special handling needed here; see
/// this file's header on how Swift's default `Decodable` synthesis already drops any
/// JSON key with no matching property below.
struct Checker: Decodable {
    let id: String
    let severity: CliSeverity
    let detail: String?
    let repair: String?
    /// Security-relevant (`doctor.schema.json`: "a missing value is treated as
    /// destructive, fail-closed") — REQUIRED, never defaulted. A missing `destructive`
    /// key fails this whole decode; `CliClient` maps that to `.missingSecurityField`.
    let destructive: Bool
    let layer: String?
    let product: String?
    let localSha: String?
    let remoteSha: String?
    let path: String?
    let escalate: String?
}

enum AuthEntryState: String, Decodable {
    case expired
    case revoked
}

struct AuthEntry: Decodable {
    let identity: String
    let scope: String
    let state: AuthEntryState
    let expiresAt: String?
}

struct DoctorReport: Decodable {
    let schemaVersion: String
    let host: String
    let score: Int
    let generatedAt: String?
    let status: DoctorStatus
    let offline: Bool
    let checkers: [Checker]
    /// Not in `doctor.schema.json`'s `required` list — omitted entirely on a
    /// verdict with nothing to flag, per the schema's own `auth` description
    /// ("Only failing/needs-attention entries are expected in this array").
    let auth: [AuthEntry]?
}

// MARK: - layers.schema.json

enum LayerTier: String, Decodable {
    case org
    case department
}

enum LayerNotEntitledReason: String, Decodable {
    case signedOut = "signed-out"
    case offline
}

/// `Identifiable` (by the layer's own `id`) is declared here, not at a call
/// site, so there is exactly one canonical conformance for every consumer
/// (`native/control-tower-tray.swift`'s Region 3 `ForEach`, and any future
/// one) to share.
struct LayerEntry: Decodable, Identifiable {
    let tier: LayerTier
    let id: String
    let name: String
    let repo: String
    /// `["boolean", "null"]` in the schema: `null` means "could not be
    /// determined" (see `reason`) and MUST be treated as not-entitled, never
    /// as `true` (`layers.schema.json`'s own fail-closed note on this field).
    let entitled: Bool?
    let joined: Bool
    let reason: LayerNotEntitledReason?
}

struct LayersReport: Decodable {
    let schemaVersion: String
    let host: String?
    let layers: [LayerEntry]
}

enum JoinOutcome: String, Decodable {
    case joined
    case alreadyJoined = "already-joined"
    case notEntitled = "not-entitled"
    case offline
    case error
}

struct JoinResult: Decodable {
    let schemaVersion: String
    let host: String?
    let result: JoinOutcome
    let tier: LayerTier
    let id: String
    let syncedLockSha: String?
    let reason: String?
}

// MARK: - freshness.schema.json

struct FreshnessLayer: Decodable {
    let id: String
    let current: String?
    let latest: String?
    let stale: Bool?
    let offline: Bool
}

struct Freshness: Decodable {
    let schemaVersion: String
    let latestLockSha: String?
    let currentLockSha: String?
    let stale: Bool?
    let offline: Bool
    let checkedAt: String
    /// OPTIONAL, ADDITIVE per-layer breakdown — omitted unless the CLI was
    /// specifically asked to compute it (see the schema's own description).
    let layers: [FreshnessLayer]?
}

// MARK: - update.schema.json

enum ChangeOp: String, Decodable {
    case added
    case updated
    case pruned
    case unchanged
}

struct Change: Decodable {
    let dimension: String
    let layer: String
    let item: String
    let op: ChangeOp
    let from: String?
    let to: String?
    /// Security-relevant ("a missing value is treated as unsigned,
    /// fail-closed") — REQUIRED, never defaulted.
    let signed: Bool
    let severityTrailer: String?
    let shadowedBy: String?
}

struct Held: Decodable {
    let dimension: String
    let from: String
    let to: String
    let reason: String
}

/// `blocked[]` items are an intentionally open, still-unfrozen shape
/// (`update.schema.json`'s own `$comment`: "the upstream design does not
/// show a concrete example item shape ... left as an open array of objects
/// until the CLI freezes it"). An empty struct always decodes successfully
/// against ANY JSON object, regardless of its actual fields, which is
/// exactly the "open array of objects" the schema describes without pulling
/// in a general `AnyCodable` machinery this app does not otherwise need.
struct BlockedItem: Decodable {}

enum UpdateResult: String, Decodable {
    case applied
    case upToDate = "up-to-date"
    case held
    case blocked
    case offline
}

struct UpdateReport: Decodable {
    let schemaVersion: String
    let host: String?
    /// ADDITIVE, per-project field (Component Sync) — absent on the
    /// machine-wide `update --json` result, present on a `--project <path>`
    /// result (see the schema's own `path` description).
    let path: String?
    let result: UpdateResult
    let lockBefore: String
    let lockAfter: String
    let changed: [Change]
    let heldForApproval: [Held]?
    let blocked: [BlockedItem]?
}

// MARK: - projects.schema.json

enum SweepProduct: String, Decodable {
    case claude
    case codex
}

struct ProjectComponent: Decodable {
    let product: SweepProduct
    let current: String?
    let latest: String?
    let stale: Bool?
    let held: Bool
}

struct Project: Decodable {
    let path: String
    let stale: Bool?
    let components: [ProjectComponent]
}

enum GlobalProduct: String, Decodable {
    case knowledge
    case cli
}

struct GlobalComponent: Decodable {
    let product: GlobalProduct
    let current: String?
    let latest: String?
    let stale: Bool?
}

/// The read-only per-project sweep (`freshness --all-projects --json`).
/// Structurally distinguished from `FanoutReport` below by shape alone
/// (`projects`+`global` here vs. `summary`+`results` there) — see this
/// file's header on why no explicit discriminant field is needed.
struct AllProjectsFreshness: Decodable {
    let schemaVersion: String
    let generatedAt: String
    let total: Int
    let projects: [Project]
    let global: [GlobalComponent]
}

enum FanoutTrigger: String, Decodable {
    case cadenceSync = "cadence-sync"
    case manual
    case releaseTag = "release-tag"
}

struct FanoutSummary: Decodable {
    let updated: Int
    let held: Int
    let upToDate: Int
    let failed: Int
    let total: Int
}

enum ResultItemComponent: String, Decodable {
    case claude
    case codex
}

enum ResultItemOutcome: String, Decodable {
    case upToDate = "up-to-date"
    case blocked
}

struct ResultItem: Decodable {
    let path: String
    /// `["string", null]` in the schema (`claude|codex|null`) — `null` marks
    /// a project-level read failure that never reached per-component work.
    let component: ResultItemComponent?
    /// Present ONLY for the two outcomes reported without a full per-project
    /// `report` (an honest up-to-date skip, or a project-level read
    /// failure) — see `report` below.
    let result: ResultItemOutcome?
    let reason: String?
    /// Present for every attempted materialize (applied/held/blocked/offline)
    /// — the SAME per-project shape `UpdateReport` decodes standalone.
    let report: UpdateReport?
}

/// The write-side fan-out roll-up (`update --fanout --json`). See
/// `AllProjectsFreshness` above on how the two `projects.schema.json`
/// branches are told apart.
struct FanoutReport: Decodable {
    let schemaVersion: String
    let generatedAt: String
    let triggeredBy: FanoutTrigger
    let summary: FanoutSummary
    let results: [ResultItem]
}

// MARK: - onboard --scope personal --json

enum OnboardResult: String, Decodable {
    case ready
    case changesRequired = "changes-required"
    case applied
    case blocked
}

enum RepositoryState: String, Decodable {
    case existingPrivate = "existing-private"
    case missing
    case created
    case conflictPublic = "conflict-public"
    case unknown
}

struct RepositoryPlanRow: Decodable {
    let component: String
    let role: String
    let unit: String?
    let owner: String
    let name: String
    let visibility: String?
    let state: RepositoryState
    let action: String
    let detail: String
    /// Added 2026-07-24 (B1, adopt-existing-content): the CLI has always
    /// emitted these four on every row (`onboard.py`'s `_row()`); this
    /// struct silently DROPPED them until now (Swift's synthesized
    /// `Decodable` ignores any JSON key with no matching property — see this
    /// file's header). That silent drop is exactly why the app could not
    /// render an "adopt my existing content" offer even after the CLI
    /// started emitting one: `package_state: "adoptable"` never reached any
    /// Swift value. `rank`/`package_state`/`package_action`/`package_detail`
    /// are in the vendored schema's `required` list, so this is a plain
    /// correctness fix, not new optional surface.
    let rank: Int
    let packageState: String
    let packageAction: String
    let packageDetail: String
    /// Added 2026-07-24 (B3, undo/decline-cost close-out): the CLI now puts
    /// a plain, component-specific sentence on an adoptable row naming what
    /// declining it costs — `onboard.schema.json`'s `repository.decline_detail`
    /// (optional; older CLI builds omit it). Rendered verbatim, never
    /// invented, on the "One question first" screen's cleared-row caption —
    /// `nil` renders no caption at all, per the spec's own failure/recovery
    /// row for this exact field.
    let declineDetail: String?
}

struct RepositoryPlanSummary: Decodable {
    let existing: Int
    let missing: Int
    let created: Int
    let blocked: Int
    /// Not in the schema's `required` list (older CLI builds omit it) —
    /// optional, never defaulted to 0 when absent.
    let adoptable: Int?
}

struct OnboardReport: Decodable {
    let schemaVersion: String
    let scope: String
    let owner: String
    let mode: String
    let result: OnboardResult
    let repositories: [RepositoryPlanRow]
    let summary: RepositoryPlanSummary
}

struct EcosystemOnboardStage: Decodable {
    let stage: String
    let result: String
    let detail: String?
    let action: String?
    let path: String?
    let rollbackPath: String?
    let layers: Int?
    let blocked: Int?
    let held: Int?
    let score: Int?
    /// `device-ssh`-only fields (verified live, `cc onboard --org auto
    /// --products claude --json`: `{"key": "unknown", "registration":
    /// "unknown", "config": "held", ...}`) — previously silently dropped,
    /// same class of gap as `RepositoryPlanRow`'s `rank`/`package_state`
    /// above (Swift's synthesized `Decodable` ignores any JSON key with no
    /// matching property). `config == "held"` (or `key == "incomplete"`) is
    /// the wizard's H4-vs-H3 discriminator for this stage (holding-copy-spec
    /// §3: "This Mac already has a GitHub connection I didn't set up" is
    /// invariant #3 working, never a fault) — see `WizardModel`'s Holding
    /// classifier in `native/wizard.swift`. `registration` is decoded for
    /// completeness (the CLI always emits it alongside the other two) and IS
    /// read: `registration == "not-permitted"` is Holding's H7 discriminator
    /// (`WizardModel.holdingInfo(forBlockedOnboard:)`'s `device-ssh` branch,
    /// checked BEFORE the `config == "held"` H4 branch, per copy spec
    /// Appendix D.2's gate table) and drives `TrayModel.permissionNeededPending`
    /// (`native/control-tower-tray.swift`), Region 6's `permission-needed`
    /// prompt.
    let key: String?
    let registration: String?
    let config: String?
}

/// Content-free topology proof returned by aggregate onboarding. Repository
/// URLs, credentials, signer data, and package contents stay on the CLI side
/// of the seam; the app only renders which layers were connected and the
/// precedence assigned by the CLI.
struct EcosystemOnboardLayer: Decodable {
    let id: String
    let product: String
    let role: String
    let rank: Int
}

/// A content-free adoption decision computed by `cc onboard`. The app never
/// inspects paths or decides whether something is safe to move; it renders the
/// CLI's reuse/create/migrate/repair/review verdict.
struct EcosystemInventoryItem: Decodable, Identifiable {
    let id: String
    let scope: String
    let title: String
    let state: String
    let action: String
    let detail: String
    let sourcePath: String?
    let destinationPath: String?
    let reversible: Bool
    /// Added 2026-07-24 (B3, undo/decline-cost close-out): same field, same
    /// verbatim-or-nothing rule as `RepositoryPlanRow.declineDetail` above —
    /// `onboard.schema.json`'s `inventoryItem.decline_detail` (optional).
    /// This is the one the "One question first" screen's ask rows actually
    /// decode from (`WizardModel.personalOnboardQuestion(from:)` builds its
    /// `ask` rows from THIS report's `inventory`, not `RepositoryPlanRow`'s).
    let declineDetail: String?
}

struct EcosystemInventorySummary: Decodable {
    let reused: Int
    let changes: Int
    let review: Int
}

struct EcosystemOnboardReport: Decodable {
    let schemaVersion: String
    let scope: String
    let mode: String
    let result: OnboardResult
    let org: String
    let products: [String]
    let stages: [EcosystemOnboardStage]
    let layers: [EcosystemOnboardLayer]
    let inventory: [EcosystemInventoryItem]?
    let inventorySummary: EcosystemInventorySummary?
}

// MARK: - workspace --all --json

enum WorkspaceActivationState: String, Decodable {
    case ready
    case setupAvailable = "setup-available"
    case activationRequired = "activation-required"
    case blocked
}

enum PersonalProfileState: String, Decodable {
    case associated
    case available
    case localOnly = "local-only"
}

struct WorkspacePersonalProfile: Decodable {
    let state: PersonalProfileState
    let projectId: String?
}

/// Whether the app must ask before setting a project up (`ask`), whether it
/// may apply silently (`automatic`, reserved — `workspace_status()`'s own
/// module docstring: the CLI does not emit this yet, pending a "known
/// projects as of grant time" ledger), or whether there is nothing to ask
/// about at all (`excluded` — set by `revert`; `not-offered` — already
/// `ready`, or genuinely `blocked`). The app never infers this itself; it
/// only ever selects the checkbox-vs-immediate-`Add` grammar named by
/// `canApplyNow` below and the caption named by this value.
enum WorkspaceSetupPolicy: String, Decodable {
    case ask
    case automatic
    case excluded
    case notOffered = "not-offered"
}

struct WorkspaceUndo: Decodable {
    let available: Bool
    let detail: String
}

struct WorkspaceEntry: Decodable, Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let projectId: String?
    let state: WorkspaceActivationState
    let detail: String
    let declaredComponents: [String]
    let installedComponents: [String]
    let recommendedComponents: [String]
    let personalProfile: WorkspacePersonalProfile
    /// Added 2026-07-24 (adopt-and-project-setup spec) — all five are in
    /// `workspaces.schema.json`'s `required` list per workspace row. Adding
    /// them here is the same class of fix as `RepositoryPlanRow`'s
    /// `rank`/`package_state`/... above: the wire payload always carried
    /// them, Swift's synthesized `Decodable` just silently dropped them
    /// because no property claimed the key.
    let setupPolicy: WorkspaceSetupPolicy
    let policyDetail: String
    /// False before the copilots this project's setup would copy from exist
    /// on this Mac (e.g. during first-run onboarding, before Set up has
    /// run). Chooses the wizard's checkbox grammar vs. the menu bar's
    /// immediate `Add` grammar — the app never decides that for itself.
    let canApplyNow: Bool
    let applyBlockedDetail: String?
    let undo: WorkspaceUndo
}

struct WorkspaceSummary: Decodable {
    let ready: Int
    let setupAvailable: Int
    let activationRequired: Int
    let blocked: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case ready, blocked, total
        case setupAvailable = "setup-available"
        case activationRequired = "activation-required"
    }
}

enum WorkspaceReportResult: String, Decodable {
    case ready
    case actionRequired = "action-required"
    case applied
    case blocked
}

struct WorkspaceAction: Decodable {
    let id: String
    let scope: String
    let status: String
    let detail: String
}

enum WorkspaceDiscoveryState: String, Decodable {
    case granted
    case notGranted = "not-granted"
    case declined
}

/// `name` is what the app renders; `path` is only ever passed back to the
/// CLI (e.g. as `workspace forget-root --path`), never rendered — same
/// discipline as `WorkspaceRootListEntry`/`WorkspaceRootCandidate` below.
struct WorkspaceDiscoveryRoot: Decodable {
    let name: String
    let path: String
}

struct WorkspaceDiscovery: Decodable {
    let state: WorkspaceDiscoveryState
    let roots: [WorkspaceDiscoveryRoot]
}

/// `cc workspace revert --project <path> --json`'s own `revert` object —
/// what was removed (only files the CLI recorded as its own, with matching
/// checksums) and what was kept (everything else). Component lists mirror
/// `WorkspaceEntry.declaredComponents`'s `[String]` shape (`claude`/`codex`).
struct WorkspaceRevertResult: Decodable {
    let removed: [String]
    let kept: [String]
    let detail: String
}

/// One past-tense automatic-setup record (`workspaces.schema.json`'s
/// `recently_set_up`) — `detail` is already the full rendered sentence
/// (e.g. "Set your copilots up in Convoco."), never assembled from `name`
/// here. Entries age out of the CLI's own record after 168h and are purged
/// immediately on `revert` — the app holds no equivalent state itself
/// across launches (spec, "CLI contract additions").
struct WorkspaceRecentlySetUp: Decodable {
    let name: String
    let detail: String
}

struct WorkspacesReport: Decodable {
    let schemaVersion: String
    let mode: String
    let result: WorkspaceReportResult
    let workspaces: [WorkspaceEntry]
    let summary: WorkspaceSummary
    let actions: [WorkspaceAction]?
    /// `cc workspace --all --json` only — whether this Mac has a projects
    /// folder granted at all, so the menu bar can offer the grant instead of
    /// silently returning nothing (`workspaces.schema.json`'s own `discovery`
    /// description). Not present on a single-`--project` status read.
    let discovery: WorkspaceDiscovery?
    /// `cc workspace revert --project <path> --json` only.
    let revert: WorkspaceRevertResult?
    /// Added 2026-07-24 (B3) — `cc workspace --all/--project --json`'s
    /// top-level "Projects set up for you" record (`build_workspaces_report`
    /// on the CLI side; see `WorkspaceRecentlySetUp` above). Absent on the
    /// narrower `configure`/`approve-root`/etc. reports that don't route
    /// through that helper — optional, never defaulted to an empty list
    /// standing in for "nothing happened" vs. "this report doesn't carry
    /// the field at all".
    let recentlySetUp: [WorkspaceRecentlySetUp]?
}

/// `cc workspace revert --project <path> [--apply] --json` — a NARROWER
/// report shape than `WorkspacesReport` above: the real command handler
/// (`workspaces.py`'s `revert`) builds this dict by hand rather than
/// through `_report()`/`build_workspaces_report()`, so it carries no
/// `summary`/`discovery`/`actions`/`recently_set_up` at all — only
/// `workspaces` (always exactly one entry, the reverted project's own
/// fresh status) and `revert`. Decoding this verb's real output as
/// `WorkspacesReport` (which REQUIRES `summary`) would fail every single
/// call, success or blocked, which is exactly the bug this dedicated type
/// fixes — `native/cli-client.swift`'s `revertWorkspace` decodes THIS type.
struct WorkspaceRevertReport: Decodable {
    let schemaVersion: String
    let mode: String
    let result: WorkspaceReportResult
    let workspaces: [WorkspaceEntry]
    let revert: WorkspaceRevertResult
}

struct WorkspaceRoot: Decodable {
    let name: String
    let state: String
    let detail: String
}

/// `cc workspace approve-root` / `forget-root --path ... --json` — one
/// explicit folder grant/revocation result.
struct WorkspaceRootReport: Decodable {
    let schemaVersion: String
    let mode: String
    let result: WorkspaceReportResult
    let root: WorkspaceRoot
}

/// `cc workspace roots --json` — every folder currently approved for
/// project discovery, plus detected one-click candidates. A structurally
/// distinct shape from `WorkspaceRootReport` above (`roots`+`candidates`
/// arrays vs. a single `root`) — same "typed verb already knows which
/// branch it called" discipline this file's header describes for `oneOf`
/// shapes; `CliClient.workspaceRoots()` is the one call site that decodes
/// this one.
struct WorkspaceRootListEntry: Decodable, Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let projectCount: Int
}

struct WorkspaceRootCandidate: Decodable, Identifiable {
    var id: String { path }
    let path: String
    let label: String
    let projectCount: Int
}

struct WorkspaceRootsListReport: Decodable {
    let schemaVersion: String
    let mode: String
    let result: WorkspaceReportResult
    let roots: [WorkspaceRootListEntry]?
    let candidates: [WorkspaceRootCandidate]?
}

/// `cc workspace decline --apply --json` — the machine-wide "I don't keep
/// projects on this Mac" opt-out. Same `discovery` shape `WorkspacesReport`
/// carries, alone at the top level (no `workspaces`/`summary` on this call).
struct WorkspaceDeclineReport: Decodable {
    let schemaVersion: String
    let mode: String
    let result: WorkspaceReportResult
    let discovery: WorkspaceDiscovery
}
