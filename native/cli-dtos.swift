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
    /// Canonical topology role emitted by cc. `layer` is an opaque identity
    /// and must never be parsed to infer Foundation/Organization/etc.
    let layerRole: String?
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

// MARK: - connections.schema.json (task 221 bridge stage C)

/// Envelope-level outcome. Decoded LENIENTLY (a hand-written `init(from:)`,
/// not a raw-value `Decodable` enum like `DoctorStatus` above) rather than
/// throwing on an unrecognized string: `SchemaGate` only range-gates the
/// MAJOR version (`cli-client.swift`), so an additive minor bump could add a
/// new `result` value without this app's schema floor rejecting it first. An
/// unrecognized value folds into `.unknown`, which every call site treats
/// exactly like any other non-"ok" result (never silently "ok") — fail-closed,
/// same discipline as `LayerEntry.entitled`'s `nil`-means-not-entitled rule.
enum ConnectionsResult: Decodable, Equatable {
    case ok
    case copilotUnavailable
    case orgConfigUnavailable
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "ok": self = .ok
        case "copilot-unavailable": self = .copilotUnavailable
        case "org-config-unavailable": self = .orgConfigUnavailable
        default: self = .unknown
        }
    }
}

/// Per-row secret readiness. Same lenient-decode reasoning as
/// `ConnectionsResult` above — an unrecognized future value becomes
/// `.unknown` rather than failing the whole report's decode, and is grouped
/// with `.noStore` at render time (`native/render-state.swift`'s
/// `ConnectionsRender.noStoreRows`) rather than ever being treated as ready.
enum ConnectionSecretState: Decodable, Equatable {
    case ready
    case needsConnect
    case noStore
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "ready": self = .ready
        case "needs-connect": self = .needsConnect
        case "no-store": self = .noStore
        default: self = .unknown
        }
    }
}

/// A single declared credential name (never a value) plus which
/// credential-ladder rungs it may resolve from. `from` is left a plain
/// `String` (not a closed enum) -- this app never branches on it (only
/// `ConnectionRow.missing`'s NAMES are ever rendered), so there is nothing
/// for a stricter type to buy here, and a plain `String` is inherently
/// forward-tolerant of a future routing hint.
struct ConnectionRequiredSecret: Decodable, Equatable {
    let name: String
    let from: String
}

/// One row of the organization's declared service roster
/// (`connections.schema.json`'s `$defs.connection`). `tier`/`mode` are
/// decoded for contract fidelity but deliberately never surfaced as on-screen
/// jargon (`docs/03-design/`'s Quiet Instrument voice) -- only
/// `name`/`description`/`secretState`/`missing` drive any rendered text.
/// `Equatable` so `ConnectRender.Outcome` (native/render-state.swift) can be,
/// which is what lets a SwiftUI view hold the sheet's terminal state in
/// `@State` and compare it without re-rendering on every unrelated update.
struct ConnectionRow: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let tier: String
    let mode: String
    let requiresSecret: [ConnectionRequiredSecret]
    let storeScope: String?
    let secretState: ConnectionSecretState
    let missing: [String]
}

/// The org's declared shared-secret-store reachability
/// (`connections.schema.json`'s `store` object) -- `type`/`scope`/`detail`
/// are non-secret summaries only (never a credential, never a value).
struct ConnectionsStore: Decodable {
    let type: String?
    let reachable: Bool
    let scope: String?
    let detail: String?
}

/// `cc connections --json`'s full envelope. `connections` is empty only when
/// `result == .copilotUnavailable` (the schema's own note) -- `native/render-state.swift`'s
/// `ConnectionsRender` is the one place this app derives the two-card
/// (Ready to use / Available to connect) layout from it.
struct ConnectionsReport: Decodable {
    let schemaVersion: String
    let result: ConnectionsResult
    let detail: String?
    let org: String?
    let store: ConnectionsStore
    let connections: [ConnectionRow]
}

// MARK: - connect.schema.json (task 222 — the in-app Connect sheet)

/// `cc connect`'s envelope-level outcome. Lenient decode for the same reason
/// `ConnectionsResult` above is: `SchemaGate` only range-gates the MAJOR
/// version, so an additive minor bump could add a value this build has never
/// heard of. An unrecognized value folds into `.unknown`, which every call
/// site treats as "did not succeed" — never silently "ok".
enum ConnectResult: Decodable, Equatable {
    case ok
    case unknownService
    case invalidInput
    case copilotUnavailable
    case orgConfigUnavailable
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "ok": self = .ok
        case "unknown-service": self = .unknownService
        case "invalid-input": self = .invalidInput
        case "copilot-unavailable": self = .copilotUnavailable
        case "org-config-unavailable": self = .orgConfigUnavailable
        default: self = .unknown
        }
    }
}

/// Which mode the CLI actually ran in. The app sends `--check` for its
/// post-connect refresh and nothing else, so a `check` reply to a `connect`
/// call (or the reverse) is a contract violation the render layer treats as a
/// failure rather than trusting — see `ConnectRender.outcome(for:)`.
enum ConnectMode: Decodable, Equatable {
    case connect
    case check
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "connect": self = .connect
        case "check": self = .check
        default: self = .unknown
        }
    }
}

