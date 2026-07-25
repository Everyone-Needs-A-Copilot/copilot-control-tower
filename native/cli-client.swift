//
// Copilot Control Tower — the CLI seam.
//
// This file is the ONE place in the app that ever spawns the `copilot`/`cc`
// CLI. Everything downstream (`native/render-state.swift`, the tray, the
// wizard, admin) renders `CliClient`'s typed results; nothing else in this
// app touches `Process` for a CLI invocation. That is invariant #1
// ("Parse, never compute" — `CLAUDE.md`): Control Tower calls versioned
// `--json` verbs and renders the result, never resolves/syncs/computes
// ecosystem state itself.
//
// Contract source of truth: `docs/01-architecture/cli-contract.md` and the
// versioned schemas in `docs/01-architecture/schemas/`. The DTOs this file's
// typed verbs decode into live in `native/cli-dtos.swift` (split out to keep
// this file to "how do I call the CLI", not "what does it hand back").
//
// SECURITY / FAIL-CLOSED NOTES (see `CLAUDE.md` invariant #4):
//   - The CLI is NEVER invoked via a shell (`no shell, no -lc`). `Process`
//     is given an absolute `executableURL` and a plain `[String]` argument
//     array — no string ever gets anywhere near `/bin/sh`.
//   - The CLI path itself is never a bare name (`cc`/`copilot`) that would
//     resolve through `$PATH` at exec time — see `CliLocator` below.
//   - `SchemaGate` decodes ONLY `schema_version` before trusting any other
//     field of a response, so a schema-out-of-range payload never gets far
//     enough to leak a stale/attacker-shaped field into the render layer.
//   - Exit code 2 is the CLI's own "trust nothing but this envelope" signal
//     (env/credential error) — the body is decoded ONLY as the shared
//     `{schema_version, error:{code,message}}` envelope in that case, never
//     as the verb's normal success shape.
//
// CRITICAL SwiftUI/AppKit ordering constraint (see `.claude/memory` and this
// repo's other `native/*.swift` file headers): nothing in this file may be
// invoked from a SwiftUI `@State`/`@StateObject` `init()`. `CliClient` is a
// plain `actor` (not `@MainActor`), so every one of its methods already runs
// off the main actor/thread by default; the one exception (Process spawning)
// additionally hops to a background `DispatchQueue` explicitly below, so
// this is safe to call from a view's `.task { }` or a button action, never
// from a property-wrapper initializer.

import Foundation

// MARK: - Shared process-pipe plumbing
//
// `LineFramer`/`ProcessDrain` live here (not in `native/admin.swift`, where
// `ShellRunner` also uses them) because this is the one process-utility file
// compiled into BOTH the User build (`scripts/build-user.command`) and the
// Admin build (`scripts/build-admin.command`); `native/admin.swift` is
// Admin-only.

/// Frames arbitrary incremental byte chunks into complete lines, splitting on
/// `\n` (a trailing `\r` is trimmed so CRLF output frames the same as LF).
/// A partial line is held until either a later chunk completes it or
/// `flush()` delivers it as-is (e.g. at end-of-stream), so a final line with
/// no trailing newline is still delivered exactly once, never dropped.
/// Callers feed it from a single serial source (one pipe's readability
/// handler, invoked serially by construction) — this is not safe to `feed`
/// from more than one thread at a time.
final class LineFramer {
    private var buffer = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func feed(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        buffer.append(chunk)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            emit(buffer[buffer.startIndex..<newlineIndex])
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
        }
    }

    /// Delivers any held partial line (no trailing newline) exactly once —
    /// call this once, at end-of-stream. A no-op when nothing is held.
    func flush() {
        guard !buffer.isEmpty else { return }
        emit(buffer[buffer.startIndex...])
        buffer.removeAll()
    }

    private func emit(_ lineData: Data.SubSequence) {
        var trimmed = lineData
        if trimmed.last == 0x0D { trimmed = trimmed.dropLast() }
        onLine(String(decoding: trimmed, as: UTF8.self))
    }
}

