#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-release-source.XXXXXX")"
cleanup() { chmod -R u+w "${scratch}" 2>/dev/null || true; rm -rf "${scratch}"; }
trap cleanup EXIT

"${ROOT}/scripts/verify-release-launcher.sh"

# The repository adapter is intentionally inert. It has no Git, shell,
# credential, network, build, signing, notary, or private-inner surface and can
# forward only public operator intent to one fixed protected executable.
python3 - "${ROOT}/scripts/package-user-release.swift" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
assert 'private let bundle = "/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"' in source
assert 'private let anchor = bundle + "/Contents/MacOS/ct-publisher-bootstrap"' in source
assert "execv(anchor, argv)" in source
for forbidden in (
    "/usr/bin/git", "Process()", "URLSession", "GH_TOKEN", "GITHUB_TOKEN",
    "CT_SIGN_IDENTITY", "CT_NOTARY", "--verified-source", "--materialized-root",
    "--test-bootstrap", "credential", "notarytool", "codesign",
):
    assert forbidden not in source, forbidden
PY
echo "PASS: repository adapter has zero release, network, or credential authority"

test_anchor="${scratch}/ct-publisher-bootstrap-test"
/usr/bin/swiftc -D CT_PUBLISHER_BOOTSTRAP_TEST_BUILD \
    "${ROOT}/publisher-bootstrap/PublisherBootstrap.swift" -o "${test_anchor}"
/bin/chmod 755 "${test_anchor}"

# The first executable lives beneath a non-replaceable directory-entry chain.
# The hermetic seam uses the current uid only so it can construct the same
# owner/mode/type contract without administrator mutation.
chain_root="${scratch}/protected-chain"
chain_bundle="${chain_root}/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"
chain_executable="${chain_bundle}/Contents/MacOS/ct-publisher-bootstrap"
/bin/mkdir -p "${chain_bundle}/Contents/MacOS"
/bin/cp "${test_anchor}" "${chain_executable}"
/bin/chmod 0555 "${chain_root}" "${chain_root}/Library" \
    "${chain_root}/Library/PrivilegedHelperTools" "${chain_bundle}" \
    "${chain_bundle}/Contents" "${chain_bundle}/Contents/MacOS" "${chain_executable}"
chain_root="$(cd "${chain_root}" && /bin/pwd -P)"
chain_bundle="${chain_root}/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"
chain_executable="${chain_bundle}/Contents/MacOS/ct-publisher-bootstrap"
chain_env=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="${scratch}" TMPDIR="${scratch}" \
    CT_PUBLISHER_BOOTSTRAP_TEST=1 CT_PUBLISHER_BOOTSTRAP_TEST_CHAIN_ROOT="${chain_root}")
[[ "$("${chain_env[@]}" "${chain_executable}")" == "publisher bootstrap synthetic protected path: PASS" ]]
if /bin/mv "${chain_executable}" "${chain_executable}.replaced" 2>/dev/null; then
    echo "FAIL: protected anchor directory entry was replaceable" >&2; exit 1
fi
/bin/chmod 0755 "${chain_root}/Library"
if "${chain_env[@]}" "${chain_executable}" >/dev/null 2>&1; then
    echo "FAIL: writable trust ancestor was accepted" >&2; exit 1
fi
/bin/chmod 0555 "${chain_root}/Library"
if "${chain_env[@]}" "${test_anchor}" >/dev/null 2>&1; then
    echo "FAIL: copied publisher anchor was accepted" >&2; exit 1
fi
/bin/chmod 0755 "${chain_bundle}/Contents/MacOS"
/bin/mv "${chain_executable}" "${chain_executable}.regular"
/bin/ln -s "${chain_executable}.regular" "${chain_executable}"
/bin/chmod 0555 "${chain_bundle}/Contents/MacOS"
if "${chain_env[@]}" "${chain_executable}" >/dev/null 2>&1; then
    echo "FAIL: symlink publisher anchor was accepted" >&2; exit 1
fi
/bin/chmod 0755 "${chain_bundle}/Contents/MacOS"
/bin/rm "${chain_executable}"
/bin/mv "${chain_executable}.regular" "${chain_executable}"
/bin/chmod 0555 "${chain_bundle}/Contents/MacOS"
/bin/chmod +a "user:$(/usr/bin/id -un) allow read" "${chain_root}/Library"
if "${chain_env[@]}" "${chain_executable}" >/dev/null 2>&1; then
    echo "FAIL: extended ACL on trust ancestor was accepted" >&2; exit 1
fi
/bin/chmod -N "${chain_root}/Library"
echo "PASS: root-only anchor chain rejects replacement, writable ancestor, copy, symlink, and ACL"

