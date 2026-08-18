import Darwin
import CoreFoundation
import Foundation

private let canonicalRemote = "https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower.git"
private let canonicalTrustRoot = "/Library/PrivilegedHelperTools"
private let canonicalBundle = canonicalTrustRoot + "/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"
private let canonicalExecutable = canonicalBundle + "/Contents/MacOS/ct-publisher-bootstrap"
private let canonicalIdentifier = "com.everyoneneedsacopilot.controltower.publisher-bootstrap"
private let canonicalTeamID = "3SYGVX2HB8"
private let canonicalPackageIdentifier = "com.everyoneneedsacopilot.controltower.publisher-bootstrap.pkg"
private let approvalPath = "/Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap/approved-source.json"
private let authorityKeys = [
    "GH_TOKEN", "GITHUB_TOKEN", "CT_SIGN_IDENTITY", "CT_NOTARY_KEYCHAIN_PROFILE",
    "CT_NOTARY_KEY_ID", "CT_NOTARY_KEY_ISSUER", "CT_NOTARY_KEY_PATH",
    "CT_VENDORED_CC_PATH",
]
private let forbiddenGitEnvironmentPrefixes = [
    "GIT_CONFIG", "GIT_TRACE", "BASH_FUNC_",
]
private let forbiddenGitEnvironmentNames: Set<String> = [
    "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_CEILING_DIRECTORIES",
    "GIT_DISCOVERY_ACROSS_FILESYSTEM", "GIT_EXEC_PATH", "GIT_SSH", "GIT_SSH_COMMAND",
    "GIT_ASKPASS", "GIT_PROXY_COMMAND", "GIT_PROTOCOL_FROM_USER", "GIT_ALLOW_PROTOCOL",
    "GIT_SSL_NO_VERIFY", "GIT_SSL_CAINFO", "GIT_SSL_CAPATH", "GIT_CURL_VERBOSE",
    "SSH_ASKPASS", "SSH_ASKPASS_REQUIRE", "BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS",
]

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

private struct CommandResult {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var text: String { String(decoding: stdout, as: UTF8.self) }
}

private func run(
    _ executable: String,
    _ arguments: [String],
    environment: [String: String],
    currentDirectory: String,
    input: Data? = nil,
    inheritOutput: Bool = false
) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

    let stdout = Pipe()
    let stderr = Pipe()
    if inheritOutput {
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
    } else {
        process.standardOutput = stdout
        process.standardError = stderr
    }

    let stdin = input == nil ? nil : Pipe()
    if let stdin { process.standardInput = stdin }

    do {
        try process.run()
        if let input, let stdin {
            stdin.fileHandleForWriting.write(input)
            stdin.fileHandleForWriting.closeFile()
        }
        let outputData = inheritOutput ? Data() : stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = inheritOutput ? Data() : stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, stdout: outputData, stderr: errorData)
    } catch {
        fail("could not start approved executable")
    }
}

private func lexicalRegularFile(_ path: String, executable: Bool) -> Bool {
    guard path.hasPrefix("/") else { return false }
    var metadata = stat()
    guard lstat(path, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == S_IFREG,
          (metadata.st_mode & 0o022) == 0 else { return false }
    return !executable || (metadata.st_mode & 0o111) != 0
}

private func anchorCommand(
    _ executable: String, _ arguments: [String], currentDirectory: String
) -> CommandResult {
    run(
        executable, arguments,
        environment: [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": "/var/empty",
            "TMPDIR": "/tmp",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0",
        ],
        currentDirectory: currentDirectory
    )
}

struct ApprovedSource: Decodable {
    struct AppIdentity: Decodable {
        let path: String
        let bundleIdentifier: String
        let teamID: String
        let cdhash: String
        let bundleSHA256: String

        enum CodingKeys: String, CodingKey {
            case path
            case bundleIdentifier = "bundle_identifier"
            case teamID = "team_id"
            case cdhash
            case bundleSHA256 = "bundle_sha256"
        }
    }

    let schemaVersion: Int
    let remote: String
    let ref: String
    let commit: String
    let tree: String
    let packageIdentifier: String
    let app: AppIdentity

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case remote, ref, commit, tree
        case packageIdentifier = "package_identifier"
        case app
    }
}

