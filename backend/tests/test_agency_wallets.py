from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import pytest
from eth_account import Account
from eth_account.messages import encode_defunct
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.security import create_access_token
from app.db.base import Base
from app.main import create_app
from app.modules.identity.models import Agency, StaffAccount, StaffSession


@dataclass
class AgencyWalletContext:
    client: TestClient
    session_factory: sessionmaker[Session]
    settings: Settings
    now: datetime


_PRIVATE_KEY = "0x" + "11" * 32
_WALLET = Account.from_key(_PRIVATE_KEY).address.lower()
_OTHER_PRIVATE_KEY = "0x" + "22" * 32
_OTHER_WALLET = Account.from_key(_OTHER_PRIVATE_KEY).address.lower()


@pytest.fixture

def agency_wallet_context() -> Any:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    now = datetime.now(timezone.utc)
    settings = Settings(
        database_url="sqlite+pysqlite:///:memory:",
        jwt_secret="agency-wallet-test-secret-at-least-32-bytes",
        totp_encryption_key=base64.urlsafe_b64encode(b"w" * 32).decode("ascii"),
        web_origin="https://panel.example.test",
    )
    app = create_app(
        settings=settings,
        session_factory=session_factory,
        clock=lambda: context.now,
    )
    context = AgencyWalletContext(client=None, session_factory=session_factory, settings=settings, now=now)  # type: ignore[arg-type]
    with TestClient(app, base_url="https://testserver") as client:
        context.client = client
        yield context
    engine.dispose()


def _staff_token(
    context: AgencyWalletContext,
    *,
    account_id: str,
    role: str = "agency_admin",
    tenant_id: str | None = "agency-one",
) -> str:
    session_id = f"session-{account_id}"
    with context.session_factory.begin() as session:
        if tenant_id is not None and session.get(Agency, tenant_id) is None:
            session.add(Agency(id=tenant_id))
            session.flush()
        session.add(
            StaffAccount(
                id=account_id,
                email=f"{account_id}@example.test",
                password_hash="test-password-hash",
                role=role,
                tenant_id=tenant_id,
                active=True,
                totp_secret_encrypted="encrypted-test-secret",
                totp_enabled=True,
                created_at=context.now,
            )
        )
        session.add(
            StaffSession(
                id=session_id,
                user_id=account_id,
                refresh_hash=f"refresh-{account_id}",
                csrf_hash=f"csrf-{account_id}",
                created_at=context.now,
                last_activity_at=context.now,
                expires_at=context.now + timedelta(hours=1),
                revoked_at=None,
            )
        )
    return create_access_token(
        user_id=account_id,
        session_id=session_id,
        signing_key=context.settings.jwt_secret,
        now=context.now,
        lifetime_minutes=context.settings.access_token_minutes,
    )


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _issue_challenge(
    context: AgencyWalletContext,
    token: str,
    *,
    agency_id: str = "agency-one",
    address: str = _WALLET,
) -> dict[str, Any]:
    response = context.client.post(
        f"/api/v1/staff/agencies/{agency_id}/wallet-challenges",
        json={"address": address},
        headers=_headers(token),
    )
    assert response.status_code == 201, response.text
    return response.json()


def _signature(message: str, private_key: str = _PRIVATE_KEY) -> str:
    return Account.sign_message(encode_defunct(text=message), private_key=private_key).signature.hex()


def _link_wallet(
    context: AgencyWalletContext,
    token: str,
    challenge: dict[str, Any],
    *,
    signature: str | None = None,
    agency_id: str = "agency-one",
) -> Any:
    proof = signature or _signature(challenge["message"])
    return context.client.put(
        f"/api/v1/staff/agencies/{agency_id}/wallet",
        json={"challenge_id": challenge["challenge_id"], "signature": proof},
        headers=_headers(token),
    )


def test_agency_admin_can_link_wallet_after_proving_ownership(
    agency_wallet_context: AgencyWalletContext,
) -> None:
    context = agency_wallet_context
    token = _staff_token(context, account_id="agency-admin")
    challenge = _issue_challenge(context, token)

    response = _link_wallet(context, token, challenge)

    assert response.status_code == 201, response.text
    assert response.json()["address"] == _WALLET
    assert response.json()["agency_id"] == "agency-one"


