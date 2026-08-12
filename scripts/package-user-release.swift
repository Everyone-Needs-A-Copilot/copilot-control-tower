import Darwin
import Foundation

private let canonicalRemote = "https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower.git"
private let authorityKeys = [
    "GH_TOKEN", "GITHUB_TOKEN", "CT_SIGN_IDENTITY", "CT_NOTARY_KEYCHAIN_PROFILE",
    "CT_NOTARY_KEY_ID", "CT_NOTARY_KEY_ISSUER", "CT_NOTARY_KEY_PATH",
]

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

private struct Result {
    let status: Int32
    let output: String
}

private func run(
    _ executable: String,
    _ arguments: [String],
    environment: [String: String],
    currentDirectory: String? = nil,
    capture: Bool = true
) -> Result {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    if let currentDirectory {
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
    }
    let pipe = Pipe()
    if capture {
        process.standardOutput = pipe
        process.standardError = pipe
    } else {
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
    }
    do {
        try process.run()
        process.waitUntilExit()
        let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    } catch {
        fail("could not start \(executable)")
    }
}

private func cleanEnvironment(home: String, temporary: String) -> [String: String] {
    [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": home,
        "TMPDIR": temporary,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
    ]
}

private func trustedGit(
    _ arguments: [String],
    environment: [String: String],
    allowLocalFixture: Bool = false
) -> Result {
    var fixed = [
        "-c", "credential.helper=",
        "-c", "protocol.ext.allow=never",
        "-c", "protocol.ssh.allow=never",
        "-c", "protocol.git.allow=never",
        "-c", "protocol.http.allow=never",
        "-c", "protocol.https.allow=always",
        "-c", "http.followRedirects=false",
        "-c", "include.path=/dev/null",
    ]
    fixed += ["-c", allowLocalFixture ? "protocol.file.allow=always" : "protocol.file.allow=never"]
    return run("/usr/bin/git", fixed + arguments, environment: environment)
}

private func resolveRef(
    remote: String,
    requested: String,
    environment: [String: String],
    allowLocalFixture: Bool
) -> (String, String) {
    guard !requested.isEmpty, !requested.hasPrefix("-"),
          !requested.contains("\n"), !requested.contains("\t") else {
        fail("invalid release source ref")
    }
    let head = requested.hasPrefix("refs/heads/") ? requested : "refs/heads/\(requested)"
    let tag = requested.hasPrefix("refs/tags/") ? requested : "refs/tags/\(requested)"
    let headResult = trustedGit(
        ["ls-remote", remote, head], environment: environment,
        allowLocalFixture: allowLocalFixture
    )
    let tagResult = trustedGit(
        ["ls-remote", remote, tag, "\(tag)^{}"], environment: environment,
        allowLocalFixture: allowLocalFixture
    )
    guard headResult.status == 0, tagResult.status == 0 else {
        fail("could not inspect approved remote")
    }
    let headLine = headResult.output.split(separator: "\n").first.map(String.init) ?? ""
    let tagLines = tagResult.output.split(separator: "\n").map(String.init)
    if !headLine.isEmpty && !tagLines.isEmpty && !requested.hasPrefix("refs/") {
        fail("release source ref is ambiguous")
    }
    if !headLine.isEmpty {
        return (head, String(headLine.split(whereSeparator: { $0 == "\t" || $0 == " " }).first!))
    }
    if !tagLines.isEmpty {
        let peeled = tagLines.first(where: { $0.hasSuffix("^{}") }) ?? tagLines[0]
        return (tag, String(peeled.split(whereSeparator: { $0 == "\t" || $0 == " " }).first!))
    }
    fail("approved remote does not advertise \(requested)")
}

