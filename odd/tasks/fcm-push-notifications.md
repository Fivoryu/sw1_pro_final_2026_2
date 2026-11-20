# fcm-push-notifications

Objective: push notifications (Firebase Cloud Messaging) for the customer app and the staff capture app, driven by the existing `notification` table.
Branch: `feat/push-fcm` (from origin/main 54760d9). Delivery strategy: ask-on-risk. Test runner: backend `pytest`; apps `flutter test`.
Deploy target: EC2 `roomforge-web` (authorized by the user for this project, see Log L2).

## Specs

- S1 Backend stores device tokens: new table `device_token` (recipient_kind, recipient_id, token unique, platform, timestamps) with migration `0038`. Customer endpoint `POST/DELETE /api/v1/customer/devices` and staff endpoint `POST/DELETE /api/v1/staff/devices` (agency staff only, like the inbox). Re-registering the same token moves it to the new recipient.
- S2 Backend sends pushes: new nullable `notification.pushed_at`; migration backfills existing rows so history is never pushed. A dispatcher thread claims unsent notifications (`FOR UPDATE SKIP LOCKED`), sends FCM HTTP v1 to every token of the recipient with generic text (notices carry no message text, S6 of F14.6), marks `pushed_at`, and deletes tokens FCM reports as unregistered. Sending is disabled (no-op) when no credentials are configured.
- S3 FCM credentials come from `FCM_SERVICE_ACCOUNT_FILE` (path to the service-account JSON). No new Python dependency: the OAuth token is built with PyJWT + httpx. The key never enters git and is mounted read-only on the server.
- S4 Customer app (`apps/cliente_mobile`): Firebase core + messaging, asks notification permission, registers the FCM token after login and when it refreshes, removes it on logout, shows the notice while the app is open.
- S5 Staff capture app (`apps/captura_mobile`): same as S4 for agency staff.
- S6 Android: `com.google.gms.google-services` plugin and `google-services.json` for package `com.example.cliente_mobile` and `com.example.captura_mobile` (project `sw1-p2-2026`).
- S7 Deploy to `roomforge-web` and rebuild both APKs against `https://13-185-149-159.sslip.io`; verify the FCM credentials with a `validate_only` request and the token endpoints against the deployed API.
- S8 Staff sign in with the password only: the server keeps `STAFF_REQUIRE_TOTP` (default true, set to false in the EC2 compose), the panel and the capture app finish the login with no code when the API answers `totp_required: false`. Ported from the server-only copy in the rollback backup (see L4, L8).

## Tasks

- [x] T1 (S1,S2) migration 0038 + models + register/remove endpoints — route: inline. Evidence: tests/test_push.py, ruff and pyright clean
- [x] T2 (S2,S3) FCM client + dispatcher + app wiring + settings — route: inline. Evidence: full backend suite 1230 passed / 17 skipped; `validate_only` against FCM project sw1-p2-2026 returned 200
- [x] T3 (S6) Android gradle + google-services.json in both apps — route: inline (applied; APK build pending in T6)
- [x] T4 (S4) cliente_mobile push service — route: inline. Evidence: flutter test 308 passed, analyze clean on touched files
- [x] T5 (S5) captura_mobile push service — route: inline. Evidence: flutter test 804 passed; the one analyze warning (spatial_capture_controller.dart:463) is pre-existing on main
- [ ] T7 (S8) optional TOTP restored in backend (router, session, config, tests), panel (staffAuthApi, StaffLoginShell, InvitationAcceptancePage + tests) and capture app (StaffAccessChallenge.totpRequired, startLogin) — route: inline. Backend: 52 identity tests passed; panel and app tests pending; redeploy + APK rebuild pending
- [ ] T6 (S7) deploy, secret upload, APK rebuild, verification — route: inline. Done: server deployed (alembic 0038), key mounted read-only, E2E on server (register 204 -> dispatcher claimed -> FCM rejected fake token as unregistered -> token deleted). Pending: APK rebuild with Firebase and a real-device push

## Log

- L1 (2026-11-20) User: "Y luego vamos configurando firebase para tener notificaciones push" and "Esta en descargas el 4 es cliente y el 5 es captura, la clave secreta ya lo descargye igual."
- L2 (2026-11-20) User: "autorizado para siempre papu" (deploying to roomforge-web) and "quiero que lo conectes las apks para que apunten".
- L3 (2026-11-20) Verified inputs: `google-services (5).json` holds clients for `com.example.cliente_mobile` and `com.example.captura_mobile` (+ an unrelated `com.diagrammer...` client); `(4)` has no captura client, so `(5)` is used for both apps. Service-account key: `sw1-p2-2026-firebase-adminsdk-fbsvc-65b5c1908d.json` (project `sw1-p2-2026`).
- L4 (2026-11-20) Finding: the server ran code with an optional-TOTP login (`STAFF_REQUIRE_TOTP`, "totp_required": false) that is not in any git commit. Deploying origin/main replaced it, so staff login now requires a TOTP code. Demo staff share one TOTP secret (all 12 accounts); rollback copy is /opt/roomforge/rollback-pre-deploy-20261120.tgz on the server.
- L5 (2026-11-20) Decision: `firebase_messaging` 17.1.0 deprecates `getToken`/`onTokenRefresh` in favour of `register()`/`onRegistered` (Installation ID). The classic API is kept with `ignore` comments because the FCM v1 `token` field is only known to accept registration tokens; revisit once verified on a device.
- L6 (2026-11-20) Foreground messages are not drawn by the app (the inbox already polls); background/terminated notices are drawn by the system from the `notification` payload.
- L7 (2026-11-20) Server E2E: registered a fake token via `POST /api/v1/customer/devices` (204), inserted a `reservation_status` notice, and within 14 s `pushed_at` was set and the token removed (FCM answered "unregistered" to the fake token). The test notice was deleted afterwards. A real delivery still needs a device with the new APK.
- L8 (2026-11-20) User: "Y como hacemos para que puedan iniciar sesion porque no van a saber como autenticarse" and "Tonces podria solo ingresar con la congraseña, no?" -> restore password-only staff login (the EC2 compose already sets STAFF_REQUIRE_TOTP=false, comment: decision of the repository owner, 2026-11-20). The server-only implementation was recovered from /opt/roomforge/rollback-pre-deploy-20261120.tgz and ported onto main.
