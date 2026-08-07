from __future__ import annotations

from pathlib import Path

import pytest

from control_tower_access_broker.config import ConfigurationError, Settings


def _environment(monkeypatch, tmp_path: Path) -> dict[str, str]:
    github_key = tmp_path / "github.pem"
    signing_key = tmp_path / "signing.pem"
    github_key.write_text("key")
    signing_key.write_text("key")
    github_key.chmod(0o600)
    signing_key.chmod(0o600)
    values = {
        "BROKER_ISSUER": "https://access.example.test",
        "BROKER_AUDIENCE": "https://secrets.example.test",
        "BROKER_ORG": "Example-Org",
        "BROKER_GITHUB_APP_ID": "1",
        "BROKER_GITHUB_INSTALLATION_ID": "2",
        "BROKER_GITHUB_PRIVATE_KEY_FILE": str(github_key),
        "BROKER_SIGNING_KEY_FILE": str(signing_key),
        "BROKER_SIGNING_KEY_ID": "2026-08",
        "BROKER_POLICY_REPOSITORY": "Example-Org/copilot-internal",
        "BROKER_DATABASE_PATH": str(tmp_path / "events.sqlite3"),
    }
    for name, value in values.items():
        monkeypatch.setenv(name, value)
    return values


def test_settings_accept_complete_fail_closed_configuration(monkeypatch, tmp_path):
    _environment(monkeypatch, tmp_path)
    monkeypatch.setenv("BROKER_TRUSTED_PROXY_CIDRS", "127.0.0.1/32,10.0.0.0/8")

    settings = Settings.from_environment()

    assert settings.assertion_ttl_seconds == 60
    assert settings.login_rate_per_minute == 10
    assert len(settings.trusted_proxy_networks) == 2


@pytest.mark.parametrize(
    "name,value,match",
    [
        ("BROKER_ISSUER", "http://access.example.test", "HTTPS origin"),
        ("BROKER_ASSERTION_TTL_SECONDS", "61", "at most 60"),
        ("BROKER_LOGIN_RATE_PER_MINUTE", "11", "at most 10"),
        ("BROKER_POLICY_REPOSITORY", "Other-Org/policy", "belong"),
        ("BROKER_SIGNING_KEY_ID", "not allowed!", "invalid shape"),
    ],
)
def test_settings_reject_unsafe_or_widened_values(monkeypatch, tmp_path, name, value, match):
    _environment(monkeypatch, tmp_path)
    monkeypatch.setenv(name, value)

    with pytest.raises(ConfigurationError, match=match):
        Settings.from_environment()


def test_settings_reject_world_readable_secret_file(monkeypatch, tmp_path):
    values = _environment(monkeypatch, tmp_path)
    Path(values["BROKER_SIGNING_KEY_FILE"]).chmod(0o644)

    with pytest.raises(ConfigurationError, match="private file"):
        Settings.from_environment()