private func approvedReceiptTeamIsValid(_ team: String) -> Bool {
#if CT_PUBLISHER_BOOTSTRAP_TEST_BUILD
    return team == canonicalTeamID || team == "adhoc"
#else
    return team == canonicalTeamID
#endif
}

private func hasExtendedACL(_ path: String) -> Bool {
    errno = 0
    guard let acl = acl_get_link_np(path, ACL_TYPE_EXTENDED) else {
        // macOS reports ENOENT when an existing object has no extended ACL.
        return errno != ENOENT
    }
    defer { acl_free(UnsafeMutableRawPointer(acl)) }
    var entry: acl_entry_t?
    return acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == 0
}

private func validateProtectedComponent(_ path: String, directory: Bool, owner: uid_t = 0) {
    var metadata = stat()
    guard lstat(path, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == (directory ? S_IFDIR : S_IFREG),
          metadata.st_uid == owner, (metadata.st_mode & 0o022) == 0,
          access(path, W_OK) != 0, !hasExtendedACL(path) else {
        fail("publisher bootstrap installation is not root-owned and protected")
    }
}

private func runningExecutablePath() -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    let count = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
    guard count > 0 else { fail("could not authenticate the running publisher bootstrap path") }
    return String(cString: buffer)
}

private func validateProtectedAnchorChain(
    bundle: String, executable: String, trustRoot: String, owner: uid_t
) {
    let prefix = trustRoot == canonicalTrustRoot ? "" : trustRoot
    let library = prefix + "/Library"
    let helperTools = library + "/PrivilegedHelperTools"
    let expectedBundle = helperTools + "/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"
    let expectedExecutable = expectedBundle + "/Contents/MacOS/ct-publisher-bootstrap"
    guard bundle == expectedBundle, executable == expectedExecutable else {
        fail("publisher bootstrap canonical path is inconsistent")
    }
    if prefix.isEmpty { validateProtectedComponent("/", directory: true, owner: owner) }
    else { validateProtectedComponent(prefix, directory: true, owner: owner) }
    validateProtectedComponent(library, directory: true, owner: owner)
    validateProtectedComponent(helperTools, directory: true, owner: owner)
    validateProtectedComponent(bundle, directory: true, owner: owner)
    validateProtectedComponent(bundle + "/Contents", directory: true, owner: owner)
    validateProtectedComponent(bundle + "/Contents/MacOS", directory: true, owner: owner)
    validateProtectedComponent(executable, directory: false, owner: owner)
}

private func validateProtectedApprovalChain(owner: uid_t = 0) {
    validateProtectedComponent("/", directory: true, owner: owner)
    validateProtectedComponent("/Library", directory: true, owner: owner)
    validateProtectedComponent("/Library/Application Support", directory: true, owner: owner)
    validateProtectedComponent("/Library/Application Support/Everyone Needs a Copilot", directory: true, owner: owner)
    validateProtectedComponent("/Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap", directory: true, owner: owner)
    validateProtectedComponent(approvalPath, directory: false, owner: owner)
}

private func validateInstalledAnchor() {
#if CT_PUBLISHER_BOOTSTRAP_TEST_BUILD
    guard ProcessInfo.processInfo.environment["CT_PUBLISHER_BOOTSTRAP_TEST"] == "1" else {
        fail("test publisher bootstrap requires its explicit hermetic test seam")
    }
    if let root = ProcessInfo.processInfo.environment["CT_PUBLISHER_BOOTSTRAP_TEST_CHAIN_ROOT"] {
        let bundle = root + "/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"
        let executable = bundle + "/Contents/MacOS/ct-publisher-bootstrap"
        guard CommandLine.arguments[0] == executable, runningExecutablePath() == executable else {
            fail("publisher bootstrap must run from its protected canonical path")
        }
        validateProtectedAnchorChain(bundle: bundle, executable: executable, trustRoot: root, owner: getuid())
        print("publisher bootstrap synthetic protected path: PASS")
        exit(0)
    }
    return
#else
    guard CommandLine.arguments[0] == canonicalExecutable,
          runningExecutablePath() == canonicalExecutable else {
        fail("publisher bootstrap must run from its protected canonical path")
    }
    validateProtectedAnchorChain(
        bundle: canonicalBundle, executable: canonicalExecutable,
        trustRoot: canonicalTrustRoot, owner: 0
    )
    let requirement = "=anchor apple generic and identifier \"\(canonicalIdentifier)\" and certificate leaf[subject.OU] = \"\(canonicalTeamID)\""
    let codesign = anchorCommand(
        "/usr/bin/codesign", ["--verify", "--deep", "--strict", "--test-requirement", requirement, canonicalBundle],
        currentDirectory: canonicalTrustRoot
    )
    guard codesign.status == 0 else { fail("publisher bootstrap signature or designated requirement is invalid") }
    let assessment = anchorCommand(
        "/usr/sbin/spctl", ["--assess", "--type", "execute", canonicalBundle],
        currentDirectory: canonicalTrustRoot
    )
    guard assessment.status == 0 else { fail("publisher bootstrap failed Gatekeeper assessment") }
    let staple = anchorCommand(
        "/usr/bin/xcrun", ["stapler", "validate", canonicalBundle], currentDirectory: canonicalTrustRoot
    )
    guard staple.status == 0 else { fail("publisher bootstrap notarization ticket is absent or invalid") }
#endif
}

