from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from control_tower_access_broker.app import Services, create_app
from control_tower_access_broker.config import Settings
from control_tower_access_broker.state import IssueLedger, NonceStore, SlidingWindowLimiter


class FakeGitHub:
    def __init__(self, *, public_key: str, policy: str, member: bool = True, teams=()) -> None:
        self.public_key = public_key
        self.policy = policy
        self.member = member
        self.teams = set(teams)

    def public_keys(self, _login: str) -> list[str]:
        return [self.public_key]

    def has_repository_access(self, _repository: str, _login: str) -> bool:
        return self.member

    def is_team_member(self, team: str, _login: str) -> bool:
        return team in self.teams

    def policy_source(self, _repository: str, _path: str, _ref: str) -> str:
        return self.policy


@pytest.fixture
def device_key(tmp_path: Path) -> tuple[Path, str]:
    key = tmp_path / "device"
    ssh_keygen = shutil.which("ssh-keygen")
    assert ssh_keygen is not None
    result = subprocess.run(  # noqa: S603 -- executable is resolved by shutil.which.
        [ssh_keygen, "-q", "-t", "ed25519", "-N", "", "-f", str(key)],
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0
    return key, Path(f"{key}.pub").read_text(encoding="utf-8").strip()


@pytest.fixture
def policy() -> str:
    return """\
schema_version: "2.0"
org: Example-Org
store:
  workspace_id: workspace-1
  broker_issuer: https://access.example.test
  broker_audience: https://secrets.example.test
  team_scopes:
    - team: everyone
      scope: shared
      environment: prod
      secret_path: /shared
      access: read
      identity_id: identity-shared-0001
    - team: accounting
      scope: accounting
      environment: prod
      secret_path: /departments/accounting
      access: read
      identity_id: identity-accounting-0001
"""


def make_services(tmp_path: Path, github: FakeGitHub, **overrides) -> Services:
    values = {
        "issuer": "https://access.example.test",
        "audience": "https://secrets.example.test",
        "organization": "Example-Org",
        "github_app_id": 1,
        "github_installation_id": 2,
        "github_private_key_file": tmp_path / "github.pem",
        "signing_key_file": tmp_path / "signing.pem",
        "signing_key_id": "test-key",
        "policy_repository": "Example-Org/copilot-internal",
        "policy_path": "ecosystem.yml",
        "policy_ref": "main",
        "database_path": tmp_path / "events.sqlite3",
        "trusted_proxy_networks": (),
        "nonce_ttl_seconds": 60,
        "assertion_ttl_seconds": 60,
        "login_rate_per_minute": 10,
        "ip_rate_per_minute": 30,
        "policy_cache_seconds": 60,
        "daily_issue_floor": 100,
    }
    values.update(overrides)
    settings = Settings(**values)
    signing_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return Services(
        settings=settings,
        signing_key=signing_key,
        github=github,
        nonces=NonceStore(settings.nonce_ttl_seconds),
        login_limiter=SlidingWindowLimiter(settings.login_rate_per_minute),
        ip_limiter=SlidingWindowLimiter(settings.ip_rate_per_minute),
        ledger=IssueLedger(settings.database_path, daily_floor=settings.daily_issue_floor),
    )


@pytest.fixture
def app_factory(tmp_path: Path):
    def factory(github: FakeGitHub, **overrides):
        return create_app(make_services(tmp_path, github, **overrides))

    return factory
