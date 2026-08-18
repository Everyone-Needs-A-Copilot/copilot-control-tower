#!/usr/bin/env -S -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash --noprofile --norc
# Prepare credential-free publisher-bootstrap inputs from one authenticated Git
# tree. This checkout stage never signs, notarizes, staples, installs, elevates,
# or reads release authority. Its output is input to an independent ceremony;
# it is not an approved or installable first-trust artifact.

set -euo pipefail

readonly CANONICAL_REMOTE="https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower.git"
readonly PACKAGE_ID="com.everyoneneedsacopilot.controltower.publisher-bootstrap.pkg"
readonly APP_ID="com.everyoneneedsacopilot.controltower.publisher-bootstrap"
readonly TEAM_ID="3SYGVX2HB8"
readonly APP_REL="Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app"
readonly RECEIPT_REL="Library/Application Support/Everyone Needs a Copilot/Publisher Bootstrap/approved-source.json"

usage() {
  echo "Usage: $0 --source-ref REF --source-commit SHA --source-tree SHA --package-version X.Y.Z --output-dir DIR [--local-test-only --source-remote URL]"
}

source_ref=""; source_commit=""; source_tree=""; package_version=""; output_dir=""
source_remote="${CANONICAL_REMOTE}"; local_test=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-ref) source_ref="${2:-}"; shift 2;;
    --source-commit) source_commit="${2:-}"; shift 2;;
    --source-tree) source_tree="${2:-}"; shift 2;;
    --package-version) package_version="${2:-}"; shift 2;;
    --output-dir) output_dir="${2:-}"; shift 2;;
    --source-remote) source_remote="${2:-}"; shift 2;;
    --local-test-only) local_test=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "error: unknown option" >&2; exit 1;;
  esac
done

