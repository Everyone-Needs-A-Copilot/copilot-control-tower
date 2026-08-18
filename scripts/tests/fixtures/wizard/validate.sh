#!/usr/bin/env bash
# Validate the M3 wizard fixture corpus: the mock-cc `auth` device-flow seam's output
# shape, and the internal consistency of every scenarios/*.json manifest. See README.md
# in this directory. Exits non-zero on any failure. No external Python packages
# required (unlike the sibling ../validate.sh, this one doesn't need jsonschema --
# there is no frozen upstream schema for `cc auth --json` yet, see README.md).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec python3 "$HERE/validate.py"
