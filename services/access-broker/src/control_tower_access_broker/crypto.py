"""Minimal JOSE signing for GitHub App and Infisical OIDC assertions."""

from __future__ import annotations

import base64
import json
import secrets
import time
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa


class KeyError(RuntimeError):
    """A configured signing key is not a safe RSA key."""


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _json_segment(value: dict[str, Any]) -> str:
    return b64url(json.dumps(value, separators=(",", ":"), sort_keys=True).encode("utf-8"))


def load_rsa_private_key(path: Path) -> rsa.RSAPrivateKey:
    try:
        loaded = serialization.load_pem_private_key(path.read_bytes(), password=None)
    except (OSError, TypeError, ValueError) as exc:
        raise KeyError("configured key is not a readable unencrypted PEM private key") from exc
    if not isinstance(loaded, rsa.RSAPrivateKey) or loaded.key_size < 2048:
        raise KeyError("configured key must be an RSA key of at least 2048 bits")
    return loaded


def sign_compact_jwt(
    key: rsa.RSAPrivateKey,
    claims: dict[str, Any],
    *,
    key_id: str | None = None,
) -> str:
    header: dict[str, Any] = {"alg": "RS256", "typ": "JWT"}
    if key_id:
        header["kid"] = key_id
    signing_input = f"{_json_segment(header)}.{_json_segment(claims)}"
    signature = key.sign(
        signing_input.encode("ascii"),
        padding.PKCS1v15(),
        hashes.SHA256(),
    )
    return f"{signing_input}.{b64url(signature)}"


def github_app_jwt(key: rsa.RSAPrivateKey, app_id: int, *, now: int | None = None) -> str:
    issued = int(time.time()) if now is None else now
    return sign_compact_jwt(
        key,
        {"iat": issued - 60, "exp": issued + 540, "iss": str(app_id)},
    )


def oidc_assertion(
    key: rsa.RSAPrivateKey,
    *,
    key_id: str,
    issuer: str,
    audience: str,
    organization: str,
    login: str,
    machine_id: str,
    scope: str,
    ttl_seconds: int,
    now: int | None = None,
) -> tuple[str, int]:
    issued = int(time.time()) if now is None else now
    expires = issued + ttl_seconds
    subject = f"github:{login.casefold()}:machine:{machine_id}"
    claims = {
        "iss": issuer,
        "sub": subject,
        "aud": audience,
        "iat": issued,
        "nbf": issued - 5,
        "exp": expires,
        "jti": secrets.token_urlsafe(24),
        "org": organization,
        "github_login": login.casefold(),
        "machine_id": machine_id,
        "copilot_scope": scope,
    }
    return sign_compact_jwt(key, claims, key_id=key_id), expires


def jwk_for_key(key: rsa.RSAPrivateKey, *, key_id: str) -> dict[str, str]:
    numbers = key.public_key().public_numbers()
    exponent = numbers.e.to_bytes((numbers.e.bit_length() + 7) // 8, "big")
    modulus = numbers.n.to_bytes((numbers.n.bit_length() + 7) // 8, "big")
    return {
        "kty": "RSA",
        "use": "sig",
        "alg": "RS256",
        "kid": key_id,
        "e": b64url(exponent),
        "n": b64url(modulus),
    }
