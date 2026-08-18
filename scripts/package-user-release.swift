import Darwin
import Foundation
import Security

private let bundle = "/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"
private let anchor = bundle + "/Contents/MacOS/ct-publisher-bootstrap"
private let identifier = "com.everyoneneedsacopilot.controltower.publisher-bootstrap"
private let teamID = "3SYGVX2HB8"
private let allowedFlags: Set<String> = ["--source-ref", "--output-dir"]

private func refuse(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
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

private func requireProtected(_ path: String, directory: Bool) {
    var metadata = stat()
    guard lstat(path, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == (directory ? S_IFDIR : S_IFREG),
          metadata.st_uid == 0, (metadata.st_mode & 0o022) == 0,
          access(path, W_OK) != 0, !hasExtendedACL(path) else {
        refuse("the protected publisher bootstrap path is unsafe")
    }
}

private func preflightProtectedAnchor() {
    for directory in [
        "/", "/Library", "/Library/PrivilegedHelperTools", bundle,
        bundle + "/Contents", bundle + "/Contents/MacOS",
    ] { requireProtected(directory, directory: true) }
    requireProtected(anchor, directory: false)

    var staticCode: SecStaticCode?
    var requirement: SecRequirement?
    let expression = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: bundle) as CFURL, [], &staticCode) == errSecSuccess,
          SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
          let staticCode, let requirement,
          SecStaticCodeCheckValidity(
              staticCode, SecCSFlags(rawValue: (1 << 4) | (1 << 0)), requirement
          ) == errSecSuccess else {
        refuse("the protected publisher bootstrap code identity is invalid")
    }
}

var forwarded = [anchor]
var index = 1
while index < CommandLine.arguments.count {
    let argument = CommandLine.arguments[index]
    if argument == "--verify-source-only" {
        forwarded.append(argument)
        index += 1
        continue
    }
    if argument == "-h" || argument == "--help" {
        print("Usage: scripts/package-user-release --source-ref REF [--output-dir PATH] [--verify-source-only]")
        exit(0)
    }
    guard allowedFlags.contains(argument), index + 1 < CommandLine.arguments.count else {
        refuse("unsupported publisher-bootstrap argument")
    }
    forwarded.append(argument)
    forwarded.append(CommandLine.arguments[index + 1])
    index += 2
}

guard forwarded.contains("--source-ref") else { refuse("--source-ref is required") }
preflightProtectedAnchor()
forwarded.withUnsafeMutableBufferPointer { buffer in
    let argv = buffer.map { strdup($0) } + [nil]
    defer { argv.compactMap { $0 }.forEach { free($0) } }
    execv(anchor, argv)
}
refuse("the protected publisher bootstrap is unavailable")
