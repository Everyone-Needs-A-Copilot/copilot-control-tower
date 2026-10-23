#!/bin/bash
# Parse every bash script under scripts/ and packaging/launchd/ with the macOS
# system /bin/bash (3.2). Release scripts carry a /bin/bash shebang, and 3.2
# rejects constructs newer shells accept, such as a newline after a [[ binary
# operator. Fails closed: a parse error, an unreadable root, or finding no
# scripts at all is a failure.
#
#   scripts/check-release-script-syntax.sh [ROOT]
#
# ROOT defaults to this repository; release-local.sh passes the tag's clean
# clone so the tool, not the tag, decides whether the tag's scripts parse.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${1:-${SCRIPT_DIR}/..}"
[[ -d "${ROOT}" ]] || { echo "release script syntax: root not found: ${ROOT}" >&2; exit 2; }
ROOT="$(cd "${ROOT}" && pwd -P)"
BASH_32=/bin/bash

checked=0
failed=0
while IFS= read -r file; do
    if ! IFS= read -r first_line < "${file}" || [[ "${first_line}" != '#!'*bash* ]]; then
        continue
    fi
    checked=$((checked + 1))
    if ! "${BASH_32}" -n "${file}"; then
        echo "release script syntax: ${BASH_32} -n failed: ${file#${ROOT}/}" >&2
        failed=$((failed + 1))
    fi
done < <(find "${ROOT}/scripts" "${ROOT}/packaging/launchd" -type f 2>/dev/null | LC_ALL=C sort)

[[ "${checked}" -gt 0 ]] || { echo "release script syntax: no bash scripts found under ${ROOT}" >&2; exit 2; }
[[ "${failed}" -eq 0 ]] || { echo "release script syntax: ${failed} of ${checked} scripts do not parse under ${BASH_32}" >&2; exit 1; }
echo "release script syntax: PASS ${checked} scripts parse under ${BASH_32}"
