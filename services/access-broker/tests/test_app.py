from __future__ import annotations

import base64
import json
import logging
import shutil
import subprocess

from conftest import FakeGitHub
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from fastapi.testclient import TestClient

from control_tower_access_broker.ssh_verify import SIGNATURE_NAMESPACE, canonical_challenge

LOGIN = "pablo"
MACHINE_ID = "0123456789abcdef0123456789abcdef"


def _decode(segment: str) -> dict:
    segment += "=" * (-len(segment) % 4)
    return json.loads(base64.urlsafe_b64decode(segment).decode("utf-8"))


def _sign(device_key, challenge: dict) -> str:
    message = canonical_challenge(
        audience="https://access.example.test",
        login=LOGIN,
        machine_id=MACHINE_ID,
        nonce_id=challenge["nonce_id"],
        nonce=challenge["nonce"],
    )
    ssh_keygen = shutil.which("ssh-keygen")
    assert ssh_keygen is not None
    result = subprocess.run(  # noqa: S603 -- executable is resolved by shutil.which.
        [
            ssh_keygen,
            "-Y",
            "sign",
            "-f",
            str(device_key),
            "-n",
            SIGNATURE_NAMESPACE,
            "-",
        ],
        input=message,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0
    return result.stdout.decode("utf-8")


def _challenge(client: TestClient) -> dict:
    response = client.post(
        "/v1/challenges",
        json={"schema_version": "1.0", "login": LOGIN, "machine_id": MACHINE_ID},
    )
    assert response.status_code == 200
    return response.json()


def _assertion_request(challenge: dict, signature: str) -> dict:
    return {
        "schema_version": "1.0",
        "login": LOGIN,
        "machine_id": MACHINE_ID,
        "nonce_id": challenge["nonce_id"],
        "nonce": challenge["nonce"],
        "signature": signature,
    }


def test_issues_scope_bound_assertions_and_rejects_replay_without_logging_tokens(
    app_factory, device_key, policy, caplog
):
    key_path, public_key = device_key
    github = FakeGitHub(public_key=public_key, policy=policy, teams={"accounting"})
    app = app_factory(github)
    with (
        TestClient(app) as client,
        caplog.at_level(logging.INFO, logger="control_tower_access_broker.audit"),
    ):
        challenge = _challenge(client)
        signature = _sign(key_path, challenge)
        request = _assertion_request(challenge, signature)
        response = client.post("/v1/assertions", json=request)
        assert response.status_code == 200
        report = response.json()
        assert [row["scope"] for row in report["assertions"]] == ["shared", "accounting"]
        token = report["assertions"][0]["assertion"]
        header_segment, payload_segment, signature_segment = token.split(".")
        assert _decode(header_segment) == {"alg": "RS256", "kid": "test-key", "typ": "JWT"}
        claims = _decode(payload_segment)
        assert claims["iss"] == "https://access.example.test"
        assert claims["aud"] == "https://secrets.example.test"
        assert claims["sub"] == f"github:{LOGIN}:machine:{MACHINE_ID}"
        assert claims["copilot_scope"] == "shared"
        assert 0 < claims["exp"] - claims["iat"] <= 60
        signed = f"{header_segment}.{payload_segment}".encode("ascii")
        token_signature = base64.urlsafe_b64decode(
            signature_segment + "=" * (-len(signature_segment) % 4)
        )
        app.state.services.signing_key.public_key().verify(
            token_signature,
            signed,
            padding.PKCS1v15(),
            hashes.SHA256(),
        )

        replay = client.post("/v1/assertions", json=request)
        assert replay.status_code == 401
        assert replay.json()["error"]["code"] == "identity-not-confirmed"

    rendered_logs = "\n".join(record.getMessage() for record in caplog.records)
    assert token not in rendered_logs
    assert signature not in rendered_logs
    assert challenge["nonce"] not in rendered_logs
    assert "shared" in rendered_logs


def test_denies_valid_machine_without_current_org_membership(app_factory, device_key, policy):
    key_path, public_key = device_key
    github = FakeGitHub(public_key=public_key, policy=policy, member=False)
    with TestClient(app_factory(github)) as client:
        challenge = _challenge(client)
        response = client.post(
            "/v1/assertions",
            json=_assertion_request(challenge, _sign(key_path, challenge)),
        )
    assert response.status_code == 403
    assert response.json()["result"] == "not-entitled"
    assert "assertions" not in response.json()


def test_bad_signature_consumes_challenge(app_factory, device_key, policy):
    _key_path, public_key = device_key
    github = FakeGitHub(public_key=public_key, policy=policy)
    with TestClient(app_factory(github)) as client:
        challenge = _challenge(client)
        request = _assertion_request(
            challenge,
            "-----BEGIN SSH SIGNATURE-----\n" + "A" * 100 + "\n-----END SSH SIGNATURE-----\n",
        )
        first = client.post("/v1/assertions", json=request)
        second = client.post("/v1/assertions", json=request)
    assert first.status_code == 401
    assert second.status_code == 401


def test_challenge_rate_limit_is_fail_closed(app_factory, device_key, policy):
    _key_path, public_key = device_key
    github = FakeGitHub(public_key=public_key, policy=policy)
    with TestClient(app_factory(github, login_rate_per_minute=1)) as client:
        assert _challenge(client)
        limited = client.post(
            "/v1/challenges",
            json={"schema_version": "1.0", "login": LOGIN, "machine_id": MACHINE_ID},
        )
    assert limited.status_code == 429
    assert limited.json()["result"] == "rate-limited"


def test_discovery_publishes_only_public_key_material(app_factory, device_key, policy):
    _key_path, public_key = device_key
    github = FakeGitHub(public_key=public_key, policy=policy)
    app = app_factory(github)
    with TestClient(app) as client:
        discovery = client.get("/.well-known/openid-configuration")
        jwks = client.get("/.well-known/jwks.json")
    assert discovery.json()["issuer"] == "https://access.example.test"
    assert discovery.json()["jwks_uri"].endswith("/.well-known/jwks.json")
    assert set(jwks.json()["keys"][0]) == {"alg", "e", "kid", "kty", "n", "use"}


def test_validation_error_never_reflects_signature(app_factory, device_key, policy):
    _key_path, public_key = device_key
    marker = "secret-shaped-signature-marker"
    github = FakeGitHub(public_key=public_key, policy=policy)
    with TestClient(app_factory(github)) as client:
        response = client.post(
            "/v1/assertions",
            json={
                "schema_version": "1.0",
                "login": LOGIN,
                "machine_id": MACHINE_ID,
                "nonce_id": "too-short",
                "nonce": "too-short",
                "signature": marker,
            },
        )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid-request"
    assert marker not in response.text