/// Shared pipe-draining core for every child process this app spawns
/// (`CliClient.runRaw` below and `native/admin.swift`'s `ShellRunner`). Both
/// runners used to either call `waitUntilExit()` before reading their pipes
/// at all, or drain stdout and stderr strictly one after the other — either
/// way, a child that writes more than one pipe buffer's worth (64KB) to
/// BOTH streams can deadlock: it blocks on a full pipe write while nothing
/// is reading that pipe. Draining both pipes concurrently via
/// `readabilityHandler`, independent of when `waitUntilExit()` is called,
/// makes that deadlock structurally impossible here, not just unlikely.
enum ProcessDrain {
    struct Result {
        let stdout: Data
        let stderr: Data
        /// True when `timeout` elapsed and the process was killed rather
        /// than exiting on its own. The caller's `terminationStatus` in
        /// that case reflects the kill, not a real program outcome.
        let timedOut: Bool
    }

    /// `process` must already be running (`try process.run()` already
    /// called) with `stdoutPipe`/`stderrPipe` set as its `standardOutput`/
    /// `standardError`. `onStdoutLine`, when non-nil, is fed every stdout
    /// chunk through a `LineFramer` as it arrives — purely additive, the
    /// returned `stdout` still carries the complete accumulated output
    /// either way, so an existing non-streaming caller is unaffected.
    /// `timeout`, when non-nil and positive, terminates the process and
    /// sets `timedOut` if it has not exited within that many seconds,
    /// instead of waiting forever.
    static func run(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        timeout: TimeInterval?,
        onStdoutLine: ((String) -> Void)?
    ) -> Result {
        let outHandle = stdoutPipe.fileHandleForReading
        let errHandle = stderrPipe.fileHandleForReading
        let outDrained = DispatchSemaphore(value: 0)
        let errDrained = DispatchSemaphore(value: 0)
        let lineFramer = onStdoutLine.map(LineFramer.init(onLine:))

        // Each pipe is drained by a BLOCKING read loop on its own dedicated
        // thread, and deliberately NOT by `readabilityHandler`.
        //
        // This function blocks its caller until the child exits. A handler
        // that never gets scheduled cannot drain, the pipe buffer fills, the
        // child blocks forever on its next write, and so it never exits —
        // which means the wait below never returns either. That deadlock is
        // not hypothetical: it hung every single CLI call and was only caught
        // by `scripts/tests/smoke-cli.sh`, because the in-binary bundle
        // self-tests never spawn a real child. Draining must never depend on
        // the caller's thread being free to service callbacks.
        //
        // `availableData` blocks until at least one byte is readable and
        // returns empty exactly at EOF, so each loop ends on its own when the
        // child's pipe closes.
        //
        // The accumulators are each touched by exactly one thread before its
        // semaphore is signalled, and read by the caller only after both
        // waits below have returned — that ordering is the synchronisation.
        // NOTE: `onStdoutLine` is therefore invoked on a background thread;
        // callers that touch UI state must hop to the main actor themselves.
        nonisolated(unsafe) var outData = Data()
        nonisolated(unsafe) var errData = Data()

        let drainQueue = DispatchQueue(label: "control-tower.process-drain", attributes: .concurrent)
        drainQueue.async {
            while case let chunk = outHandle.availableData, !chunk.isEmpty {
                outData.append(chunk)
                lineFramer?.feed(chunk)
            }
            lineFramer?.flush()
            outDrained.signal()
        }
        drainQueue.async {
            while case let chunk = errHandle.availableData, !chunk.isEmpty {
                errData.append(chunk)
            }
            errDrained.signal()
        }

        // `waitUntilExit()` blocks its caller until the process exits; on
        // its own dedicated task, this call can race against `timeout`
        // below instead of hanging this whole function with it.
        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            exited.signal()
        }

        var timedOut = false
        if let timeout, timeout > 0 {
            if exited.wait(timeout: .now() + timeout) == .timedOut {
                timedOut = true
                process.terminate()
                _ = exited.wait(timeout: .now() + 5)
            }
        } else {
            exited.wait()
        }