# The process is environment-empty from its shebang onward. Hostile startup
# hooks and TMPDIR text cannot run before immutable verification or select a
# privileged script path.
startup_root="${scratch}/hostile-startup"
/bin/mkdir -p "${startup_root}/python"
startup_marker="${startup_root}/sitecustomize-ran"
shell_marker="${startup_root}/shell-startup-ran"
tmp_marker="${startup_root}/tmp-injection-ran"
/usr/bin/printf 'from pathlib import Path\nPath("%s").write_text("ran")\n' "${startup_marker}" > "${startup_root}/python/sitecustomize.py"
/usr/bin/printf '#!/bin/bash\n/usr/bin/touch "%s"\n' "${shell_marker}" > "${startup_root}/startup.sh"
/bin/chmod 0755 "${startup_root}/startup.sh"
PYTHONPATH="${startup_root}/python" PYTHONHOME="${startup_root}/python" \
  BASH_ENV="${startup_root}/startup.sh" ENV="${startup_root}/startup.sh" \
  TMPDIR="${startup_root}/'\$(/usr/bin/touch ${tmp_marker})'" \
  "${ROOT}/scripts/provision-publisher-bootstrap.sh" --help >/dev/null
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="${startup_root}" TMPDIR="${startup_root}" \
  PYTHONPATH="${startup_root}/python" /usr/bin/python3 -I -E -s - <<'PY'
print("isolated verifier")
PY
[[ ! -e "${startup_marker}" && ! -e "${shell_marker}" && ! -e "${tmp_marker}" ]]
echo "PASS: hostile Python, shell startup, and TMPDIR authority are inert before trust"

# Build the exact current source as an authenticated, payload-only local package.
# The seam uses an ad-hoc app and an unsigned, visibly named package; it never
# invokes Installer or changes a protected system path.
package_work="${scratch}/package-source"
package_remote="${scratch}/package-source.git"
package_output="${scratch}/package-output"
/bin/mkdir "${package_work}"
/usr/bin/git -C "${ROOT}" archive HEAD | /usr/bin/tar -x -C "${package_work}"
while IFS= read -r changed; do
    [[ -z "${changed}" ]] || /usr/bin/ditto "${ROOT}/${changed}" "${package_work}/${changed}"
done < <(/usr/bin/git -C "${ROOT}" diff --name-only)
/usr/bin/git -C "${package_work}" init -q -b main
/usr/bin/git -C "${package_work}" config user.name fixture
/usr/bin/git -C "${package_work}" config user.email fixture@example.invalid
/usr/bin/git -C "${package_work}" add .
/usr/bin/git -C "${package_work}" commit -qm package-fixture
/usr/bin/git clone -q --bare "${package_work}" "${package_remote}"
package_commit="$(/usr/bin/git -C "${package_work}" rev-parse HEAD)"
package_tree="$(/usr/bin/git -C "${package_work}" rev-parse 'HEAD^{tree}')"
"${ROOT}/scripts/provision-publisher-bootstrap.sh" \
    --source-remote "file://${package_remote}" --source-ref refs/heads/main \
    --source-commit "${package_commit}" --source-tree "${package_tree}" \
    --package-version 1.0.1 --output-dir "${package_output}" --local-test-only >/dev/null
package="${package_output}/Copilot-Control-Tower-Publisher-Bootstrap.unsigned-input.pkg"
package_output_repeat="${scratch}/package-output-repeat"
"${ROOT}/scripts/provision-publisher-bootstrap.sh" \
    --source-remote "file://${package_remote}" --source-ref refs/heads/main \
    --source-commit "${package_commit}" --source-tree "${package_tree}" \
    --package-version 1.0.1 --output-dir "${package_output_repeat}" --local-test-only >/dev/null
/usr/bin/cmp "${package_output}/source-input.json" "${package_output_repeat}/source-input.json"
/usr/bin/cmp "${package_output}/approval-manifest.template.json" "${package_output_repeat}/approval-manifest.template.json"
/usr/bin/cmp "${package}" "${package_output_repeat}/Copilot-Control-Tower-Publisher-Bootstrap.unsigned-input.pkg"
echo "PASS: repeated exact source/version preparation is byte-deterministic"
verify_package=("${ROOT}/scripts/verify-publisher-bootstrap.sh" --package "${package}"
    --expected-source-remote "file://${package_remote}" --expected-source-ref refs/heads/main
    --expected-source-commit "${package_commit}" --expected-source-tree "${package_tree}"
    --expected-app-team adhoc --allow-unsigned-test)
"${verify_package[@]}" >/dev/null
echo "PASS: package has zero scripts and exact payload, BOM ownership/modes, app identity, and source receipt"