private func approvedSource() -> ApprovedSource {
#if CT_PUBLISHER_BOOTSTRAP_TEST_BUILD
    guard let path = ProcessInfo.processInfo.environment["CT_PUBLISHER_BOOTSTRAP_TEST_APPROVAL"] else {
        fail("test publisher bootstrap approval is unavailable")
    }
#else
    let path = approvalPath
    validateProtectedApprovalChain()
#endif
    guard let data = FileManager.default.contents(atPath: path),
          let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rawSchema = raw["schema_version"] as? NSNumber,
          CFGetTypeID(rawSchema) != CFBooleanGetTypeID(),
          !["f", "d"].contains(String(cString: rawSchema.objCType)),
          rawSchema.intValue == 2,
          let approval = try? JSONDecoder().decode(ApprovedSource.self, from: data),
          approval.schemaVersion == 2,
          approval.packageIdentifier == canonicalPackageIdentifier,
          approval.app.path == canonicalBundle,
          approval.app.bundleIdentifier == canonicalIdentifier,
          approvedReceiptTeamIsValid(approval.app.teamID),
          approval.app.cdhash.range(of: "^[0-9a-f]{40,64}$", options: .regularExpression) != nil,
          approval.app.bundleSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
          approval.ref.hasPrefix("refs/"),
          approval.commit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
          approval.tree.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
        fail("publisher bootstrap approved-source record is invalid")
    }
#if !CT_PUBLISHER_BOOTSTRAP_TEST_BUILD
    guard approval.remote == canonicalRemote else {
        fail("publisher bootstrap approved-source endpoint is invalid")
    }
#endif
    return approval
}

struct SecureWorkspace {
    let root: String
    let home: String
    let store: String
    let source: String

    init(prefix: String) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix).\(UUID().uuidString)")
            .standardizedFileURL
        root = rootURL.path
        home = rootURL.appendingPathComponent("home").path
        store = rootURL.appendingPathComponent("objects.git").path
        source = rootURL.appendingPathComponent("source").path
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: home), withIntermediateDirectories: false
            )
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: source), withIntermediateDirectories: false
            )
            chmod(root, 0o700)
            chmod(home, 0o700)
            chmod(source, 0o700)
        } catch {
            fail("could not create isolated release workspace")
        }
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }
}

private func cleanEnvironment(workspace: SecureWorkspace) -> [String: String] {
    [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": workspace.home,
        "TMPDIR": workspace.root,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
    ]
}

private func trustedGit(
    _ arguments: [String],
    workspace: SecureWorkspace,
    allowLocalFixture: Bool,
    input: Data? = nil
) -> CommandResult {
    var fixed = [
        "-c", "credential.helper=",
        "-c", "core.hooksPath=/dev/null",
        "-c", "core.fsmonitor=false",
        "-c", "diff.external=",
        "-c", "diff.trustExitCode=false",
        "-c", "protocol.ext.allow=never",
        "-c", "protocol.ssh.allow=never",
        "-c", "protocol.git.allow=never",
        "-c", "protocol.http.allow=never",
        "-c", "protocol.https.allow=always",
        "-c", "http.followRedirects=false",
        "-c", "include.path=/dev/null",
    ]
    fixed += ["-c", allowLocalFixture ? "protocol.file.allow=always" : "protocol.file.allow=never"]
    return run(
        "/usr/bin/git", fixed + arguments,
        environment: cleanEnvironment(workspace: workspace),
        currentDirectory: workspace.root,
        input: input
    )
}

