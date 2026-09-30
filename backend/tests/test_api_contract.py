from __future__ import annotations

from typing import cast

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from httpx import Response

from app.modules.identity.models import Agency
from test_agencies import (
    AgencyApiContext,
    _headers,
    _platform_admin_token,
    _seed_account,
)

pytest_plugins = ("test_agencies",)


def _assert_error(response: Response, *, status: int, code: str) -> dict[str, str]:
    assert response.status_code == status
    body = response.json()
    assert set(body) == {"detail", "code"}
    assert "error" not in body
    assert isinstance(body["detail"], str)
    assert body["code"] == code
    return body


def test_expected_api_errors_use_homogeneous_envelopes(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin_headers = _headers(_platform_admin_token(context))

    unauthorized = context.client.get("/api/v1/agencies")
    invalid = context.client.post("/api/v1/agencies", json={}, headers=admin_headers)
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-known"))
    agent_token = _seed_account(
        context,
        account_id="agency-agent",
        role="agent",
        tenant_id="agency-known",
    )
    forbidden = context.client.get(
        "/api/v1/agencies", headers=_headers(agent_token)
    )
    not_found = context.client.post(
        "/api/v1/agencies/missing/admin-invitations",
        json={"email": "staff@example.test"},
        headers=admin_headers,
    )
    context.client.post(
        "/api/v1/agencies", json={"id": "agency-duplicate"}, headers=admin_headers
    )
    conflict = context.client.post(
        "/api/v1/agencies", json={"id": "agency-duplicate"}, headers=admin_headers
    )
    context.email_sender.fail = True
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-for-mail"))
    dependency_failure = context.client.post(
        "/api/v1/agencies/agency-for-mail/admin-invitations",
        json={"email": "staff@example.test"},
        headers=admin_headers,
    )

    _assert_error(unauthorized, status=401, code="unauthorized")
    _assert_error(invalid, status=422, code="validation_error")
    _assert_error(forbidden, status=403, code="forbidden")
    _assert_error(not_found, status=404, code="not_found")
    _assert_error(conflict, status=409, code="conflict")
    _assert_error(dependency_failure, status=502, code="dependency_unavailable")


@pytest.mark.parametrize(
    ("failure", "expected_status", "expected_code"),
    [
        ("registration_conflict", 409, "conflict"),
        ("login_failure", 401, "unauthorized"),
        ("validation_failure", 422, "validation_error"),
    ],
)
def test_customer_errors_use_shared_envelope(
    agency_api_context: AgencyApiContext,
    failure: str,
    expected_status: int,
    expected_code: str,
) -> None:
    context = agency_api_context
    payload = {"email": "customer@example.test", "password": "password"}

    if failure == "registration_conflict":
        registration = context.client.post(
            "/api/v1/customer/auth/register", json=payload
        )
        assert registration.status_code == 201
        response = context.client.post("/api/v1/customer/auth/register", json=payload)
    elif failure == "login_failure":
        response = context.client.post(
            "/api/v1/customer/auth/login",
            json={"email": "unknown@example.test", "password": "password"},
        )
    else:
        response = context.client.post("/api/v1/customer/auth/register", json={})

    body = response.json()
    assert response.status_code == expected_status
    assert set(body) == {"detail", "code"}
    assert "error" not in body
    assert isinstance(body["detail"], str)
    assert body["code"] == expected_code


def test_unexpected_errors_are_generic_and_do_not_expose_exception_details(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context

    def fail_unexpectedly() -> None:
        raise RuntimeError("secret database password=do-not-expose")

    app = cast(FastAPI, context.client.app)
    app.add_api_route("/test/internal-error", fail_unexpectedly, methods=["GET"])

    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.get("/test/internal-error")

    body = _assert_error(response, status=500, code="internal_error")
    assert body == {"detail": "Internal server error", "code": "internal_error"}
    assert "do-not-expose" not in response.text


@pytest.mark.parametrize(
    ("status", "code", "safe_detail"),
    [
        (502, "dependency_unavailable", "A required dependency is unavailable"),
        (500, "internal_error", "Internal server error"),
    ],
)
def test_http_5xx_details_are_redacted(
    agency_api_context: AgencyApiContext, status: int, code: str, safe_detail: str
) -> None:
    context = agency_api_context

    def fail_with_http_exception() -> None:
        raise HTTPException(status_code=status, detail="sensitive-token")

    app = cast(FastAPI, context.client.app)
    path = f"/test/http-{status}"
    app.add_api_route(path, fail_with_http_exception, methods=["GET"])

    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.get(path)

    body = _assert_error(response, status=status, code=code)
    assert body == {"detail": safe_detail, "code": code}
    assert "sensitive-token" not in response.text


def test_openapi_documents_error_response_on_identity_and_agencies(
    agency_api_context: AgencyApiContext,
) -> None:
    openapi = agency_api_context.client.get("/openapi.json").json()
    error_schema = openapi["components"]["schemas"]["ErrorResponse"]
    assert set(error_schema["properties"]) == {"detail", "code"}
    assert set(error_schema["required"]) == {"detail", "code"}

    for path, method in (
        ("/api/v1/agencies", "get"),
        ("/api/v1/auth/login", "post"),
    ):
        responses = openapi["paths"][path][method]["responses"]
        for status in ("default", "422"):
            error = responses[status]["content"]["application/json"]["schema"]
            assert error["$ref"] == "#/components/schemas/ErrorResponse"
