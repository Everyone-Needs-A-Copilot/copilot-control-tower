#!/usr/bin/env python3
"""Validate the doctor fixture corpus against docs/01-architecture/schemas/doctor.schema.json,
PLUS (Stream-Z WS-A integration) the `layers`/`projects` fixture corpora added alongside the
`auth`/`layers`/`freshness --all-projects`/`update --project|--fanout` mock-cc surfaces.

Usage:
    python3 validate.py

Exit code 0 iff every fixture under corpus/ is schema-valid (Draft 2020-12) AND
every fixture under invalid/ is confirmed non-schema-valid or unparseable (i.e. it
is doing its job as an adversarial case), AND every fixture under layers/corpus/
validates against layers.schema.json, AND every fixture under projects/corpus/
validates against projects.schema.json (which $refs update.schema.json for a
per-project materialize `report`), AND every fixture under connections/corpus/
validates against connections.schema.json (task 221 bridge stage C). This
intentionally does NOT assert anything about the app's own semantic range-gate
(MIN_SCHEMA/MAX_SCHEMA are Rust compiled-in constants, not part of the JSON
Schema — see doctor.schema.json's $comment on the `status` property and
README.md in this directory).

`deprovision/corpus/`, `update/corpus/` (their own, non-`layers`/`projects` shapes)
are deliberately NOT validated here — see their own README.md files: those two are
exercised by this repo's Rust-side `model::deprovision`/`model::update` fail-closed
parsing tests directly (a different app-side ownership boundary than this Python
schema validator), the same precedent this file continues for doctor/layers/projects.
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
LAYERS_CORPUS_DIR = HERE / "layers" / "corpus"
PROJECTS_CORPUS_DIR = HERE / "projects" / "corpus"
CONNECTIONS_CORPUS_DIR = HERE / "connections" / "corpus"

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


def load_wsa_registry() -> Registry:
    """Registry for the newer WS-A verb schemas (layers/projects, which $refs
    update.schema.json for the per-project materialize `report`; connections,
    task 221 bridge stage C, which $refs only `_envelope.schema.json`) -- kept
    separate from `load_registry()` above (doctor-only) so neither corpus's
    validator accidentally cross-resolves the other's `$id`."""
    resources = []
    for name in (
        "_envelope.schema.json",
        "update.schema.json",
        "layers.schema.json",
        "projects.schema.json",
        "connections.schema.json",
    ):
        contents = json.loads((SCHEMAS_DIR / name).read_text())
        resources.append(Resource.from_contents(contents, default_specification=DRAFT202012))
    return Registry().with_resources([(r.contents["$id"], r) for r in resources])


def build_layers_validator(registry: Registry) -> Draft202012Validator:
    schema = json.loads((SCHEMAS_DIR / "layers.schema.json").read_text())
    return Draft202012Validator(schema, registry=registry)


def build_projects_validator(registry: Registry) -> Draft202012Validator:
    schema = json.loads((SCHEMAS_DIR / "projects.schema.json").read_text())
    return Draft202012Validator(schema, registry=registry)


def build_connections_validator(registry: Registry) -> Draft202012Validator:
    schema = json.loads((SCHEMAS_DIR / "connections.schema.json").read_text())
    return Draft202012Validator(schema, registry=registry)


def check_generic_corpus(validator: Draft202012Validator, corpus_dir: Path, label: str) -> list[str]:
    """Same all-must-pass check as check_corpus(), generalized for a named
    corpus dir + a schema label in the printed/failure output."""
    failures = []
    files = sorted(corpus_dir.glob("*.json"))
    if not files:
        failures.append(f"{label}/ is empty — no fixtures to validate")
    for path in files:
        try:
            instance = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            failures.append(f"{label}/{path.name}: NOT VALID JSON ({e}) — {label}/ fixtures must parse")
            continue
        errors = sorted(validator.iter_errors(instance), key=lambda e: e.path)
        if errors:
            msgs = "; ".join(f"{list(e.path)}: {e.message}" for e in errors)
            failures.append(f"{label}/{path.name}: SCHEMA INVALID — {msgs}")
        else:
            print(f"  OK   {label}/{path.name}")
    return failures


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

    wsa_registry = load_wsa_registry()
    layers_validator = build_layers_validator(wsa_registry)
    projects_validator = build_projects_validator(wsa_registry)
    connections_validator = build_connections_validator(wsa_registry)

    print()
    print("Validating layers/corpus/ (must ALL pass layers.schema.json):")
    layers_failures = check_generic_corpus(layers_validator, LAYERS_CORPUS_DIR, "layers/corpus")

    print()
    print("Validating projects/corpus/ (must ALL pass projects.schema.json):")
    projects_failures = check_generic_corpus(projects_validator, PROJECTS_CORPUS_DIR, "projects/corpus")

    print()
    print("Validating connections/corpus/ (must ALL pass connections.schema.json):")
    connections_failures = check_generic_corpus(connections_validator, CONNECTIONS_CORPUS_DIR, "connections/corpus")

    failures = corpus_failures + invalid_failures + layers_failures + projects_failures + connections_failures
    print()
    if failures:
        print(f"FAILED ({len(failures)}):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("All fixtures behave as expected. Corpus is schema-valid; invalid/ fixtures are adversarial as intended; "
          "layers/corpus/, projects/corpus/, and connections/corpus/ are schema-valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
