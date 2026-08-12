import Foundation

let root = CommandLine.arguments[1]
let program = root + "/scripts/package-user-release.program"
let launcher = root + "/scripts/package-user-release"
let challenge = "foreign-parent-challenge"
var body = Data("CT_RELEASE_STREAM_CHALLENGE='\(challenge)'\n".utf8)
body.append(FileManager.default.contents(atPath: program)!)

let child = Process()
let pipe = Pipe()
child.executableURL = URL(fileURLWithPath: "/bin/bash")
child.arguments = ["--noprofile", "--norc", "-s", "--", "--help"]
child.environment = [
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "CT_RELEASE_STREAM": "1",
    "CT_RELEASE_EXPECTED_CHALLENGE": challenge,
    "CT_RELEASE_LAUNCHER_PATH": launcher,
    "CT_RELEASE_IMPLEMENTATION_PATH": program,
]
child.standardInput = pipe
child.standardOutput = FileHandle.nullDevice
child.standardError = FileHandle.nullDevice
try child.run()
pipe.fileHandleForWriting.write(body)
pipe.fileHandleForWriting.closeFile()
child.waitUntilExit()
exit(child.terminationStatus == 0 ? 1 : 0)
