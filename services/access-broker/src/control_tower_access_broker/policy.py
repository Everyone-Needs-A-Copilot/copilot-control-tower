"""Strict parser for protected store.team_scopes policy."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

import yaml

_SLUG = re.compile(r"^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$")
_IDENTITY_ID = re.compile(r"^[A-Za-z0-9-]{8,80}$")
_ROW_KEYS = {
    "team",
    "scope",
    "workspace_id",
    "environment",
    "secret_path",
    "access",
    "identity_id",
}


class PolicyError(RuntimeError):
    """Protected organization policy is absent, malformed, or unsafe."""


@dataclass(frozen=True)
class ScopePolicy:
    team: str
    scope: str
    workspace_id: str
    environment: str
    secret_path: str
    identity_id: str


def _text(row: dict[str, Any], key: str) -> str:
    value = row.get(key)
    if not isinstance(value, str) or not value.strip():
        raise PolicyError(f"team_scopes.{key} must be a non-empty string")
    return value.strip()


def parse_policy(
    source: str,
    *,
    expected_issuer: str,
    expected_audience: str,
) -> tuple[str, list[ScopePolicy]]:
    try:
        payload = yaml.safe_load(source)
    except yaml.YAMLError as exc:
        raise PolicyError("organization policy is not valid YAML") from exc
    if not isinstance(payload, dict):
        raise PolicyError("organization policy must be a mapping")
    store = payload.get("store")
    if not isinstance(store, dict):
        raise PolicyError("organization policy has no store mapping")
    if store.get("broker_issuer") != expected_issuer:
        raise PolicyError("organization policy broker issuer does not match this broker")
    if store.get("broker_audience") != expected_audience:
        raise PolicyError("organization policy broker audience does not match this broker")
    default_workspace = store.get("workspace_id")
    if not isinstance(default_workspace, str) or not default_workspace.strip():
        raise PolicyError("organization policy has no workspace_id")
    rows = store.get("team_scopes")
    if not isinstance(rows, list) or not rows:
        raise PolicyError("organization policy has no team scopes")

    parsed: list[ScopePolicy] = []
    seen: set[str] = set()
    for item in rows:
        if not isinstance(item, dict) or set(item) - _ROW_KEYS:
            raise PolicyError("team_scopes contains an invalid row or unknown field")
        team = _text(item, "team").casefold()
        scope = _text(item, "scope").casefold()
        environment = _text(item, "environment")
        secret_path = _text(item, "secret_path")
        access = _text(item, "access").casefold()
        identity_id = _text(item, "identity_id")
        workspace = item.get("workspace_id", default_workspace)
        if not isinstance(workspace, str) or not workspace.strip():
            raise PolicyError("team_scopes.workspace_id must be a non-empty string")
        if team != "everyone" and not _SLUG.fullmatch(team):
            raise PolicyError("team_scopes.team has an invalid slug")
        if not _SLUG.fullmatch(scope) or scope in seen:
            raise PolicyError("team_scopes.scope is invalid or duplicated")
        if access != "read":
            raise PolicyError("self-service team scopes must be read-only")
        if not _IDENTITY_ID.fullmatch(identity_id):
            raise PolicyError("team_scopes.identity_id has an invalid shape")
        if (
            not secret_path.startswith("/")
            or "//" in secret_path
            or ".." in secret_path.split("/")
            or any(mark in secret_path for mark in "*?[]{}")
        ):
            raise PolicyError("team_scopes.secret_path must be an absolute path without wildcards")
        if any(mark in environment for mark in "*?[]{}"):
            raise PolicyError("team_scopes.environment must not contain wildcards")
        seen.add(scope)
        parsed.append(
            ScopePolicy(
                team=team,
                scope=scope,
                workspace_id=workspace.strip(),
                environment=environment,
                secret_path=secret_path,
                identity_id=identity_id,
            )
        )
    return str(payload.get("org") or ""), parsed
