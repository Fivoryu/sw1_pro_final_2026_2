from __future__ import annotations

from datetime import timedelta

import httpx
from sqlalchemy import select

from app.modules.notifications.models import Notification
from app.modules.notifications.service import notify
from app.modules.push.dispatcher import compose, dispatch_pending
from app.modules.push.fcm import FcmClient, SendResult
from app.modules.push.models import DeviceToken
from chat_support import AgencyApiContext, register_customer, seed_staff

CUSTOMER_DEVICES = "/api/v1/customer/devices"
STAFF_DEVICES = "/api/v1/staff/devices"
TOKEN_A = "a" * 40
TOKEN_B = "b" * 40


class RecordingSender:
    def __init__(self, results: dict[str, SendResult] | None = None) -> None:
        self.calls: list[tuple[str, str, str, dict[str, str]]] = []
        self._results = results or {}

    def send(self, token: str, *, title: str, body: str, data: dict[str, str]) -> SendResult:
        self.calls.append((token, title, body, data))
        return self._results.get(token, "sent")


def _tokens(context: AgencyApiContext) -> list[DeviceToken]:
    with context.session_factory() as session:
        return list(session.scalars(select(DeviceToken).order_by(DeviceToken.token)))


def _add_notice(context: AgencyApiContext, *, kind="chat_message", recipient_kind, recipient_id, age=None):
    with context.session_factory.begin() as session:
        notice = notify(
            session,
            recipient_kind=recipient_kind,
            recipient_id=recipient_id,
            kind=kind,
            now=context.now - (age or timedelta(0)),
            detail="accepted" if kind == "reservation_status" else None,
        )
        assert notice is not None
        return notice.id


