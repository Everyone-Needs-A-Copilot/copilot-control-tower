from __future__ import annotations

import base64

import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from control_tower_access_broker.github import GitHubClient, GitHubUnavailable


class _Response:
    def __init__(self, status: int, payload=None, text: str = ""):
        self.status_code = status
        self._payload = payload
        self.text = text
        self.content = text.encode("utf-8")

    def json(self):
        if self._payload is None:
            raise ValueError
        return self._payload


class _HTTP:
    def __init__(self):
        self.posts = 0

    def close(self):
        pass

    def post(self, url, headers, json):
        del url
        self.posts += 1
        assert headers["Authorization"].startswith("Bearer ")
        assert json == {
            "repositories": ["policy"],
            "permissions": {"contents": "read", "metadata": "read"},
        }
        return _Response(201, {"token": "installation-token"})

    def get(self, url, headers=None, params=None):
        del params
        if url.endswith("/pablo.keys"):
            return _Response(
                200,
                text="ssh-ed25519 AAAATEST valid\nssh-rsa ignored\n",
            )
        assert headers["Authorization"] == "Bearer installation-token"
        if "/collaborators/" in url and url.endswith("/permission"):
            return _Response(
                200,
                {
                    "permission": "read",
                    "role_name": "read",
                    "user": {"login": "pablo"},
                },
            )
        if "/teams/accounting/" in url:
            return _Response(200, {"state": "active"})
        if "/teams/other/" in url:
            return _Response(404, {})
        if "/contents/" in url:
            encoded = base64.b64encode(b"org: Example-Org\n").decode()
            return _Response(200, {"encoding": "base64", "content": encoded})
        raise AssertionError(url)


@pytest.fixture
def github():
    client = GitHubClient(
        organization="Example-Org",
        policy_repository="Example-Org/policy",
        app_id=1,
        installation_id=2,
        app_key=rsa.generate_private_key(public_exponent=65537, key_size=2048),
        api_base="https://api.example.test",
        public_keys_base="https://keys.example.test",
    )
    client._http.close()
    client._http = _HTTP()
    return client


def test_github_client_uses_app_authority_and_filters_public_keys(github):
    assert github.public_keys("pablo") == ["ssh-ed25519 AAAATEST valid"]
    assert github.has_repository_access("Example-Org/policy", "pablo") is True
    assert github.is_team_member("accounting", "pablo") is True
    assert github.is_team_member("other", "pablo") is False
    assert github.policy_source("Example-Org/policy", "ecosystem.yml", "main") == (
        "org: Example-Org\n"
    )
    assert github._http.posts == 1


def test_github_client_returns_not_entitled_when_repository_access_is_absent(github):
    github._http.get = lambda *args, **kwargs: _Response(404, {})
    assert github.has_repository_access("Example-Org/policy", "pablo") is False


@pytest.mark.parametrize(
    ("response", "reason"),
    [
        (_Response(403, {}), "github-repository-access-unavailable"),
        (_Response(200, {"permission": "read", "user": {"login": "other"}}), "malformed"),
        (_Response(200, {"permission": "none", "user": {"login": "pablo"}}), "malformed"),
    ],
)
def test_github_client_fails_closed_when_repository_access_is_not_authoritative(
    github, response, reason
):
    github._http.get = lambda *args, **kwargs: response
    with pytest.raises(GitHubUnavailable, match=reason):
        github.has_repository_access("Example-Org/policy", "pablo")


def test_github_client_fails_closed_when_no_supported_public_key(github):
    github._http.get = lambda *args, **kwargs: _Response(200, text="ssh-rsa ignored\n")
    with pytest.raises(GitHubUnavailable):
        github.public_keys("pablo")


def test_github_client_fails_closed_on_malformed_policy(github):
    github._http.get = lambda *args, **kwargs: _Response(
        200, {"encoding": "base64", "content": "not base64!!!"}
    )
    with pytest.raises(GitHubUnavailable):
        github.policy_source("Example-Org/policy", "ecosystem.yml", "main")