# Source preparation emits an immutable schema template that cannot authorize
# itself. The tuple policy binds the out-of-band manifest digest to package A
# and enforces a strictly advancing version floor even for same-team inputs.
tuple_root="${scratch}/tuple-policy"
/bin/mkdir "${tuple_root}"
package_a="${tuple_root}/candidate-a.pkg"; package_b="${tuple_root}/candidate-b.pkg"
/usr/bin/printf 'same-team candidate A\n' > "${package_a}"
/usr/bin/printf 'same-team candidate B\n' > "${package_b}"
manifest_a="${tuple_root}/approval-a.json"
/usr/bin/python3 -I -E -s - "${manifest_a}" "${package_a}" "${package_commit}" "${package_tree}" <<'PY'
import hashlib, json, pathlib, sys
out, package, commit, tree = map(pathlib.Path, sys.argv[1:])
value = {
    "schema_version": 1,
    "status": "OWNER-APPROVED",
    "source": {
        "remote": "https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower.git",
        "ref": "refs/tags/publisher-anchor-1.0.1", "commit": commit.name, "tree": tree.name,
    },
    "package": {
        "identifier": "com.everyoneneedsacopilot.controltower.publisher-bootstrap.pkg",
        "version": "1.0.1", "installer_team_id": "3SYGVX2HB8",
        "final_signed_sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
    },
    "application": {
        "bundle_identifier": "com.everyoneneedsacopilot.controltower.publisher-bootstrap",
        "team_id": "3SYGVX2HB8", "cdhash": "a" * 40, "bundle_sha256": "b" * 64,
    },
    "anti_rollback": {"previous_package_version": "1.0.0", "minimum_package_version": "1.0.1"},
    "owner_approval": {"approval_id": "owner-approval-0001", "approved_at_utc": "2026-08-13T17:00:00Z"},
}
out.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
PY
manifest_a_sha="$(/usr/bin/shasum -a 256 "${manifest_a}" | /usr/bin/cut -d ' ' -f 1)"
"${ROOT}/scripts/verify-publisher-approval-tuple.py" "${manifest_a}" "${manifest_a_sha}" "${package_a}" >/dev/null
if "${ROOT}/scripts/verify-publisher-approval-tuple.py" "${manifest_a}" "${manifest_a_sha}" "${package_b}" >/dev/null 2>&1; then
    echo "FAIL: same-team package B substituted for owner-approved package A" >&2; exit 1
fi
manifest_downgrade="${tuple_root}/approval-downgrade.json"
/usr/bin/python3 -I -E -s - "${manifest_a}" "${manifest_downgrade}" <<'PY'
import json, pathlib, sys
value=json.loads(pathlib.Path(sys.argv[1]).read_text())
value["package"]["version"]="1.0.0"
value["anti_rollback"]={"previous_package_version":"1.0.0","minimum_package_version":"1.0.1"}
pathlib.Path(sys.argv[2]).write_text(json.dumps(value, sort_keys=True, separators=(",", ":"))+"\n")
PY
downgrade_sha="$(/usr/bin/shasum -a 256 "${manifest_downgrade}" | /usr/bin/cut -d ' ' -f 1)"
if "${ROOT}/scripts/verify-publisher-approval-tuple.py" "${manifest_downgrade}" "${downgrade_sha}" "${package_a}" >/dev/null 2>&1; then
    echo "FAIL: same-team package did not advance the approved version floor" >&2; exit 1
fi
manifest_extra="${tuple_root}/approval-extra-field.json"
/usr/bin/python3 -I -E -s - "${manifest_a}" "${manifest_extra}" <<'PY'
import json, pathlib, sys
value=json.loads(pathlib.Path(sys.argv[1]).read_text()); value["unreviewed_extension"]=True
pathlib.Path(sys.argv[2]).write_text(json.dumps(value, sort_keys=True, separators=(",", ":"))+"\n")
PY
extra_sha="$(/usr/bin/shasum -a 256 "${manifest_extra}" | /usr/bin/cut -d ' ' -f 1)"
if "${ROOT}/scripts/verify-publisher-approval-tuple.py" "${manifest_extra}" "${extra_sha}" "${package_a}" >/dev/null 2>&1; then
    echo "FAIL: approval manifest accepted an unreviewed schema field" >&2; exit 1
fi
if "${ROOT}/scripts/verify-publisher-approval-tuple.py" "${manifest_extra}" "${manifest_a_sha}" "${package_a}" >/dev/null 2>&1; then
    echo "FAIL: changed approval manifest accepted the prior out-of-band digest" >&2; exit 1
fi
for schema_case in true '"1"' 1.0 null '[]' '{}'; do
    schema_label="$(/usr/bin/printf '%s' "${schema_case}" | /usr/bin/shasum -a 256 | /usr/bin/cut -c 1-12)"
    schema_manifest="${tuple_root}/approval-schema-${schema_label}.json"
    /usr/bin/python3 -I -E -s - "${manifest_a}" "${schema_manifest}" "${schema_case}" <<'PY'
import json, pathlib, sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text())
value["schema_version"] = json.loads(sys.argv[3])
pathlib.Path(sys.argv[2]).write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
PY
    schema_sha="$(/usr/bin/shasum -a 256 "${schema_manifest}" | /usr/bin/cut -d ' ' -f 1)"
    if "${ROOT}/scripts/verify-publisher-approval-tuple.py" "${schema_manifest}" "${schema_sha}" "${package_a}" >/dev/null 2>&1; then
        echo "FAIL: approval manifest accepted non-integer schema type ${schema_case}" >&2; exit 1
    fi
