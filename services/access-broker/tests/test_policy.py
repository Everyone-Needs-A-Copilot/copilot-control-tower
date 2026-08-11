from __future__ import annotations

import pytest

from control_tower_access_broker.policy import PolicyError, parse_policy


def test_policy_accepts_only_explicit_read_scopes(policy):
    org, rows = parse_policy(
        policy,
        expected_issuer="https://access.example.test",
        expected_audience="https://secrets.example.test",
    )
    assert org == "Example-Org"
    assert [(row.team, row.scope, row.secret_path) for row in rows] == [
        ("everyone", "shared", "/shared"),
        ("accounting", "accounting", "/departments/accounting"),
    ]


@pytest.mark.parametrize(
    "before,after",
    [
        ("access: read", "access: write"),
        ("secret_path: /shared", "secret_path: /**"),
        ("scope: shared", "scope: '*'"),
        ("broker_audience: https://secrets.example.test", "broker_audience: https://other.test"),
    ],
)
def test_policy_fails_closed_on_widening_or_trust_drift(policy, before, after):
    with pytest.raises(PolicyError):
        parse_policy(
            policy.replace(before, after),
            expected_issuer="https://access.example.test",
            expected_audience="https://secrets.example.test",
        )


def test_policy_rejects_unknown_fields(policy):
    with pytest.raises(PolicyError):
        parse_policy(
            policy.replace("access: read", "access: read\n      surprise: true", 1),
            expected_issuer="https://access.example.test",
            expected_audience="https://secrets.example.test",
        )