/// Per-credential outcome. Lenient decode, and an unrecognized value folds
/// into `.failed` rather than `.unknown` + a separate branch: the only honest
/// reading of "this build does not know what happened to this credential" is
/// "do not claim it was stored".
enum CredentialOutcomeState: Decodable, Equatable {
    case stored
    case alreadyPresent
    case failed

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "stored": self = .stored
        case "already-present": self = .alreadyPresent
        default: self = .failed
        }
    }
}

/// One credential's outcome (`connect.schema.json`'s `$defs.credentialOutcome`).
/// `name` is a NAME, never a value; `detail` is the CLI's own plain-language
/// reason and is contractually guaranteed never to contain the value or any
/// substring of it. Nothing in this app ever puts a value into a DTO — the
/// values travel one way, over stdin, and are never read back.
struct CredentialOutcome: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let outcome: CredentialOutcomeState
    let detail: String?
}

/// `cc connect <service-id> [--check] --json`'s full envelope.
///
/// `service` is the SAME row shape `cc connections --json` returns (the schema
/// `$ref`s `connections.schema.json#/$defs/connection` rather than duplicating
/// it), re-evaluated AFTER any writes — which is precisely what lets the two
/// connections surfaces refresh a single row from this reply without a second
/// full `connections` call, and without this app deciding for itself whether
/// the write "worked" (invariant #1).
struct ConnectReport: Decodable {
    let schemaVersion: String
    let result: ConnectResult
    let detail: String?
    let mode: ConnectMode
    let service: ConnectionRow?
    let credentials: [CredentialOutcome]?
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

// MARK: - onboard schema 2.0 (task 208/G-5, task 210/G-7, task 211/G-4b) —
// `layers_state`, the fully-required `ecosystemLayer` row shape (still
// decoded with per-row optionals below, for backward tolerance — see
// `EcosystemOnboardLayer`'s own doc comment), and the `completed_actions`
// mutation ledger + `resume` hint. `SchemaGate` (`native/cli-client.swift`)
// now rejects an `onboard` response below major 2 before any of this is
// ever reached, so a report that DOES decode here is guaranteed to have
// come from a helper that emits these fields — `layersState`/
// `completedActions` are therefore REQUIRED (never optional/defaulted),
// matching this file's own "a required field absent is a decode failure"
// discipline. `resume` stays optional: the schema requires it only when
// `result == "blocked"`, a cross-field rule Swift's `Decodable` cannot
// express structurally, so a `blocked` report with no `resume` still
// decodes (fail-open on this ONE non-security field, not fail-closed) —
// `WizardModel.holdingInfo(forBlockedOnboard:)` treats an absent `resume`
// the same as `safe_to_rerun: true` (retry stays offered by default,
// per that classifier's own doc comment), never as a crash.

enum EcosystemLayersState: String, Decodable {
    case reported
    case notComputed = "not-computed"
}

enum CompletedActionOutcome: String, Decodable {
    case completed
    case failed
    case rolledBack = "rolled-back"
}

/// One `completed_actions` ledger row — a mutation the run actually
/// completed, attempted, or rolled back, in the order it happened. Every
/// field below is in the schema's `required` list; `additionalProperties:
/// true` carries kind-specific extras (`url`, `from_sha`, `to_sha`,
/// `backup_path`, ...) this app never renders (§"no raw Git error text on
/// screen" — task 210) and Swift's synthesized `Decodable` already drops,
/// same discipline as `Checker`'s own doc comment in this file's header.
struct CompletedAction: Decodable {
    let kind: String
    let target: String
    let outcome: CompletedActionOutcome
    let summary: String
}

/// Only present when `result == "blocked"`. `safeToRerun` answers "will a
/// retry be SAFE (never-destroy — it adopts rather than recreates)", never
/// "will a retry actually get past this block" — that second question is
/// answered by the blocked stage's own `layers`/row `action`/`sync_state`
/// (a Git-history review row never changes on retry regardless of this
/// flag). See `WizardModel.holdingInfo(forBlockedOnboard:)`, task 210/G-7.
struct ResumeHint: Decodable {
    let safeToRerun: Bool
    let detail: String
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
    let unit: String?
    let repositoryOwner: String?
    let repositoryName: String?
    let repositoryVisibility: String?
    let remoteState: String?
    let localPath: String?
    let localState: String?
    let connectionState: String?
    let syncState: String?
    let action: String?
    let detail: String?
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
    /// The complete CSE component set the aggregate transaction provisions.
    /// This is intentionally distinct from `products`, which remains the
    /// person's selected assistant runtimes (Claude and optionally Codex).
    let components: [String]
    let stages: [EcosystemOnboardStage]
    /// Discriminates `layers`' two legal shapes (task 208/G-5): `reported`
    /// means topology was actually computed for this exit and `layers`
    /// carries at least one fully-populated row; `not-computed` means this
    /// exit returned before topology could be computed at all and `layers`
    /// is `[]`. Read THIS field before ever branching on `layers.isEmpty` —
    /// an empty array alone is never itself meaningful evidence of absence.
    let layersState: EcosystemLayersState
    let layers: [EcosystemOnboardLayer]
    let inventory: [EcosystemInventoryItem]?
    let inventorySummary: EcosystemInventorySummary?
    /// Every mutation this run actually completed, attempted, or rolled
    /// back, in the order it happened — always present, possibly empty. A
    /// "nothing was changed" claim may only ever be rendered when this is
    /// empty (task 211/G-4b); see `WizardModel.hasCompletedWork(_:)` and
    /// every Holding H3 branch that now threads this through.
    let completedActions: [CompletedAction]
    /// Present only when `result == "blocked"` (schema's own conditional
    /// requirement — see this section's header comment on why this stays
    /// optional rather than required).
    let resume: ResumeHint?
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

enum WorkspaceIntegrationClassification: String, Decodable {
    case ready
    case safeFinish = "safe-finish"
    case guidedIntegration = "guided-integration"
    case ownerDecision = "owner-decision"
    case couldNotVerify = "could-not-verify"
}

enum WorkspaceResponsibleActor: String, Decodable {
    case none
    case cli
    case projectAuthor = "project-author"
    case projectOwner = "project-owner"
    case ecosystemOwner = "ecosystem-owner"
    case person
}

enum WorkspaceComponentName: String, Decodable {
    case claude
    case codex
}

struct WorkspaceExpectedContract: Decodable {
    let id: String
    let version: String
}

enum WorkspaceEvidenceKind: String, Decodable {
    case marker
    case manifest
    case frameworkFile = "framework-file"
    case projectFile = "project-file"
    case link
    case lockRecord = "lock-record"
}

enum WorkspaceEvidenceState: String, Decodable {
    case verified
    case missing
    case mismatch
    case unreadable
}

struct WorkspaceEvidence: Decodable {
    let kind: WorkspaceEvidenceKind
    let path: String
    let state: WorkspaceEvidenceState
    let detail: String
}

struct WorkspaceRecognizedSetup: Decodable {
    let variantId: String
    let version: String
    let evidence: [WorkspaceEvidence]
}

struct WorkspaceMissingRequirement: Decodable {
    let id: String
    let detail: String
}

struct WorkspaceVerification: Decodable {
    let command: [String]
    let expected: String
    let stopConditions: [String]
}

enum WorkspaceArtifactKind: String, Decodable {
    case instruction
    case agent
    case skill
    case command
    case plugin
    case config
    case manifest
    case projectFile = "project-file"
}

struct WorkspaceArtifact: Decodable {
    let kind: WorkspaceArtifactKind
    let path: String
    let detail: String
}

enum WorkspaceSafeActionKind: String, Decodable {
    case adoptExisting = "adopt-existing"
    case addMissing = "add-missing"
    case repairKnown = "repair-known"
    case composite
}

struct WorkspaceSafeAction: Decodable {
    let id: String
    let inspectionId: String
    let kind: WorkspaceSafeActionKind
    let components: [WorkspaceComponentName]
    let detail: String
    let applyVerb: String
    let willAdd: [WorkspaceArtifact]
    let willPreserve: [WorkspaceArtifact]
    let willNotChange: [WorkspaceArtifact]
    let verification: WorkspaceVerification
}

struct WorkspaceInspection: Decodable {
    let id: String
    let contractId: String
    let contractVersion: String
    let scope: String
    let complete: Bool
}

struct WorkspaceCapabilities: Decodable {
    let instructions: Int
    let agents: Int
    let skills: Int
    let commands: Int
    let plugins: Int
    let integrationPaths: [String]
}

struct WorkspacePreservation: Decodable {
    let mustPreserve: [WorkspaceArtifact]
    let prohibitedActions: [String]
}

struct WorkspacePlanText: Decodable {
    let version: String
    let text: String
}

struct WorkspaceIntegrationPlan: Decodable {
    let id: String
    let inspectionId: String
    let responsibleActor: WorkspaceResponsibleActor
    let detected: [String]
    let missing: [String]
    let preserve: [String]
    let prohibited: [String]
    let prompt: WorkspacePlanText?
    let ownerHandoff: WorkspacePlanText?
    let verification: WorkspaceVerification
    let stopConditions: [String]
}

struct WorkspaceDiagnostic: Decodable {
    let id: String
    let inspectionId: String
    let mode: String
    let prompt: WorkspacePlanText
    let verification: WorkspaceVerification
    let stopConditions: [String]
}

struct WorkspaceComponentAssessment: Decodable {
    let component: WorkspaceComponentName
    let expected: Bool
    let expectedContract: WorkspaceExpectedContract
    let classification: WorkspaceIntegrationClassification
    let recognizedSetup: WorkspaceRecognizedSetup?
    let missingRequirements: [WorkspaceMissingRequirement]
    let responsibleActor: WorkspaceResponsibleActor
    let safeAction: WorkspaceSafeAction?
    let verification: WorkspaceVerification
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
    /// Authoritative schema-1.1 integration facts. Control Tower renders
    /// these values and passes opaque action/plan ids back to `cc`; it never
    /// derives a classification from paths, counts, or component evidence.
    let classification: WorkspaceIntegrationClassification
    let responsibleActor: WorkspaceResponsibleActor
    let inspection: WorkspaceInspection
    let components: [WorkspaceComponentAssessment]
    let capabilities: WorkspaceCapabilities
    let preservation: WorkspacePreservation
    let safeAction: WorkspaceSafeAction?
    let planAvailable: Bool
    let integrationPlan: WorkspaceIntegrationPlan?
    /// Optional for backward compatibility with cc 1.7.12. Newer helpers
    /// supply this only for a detail-scoped could-not-verify result.
    let diagnostic: WorkspaceDiagnostic?
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

struct WorkspaceClassificationSummary: Decodable {
    let ready: Int
    let safeFinish: Int
    let guidedIntegration: Int
    let ownerDecision: Int
    let couldNotVerify: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case ready, total
        case safeFinish = "safe-finish"
        case guidedIntegration = "guided-integration"
        case ownerDecision = "owner-decision"
        case couldNotVerify = "could-not-verify"
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
    let classificationSummary: WorkspaceClassificationSummary
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

// MARK: - reconcile response schema 2.0 / request schema 1.0

/// Explicit user intent passed to Python. These request DTOs contain no
/// discovery, eligibility, default-selection, or path-normalization logic.
/// The helper validates and canonicalizes the exact bytes before inspecting
/// or mutating any ecosystem state.
enum ReconciliationComponent: String, Codable, Hashable {
    case claude
    case codex
}

struct ReconciliationProjectSelection: Encodable {
    let path: String
    let components: [ReconciliationComponent]
    let recipeIds: [ReconciliationComponent: String]