def test_customer_registers_and_removes_a_device(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    customer_id, headers = register_customer(context)

    registered = context.client.post(
        CUSTOMER_DEVICES, json={"token": TOKEN_A, "platform": "android"}, headers=headers
    )
    assert registered.status_code == 204
    stored = _tokens(context)
    assert [(t.recipient_kind, t.recipient_id, t.token, t.platform) for t in stored] == [
        ("customer", customer_id, TOKEN_A, "android")
    ]

    removed = context.client.post(CUSTOMER_DEVICES + "/remove", json={"token": TOKEN_A}, headers=headers)
    assert removed.status_code == 204
    assert _tokens(context) == []


def test_registering_twice_keeps_one_row_and_a_new_login_takes_the_token(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    first_id, first = register_customer(context, "first@example.test")
    second_id, second = register_customer(context, "second@example.test")

    for headers in (first, first, second):
        assert (
            context.client.post(CUSTOMER_DEVICES, json={"token": TOKEN_A}, headers=headers).status_code
            == 204
        )
    stored = _tokens(context)
    assert len(stored) == 1
    assert (stored[0].recipient_id, stored[0].platform) == (second_id, "android")
    assert first_id != second_id

    # Removing a token the caller does not own changes nothing.
    context.client.post(CUSTOMER_DEVICES + "/remove", json={"token": TOKEN_A}, headers=first)
    assert len(_tokens(context)) == 1


def test_device_endpoints_validate_input_and_require_a_session(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, headers = register_customer(context)
    assert context.client.post(CUSTOMER_DEVICES, json={"token": "short"}, headers=headers).status_code == 422
    assert (
        context.client.post(
            CUSTOMER_DEVICES, json={"token": TOKEN_A, "platform": "windows"}, headers=headers
        ).status_code
        == 422
    )
    assert context.client.post(CUSTOMER_DEVICES, json={"token": TOKEN_A}).status_code == 401
    assert context.client.post(STAFF_DEVICES, json={"token": TOKEN_A}).status_code == 401


def test_staff_devices_are_limited_to_agency_staff(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    agent = seed_staff(context, "agent-push")
    platform_admin = seed_staff(context, "platform-push", role="platform_admin", agency_id=None)

    assert context.client.post(STAFF_DEVICES, json={"token": TOKEN_A}, headers=agent).status_code == 204
    assert (
        context.client.post(STAFF_DEVICES, json={"token": TOKEN_B}, headers=platform_admin).status_code
        == 403
    )
    assert [(t.recipient_kind, t.recipient_id) for t in _tokens(context)] == [("staff", "agent-push")]

    removed = context.client.post(STAFF_DEVICES + "/remove", json={"token": TOKEN_A}, headers=agent)
    assert removed.status_code == 204
    assert _tokens(context) == []


def test_a_recipient_keeps_only_the_ten_newest_tokens(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    _, headers = register_customer(context)
    for index in range(12):
        token = f"{index:02d}" + "t" * 38
        assert context.client.post(CUSTOMER_DEVICES, json={"token": token}, headers=headers).status_code == 204
    assert len(_tokens(context)) == 10


def test_dispatch_pushes_each_notice_once_to_every_device_of_the_recipient(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    customer_id, headers = register_customer(context)
    for token in (TOKEN_A, TOKEN_B):
        context.client.post(CUSTOMER_DEVICES, json={"token": token}, headers=headers)
    notice_id = _add_notice(context, recipient_kind="customer", recipient_id=customer_id)
    _add_notice(context, recipient_kind="customer", recipient_id="someone-else")

    sender = RecordingSender()
    assert dispatch_pending(context.session_factory, sender, now=context.now) == 2
    assert sorted(call[0] for call in sender.calls) == [TOKEN_A, TOKEN_B]
    _, title, body, data = sender.calls[0]
    assert (title, body) == ("Nuevo mensaje", "Tienes un mensaje nuevo en una conversación.")
    assert data == {"kind": "chat_message", "notification_id": notice_id}

    # Claimed notices are not pushed again.
    assert dispatch_pending(context.session_factory, sender, now=context.now) == 0
    assert len(sender.calls) == 2
    with context.session_factory() as session:
        assert all(n.pushed_at is not None for n in session.scalars(select(Notification)))


def test_dispatch_removes_unregistered_tokens_and_skips_read_and_stale_notices(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    customer_id, headers = register_customer(context)
    for token in (TOKEN_A, TOKEN_B):
        context.client.post(CUSTOMER_DEVICES, json={"token": token}, headers=headers)
    _add_notice(context, recipient_kind="customer", recipient_id=customer_id, age=timedelta(days=3))
    read_id = _add_notice(context, recipient_kind="customer", recipient_id=customer_id)
    with context.session_factory.begin() as session:
        session.get(Notification, read_id).read_at = context.now  # type: ignore[union-attr]
    live_id = _add_notice(
        context, kind="reservation_status", recipient_kind="customer", recipient_id=customer_id
    )

    sender = RecordingSender({TOKEN_A: "unregistered"})
    assert dispatch_pending(context.session_factory, sender, now=context.now) == 2
    assert {call[0] for call in sender.calls} == {TOKEN_A, TOKEN_B}
    assert all(call[3]["notification_id"] == live_id for call in sender.calls)
    assert sender.calls[0][1:3] == ("Reserva actualizada", "Tu reserva fue aceptada.")
    assert [t.token for t in _tokens(context)] == [TOKEN_B]


def test_compose_uses_generic_copy_for_every_kind() -> None:
    def notice(kind: str, recipient_kind: str = "customer", detail: str | None = None) -> Notification:
        return Notification(kind=kind, recipient_kind=recipient_kind, recipient_id="x", detail=detail)

    assert compose(notice("chat_assigned", "staff"))[0] == "Conversación asignada"
    assert compose(notice("chat_needs_admin", "staff"))[0] == "Conversación sin agente"
    assert compose(notice("chat_overdue", "staff"))[0] == "Conversación pendiente"
    assert compose(notice("reservation_status", "staff", "rejected")) == (
        "Reserva actualizada",
        "Una reserva fue rechazada.",
    )
    assert compose(notice("reservation_status", "customer", "weird"))[1] == (
        "El estado de una reserva cambió."
    )


def _fcm(handler) -> FcmClient:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode("ascii")
    account = {
        "type": "service_account",
        "project_id": "demo-project",
        "client_email": "push@demo-project.iam.gserviceaccount.com",
        "private_key": pem,
        "token_uri": "https://oauth.test/token",
    }
    return FcmClient(account, http=httpx.Client(transport=httpx.MockTransport(handler)))


def test_fcm_client_authenticates_once_and_maps_results() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.host == "oauth.test":
            return httpx.Response(200, json={"access_token": "tok", "expires_in": 3600})
        assert request.headers["Authorization"] == "Bearer tok"
        token = request.read().decode()
        if "dead-token" in token:
            return httpx.Response(404, json={"error": {"details": [{"errorCode": "UNREGISTERED"}]}})
        if "bad-token" in token:
            return httpx.Response(
                400, json={"error": {"message": "The registration token is not a valid FCM registration token"}}
            )
        if "boom-token" in token:
            return httpx.Response(500, text="oops")
        return httpx.Response(200, json={"name": "projects/demo-project/messages/1"})

    client = _fcm(handler)
    data = {"kind": "chat_message"}
    assert client.send("good-token", title="t", body="b", data=data) == "sent"
    assert client.send("dead-token", title="t", body="b", data=data) == "unregistered"
    assert client.send("bad-token", title="t", body="b", data=data) == "unregistered"
    assert client.send("boom-token", title="t", body="b", data=data) == "failed"
    # One OAuth exchange serves every send.
    assert sum(1 for r in seen if r.url.host == "oauth.test") == 1
    sent = [r for r in seen if r.url.host == "fcm.googleapis.com"][0]
    assert str(sent.url) == "https://fcm.googleapis.com/v1/projects/demo-project/messages:send"


def test_fcm_client_reports_failed_when_the_network_breaks() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("down")

    assert _fcm(handler).send("x" * 30, title="t", body="b", data={}) == "failed"
