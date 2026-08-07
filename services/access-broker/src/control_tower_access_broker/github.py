"""Least-privilege GitHub App client for identity and entitlement evidence."""

from __future__ import annotations

import base64
import threading
import time
from dataclasses import dataclass

import httpx
from cryptography.hazmat.primitives.asymmetric import rsa

from .crypto import github_app_jwt


class GitHubUnavailable(RuntimeError):
    """GitHub did not provide authoritative evidence."""


@dataclass(frozen=True)
class InstallationCredential:
    token: str
    expires_at: float


class GitHubClient:
    def __init__(
        self,
        *,
        organization: str,
        app_id: int,
        installation_id: int,
        app_key: rsa.RSAPrivateKey,
        timeout: float = 8.0,
        api_base: str = "https://api.github.com",
        public_keys_base: str = "https://github.com",
    ) -> None:
        self.organization = organization
        self.app_id = app_id
        self.installation_id = installation_id
        self.app_key = app_key
        self.api_base = api_base.rstrip("/")
        self.public_keys_base = public_keys_base.rstrip("/")
        self._http = httpx.Client(timeout=timeout, follow_redirects=False)
        self._credential: InstallationCredential | None = None
        self._credential_lock = threading.Lock()

    def close(self) -> None:
        self._http.close()

    def _installation_token(self) -> str:
        with self._credential_lock:
            now = time.time()
            if self._credential and self._credential.expires_at - now > 120:
                return self._credential.token
            headers = {
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {github_app_jwt(self.app_key, self.app_id)}",
                "X-GitHub-Api-Version": "2022-11-28",
            }
            try:
                response = self._http.post(
                    f"{self.api_base}/app/installations/{self.installation_id}/access_tokens",
                    headers=headers,
                )
            except httpx.HTTPError as exc:
                raise GitHubUnavailable("github-installation-token-unavailable") from exc
            if response.status_code != 201:
                raise GitHubUnavailable("github-installation-token-refused")
            try:
                payload = response.json()
                token = payload["token"]
            except (ValueError, KeyError, TypeError) as exc:
                raise GitHubUnavailable("github-installation-token-malformed") from exc
            if not isinstance(token, str) or not token:
                raise GitHubUnavailable("github-installation-token-malformed")
            # GitHub installation tokens currently live for one hour. Cache for
            # at most 50 minutes so an absent/malformed expires_at can never
            # extend authority beyond the server's own token lifetime.
            self._credential = InstallationCredential(token=token, expires_at=now + 3000)
            return token

    def _headers(self) -> dict[str, str]:
        return {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {self._installation_token()}",
            "X-GitHub-Api-Version": "2022-11-28",
        }

    def public_keys(self, login: str) -> list[str]:
        try:
            response = self._http.get(f"{self.public_keys_base}/{login}.keys")
        except httpx.HTTPError as exc:
            raise GitHubUnavailable("github-public-keys-unavailable") from exc
        if response.status_code != 200 or len(response.content) > 65_536:
            raise GitHubUnavailable("github-public-keys-unavailable")
        keys = [line.strip() for line in response.text.splitlines() if line.strip()]
        allowed_prefixes = ("ssh-ed25519 ", "sk-ssh-ed25519@openssh.com ")
        safe = [line for line in keys if line.startswith(allowed_prefixes)]
        if not safe or len(safe) > 50:
            raise GitHubUnavailable("github-public-keys-unavailable")
        return safe

    def is_organization_member(self, login: str) -> bool:
        try:
            response = self._http.get(
                f"{self.api_base}/orgs/{self.organization}/memberships/{login}",
                headers=self._headers(),
            )
        except httpx.HTTPError as exc:
            raise GitHubUnavailable("github-membership-unavailable") from exc
        if response.status_code == 404:
            return False
        if response.status_code != 200:
            raise GitHubUnavailable("github-membership-unavailable")
        try:
            payload = response.json()
        except ValueError as exc:
            raise GitHubUnavailable("github-membership-malformed") from exc
        return (
            payload.get("state") == "active"
            and payload.get("organization", {}).get("login", "").casefold()
            == self.organization.casefold()
        )

    def is_team_member(self, team: str, login: str) -> bool:
        try:
            response = self._http.get(
                f"{self.api_base}/orgs/{self.organization}/teams/{team}/memberships/{login}",
                headers=self._headers(),
            )
        except httpx.HTTPError as exc:
            raise GitHubUnavailable("github-team-membership-unavailable") from exc
        if response.status_code == 404:
            return False
        if response.status_code != 200:
            raise GitHubUnavailable("github-team-membership-unavailable")
        try:
            return response.json().get("state") == "active"
        except ValueError as exc:
            raise GitHubUnavailable("github-team-membership-malformed") from exc

    def policy_source(self, repository: str, path: str, ref: str) -> str:
        try:
            response = self._http.get(
                f"{self.api_base}/repos/{repository}/contents/{path}",
                params={"ref": ref},
                headers=self._headers(),
            )
        except httpx.HTTPError as exc:
            raise GitHubUnavailable("github-policy-unavailable") from exc
        if response.status_code != 200:
            raise GitHubUnavailable("github-policy-unavailable")
        try:
            payload = response.json()
            if payload.get("encoding") != "base64" or not isinstance(payload.get("content"), str):
                raise ValueError
            decoded = base64.b64decode(payload["content"], validate=True)
        except (ValueError, TypeError) as exc:
            raise GitHubUnavailable("github-policy-malformed") from exc
        if len(decoded) > 1_048_576:
            raise GitHubUnavailable("github-policy-too-large")
        try:
            return decoded.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise GitHubUnavailable("github-policy-malformed") from exc