    init(
        path: String,
        components: [ReconciliationComponent],
        recipeIds: [ReconciliationComponent: String] = [:]
    ) {
        self.path = path
        self.components = components
        self.recipeIds = recipeIds
    }

    enum CodingKeys: String, CodingKey {
        case path, components, recipeIds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(components, forKey: .components)
        if !recipeIds.isEmpty {
            let wireRecipeIds = Dictionary(
                uniqueKeysWithValues: recipeIds.map { ($0.key.rawValue, $0.value) }
            )
            try container.encode(wireRecipeIds, forKey: .recipeIds)
        }
    }
}

enum ReconciliationBatchCategory: String, Decodable {
    case newSetup = "new-setup"
    case correction
}

struct ReconciliationDefaultSelection: Decodable {
    let path: String
    let components: [ReconciliationComponent]
    let category: ReconciliationBatchCategory
    let recipeIds: [ReconciliationComponent: String]

    enum CodingKeys: String, CodingKey {
        case path, components, category, recipeIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        let decodedComponents = try container.decode(
            [ReconciliationComponent].self,
            forKey: .components
        )
        guard decodedComponents == [.claude]
                || decodedComponents == [.codex]
                || decodedComponents == [.claude, .codex] else {
            throw DecodingError.dataCorruptedError(
                forKey: .components,
                in: container,
                debugDescription: "Selection components must be Claude, Codex, or Claude then Codex."
            )
        }
        components = decodedComponents
        category = try container.decode(ReconciliationBatchCategory.self, forKey: .category)
        let wireRecipeIds = try container.decodeIfPresent(
            [String: String].self,
            forKey: .recipeIds
        ) ?? [:]
        var decodedRecipeIds: [ReconciliationComponent: String] = [:]
        for (key, value) in wireRecipeIds {
            guard let component = ReconciliationComponent(rawValue: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .recipeIds,
                    in: container,
                    debugDescription: "Default recipe keys must name Claude or Codex."
                )
            }
            decodedRecipeIds[component] = value
        }
        recipeIds = decodedRecipeIds
    }