done
template="${package_output}/approval-manifest.template.json"
template_sha="$(/usr/bin/shasum -a 256 "${template}" | /usr/bin/cut -d ' ' -f 1)"
if "${ROOT}/scripts/verify-publisher-approval-tuple.py" "${template}" "${template_sha}" "${package}" >/dev/null 2>&1; then
    echo "FAIL: incomplete checkout-generated manifest authorized installation" >&2; exit 1
fi
echo "PASS: exact tuple accepts A and rejects same-team B, downgrade, schema drift, digest drift, and self-approval"

# The compiled Publisher Bootstrap consumes the same schema-2 receipt contract
# carried by the package. Required nested fields are mandatory and unknown
# versions fail before Git/network or release authority.
receipt_expanded="${scratch}/receipt-expanded"
/usr/sbin/pkgutil --expand-full "${package}" "${receipt_expanded}"
package_receipt="${receipt_expanded}/Payload/Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap/approved-source.json"
# Keep the exact packaged schema/app identity while substituting a one-blob
# local source identity so this direct decoding behavior test stays bounded.
receipt_source="${scratch}/receipt-source"; receipt_remote="${scratch}/receipt-source.git"
/bin/mkdir "${receipt_source}"; /usr/bin/printf receipt > "${receipt_source}/README.md"
/usr/bin/git -C "${receipt_source}" init -q -b main
/usr/bin/git -C "${receipt_source}" config user.name fixture
/usr/bin/git -C "${receipt_source}" config user.email fixture@example.invalid
/usr/bin/git -C "${receipt_source}" add .; /usr/bin/git -C "${receipt_source}" commit -qm receipt
/usr/bin/git clone -q --bare "${receipt_source}" "${receipt_remote}"
receipt_commit="$(/usr/bin/git -C "${receipt_source}" rev-parse HEAD)"
receipt_tree="$(/usr/bin/git -C "${receipt_source}" rev-parse 'HEAD^{tree}')"
/usr/bin/python3 - "${package_receipt}" "${receipt_remote}" "${receipt_commit}" "${receipt_tree}" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); value=json.loads(p.read_text())
value.update(remote="file://"+sys.argv[2], commit=sys.argv[3], tree=sys.argv[4])
p.write_text(json.dumps(value, sort_keys=True, separators=(",", ":"))+"\n")
PY
receipt_env=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="${scratch}" TMPDIR="${scratch}"
  CT_PUBLISHER_BOOTSTRAP_TEST=1 CT_PUBLISHER_BOOTSTRAP_TEST_APPROVAL="${package_receipt}")
receipt_positive="$("${receipt_env[@]}" "${test_anchor}" --source-ref refs/heads/main --verify-source-only)"
[[ "${receipt_positive}" == "release source verified without Git metadata: refs/heads/main ${receipt_commit} ${receipt_tree}" ]]
/usr/bin/python3 - "${test_anchor}" "${package_receipt}" "${scratch}" <<'PY'
import json, os, pathlib, subprocess, sys
anchor, original, scratch = sys.argv[1:]
base = json.loads(pathlib.Path(original).read_text())
for label, value in (
    ("malformed", b"{not-json\n"),
    ("missing-app", json.dumps({key: item for key, item in base.items() if key != "app"}).encode()),
    ("missing-digest", json.dumps({**base, "app": {key: item for key, item in base["app"].items() if key != "bundle_sha256"}}).encode()),
    ("unknown-schema", json.dumps({**base, "schema_version": 99}).encode()),
    ("boolean-schema", json.dumps({**base, "schema_version": True}).encode()),
    ("string-schema", json.dumps({**base, "schema_version": "2"}).encode()),
    ("float-schema", json.dumps({**base, "schema_version": 2.0}).encode()),
    ("null-schema", json.dumps({**base, "schema_version": None}).encode()),
    ("array-schema", json.dumps({**base, "schema_version": []}).encode()),
    ("object-schema", json.dumps({**base, "schema_version": {}}).encode()),
):
    receipt = pathlib.Path(scratch) / f"receipt-{label}.json"
    receipt.write_bytes(value)
    env = {"PATH":"/usr/bin:/bin:/usr/sbin:/sbin", "HOME":scratch, "TMPDIR":scratch,
           "CT_PUBLISHER_BOOTSTRAP_TEST":"1", "CT_PUBLISHER_BOOTSTRAP_TEST_APPROVAL":str(receipt)}
    result = subprocess.run([anchor, "--source-ref", "refs/heads/main", "--verify-source-only"],
                            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
    assert result.returncode != 0, label
    assert result.stderr.startswith("error: publisher bootstrap approved-source record is invalid"), label
PY
echo "PASS: compiled bootstrap accepts package schema 2 and rejects malformed, missing, and unknown receipts"

expect_package_rejected() {
    local label="$1" mutation="$2" expanded="${scratch}/mutant-${1}" mutant="${scratch}/mutant-${1}.pkg"
    /usr/sbin/pkgutil --expand-full "${package}" "${expanded}"
    local app="${expanded}/Payload/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"
    local receipt="${expanded}/Payload/Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap/approved-source.json"
    case "${mutation}" in
        payload) /usr/bin/printf altered >> "${app}/Contents/MacOS/ct-publisher-bootstrap";;
        receipt) /usr/bin/python3 - "${receipt}" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); value=json.loads(p.read_text()); value["tree"]="b"*40; p.write_text(json.dumps(value)+"\n")