private func commandText(_ result: CommandResult, failure: String) -> String {
    guard result.status == 0 else { fail(failure) }
    return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func validateRef(_ requested: String) {
    guard !requested.isEmpty, !requested.hasPrefix("-"),
          !requested.contains("\n"), !requested.contains("\t"),
          !requested.contains(" ") else {
        fail("invalid release source ref")
    }
}

private func resolveRef(
    remote: String,
    requested: String,
    workspace: SecureWorkspace,
    allowLocalFixture: Bool
) -> (ref: String, commit: String) {
    validateRef(requested)
    guard remote == canonicalRemote || allowLocalFixture else {
        fail("release remote is not the approved HTTPS endpoint")
    }
    let head = requested.hasPrefix("refs/heads/") ? requested : "refs/heads/\(requested)"
    let tag = requested.hasPrefix("refs/tags/") ? requested : "refs/tags/\(requested)"
    let headResult = trustedGit(
        ["ls-remote", remote, head], workspace: workspace, allowLocalFixture: allowLocalFixture
    )
    let tagResult = trustedGit(
        ["ls-remote", remote, tag, "\(tag)^{}"], workspace: workspace,
        allowLocalFixture: allowLocalFixture
    )
    guard headResult.status == 0, tagResult.status == 0 else {
        fail("could not inspect approved remote")
    }
    let headLines = headResult.text.split(separator: "\n").map(String.init)
    let tagLines = tagResult.text.split(separator: "\n").map(String.init)
    if !headLines.isEmpty && !tagLines.isEmpty && !requested.hasPrefix("refs/") {
        fail("release source ref is ambiguous")
    }

    func oid(from line: String) -> String {
        let value = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.map(String.init) ?? ""
        guard value.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            fail("approved remote returned an invalid object identity")
        }
        return value
    }

    if let line = headLines.first { return (head, oid(from: line)) }
    if !tagLines.isEmpty {
        let line = tagLines.first(where: { $0.hasSuffix("^{}") }) ?? tagLines[0]
        return (tag, oid(from: line))
    }
    fail("approved remote does not advertise \(requested)")
}

struct TreeEntry {
    let mode: String
    let oid: String
    let path: String
}

private func validateRelativePath(_ path: String) {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !path.isEmpty, !path.hasPrefix("/"),
          !parts.contains(""), !parts.contains("."), !parts.contains(".."),
          !parts.contains(where: { $0.lowercased() == ".git" }) else {
        fail("Git tree contains an unsafe path")
    }
}

private func treeEntries(
    store: String,
    commit: String,
    workspace: SecureWorkspace,
    allowLocalFixture: Bool
) -> [TreeEntry] {
    let result = trustedGit(
        ["--git-dir", store, "ls-tree", "-rz", "--full-tree", commit],
        workspace: workspace, allowLocalFixture: allowLocalFixture
    )
    guard result.status == 0 else { fail("could not enumerate approved source tree") }
    var entries: [TreeEntry] = []
    for record in result.stdout.split(separator: 0, omittingEmptySubsequences: true) {
        guard let tab = record.firstIndex(of: 9),
              let metadata = String(data: record[..<tab], encoding: .utf8),
              let path = String(data: record[record.index(after: tab)...], encoding: .utf8) else {
            fail("approved source tree contains an unsupported path encoding")
        }
        let fields = metadata.split(separator: " ").map(String.init)
        guard fields.count == 3, fields[1] == "blob",
              fields[0] == "100644" || fields[0] == "100755",
              fields[2].range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            fail("approved source tree contains a symlink, gitlink, or unsupported mode")
        }
        validateRelativePath(path)
        entries.append(TreeEntry(mode: fields[0], oid: fields[2], path: path))
    }
    guard !entries.isEmpty else { fail("approved source tree is empty") }
    return entries
}