    var requestSelection: ReconciliationProjectSelection {
        ReconciliationProjectSelection(
            path: path,
            components: components,
            recipeIds: recipeIds
        )
    }
}

/// Assistant selections use the same Python-authored shape as deterministic
/// selections. Swift preserves the exact component and optional recipe scope;
/// it never widens a Claude-only or Codex-only proposal to both components.
typealias ReconciliationAssistantSelection = ReconciliationDefaultSelection

struct ReconciliationLeftUnchangedSummary: Decodable {
    let held: Int
    let ownerDecision: Int
    let couldNotVerify: Int
    let excluded: Int
    let sourceUnavailable: Int
    let other: Int
}

/// Python-authored, mutually exclusive presentation counts for the default
/// reconciliation surface. Swift displays these values without attempting to
/// rebuild them from project routes.
struct ReconciliationResolutionSummary: Decodable {
    let automatic: Int
    let claudeAssisted: Int
    let totalActionable: Int
    let managedSeparately: Int
    let leftUnchanged: ReconciliationLeftUnchangedSummary
    let newSetup: Int
    let correction: Int
}

struct ReconciliationBatchSummary: Decodable {
    let newSetup: Int
    let correction: Int
    let ready: Int
    let needsReview: Int
    let selected: Int
    let total: Int
    let productProjects: Int
    let managedSeparately: Int
}

struct ReconciliationMachineSummary: Decodable {
    let state: ReconciliationMachineState
    let title: String
    let detail: String
}

struct ReconciliationRequest: Encodable {
    let schemaVersion: String
    let roots: [String]
    let projects: [ReconciliationProjectSelection]
    let assistantProposalId: String?

