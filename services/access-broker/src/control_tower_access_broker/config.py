"""Fail-closed environment configuration for the access broker."""

from __future__ import annotations

import ipaddress
import os
import re
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

_REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


class ConfigurationError(RuntimeError):
    """The broker cannot start safely with the supplied configuration."""


def _required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ConfigurationError(f"{name} is required")
    return value


def _positive_int(name: str, default: int, *, maximum: int | None = None) -> int:
    raw = os.environ.get(name, str(default))
    try:
        value = int(raw)
    except ValueError as exc:
        raise ConfigurationError(f"{name} must be an integer") from exc
    if value <= 0 or (maximum is not None and value > maximum):
        ceiling = f" and at most {maximum}" if maximum is not None else ""
        raise ConfigurationError(f"{name} must be positive{ceiling}")
    return value


def _https_url(name: str) -> str:
    value = _required(name).rstrip("/")
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ConfigurationError(f"{name} must be an HTTPS origin without credentials")
    if parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
        raise ConfigurationError(f"{name} must be an origin, not a path")
    return value


def _secret_file(name: str) -> Path:
    path = Path(_required(name)).expanduser()
    try:
        mode = path.stat().st_mode & 0o777
    except OSError as exc:
        raise ConfigurationError(f"{name} is not readable") from exc
    if not path.is_file() or mode & 0o077:
        raise ConfigurationError(f"{name} must be a private file with mode 0600 or stricter")
    return path


Network = ipaddress.IPv4Network | ipaddress.IPv6Network


def _trusted_networks() -> tuple[Network, ...]:
    raw = os.environ.get("BROKER_TRUSTED_PROXY_CIDRS", "").strip()
    if not raw:
        return ()
    try:
        return tuple(ipaddress.ip_network(item.strip(), strict=False) for item in raw.split(","))
    except ValueError as exc:
        raise ConfigurationError("BROKER_TRUSTED_PROXY_CIDRS contains an invalid CIDR") from exc


@dataclass(frozen=True)
class Settings:
    issuer: str
    audience: str
    organization: str
    github_app_id: int
    github_installation_id: int
    github_private_key_file: Path
    signing_key_file: Path
    signing_key_id: str
    policy_repository: str
    policy_path: str
    policy_ref: str
    database_path: Path
    trusted_proxy_networks: tuple[Network, ...]
    nonce_ttl_seconds: int = 60
    assertion_ttl_seconds: int = 60
    login_rate_per_minute: int = 10
    ip_rate_per_minute: int = 30
    policy_cache_seconds: int = 60
    daily_issue_floor: int = 100

    @classmethod
    def from_environment(cls) -> Settings:
        organization = _required("BROKER_ORG")
        repository = _required("BROKER_POLICY_REPOSITORY")
        if not _REPOSITORY.fullmatch(repository):
            raise ConfigurationError("BROKER_POLICY_REPOSITORY must be owner/repository")
        if not repository.startswith(f"{organization}/"):
            raise ConfigurationError("BROKER_POLICY_REPOSITORY must belong to BROKER_ORG")
        policy_path = os.environ.get("BROKER_POLICY_PATH", "ecosystem.yml").strip()
        if not policy_path or policy_path.startswith("/") or ".." in Path(policy_path).parts:
            raise ConfigurationError("BROKER_POLICY_PATH must be a safe repository-relative path")
        signing_key_id = _required("BROKER_SIGNING_KEY_ID")
        if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", signing_key_id):
            raise ConfigurationError("BROKER_SIGNING_KEY_ID has an invalid shape")
        database_path = Path(
            os.environ.get(
                "BROKER_DATABASE_PATH",
                "/var/lib/control-tower-access-broker/events.sqlite3",
            )
        ).expanduser()
        return cls(
            issuer=_https_url("BROKER_ISSUER"),
            audience=_https_url("BROKER_AUDIENCE"),
            organization=organization,
            github_app_id=_positive_int("BROKER_GITHUB_APP_ID", 0),
            github_installation_id=_positive_int("BROKER_GITHUB_INSTALLATION_ID", 0),
            github_private_key_file=_secret_file("BROKER_GITHUB_PRIVATE_KEY_FILE"),
            signing_key_file=_secret_file("BROKER_SIGNING_KEY_FILE"),
            signing_key_id=signing_key_id,
            policy_repository=repository,
            policy_path=policy_path,
            policy_ref=os.environ.get("BROKER_POLICY_REF", "main").strip() or "main",
            database_path=database_path,
            trusted_proxy_networks=_trusted_networks(),
            nonce_ttl_seconds=_positive_int("BROKER_NONCE_TTL_SECONDS", 60, maximum=60),
            assertion_ttl_seconds=_positive_int("BROKER_ASSERTION_TTL_SECONDS", 60, maximum=60),
            login_rate_per_minute=_positive_int("BROKER_LOGIN_RATE_PER_MINUTE", 10, maximum=10),
            ip_rate_per_minute=_positive_int("BROKER_IP_RATE_PER_MINUTE", 30, maximum=30),
            policy_cache_seconds=_positive_int("BROKER_POLICY_CACHE_SECONDS", 60, maximum=300),
            daily_issue_floor=_positive_int("BROKER_DAILY_ISSUE_FLOOR", 100),
        )
