#!/usr/bin/env python3
"""Validate the doctor fixture corpus against docs/01-architecture/schemas/doctor.schema.json.

Usage:
    python3 validate.py

Exit code 0 iff every fixture under corpus/ is schema-valid (Draft 2020-12) AND
every fixture under invalid/ is confirmed non-schema-valid or unparseable (i.e. it
is doing its job as an adversarial case). This intentionally does NOT assert
anything about the app's own semantic range-gate (MIN_SCHEMA/MAX_SCHEMA are Rust
compiled-in constants, not part of the JSON Schema — see doctor.schema.json's
$comment on the `status` property and README.md in this directory).
"""
import json
import sys
from pathlib import Path

import jsonschema
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

HERE = Path(__file__).resolve().parent
SCHEMAS_DIR = HERE.parent.parent / "docs" / "01-architecture" / "schemas"
CORPUS_DIR = HERE / "corpus"
INVALID_DIR = HERE / "invalid"

# Fixtures that are syntactically schema-valid on purpose (the schema cannot encode
# the app's compiled-in min/max range — see doctor.schema.json's allOf $comment).
# These exist to exercise the app-side bidirectional range gate (Rust), not the
# JSON Schema validator, so validate.py treats them as an expected exception
# within invalid/ rather than a validator failure.
SEMANTICALLY_INVALID_BUT_SCHEMA_VALID = {
    "schema-version-above-max.json",
    "schema-version-below-min.json",
}


def load_registry() -> Registry:
    envelope_path = SCHEMAS_DIR / "_envelope.schema.json"
    doctor_path = SCHEMAS_DIR / "doctor.schema.json"
    resources = []
    for path in (envelope_path, doctor_path):
        contents = json.loads(path.read_text())
        resources.append(Resource.from_contents(contents, default_specification=DRAFT202012))
    return Registry().with_resources(
        [(r.contents["$id"], r) for r in resources]
    )


def build_validator() -> Draft202012Validator:
    doctor_schema = json.loads((SCHEMAS_DIR / "doctor.schema.json").read_text())
    registry = load_registry()
    return Draft202012Validator(doctor_schema, registry=registry)


def check_corpus(validator: Draft202012Validator) -> list[str]:
    failures = []
    files = sorted(CORPUS_DIR.glob("*.json"))
    if not files:
        failures.append("corpus/ is empty — no fixtures to validate")
    for path in files:
        try:
            instance = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            failures.append(f"corpus/{path.name}: NOT VALID JSON ({e}) — corpus/ fixtures must parse")
            continue
        errors = sorted(validator.iter_errors(instance), key=lambda e: e.path)
        if errors:
            msgs = "; ".join(f"{list(e.path)}: {e.message}" for e in errors)
            failures.append(f"corpus/{path.name}: SCHEMA INVALID — {msgs}")
        else:
            print(f"  OK   corpus/{path.name}")
    return failures


def check_invalid(validator: Draft202012Validator) -> list[str]:
    failures = []
    files = sorted(INVALID_DIR.glob("*.json"))
    if not files:
        failures.append("invalid/ is empty — no adversarial fixtures to check")
    for path in files:
        try:
            instance = json.loads(path.read_text())
        except json.JSONDecodeError:
            print(f"  OK   invalid/{path.name} (unparseable JSON, as intended)")
            continue
        errors = list(validator.iter_errors(instance))
        if errors:
            print(f"  OK   invalid/{path.name} (schema-invalid, as intended: {errors[0].message})")
        elif path.name in SEMANTICALLY_INVALID_BUT_SCHEMA_VALID:
            print(f"  OK   invalid/{path.name} (schema-valid syntax; semantically out-of-range — app range-gate case, not a JSON Schema case)")
        else:
            failures.append(
                f"invalid/{path.name}: unexpectedly SCHEMA VALID and not in the documented "
                "semantic-only exception list — this fixture is not doing its job as an adversarial case"
            )
    return failures


def main() -> int:
    validator = build_validator()
    print("Validating corpus/ (must ALL pass doctor.schema.json):")
    corpus_failures = check_corpus(validator)
    print()
    print("Checking invalid/ (must ALL fail to validate, or be documented range-gate exceptions):")
    invalid_failures = check_invalid(validator)

    failures = corpus_failures + invalid_failures
    print()
    if failures:
        print(f"FAILED ({len(failures)}):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("All fixtures behave as expected. Corpus is schema-valid; invalid/ fixtures are adversarial as intended.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