    init(
        roots: [String],
        projects: [ReconciliationProjectSelection],
        assistantProposalId: String? = nil
    ) {
        schemaVersion = "1.0"
        self.roots = roots
        self.projects = projects
        self.assistantProposalId = assistantProposalId
    }

    /// Preserve the exact root/project/component request while attaching the
    /// one opaque Python-validated proposal chosen by assistant-status.
    func attachingAssistantProposal(_ proposalId: String) -> ReconciliationRequest {
        ReconciliationRequest(
            roots: roots,
            projects: projects,
            assistantProposalId: proposalId
        )
    }

    /// Deterministic serialization only. Python remains authoritative for
    /// normalization, validation, fingerprints, and every ecosystem decision.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

struct ReconciliationEvidence: Decodable {
    let id: String
    let state: String
    let detail: String
}

struct ReconciliationBlocker: Decodable {
    let code: String
    let responsibleActor: String
    let evidence: [ReconciliationEvidence]
    let nextAction: String
}

struct ReconciliationRecipeOption: Decodable {
    let recipeId: String
    let component: ReconciliationComponent
    let summary: String
}

enum ReconciliationProjectPresence: String, Decodable {
    case none
    case claudeOnly = "claude-only"
    case codexOnly = "codex-only"
    case both
    case unknown
}

enum ReconciliationProjectRoute: String, Decodable {
    case ready
    case copilotNotPresent = "copilot-not-present"
    case safeSetupAvailable = "safe-setup-available"
    case safeUpdateAvailable = "safe-update-available"
    case customizedGuidedRoute = "customized-guided-route"
    case held
    case ownerDecision = "owner-decision"
    case couldNotVerify = "could-not-verify"
    case excluded
    case sourceUnavailable = "source-unavailable"
    case ecosystemManaged = "ecosystem-managed"
}

enum ReconciliationComponentRoute: String, Decodable {
    case ready
    case notPresent = "not-present"
    case notSelected = "not-selected"
    case safeSetupAvailable = "safe-setup-available"
    case safeUpdateAvailable = "safe-update-available"
    case customizedGuidedRoute = "customized-guided-route"
    case held
    case ownerDecision = "owner-decision"
    case couldNotVerify = "could-not-verify"
    case excluded
    case sourceUnavailable = "source-unavailable"
    case notApplicable = "not-applicable"
}

struct ReconciliationComponentAssessment: Decodable {
    let component: ReconciliationComponent
    let state: ReconciliationComponentRoute
    let selected: Bool
    let recommended: Bool
    let recommendationReason: String
    let responsibleActor: String
    let evidence: [ReconciliationEvidence]
    let missingRequirements: [ReconciliationEvidence]
    let nextAction: String
    let recipeOptions: [ReconciliationRecipeOption]
}

struct ReconciliationArtifact: Decodable {
    let kind: String
    let path: String
    let detail: String
}

struct ReconciliationDossier: Decodable {
    let inspectionId: String
    let currentEvidence: [ReconciliationEvidence]
    let missingRequirements: [ReconciliationEvidence]
    let preservation: [ReconciliationArtifact]
    let allowedTargets: [String]
    let prohibitedActions: [String]
    let verification: [String]
    let stopConditions: [String]
}

enum ReconciliationEcosystemProduct: String, Decodable {
    case claude
    case codex
    case knowledge
    case cli
}

/// Scope is authored from manifest-plus-origin evidence by Python. The custom
/// decoder makes each conditional branch required: an ecosystem repository
/// without its complete provenance never degrades into a product project.
enum ReconciliationRepositoryScope: Decodable {
    case productProject
    case ecosystemRepository(
        product: ReconciliationEcosystemProduct,
        role: String,
        layerId: String,
        repository: String
    )

    private enum Kind: String, Decodable {
        case productProject = "product-project"
        case ecosystemRepository = "ecosystem-repository"
    }

    private enum CodingKeys: String, CodingKey {
        case kind, product, role, layerId, repository
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .productProject:
            guard !container.contains(.product),
                  !container.contains(.role),
                  !container.contains(.layerId),
                  !container.contains(.repository) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "Product-project scope cannot carry ecosystem provenance."
                )
            }
            self = .productProject
        case .ecosystemRepository:
            let product = try container.decode(
                ReconciliationEcosystemProduct.self,
                forKey: .product
            )
            let role = try container.decode(String.self, forKey: .role)
            let layerId = try container.decode(String.self, forKey: .layerId)
            let repository = try container.decode(String.self, forKey: .repository)
            let repositoryParts = repository.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            guard !role.isEmpty,
                  !layerId.isEmpty,
                  repositoryParts.count == 2,
                  repositoryParts.allSatisfy({ !$0.isEmpty }) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .repository,
                    in: container,
                    debugDescription: "Ecosystem repository scope is incomplete."
                )
            }
            self = .ecosystemRepository(
                product: product,
                role: role,
                layerId: layerId,
                repository: repository
            )
        }
    }

    var isEcosystemRepository: Bool {
        if case .ecosystemRepository = self { return true }
        return false
    }
}