private func gitValue(
    _ arguments: [String], checkout: String, environment: [String: String], allowLocalFixture: Bool
) -> String {
    let result = trustedGit(
        ["-C", checkout] + arguments, environment: environment,
        allowLocalFixture: allowLocalFixture
    )
    guard result.status == 0 else { fail("could not verify immutable checkout") }
    return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func verifyCheckout(
    checkout: String,
    remote: String,
    ref: String,
    commit: String,
    tree: String,
    environment: [String: String],
    allowLocalFixture: Bool
) {
    let canonicalCheckout = URL(fileURLWithPath: checkout).resolvingSymlinksInPath().path
    let reportedRoot = gitValue(["rev-parse", "--show-toplevel"], checkout: canonicalCheckout,
                                environment: environment, allowLocalFixture: allowLocalFixture)
    guard URL(fileURLWithPath: reportedRoot).resolvingSymlinksInPath().path == canonicalCheckout else {
        fail("release checkout is not the repository root: \(reportedRoot)")
    }
    guard gitValue(["status", "--porcelain=v1", "--untracked-files=all"], checkout: canonicalCheckout,
                   environment: environment, allowLocalFixture: allowLocalFixture).isEmpty else {
        fail("verified release checkout is not clean")
    }
    let symbolic = trustedGit(["-C", canonicalCheckout, "symbolic-ref", "-q", "HEAD"], environment: environment,
                              allowLocalFixture: allowLocalFixture)
    guard symbolic.status != 0 else { fail("verified release checkout must be detached") }
    guard gitValue(["remote", "get-url", "origin"], checkout: canonicalCheckout, environment: environment,
                   allowLocalFixture: allowLocalFixture) == remote,
          gitValue(["rev-parse", "HEAD"], checkout: canonicalCheckout, environment: environment,
                   allowLocalFixture: allowLocalFixture) == commit,
          gitValue(["rev-parse", "HEAD^{tree}"], checkout: canonicalCheckout, environment: environment,
                   allowLocalFixture: allowLocalFixture) == tree else {
        fail("verified release checkout identity changed")
    }
    let resolved = resolveRef(remote: remote, requested: ref, environment: environment,
                              allowLocalFixture: allowLocalFixture)
    guard resolved.0 == ref, resolved.1 == commit else { fail("approved remote ref changed after checkout") }

    for relative in [
        "scripts/package-user-release", "scripts/package-user-release.swift",
        "scripts/package-user-release.program", "scripts/package-user-release.sha256",
        "scripts/verify-release-launcher.sh",
    ] {
        let object = gitValue(["rev-parse", "HEAD:\(relative)"], checkout: canonicalCheckout,
                              environment: environment, allowLocalFixture: allowLocalFixture)
        let file = gitValue(["hash-object", "\(canonicalCheckout)/\(relative)"], checkout: canonicalCheckout,
                            environment: environment, allowLocalFixture: allowLocalFixture)
        guard object == file else { fail("immutable release file differs from Git tree: \(relative)") }
    }
    let proof = run("\(canonicalCheckout)/scripts/verify-release-launcher.sh", [], environment: environment,
                    currentDirectory: canonicalCheckout)
    guard proof.status == 0 else { fail("compiled release launcher does not match immutable source") }
}

struct Options {
    var sourceRef = ""
    var outputDirectory = ""
    var verifyOnly = false
    var innerRef = ""
    var innerCommit = ""
    var innerTree = ""
    var innerRemote = ""
    var authorityRoot = ""
    var testBootstrap = false
}

func parseOptions() -> Options {
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
        case "--verified-source-ref": result.innerRef = value()
        case "--verified-source-commit": result.innerCommit = value()
        case "--verified-source-tree": result.innerTree = value()
        case "--verified-source-remote": result.innerRemote = value()
        case "--authority-root": result.authorityRoot = value()
        case "--test-bootstrap": result.testBootstrap = true
        case "-h", "--help":
            print("Usage: scripts/package-user-release [--source-ref REF] [--output-dir PATH] [--verify-source-only]")
            exit(0)
        default: fail("unknown option: \(argument)")
        }
        index += 1
    }
    return result
}

private func loadAuthority(root: String, home: String, temporary: String) -> [String: String] {
    let path = URL(fileURLWithPath: root).appendingPathComponent(".env.release.local").path
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
        fail("publisher authority file is missing; run Publisher Setup")
    }
    var metadata = stat()
    guard lstat(path, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == S_IFREG,
          metadata.st_uid == getuid(),
          (metadata.st_mode & 0o077) == 0 else {
        fail("publisher authority file ownership or mode is unsafe")
    }
    let shell = "set -a; source \"$1\"; /usr/bin/env -0"
    let result = run("/bin/bash", ["--noprofile", "--norc", "-c", shell, "release-authority", path],
                     environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home, "TMPDIR": temporary])
    guard result.status == 0 else { fail("could not load publisher authority file") }
    var values: [String: String] = [:]
    for item in result.output.split(separator: "\0", omittingEmptySubsequences: true) {
        let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        if pair.count == 2 { values[String(pair[0])] = String(pair[1]) }
    }
    return values
}

let options = parseOptions()
let source = ProcessInfo.processInfo.environment
let home = source["HOME"] ?? NSHomeDirectory()
let temporary = source["TMPDIR"] ?? "/tmp"
let environment = cleanEnvironment(home: home, temporary: temporary)
let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repositoryRoot = executable.deletingLastPathComponent().deletingLastPathComponent().path
let isInner = !options.innerCommit.isEmpty || !options.innerTree.isEmpty || !options.innerRef.isEmpty

