#!/usr/bin/env python3
"""Assertion pass for test_packaged_cc_topology_contract.sh (task 209).

Invoked with the venv python that has `jsonschema` installed. Not meant to
be run standalone outside that harness (it takes no defaults).
"""

from __future__ import annotations

import argparse
import json
import sys

from jsonschema.validators import Draft202012Validator

# state -> expected (action, sync_state, local_state). Mirrors
# claude-copilot tools/cc/src/cc/commands/onboard.py's
# `_classify_repository_history` / `HistoryClassification` exactly: only
# `fast-forwardable` ever promises a repair (a proven clean fast-forward);
# `exact` is the only `reuse`; every other state is `review` (never
# auto-repaired -- never-destroy).
STATE_EXPECT = {
    "exact": ("reuse", "current", "visible"),
    "fast-forwardable": ("repair", "behind", "visible"),
    "dirty": ("review", "local-changes", "visible"),
    "ahead-only": ("review", "ahead", "visible"),
    "divergent-identical-tree": ("review", "diverged-identical", "visible"),
    "divergent-different-content": ("review", "diverged", "visible"),
    "unreadable": ("review", "unreadable", "conflict"),
    "wrong-origin": ("review", "wrong-origin", "conflict"),
}


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def load_rows(path: str) -> list[dict[str, str]]:
    rows = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            component, role, state, repo_name, local_path = line.split("\t")
            rows.append(
                {
                    "component": component,
                    "role": role,
                    "state": state,
                    "repo_name": repo_name,
                    "local_path": local_path,
                }
            )
    return rows


def assert_report_shape(report: dict, errors: list[str], *, label: str) -> None:
    expectations = {
        "schema_version": "2.0",
        "scope": "ecosystem",
        "mode": "plan",
        "result": "blocked",
        "layers_state": "reported",
    }
    for key, expected in expectations.items():
        actual = report.get(key)
        if actual != expected:
            fail(errors, f"{label}: {key} == {actual!r}, expected {expected!r}")
    if report.get("completed_actions") != []:
        fail(
            errors,
            f"{label}: completed_actions must be empty in a read-only plan run, "
            f"got {report.get('completed_actions')!r}",
        )
    resume = report.get("resume")
    if not isinstance(resume, dict) or resume.get("safe_to_rerun") is not True:
        fail(errors, f"{label}: resume.safe_to_rerun must be true, got {resume!r}")
    layers = report.get("layers")
    if not isinstance(layers, list) or len(layers) != 16:
        fail(
            errors,
            f"{label}: expected exactly 16 topology rows (4 components x 4 "
            f"layers), got {len(layers) if isinstance(layers, list) else layers!r}",
        )


def assert_rows(
    report: dict, rows: list[dict[str, str]], repo_root: str, errors: list[str]
) -> None:
    layers = report.get("layers") or []
    by_key = {
        (layer.get("product"), layer.get("role"), layer.get("repository_name")): layer
        for layer in layers
    }
    seen_ids = set()
    for row in rows:
        key = (row["component"], row["role"], row["repo_name"])
        layer = by_key.get(key)
        if layer is None:
            fail(errors, f"missing topology row for {key} (state={row['state']})")
            continue
        seen_ids.add(id(layer))

        expected_local_path = row["local_path"]
        if layer.get("local_path") != expected_local_path:
            fail(
                errors,
                f"{key}: local_path == {layer.get('local_path')!r}, "
                f"expected {expected_local_path!r}",
            )

        expected_action, expected_sync, expected_local_state = STATE_EXPECT[
            row["state"]
        ]
        if layer.get("action") != expected_action:
            fail(
                errors,
                f"{key} (state={row['state']}): action == "
                f"{layer.get('action')!r}, expected {expected_action!r}",
            )
        if layer.get("sync_state") != expected_sync:
            fail(
                errors,
                f"{key} (state={row['state']}): sync_state == "
                f"{layer.get('sync_state')!r}, expected {expected_sync!r}",
            )
        if layer.get("local_state") != expected_local_state:
            fail(
                errors,
                f"{key} (state={row['state']}): local_state == "
                f"{layer.get('local_state')!r}, expected {expected_local_state!r}",
            )

    if len(seen_ids) != len(layers):
        fail(
            errors,
            f"report contains {len(layers)} rows but only {len(seen_ids)} "
            "matched an expected (component, role, repository_name) -- "
            "unexpected/duplicate row present",
        )


def _short_message(error) -> str:
    # A top-level `oneOf` failure embeds the ENTIRE instance in .message
    # (every branch's mismatch reason, each repeating the whole report).
    # validator_value carries the much shorter "$ref list that didn't match"
    # instead; fall back to a truncated .message only when that is absent.
    if error.validator == "oneOf" and isinstance(error.validator_value, list):
        refs = [str(item.get("$ref", item)) for item in error.validator_value]
        context_summaries = [
            f"[{sub.validator}] {sub.message.splitlines()[0][:160]}"
            for sub in (error.context or [])
        ]
        return f"matched none of {refs}: " + "; ".join(context_summaries)
    message = error.message
    return message if len(message) <= 300 else message[:300] + "...(truncated)"


def assert_schema(report: dict, schema_path: str, errors: list[str]) -> None:
    schema = json.load(open(schema_path, encoding="utf-8"))
    validator = Draft202012Validator(schema)
    schema_errors = sorted(validator.iter_errors(report), key=lambda e: list(e.path))
    for error in schema_errors[:10]:
        fail(errors, f"schema violation at {list(error.path)}: {_short_message(error)}")
    if len(schema_errors) > 10:
        fail(errors, f"...and {len(schema_errors) - 10} more schema violations")


def assert_source_matches_packaged(
    source: dict, packaged: dict, errors: list[str]
) -> None:
    if source == packaged:
        return
    # Point at the first differing top-level key for a useful message; a
    # full structural diff is unnecessary noise once any key differs, since
    # both reports come from running the identical fixture/env twice.
    keys = sorted(set(source) | set(packaged))
    for key in keys:
        if source.get(key) != packaged.get(key):
            fail(
                errors,
                f"source vs packaged report differ at top-level key {key!r}: "
                f"source={source.get(key)!r} packaged={packaged.get(key)!r}",
            )
            return
    fail(errors, "source vs packaged report differ (no single top-level key pinpointed)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema", required=True)
    parser.add_argument("--rows", required=True)
    parser.add_argument("--packaged", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--repo-root", required=True)
    args = parser.parse_args()

    rows = load_rows(args.rows)
    if len(rows) != 16:
        print(f"FAIL: fixture row table has {len(rows)} rows, expected 16", file=sys.stderr)
        return 1

    packaged = json.load(open(args.packaged, encoding="utf-8"))
    source = json.load(open(args.source, encoding="utf-8"))

    errors: list[str] = []
    assert_report_shape(packaged, errors, label="packaged")
    assert_rows(packaged, rows, args.repo_root, errors)
    assert_schema(packaged, args.schema, errors)
    assert_source_matches_packaged(source, packaged, errors)

    if errors:
        print(f"FAIL: {len(errors)} assertion(s) failed", file=sys.stderr)
        for message in errors:
            print(f"  - {message}", file=sys.stderr)
        return 1

    print(
        "assert_topology_report: PASS -- 16/16 rows correct, schema 2.0 valid, "
        "source report == packaged report"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