PY
            ;;
        extra) /usr/bin/printf extra > "${expanded}/Payload/Library/extra-path";;
        symlink) /bin/ln -s "Application Support/Everyone Needs a Copilot/Publisher Bootstrap/approved-source.json" \
            "${expanded}/Payload/Library/unsafe-link";;
        acl) /bin/chmod +a "user:$(/usr/bin/id -un) allow read" "${receipt}";;
        writable) /bin/chmod 0666 "${receipt}";;
        bundle)
            /usr/bin/plutil -replace CFBundleIdentifier -string com.example.foreign "${app}/Contents/Info.plist"
            /usr/bin/codesign --force --sign - "${app}" >/dev/null
            ;;
        candidate-b)
            /usr/bin/printf 'import Foundation\nprint("alternate candidate")\n' > "${expanded}/alternate.swift"
            /usr/bin/swiftc -O "${expanded}/alternate.swift" -o "${app}/Contents/MacOS/ct-publisher-bootstrap"
            /bin/rm "${expanded}/alternate.swift"
            /usr/bin/codesign --force --sign - "${app}" >/dev/null
            ;;
    esac
    /usr/sbin/pkgutil --flatten "${expanded}" "${mutant}"
    local args=("${ROOT}/scripts/verify-publisher-bootstrap.sh" --package "${mutant}"
        --expected-source-remote "file://${package_remote}" --expected-source-ref refs/heads/main
        --expected-source-commit "${package_commit}" --expected-source-tree "${package_tree}"
        --expected-app-team adhoc --allow-unsigned-test)
    if "${args[@]}" >/dev/null 2>&1; then
        echo "FAIL: ${label} package was accepted" >&2; exit 1
    fi
}
for package_case in payload receipt extra symlink acl writable bundle candidate-b; do
    expect_package_rejected "${package_case}" "${package_case}"
done
if "${ROOT}/scripts/verify-publisher-bootstrap.sh" --package "${package}" \
    --expected-source-remote "file://${package_remote}" --expected-source-ref refs/heads/main \
    --expected-source-commit "${package_commit}" --expected-source-tree "${package_tree}" \
    --expected-app-team 3SYGVX2HB8 >/dev/null 2>&1; then
    echo "FAIL: ad-hoc app or unsigned package crossed the real identity path" >&2; exit 1
fi
if [[ "${package_commit:0:1}" == b ]]; then wrong_commit="a${package_commit:1}"
else wrong_commit="b${package_commit:1}"; fi
if "${verify_package[@]/${package_commit}/${wrong_commit}}" >/dev/null 2>&1; then
    echo "FAIL: package accepted the wrong approved source commit" >&2; exit 1
fi
echo "PASS: altered payload/receipt, extra path, symlink, ACL, writable mode, wrong bundle/identity, and A/B substitution reject"

# A moved source ref cannot be used to reproduce an older approved package.
/usr/bin/printf 'moved\n' >> "${package_work}/README.md"
/usr/bin/git -C "${package_work}" add README.md
/usr/bin/git -C "${package_work}" commit -qm moved
/usr/bin/git -C "${package_work}" push -q "${package_remote}" HEAD:refs/heads/main
if "${ROOT}/scripts/provision-publisher-bootstrap.sh" \
    --source-remote "file://${package_remote}" --source-ref refs/heads/main \
    --source-commit "${package_commit}" --source-tree "${package_tree}" \
    --package-version 1.0.1 --output-dir "${scratch}/moved-output" --local-test-only >/dev/null 2>&1; then
    echo "FAIL: moved source ref reproduced the older package" >&2; exit 1
fi
echo "PASS: wrong and moved approved source identities fail closed"

# Source QA proves only the exact future Installer command and that neither the
# builder nor package verifier reads the rejected /Applications anchor. Actual
# replacement/failure/rollback behavior is an attended installed-state QA item.
/usr/bin/python3 - "${ROOT}/scripts/provision-publisher-bootstrap.sh" \
    "${ROOT}/scripts/verify-publisher-bootstrap.sh" \
    "${ROOT}/docs/07-contributing/publisher-release-runbook.md" <<'PY'