private func fetchApprovedTree(
    remote: String,
    ref: String,
    expectedCommit: String,
    workspace: SecureWorkspace,
    allowLocalFixture: Bool
) -> String {
    let initialized = trustedGit(
        ["init", "--bare", "--quiet", workspace.store],
        workspace: workspace, allowLocalFixture: allowLocalFixture
    )
    guard initialized.status == 0 else { fail("could not initialize isolated Git store") }
    chmod(workspace.store, 0o700)
    let fetched = trustedGit(
        ["--git-dir", workspace.store, "fetch", "--quiet", "--no-tags", "--force",
         remote, "\(ref):refs/bootstrap/source"],
        workspace: workspace, allowLocalFixture: allowLocalFixture
    )
    guard fetched.status == 0 else { fail("could not fetch approved release source") }
    let commit = commandText(
        trustedGit(
            ["--git-dir", workspace.store, "rev-parse", "refs/bootstrap/source^{commit}"],
            workspace: workspace, allowLocalFixture: allowLocalFixture
        ), failure: "could not resolve fetched release commit"
    )
    guard commit == expectedCommit else { fail("fetched release commit does not match advertised ref") }
    return commandText(
        trustedGit(
            ["--git-dir", workspace.store, "rev-parse", "\(commit)^{tree}"],
            workspace: workspace, allowLocalFixture: allowLocalFixture
        ), failure: "could not resolve fetched release tree"
    )
}

private func materialize(
    entries: [TreeEntry],
    workspace: SecureWorkspace,
    allowLocalFixture: Bool
) {
    for entry in entries {
        let destination = URL(fileURLWithPath: workspace.source).appendingPathComponent(entry.path)
        let canonical = destination.standardizedFileURL.path
        guard canonical.hasPrefix(workspace.source + "/") else { fail("source path escaped materialization root") }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        } catch {
            fail("could not create materialized source directory")
        }
        let blob = trustedGit(
            ["--git-dir", workspace.store, "cat-file", "blob", entry.oid],
            workspace: workspace, allowLocalFixture: allowLocalFixture
        )
        guard blob.status == 0 else { fail("could not read approved source object") }
        do {
            try blob.stdout.write(to: destination, options: .atomic)
            chmod(canonical, entry.mode == "100755" ? 0o755 : 0o644)
        } catch {
            fail("could not materialize approved source object")
        }
    }
}

