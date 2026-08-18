#!/usr/bin/env -S -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash --noprofile --norc

set -euo pipefail

readonly PACKAGE_ID="com.everyoneneedsacopilot.controltower.publisher-bootstrap.pkg"
readonly APP_ID="com.everyoneneedsacopilot.controltower.publisher-bootstrap"
readonly TEAM_ID="3SYGVX2HB8"
readonly CANONICAL_APP="/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"
readonly CANONICAL_APPROVAL="/Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap/approved-source.json"

usage() {
  echo "Usage: $0 [--package PKG --expected-source-ref REF --expected-source-commit SHA --expected-source-tree SHA --expected-source-remote URL [--expected-app-team TEAM] [--allow-unsigned-test]] [--approval-manifest JSON --expected-approval-manifest-sha256 SHA --approved-package PKG]"
}

package=""; expected_ref=""; expected_commit=""; expected_tree=""
expected_remote="https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower.git"
expected_team="${TEAM_ID}"; allow_unsigned=false; installed_test_root=""; installed_test_owner=""
installed_test_wrong_owner_path=""
approval_manifest=""; expected_approval_manifest_sha256=""; approved_package=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --package) package="${2:-}"; shift 2;;
    --expected-source-ref) expected_ref="${2:-}"; shift 2;;
    --expected-source-commit) expected_commit="${2:-}"; shift 2;;
    --expected-source-tree) expected_tree="${2:-}"; shift 2;;
    --expected-source-remote) expected_remote="${2:-}"; shift 2;;
    --expected-app-team) expected_team="${2:-}"; shift 2;;
    --allow-unsigned-test) allow_unsigned=true; shift;;
    --installed-test-root) installed_test_root="${2:-}"; shift 2;;
    --installed-test-owner) installed_test_owner="${2:-}"; shift 2;;
    --installed-test-wrong-owner-path) installed_test_wrong_owner_path="${2:-}"; shift 2;;
    --approval-manifest) approval_manifest="${2:-}"; shift 2;;
    --expected-approval-manifest-sha256) expected_approval_manifest_sha256="${2:-}"; shift 2;;
    --approved-package) approved_package="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "error: unknown option" >&2; exit 1;;
  esac
done

