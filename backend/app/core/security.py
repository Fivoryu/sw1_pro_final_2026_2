from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import time
from datetime import datetime, timezone
from urllib.parse import quote

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError, VerificationError
from cryptography.fernet import Fernet, InvalidToken

_password_hasher = PasswordHasher()


def hash_password(password: str) -> str:
    return _password_hasher.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    try:
        return _password_hasher.verify(password_hash, password)
    except (InvalidHashError, VerifyMismatchError, VerificationError):
        return False


def hash_secret(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def encrypt_totp_secret(secret: str, encryption_key: str) -> str:
    return Fernet(encryption_key.encode("ascii")).encrypt(secret.encode("ascii")).decode("ascii")


def decrypt_totp_secret(encrypted: str, encryption_key: str) -> str:
    try:
        return Fernet(encryption_key.encode("ascii")).decrypt(encrypted.encode("ascii")).decode("ascii")
    except (InvalidToken, ValueError, UnicodeDecodeError) as exc:
        raise ValueError("Stored TOTP secret cannot be decrypted") from exc


def new_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def totp_code(secret: str, at: datetime, *, step_seconds: int = 30) -> str:
    timestamp = at.astimezone(timezone.utc).timestamp()
    counter = int(timestamp // step_seconds)
    padded = secret + "=" * ((8 - len(secret) % 8) % 8)
    key = base64.b32decode(padded, casefold=True)
    digest = hmac.new(key, counter.to_bytes(8, "big"), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    binary = int.from_bytes(digest[offset : offset + 4], "big") & 0x7FFFFFFF
    return f"{binary % 1_000_000:06d}"


def verify_totp(secret: str, supplied: str, at: datetime, *, window: int = 1) -> bool:
    if len(supplied) != 6 or not supplied.isdigit():
        return False
    now = at.astimezone(timezone.utc)
    for offset in range(-window, window + 1):
        candidate = totp_code(secret, datetime.fromtimestamp(now.timestamp() + offset * 30, timezone.utc))
        if hmac.compare_digest(candidate, supplied):
            return True
    return False


def new_recovery_codes(count: int) -> list[str]:
    return [secrets.token_urlsafe(9) for _ in range(count)]


def make_totp_uri(secret: str, email: str) -> str:
    label = quote(f"RoomForge:{email}", safe=":")
    issuer = quote("RoomForge", safe="")
    return f"otpauth://totp/{label}?secret={secret}&issuer={issuer}&digits=6&period=30"


def create_access_token(
    *, user_id: str, session_id: str, signing_key: str, now: datetime, lifetime_minutes: int
) -> str:
    issued_at = int(now.astimezone(timezone.utc).timestamp())
    payload = {
        "sub": user_id,
        "sid": session_id,
        "iat": issued_at,
        "exp": issued_at + lifetime_minutes * 60,
        "jti": secrets.token_urlsafe(12),
    }
    return jwt.encode(payload, signing_key, algorithm="HS256")


def decode_access_token(token: str, signing_key: str) -> dict[str, object]:
    return jwt.decode(
        token,
        signing_key,
        algorithms=["HS256"],
        options={"require": ["sub", "sid", "iat", "exp", "jti"]},
    )


def random_token() -> str:
    return secrets.token_urlsafe(32)


def unix_time(at: datetime) -> int:
    return int(time.mktime(at.astimezone().timetuple()))
