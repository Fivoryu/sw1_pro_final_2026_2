from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path

import pytest

from app.core.dev_email import (
    DEV_OUTBOX_DIR_ENV,
    DevOutboxEmailSender,
    create_dev_outbox_sender,
)
from app.modules.identity.notifier import EmailDeliveryUnavailable, configured_email_sender

_LINK = "http://127.0.0.1:5173/invitations/accept/secret-token-value"
_EXPIRES_AT = datetime(2026, 10, 2, 12, 0, tzinfo=timezone.utc)


def _outbox_files(outbox: Path) -> list[Path]:
    return sorted(outbox.glob("*.json"))


def test_sender_writes_the_invitation_to_the_outbox(tmp_path: Path) -> None:
    sender = DevOutboxEmailSender(outbox_dir=tmp_path)

    sender.send_invitation(
        "Admin@Example.test", _LINK, _EXPIRES_AT, timeout_seconds=10
    )

    files = _outbox_files(tmp_path)
    assert len(files) == 1
    assert json.loads(files[0].read_text(encoding="utf-8")) == {
        "email": "Admin@Example.test",
        "link": _LINK,
        "expires_at": "2026-10-02T12:00:00+00:00",
    }


def test_each_invitation_gets_its_own_outbox_file(tmp_path: Path) -> None:
    sender = DevOutboxEmailSender(outbox_dir=tmp_path)

    sender.send_invitation("a@example.test", _LINK, _EXPIRES_AT, timeout_seconds=10)
    sender.send_invitation("b@example.test", _LINK, _EXPIRES_AT, timeout_seconds=10)

    emails = {
        json.loads(path.read_text(encoding="utf-8"))["email"]
        for path in _outbox_files(tmp_path)
    }
    assert emails == {"a@example.test", "b@example.test"}


def test_sender_creates_a_missing_outbox_directory(tmp_path: Path) -> None:
    outbox = tmp_path / "nested" / "outbox"
    sender = DevOutboxEmailSender(outbox_dir=outbox)

    sender.send_invitation("a@example.test", _LINK, _EXPIRES_AT, timeout_seconds=10)

    assert len(_outbox_files(outbox)) == 1


def test_sender_never_logs_the_invitation_link(
    tmp_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    sender = DevOutboxEmailSender(outbox_dir=tmp_path)

    with caplog.at_level(logging.DEBUG):
        sender.send_invitation("a@example.test", _LINK, _EXPIRES_AT, timeout_seconds=10)

    assert "secret-token-value" not in caplog.text


def test_sender_rejects_a_non_positive_timeout(tmp_path: Path) -> None:
    sender = DevOutboxEmailSender(outbox_dir=tmp_path)

    with pytest.raises(ValueError):
        sender.send_invitation("a@example.test", _LINK, _EXPIRES_AT, timeout_seconds=0)
    assert _outbox_files(tmp_path) == []


@pytest.mark.parametrize(
    "origin",
    ["http://127.0.0.1:5173", "http://localhost:5173", "http://127.0.0.1"],
)
def test_factory_accepts_a_local_panel_origin(
    origin: str, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("STAFF_WEB_ORIGIN", origin)
    monkeypatch.setenv(DEV_OUTBOX_DIR_ENV, str(tmp_path))

    sender = create_dev_outbox_sender()

    sender.send_invitation("a@example.test", _LINK, _EXPIRES_AT, timeout_seconds=10)
    assert len(_outbox_files(tmp_path)) == 1


@pytest.mark.parametrize(
    "origin",
    [
        None,
        "",
        "https://panel.roomforge.example",
        "http://10.0.0.5:5173",
        "http://localhost.example.com:5173",
        "http://127.0.0.1.example.com",
    ],
)
def test_factory_fails_closed_outside_a_local_panel_origin(
    origin: str | None, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    if origin is None:
        monkeypatch.delenv("STAFF_WEB_ORIGIN", raising=False)
    else:
        monkeypatch.setenv("STAFF_WEB_ORIGIN", origin)
    monkeypatch.setenv(DEV_OUTBOX_DIR_ENV, str(tmp_path))

    with pytest.raises(RuntimeError):
        create_dev_outbox_sender()


def test_identity_notifier_loads_the_dev_sender_from_configuration(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("STAFF_EMAIL_SENDER_FACTORY", "app.core.dev_email:create_dev_outbox_sender")
    monkeypatch.setenv("STAFF_WEB_ORIGIN", "http://127.0.0.1:5173")
    monkeypatch.setenv(DEV_OUTBOX_DIR_ENV, str(tmp_path))

    sender = configured_email_sender()
    sender.send_invitation("a@example.test", _LINK, _EXPIRES_AT, timeout_seconds=10)

    assert len(_outbox_files(tmp_path)) == 1


def test_identity_notifier_reports_the_dev_sender_unavailable_outside_local(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("STAFF_EMAIL_SENDER_FACTORY", "app.core.dev_email:create_dev_outbox_sender")
    monkeypatch.setenv("STAFF_WEB_ORIGIN", "https://panel.roomforge.example")
    monkeypatch.setenv(DEV_OUTBOX_DIR_ENV, str(tmp_path))

    with pytest.raises(EmailDeliveryUnavailable):
        configured_email_sender()
