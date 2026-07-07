#!/usr/bin/env python3
"""Validate the M3 wizard fixture corpus: the mock-cc `auth` seam's output shape, and
the internal consistency of every scenarios/*.json manifest (referenced doctor/managed-
profile fixtures actually exist; no scenario other than the one documented adversarial
exception carries a secret-shaped field).

This is NOT validating against a frozen upstream JSON Schema -- per the M3 architecture
WP (.copilot/wp/15.md §0), `cc auth --json` has no schema yet (D-3-M3, batched to WS-A).
This script instead pins down the SHAPE this fixture corpus promises to the Rust seam
(Stream-A) and the UI (Stream-B): the ceremony fields, the terminal-status enum, and the
secret-never-crosses-the-seam invariant (fitness fn 2 in the WP).

Usage:
    python3 validate.py

Exit 0 iff every check passes.
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIXTURES_DIR = HERE.parent
MOCK_CC = FIXTURES_DIR / "mock-cc"
SCENARIOS_DIR = HERE / "scenarios"
CORPUS_DIR = FIXTURES_DIR / "corpus"
SETTINGS_DIR = FIXTURES_DIR / "settings"

CEREMONY_REQUIRED_KEYS = {"user_code", "verification_uri", "expires_in", "interval"}
POLL_ALLOWED_STATUSES = {"authorized", "denied", "expired", "timeout", "pending"}
# Field-name substrings that would indicate a secret/token crossed the seam. Checked
# against every key in every emitted JSON body (ceremony + poll), and against every
# scenario manifest's own JSON, EXCEPT the one documented adversarial fixture, which is
# permitted (and expected) to carry `access_token` as its entire reason for existing.
SECRET_SHAPED_SUBSTRINGS = ("token", "secret", "password", "credential", "api_key", "apikey")

ADVERSARIAL_SCENARIOS = {"signin-adversarial-leaked-field"}
ADVERSARIAL_ALLOWED_VALUE = "FAKE-SYNTHETIC-NOT-A-REAL-TOKEN-0000000000"

# Manifest KEYS (not prose values) that are expected/allowlisted even though they
# contain a secret-shaped substring, because they describe the CONCEPT (e.g. "did a
# token ever cross the seam? no.") rather than carrying an actual secret VALUE. The
# secret-shape scan below walks JSON KEYS ONLY -- free-text prose fields (title,
# notes, scenario_id, description) legitimately discuss tokens/credentials in the
# abstract and are excluded from the scan entirely.
ALLOWLISTED_KEYS = {
    "token_ever_seen_by_app",
    "wizard_auth_scenario",
    "auth_terminal_status",
    "managed_profile_state",
}
PROSE_KEYS = {"title", "notes", "scenario_id", "description"}


def collect_secret_shaped_keys(obj, path="") -> list[str]:
    """Recursively collect JSON key paths that look secret-shaped, skipping prose
    fields and the explicit allowlist above."""
    hits = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in PROSE_KEYS:
                continue
            key_path = f"{path}.{k}" if path else k
            if k not in ALLOWLISTED_KEYS and any(s in k.lower() for s in SECRET_SHAPED_SUBSTRINGS):
                hits.append(key_path)
            hits.extend(collect_secret_shaped_keys(v, key_path))
    elif isinstance(obj, list):
        for idx, item in enumerate(obj):
            hits.extend(collect_secret_shaped_keys(item, f"{path}[{idx}]"))
    return hits


def run_mock_cc(args, env_overrides):
    import os
    env = dict(os.environ)
    env.update(env_overrides)
    result = subprocess.run(
        [str(MOCK_CC), *args], capture_output=True, text=True, env=env, timeout=10
    )
    return result


def check_ceremony_shape() -> list[str]:
    failures = []
    result = run_mock_cc(["auth", "--json"], {})
    if result.returncode != 0:
        failures.append(f"auth initiate: expected exit 0, got {result.returncode}")
        return failures
    try:
        body = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        failures.append(f"auth initiate: stdout did not parse as JSON: {e}")
        return failures
    if set(body.keys()) != CEREMONY_REQUIRED_KEYS:
        failures.append(
            f"auth initiate: expected EXACTLY {sorted(CEREMONY_REQUIRED_KEYS)}, got {sorted(body.keys())}"
        )
    for key in body:
        if any(s in key.lower() for s in SECRET_SHAPED_SUBSTRINGS):
            failures.append(f"auth initiate: ceremony field '{key}' looks secret-shaped -- must never appear")
    if not failures:
        print("  OK   auth initiate ceremony shape (user_code, verification_uri, expires_in, interval; no secret field)")
    # `auth login --json` must be an identical alias (D-3-M3 recommendation #2).
    login_result = run_mock_cc(["auth", "login", "--json"], {})
    if login_result.returncode != 0 or login_result.stdout != result.stdout:
        failures.append("auth login --json: must be byte-identical to `auth --json` (alias, not a distinct verb)")
    else:
        print("  OK   auth login --json is an identical alias for auth --json")
    return failures


def check_poll_scenarios() -> list[str]:
    failures = []
    for scenario in sorted(POLL_ALLOWED_STATUSES):
        result = run_mock_cc(["auth", "--json", "--poll"], {"CT_AUTH_SCENARIO": scenario})
        if result.returncode != 0:
            failures.append(f"auth poll scenario={scenario}: expected exit 0, got {result.returncode}")
            continue
        try:
            body = json.loads(result.stdout)
        except json.JSONDecodeError as e:
            failures.append(f"auth poll scenario={scenario}: stdout did not parse as JSON: {e}")
            continue
        if body.get("status") != scenario:
            failures.append(f"auth poll scenario={scenario}: expected status='{scenario}', got {body.get('status')!r}")
        if set(body.keys()) != {"status"}:
            failures.append(f"auth poll scenario={scenario}: expected ONLY a 'status' key, got {sorted(body.keys())}")
        for key in body:
            if any(s in key.lower() for s in SECRET_SHAPED_SUBSTRINGS):
                failures.append(f"auth poll scenario={scenario}: field '{key}' looks secret-shaped -- must never appear")
        if not any(f.startswith(f"auth poll scenario={scenario}") for f in failures):
            print(f"  OK   auth poll scenario={scenario} (status-only body, no secret field)")

    # exit-2 env-error path
    result = run_mock_cc(["auth", "--json", "--poll"], {"CT_AUTH_SCENARIO": "exit-2"})
    if result.returncode != 2:
        failures.append(f"auth poll scenario=exit-2: expected exit 2, got {result.returncode}")
    elif result.stdout.strip():
        failures.append("auth poll scenario=exit-2: expected NO stdout body (no trustworthy body on env error)")
    else:
        print("  OK   auth poll scenario=exit-2 (exit 2, no stdout body)")

    # unknown scenario name -> exit 2, fail closed
    result = run_mock_cc(["auth", "--json", "--poll"], {"CT_AUTH_SCENARIO": "not-a-real-scenario"})
    if result.returncode != 2:
        failures.append(f"auth poll scenario=<unknown>: expected exit 2 (fail closed), got {result.returncode}")
    else:
        print("  OK   auth poll scenario=<unknown> fails closed with exit 2")

    # the one documented adversarial scenario: the leaked field MUST be present (that's
    # its entire purpose) but MUST be exactly the documented obviously-fake constant --
    # never a different, more realistic-looking value.
    result = run_mock_cc(["auth", "--json", "--poll"], {"CT_AUTH_SCENARIO": "authorized-leaked-field-adversarial"})
    if result.returncode != 0:
        failures.append(f"auth poll scenario=authorized-leaked-field-adversarial: expected exit 0, got {result.returncode}")
    else:
        try:
            body = json.loads(result.stdout)
        except json.JSONDecodeError as e:
            failures.append(f"auth poll scenario=authorized-leaked-field-adversarial: stdout did not parse: {e}")
            body = {}
        if body.get("status") != "authorized":
            failures.append("auth poll scenario=authorized-leaked-field-adversarial: expected status='authorized'")
        if body.get("access_token") != ADVERSARIAL_ALLOWED_VALUE:
            failures.append(
                "auth poll scenario=authorized-leaked-field-adversarial: expected the documented obviously-fake "
                f"access_token constant ({ADVERSARIAL_ALLOWED_VALUE!r}), got {body.get('access_token')!r} -- "
                "a realistic-looking value here would defeat the point of the negative test"
            )
        if not any("authorized-leaked-field-adversarial" in f for f in failures):
            print("  OK   auth poll scenario=authorized-leaked-field-adversarial carries exactly the documented synthetic poison")
    return failures


def check_scenario_manifests() -> list[str]:
    failures = []
    files = sorted(SCENARIOS_DIR.glob("*.json"))
    if not files:
        failures.append("scenarios/ is empty -- no wizard scenario manifests to validate")
    required_keys = {"fixture_version", "scenario_id", "title", "path", "env", "expected"}
    for path in files:
        try:
            manifest = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            failures.append(f"scenarios/{path.name}: NOT VALID JSON ({e})")
            continue
        missing = required_keys - manifest.keys()
        if missing:
            failures.append(f"scenarios/{path.name}: missing required key(s) {sorted(missing)}")
        if manifest.get("scenario_id") != path.stem:
            failures.append(f"scenarios/{path.name}: scenario_id '{manifest.get('scenario_id')}' must match filename stem '{path.stem}'")
        if manifest.get("path") not in {"managed", "unmanaged"}:
            failures.append(f"scenarios/{path.name}: 'path' must be 'managed' or 'unmanaged', got {manifest.get('path')!r}")

        # Cross-reference: env.CT_FIXTURE, if present, must resolve to a real doctor
        # corpus/invalid fixture (reuse the existing doctor corpus, per task scope).
        env = manifest.get("env", {})
        ct_fixture = env.get("CT_FIXTURE")
        if ct_fixture:
            if not (CORPUS_DIR / f"{ct_fixture}.json").exists() and not (FIXTURES_DIR / "invalid" / f"{ct_fixture}.json").exists():
                failures.append(f"scenarios/{path.name}: env.CT_FIXTURE='{ct_fixture}' does not resolve to any corpus/ or invalid/ fixture")

        ct_auth_scenario = env.get("CT_AUTH_SCENARIO")
        known_auth_scenarios = POLL_ALLOWED_STATUSES | {"authorized-leaked-field-adversarial", "exit-2"}
        if ct_auth_scenario and ct_auth_scenario not in known_auth_scenarios:
            failures.append(f"scenarios/{path.name}: env.CT_AUTH_SCENARIO='{ct_auth_scenario}' is not a scenario mock-cc understands")

        # Cross-reference: managed_profile_fixture, if present, must resolve to a real
        # file under settings/ (reused from M2 -- never re-authored here).
        profile = manifest.get("managed_profile_fixture")
        if profile:
            resolved = (path.parent / profile).resolve()
            if not resolved.exists():
                failures.append(f"scenarios/{path.name}: managed_profile_fixture '{profile}' does not exist ({resolved})")

        # No secret-shaped KEY anywhere in a non-adversarial manifest (prose values
        # in title/notes/scenario_id/description are exempt -- see PROSE_KEYS).
        if path.stem not in ADVERSARIAL_SCENARIOS:
            hits = collect_secret_shaped_keys(manifest)
            for h in hits:
                failures.append(f"scenarios/{path.name}: key '{h}' is secret-shaped but this is not a documented adversarial fixture")
        else:
            # The adversarial fixture is EXPECTED to carry raw_poll_body_emitted.access_token
            # -- confirm it's exactly the documented synthetic constant, not a realistic one.
            raw = manifest.get("raw_poll_body_emitted", {})
            if raw.get("access_token") != ADVERSARIAL_ALLOWED_VALUE:
                failures.append(
                    f"scenarios/{path.name}: raw_poll_body_emitted.access_token must be the documented "
                    f"synthetic constant {ADVERSARIAL_ALLOWED_VALUE!r}, got {raw.get('access_token')!r}"
                )

        if not any(path.name in f for f in failures):
            print(f"  OK   scenarios/{path.name}")
    return failures


def check_products_sample() -> list[str]:
    failures = []
    p = HERE / "products.sample.json"
    if not p.exists():
        failures.append("products.sample.json is missing")
        return failures
    try:
        data = json.loads(p.read_text())
    except json.JSONDecodeError as e:
        failures.append(f"products.sample.json: NOT VALID JSON ({e})")
        return failures
    products = data.get("products", [])
    if not isinstance(products, list) or not products:
        failures.append("products.sample.json: 'products' must be a non-empty list")
    ids = [pr.get("id") for pr in products if isinstance(pr, dict)]
    if len(ids) != len(set(ids)):
        failures.append("products.sample.json: duplicate product ids")
    if not failures:
        print("  OK   products.sample.json")
    return failures


def main() -> int:
    if not MOCK_CC.exists():
        print(f"error: {MOCK_CC} not found", file=sys.stderr)
        return 2

    print("Checking mock-cc auth initiate/ceremony shape:")
    f1 = check_ceremony_shape()
    print()
    print("Checking mock-cc auth poll scenarios (terminal + pending + env-error + adversarial):")
    f2 = check_poll_scenarios()
    print()
    print("Checking wizard/scenarios/*.json manifests (cross-references + no leaked secrets):")
    f3 = check_scenario_manifests()
    print()
    print("Checking wizard/products.sample.json:")
    f4 = check_products_sample()

    failures = f1 + f2 + f3 + f4
    print()
    if failures:
        print(f"FAILED ({len(failures)}):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("All wizard fixtures behave as expected: auth seam shape is frozen-and-clean, "
          "scenario manifests cross-reference real fixtures, no secret ever crosses the seam.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
