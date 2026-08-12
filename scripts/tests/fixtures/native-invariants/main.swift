import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("native presentation invariant failed: \(message)\n", stderr)
        exit(1)
    }
}

require(Layer.foundation.plainLanguageName == "Core setup", "foundation name")
require(Layer.org.plainLanguageName == "Your organization", "organization name")
require(Layer.dept.plainLanguageName == "Your department", "department name")
require(Layer.personal.plainLanguageName == "This Mac", "personal name")

require(Severity.pass.plainLanguageStatus == "Ready", "passing component status")
require(Severity.warn.plainLanguageStatus == "Needs review", "warning component status")
require(Severity.fail.plainLanguageStatus == "Needs attention", "failing component status")
require(LayerSeverity.none.plainLanguageStatus == "Not reported", "absent layer status")

let component = ComponentView(
    component: "Claude Copilot",
    worstSeverity: .fail,
    layers: [
        LayerView(layer: .foundation, severity: .pass, badgeState: .pass, detail: nil),
        LayerView(layer: .org, severity: .warn, badgeState: .hollow, detail: nil),
        LayerView(layer: .dept, severity: .fail, badgeState: .triangle, detail: nil),
        LayerView(layer: .personal, severity: .none, badgeState: .hollow, detail: nil),
    ]
)

let expectedSummary = "Core setup: Ready · Your organization: Needs review · Your department: Needs attention · This Mac: Not reported"
require(component.plainLanguageLayerSummary == expectedSummary, "visible summary")
require(
    component.plainLanguageAccessibilityLabel
        == "Claude Copilot, Needs attention. \(expectedSummary)",
    "accessibility summary"
)

let forbiddenTokens = ["foundation", "org:", "dept", "personal", "pass", "warn", "fail"]
let rendered = component.plainLanguageAccessibilityLabel.lowercased()
for token in forbiddenTokens {
    require(!rendered.contains(token), "raw token leaked: \(token)")
}

print("native presentation invariants: PASS")
