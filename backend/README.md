# RoomForge Backend

Fresh FastAPI slice for staff identity and authentication. The initial scope is limited to the roles `platform_admin`, `agency_admin`, and `agent`; agency/member CRUD, public staff signup, customer/mobile flows, and listing features are not included.

## Configuration

The application reads process environment variables only; it does not load `.env` files.

- `DATABASE_URL`: SQLAlchemy PostgreSQL URL using psycopg.
- `JWT_SECRET`: at least 32 bytes, used to sign short-lived access JWTs.
- `STAFF_TOTP_ENCRYPTION_KEY`: Fernet-compatible key used to encrypt TOTP seeds at rest.
- `STAFF_WEB_ORIGIN`: exact trusted panel origin used for CORS and cookie-authenticated request checks.
- `STAFF_SECURE_COOKIES`: defaults to `true`; disable only for isolated local HTTP development.
- `STAFF_EMAIL_SENDER_FACTORY`: optional `module:factory` plugin implementing `send_invitation(email, link, expires_at, *, timeout_seconds)`. The required keyword-only timeout must be enforced by the provider's native transport; the application does not wrap synchronous sends in a thread or `Future`. There is no default SMTP implementation or paid email integration. Without an approved existing transport, live invitation delivery remains unavailable.

Do not place credentials in source control or return/log authentication material. The TOTP seed is returned only to the invitee during enrollment; recovery codes are returned once after successful enrollment. Refresh credentials are only placed in an `HttpOnly`, `Secure` (unless explicitly disabled), `SameSite=Strict` cookie. The CSRF value is returned separately and must accompany refresh/logout requests. `login/totp`, `refresh` and `logout` reject any present `Origin` other than `STAFF_WEB_ORIGIN` (including `null`); requests without an `Origin` header come from native clients such as the capture app, which still need the TOTP proof to log in and the refresh cookie plus the CSRF token to refresh or log out.

## Initial platform administrator

There is no public bootstrap or staff registration endpoint. An operator with local/deployment access runs:

```text
python -m app.modules.identity.bootstrap --email administrator@example.test
```

The command requires database configuration and an explicitly configured email sender plugin. It does not print the invite token. Invitation acceptance creates a short-lived TOTP enrollment challenge; the initial admin must verify TOTP before the account is enabled. Subsequent admin login requires a TOTP code or an unused recovery code before a session is issued.

## API surface

- `POST /api/v1/auth/invitations/accept`: accept the one-time invitation and begin TOTP enrollment.
- `POST /api/v1/auth/totp/enroll/verify`: verify initial TOTP and display one-time recovery codes.
- `POST /api/v1/auth/login`: validate password and create a short-lived TOTP challenge for admins.
- `POST /api/v1/auth/login/totp`: complete admin MFA or issue a session for a non-admin staff account.
- `POST /api/v1/auth/refresh`: rotate the opaque refresh credential after Origin and CSRF validation.
- `POST /api/v1/auth/logout`: revoke the current refresh session after Origin and CSRF validation.
- `GET /api/v1/auth/me`: validate the current server-side session and resolve role/tenant from the database.

Access JWTs identify a user and session only; role and tenant authority are resolved from persisted account data. Administrative sessions expire after 30 minutes of inactivity. Refresh values, invitation tokens, TOTP seeds, passwords, and recovery codes are never stored in plaintext; TOTP seeds are encrypted because verification requires the original seed.

## Database and checks

Alembic migration `0001_staff_identity` creates the staff identity tables for an isolated fresh database. Do not run it against an existing local database as part of this slice. Database-backed migration verification is reserved for the isolated verification task.

From this directory:

```text
../.venv/Scripts/python.exe -m pytest tests -q
../.venv/Scripts/ruff.exe check app tests
../.venv/Scripts/pyright.exe app tests
```

Most unit tests use in-memory SQLite and in-test fakes. The dedicated Docker test runner also executes the F04 PostgreSQL migration test against a fresh temporary database.

## Isolated Docker test runner

The API image remains runtime-only. The separate Compose project builds a test-only image with the dependencies from `.[dev]` and a temporary PostgreSQL service. It installs `libatomic1` for the bundled Node runtime used by Pyright on `python:3.12-slim`. It binds `app/`, `tests/`, `alembic/`, and `alembic.ini` read-only from the working tree into the container, so code/test edits do not require rebuilding. PostgreSQL uses a temporary filesystem and shares its loopback network namespace with pytest so the F04 migration test can use its required fresh `roomforge_f04_*` database. The runner never connects to or modifies the persistent databases in `compose.local.yml` or `compose.postgres.yml`.

Run from Windows PowerShell with Docker Desktop active, or from a WSL shell integrated with Docker Desktop.

Build the test image once, then rebuild only when the Dockerfile or Python dependencies change:

```powershell
$compose = "infra/docker/compose.tests.yml"
docker compose -f $compose build backend-tests
```

Focused photo tests:

```powershell
$compose = "infra/docker/compose.tests.yml"
docker compose -f $compose run --rm backend-tests tests/test_listing_photos.py -q
$testExit = $LASTEXITCODE
docker compose -f $compose down --remove-orphans
exit $testExit
```

Full backend suite:

```powershell
$compose = "infra/docker/compose.tests.yml"
docker compose -f $compose run --rm backend-tests
$testExit = $LASTEXITCODE
docker compose -f $compose down --remove-orphans
exit $testExit
```

Isolated Pyright check:

```powershell
$compose = "infra/docker/compose.tests.yml"
docker compose -f $compose run --rm --entrypoint pyright backend-tests app tests
$checkExit = $LASTEXITCODE
docker compose -f $compose down --remove-orphans
exit $checkExit
```
