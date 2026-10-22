"""Helpers for TestClient typing under the httpx2-era Starlette testclient.

Starlette types ``TestClient.app`` as an internal ASGI wrapper once the
httpx2 backend is in use, so reaching the real FastAPI application
(app.state, dependency_overrides, openapi) needs one documented cast.
"""

from __future__ import annotations

from typing import cast

from fastapi import FastAPI
from fastapi.testclient import TestClient


def client_app(client: TestClient) -> FastAPI:
    """Return the FastAPI application served by the given TestClient."""
    return cast(FastAPI, client.app)
