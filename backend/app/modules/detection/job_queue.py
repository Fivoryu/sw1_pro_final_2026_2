"""The detection job queue, behind an interface (F08.4).

The API never talks to SQS directly: it publishes through this contract, so the
whole suite runs without AWS and a publish failure is provable on demand.

The message carries everything the worker needs, so the worker never has to read
the catalog.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import asdict, dataclass
from typing import Any, Protocol
from urllib.parse import urlparse

MESSAGE_VERSION = 1
LOCAL_QUEUE_HOSTS = frozenset({"floci", "localhost", "127.0.0.1", "::1"})
LOCAL_AWS_ACCESS_KEY_ID = "local-test-key"
LOCAL_AWS_SECRET_ACCESS_KEY = "local-test-secret"


def validate_local_endpoint(endpoint_url: str | None) -> str:
    """Reject missing and non-local SQS endpoints before constructing an AWS client."""
    if not endpoint_url:
        raise ValueError("SQS_ENDPOINT_URL must point to a local Floci endpoint")
    try:
        parsed = urlparse(endpoint_url)
        host = parsed.hostname
    except ValueError:
        parsed = urlparse("")
        host = None
    if (
        parsed.scheme not in {"http", "https"}
        or host not in LOCAL_QUEUE_HOSTS
        or parsed.username is not None
        or parsed.password is not None
    ):
        raise ValueError("SQS_ENDPOINT_URL must point to a local Floci endpoint")
    return endpoint_url.rstrip("/")


class JobQueueUnavailableError(RuntimeError):
    """The queue could not accept a message."""


@dataclass(frozen=True)
class JobMessage:
    """Exactly what travels on the queue for one detection job."""

    version: int
    job_id: str
    photo_id: str
    object_key: str
    model_id: str
    attempt: int

    def as_body(self) -> str:
        return json.dumps(asdict(self), separators=(",", ":"), sort_keys=True)

    @classmethod
    def from_body(cls, body: str) -> JobMessage:
        payload: Mapping[str, Any] = json.loads(body)
        return cls(
            version=int(payload["version"]),
            job_id=str(payload["job_id"]),
            photo_id=str(payload["photo_id"]),
            object_key=str(payload["object_key"]),
            model_id=str(payload["model_id"]),
            attempt=int(payload["attempt"]),
        )


class JobQueue(Protocol):
    def publish(self, message: JobMessage) -> None: ...


class InMemoryJobQueue:
    """Test double. ``fail_on_publish`` exists to prove the persist/publish window."""

    def __init__(self, *, fail_on_publish: bool = False) -> None:
        self.published: list[JobMessage] = []
        self.fail_on_publish = fail_on_publish

    def publish(self, message: JobMessage) -> None:
        if self.fail_on_publish:
            raise JobQueueUnavailableError("la cola de detección rechazó el mensaje")
        self.published.append(message)


class SqsJobQueue:
    """SQS publisher. boto3 is imported lazily so the API starts without it."""

    def __init__(self, *, queue_name: str, endpoint_url: str | None, region: str) -> None:
        self._queue_name = queue_name
        self._endpoint_url = endpoint_url
        self._region = region
        self._queue: Any = None

    def _resolve(self) -> Any:
        if self._queue is None:
            endpoint_url = validate_local_endpoint(self._endpoint_url)
            import boto3

            # boto3 ships no type stubs here, so the resource is typed explicitly.
            resource: Any = boto3.resource(
                "sqs",
                endpoint_url=endpoint_url,
                region_name=self._region,
                aws_access_key_id=LOCAL_AWS_ACCESS_KEY_ID,
                aws_secret_access_key=LOCAL_AWS_SECRET_ACCESS_KEY,
            )
            self._queue = resource.get_queue_by_name(QueueName=self._queue_name)
        return self._queue

    def publish(self, message: JobMessage) -> None:
        try:
            self._resolve().send_message(MessageBody=message.as_body())
        except Exception as error:  # boundary: any client error means "not published"
            raise JobQueueUnavailableError(
                f"no se pudo publicar el trabajo en la cola: {error}"
            ) from error


def create_job_queue(settings: Any) -> SqsJobQueue:
    return SqsJobQueue(
        queue_name=settings.detection_queue_name,
        endpoint_url=settings.sqs_endpoint_url,
        region=settings.s3_region,
    )