struct ReconciliationProject: Decodable {
    let path: String
    let root: String
    let name: String
    let scope: ReconciliationRepositoryScope
    let inspectionId: String
    let presence: ReconciliationProjectPresence
    let route: ReconciliationProjectRoute
    let selectedComponents: [ReconciliationComponent]
    let components: [ReconciliationComponentAssessment]
    let blockers: [ReconciliationBlocker]
    let nextAction: String
    let dossier: ReconciliationDossier?
}

enum ReconciliationMachineState: String, Decodable {
    case ready
    case actionRequired = "action-required"
    case couldNotVerify = "could-not-verify"
}

struct ReconciliationHelper: Decodable {
    let state: String
    let version: String?
    let path: String?
    let detail: String
}

struct ReconciliationFramework: Decodable {
    let component: ReconciliationComponent
    let state: String
    let path: String?
    let version: String?
    let detail: String
}

struct ReconciliationConfiguration: Decodable {
    let state: String
    let path: String?
    let approvedRoots: [String]
    let detail: String
}

struct ReconciliationAuthentication: Decodable {
    let state: String
    let credentialState: String
    let detail: String
}

struct ReconciliationConnectivity: Decodable {
    let state: String
    let detail: String
}

struct ReconciliationLayers: Decodable {
    let state: String
    let ready: Int
    let total: Int
    let detail: String
}

struct ReconciliationDependency: Decodable {
    let id: String
    let state: String
    let detail: String
}

struct ReconciliationMachine: Decodable {
    let state: ReconciliationMachineState
    let helper: ReconciliationHelper
    let frameworks: [ReconciliationFramework]
    let configuration: ReconciliationConfiguration
    let authentication: ReconciliationAuthentication
    let connectivity: ReconciliationConnectivity
    let layers: ReconciliationLayers
    let dependencies: [ReconciliationDependency]
    let blockers: [ReconciliationBlocker]
    let nextAction: String
}

struct ReconciliationProjectCounts: Decodable {
    let ready: Int
    let copilotNotPresent: Int
    let safeSetupAvailable: Int
    let safeUpdateAvailable: Int
    let customizedGuidedRoute: Int
    let held: Int
    let ownerDecision: Int
    let couldNotVerify: Int
    let excluded: Int
    let sourceUnavailable: Int
    let ecosystemManaged: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case ready, held, excluded, total
        case copilotNotPresent = "copilot-not-present"
        case safeSetupAvailable = "safe-setup-available"
        case safeUpdateAvailable = "safe-update-available"
        case customizedGuidedRoute = "customized-guided-route"
        case ownerDecision = "owner-decision"
        case couldNotVerify = "could-not-verify"
        case sourceUnavailable = "source-unavailable"
        case ecosystemManaged = "ecosystem-managed"
    }
}

struct ReconciliationScopeCounts: Decodable {
    let totalRepositories: Int
    let productProjects: Int
    let ecosystemRepositories: Int
}

struct ReconciliationSummary: Decodable {
    let projectCounts: ReconciliationProjectCounts
    let scopeCounts: ReconciliationScopeCounts
    let selectedProjects: Int
    let overlapExplanation: String
}

enum ReconciliationOperationKind: String, Decodable {
    case createFileFromSource = "create-file-from-source"
    case copyFileFromSource = "copy-file-from-source"
    case copyTreeFromSource = "copy-tree-from-source"
    case appendManagedBlock = "append-managed-block"
    case mergeJSONKeys = "merge-json-keys"
    case replaceRecognizedSymlinkWithCopy = "replace-recognized-symlink-with-copy"
    case createInternalRelativeSymlink = "create-internal-relative-symlink"
    case upsertLockComponent = "upsert-lock-component"
    case writeProjectDeclaration = "write-project-declaration"
    case associatePersonalProject = "associate-personal-project"
}

struct ReconciliationOperation: Decodable {
    let id: String
    let kind: ReconciliationOperationKind
    let component: ReconciliationComponent
    let target: String
    let description: String
    let expectedBeforeFingerprint: String
    let sourceFingerprint: String?
}

struct ReconciliationRecipeBinding: Decodable {
    let component: ReconciliationComponent
    let recipeId: String
}

struct ReconciliationSourceBinding: Decodable {
    let component: ReconciliationComponent
    let version: String
    let fingerprint: String
}

struct ReconciliationProjectPlan: Decodable {
    let path: String
    let inspectionId: String
    let recipes: [ReconciliationRecipeBinding]
    let sources: [ReconciliationSourceBinding]
    let operations: [ReconciliationOperation]
    let preservation: [ReconciliationArtifact]
    let prohibitedActions: [String]
    let verification: [String]
}

