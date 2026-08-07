"""FastAPI application for GitHub-authorized Infisical OIDC assertions."""

from __future__ import annotations

import ipaddress
import logging
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import UTC, datetime
from functools import lru_cache
from typing import Literal, Protocol

from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from . import audit
from .config import Settings
from .crypto import jwk_for_key, load_rsa_private_key, oidc_assertion
from .github import GitHubClient, GitHubUnavailable
from .models import (
    AssertionRequest,
    AssertionResponse,
    ChallengeRequest,
    ChallengeResponse,
    ErrorDetail,
    ErrorResponse,
    ScopeAssertion,
)
from .policy import PolicyError, ScopePolicy, parse_policy
from .ssh_verify import canonical_challenge, verify_signature
from .state import IssueLedger, NonceStore, SlidingWindowLimiter

logging.basicConfig(level=logging.INFO, format="%(message)s")


class GitHubEvidence(Protocol):
    def public_keys(self, login: str) -> list[str]: ...
    def is_organization_member(self, login: str) -> bool: ...
    def is_team_member(self, team: str, login: str) -> bool: ...
    def policy_source(self, repository: str, path: str, ref: str) -> str: ...


@dataclass
class Services:
    settings: Settings
    signing_key: rsa.RSAPrivateKey
    github: GitHubEvidence
    nonces: NonceStore
    login_limiter: SlidingWindowLimiter
    ip_limiter: SlidingWindowLimiter
    ledger: IssueLedger


def _error(
    status: int,
    result: Literal["unavailable", "not-entitled", "rate-limited"],
    code: str,
    message: str,
) -> JSONResponse:
    report = ErrorResponse(
        result=result,
        error=ErrorDetail(code=code, message=message),
    )
    return JSONResponse(status_code=status, content=report.model_dump(mode="json"))


def _source_ip(request: Request, settings: Settings) -> str:
    peer = request.client.host if request.client else "unknown"
    try:
        peer_address = ipaddress.ip_address(peer)
    except ValueError:
        return "unknown"
    trusted = any(peer_address in network for network in settings.trusted_proxy_networks)
    if trusted:
        forwarded = request.headers.get("x-forwarded-for", "").split(",", 1)[0].strip()
        try:
            return str(ipaddress.ip_address(forwarded))
        except ValueError:
            return str(peer_address)
    return str(peer_address)


def _entitled_scopes(
    github: GitHubEvidence,
    login: str,
    rows: list[ScopePolicy],
) -> list[ScopePolicy]:
    if not github.is_organization_member(login):
        return []
    matched: list[ScopePolicy] = []
    team_answers: dict[str, bool] = {}
    for row in rows:
        if row.team == "everyone":
            matched.append(row)
            continue
        if row.team not in team_answers:
            team_answers[row.team] = github.is_team_member(row.team, login)
        if team_answers[row.team]:
            matched.append(row)
    return matched


def build_services(settings: Settings) -> Services:
    signing_key = load_rsa_private_key(settings.signing_key_file)
    github_key = load_rsa_private_key(settings.github_private_key_file)
    return Services(
        settings=settings,
        signing_key=signing_key,
        github=GitHubClient(
            organization=settings.organization,
            app_id=settings.github_app_id,
            installation_id=settings.github_installation_id,
            app_key=github_key,
        ),
        nonces=NonceStore(settings.nonce_ttl_seconds),
        login_limiter=SlidingWindowLimiter(settings.login_rate_per_minute),
        ip_limiter=SlidingWindowLimiter(settings.ip_rate_per_minute),
        ledger=IssueLedger(settings.database_path, daily_floor=settings.daily_issue_floor),
    )


