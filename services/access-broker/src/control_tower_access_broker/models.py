"""Versioned HTTP request/response models."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

_LOGIN_PATTERN = r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$"
_MACHINE_PATTERN = r"^[a-f0-9]{32}$"


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ChallengeRequest(StrictModel):
    schema_version: Literal["1.0"] = "1.0"
    login: str = Field(min_length=1, max_length=39, pattern=_LOGIN_PATTERN)
    machine_id: str = Field(pattern=_MACHINE_PATTERN)


class ChallengeResponse(StrictModel):
    schema_version: Literal["1.0"] = "1.0"
    nonce_id: str
    nonce: str
    expires_at: datetime


class AssertionRequest(StrictModel):
    schema_version: Literal["1.0"] = "1.0"
    login: str = Field(min_length=1, max_length=39, pattern=_LOGIN_PATTERN)
    machine_id: str = Field(pattern=_MACHINE_PATTERN)
    nonce_id: str = Field(min_length=20, max_length=120)
    nonce: str = Field(min_length=20, max_length=120)
    signature: str = Field(min_length=80, max_length=16_384)


class ScopeAssertion(StrictModel):
    scope: str
    identity_id: str
    assertion: str
    expires_at: datetime


class AssertionResponse(StrictModel):
    schema_version: Literal["1.0"] = "1.0"
    result: Literal["ready"] = "ready"
    organization: str
    machine_id: str
    assertions: list[ScopeAssertion]


class ErrorDetail(StrictModel):
    code: str
    message: str


class ErrorResponse(StrictModel):
    schema_version: Literal["1.0"] = "1.0"
    result: Literal["unavailable", "not-entitled", "rate-limited"]
    error: ErrorDetail