if !isInner {
    if let key = authorityKeys.first(where: { source[$0] != nil }) {
        fail("release authority must not be supplied to the credential-free bootstrap: \(key)")
    }
    if source["CT_RELEASE_CHECKOUT"] != nil { fail("CT_RELEASE_CHECKOUT is not a supported release authority") }
    let testRemote = source["CT_RELEASE_BOOTSTRAP_TEST_REMOTE"]
    if testRemote != nil && !options.verifyOnly { fail("bootstrap test remote is verification-only") }
    let remote = testRemote ?? canonicalRemote
    let allowLocalFixture = testRemote != nil
    var requested = options.sourceRef
    if requested.isEmpty {
        requested = gitValue(["branch", "--show-current"], checkout: repositoryRoot,
                             environment: environment, allowLocalFixture: false)
    }
    if requested.isEmpty { fail("--source-ref is required from a detached checkout") }
    let resolved = resolveRef(remote: remote, requested: requested, environment: environment,
                              allowLocalFixture: allowLocalFixture)
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("control-tower-bootstrap.\(UUID().uuidString)")
        .standardizedFileURL.path
    try? FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: scratch) }
    let checkout = URL(fileURLWithPath: scratch).appendingPathComponent("checkout")
        .standardizedFileURL.path
    let clone = trustedGit(["clone", "--quiet", "--no-checkout", remote, checkout],
                           environment: environment, allowLocalFixture: allowLocalFixture)
    guard clone.status == 0 else { fail("could not clone approved release source") }
    let checkoutResult = trustedGit(["-C", checkout, "checkout", "--quiet", "--detach", resolved.1],
                                    environment: environment, allowLocalFixture: allowLocalFixture)
    guard checkoutResult.status == 0 else { fail("could not detach approved release source") }
    let tree = gitValue(["rev-parse", "HEAD^{tree}"], checkout: checkout, environment: environment,
                        allowLocalFixture: allowLocalFixture)
    verifyCheckout(checkout: checkout, remote: remote, ref: resolved.0, commit: resolved.1, tree: tree,
                   environment: environment, allowLocalFixture: allowLocalFixture)
    var innerArguments = [
        "--verified-source-ref", resolved.0,
        "--verified-source-commit", resolved.1,
        "--verified-source-tree", tree,
        "--verified-source-remote", remote,
        "--authority-root", repositoryRoot,
    ]
    if options.verifyOnly { innerArguments.append("--verify-source-only") }
    if allowLocalFixture { innerArguments.append("--test-bootstrap") }
    if !options.outputDirectory.isEmpty { innerArguments += ["--output-dir", options.outputDirectory] }
    let inner = run("\(checkout)/scripts/package-user-release", innerArguments,
                    environment: environment, currentDirectory: checkout, capture: false)
    exit(inner.status)
}

guard !options.innerRef.isEmpty, !options.innerCommit.isEmpty, !options.innerTree.isEmpty,
      !options.innerRemote.isEmpty, !options.authorityRoot.isEmpty else {
    fail("verified inner source arguments are incomplete")
}
guard options.innerRemote == canonicalRemote || (options.testBootstrap && options.verifyOnly) else {
    fail("inner release remote is not approved")
}
verifyCheckout(checkout: repositoryRoot, remote: options.innerRemote, ref: options.innerRef,
               commit: options.innerCommit, tree: options.innerTree, environment: environment,
               allowLocalFixture: options.testBootstrap)
if options.testBootstrap {
    print("release bootstrap source verified: \(options.innerRef) \(options.innerCommit) \(options.innerTree)")
    exit(0)
}

let implementation = executable.deletingLastPathComponent().appendingPathComponent("package-user-release.program").path
guard let implementationBody = FileManager.default.contents(atPath: implementation) else {
    fail("release implementation is missing")
}
var challengeBytes = [UInt8](repeating: 0, count: 32)
arc4random_buf(&challengeBytes, challengeBytes.count)
let challenge = challengeBytes.map { String(format: "%02x", $0) }.joined()
var streamedBody = Data("CT_RELEASE_STREAM_CHALLENGE='\(challenge)'\n".utf8)
streamedBody.append(implementationBody)
var childEnvironment: [String: String] = [
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home, "TMPDIR": temporary,
    "CT_RELEASE_STREAM": "1", "CT_RELEASE_EXPECTED_CHALLENGE": challenge,
    "CT_RELEASE_LAUNCHER_PATH": executable.path,
    "CT_RELEASE_IMPLEMENTATION_PATH": implementation,
]
if !options.verifyOnly {
    let authority = loadAuthority(root: options.authorityRoot, home: home, temporary: temporary)
    for key in authorityKeys where !(authority[key] ?? "").isEmpty { childEnvironment[key] = authority[key] }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = ["--noprofile", "--norc", "-s", "--",
                     "--verified-source-ref", options.innerRef,
                     "--verified-source-commit", options.innerCommit,
                     "--verified-source-tree", options.innerTree] +
                    (options.verifyOnly ? ["--verify-source-only"] : []) +
                    (options.outputDirectory.isEmpty ? [] : ["--output-dir", options.outputDirectory])
process.environment = childEnvironment
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