from pathlib import Path
import sys
builder, verifier, runbook = (Path(path).read_text() for path in sys.argv[1:])
assert "/usr/sbin/installer" not in builder
assert "/usr/sbin/installer" not in verifier
assert "/Applications/Copilot Control Tower Publisher Bootstrap.app" not in builder
assert "/Applications/Copilot Control Tower Publisher Bootstrap.app" not in verifier
installer = runbook.index("/usr/sbin/installer")
package_argument = runbook.index("-pkg /root-owned/non-writable/staging/EXACT_APPROVED_PACKAGE.pkg", installer)
target_argument = runbook.index("-target /", package_argument)
assert installer < package_argument < target_argument
assert "independent owner-approved package tuple is required" in verifier
assert "mutable checkout copy is not itself authority" in runbook
PY
missing_tuple_error="$(${ROOT}/scripts/verify-publisher-bootstrap.sh 2>&1 || true)"
[[ "${missing_tuple_error}" == "error: independent owner-approved package tuple is required" ]]
echo "PASS: source contract orders exact Installer package and never reads /Applications bytes"

# Invoke the production installed-state ancestry functions through their
# temporary-root seam. Every app and approval component is exercised against
# type, owner, writable-mode, ACL, and symlink failures.
ancestry_base="${scratch}/ancestry-base"
app_rel="/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"
approval_rel="/Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap/approved-source.json"
/bin/mkdir -p "${ancestry_base}${app_rel}/Contents/MacOS" "$(/usr/bin/dirname "${ancestry_base}${approval_rel}")"
/usr/bin/printf executable > "${ancestry_base}${app_rel}/Contents/MacOS/ct-publisher-bootstrap"
/usr/bin/printf receipt > "${ancestry_base}${approval_rel}"
/usr/bin/find "${ancestry_base}" -type d -exec /bin/chmod 0555 {} +
/usr/bin/find "${ancestry_base}" -type f -exec /bin/chmod 0444 {} +
ancestry_owner="$(/usr/bin/id -u)"
"${ROOT}/scripts/verify-publisher-bootstrap.sh" --installed-test-root "${ancestry_base}" \
    --installed-test-owner "${ancestry_owner}" >/dev/null
ancestor_entries=(
  "d:/Library" "d:/Library/PrivilegedHelperTools" "d:${app_rel}"
  "d:${app_rel}/Contents" "d:${app_rel}/Contents/MacOS"
  "f:${app_rel}/Contents/MacOS/ct-publisher-bootstrap"
  "d:/Library/Application Support" "d:/Library/Application Support/Everyone Needs a Copilot"
  "d:/Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap" "f:${approval_rel}"
)
ancestry_case=0
for entry in "${ancestor_entries[@]}"; do
  kind="${entry%%:*}"; relative="${entry#*:}"
  for mutation in type owner writable acl symlink; do
    fixture="${scratch}/ancestry-$((++ancestry_case))"
    /usr/bin/ditto "${ancestry_base}" "${fixture}"
    target="${fixture}${relative}"
    args=("${ROOT}/scripts/verify-publisher-bootstrap.sh" --installed-test-root "${fixture}"
      --installed-test-owner "${ancestry_owner}")
    case "${mutation}" in
      type)
        /bin/chmod u+w "$(/usr/bin/dirname "${target}")"
        if [[ "${kind}" == d ]]; then /bin/chmod -R u+w "${target}"; /bin/rm -rf "${target}"; /usr/bin/printf file > "${target}"
        else /bin/rm "${target}"; /bin/mkdir "${target}"; fi
        ;;
      owner) args+=(--installed-test-wrong-owner-path "${relative}");;
      writable) /bin/chmod u+w "${target}";;
      acl) /bin/chmod +a "user:$(/usr/bin/id -un) allow read" "${target}";;
      symlink)
        /bin/chmod u+w "$(/usr/bin/dirname "${target}")"
        if [[ -d "${target}" ]]; then /bin/chmod -R u+w "${target}"; /bin/rm -rf "${target}"; else /bin/rm "${target}"; fi
        /bin/ln -s "${ancestry_base}${relative}" "${target}"
        ;;
    esac
    if "${args[@]}" >/dev/null 2>&1; then
      echo "FAIL: ${relative} accepted ${mutation}" >&2; exit 1
    fi
  done
done
echo "PASS: production verifier rejects type/owner/mode/ACL/symlink across every app and approval component"

