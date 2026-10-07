"""Object storage for listing photos.

Clients upload and download photo bytes directly with short-lived signed links;
the API only signs links and, when a photo is confirmed, reads it back to
validate it and rewrite it without metadata. Bytes never reach PostgreSQL.
"""

from __future__ import annotations

from typing import Any, Protocol
from urllib.parse import quote

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.core.config import Settings


class PhotoStorageUnavailableError(Exception):
    """The object storage could not be reached or rejected the request."""


class PhotoTooLargeError(Exception):
    """A stored object is larger than the caller accepts."""


class PhotoStorage(Protocol):
    def presign_upload(self, key: str, *, content_type: str, expires_in: int) -> str: ...

    def presign_download(self, key: str, *, expires_in: int) -> str: ...

    def read(self, key: str, *, max_bytes: int) -> bytes | None: ...

    def write(self, key: str, data: bytes, *, content_type: str) -> None: ...

    def delete(self, key: str) -> None: ...


class S3PhotoStorage:
    """S3 (or Floci locally) behind two clients.

    The internal client talks to the storage from the API's network; the signer
    produces links for the address clients use, because a SigV4 signature covers
    the host it was computed for.
    """

    def __init__(
        self,
        *,
        bucket: str,
        endpoint_url: str | None,
        public_endpoint_url: str | None,
        region: str,
        access_key_id: str | None = None,
        secret_access_key: str | None = None,
        timeout_seconds: int = 10,
    ) -> None:
        self._bucket = bucket
        config = Config(
            signature_version="s3v4",
            s3={"addressing_style": "path"},
            connect_timeout=timeout_seconds,
            read_timeout=timeout_seconds,
            retries={"max_attempts": 2},
        )
        credentials: dict[str, Any] = {}
        if access_key_id and secret_access_key:
            credentials = {
                "aws_access_key_id": access_key_id,
                "aws_secret_access_key": secret_access_key,
            }
        self._client: Any = boto3.client(
            "s3", endpoint_url=endpoint_url, region_name=region, config=config, **credentials
        )
        self._signer: Any = boto3.client(
            "s3",
            endpoint_url=public_endpoint_url or endpoint_url,
            region_name=region,
            config=config,
            **credentials,
        )

    def presign_upload(self, key: str, *, content_type: str, expires_in: int) -> str:
        return self._signer.generate_presigned_url(
            "put_object",
            Params={"Bucket": self._bucket, "Key": key, "ContentType": content_type},
            ExpiresIn=expires_in,
        )

    def presign_download(self, key: str, *, expires_in: int) -> str:
        return self._signer.generate_presigned_url(
            "get_object", Params={"Bucket": self._bucket, "Key": key}, ExpiresIn=expires_in
        )

    def read(self, key: str, *, max_bytes: int) -> bytes | None:
        try:
            head = self._client.head_object(Bucket=self._bucket, Key=key)
            if int(head["ContentLength"]) > max_bytes:
                raise PhotoTooLargeError
            body = self._client.get_object(Bucket=self._bucket, Key=key)["Body"]
            data: bytes = body.read(max_bytes + 1)
        except ClientError as error:
            if _is_missing(error):
                return None
            raise PhotoStorageUnavailableError from None
        except BotoCoreError:
            raise PhotoStorageUnavailableError from None
        if len(data) > max_bytes:
            raise PhotoTooLargeError
        return data

    def write(self, key: str, data: bytes, *, content_type: str) -> None:
        try:
            self._client.put_object(
                Bucket=self._bucket, Key=key, Body=data, ContentType=content_type
            )
        except (BotoCoreError, ClientError):
            raise PhotoStorageUnavailableError from None

    def delete(self, key: str) -> None:
        try:
            self._client.delete_object(Bucket=self._bucket, Key=key)
        except (BotoCoreError, ClientError):
            raise PhotoStorageUnavailableError from None


def _is_missing(error: ClientError) -> bool:
    code = str(error.response.get("Error", {}).get("Code", ""))
    return code in {"404", "NoSuchKey", "NotFound"}


class InMemoryPhotoStorage:
    """Storage double for tests: objects live in a dict and links are inert."""

    def __init__(self, base_url: str = "https://storage.example.test/photos") -> None:
        self.base_url = base_url
        self.objects: dict[str, bytes] = {}
        self.content_types: dict[str, str] = {}

    def presign_upload(self, key: str, *, content_type: str, expires_in: int) -> str:
        return f"{self.base_url}/{quote(key)}?upload={expires_in}&type={quote(content_type)}"

    def presign_download(self, key: str, *, expires_in: int) -> str:
        return f"{self.base_url}/{quote(key)}?download={expires_in}"

    def read(self, key: str, *, max_bytes: int) -> bytes | None:
        data = self.objects.get(key)
        if data is not None and len(data) > max_bytes:
            raise PhotoTooLargeError
        return data

    def write(self, key: str, data: bytes, *, content_type: str) -> None:
        self.objects[key] = data
        self.content_types[key] = content_type

    def delete(self, key: str) -> None:
        self.objects.pop(key, None)
        self.content_types.pop(key, None)


def create_photo_storage(settings: Settings) -> PhotoStorage | None:
    """Build the configured storage, or None when photos are not configured."""
    if not settings.s3_bucket_name:
        return None
    public = settings.s3_public_endpoint_url
    return S3PhotoStorage(
        bucket=settings.s3_bucket_name,
        endpoint_url=settings.s3_endpoint_url,
        public_endpoint_url=public.rstrip("/") if public else None,
        region=settings.s3_region,
    )
