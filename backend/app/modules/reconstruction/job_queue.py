"""The reconstruction job queue, behind an interface (F07.7).

Same approach as the detection queue: the API publishes through this contract and
never talks to SQS directly. The message is just a version, the job id and the
attempt number; the worker claims the job to learn everything else.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from typing import Any, Protocol

from app.modules.detection.job_queue import (
    LOCAL_AWS_ACCESS_KEY_ID,
    LOCAL_AWS_SECRET_ACCESS_KEY,
    JobQueueUnavailableError,
    validate_local_endpoint,
)

MESSAGE_VERSION = 1


@dataclass(frozen=True)
class ReconstructionMessage:
    version: int
    job_id: str
    attempt: int

    def as_body(self) -> str:
        return json.dumps(asdict(self), separators=(",", ":"), sort_keys=True)

    @classmethod
    def from_body(cls, body: str) -> ReconstructionMessage:
        payload = json.loads(body)
        return cls(
            version=int(payload["version"]),
            job_id=str(payload["job_id"]),
            attempt=int(payload["attempt"]),
        )


class ReconstructionQueue(Protocol):
    def publish(self, message: ReconstructionMessage) -> None: ...


class InMemoryReconstructionQueue:
    """Test double; ``fail_on_publish`` proves the persist/publish window."""

    def __init__(self, *, fail_on_publish: bool = False) -> None:
        self.published: list[ReconstructionMessage] = []
        self.fail_on_publish = fail_on_publish

    def publish(self, message: ReconstructionMessage) -> None:
        if self.fail_on_publish:
            raise JobQueueUnavailableError("the reconstruction queue rejected the message")
        self.published.append(message)


class SqsReconstructionQueue:
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

            resource: Any = boto3.resource(
                "sqs",
                endpoint_url=endpoint_url,
                region_name=self._region,
                aws_access_key_id=LOCAL_AWS_ACCESS_KEY_ID,
                aws_secret_access_key=LOCAL_AWS_SECRET_ACCESS_KEY,
            )
            self._queue = resource.get_queue_by_name(QueueName=self._queue_name)
        return self._queue

    def publish(self, message: ReconstructionMessage) -> None:
        try:
            self._resolve().send_message(MessageBody=message.as_body())
        except Exception as error:  # boundary: any client error means "not published"
            raise JobQueueUnavailableError(
                f"could not publish the reconstruction job: {error}"
            ) from error


def create_reconstruction_queue(settings: Any) -> SqsReconstructionQueue:
    return SqsReconstructionQueue(
        queue_name=settings.reconstruction_queue_name,
        endpoint_url=settings.sqs_endpoint_url,
        region=settings.s3_region,
    )
