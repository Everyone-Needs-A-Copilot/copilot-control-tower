#!/usr/bin/env bash
# The app's offline notarization ticket must be inside the DMG payload.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

python3 - "${REPO_ROOT}/scripts/package-user-release.program" \
    "${REPO_ROOT}/scripts/notarize.sh" <<'PY'
from pathlib import Path
import sys

package = Path(sys.argv[1]).read_text(encoding="utf-8")
notarize = Path(sys.argv[2]).read_text(encoding="utf-8")

app_notary = package.index('scripts/notarize.sh app "${app_path}"')
payload_copy = package.index('ditto "${app_path}" "${payload_dir}/Copilot Control Tower.app"')
dmg_create = package.index("hdiutil create")
dmg_notary = package.index('scripts/notarize.sh dmg "${unsigned_dmg}"')

assert app_notary < payload_copy < dmg_create < dmg_notary
assert 'ditto -c -k --keepParent "${ARTIFACT_PATH}" "${submit_path}"' in notarize
assert 'xcrun stapler validate "${ARTIFACT_PATH}"' in notarize
PY

echo "notarization order test: PASS"