verify_independent_tuple() {
  local manifest="$1" expected_sha="$2" approved_pkg="$3"
  [[ -n "${manifest}" && -n "${expected_sha}" && -n "${approved_pkg}" ]] || {
    echo "error: independent owner-approved package tuple is required" >&2; exit 1
  }
  "$(/usr/bin/dirname "$0")/verify-publisher-approval-tuple.py" \
    "${manifest}" "${expected_sha}" "${approved_pkg}" >/dev/null
}
if [[ -n "${installed_test_root}" ]]; then
  [[ "${installed_test_root}" == /private/var/tmp/* || "${installed_test_root}" == /var/folders/* ]] || {
    echo "error: installed-state test root must be a temporary fixture" >&2; exit 1
  }
  [[ "${installed_test_owner}" =~ ^[0-9]+$ ]] || {
    echo "error: installed-state test owner is required" >&2; exit 1
  }
  if [[ -n "${installed_test_wrong_owner_path}" ]]; then
    [[ "${installed_test_wrong_owner_path}" == /* && "${installed_test_wrong_owner_path}" != *".."* ]] || {
      echo "error: installed-state wrong-owner fixture path is invalid" >&2; exit 1
    }
  fi
  readonly APP="${installed_test_root}${CANONICAL_APP}"
  readonly APPROVAL="${installed_test_root}${CANONICAL_APPROVAL}"
  readonly INSTALLED_OWNER="${installed_test_owner}"
else
  readonly APP="${CANONICAL_APP}"
  readonly APPROVAL="${CANONICAL_APPROVAL}"
  readonly INSTALLED_OWNER="0"
fi
readonly EXECUTABLE="${APP}/Contents/MacOS/ct-publisher-bootstrap"

bundle_sha() {
  /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty TMPDIR=/tmp \
    /usr/bin/python3 -I -E -s - "$1" <<'PY'
import hashlib, pathlib, stat, sys
root=pathlib.Path(sys.argv[1]); rows=[]
for path in sorted(root.rglob("*"), key=lambda p:p.relative_to(root).as_posix()):
    rel=path.relative_to(root).as_posix(); value=path.lstat(); kind=value.st_mode & stat.S_IFMT(value.st_mode)
    if kind == stat.S_IFDIR: rows.append(f"d {value.st_mode & 0o777:o} {rel}\n")
    elif kind == stat.S_IFREG: rows.append(f"f {value.st_mode & 0o777:o} {hashlib.sha256(path.read_bytes()).hexdigest()} {rel}\n")
    else: raise SystemExit("error: application contains a special file")
print(hashlib.sha256("".join(rows).encode()).hexdigest())
PY
}

verify_identity() {
  local app="$1" team="$2" identifier cdhash actual_team
  /usr/bin/codesign --verify --deep --strict "${app}"
  identifier="$(/usr/bin/codesign -dvv "${app}" 2>&1 | /usr/bin/sed -n 's/^Identifier=//p' | /usr/bin/head -1)"
  cdhash="$(/usr/bin/codesign -dvvv "${app}" 2>&1 | /usr/bin/sed -n 's/^CDHash=//p' | /usr/bin/head -1 | /usr/bin/tr 'A-F' 'a-f')"
  actual_team="$(/usr/bin/codesign -dvv "${app}" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p' | /usr/bin/head -1)"
  [[ ( "${identifier}" == "${APP_ID}" || ( "${team}" == "adhoc" && "${identifier}" == "ct-publisher-bootstrap" ) ) &&
     "${cdhash}" =~ ^[0-9a-f]{40,64}$ ]] || {
    echo "error: publisher application identity is invalid" >&2; exit 1
  }
  if [[ "${team}" == "adhoc" ]]; then
    [[ -z "${actual_team}" || "${actual_team}" == "not set" ]] || {
      echo "error: test package application is not ad hoc" >&2; exit 1
    }
  else
    [[ "${team}" == "${TEAM_ID}" && "${actual_team}" == "${TEAM_ID}" ]] || {
      echo "error: publisher application Team ID is invalid" >&2; exit 1
    }
    requirement="=anchor apple generic and identifier \"${APP_ID}\" and certificate leaf[subject.OU] = \"${TEAM_ID}\""
    /usr/bin/codesign --verify --deep --strict --test-requirement "${requirement}" "${app}"
  fi
  /usr/bin/printf '%s\n' "${cdhash}"
}

if [[ -n "${package}" ]]; then
  [[ "${package}" == /* && -f "${package}" && ! -L "${package}" &&
     "${expected_ref}" == refs/* && "${expected_commit}" =~ ^[0-9a-f]{40}$ &&
     "${expected_tree}" =~ ^[0-9a-f]{40}$ ]] || {
    echo "error: exact package and source expectations are required" >&2; exit 1
  }
  signature="$(/usr/sbin/pkgutil --check-signature "${package}" 2>&1 || true)"
  if [[ "${allow_unsigned}" == true ]]; then
    [[ "${expected_team}" == "adhoc" ]] &&
      /usr/bin/grep -F "Status: no signature" <<<"${signature}" >/dev/null || {
      echo "error: unsigned package verification is restricted to the explicit local seam (${signature//$'\n'/ })" >&2; exit 1
    }
  else
    verify_independent_tuple "${approval_manifest}" "${expected_approval_manifest_sha256}" "${approved_package}"
    [[ "${package}" == "${approved_package}" ]] || {
      echo "error: verified package path differs from the owner-approved package path" >&2; exit 1
    }
    [[ "${signature}" == *"Developer ID Installer:"* && "${signature}" == *"(${TEAM_ID})"* ]] || {
      echo "error: package signer is not the approved Developer ID Installer team" >&2; exit 1
    }
    /usr/sbin/spctl --assess --type install "${package}"
    /usr/bin/xcrun stapler validate "${package}"
  fi

  scratch="$(/usr/bin/mktemp -d /private/var/tmp/ct-anchor-verify.XXXXXX)"
  cleanup() { /bin/rm -rf -- "${scratch}"; }
  trap cleanup EXIT
  /bin/chmod 700 "${scratch}"
  /usr/sbin/pkgutil --expand-full "${package}" "${scratch}/expanded"
  [[ -f "${scratch}/expanded/Bom" && -f "${scratch}/expanded/PackageInfo" &&
     -d "${scratch}/expanded/Payload" && ! -e "${scratch}/expanded/Scripts" ]] || {
    echo "error: package structure is invalid or contains scripts" >&2; exit 1
  }
  [[ "$(/usr/bin/find "${scratch}/expanded" -mindepth 1 -maxdepth 1 -print | /usr/bin/wc -l | /usr/bin/tr -d ' ')" == "3" ]] || {
    echo "error: package contains an unexpected archive member" >&2; exit 1
  }

  app="${scratch}/expanded/Payload${APP}"
  approval="${scratch}/expanded/Payload${APPROVAL}"
  cdhash="$(verify_identity "${app}" "${expected_team}")"
  digest="$(bundle_sha "${app}")"
  /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty TMPDIR="${scratch}" \
    /usr/bin/python3 -I -E -s - "${scratch}/expanded" "${approval}" "${app}" \
    "${expected_remote}" "${expected_ref}" "${expected_commit}" "${expected_tree}" \
    "${expected_team}" "${cdhash}" "${digest}" "${PACKAGE_ID}" "${APP_ID}" "${approval_manifest}" <<'PY'
import json, os, pathlib, plistlib, re, stat, subprocess, sys, xml.etree.ElementTree as ET
expanded, receipt_path, app_path = map(pathlib.Path, sys.argv[1:4])
remote, ref, commit, tree, team, cdhash, digest, package_id, app_id, manifest_path = sys.argv[4:]
payload = expanded / "Payload"

# The component package is payload-only and installs at the filesystem root.
package_info = ET.parse(expanded / "PackageInfo").getroot()
if package_info.attrib.get("identifier") != package_id or package_info.attrib.get("install-location") != "/":
    raise SystemExit("error: package identifier or install location is invalid")
if package_info.find("scripts") is not None or list(expanded.rglob("Scripts")):
    raise SystemExit("error: package scripts are forbidden")

allowed_roots = (
    "Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app",
    "Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap/approved-source.json",
)
actual = {}
for path in [payload, *sorted(payload.rglob("*"))]:
    rel = "." if path == payload else path.relative_to(payload).as_posix()
    value = path.lstat(); kind = value.st_mode & stat.S_IFMT(value.st_mode)
    if rel != "." and not any(root == rel or root.startswith(rel + "/") or rel.startswith(root + "/") for root in allowed_roots):
        raise SystemExit("error: package contains an extra payload path")
    if kind not in {stat.S_IFDIR, stat.S_IFREG}:
        raise SystemExit("error: package payload contains a symlink or special file")
    if rel.startswith("._") or "/._" in rel:
        raise SystemExit("error: package contains an AppleDouble path")
    mode = value.st_mode & 0o777
    expected_mode = 0o755 if kind == stat.S_IFDIR or rel.endswith("/Contents/MacOS/ct-publisher-bootstrap") else 0o644
    if mode != expected_mode:
        raise SystemExit("error: package payload mode is unsafe")
    acl = subprocess.check_output(["/bin/ls", "-led", str(path)], text=True).splitlines()[1:]
    if any(re.match(r"^\s*\d+:", line) for line in acl):
        raise SystemExit("error: package payload contains an ACL")
    actual["." if rel == "." else "./" + rel] = ("d" if kind == stat.S_IFDIR else "f", mode)
if not receipt_path.is_file() or not app_path.is_dir():
    raise SystemExit("error: package is missing its exact app or receipt")

# BOM is the installation ownership/mode contract; every entry is root:wheel
# and corresponds exactly to the safely extracted payload.
bom_text = subprocess.check_output(["/usr/bin/lsbom", "-p", "fMUG", str(expanded / "Bom")], text=True)
bom = {}
for line in bom_text.splitlines():
    match = re.match(r"^(.*?)\t([dl-][rwx-]{9}) ?\t([^\t]+)\t([^\t]+)$", line)
    if not match:
        raise SystemExit("error: package BOM is malformed")
    path, mode_text, owner, group = match.groups()
    if owner != "root" or group != "wheel":
        raise SystemExit("error: package BOM ownership is not root:wheel")
    # pkgbuild records AppleDouble metadata entries in the BOM even when
    # expand-full proves they are not filesystem payload objects. They are
    # admissible only as metadata twins of an exact allowed payload path.
    parts = pathlib.PurePosixPath(path).parts
    if parts and parts[-1].startswith("._"):
        twin = str(pathlib.PurePosixPath(*parts[:-1], parts[-1][2:]))
        if path.startswith("./"):
            twin = "./" + twin
        if twin not in actual:
            raise SystemExit("error: package BOM contains orphaned AppleDouble metadata")
        continue
    # Convert permission characters without trusting platform stat output.
    mode = sum(bit for char, bit in zip(mode_text[1:], (0o400,0o200,0o100,0o040,0o020,0o010,0o004,0o002,0o001)) if char != "-")
    bom[path] = ("d" if mode_text[0] == "d" else "f", mode)
if bom != actual:
    missing = sorted(set(actual) - set(bom))
    extra = sorted(set(bom) - set(actual))
    changed = sorted(path for path in set(actual) & set(bom) if actual[path] != bom[path])
    raise SystemExit(f"error: package BOM and extracted payload differ: missing={missing} extra={extra} changed={changed}")

receipt = json.loads(receipt_path.read_text())
expected = {
    "schema_version": 2, "remote": remote, "ref": ref, "commit": commit, "tree": tree,
    "package_identifier": package_id,
    "app": {
        "path": "/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app",
        "bundle_identifier": app_id, "team_id": team, "cdhash": cdhash, "bundle_sha256": digest,
    },
}
if receipt != expected:
    raise SystemExit("error: signed payload receipt differs from package/source identity")
if manifest_path:
    manifest = json.loads(pathlib.Path(manifest_path).read_text())
    if manifest["source"] != {"remote": remote, "ref": ref, "commit": commit, "tree": tree}:
        raise SystemExit("error: package source expectations differ from owner-approved tuple")
    if package_info.attrib.get("version") != manifest["package"]["version"]:
        raise SystemExit("error: package version differs from owner-approved tuple")
    if manifest["package"]["identifier"] != package_id or manifest["application"] != {
        "bundle_identifier": app_id, "team_id": team, "cdhash": cdhash, "bundle_sha256": digest,
    }:
        raise SystemExit("error: package application identity differs from owner-approved tuple")
with (app_path / "Contents/Info.plist").open("rb") as handle:
    if plistlib.load(handle).get("CFBundleIdentifier") != app_id:
        raise SystemExit("error: packaged application bundle identifier is invalid")
PY
  echo "publisher bootstrap payload-only package: PASS"
  exit 0
fi

# Installed-state verification. The package ceremony is separate; this path is
# credential-free and performs no repair, rollback, deletion, or other writes.
if [[ -z "${installed_test_root}" ]]; then
  # Fail before consulting installed paths when independent first-trust input is
  # absent. A self-consistent installed app/receipt is not owner authorization.
  verify_independent_tuple "${approval_manifest}" "${expected_approval_manifest_sha256}" "${approved_package}"
fi
reject_acl() {
  local path="$1"
  [[ -z "$(/bin/ls -led "${path}" | /usr/bin/awk 'NR > 1 && $1 ~ /^[0-9]+:$/ { print; exit }')" ]] || {
    echo "error: protected publisher bootstrap path has an extended ACL" >&2; exit 1
  }
}
protected_directory() {
  local directory="$1" mode actual_owner
  actual_owner="$(/usr/bin/stat -f '%u' "${directory}" 2>/dev/null || true)"
  if [[ -n "${installed_test_wrong_owner_path}" && "${directory}" == "${installed_test_root}${installed_test_wrong_owner_path}" ]]; then
    actual_owner="$((INSTALLED_OWNER + 1))"
  fi
  [[ -d "${directory}" && ! -L "${directory}" && "${actual_owner}" == "${INSTALLED_OWNER}" ]] || {
    echo "error: unsafe publisher bootstrap directory" >&2; exit 1
  }
  mode="$(/usr/bin/stat -f '%Lp' "${directory}")"
  [[ $((8#${mode} & 8#022)) == 0 && ! -w "${directory}" ]] || {
    echo "error: publisher bootstrap directory is writable" >&2; exit 1
  }
  reject_acl "${directory}"
}
protected_file() {
  local file="$1" mode actual_owner
  actual_owner="$(/usr/bin/stat -f '%u' "${file}" 2>/dev/null || true)"
  if [[ -n "${installed_test_wrong_owner_path}" && "${file}" == "${installed_test_root}${installed_test_wrong_owner_path}" ]]; then
    actual_owner="$((INSTALLED_OWNER + 1))"
  fi
  [[ -f "${file}" && ! -L "${file}" && "${actual_owner}" == "${INSTALLED_OWNER}" ]] || {
    echo "error: unsafe publisher bootstrap file" >&2; exit 1
  }
  mode="$(/usr/bin/stat -f '%Lp' "${file}")"
  [[ $((8#${mode} & 8#022)) == 0 && ! -w "${file}" ]] || {
    echo "error: publisher bootstrap file is writable" >&2; exit 1
  }
  reject_acl "${file}"
}
installed_prefix="${installed_test_root}"
for directory in "${installed_prefix:-/}" "${installed_prefix}/Library" "${installed_prefix}/Library/PrivilegedHelperTools" \
  "${APP}" "${APP}/Contents" "${APP}/Contents/MacOS" "${installed_prefix}/Library/Application Support" \
  "${installed_prefix}/Library/Application Support/Everyone Needs a Copilot" \
  "${installed_prefix}/Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap"; do
  protected_directory "${directory}"
done
protected_file "${EXECUTABLE}"
protected_file "${APPROVAL}"
if [[ -n "${installed_test_root}" ]]; then
  echo "publisher bootstrap installed ancestry test: PASS"
  exit 0
fi

cdhash="$(verify_identity "${APP}" "${TEAM_ID}")"
digest="$(bundle_sha "${APP}")"
/usr/sbin/spctl --assess --type execute "${APP}"
/usr/bin/xcrun stapler validate "${APP}"
/usr/bin/python3 -I -E -s - "${APPROVAL}" "${cdhash}" "${digest}" "${approval_manifest}" <<'PY'
import json, pathlib, re, sys
value=json.loads(pathlib.Path(sys.argv[1]).read_text())
manifest=json.loads(pathlib.Path(sys.argv[4]).read_text())
assert type(value["schema_version"]) is int and value["schema_version"] == 2
assert value["remote"] == "https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower.git"
assert value["ref"].startswith("refs/")
assert re.fullmatch(r"[0-9a-f]{40}", value["commit"])
assert re.fullmatch(r"[0-9a-f]{40}", value["tree"])
assert value["package_identifier"] == "com.everyoneneedsacopilot.controltower.publisher-bootstrap.pkg"
assert value["app"] == {
    "path": "/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app",
    "bundle_identifier": "com.everyoneneedsacopilot.controltower.publisher-bootstrap",
    "team_id": "3SYGVX2HB8", "cdhash": sys.argv[2], "bundle_sha256": sys.argv[3],
}
assert value["remote"] == manifest["source"]["remote"]
assert value["ref"] == manifest["source"]["ref"]
assert value["commit"] == manifest["source"]["commit"]
assert value["tree"] == manifest["source"]["tree"]
assert value["package_identifier"] == manifest["package"]["identifier"]
assert value["app"]["bundle_identifier"] == manifest["application"]["bundle_identifier"]
assert value["app"]["team_id"] == manifest["application"]["team_id"]
assert value["app"]["cdhash"] == manifest["application"]["cdhash"]
assert value["app"]["bundle_sha256"] == manifest["application"]["bundle_sha256"]
PY
installed_version="$(/usr/sbin/pkgutil --pkg-info-plist "${PACKAGE_ID}" | /usr/bin/plutil -extract pkg-version raw -o - -)"
approved_version="$(/usr/bin/python3 -I -E -s -c 'import json,sys; print(json.load(open(sys.argv[1]))["package"]["version"])' "${approval_manifest}")"
[[ "${installed_version}" == "${approved_version}" ]] || {
  echo "error: installed package receipt version differs from the owner-approved tuple" >&2; exit 1
}
echo "publisher bootstrap installed trust boundary: PASS"