enum ReconciliationRollbackStatus: String, Decodable {
    case restored
    case mismatch
    case conflict
    case unreadable
}

struct ReconciliationRollbackTarget: Decodable {
    let target: String
    let status: ReconciliationRollbackStatus
    let detail: String
}

enum ReconciliationLedgerStatus: String, Decodable {
    case applied
    case blocked
    case rolledBack = "rolled-back"
    case incompleteRollback = "incomplete-rollback"
    case unchanged
}

enum ReconciliationVerificationState: String, Decodable {
    case ready
    case failed
    case notRun = "not-run"
}

struct ReconciliationLedgerEntry: Decodable {
    let path: String
    let status: ReconciliationLedgerStatus
    let detail: String
    let completedOperationIds: [String]
    let verification: ReconciliationVerificationState
    let rollback: [ReconciliationRollbackTarget]
}

enum ReconciliationDiagnosticState: String, Decodable {
    case available
    case unavailable
}

struct ReconciliationDiagnosticReference: Decodable {
    let schemaVersion: String
    let id: String
    let state: ReconciliationDiagnosticState
    let path: String?
    let createdAt: String
    let detail: String
}

enum ReconciliationAssessPhase: String, Decodable { case assess }
enum ReconciliationAssistantPreparePhase: String, Decodable {
    case assistantPrepare = "assistant-prepare"
}
enum ReconciliationAssistantStatusPhase: String, Decodable {
    case assistantStatus = "assistant-status"
}
enum ReconciliationPlanPhase: String, Decodable { case plan }
enum ReconciliationApplyPhase: String, Decodable { case apply }
enum ReconciliationVerifyPhase: String, Decodable { case verify }
enum ReconciliationRecoverPhase: String, Decodable { case recover }
enum ReconciliationErrorPhase: String, Decodable { case error }

enum ReconciliationReadResult: String, Decodable {
    case ready
    case actionRequired = "action-required"
    case blocked
}

enum ReconciliationAssistantPrepareResult: String, Decodable { case ready }

enum ReconciliationAssistantStatusResult: String, Decodable {
    case running
    case ready
    case blocked
}

enum ReconciliationAssistantProgressStage: String, Decodable {
    case sessionPrepared = "session-prepared"
    case claudeCodeRunning = "claude-code-running"
    case pythonValidatingSelections = "python-validating-selections"
    case pythonValidatingPlan = "python-validating-plan"
    case ready
    case blocked
}

enum ReconciliationAssistantLiveness: String, Decodable {
    case waiting
    case active
    case stale
    case complete
    case blocked
}

struct ReconciliationAssistantProgress: Decodable {
    let stage: ReconciliationAssistantProgressStage
    let liveness: ReconciliationAssistantLiveness
    let detail: String
    let startedAt: String
    let lastActivityAt: String
    let elapsedSeconds: Int
    let selectedProjectCount: Int
    let candidateGroupCount: Int
    let candidateCount: Int

    func isConsistent(with result: ReconciliationAssistantStatusResult) -> Bool {
        switch result {
        case .running:
            return stage != .ready
                && stage != .blocked
                && liveness != .complete
                && liveness != .blocked
        case .ready:
            return stage == .ready && liveness == .complete
        case .blocked:
            return stage == .blocked && liveness == .blocked
        }
    }
}

enum ReconciliationApplyResult: String, Decodable {
    case applied
    case partial
    case blocked
}

enum ReconciliationRecoverResult: String, Decodable {
    case ready
    case partial
    case blocked
}

struct ReconciliationAssessReport: Decodable {
    let schemaVersion: String
    let phase: ReconciliationAssessPhase
    let result: ReconciliationReadResult
    let runId: String
    let generatedAt: String
    let machine: ReconciliationMachine
    let machineSummary: ReconciliationMachineSummary
    let projects: [ReconciliationProject]
    let defaultSelection: [ReconciliationDefaultSelection]
    let assistantSelection: [ReconciliationAssistantSelection]
    let batchSummary: ReconciliationBatchSummary
    let resolutionSummary: ReconciliationResolutionSummary
    let summary: ReconciliationSummary
    let nextActions: [String]

    /// The complete default-all set is the union of Python's two authored
    /// lists. This is membership plumbing only; Swift does not add, classify,
    /// or infer an eligible project.
    var authorizedSelectionPaths: Set<String> {
        Set(defaultSelection.map(\.path) + assistantSelection.map(\.path))
    }

    var authoredSelectionCount: Int {
        defaultSelection.count + assistantSelection.count
    }

    func requestSelections(selectedPaths: Set<String>) -> [ReconciliationProjectSelection] {
        defaultSelection.compactMap { selection in
            selectedPaths.contains(selection.path) ? selection.requestSelection : nil
        } + assistantSelection.compactMap { selection in
            selectedPaths.contains(selection.path) ? selection.requestSelection : nil
        }
    }
}

