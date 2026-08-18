#!/usr/bin/env bash
# Validate the doctor fixture corpus against docs/01-architecture/schemas/doctor.schema.json
# (Draft 2020-12). See README.md for the corpus map. Exits non-zero on any failure.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! python3 -c "import jsonschema, referencing" >/dev/null 2>&1; then
  echo "error: this script needs the 'jsonschema' and 'referencing' Python packages." >&2
  echo "       pip3 install jsonschema referencing" >&2
  exit 2
fi

exec python3 "$HERE/validate.py"
