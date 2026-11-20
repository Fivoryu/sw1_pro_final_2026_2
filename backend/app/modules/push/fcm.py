"""Firebase Cloud Messaging HTTP v1 client built on PyJWT and httpx (no extra dependency)."""

from __future__ import annotations

import json
import logging
import threading
import time
from typing import Literal, Protocol

import httpx
import jwt

LOGGER = logging.getLogger("roomforge.push.fcm")

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
DEFAULT_TOKEN_URI = "https://oauth2.googleapis.com/token"
SEND_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
ANDROID_CHANNEL_ID = "roomforge_default"

SendResult = Literal["sent", "unregistered", "failed"]


class PushSender(Protocol):
    def send(self, token: str, *, title: str, body: str, data: dict[str, str]) -> SendResult: ...


class FcmClient:
    """Sends one notification to one registration token with a cached OAuth access token."""

    def __init__(self, service_account: dict[str, str], *, http: httpx.Client | None = None) -> None:
        self._project_id = service_account["project_id"]
        self._client_email = service_account["client_email"]
        self._private_key = service_account["private_key"]
        self._token_uri = service_account.get("token_uri") or DEFAULT_TOKEN_URI
        self._http = http or httpx.Client(timeout=10.0)
        self._lock = threading.Lock()
        self._access_token: str | None = None
        self._expires_at = 0.0

    @classmethod
    def from_file(cls, path: str) -> FcmClient:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        if data.get("type") != "service_account":
            raise ValueError("FCM_SERVICE_ACCOUNT_FILE must be a service-account key")
        return cls(data)

    @property
    def project_id(self) -> str:
        return self._project_id

    def _token(self) -> str:
        with self._lock:
            now = time.time()
            if self._access_token is not None and now < self._expires_at - 60:
                return self._access_token
            assertion = jwt.encode(
                {
                    "iss": self._client_email,
                    "scope": FCM_SCOPE,
                    "aud": self._token_uri,
                    "iat": int(now),
                    "exp": int(now) + 3600,
                },
                self._private_key,
                algorithm="RS256",
            )
            response = self._http.post(
                self._token_uri,
                data={
                    "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                    "assertion": assertion,
                },
            )
            response.raise_for_status()
            payload = response.json()
            self._access_token = str(payload["access_token"])
            self._expires_at = now + int(payload.get("expires_in", 3600))
            return self._access_token

    @staticmethod
    def build_message(
        token: str, *, title: str, body: str, data: dict[str, str]
    ) -> dict[str, object]:
        return {
            "token": token,
            "notification": {"title": title, "body": body},
            "data": data,
            "android": {
                "priority": "HIGH",
                "notification": {"channel_id": ANDROID_CHANNEL_ID},
            },
        }

    def post(self, message: dict[str, object], *, validate_only: bool = False) -> httpx.Response:
        return self._http.post(
            SEND_URL.format(project_id=self._project_id),
            headers={"Authorization": f"Bearer {self._token()}"},
            json={"validate_only": validate_only, "message": message},
        )

    def send(self, token: str, *, title: str, body: str, data: dict[str, str]) -> SendResult:
        try:
            response = self.post(self.build_message(token, title=title, body=body, data=data))
        except (httpx.HTTPError, KeyError, ValueError) as exc:
            LOGGER.warning("FCM request failed: %s", type(exc).__name__)
            return "failed"
        if response.status_code == 200:
            return "sent"
        text = response.text
        if response.status_code == 404 or "UNREGISTERED" in text:
            return "unregistered"
        if response.status_code == 400 and "registration token" in text.lower():
            return "unregistered"
        LOGGER.warning("FCM rejected a message with status %s", response.status_code)
        return "failed"
