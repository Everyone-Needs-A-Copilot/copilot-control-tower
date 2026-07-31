#!/usr/bin/env python3
"""Generic onboard-report shape + canonical-schema validator.

Used by PKG-01 (test_walkthrough_05_08_acceptance.sh) and
verify-vendored-cc.sh for a lightweight "is this a real, schema-valid
ecosystem topology report" check -- NOT the full per-row history-state
contract (see test_packaged_cc_topology_contract.sh for that). Run with the
jsonschema-enabled venv python (see either caller for how that venv is
prepared/cached).
"""

from __future__ import annotations

import argparse
import json
import sys

from jsonschema.validators import Draft202012Validator


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument(
        "--min-layers",
        type=int,
        default=1,
        help="minimum populated topology rows required when layers_state == reported",
    )
    args = parser.parse_args()

    errors: list[str] = []
    try:
        report = json.load(open(args.report, encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: {args.report} is not valid JSON: {exc}", file=sys.stderr)
        return 1

    schema = json.load(open(args.schema, encoding="utf-8"))
    validator = Draft202012Validator(schema)
    schema_errors = list(validator.iter_errors(report))
    if schema_errors:
        for error in sorted(schema_errors, key=lambda e: list(e.path))[:5]:
            message = error.message
            if len(message) > 300:
                message = message[:300] + "...(truncated)"
            errors.append(f"schema violation at {list(error.path)}: {message}")

    if report.get("scope") == "ecosystem":
        layers_state = report.get("layers_state")
        if layers_state not in ("reported", "not-computed"):
            errors.append(f"layers_state == {layers_state!r}, expected reported|not-computed")
        layers = report.get("layers")
        if layers_state == "reported":
            if not isinstance(layers, list) or len(layers) < args.min_layers:
                errors.append(
                    f"layers_state is 'reported' but layers has "
                    f"{len(layers) if isinstance(layers, list) else layers!r} rows "
                    f"(need >= {args.min_layers})"
                )
            required_row_fields = (
                "action",
                "local_state",
                "sync_state",
                "remote_state",
                "repository_name",
                "local_path",
            )
            for layer in layers or []:
                missing = [field for field in required_row_fields if field not in layer]
                if missing:
                    errors.append(
                        f"layer {layer.get('id')!r} is missing required fields: {missing}"
                    )
        elif layers_state == "not-computed" and layers != []:
            errors.append("layers_state is 'not-computed' but layers is not []")

        if report.get("result") == "blocked" and "resume" not in report:
            errors.append("result is 'blocked' but no resume hint is present")

    if errors:
        print(f"FAIL: {len(errors)} assertion(s) failed for {args.report}", file=sys.stderr)
        for message in errors:
            print(f"  - {message}", file=sys.stderr)
        return 1

    layer_count = len(report.get("layers") or [])
    print(
        f"assert_onboard_schema: PASS -- schema {schema.get('$id', '')} valid, "
        f"layers_state={report.get('layers_state')!r}, {layer_count} row(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
