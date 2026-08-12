import Darwin
import Foundation

private let canonicalRemote = "https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower.git"
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

private struct TreeEntry {
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

private func verifyLauncher(root: String, workspace: SecureWorkspace) {
    let script = URL(fileURLWithPath: root).appendingPathComponent("scripts/verify-release-launcher.sh").path
    let result = run(
        script, [], environment: cleanEnvironment(workspace: workspace), currentDirectory: root
    )
    guard result.status == 0 else { fail("compiled release launcher does not match approved source") }
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
    var authorityRoot = ""
    var testBootstrap = false
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
        case "--authority-root": result.authorityRoot = value()
        case "--test-bootstrap": result.testBootstrap = true
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

private func loadAuthority(root: String, workspace: SecureWorkspace) -> [String: String] {
    let path = URL(fileURLWithPath: root).appendingPathComponent(".env.release.local").path
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
let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let sourceRoot = executable.deletingLastPathComponent().deletingLastPathComponent().path
let hasInnerIdentity = !options.innerRef.isEmpty || !options.innerCommit.isEmpty || !options.innerTree.isEmpty

if options.verifyMaterialized {
    guard !options.innerRef.isEmpty, !options.innerCommit.isEmpty, !options.innerTree.isEmpty,
          options.innerRemote == canonicalRemote, options.authorityRoot.isEmpty,
          !options.testBootstrap else {
        fail("materialized verification arguments are incomplete or unsafe")
    }
    rejectOuterAuthority(sourceEnvironment)
    verifyRemoteMaterialization(
        sourceRoot: sourceRoot, remote: options.innerRemote, ref: options.innerRef,
        commit: options.innerCommit, tree: options.innerTree, allowLocalFixture: false,
        allowedGeneratedRoots: ["build", "dist"]
    )
    print("release materialized source verified: \(options.innerRef) \(options.innerCommit) \(options.innerTree)")
    exit(0)
}

if !hasInnerIdentity {
    rejectOuterAuthority(sourceEnvironment)
    guard !options.sourceRef.isEmpty else { fail("--source-ref is required") }
    let testRemote = sourceEnvironment["CT_RELEASE_BOOTSTRAP_TEST_REMOTE"]
    if testRemote != nil && !options.verifyOnly { fail("bootstrap test remote is verification-only") }
    let remote = testRemote ?? canonicalRemote
    let allowLocalFixture = testRemote != nil
    let workspace = SecureWorkspace(prefix: "control-tower-bootstrap")
    defer { workspace.remove() }
    let resolved = resolveRef(
        remote: remote, requested: options.sourceRef, workspace: workspace,
        allowLocalFixture: allowLocalFixture
    )
    let tree = fetchApprovedTree(
        remote: remote, ref: resolved.ref, expectedCommit: resolved.commit,
        workspace: workspace, allowLocalFixture: allowLocalFixture
    )
    let entries = treeEntries(
        store: workspace.store, commit: resolved.commit, workspace: workspace,
        allowLocalFixture: allowLocalFixture
    )
    materialize(entries: entries, workspace: workspace, allowLocalFixture: allowLocalFixture)
    verifyMaterialized(
        root: workspace.source, entries: entries, workspace: workspace,
        allowLocalFixture: allowLocalFixture, allowedGeneratedRoots: []
    )
    verifyLauncher(root: workspace.source, workspace: workspace)

    var arguments = [
        "--verified-source-ref", resolved.ref,
        "--verified-source-commit", resolved.commit,
        "--verified-source-tree", tree,
        "--verified-source-remote", remote,
        "--authority-root", sourceRoot,
    ]
    if options.verifyOnly { arguments.append("--verify-source-only") }
    if allowLocalFixture { arguments.append("--test-bootstrap") }
    if !options.outputDirectory.isEmpty { arguments += ["--output-dir", options.outputDirectory] }
    let inner = run(
        URL(fileURLWithPath: workspace.source).appendingPathComponent("scripts/package-user-release").path,
        arguments,
        environment: cleanEnvironment(workspace: workspace),
        currentDirectory: workspace.source,
        inheritOutput: true
    )
    exit(inner.status)
}

guard !options.innerRef.isEmpty, !options.innerCommit.isEmpty, !options.innerTree.isEmpty,
      !options.innerRemote.isEmpty, !options.authorityRoot.isEmpty else {
    fail("verified inner source arguments are incomplete")
}
guard options.innerRemote == canonicalRemote || (options.testBootstrap && options.verifyOnly) else {
    fail("inner release remote is not approved")
}
let innerWorkspace = SecureWorkspace(prefix: "control-tower-inner")
defer { innerWorkspace.remove() }
verifyRemoteMaterialization(
    sourceRoot: sourceRoot, remote: options.innerRemote, ref: options.innerRef,
    commit: options.innerCommit, tree: options.innerTree, allowLocalFixture: options.testBootstrap,
    allowedGeneratedRoots: []
)
verifyLauncher(root: sourceRoot, workspace: innerWorkspace)
if options.testBootstrap {
    print("release bootstrap source verified: \(options.innerRef) \(options.innerCommit) \(options.innerTree)")
    exit(0)
}

let implementation = executable.deletingLastPathComponent()
    .appendingPathComponent("package-user-release.program").path
guard let implementationBody = FileManager.default.contents(atPath: implementation) else {
    fail("release implementation is missing")
}
var challengeBytes = [UInt8](repeating: 0, count: 32)
arc4random_buf(&challengeBytes, challengeBytes.count)
let challenge = challengeBytes.map { String(format: "%02x", $0) }.joined()
var streamedBody = Data("CT_RELEASE_STREAM_CHALLENGE='\(challenge)'\n".utf8)
streamedBody.append(implementationBody)
var childEnvironment: [String: String] = [
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": sourceEnvironment["HOME"] ?? NSHomeDirectory(),
    "TMPDIR": sourceEnvironment["TMPDIR"] ?? "/tmp",
    "CT_RELEASE_STREAM": "1",
    "CT_RELEASE_EXPECTED_CHALLENGE": challenge,
    "CT_RELEASE_LAUNCHER_PATH": executable.path,
    "CT_RELEASE_IMPLEMENTATION_PATH": implementation,
]
if !options.verifyOnly {
    let authority = loadAuthority(root: options.authorityRoot, workspace: innerWorkspace)
    for key in authorityKeys where !(authority[key] ?? "").isEmpty {
        childEnvironment[key] = authority[key]
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = [
    "--noprofile", "--norc", "-s", "--",
    "--verified-source-ref", options.innerRef,
    "--verified-source-commit", options.innerCommit,
    "--verified-source-tree", options.innerTree,
] + (options.verifyOnly ? ["--verify-source-only"] : []) +
    (options.outputDirectory.isEmpty ? [] : ["--output-dir", options.outputDirectory])
process.environment = childEnvironment
process.currentDirectoryURL = URL(fileURLWithPath: sourceRoot)
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
    fail("could not start release implementation")
}