fixture_work="${scratch}/source"
fixture_remote="${scratch}/source.git"
/bin/mkdir -p "${fixture_work}/scripts"
/bin/cp "${ROOT}/scripts/package-user-release.program" "${fixture_work}/scripts/"
/usr/bin/printf 'public fixture\n' > "${fixture_work}/README.md"
/usr/bin/git -C "${fixture_work}" init -q -b main
/usr/bin/git -C "${fixture_work}" config user.name fixture
/usr/bin/git -C "${fixture_work}" config user.email fixture@example.invalid
/usr/bin/git -C "${fixture_work}" add .
/usr/bin/git -C "${fixture_work}" commit -qm fixture
/usr/bin/git clone -q --bare "${fixture_work}" "${fixture_remote}"
commit="$(/usr/bin/git -C "${fixture_work}" rev-parse HEAD)"
tree="$(/usr/bin/git -C "${fixture_work}" rev-parse 'HEAD^{tree}')"
approval="${scratch}/approved-source.json"
/bin/cat > "${approval}" <<JSON
{"schema_version":2,"remote":"file://${fixture_remote}","ref":"refs/heads/main","commit":"${commit}","tree":"${tree}","package_identifier":"com.everyoneneedsacopilot.controltower.publisher-bootstrap.pkg","app":{"path":"/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app","bundle_identifier":"com.everyoneneedsacopilot.controltower.publisher-bootstrap","team_id":"3SYGVX2HB8","cdhash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bundle_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}
JSON

anchor_env=(
    /usr/bin/env -i
    PATH=/usr/bin:/bin:/usr/sbin:/sbin
    HOME="${scratch}"
    TMPDIR="${scratch}"
    CT_PUBLISHER_BOOTSTRAP_TEST=1
    CT_PUBLISHER_BOOTSTRAP_TEST_APPROVAL="${approval}"
)

positive="$(${anchor_env[@]} "${test_anchor}" \
    --source-ref refs/heads/main --verify-source-only)"
[[ "${positive}" == "release source verified without Git metadata: refs/heads/main ${commit} ${tree}" ]]
echo "PASS: independently anchored bare-store bootstrap verifies approved no-.git source"

# A locally rebuilt, self-consistent repository launcher has no path to the
# anchor's root-owned approval contract. An unapproved source is refused before
# Git/network. Timeout bounds every malicious control.
python3 - "${test_anchor}" "${approval}" "${scratch}" <<'PY'
import os
from pathlib import Path
import subprocess
import sys

anchor, approval, scratch = sys.argv[1:]
base = {
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": scratch,
    "TMPDIR": scratch,
    "CT_PUBLISHER_BOOTSTRAP_TEST": "1",
    "CT_PUBLISHER_BOOTSTRAP_TEST_APPROVAL": approval,
}

def reject(label, args, extra=None):
    env = dict(base)
    if extra:
        env.update(extra)
    try:
        result = subprocess.run(
            [anchor, *args], env=env, cwd=scratch, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError(f"{label}: timeout") from error
    assert result.returncode != 0, f"{label}: unexpectedly accepted"
    assert result.stderr.startswith("error: "), f"{label}: unbounded error"
    for secret in ("AUTHORITY_SENTINEL", "TOKEN_SENTINEL"):
        assert secret not in result.stdout + result.stderr

reject("unapproved locally rebuilt ref", ["--source-ref", "refs/heads/locally-rebuilt", "--verify-source-only"])
reject("release authority before source trust", ["--source-ref", "refs/heads/main", "--verify-source-only"], {"CT_SIGN_IDENTITY":"AUTHORITY_SENTINEL"})
reject("Git authority before source trust", ["--source-ref", "refs/heads/main", "--verify-source-only"], {"GIT_CONFIG_GLOBAL":"/tmp/TOKEN_SENTINEL"})
reject("private inner flag", ["--verified-source-ref", "refs/heads/main"])
PY
echo "PASS: unapproved repo rebuild, early authority, Git injection, and private flags fail closed"

# Local Git config, helpers, URL rewrites, and shell startup are inert under the
# anchor's env-i/config-null/non-repository working directory.
evil="${scratch}/evil.git"
/usr/bin/git init --bare -q "${evil}"
local_repo="${scratch}/local-repo"
/usr/bin/git init -q "${local_repo}"
/usr/bin/git -C "${local_repo}" config "url.file://${evil}.insteadOf" "file://${fixture_remote}"
helper_marker="${scratch}/helper-ran"
helper="${scratch}/helper"
printf '#!/bin/sh\nprintf ran > %q\nexit 1\n' "${helper_marker}" > "${helper}"
/bin/chmod 755 "${helper}"
/usr/bin/git -C "${local_repo}" config credential.helper "!${helper}"
startup_marker="${scratch}/startup-ran"
if "${anchor_env[@]}" BASH_ENV="${helper}" ENV="${helper}" \
   "${test_anchor}" --source-ref refs/heads/main --verify-source-only >/dev/null 2>&1; then
    echo "FAIL: publisher bootstrap accepted shell startup authority" >&2; exit 1
fi
(
    cd "${local_repo}"
    "${anchor_env[@]}" "${test_anchor}" \
        --source-ref refs/heads/main --verify-source-only >/dev/null
)
[[ ! -e "${helper_marker}" && ! -e "${startup_marker}" ]]
echo "PASS: repository Git config, helper, and shell startup cannot influence anchored fetch"

# Git symlinks/gitlinks cannot enter the materialized source tree.
linked_work="${scratch}/linked-work"
linked_remote="${scratch}/linked.git"
/bin/cp -R "${fixture_work}" "${linked_work}"
/bin/ln -s ../outside "${linked_work}/unsafe-link"
/usr/bin/git -C "${linked_work}" add unsafe-link
/usr/bin/git -C "${linked_work}" commit -qm linked
/usr/bin/git clone -q --bare "${linked_work}" "${linked_remote}"
linked_commit="$(/usr/bin/git -C "${linked_work}" rev-parse HEAD)"
linked_tree="$(/usr/bin/git -C "${linked_work}" rev-parse 'HEAD^{tree}')"
linked_approval="${scratch}/linked-approval.json"
/bin/cat > "${linked_approval}" <<JSON
{"schema_version":2,"remote":"file://${linked_remote}","ref":"refs/heads/main","commit":"${linked_commit}","tree":"${linked_tree}","package_identifier":"com.everyoneneedsacopilot.controltower.publisher-bootstrap.pkg","app":{"path":"/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app","bundle_identifier":"com.everyoneneedsacopilot.controltower.publisher-bootstrap","team_id":"3SYGVX2HB8","cdhash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bundle_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}
JSON
if /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="${scratch}" TMPDIR="${scratch}" \
   CT_PUBLISHER_BOOTSTRAP_TEST=1 CT_PUBLISHER_BOOTSTRAP_TEST_APPROVAL="${linked_approval}" \
   "${test_anchor}" --source-ref refs/heads/main --verify-source-only >/dev/null 2>&1; then
    echo "FAIL: symlink-bearing source tree was accepted" >&2; exit 1
fi
echo "PASS: symlink-bearing approved Git tree fails closed"

python3 - "${ROOT}/publisher-bootstrap/PublisherBootstrap.swift" \
    "${ROOT}/scripts/package-user-release.program" \
    "${ROOT}/scripts/provision-publisher-bootstrap.sh" <<'PY'
from pathlib import Path
import sys

anchor = Path(sys.argv[1]).read_text(encoding="utf-8")
program = Path(sys.argv[2]).read_text(encoding="utf-8")
provisioner = Path(sys.argv[3]).read_text(encoding="utf-8")
for required in (
    'canonicalTrustRoot = "/Library/PrivilegedHelperTools"',
    'canonicalExecutable = canonicalBundle + "/Contents/MacOS/ct-publisher-bootstrap"',
    'canonicalIdentifier = "com.everyoneneedsacopilot.controltower.publisher-bootstrap"',
    'canonicalTeamID = "3SYGVX2HB8"',
    'approvalPath = "/Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap/approved-source.json"',
    '"init", "--bare"', '"ls-tree", "-rz", "--full-tree"',
    '"cat-file", "blob"', 'credential.helper=', 'protocol.file.allow=never',
    'http.followRedirects=false', 'root-approved source ref moved',
    'runningExecutablePath() == canonicalExecutable',
    'validateProtectedAnchorChain(', 'validateProtectedApprovalChain()',
    '!hasExtendedACL(path)',
):
    assert required in anchor, required
assert '=designated =>' not in anchor
assert '=anchor apple generic' in anchor
assert "git clone" not in anchor
assert "release_verify_checkout" not in program
assert "release_trusted_git" not in program
assert "verify_materialized_source" in program
assert program.count("verify_materialized_source") >= 4
assert 'CT_RELEASE_ANCHOR_PATH' in program
assert '/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app/Contents/MacOS/ct-publisher-bootstrap' in program
assert '/Applications/Copilot Control Tower Publisher Bootstrap.app/Contents/MacOS/ct-publisher-bootstrap' not in program
for required in (
    '#!/usr/bin/env -S -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash --noprofile --norc',
    '/usr/bin/mktemp -d /private/var/tmp/ct-anchor-input.XXXXXX',
    '"ls-tree", "-rz", "--full-tree"', '"cat-file", "blob"',
    'GIT_CONFIG_GLOBAL=/dev/null', 'protocol.file.allow=',
    'approved source ref moved', 'materialized source differs from approved Git bytes',
    'readonly APP_REL="Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"',
    'readonly RECEIPT_REL="Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap/approved-source.json"',
    '--install-location / --ownership recommended', '--filter', '--package-version',
    '"schema_version": 2', '"bundle_sha256": digest', '"cdhash": cdhash',
    '--local-test-only', 'unsigned-input.pkg', 'approval-manifest.template.json',
    'INCOMPLETE-INDEPENDENT-AUTHORITY-REQUIRED',
    'independent signing, owner approval, root staging, installation, and anti-rollback verification are required',
):
    assert required in provisioner, required
for forbidden in (
    "/usr/bin/osascript", "with administrator privileges", "install_script", "rollback_script",
    "create-protected-snapshot", "/usr/sbin/installer", "/Applications/Copilot Control Tower Publisher Bootstrap.app",
    ".env.release.local", "CT_SIGN_IDENTITY", "CT_INSTALLER_IDENTITY", "CT_NOTARY_KEYCHAIN_PROFILE",
    "/usr/bin/productsign", "notarytool submit", "stapler staple", "codesign --force", "source \"${authority_file}\"",
):
    assert forbidden not in provisioner, forbidden
assert "${TMPDIR" not in provisioner
assert provisioner.count("/usr/bin/python3") == provisioner.count("/usr/bin/python3 -I -E -s")
PY
echo "PASS: static gate proves checkout preparation is credential-free and cannot sign/notarize/install"

echo "release source integrity: PASS"
