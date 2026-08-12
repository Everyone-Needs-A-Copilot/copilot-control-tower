//
// scripts/tests/test_cli_locator_trust_boundary.sh's driver.
//
// Proves Finding A (`tc wp get 525`) is actually fixed: once this process
// is itself running as the compiled-in-trusted, Developer-ID-signed article
// (`ProductionTrustAnchor`, `native/cli-client.swift`), `CliLocator.locate()`
// refuses a `CT_CLI_PATH` override that does not carry the same trust
// anchor, and falls back to the bundled/standard resolution exactly as an
// unset override already does. It also proves the fix is not a blanket
// "disable the override" — a legitimately re-signed override (the
// support/reinstall scenario the security review's remediation text names)
// is still accepted. And it proves every existing dev/test build (ad-hoc
// signed, which is everything `scripts/build-user.command` produces outside
// the release pipeline's own final signing step) keeps the historical
// override seam completely unchanged.
//
// `runningExecutablePath`/`bundledResourceURL` are `CliLocator.locate()`'s
// own injectable test seam — this drives the exact production code path,
// never a re-implementation of its logic.

import Foundation

var failureCount = 0
func check(_ name: String, _ passed: Bool, _ detail: @autoclosure () -> String = "") {
    if passed {
        print("ok - \(name)")
    } else {
        failureCount += 1
        print("not ok - \(name)  (\(detail()))")
    }
}

guard CommandLine.arguments.count == 6 else {
    print(
        "usage: cli-locator-trust-main <production-signed-self> "
            + "<adhoc-signed-self> <bundled-dir> <unverified-override> "
            + "<trusted-override>"
    )
    exit(2)
}
let productionSignedSelf = CommandLine.arguments[1]
let adhocSignedSelf = CommandLine.arguments[2]
let bundledDir = URL(fileURLWithPath: CommandLine.arguments[3])
let bundledCC = bundledDir.appendingPathComponent("cc")
let unverifiedOverride = CommandLine.arguments[4]
let trustedOverride = CommandLine.arguments[5]

// Sanity: the trust anchor itself must actually distinguish these fixtures
// before the higher-level `locate()` assertions below can mean anything.
check(
    "ProductionTrustAnchor accepts the real-Developer-ID-signed fixture",
    ProductionTrustAnchor.isSatisfied(byFileAt: productionSignedSelf)
)
check(
    "ProductionTrustAnchor rejects the ad-hoc-signed fixture",
    !ProductionTrustAnchor.isSatisfied(byFileAt: adhocSignedSelf)
)
check(
    "ProductionTrustAnchor rejects the unverified override candidate",
    !ProductionTrustAnchor.isSatisfied(byFileAt: unverifiedOverride)
)
check(
    "ProductionTrustAnchor accepts the trusted override candidate",
    ProductionTrustAnchor.isSatisfied(byFileAt: trustedOverride)
)

// The actual Finding A regression proof: a production-signed running app
// must never execute an unverified CT_CLI_PATH target.
setenv("CT_CLI_PATH", unverifiedOverride, 1)
let refused = CliLocator.locate(
    bundledResourceURL: bundledDir,
    runningExecutablePath: productionSignedSelf
)
check(
    "signed release path refuses an unverified CT_CLI_PATH override and falls back to the bundled cc",
    refused?.standardizedFileURL == bundledCC.standardizedFileURL,
    "got \(String(describing: refused))"
)

// Not a blanket kill switch: an override that itself carries the compiled-in
// trust anchor (a genuinely re-signed replacement cc) is still honored.
setenv("CT_CLI_PATH", trustedOverride, 1)
let accepted = CliLocator.locate(
    bundledResourceURL: bundledDir,
    runningExecutablePath: productionSignedSelf
)
check(
    "signed release path accepts a CT_CLI_PATH override that shares the compiled-in trust anchor",
    accepted?.standardizedFileURL == URL(fileURLWithPath: trustedOverride).standardizedFileURL,
    "got \(String(describing: accepted))"
)