def test_agent_and_platform_admin_cannot_link_an_agency_wallet(
    agency_wallet_context: AgencyWalletContext,
) -> None:
    context = agency_wallet_context
    agent = _staff_token(context, account_id="agent", role="agent")
    platform_admin = _staff_token(
        context, account_id="platform-admin", role="platform_admin", tenant_id=None
    )

    responses = [
        context.client.post(
            "/api/v1/staff/agencies/agency-one/wallet-challenges",
            json={"address": _WALLET},
            headers=_headers(token),
        )
        for token in (agent, platform_admin)
    ]

    assert [response.status_code for response in responses] == [403, 403]


def test_agency_admin_cannot_act_for_another_tenant(
    agency_wallet_context: AgencyWalletContext,
) -> None:
    context = agency_wallet_context
    token = _staff_token(context, account_id="agency-one-admin")

    response = context.client.post(
        "/api/v1/staff/agencies/agency-two/wallet-challenges",
        json={"address": _WALLET},
        headers=_headers(token),
    )

    assert response.status_code == 403


def test_invalid_expired_and_replayed_wallet_challenges_fail_generically(
    agency_wallet_context: AgencyWalletContext,
) -> None:
    context = agency_wallet_context
    token = _staff_token(context, account_id="agency-admin")
    invalid_signature_challenge = _issue_challenge(context, token)

    invalid = _link_wallet(
        context,
        token,
        invalid_signature_challenge,
        signature="not-a-valid-signature",
    )
    replay = _link_wallet(context, token, invalid_signature_challenge)
    expired_challenge = _issue_challenge(context, token, address=_OTHER_WALLET)
    context.now += timedelta(minutes=5)
    expired = _link_wallet(
        context,
        token,
        expired_challenge,
        signature=_signature(expired_challenge["message"], _OTHER_PRIVATE_KEY),
    )

    assert [invalid.status_code, replay.status_code, expired.status_code] == [401, 401, 401]
    assert invalid.json() == replay.json() == expired.json()


def test_challenge_is_consumed_before_signature_recovery(
    agency_wallet_context: AgencyWalletContext,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = agency_wallet_context
    token = _staff_token(context, account_id="agency-admin")
    challenge = _issue_challenge(context, token)
    from app.modules.agencies.models import AgencyWalletChallenge

    real_recover = Account.recover_message
    observed_consumed: list[bool] = []

    def recover_after_consumption(*args: Any, **kwargs: Any) -> str:
        with context.session_factory() as session:
            row = session.get(AgencyWalletChallenge, challenge["challenge_id"])
            observed_consumed.append(row is not None and row.consumed_at is not None)
        return real_recover(*args, **kwargs)

    monkeypatch.setattr(Account, "recover_message", staticmethod(recover_after_consumption))
    response = _link_wallet(context, token, challenge)

    assert response.status_code == 201, response.text
    assert observed_consumed == [True]


def test_agency_wallet_is_immutable_and_address_is_globally_unique(
    agency_wallet_context: AgencyWalletContext,
) -> None:
    context = agency_wallet_context
    first_admin = _staff_token(context, account_id="agency-one-admin")
    second_admin = _staff_token(
        context, account_id="agency-two-admin", tenant_id="agency-two"
    )
    first = _issue_challenge(context, first_admin)
    prepared_replacement = _issue_challenge(
        context, first_admin, address=_OTHER_WALLET
    )

    assert _link_wallet(context, first_admin, first).status_code == 201
    cannot_replace = _link_wallet(
        context,
        first_admin,
        prepared_replacement,
        signature=_signature(prepared_replacement["message"], _OTHER_PRIVATE_KEY),
    )
    second_agency_challenge = _issue_challenge(
        context, second_admin, agency_id="agency-two"
    )
    globally_duplicate = _link_wallet(
        context, second_admin, second_agency_challenge, agency_id="agency-two"
    )

    assert cannot_replace.status_code == 409
    assert globally_duplicate.status_code == 409
    assert "address" not in globally_duplicate.text.lower()


def test_agency_write_methods_are_allowed_by_cors_without_allowing_other_writes(
    agency_wallet_context: AgencyWalletContext,
) -> None:
    context = agency_wallet_context
    headers = {
        "Origin": context.settings.web_origin,
        "Access-Control-Request-Method": "PATCH",
    }

    allowed = context.client.options(
        "/api/v1/staff/agencies/agency-one/listings/listing-one/deposit",
        headers=headers,
    )
    disallowed = context.client.options(
        "/api/v1/staff/agencies/agency-one/listings/listing-one/deposit",
        headers={**headers, "Access-Control-Request-Method": "DELETE"},
    )

    assert allowed.status_code == 200
    assert allowed.headers["access-control-allow-origin"] == context.settings.web_origin
    assert "PATCH" in allowed.headers["access-control-allow-methods"]
    assert disallowed.status_code == 400