        // Both read loops hit EOF once the child's pipes close, which happens
        // at or just after exit. Bounded anyway, so a pipe held open by some
        // surviving grandchild degrades to truncated output instead of a hang.
        _ = outDrained.wait(timeout: .now() + 5)
        _ = errDrained.wait(timeout: .now() + 5)

        return Result(stdout: outData, stderr: errData, timedOut: timedOut)
    }
}

// MARK: - Locating the CLI binary

/// Resolves the absolute path to the `cc` CLI binary this app supervises.
/// NEVER returns a bare command name — the caller (`CliClient.runRaw`) hands
/// this straight to `Process.executableURL`, which does not consult `$PATH`,
/// so a bare name here would simply fail to launch rather than silently
/// resolving to an attacker-controlled binary earlier on `$PATH`. That is the
/// point: this app decides which `cc` it trusts, `$PATH` does not decide for
/// it.
enum CliLocator {
    /// Dev/test override — wins over every standard location, but ONLY when
    /// it actually points at an executable file. An unset or non-executable
    /// override is not an error here; it just falls through to the standard
    /// search below (the standard locations remain a legitimate real-machine
    /// answer even when a stale/typo'd `CT_CLI_PATH` is sitting in the
    /// environment).
    private static let overrideEnvVar = "CT_CLI_PATH"

    /// Standard install locations, checked in this order. Mirrors the
    /// install locations `cc`'s own installer documents (`~/.local/bin` for
    /// a user-scoped pipx/uv install, then the two common Homebrew prefixes).
    private static let standardLocations = [
        "~/.local/bin/cc",
        "/opt/homebrew/bin/cc",
        "/usr/local/bin/cc",
    ]

    static func locate() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let override = env[overrideEnvVar], !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        for candidate in standardLocations {
            let expanded = (candidate as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        return nil
    }
}

// MARK: - Errors

/// Every way a CLI call can fail to produce a trustworthy result. This is
/// the app-side half of `CliUnreadableReason` (`native/models.swift`) — that
/// enum is the RENDER vocabulary (what the popover says), this one is the
/// CALL-SITE vocabulary (what actually went wrong). `native/render-state.swift`
/// maps every case here onto a `CliUnreadableReason` for the "bang" fallback.
enum CliError: Error, Equatable {
    /// `CliLocator.locate()` found nothing executable anywhere it looked.
    case notFound
    /// `Process.run()` itself threw (e.g. the resolved path stopped being
    /// executable between `locate()` and launch).
    case launchFailed
    /// Exit code 2 — the CLI's own "no trustworthy body" signal, decoded as
    /// the shared `{schema_version, error:{code,message}}` envelope.
    case exit2(code: String, message: String)
    /// The body did not decode as the expected shape (and was not a
    /// recognizable exit-2 envelope either).
    case parse
    /// `SchemaGate` rejected `schema_version` before trusting anything else.
    case schemaOutOfRange
    /// A required security-relevant field (`destructive`/`signed`/`severity`)
    /// was absent — fail-closed per `_envelope.schema.json`'s header comment
    /// ("Missing security-relevant fields fail closed at the consumer").
    case missingSecurityField
}

// MARK: - Schema gate

/// Range-gates `schema_version` BEFORE any other field of a CLI response is
/// ever decoded or trusted (`cli-contract.md`'s "Requirements" section:
/// "Control Tower declares a `min_schema`/`max_schema` range and gates BOTH
/// directions — a CLI schema older than its floor is as fatal as one
/// newer"). For this phase's frozen contract (every schema in
/// `docs/01-architecture/schemas/` is major version 1, floor `1.0`) that
/// range collapses to one rule: the major component must be exactly 1. A
/// wider `min_schema`/`max_schema` range is a future-phase concern once a
/// second major version actually exists to gate against.
enum SchemaGate {
    static let requiredMajor = 1
    static let minSchema = "1.0"

    private struct VersionOnly: Decodable {
        let schemaVersion: String
    }