// Every dev/test build in this repo is ad-hoc signed (or, mid-release-
// pipeline, briefly unsigned) — none of it satisfies ProductionTrustAnchor,
// so the historical, unverified override seam must be completely unchanged
// there. This is what keeps scripts/tests/smoke-scenarios.sh and friends
// working without modification.
setenv("CT_CLI_PATH", unverifiedOverride, 1)
let devBuildResult = CliLocator.locate(
    bundledResourceURL: bundledDir,
    runningExecutablePath: adhocSignedSelf
)
check(
    "ad-hoc-signed (dev/test) build keeps honoring CT_CLI_PATH unchanged",
    devBuildResult?.standardizedFileURL == URL(fileURLWithPath: unverifiedOverride).standardizedFileURL,
    "got \(String(describing: devBuildResult))"
)

// An unset override in the signed release path is unaffected by any of the
// above — it always resolved the bundled cc, and still does.
unsetenv("CT_CLI_PATH")
let noOverride = CliLocator.locate(
    bundledResourceURL: bundledDir,
    runningExecutablePath: productionSignedSelf
)
check(
    "an unset override still resolves the bundled cc in the signed release path",
    noOverride?.standardizedFileURL == bundledCC.standardizedFileURL,
    "got \(String(describing: noOverride))"
)

// Crash-only supervision is allowed to mutate LaunchAgents only for an
// ordinary manual launch of the trusted production article at its canonical
// installed path. Every harness/copy/managed-child shape stays inert.
let canonicalApp = "/Applications/Copilot Control Tower.app"
check(
    "trusted canonical manual launch is eligible for watchdog handoff",
    LaunchdSupervisor.shouldActivateCurrentApp(
        environment: [:],
        arguments: [canonicalApp + "/Contents/MacOS/Copilot Control Tower"],
        bundlePath: canonicalApp,
        executablePath: productionSignedSelf
    )
)
check(
    "trusted canonical app is accepted for explicit watchdog install",
    LaunchdSupervisor.isTrustedInstalledApp(
        bundlePath: canonicalApp,
        executablePath: productionSignedSelf
    )
)
check(
    "ad-hoc canonical app is rejected for explicit watchdog install",
    !LaunchdSupervisor.isTrustedInstalledApp(
        bundlePath: canonicalApp,
        executablePath: adhocSignedSelf
    )
)
check(
    "trusted noncanonical app is rejected for explicit watchdog install",
    !LaunchdSupervisor.isTrustedInstalledApp(
        bundlePath: "/tmp/Copilot Control Tower.app",
        executablePath: productionSignedSelf
    )
)
check(
    "launchd-managed child cannot recursively activate watchdog",
    !LaunchdSupervisor.shouldActivateCurrentApp(
        environment: [LaunchdSupervisor.managedEnvironmentKey: "1"],
        arguments: [canonicalApp + "/Contents/MacOS/Copilot Control Tower"],
        bundlePath: canonicalApp,
        executablePath: productionSignedSelf
    )
)
check(
    "selftest launch cannot activate watchdog",
    !LaunchdSupervisor.shouldActivateCurrentApp(
        environment: ["CT_SELFTEST": "1"],
        arguments: [canonicalApp + "/Contents/MacOS/Copilot Control Tower"],
        bundlePath: canonicalApp,
        executablePath: productionSignedSelf
    )
)
check(
    "copied candidate cannot activate watchdog",
    !LaunchdSupervisor.shouldActivateCurrentApp(
        environment: [:],
        arguments: ["/tmp/Copilot Control Tower.app/Contents/MacOS/Copilot Control Tower"],
        bundlePath: "/tmp/Copilot Control Tower.app",
        executablePath: productionSignedSelf
    )
)
check(
    "ad-hoc app cannot activate watchdog",
    !LaunchdSupervisor.shouldActivateCurrentApp(
        environment: [:],
        arguments: [canonicalApp + "/Contents/MacOS/Copilot Control Tower"],
        bundlePath: canonicalApp,
        executablePath: adhocSignedSelf
    )
)
check(
    "headless argument cannot activate watchdog",
    !LaunchdSupervisor.shouldActivateCurrentApp(
        environment: [:],
        arguments: [canonicalApp + "/Contents/MacOS/Copilot Control Tower", "--headless-detect"],
        bundlePath: canonicalApp,
        executablePath: productionSignedSelf
    )
)

if failureCount == 0 {
    print("cli-locator trust boundary: ALL ASSERTIONS PASSED")
    exit(0)
} else {
    print("cli-locator trust boundary: \(failureCount) ASSERTION(S) FAILED")
    exit(1)
}
