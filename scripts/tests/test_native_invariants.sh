#!/usr/bin/env bash
# Shipping-native fitness gate for the witness and plain-language boundaries.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NATIVE_ROOT="${REPO_ROOT}/native"

die() {
    echo "native invariants: $*" >&2
    exit 1
}

native_files=("${NATIVE_ROOT}"/*.swift)
[[ ${#native_files[@]} -gt 0 ]] || die "no shipping Swift files found"

# Internal identifiers remain legitimate in DTO/model logic. They may not be
# interpolated into presentation copy. This covers the exact bypasses that
# previously reached both visible text and VoiceOver.
if rg -n '\.(severity|worstSeverity)\.rawValue|\.layer\.label' "${native_files[@]}"; then
    die "raw layer or severity vocabulary reaches a native presentation path"
fi

# A checker is a finding, not a component/layer verdict. The current doctor
# contract carries only one authoritative display status (`doctor.status`).
# Reject the app-owned worst-wins/ready aggregation shapes that previously
# turned checker facts into a second health engine.
health_derivation_pattern='worstSeverity\(|contains\(where: \{ \$0\.severity|allSatisfy \{ \$0\.kind == \.ready|overallKind'
if rg -n "${health_derivation_pattern}" "${native_files[@]}"; then
    die "native Swift derives a health verdict not supplied by cc"
fi

# Missing checker attribution is unknown. It is not proof that a person is
# unentitled or absent from a layer.
if rg -n -F "You're not in this one" "${native_files[@]}"; then
    die "missing checker evidence became a confident membership claim"
fi

# Future role values must remain unknown. Any default-to-Personal branch turns
# an unrecognized shared scope into a false privacy claim, whether it returns
# person-facing text directly or first assigns the Personal enum case.
role_default_pattern='default:[^\n]*(\.personal|"This Mac"|"Personal")'
if rg -n "${role_default_pattern}" "${native_files[@]}"; then
    die "unknown role defaults to Personal/This Mac"
fi

# Process execution is confined to the typed cc client and the separately
# packaged Admin operator boundary. Views/render-state/models must stay pure.
while IFS= read -r source; do
    case "$(basename "${source}")" in
        cli-client.swift|admin.swift) ;;
        *) die "Process() escaped an approved native boundary: ${source#${REPO_ROOT}/}" ;;
    esac
done < <(rg -l -F 'Process()' "${native_files[@]}" || true)

# Prove the scanner has a negative shape, so a typo cannot silently turn the
# repository scan into an always-green check.
if ! printf '%s\n' 'Text("\(row.severity.rawValue)")' |
    rg -q '\.(severity|worstSeverity)\.rawValue|\.layer\.label'; then
    die "raw-token negative control did not trigger"
fi
if ! printf '%s\n' 'private static func worstSeverity(_ rows: [Row]) -> Severity' |
    rg -q "${health_derivation_pattern}"; then
    die "health-derivation negative control did not trigger"
fi
if ! printf '%s\n' 'return "You’re not in this one"' |
    rg -q "not in this one"; then
    die "missing-evidence negative control did not trigger"
fi
for optimistic_role_default in \
    'default: layer = .personal' \
    'default: return "This Mac"' \
    'default: return "Personal"'; do
    if ! printf '%s\n' "${optimistic_role_default}" |
        rg -q "${role_default_pattern}"; then
        die "unknown-role negative control did not trigger: ${optimistic_role_default}"
    fi
done

scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-native-invariants.XXXXXX")"
cleanup() {
    rm -rf "${scratch}"
}
trap cleanup EXIT

CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc \
    "${SCRIPT_DIR}/fixtures/native-invariants/main.swift" \
    "${NATIVE_ROOT}/models.swift" \
    -o "${scratch}/native-presentation-invariants"
"${scratch}/native-presentation-invariants"

echo "native invariants: PASS (${#native_files[@]} shipping Swift files scanned)"