struct ReconciliationAssistantPrepareReport: Decodable {
    let schemaVersion: String
    let phase: ReconciliationAssistantPreparePhase
    let result: ReconciliationAssistantPrepareResult
    let runId: String
    let generatedAt: String
    let sessionId: String
    let expiresAt: String
    let selectedProjects: [String]
    let progress: ReconciliationAssistantProgress
    let nextActions: [String]

    func matches(request: ReconciliationRequest) -> Bool {
        selectedProjects == request.projects.map(\.path)
            && progress.stage == .sessionPrepared
            && progress.liveness == .waiting
            && progress.selectedProjectCount == selectedProjects.count
    }
}

enum ReconciliationAssistantStatusTransition: Equatable {
    case running
    case ready(proposalId: String)
    case blocked(detail: String)
    case incompatible
}

struct ReconciliationAssistantStatusReport: Decodable {
    let schemaVersion: String
    let phase: ReconciliationAssistantStatusPhase
    let result: ReconciliationAssistantStatusResult
    let runId: String
    let generatedAt: String
    let sessionId: String
    let proposalId: String?
    let selectedProjects: [String]
    let progress: ReconciliationAssistantProgress
    let detail: String
    let nextActions: [String]

    func transition(
        expectedSessionId: String,
        request: ReconciliationRequest
    ) -> ReconciliationAssistantStatusTransition {
        guard sessionId == expectedSessionId,
              selectedProjects == request.projects.map(\.path),
              progress.selectedProjectCount == selectedProjects.count,
              progress.isConsistent(with: result) else {
            return .incompatible
        }
        switch result {
        case .running:
            return proposalId == nil ? .running : .incompatible
        case .ready:
            guard let proposalId, !proposalId.isEmpty else { return .incompatible }
            return .ready(proposalId: proposalId)
        case .blocked:
            return proposalId == nil ? .blocked(detail: detail) : .incompatible
        }
    }
}

struct ReconciliationPlanReport: Decodable {
    let schemaVersion: String
    let phase: ReconciliationPlanPhase
    let result: ReconciliationReadResult
    let runId: String
    let generatedAt: String
    let machine: ReconciliationMachine
    let projects: [ReconciliationProject]
    let summary: ReconciliationSummary
    let nextActions: [String]
    let requestFingerprint: String
    let planId: String
    let expiresAt: String
    let plans: [ReconciliationProjectPlan]
}

struct ReconciliationApplyReport: Decodable {
    let schemaVersion: String
    let phase: ReconciliationApplyPhase
    let result: ReconciliationApplyResult
    let runId: String
    let generatedAt: String
    let machine: ReconciliationMachine
    let projects: [ReconciliationProject]
    let summary: ReconciliationSummary
    let nextActions: [String]
    let requestFingerprint: String
    let requestedPlanId: String
    let planId: String
    let ledger: [ReconciliationLedgerEntry]
    let diagnostics: ReconciliationDiagnosticReference
}

struct ReconciliationVerifyReport: Decodable {
    let schemaVersion: String
    let phase: ReconciliationVerifyPhase
    let result: ReconciliationReadResult
    let runId: String
    let generatedAt: String
    let machine: ReconciliationMachine
    let projects: [ReconciliationProject]
    let summary: ReconciliationSummary
    let nextActions: [String]
    let requestFingerprint: String
}

enum ReconciliationRecoveryOutcome: String, Decodable {
    case applied
    case rolledBack = "rolled-back"
    case blocked
    case incompleteRollback = "incomplete-rollback"
}

struct ReconciliationRecoveryEntry: Decodable {
    let interruptedRunId: String
    let requestedPlanId: String
    let outcome: ReconciliationRecoveryOutcome
    let ledger: [ReconciliationLedgerEntry]
    let diagnostics: ReconciliationDiagnosticReference
}

struct ReconciliationRecoverReport: Decodable {
    let schemaVersion: String
    let phase: ReconciliationRecoverPhase
    let result: ReconciliationRecoverResult
    let runId: String
    let generatedAt: String
    let recoveries: [ReconciliationRecoveryEntry]
    let nextActions: [String]
}

enum ReconciliationErrorResult: String, Decodable { case error }

struct ReconciliationErrorBody: Decodable {
    let code: String
    let detail: String
}

struct ReconciliationErrorReport: Decodable {
    let schemaVersion: String
    let phase: ReconciliationErrorPhase
    let result: ReconciliationErrorResult
    let exitCode: Int
    let error: ReconciliationErrorBody
}

/// Reconcile's schema defines structured error reports for both exit 1 and
/// exit 2. Preserve those Python-authored details as a renderable outcome;
/// `CliError` remains reserved for launch, schema, and decode failures where
/// no compatible reconciliation truth is available.
enum ReconciliationOutcome<Report: Decodable>: Decodable {
    case report(Report)
    case error(ReconciliationErrorReport)

    init(from decoder: Decoder) throws {
        if let error = try? ReconciliationErrorReport(from: decoder) {
            self = .error(error)
        } else {
            self = .report(try Report(from: decoder))
        }
    }
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
