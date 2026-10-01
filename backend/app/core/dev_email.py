"""Local-development staff email transport that writes invitations to an outbox directory.

Load it only through ``STAFF_EMAIL_SENDER_FACTORY=app.core.dev_email:create_dev_outbox_sender``.
Invitation links carry one-time tokens, so they are written to private files instead of logs,
and the factory refuses to run unless the trusted panel origin is a loopback address.
"""

from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit
from uuid import uuid4

DEV_OUTBOX_DIR_ENV = "ROOMFORGE_DEV_OUTBOX_DIR"
_DEFAULT_OUTBOX_DIR = "/tmp/roomforge-dev-outbox"
_LOCAL_HOSTS = frozenset({"127.0.0.1", "localhost"})


class DevOutboxEmailSender:
    def __init__(self, *, outbox_dir: Path) -> None:
        self._outbox_dir = outbox_dir

    def send_invitation(
        self,
        email: str,
        link: str,
        expires_at: datetime,
        *,
        timeout_seconds: int,
    ) -> None:
        if timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        self._outbox_dir.mkdir(parents=True, exist_ok=True)
        message = {"email": email, "link": link, "expires_at": expires_at.isoformat()}
        path = self._outbox_dir / f"{datetime.now().strftime('%Y%m%dT%H%M%S')}-{uuid4().hex}.json"
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as outbox_file:
            json.dump(message, outbox_file)


def create_dev_outbox_sender() -> DevOutboxEmailSender:
    origin = urlsplit(os.environ.get("STAFF_WEB_ORIGIN", ""))
    if origin.scheme not in {"http", "https"} or origin.hostname not in _LOCAL_HOSTS:
        raise RuntimeError("The development outbox requires a loopback STAFF_WEB_ORIGIN")
    return DevOutboxEmailSender(
        outbox_dir=Path(os.environ.get(DEV_OUTBOX_DIR_ENV, _DEFAULT_OUTBOX_DIR))
    )