private func verifyMaterialized(
    root: String,
    entries: [TreeEntry],
    workspace: SecureWorkspace,
    allowLocalFixture: Bool,
    allowedGeneratedRoots: Set<String>
) {
    let resolvedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
    let expected = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
    guard expected.count == entries.count else { fail("approved source tree contains duplicate paths") }
    var actual: Set<String> = []
    guard let enumerator = FileManager.default.enumerator(atPath: resolvedRoot) else {
        fail("could not inspect materialized source")
    }
    while let relative = enumerator.nextObject() as? String {
        let top = relative.split(separator: "/", maxSplits: 1).first.map(String.init) ?? relative
        if allowedGeneratedRoots.contains(top) {
            if relative == top { enumerator.skipDescendants() }
            continue
        }
        let path = URL(fileURLWithPath: resolvedRoot).appendingPathComponent(relative).path
        var metadata = stat()
        guard lstat(path, &metadata) == 0 else { fail("materialized source changed during inspection") }
        let kind = metadata.st_mode & S_IFMT
        if kind == S_IFDIR { continue }
        guard kind == S_IFREG else { fail("materialized source contains a link or special file") }
        actual.insert(relative)
    }
    guard actual == Set(expected.keys) else { fail("materialized source file set differs from approved tree") }

    for (relative, entry) in expected {
        let path = URL(fileURLWithPath: resolvedRoot).appendingPathComponent(relative).path
        var metadata = stat()
        guard lstat(path, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
              (metadata.st_mode & 0o022) == 0 else {
            fail("materialized source file ownership or mode is unsafe")
        }
        let executable = (metadata.st_mode & 0o111) != 0
        guard executable == (entry.mode == "100755") else {
            fail("materialized source executable mode differs from approved tree")
        }
        let hash = commandText(
            trustedGit(
                ["hash-object", "--no-filters", path], workspace: workspace,
                allowLocalFixture: allowLocalFixture
            ), failure: "could not hash materialized source"
        )
        guard hash == entry.oid else { fail("materialized source bytes differ from approved tree") }
    }
    var gitMetadata: ObjCBool = false
    guard !FileManager.default.fileExists(
        atPath: URL(fileURLWithPath: resolvedRoot).appendingPathComponent(".git").path,
        isDirectory: &gitMetadata
    ) else {
        fail("materialized source must not contain Git metadata")
    }
}

private func verifyRemoteMaterialization(
    sourceRoot: String,
    remote: String,
    ref: String,
    commit: String,
    tree: String,
    allowLocalFixture: Bool,
    allowedGeneratedRoots: Set<String>
) {
    let workspace = SecureWorkspace(prefix: "control-tower-verify")
    defer { workspace.remove() }
    let resolved = resolveRef(
        remote: remote, requested: ref, workspace: workspace, allowLocalFixture: allowLocalFixture
    )
    guard resolved.ref == ref, resolved.commit == commit else { fail("approved remote ref changed") }
    let fetchedTree = fetchApprovedTree(
        remote: remote, ref: ref, expectedCommit: commit, workspace: workspace,
        allowLocalFixture: allowLocalFixture
    )
    guard fetchedTree == tree else { fail("approved remote tree changed") }
    let entries = treeEntries(
        store: workspace.store, commit: commit, workspace: workspace,
        allowLocalFixture: allowLocalFixture
    )
    verifyMaterialized(
        root: sourceRoot, entries: entries, workspace: workspace,
        allowLocalFixture: allowLocalFixture, allowedGeneratedRoots: allowedGeneratedRoots
    )
}

struct Options {
    var sourceRef = ""
    var outputDirectory = ""
    var verifyOnly = false
    var verifyMaterialized = false
    var innerRef = ""
    var innerCommit = ""
    var innerTree = ""
    var innerRemote = ""
    var materializedRoot = ""
}

private func parseOptions() -> Options {
    var result = Options()
    var index = 1
    while index < CommandLine.arguments.count {
        let argument = CommandLine.arguments[index]
        func value() -> String {
            guard index + 1 < CommandLine.arguments.count else { fail("\(argument) requires a value") }
            index += 1
            return CommandLine.arguments[index]
        }
        switch argument {
        case "--source-ref": result.sourceRef = value()
        case "--output-dir": result.outputDirectory = value()
        case "--verify-source-only": result.verifyOnly = true
        case "--verify-materialized-source": result.verifyMaterialized = true
        case "--verified-source-ref": result.innerRef = value()
        case "--verified-source-commit": result.innerCommit = value()
        case "--verified-source-tree": result.innerTree = value()
        case "--verified-source-remote": result.innerRemote = value()
        case "--materialized-root": result.materializedRoot = value()
        case "-h", "--help":
            print("Usage: scripts/package-user-release --source-ref REF [--output-dir PATH] [--verify-source-only]")
            exit(0)
        default: fail("unknown option: \(argument)")
        }
        index += 1
    }
    return result
}

private func rejectOuterAuthority(_ environment: [String: String]) {
    if let key = authorityKeys.first(where: { environment[$0] != nil }) {
        fail("release authority must not be supplied to the credential-free bootstrap: \(key)")
    }
    if environment["CT_RELEASE_CHECKOUT"] != nil {
        fail("CT_RELEASE_CHECKOUT is not a supported release authority")
    }
    if let key = environment.keys.first(where: { name in
        forbiddenGitEnvironmentNames.contains(name) ||
            forbiddenGitEnvironmentPrefixes.contains(where: { prefix in name.hasPrefix(prefix) })
    }) {
        fail("Git or shell authority environment is forbidden: \(key)")
    }
}

private func loadAuthority(workspace: SecureWorkspace) -> [String: String] {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Copilot Control Tower Publisher/.env.release.local").path
    var metadata = stat()
    guard lstat(path, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
          metadata.st_uid == getuid(), (metadata.st_mode & 0o077) == 0 else {
        fail("publisher authority file is missing or unsafe; run Publisher Setup")
    }
    let shell = "set -a; source \"$1\"; /usr/bin/env -0"
    let result = run(
        "/bin/bash", ["--noprofile", "--norc", "-c", shell, "release-authority", path],
        environment: [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": workspace.home,
            "TMPDIR": workspace.root,
        ],
        currentDirectory: workspace.root
    )
    guard result.status == 0 else { fail("could not load publisher authority file") }
    var values: [String: String] = [:]
    for item in result.stdout.split(separator: 0, omittingEmptySubsequences: true) {
        let pair = item.split(separator: 61, maxSplits: 1, omittingEmptySubsequences: false)
        if pair.count == 2, let key = String(data: pair[0], encoding: .utf8),
           let value = String(data: pair[1], encoding: .utf8) {
            values[key] = value
        }
    }
    return values
}

let options = parseOptions()
let sourceEnvironment = ProcessInfo.processInfo.environment
validateInstalledAnchor()
let approval = approvedSource()

#if CT_PUBLISHER_BOOTSTRAP_TEST_BUILD
let allowLocalFixture = true
#else
let allowLocalFixture = false
#endif

if options.verifyMaterialized {
    rejectOuterAuthority(sourceEnvironment)
    guard options.innerRef == approval.ref, options.innerCommit == approval.commit,
          options.innerTree == approval.tree, options.innerRemote == approval.remote,
          !options.materializedRoot.isEmpty else {
        fail("materialized verification arguments are not the root-approved source")
    }
    verifyRemoteMaterialization(
        sourceRoot: options.materializedRoot, remote: approval.remote, ref: approval.ref,
        commit: approval.commit, tree: approval.tree, allowLocalFixture: allowLocalFixture,
        allowedGeneratedRoots: ["build", "dist"]
    )
    print("release materialized source verified: \(approval.ref) \(approval.commit) \(approval.tree)")
    exit(0)
}

rejectOuterAuthority(sourceEnvironment)
guard options.sourceRef == approval.ref else {
    fail("requested source is not the root-approved immutable ref")
}
let workspace = SecureWorkspace(prefix: "control-tower-bootstrap")
defer { workspace.remove() }
let resolved = resolveRef(
    remote: approval.remote, requested: approval.ref, workspace: workspace,
    allowLocalFixture: allowLocalFixture
)
guard resolved.commit == approval.commit else { fail("root-approved source ref moved") }
let tree = fetchApprovedTree(
    remote: approval.remote, ref: approval.ref, expectedCommit: approval.commit,
    workspace: workspace, allowLocalFixture: allowLocalFixture
)
guard tree == approval.tree else { fail("root-approved source tree changed") }
let entries = treeEntries(
    store: workspace.store, commit: approval.commit, workspace: workspace,
    allowLocalFixture: allowLocalFixture
)
materialize(entries: entries, workspace: workspace, allowLocalFixture: allowLocalFixture)
verifyMaterialized(
    root: workspace.source, entries: entries, workspace: workspace,
    allowLocalFixture: allowLocalFixture, allowedGeneratedRoots: []
)
if options.verifyOnly {
    print("release source verified without Git metadata: \(approval.ref) \(approval.commit) \(approval.tree)")
    exit(0)
}

let implementation = URL(fileURLWithPath: workspace.source)
    .appendingPathComponent("scripts/package-user-release.program").path
guard lexicalRegularFile(implementation, executable: false),
      let implementationBody = FileManager.default.contents(atPath: implementation) else {
    fail("verified release implementation is missing or unsafe")
}
let authorityWorkspace = SecureWorkspace(prefix: "control-tower-authority")
defer { authorityWorkspace.remove() }
let authority = loadAuthority(workspace: authorityWorkspace)
var challengeBytes = [UInt8](repeating: 0, count: 32)
arc4random_buf(&challengeBytes, challengeBytes.count)
let challenge = challengeBytes.map { String(format: "%02x", $0) }.joined()
var streamedBody = Data("CT_RELEASE_STREAM_CHALLENGE='\(challenge)'\n".utf8)
streamedBody.append(implementationBody)
var childEnvironment: [String: String] = [
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
    "TMPDIR": workspace.root,
    "CT_RELEASE_STREAM": "1",
    "CT_RELEASE_EXPECTED_CHALLENGE": challenge,
    "CT_RELEASE_ANCHOR_PATH": canonicalExecutable,
    "CT_RELEASE_IMPLEMENTATION_PATH": implementation,
]
for key in authorityKeys where !(authority[key] ?? "").isEmpty {
    childEnvironment[key] = authority[key]
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = [
    "--noprofile", "--norc", "-s", "--",
    "--verified-source-ref", approval.ref,
    "--verified-source-commit", approval.commit,
    "--verified-source-tree", approval.tree,
] + (options.outputDirectory.isEmpty ? [] : ["--output-dir", options.outputDirectory])
process.environment = childEnvironment
process.currentDirectoryURL = URL(fileURLWithPath: workspace.source)
let pipe = Pipe()
process.standardInput = pipe
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError
do {
    try process.run()
    pipe.fileHandleForWriting.write(streamedBody)
    pipe.fileHandleForWriting.closeFile()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    fail("could not start verified release implementation")
}
