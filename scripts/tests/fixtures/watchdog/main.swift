import Darwin
import Foundation

let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let resources = executable
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources", isDirectory: true)
let probe = resources.appendingPathComponent("probe.log")
let remaining = resources.appendingPathComponent("remaining-crashes")

let line = "\(getpid())\n"
if let data = line.data(using: .utf8) {
    if FileManager.default.fileExists(atPath: probe.path),
       let handle = try? FileHandle(forWritingTo: probe) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
    } else {
        try? data.write(to: probe, options: .atomic)
    }
}

let raw = (try? String(contentsOf: remaining, encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
let crashCount = Int(raw) ?? 0
if crashCount > 0 {
    try? "\(crashCount - 1)\n".write(to: remaining, atomically: true, encoding: .utf8)
    exit(17)
}
exit(0)
