# F03 — Corrección: acceso de personal desde clientes nativos (app de captura)

## Objetivo

Permitir que la app de captura (`apps/captura_mobile`) complete el acceso de personal contra la API real. Hoy recibe `403 Origin is not allowed` en `POST /api/v1/auth/login/totp`, `refresh` y `logout` porque, como cliente nativo, no envía el encabezado `Origin`. El defecto bloquea F04 (el agente no puede crear borradores desde la app) y se corrige aquí como unidad propia de F03, dentro de la rama `feat/f04-listings-completion`, con commit separado.

## Hallazgo (2026-10-01)

- `backend/app/modules/identity/router.py` rechaza con `403` cualquier petición a `login/totp`, `refresh` y `logout` cuyo `Origin` no sea exactamente `STAFF_WEB_ORIGIN`, incluida la ausencia del encabezado.
- Comprobado contra la API del stack local con un challenge inválido: sin `Origin` → `403 {"detail":"Origin is not allowed"}`; con el `Origin` del panel → `401 Login challenge is invalid or expired` (la petición llega a la validación del código).
- `odd/tasks/f03-identity-agencies.md` declara completa la sesión de personal de la app de captura, pero sus pruebas usan `test/support/fake_staff_backend.dart` y el registro indica que el backend no se cambió; nunca se ejercitó contra la API real ni en dispositivo.
- Además, `StaffSessionController` de la app descarta el token de acceso tras el login, por lo que la app no puede llamar a rutas protegidas como las de inmuebles de F04.

## Decisión del usuario (2026-10-01)

Opción A: el backend acepta las peticiones **sin** `Origin` (clientes nativos) y sigue rechazando con `403` cualquier `Origin` presente distinto de `STAFF_WEB_ORIGIN`, incluido `null`. `refresh` y `logout` siguen exigiendo el token CSRF. Razón: el control de `Origin` mitiga CSRF, que solo ocurre en navegadores, y los navegadores envían `Origin` en todo `POST` entre sitios; un cliente sin navegador que omite `Origin` debe presentar igualmente el challenge y el TOTP, o la cookie de refresh más el token CSRF. Es la pauta de OWASP: verificar `Origin` cuando existe y apoyarse en el token CSRF cuando no.

Alternativas descartadas: que la app envíe el `Origin` del panel (acopla la app a la dirección web por entorno y la hace pasar por el navegador) y rutas de acceso móvil separadas (diseño nuevo de F03, mayor alcance).

## Alcance permitido

- `backend/app/modules/identity/router.py` — únicamente las tres comprobaciones de `Origin`.
- `backend/tests/test_staff_identity_tdd.py` — pruebas nuevas.
- `backend/README.md` — descripción de la regla.
- `apps/captura_mobile/lib/domain/staff_session_controller.dart` y su prueba — conservar el token de acceso en memoria.
- Este registro y una nota en `odd/tasks/f03-identity-agencies.md`.

Fuera de superficie: el resto de `identity`, sesiones de cliente, CORS, panel, migraciones.

## Tareas

- [x] **F03O-T1 — Regla de `Origin` en el backend.** TDD: sin `Origin` se completa el login TOTP; `refresh`/`logout` sin `Origin` siguen exigiendo CSRF válido; `Origin: null` y `Origin` ajeno → `403` sin efectos.
- [x] **F03O-T2 — Token de acceso en la app de captura.** TDD: el controlador conserva el token de acceso en memoria (nunca en almacenamiento) y lo actualiza al restaurar la sesión.
- [ ] **F03O-T3 — Verificación.** Suite backend, Ruff, Pyright; `flutter test`/`flutter analyze` de la app; acceso real desde el emulador.

## Registro de ejecución

### F03O-T1 — Regla de `Origin` en el backend (2026-10-01)

- `identity/router.py`: las tres comprobaciones se reemplazaron por `_reject_foreign_origin`, que rechaza con `403 Origin is not allowed` solo un `Origin` presente distinto de `STAFF_WEB_ORIGIN` (`null` incluido) y acepta su ausencia. El resto de cada ruta no cambia: `login/totp` sigue exigiendo challenge y TOTP; `refresh` y `logout` siguen exigiendo cookie y token CSRF.
- TDD en `test_staff_identity_tdd.py` (5 pruebas nuevas): RED 3 fallidas por `403 Origin is not allowed` (login, refresh y logout sin `Origin`) y 2 ya aprobadas (`Origin: null` y ajeno en el login, guardas de regresión); GREEN 5/5. Las pruebas de `refresh`/`logout` sin `Origin` comprueban además que sin CSRF, con CSRF incorrecto y con `Origin: null` responden `403` sin rotar ni revocar la sesión.
- Ninguna prueba existente cambió: las que esperan `403` usan un `Origin` ajeno o un CSRF ausente/incorrecto.
- Verificación en contenedor `roomforge-backend-dev:local`: identidad y agencias 105/105; suite backend 466 aprobadas, 3 omitidas, 4 advertencias; Ruff limpio; Pyright 0 errores.
- `backend/README.md` describe la regla. Discrepancia preexistente anotada y no corregida: el README dice `SameSite=Strict` para la cookie de refresh, mientras el código la emite con `samesite="lax"`.

### F03O-T2 — Token de acceso en la app de captura (2026-10-01)

- Entorno: Flutter 3.41.8 (Dart 3.11.5, misma versión que el CI) instalado en `D:\tools\flutter` desde el archivo oficial, con SHA-256 verificado contra `releases_windows.json`; `PUB_CACHE`, `GRADLE_USER_HOME` y `ANDROID_HOME` como variables de usuario. `flutter doctor`: Flutter, Android toolchain y dispositivos correctos; el aviso de Visual Studio solo afecta a apps de escritorio Windows. Línea base de la app antes del cambio: `flutter test` 45/45 y `flutter analyze` sin problemas.
- `staff_session_controller.dart`: expone `accessToken`, asignado al aceptar el grant (login TOTP y restauración) y borrado al cerrar sesión o al descartar la sesión; nunca pasa por el almacén seguro.
- TDD en `staff_session_controller_test.dart` (4 pruebas nuevas): RED por compilación (`The getter 'accessToken' isn't defined`); GREEN 15/15 en el archivo; app completa 49/49; `flutter analyze` sin problemas; `dart format` sin cambios.