    /// Decodes ONLY `schema_version` — never any other key of `data` — so a
    /// schema-out-of-range payload is rejected before any other (possibly
    /// security-relevant) field is ever trusted.
    static func check(_ data: Data) -> Result<Void, CliError> {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let versionOnly = try? decoder.decode(VersionOnly.self, from: data) else {
            return .failure(.parse)
        }

        let parts = versionOnly.schemaVersion.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2, let major = parts.first else {
            return .failure(.schemaOutOfRange)
        }
        guard major == requiredMajor else {
            return .failure(.schemaOutOfRange)
        }
        return .success(())
    }
}

// MARK: - The CLI client

/// The single seam every CLI call in this app goes through. A plain `actor`
/// (not `@MainActor`) — its methods run on the actor's own executor, off the
/// main thread, by construction; `runRaw` additionally hops to a background
/// `DispatchQueue` for the actual `Process` spawn/wait, matching the
/// off-main-thread convention `native/admin.swift`'s `ShellRunner` already
/// establishes elsewhere in this app (that runner intentionally goes through
/// the user's login shell for PATH-sensitive admin tooling; this one
/// deliberately does NOT — see the file header).
actor CliClient {
    static let shared = CliClient()

    private init() {}

    /// Spawns `cc <args>` with an absolute `executableURL` and a plain
    /// argument array. NEVER a shell, NEVER `-lc` — every argument is passed
    /// as its own `Process.arguments` element, so nothing is ever
    /// interpolated into a shell command line.
    ///
    /// `onStdoutLine`, when non-nil, is invoked once per complete line of
    /// stdout as it arrives (newline-framed; see `LineFramer` above) IN
    /// ADDITION to the full accumulated `stdout` this method always
    /// returns — an opt-in streaming callback, additive to every existing
    /// call site, none of which pass one. It fires off the main
    /// thread/actor; a caller that touches `@MainActor` state from it must
    /// hop there itself.
    func runRaw(
        _ args: [String],
        onStdoutLine: ((String) -> Void)? = nil
    ) async -> Result<(stdout: Data, exit: Int32), CliError> {
        guard let executableURL = CliLocator.locate() else {
            return .failure(.notFound)
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = args

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(.launchFailed))
                    return
                }

                // `ProcessDrain` (native/admin.swift) drains both pipes
                // CONCURRENTLY, independent of when/whether
                // `waitUntilExit()` runs — this used to read stdout fully,
                // then stderr fully, then wait, which can still deadlock a
                // chatty child: if it fills the stderr pipe buffer while
                // this call is only draining stdout, the child blocks on
                // its stderr write and never produces the rest of stdout
                // either. stderr is drained (never surfaced) purely so the
                // child never blocks on it — per the copy deck, this app
                // never shows raw CLI/stderr text to the user
                // (`control-tower-copy-deck.md` hard rule "never shows a
                // raw error").
                let drained = ProcessDrain.run(
                    process: process,
                    stdoutPipe: stdoutPipe,
                    stderrPipe: stderrPipe,
                    timeout: nil,
                    onStdoutLine: onStdoutLine
                )

                continuation.resume(returning: .success((stdout: drained.stdout, exit: process.terminationStatus)))
            }
        }
    }

    // MARK: Typed verbs (frozen signatures — see the Phase F plan extract)

    func doctor() async -> Result<DoctorReport, CliError> {
        await decodeVerb(["doctor", "--json"])
    }

    func authStatus() async -> Result<AuthStatus, CliError> {
        await decodeVerb(["auth", "status", "--json"])
    }

    func authLoginInitiate() async -> Result<AuthDeviceCode, CliError> {
        await decodeVerb(["auth", "login", "--json"])
    }

    func authLoginPoll(deviceCode: String) async -> Result<AuthPoll, CliError> {
        await decodeVerb(["auth", "login", "--poll", "--device-code", deviceCode, "--json"])
    }

    func layers() async -> Result<LayersReport, CliError> {
        await decodeVerb(["layers", "--json"])
    }

    func layersJoin(id: String) async -> Result<JoinResult, CliError> {
        await decodeVerb(["layers", "join", id, "--json"])
    }

    func freshness() async -> Result<Freshness, CliError> {
        await decodeVerb(["freshness", "--json"])
    }

    func freshnessAllProjects() async -> Result<AllProjectsFreshness, CliError> {
        await decodeVerb(["freshness", "--all-projects", "--json"])
    }

    func update() async -> Result<UpdateReport, CliError> {
        await decodeVerb(["update", "--json"])
    }

    func updateFanout() async -> Result<FanoutReport, CliError> {
        await decodeVerb(["update", "--fanout", "--json"])
    }

    func updateProject(path: String) async -> Result<UpdateReport, CliError> {
        await decodeVerb(["update", "--project", path, "--json"])
    }

    func onboardPlan(components: [String]) async -> Result<OnboardReport, CliError> {
        await decodeVerb(["onboard", "--scope", "personal", "--components", components.joined(separator: ","), "--json"])
    }

    func onboardApply(components: [String]) async -> Result<OnboardReport, CliError> {
        await decodeVerb(["onboard", "--scope", "personal", "--components", components.joined(separator: ","), "--apply", "--json"])
    }

    /// `adoptExisting` is component-scoped consent (B1, adopt-existing
    /// content): components the person selected on the "One question first"
    /// screen. Empty by default — an unlisted adoptable component is a
    /// no-op on the CLI side, never an implicit decline (`onboard.py`'s own
    /// doc comment on `adopt_existing`). Appended only when non-empty so an
    /// ordinary plan/apply call's argv is unchanged from before this flag
    /// existed.
    func ecosystemOnboardPlan(products: [String], adoptExisting: [String] = []) async -> Result<EcosystemOnboardReport, CliError> {
        await decodeVerb(onboardArguments(org: "auto", products: products, apply: false, adoptExisting: adoptExisting))
    }

    func ecosystemOnboardApply(products: [String], adoptExisting: [String] = []) async -> Result<EcosystemOnboardReport, CliError> {
        await decodeVerb(onboardArguments(org: "auto", products: products, apply: true, adoptExisting: adoptExisting))
    }

    private func onboardArguments(org: String, products: [String], apply: Bool, adoptExisting: [String]) -> [String] {
        var arguments = ["onboard", "--org", org, "--products", products.joined(separator: ",")]
        if apply {
            arguments.append("--apply")
        }
        if !adoptExisting.isEmpty {
            arguments.append(contentsOf: ["--adopt-existing", adoptExisting.joined(separator: ",")])
        }
        arguments.append("--json")
        return arguments
    }

    func workspaces() async -> Result<WorkspacesReport, CliError> {
        await decodeVerb(["workspace", "--all", "--json"])
    }

    func configureWorkspace(
        path: String,
        components: [String],
        shareWithProject: Bool,
        apply: Bool
    ) async -> Result<WorkspacesReport, CliError> {
        var arguments = [
            "workspace", "configure", "--project", path,
            "--components", components.joined(separator: ","),
        ]
        if shareWithProject {
            arguments.append("--share-with-project")
        }
        if apply {
            arguments.append("--apply")
        }
        arguments.append("--json")
        return await decodeVerb(arguments)
    }

    /// **Set up** (wizard Step 8) applying every project the person selected
    /// in **Your projects** in one call, rather than one `configureWorkspace`
    /// round trip per project.
    func configureAllWorkspaces(components: String = "auto", apply: Bool) async -> Result<WorkspacesReport, CliError> {
        var arguments = ["workspace", "configure", "--apply-all", "--components", components]
        if apply {
            arguments.append("--apply")
        }
        arguments.append("--json")
        return await decodeVerb(arguments)
    }

    func approveWorkspaceRoot(path: String) async -> Result<WorkspaceRootReport, CliError> {
        await decodeVerb(["workspace", "approve-root", "--path", path, "--apply", "--json"])
    }

    func forgetWorkspaceRoot(path: String) async -> Result<WorkspaceRootReport, CliError> {
        await decodeVerb(["workspace", "forget-root", "--path", path, "--apply", "--json"])
    }

    /// `cc workspace roots --json` — every approved folder plus detected
    /// one-click candidates. Read-only; never approves anything itself.
    func workspaceRoots() async -> Result<WorkspaceRootsListReport, CliError> {
        await decodeVerb(["workspace", "roots", "--json"])
    }

    /// "I don't keep projects on this Mac" / "Not on this Mac" — the
    /// machine-wide opt-out. Reversible by approving a folder later.
    func declineWorkspaces() async -> Result<WorkspaceDeclineReport, CliError> {
        await decodeVerb(["workspace", "decline", "--apply", "--json"])
    }

    /// **Undo** — removes only the files the CLI recorded as its own (and
    /// whose recorded checksums still match), keeps everything else, and
    /// records the project as excluded from automatic setup. Decodes
    /// `WorkspaceRevertReport`, NOT `WorkspacesReport` — `cc workspace
    /// revert`'s own report is a narrower shape (no `summary`); see that
    /// type's doc comment in `native/cli-dtos.swift`.
    func revertWorkspace(path: String, apply: Bool) async -> Result<WorkspaceRevertReport, CliError> {
        var arguments = ["workspace", "revert", "--project", path]
        if apply {
            arguments.append("--apply")
        }
        arguments.append("--json")
        return await decodeVerb(arguments)
    }

    // MARK: Shared decode pipeline

    /// The shared `{schema_version, error:{code,message}}` envelope every
    /// verb emits on exit 2 (`cli-contract.md`'s "Requirements" section;
    /// `auth.schema.json`'s `errorEnvelope` def is the canonical shape).
    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable {
            let code: String
            let message: String
        }
        let schemaVersion: String
        let error: Body
    }

    /// `runRaw` → exit==2 decodes ONLY the shared error envelope → `.exit2`;
    /// otherwise `SchemaGate` first, then a real decode of `T` with
    /// `.convertFromSnakeCase`. Exit 1 with a valid JSON body is a normal
    /// business outcome (e.g. `doctor`'s "at least one checker failed") and
    /// is decoded exactly like exit 0 — only exit 2 changes what shape is
    /// trusted.
    private func decodeVerb<T: Decodable>(_ args: [String]) async -> Result<T, CliError> {
        switch await runRaw(args) {
        case .failure(let error):
            return .failure(error)

        case .success(let raw):
            if raw.exit == 2 {
                // Exit code 2 is ITSELF the "no trustworthy body" signal
                // (cli-contract.md: "2 = env/credential error"); this ALWAYS
                // maps to `.exit2`, never falls through to the generic
                // `.parse` case, regardless of whether a body happened to be
                // emitted at all. Some real (and mock) exit-2 paths print
                // nothing usable on stdout, only a diagnostic on stderr —
                // that is a valid instance of this same "don't trust it"
                // outcome, not a different, less-specific failure.
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let envelope = try? decoder.decode(ErrorEnvelope.self, from: raw.stdout) {
                    return .failure(.exit2(code: envelope.error.code, message: envelope.error.message))
                }
                return .failure(.exit2(code: "unknown", message: "no readable error body"))
            }

            if case .failure(let gateError) = SchemaGate.check(raw.stdout) {
                return .failure(gateError)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                return .success(try decoder.decode(T.self, from: raw.stdout))
            } catch {
                return .failure(Self.mapDecodingError(error))
            }
        }
    }

    /// Distinguishes "a required SECURITY field was missing" from every
    /// other decode failure, per `_envelope.schema.json`'s fail-closed rule
    /// (a missing `destructive`/`signed`/`severity` is treated as
    /// destructive/unsigned/fail, never safe) — the caller (`render-state.swift`)
    /// renders `.missingSecurityField` with its own distinct, honest copy
    /// ("I can't confirm your setup is safe right now") rather than folding
    /// it into the generic "I can't read your setup" `.parse` message.
    private static let securityFieldKeys: Set<String> = ["destructive", "signed", "severity"]

    private static func mapDecodingError(_ error: Error) -> CliError {
        if case .keyNotFound(let key, _) = error as? DecodingError {
            if securityFieldKeys.contains(key.stringValue) {
                return .missingSecurityField
            }
        }
        return .parse
    }
}
