from __future__ import annotations

from datetime import datetime, timezone
from inspect import Parameter, signature

import pytest

from app.modules.identity.notifier import (
    EmailDeliveryUnavailable,
    EmailSender,
    UnconfiguredEmailSender,
)


def test_email_sender_protocol_exposes_provider_native_timeout() -> None:
    parameters = signature(EmailSender.send_invitation).parameters

    assert "timeout_seconds" in parameters
    assert parameters["timeout_seconds"].kind is Parameter.KEYWORD_ONLY


def test_unconfigured_email_sender_accepts_the_native_timeout_contract() -> None:
    sender = UnconfiguredEmailSender()

    with pytest.raises(EmailDeliveryUnavailable, match="No approved staff email transport"):
        sender.send_invitation(
            "staff@example.test",
            "https://panel.example.test/invitations/accept/token",
            datetime.now(timezone.utc),
            timeout_seconds=10,
        )