def create_app(services: Services | None = None) -> FastAPI:
    if services is None:
        services = build_services(Settings.from_environment())

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        try:
            yield
        finally:
            close = getattr(services.github, "close", None)
            if callable(close):
                close()

    app = FastAPI(
        title="Control Tower access broker",
        version="1.0",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )
    app.state.services = services

    @app.get("/healthz")
    def health() -> dict[str, str]:
        return {"status": "ready"}

    @app.get("/.well-known/openid-configuration")
    def discovery() -> dict[str, object]:
        settings = services.settings
        return {
            "issuer": settings.issuer,
            "jwks_uri": f"{settings.issuer}/.well-known/jwks.json",
            "id_token_signing_alg_values_supported": ["RS256"],
        }

    @app.get("/.well-known/jwks.json")
    def jwks() -> dict[str, object]:
        return {
            "keys": [jwk_for_key(services.signing_key, key_id=services.settings.signing_key_id)]
        }

    @app.post("/v1/challenges", response_model=ChallengeResponse)
    def challenge(payload: ChallengeRequest, request: Request):
        source_ip = _source_ip(request, services.settings)
        if not services.ip_limiter.allow(source_ip) or not services.login_limiter.allow(
            payload.login.casefold()
        ):
            audit.emit(
                event="challenge",
                outcome="denied",
                source_ip=source_ip,
                login=payload.login,
                machine_id=payload.machine_id,
                reason_code="rate-limited",
            )
            return _error(
                429,
                "rate-limited",
                "try-later",
                "Access could not be checked right now. Try again later.",
            )
        nonce = services.nonces.create(payload.login, payload.machine_id)
        audit.emit(
            event="challenge",
            outcome="issued",
            source_ip=source_ip,
            login=payload.login,
            machine_id=payload.machine_id,
        )
        return ChallengeResponse(
            nonce_id=nonce.nonce_id,
            nonce=nonce.value,
            expires_at=datetime.fromtimestamp(nonce.expires_at, tz=UTC),
        )

    @app.post("/v1/assertions", response_model=AssertionResponse)
    def assertions(payload: AssertionRequest, request: Request):
        source_ip = _source_ip(request, services.settings)
        nonce = services.nonces.consume(
            payload.nonce_id,
            payload.nonce,
            payload.login,
            payload.machine_id,
        )
        if nonce is None:
            audit.emit(
                event="assertion",
                outcome="denied",
                source_ip=source_ip,
                login=payload.login,
                machine_id=payload.machine_id,
                reason_code="challenge-rejected",
            )
            return _error(
                401,
                "unavailable",
                "identity-not-confirmed",
                "This Mac's GitHub identity could not be confirmed.",
            )
        try:
            message = canonical_challenge(
                audience=services.settings.issuer,
                login=payload.login,
                machine_id=payload.machine_id,
                nonce_id=payload.nonce_id,
                nonce=payload.nonce,
            )
            keys = services.github.public_keys(payload.login)
            verified = verify_signature(
                login=payload.login,
                message=message,
                signature=payload.signature,
                public_keys=keys,
            )
            if not verified:
                raise PermissionError("ssh-signature-rejected")
            policy_source = services.github.policy_source(
                services.settings.policy_repository,
                services.settings.policy_path,
                services.settings.policy_ref,
            )
            policy_org, rows = parse_policy(
                policy_source,
                expected_issuer=services.settings.issuer,
                expected_audience=services.settings.audience,
            )
            if policy_org.casefold() != services.settings.organization.casefold():
                raise PolicyError("organization policy names a different organization")
            entitled = _entitled_scopes(services.github, payload.login, rows)
        except PermissionError:
            audit.emit(
                event="assertion",
                outcome="denied",
                source_ip=source_ip,
                login=payload.login,
                machine_id=payload.machine_id,
                reason_code="identity-not-confirmed",
            )
            return _error(
                401,
                "unavailable",
                "identity-not-confirmed",
                "This Mac's GitHub identity could not be confirmed.",
            )
        except (GitHubUnavailable, PolicyError):
            audit.emit(
                event="assertion",
                outcome="held",
                source_ip=source_ip,
                login=payload.login,
                machine_id=payload.machine_id,
                reason_code="authority-unavailable",
            )
            return _error(
                503,
                "unavailable",
                "authority-unavailable",
                "Your organization's access could not be checked right now.",
            )
        if not entitled:
            audit.emit(
                event="assertion",
                outcome="denied",
                source_ip=source_ip,
                login=payload.login,
                machine_id=payload.machine_id,
                reason_code="not-entitled",
            )
            return _error(
                403,
                "not-entitled",
                "not-entitled",
                "Your organization has not made shared access available to this account.",
            )

        allowed, threshold = services.ledger.allow_and_record(len(entitled))
        if not allowed:
            audit.emit(
                event="assertion",
                outcome="held",
                source_ip=source_ip,
                login=payload.login,
                machine_id=payload.machine_id,
                reason_code="circuit-open",
                threshold=threshold,
            )
            return _error(
                429,
                "rate-limited",
                "try-later",
                "Access could not be checked right now. Try again later.",
            )

        scope_assertions: list[ScopeAssertion] = []
        for row in entitled:
            token, expires = oidc_assertion(
                services.signing_key,
                key_id=services.settings.signing_key_id,
                issuer=services.settings.issuer,
                audience=services.settings.audience,
                organization=services.settings.organization,
                login=payload.login,
                machine_id=payload.machine_id,
                scope=row.scope,
                ttl_seconds=services.settings.assertion_ttl_seconds,
            )
            scope_assertions.append(
                ScopeAssertion(
                    scope=row.scope,
                    identity_id=row.identity_id,
                    assertion=token,
                    expires_at=datetime.fromtimestamp(expires, tz=UTC),
                )
            )
        audit.emit(
            event="assertion",
            outcome="issued",
            source_ip=source_ip,
            login=payload.login,
            machine_id=payload.machine_id,
            scopes=(row.scope for row in entitled),
            threshold=threshold,
        )
        return AssertionResponse(
            organization=services.settings.organization,
            machine_id=payload.machine_id,
            assertions=scope_assertions,
        )

    @app.exception_handler(Exception)
    async def unhandled(_request: Request, _exc: Exception) -> JSONResponse:
        # Never reflect exception text: third-party clients sometimes include
        # bearer material in exception objects.
        return _error(
            503,
            "unavailable",
            "broker-unavailable",
            "Your organization's access could not be checked right now.",
        )

    @app.exception_handler(RequestValidationError)
    async def invalid_request(_request: Request, _exc: RequestValidationError) -> JSONResponse:
        # FastAPI's default validation body includes the rejected input. The
        # assertion endpoint carries an SSH signature, so never reflect it.
        return _error(
            400,
            "unavailable",
            "invalid-request",
            "The access request was not valid.",
        )

    return app


@lru_cache(maxsize=1)
def create_production_app() -> FastAPI:
    return create_app()
