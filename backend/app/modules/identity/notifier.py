from __future__ import annotations

from datetime import datetime
from importlib import import_module
from os import environ
from typing import Protocol


class EmailDeliveryUnavailable(RuntimeError):
    pass


class EmailSender(Protocol):
    def send_invitation(self, email: str, link: str, expires_at: datetime) -> None: ...


class UnconfiguredEmailSender:
    def send_invitation(self, email: str, link: str, expires_at: datetime) -> None:
        del email, link, expires_at
        raise EmailDeliveryUnavailable("No approved staff email transport is configured")


def configured_email_sender() -> EmailSender:
    """Load an explicitly configured transport plugin; never selects SMTP implicitly."""
    target = environ.get("STAFF_EMAIL_SENDER_FACTORY")
    if not target:
        return UnconfiguredEmailSender()
    module_name, separator, attribute = target.partition(":")
    if not separator or not module_name or not attribute:
        raise EmailDeliveryUnavailable("STAFF_EMAIL_SENDER_FACTORY must use module:factory format")
    try:
        factory = getattr(import_module(module_name), attribute)
        sender = factory()
    except Exception as exc:
        raise EmailDeliveryUnavailable("Configured staff email transport is unavailable") from exc
    if not callable(getattr(sender, "send_invitation", None)):
        raise EmailDeliveryUnavailable("Configured staff email transport has an invalid interface")
    return sender