[[ "${source_ref}" == refs/* && "${source_commit}" =~ ^[0-9a-f]{40}$ &&
   "${source_tree}" =~ ^[0-9a-f]{40}$ &&
   "${package_version}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ &&
   "${package_version}" != "0.0.0" && "${output_dir}" == /* ]] || {
  echo "error: exact source identity, monotonic X.Y.Z package version, and absolute output directory are required" >&2
  exit 1
}
if [[ "${local_test}" == false ]]; then
  [[ "${source_remote}" == "${CANONICAL_REMOTE}" ]] || {
    echo "error: release inputs must use the canonical public remote" >&2; exit 1
  }
fi
[[ ! -e "${output_dir}" ]] || {
  echo "error: output directory already exists" >&2; exit 1
}

scratch="$(/usr/bin/mktemp -d /private/var/tmp/ct-anchor-input.XXXXXX)"
cleanup() { /bin/rm -rf -- "${scratch}"; }
trap cleanup EXIT
/bin/chmod 700 "${scratch}"
/bin/mkdir -m 700 "${scratch}/home" "${scratch}/git"

git_clean=(/usr/bin/env -i HOME="${scratch}/home" TMPDIR="${scratch}" PATH=/usr/bin:/bin:/usr/sbin:/sbin
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
  /usr/bin/git -C "${scratch}/git" -c credential.helper= -c core.hooksPath=/dev/null
  -c core.fsmonitor=false -c diff.external= -c protocol.allow=never -c protocol.https.allow=always
  -c protocol.file.allow="$([[ "${local_test}" == true ]] && echo always || echo never)"
  -c http.followRedirects=false -c include.path=/dev/null)

advertised="$("${git_clean[@]}" ls-remote --exit-code "${source_remote}" "${source_ref}" | /usr/bin/cut -f1)"
[[ "${advertised}" == "${source_commit}" ]] || {
  echo "error: approved source ref moved" >&2; exit 1
}
"${git_clean[@]}" init --bare "${scratch}/objects.git" >/dev/null
"${git_clean[@]}" --git-dir "${scratch}/objects.git" fetch --no-tags "${source_remote}" \
  "${source_ref}:refs/package/source" >/dev/null
[[ "$("${git_clean[@]}" --git-dir "${scratch}/objects.git" rev-parse 'refs/package/source^{commit}')" == "${source_commit}" &&
   "$("${git_clean[@]}" --git-dir "${scratch}/objects.git" rev-parse "${source_commit}^{tree}")" == "${source_tree}" ]] || {
  echo "error: fetched Git object identity differs" >&2; exit 1
}

# Materialize only authenticated regular Git blobs. The checkout that launched
# this stage supplies no executable bytes after this point.
/bin/mkdir -m 700 "${scratch}/source"
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty TMPDIR="${scratch}" \
  /usr/bin/python3 -I -E -s - "${scratch}/objects.git" "${source_commit}" "${scratch}/source" <<'PY'
import pathlib, subprocess, sys
store, commit, destination = sys.argv[1:]
root = pathlib.Path(destination)
raw = subprocess.check_output(["/usr/bin/git", "--git-dir", store, "ls-tree", "-rz", "--full-tree", commit])
for record in raw.split(b"\0"):
    if not record:
        continue
    meta, raw_path = record.split(b"\t", 1)
    mode, kind, oid = meta.decode().split()
    path = raw_path.decode()
    if kind != "blob" or mode not in {"100644", "100755"} or path.startswith("/") or ".." in pathlib.PurePosixPath(path).parts:
        raise SystemExit("error: approved Git tree contains an unsafe entry")
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(subprocess.check_output(["/usr/bin/git", "--git-dir", store, "cat-file", "blob", oid]))
    target.chmod(0o755 if mode == "100755" else 0o644)
PY

/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty TMPDIR="${scratch}" \
  /usr/bin/python3 -I -E -s - "${scratch}/source" "${scratch}/objects.git" "${source_commit}" <<'PY'
import pathlib, stat, subprocess, sys
root, store, commit = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
expected = {}
raw = subprocess.check_output(["/usr/bin/git", "--git-dir", store, "ls-tree", "-rz", "--full-tree", commit])
for record in raw.split(b"\0"):
    if record:
        meta, path = record.split(b"\t", 1)
        mode, kind, oid = meta.decode().split()
        expected[path.decode()] = (mode, oid)
actual = {}
for path in root.rglob("*"):
    value = path.lstat()
    if stat.S_ISDIR(value.st_mode):
        continue
    if not stat.S_ISREG(value.st_mode):
        raise SystemExit("error: materialized source contains a special file")
    actual[path.relative_to(root).as_posix()] = path
if set(actual) != set(expected):
    raise SystemExit("error: materialized source file set differs")
for relative, path in actual.items():
    mode, oid = expected[relative]
    got = subprocess.check_output(["/usr/bin/git", "hash-object", "--no-filters", str(path)], text=True).strip()
    if got != oid or bool(path.stat().st_mode & 0o111) != (mode == "100755"):
        raise SystemExit("error: materialized source differs from approved Git bytes")
PY

app="${scratch}/payload/${APP_REL}"
receipt="${scratch}/payload/${RECEIPT_REL}"
/bin/mkdir -p "$(/usr/bin/dirname "${app}")" "$(/usr/bin/dirname "${receipt}")"
"${scratch}/source/scripts/build-publisher-bootstrap.sh" "${app}" >/dev/null

# swiftc may emit an ad-hoc Mach-O signature on Apple silicon. We inspect that
# compiler output but never invoke codesign with a signing operation.
identifier="$(/usr/bin/codesign -dvv "${app}" 2>&1 | /usr/bin/sed -n 's/^Identifier=//p' | /usr/bin/head -1)"
cdhash="$(/usr/bin/codesign -dvvv "${app}" 2>&1 | /usr/bin/sed -n 's/^CDHash=//p' | /usr/bin/head -1 | /usr/bin/tr 'A-F' 'a-f')"
team="$(/usr/bin/codesign -dvv "${app}" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p' | /usr/bin/head -1)"
[[ ( "${identifier}" == "${APP_ID}" || "${identifier}" == "ct-publisher-bootstrap" ) &&
   "${cdhash}" =~ ^[0-9a-f]{40,64}$ &&
   ( -z "${team}" || "${team}" == "not set" ) ]] || {
  echo "error: prepared application is not the expected credential-free ad-hoc input" >&2; exit 1
}

bundle_sha="$(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty TMPDIR="${scratch}" \
  /usr/bin/python3 -I -E -s - "${app}" <<'PY'
import hashlib, pathlib, stat, sys
root=pathlib.Path(sys.argv[1]); rows=[]
for path in sorted(root.rglob("*"), key=lambda p:p.relative_to(root).as_posix()):
    rel=path.relative_to(root).as_posix(); value=path.lstat(); kind=value.st_mode & stat.S_IFMT(value.st_mode)
    if kind == stat.S_IFDIR: rows.append(f"d {value.st_mode & 0o777:o} {rel}\n")
    elif kind == stat.S_IFREG: rows.append(f"f {value.st_mode & 0o777:o} {hashlib.sha256(path.read_bytes()).hexdigest()} {rel}\n")
    else: raise SystemExit("error: application contains a special file")
print(hashlib.sha256("".join(rows).encode()).hexdigest())
PY
)"

/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty TMPDIR="${scratch}" \
  /usr/bin/python3 -I -E -s - "${receipt}" "${source_remote}" "${source_ref}" "${source_commit}" \
  "${source_tree}" "${PACKAGE_ID}" "${APP_ID}" "${cdhash}" "${bundle_sha}" <<'PY'
import json, pathlib, sys
out, remote, ref, commit, tree, package_id, app_id, cdhash, digest = sys.argv[1:]
value = {
    "schema_version": 2,
    "remote": remote,
    "ref": ref,
    "commit": commit,
    "tree": tree,
    "package_identifier": package_id,
    "app": {
        "path": "/Library/PrivilegedHelperTools/com.everyoneneedsacopilot.controltower.publisher-bootstrap.app",
        "bundle_identifier": app_id,
        "team_id": "adhoc",
        "cdhash": cdhash,
        "bundle_sha256": digest,
    },
}
pathlib.Path(out).write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
PY

# Normalize the unsigned package input. No scripts directory is supplied.
/usr/bin/xattr -cr "${scratch}/payload"
/usr/bin/find "${scratch}/payload" -type d -exec /bin/chmod 0755 {} +
/usr/bin/find "${scratch}/payload" -type f -exec /bin/chmod 0644 {} +
/bin/chmod 0755 "${app}/Contents/MacOS/ct-publisher-bootstrap"
/usr/bin/find "${scratch}/payload" -exec /usr/bin/touch -h -t 200101010000 {} +

unsigned_pkg="${scratch}/Copilot-Control-Tower-Publisher-Bootstrap.unsigned-input.pkg"
COPYFILE_DISABLE=1 /usr/bin/pkgbuild --root "${scratch}/payload" --identifier "${PACKAGE_ID}" \
  --version "${package_version}" --install-location / --ownership recommended --filter '(^|/)\._' \
  "${unsigned_pkg}" >/dev/null
# pkgbuild's payload, BOM, and PackageInfo are deterministic after normalization,
# but its XAR table of contents records wall-clock creation time. Replace that
# one non-semantic field and regenerate the XAR header checksum without changing
# any heap member or offset.
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty TMPDIR="${scratch}" \
  /usr/bin/python3 -I -E -s - "${unsigned_pkg}" <<'PY'
import hashlib, pathlib, re, struct, sys, zlib
path = pathlib.Path(sys.argv[1]); raw = path.read_bytes()
magic, header_size, version, compressed_size, uncompressed_size, algorithm = struct.unpack(">IHHQQI", raw[:28])
if magic != 0x78617221 or header_size != 28 or version != 1 or algorithm != 1:
    raise SystemExit("error: unsupported pkgbuild XAR header")
checksum_size = 20
compressed = raw[header_size:header_size + compressed_size]
toc = zlib.decompress(compressed)
checksum = raw[header_size + compressed_size:header_size + compressed_size + checksum_size]
if len(toc) != uncompressed_size:
    raise SystemExit("error: pkgbuild XAR table of contents checksum is invalid")
if checksum == hashlib.sha1(toc).digest():
    checksum_scope = "plain"
elif checksum == hashlib.sha1(compressed).digest():
    checksum_scope = "compressed"
else:
    raise SystemExit("error: pkgbuild XAR table of contents checksum is invalid")
normalized = toc
counts = {}
for tag in (b"creation-time", b"mtime", b"atime", b"ctime", b"time"):
    pattern = rb"<" + tag + rb">[^<]+</" + tag + rb">"
    replacement = b"<" + tag + b">2001-01-01T00:00:00</" + tag + b">"
    normalized, counts[tag] = re.subn(pattern, replacement, normalized)
if counts[b"creation-time"] != 1:
    raise SystemExit("error: pkgbuild XAR creation time is missing or ambiguous")
for tag, fixed in (
    (b"inode", b"0"), (b"deviceno", b"0"), (b"uid", b"0"), (b"gid", b"0"),
    (b"user", b"root"), (b"group", b"wheel"),
):
    pattern = rb"<" + tag + rb">[^<]+</" + tag + rb">"
    replacement = b"<" + tag + b">" + fixed + b"</" + tag + b">"
    normalized = re.sub(pattern, replacement, normalized)
new_compressed = zlib.compress(normalized, level=9)
heap = raw[header_size + compressed_size + checksum_size:]
header = struct.pack(">IHHQQI", magic, header_size, version, len(new_compressed), len(normalized), algorithm)
new_checksum = hashlib.sha1(normalized if checksum_scope == "plain" else new_compressed).digest()
path.write_bytes(header + new_compressed + new_checksum + heap)
PY
unsigned_sha="$(/usr/bin/shasum -a 256 "${unsigned_pkg}" | /usr/bin/cut -d ' ' -f 1)"

/bin/mkdir "${output_dir}"
/bin/cp "${unsigned_pkg}" "${output_dir}/"
/bin/cp -R "${app}" "${output_dir}/Copilot Control Tower Publisher Bootstrap.unsigned-input.app"

/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty TMPDIR="${scratch}" \
  /usr/bin/python3 -I -E -s - "${output_dir}" "${source_remote}" "${source_ref}" "${source_commit}" \
  "${source_tree}" "${package_version}" "${unsigned_sha}" "${cdhash}" "${bundle_sha}" <<'PY'
import json, pathlib, sys
out, remote, ref, commit, tree, version, unsigned_sha, cdhash, bundle_sha = sys.argv[1:]
root = pathlib.Path(out)
source = {
    "schema_version": 1,
    "source": {"remote": remote, "ref": ref, "commit": commit, "tree": tree},
    "package_input": {
        "identifier": "com.everyoneneedsacopilot.controltower.publisher-bootstrap.pkg",
        "version": version,
        "sha256": unsigned_sha,
    },
    "application_input": {
        "bundle_identifier": "com.everyoneneedsacopilot.controltower.publisher-bootstrap",
        "adhoc_cdhash": cdhash,
        "bundle_sha256": bundle_sha,
    },
}
template = {
    "schema_version": 1,
    "status": "INCOMPLETE-INDEPENDENT-AUTHORITY-REQUIRED",
    "source": source["source"],
    "package": {
        "identifier": source["package_input"]["identifier"],
        "version": version,
        "installer_team_id": "3SYGVX2HB8",
        "final_signed_sha256": None,
    },
    "application": {
        "bundle_identifier": source["application_input"]["bundle_identifier"],
        "team_id": "3SYGVX2HB8",
        "cdhash": None,
        "bundle_sha256": None,
    },
    "anti_rollback": {"previous_package_version": None, "minimum_package_version": version},
    "owner_approval": {"approval_id": None, "approved_at_utc": None},
}
(root / "source-input.json").write_text(json.dumps(source, sort_keys=True, separators=(",", ":")) + "\n")
(root / "approval-manifest.template.json").write_text(json.dumps(template, sort_keys=True, separators=(",", ":")) + "\n")
PY

/bin/chmod -R a-w "${output_dir}"
echo "credential-free publisher inputs prepared: ${output_dir}"
echo "INCOMPLETE: independent signing, owner approval, root staging, installation, and anti-rollback verification are required."
