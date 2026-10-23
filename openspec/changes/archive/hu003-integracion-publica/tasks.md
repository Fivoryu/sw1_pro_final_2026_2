# Tareas: integración pública de HU-003

## Alcance operativo

Estas tareas implementan únicamente la integración pública de HU-003. El cambio de la ruta viva de `POST /api/v1/auth/registro` a `POST /api/v1/auth/register` ya está completo, junto con sus callers activos, pruebas y documentación activa; **no es una tarea de implementación**. Las referencias históricas se conservan sin reescritura.

La entrega se organiza en dos slices independientes y no encadenados: Slice 2A backend y Slice 2B Flutter/evidencia condicional. El presupuesto autorizado es de 600 líneas authored modificadas: máximo 300 por slice. No se modifican `hu003-verificacion-correo`, HU-004, HU-005, HU-006, gitlinks, ramas, commits, remotes, `openspec/config.yaml`, configuración OpenSpec, secretos locales ni documentación histórica.

## Review Workload Forecast

| Field | Value |
| ------- | ------- |
| Estimated changed lines | Slice 2A: 272 + 28 de reserva = máximo 300; Slice 2B: hasta 300; total máximo 600 |
| 400-line budget risk | High |
| Chained PRs recommended | No |
| Suggested split | Slice 2A independiente → Slice 2B independiente, sin PR encadenado |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

La estrategia `ask-on-risk` no autoriza una excepción silenciosa: si un slice supera 300 líneas, si el total amenaza 600 líneas o si una prueba de seguridad queda fuera, se detiene y se solicita decisión. El conteo real de authored additions + deletions se mide antes de iniciar 2B y antes de declarar el cierre.

## Reglas comunes de ejecución

- Todas las tareas de implementación siguen estrictamente **RED → GREEN → TRIANGULATE → REFACTOR**. Cada unidad debe registrar evidencia del runner, alcance, resultado y artefacto, o `N/A` con causa concreta.
- Todo trabajo runtime-bearing usa `gentle-ai sdd-attempt acquire` antes de ejecutarse y `gentle-ai sdd-attempt settle` después, con request IDs distintos, token nativo y límites de intentos/líneas provistos por la autoridad. No se inventan contadores en este archivo, Engram ni Pi.
- El notificador se ejecuta después del commit de persistencia. Registro y token inicial conservan **dos commits retry-safe**, sin afirmar atomicidad distribuida.
- El fallo de persistencia se clasifica como `500` genérico seguro; no se convierte en `410`. El consumo estructuralmente inválido responde `422`; un `token` string presente pero no utilizable responde `410` genérico.
- Las rutas públicas nuevas usan segmentos en inglés y los campos JSON existentes permanecen en español. Solicitud y reenvío responden `202` genérico byte-a-byte, sin enumeración.
- Se conservan TTL de 7 días, cooldown de 15 minutos y máximo de 3 reenvíos por ventana de 24 horas. No se crea sesión ni se hace auto-login al consumir; el login no verificado queda bloqueado.
- Un fake demuestra lógica aislada, no Mailpit, PostgreSQL, Flutter, deep link, panel ni Sprint 3. La presencia de archivos o configuración tampoco constituye PASS.

## Orden de dependencias y límites protegidos

1. Slice 2A: prechecks → RED → GREEN → TRIANGULATE → REFACTOR → conteo y evidencia.
2. Slice 2B: solo después de que 2A tenga contrato y evidencia registrada; precheck duro → decisión de alcance → RED → GREEN → TRIANGULATE → REFACTOR.
3. No se agregan migraciones en el plan normal. `models.py`, `repository.py`, `backend/alembic/versions/0006_hu003_email_verification.py` y `backend/alembic/env.py` tienen cero líneas previstas. Una incompatibilidad imprescindible detiene el slice y requiere decisión.
4. `panel/` no recibe implementación mientras no existan scaffold, entrypoint, router, package manager y runner verificables. No se crea scaffold.

# Slice 2A — Backend público

**Presupuesto:** subtotal authored previsto 272 líneas; reserva explícita 28; máximo 300. La reserva no se consume para ocultar seguridad, tests o una ampliación de alcance.

### 2A.1 — Precheck de infraestructura, base y superficies protegidas

- [ ] Antes de editar, comprobar con evidencia de apply: `alembic heads`, `alembic current`, compatibilidad con `0006`; topología de `infra/docker/compose.postgres.yml`; disponibilidad de los runners backend; y que `models.py`, `repository.py`, migración 0006 y `alembic/env.py` no requieren modificación. Dependencias: ninguna. Superficies permitidas: lectura de los paths anteriores; no escribirlos. Hecho cuando se registra cada resultado como disponible, `N/A` o bloqueo y se detiene ante múltiples heads, base incompatible, reestructuración de Compose o dependencia de migración. Forecast: 0 líneas. <!-- sdd-owner: implementation -->

### 2A.2 — RED: contrato, dobles y regresiones backend

- [ ] Crear primero los casos rojos y ajustar dobles/fixtures para el contrato público: OpenAPI con `register`, `login`, `email-verification/request`, `email-verification/resend` y `email-verification/consume`; registro `201` pendiente; login verificado/no verificado; request/resend `202` constante; consumo `422/410/200`; persistencia `500`; no sesión, no secretos y no contraseña. Dependencias: 2A.1. Superficies exactas: `backend/tests/test_registro.py`, `backend/tests/test_autenticacion.py`, `backend/tests/test_verificacion_correo.py`, archivo nuevo `backend/tests/test_verificacion_publica.py`; no editar otros tests ni el cambio archivado. Hecho cuando los tests expresan los criterios sin rebajar regresiones existentes y fallan por ausencia de integración. Forecast: 90 líneas. <!-- sdd-owner: implementation -->

### 2A.3 — GREEN: schemas, wiring y registro/login

- [ ] Implementar lo mínimo para hacer verdes los tests de registro y login: integrar `VerificationService` mediante DI en `backend/app/modules/identity/router.py` y `service.py`; crear la cuenta no verificada en el primer commit; persistir la emisión inicial en el segundo commit; invocar el notifier solo después del commit; bloquear sesión/access token/refresh token para cuentas no verificadas; intentar reenvío automático únicamente después de credenciales válidas y conservar `401` genérico ante cualquier fallo de entrega. Dependencias: 2A.2. Superficies exactas: `backend/app/modules/identity/service.py`, `backend/app/modules/identity/router.py`, `backend/app/modules/identity/schemas.py`, `backend/app/modules/identity/verification.py`; no tocar modelos, repositorio ni sesión de JWT fuera de los puntos de integración. Hecho cuando cuentas verificadas mantienen `TokenResponse`, cuentas no verificadas no crean `Sesion`, y el fallo de notifier no altera `201` ni verifica la cuenta. Forecast: 57 líneas. <!-- sdd-owner: implementation -->

### 2A.4 — GREEN: endpoints públicos y semántica de errores

- [ ] Implementar solicitud, reenvío y consumo bajo `/api/v1/auth` con campos nuevos en español: request/resend `202` y cuerpo genérico idéntico para inexistente, verificada, cooldown, límite, entrega aceptada o fallida; consumo estructural `422`, token string presente no utilizable `410`, éxito `200` en español y persistencia `500` genérico. Mantener `410` separado de `VerificationPersistenceError`, no reflejar token/hash/input sensible y no crear sesión al consumir. Dependencias: 2A.3. Superficies exactas: `backend/app/modules/identity/router.py`, `backend/app/modules/identity/schemas.py`, `backend/app/modules/identity/verification.py`, `backend/tests/test_verificacion_publica.py`. Hecho cuando todos los payloads de la tabla normativa tienen el código/body esperado y no hay enumeración. Forecast: 50 líneas. <!-- sdd-owner: implementation -->

### 2A.5 — GREEN: seam de notificación y configuración segura

- [ ] Implementar el puerto/adaptador local sin acoplarlo a HTTP o persistencia: fake sustituible, `SmtpVerificationNotifier`, `UnavailableVerificationNotifier`, URL efímera con token solo en el mensaje, conversión segura de errores y settings externos sin secretos. Mantener 7/15/3 y no modificar `.env`. Agregar Mailpit a Compose solo si 2A.1 demuestra una extensión mínima sin reestructuración. Dependencias: 2A.3. Superficies exactas: `backend/app/modules/identity/notifier.py` nuevo, `backend/app/core/config.py`, `infra/docker/compose.postgres.yml` solo condicional; pruebas en `backend/tests/test_verificacion_publica.py` y `test_registro.py`. Hecho cuando el fake no se cuenta como Mailpit, no se guardan token/password/hash y el fallo de entrega conserva la respuesta genérica. Forecast: 53 líneas. <!-- sdd-owner: implementation -->

### 2A.6 — TRIANGULATE: persistencia, PostgreSQL, concurrencia y seguridad

- [ ] Cruzar la suite fake con backend completo y, si está disponible, PostgreSQL/Alembic real: verificar dos commits, rollback y no llamada al notifier ante persistencia fallida; TTL 7 días, cooldown 15 minutos, 3 reenvíos/24h; lock usuario → tokens; dos consumos concurrentes con exactamente un `200` y otro `410`; token único, hash persistido, ausencia de sesión y ausencia de secretos en responses, persistencia, fake, excepciones y logs inspeccionables. Dependencias: 2A.4 y 2A.5. Superficies permitidas: tests ya listados, sin cambiar contratos para acomodar el entorno. Hecho cuando se registra evidencia separada `fake`, `backend` y `PostgreSQL`; si PostgreSQL no está disponible, se registra `N/A` y no se declara la carrera PASS. Forecast: 14 líneas. <!-- sdd-owner: implementation -->

### 2A.7 — TRIANGULATE: Mailpit y contrato OpenAPI

- [ ] Si Docker/Mailpit están disponibles, levantar únicamente la topología aprobada, entregar un mensaje local, verificar enlace utilizable y revisar que no contenga contraseña, hash, secreto ni datos internos fuera del token necesario en el enlace. Verificar además OpenAPI y requests HTTP reales de las cinco rutas. Si no está disponible, registrar `N/A` o fallo de entrega, nunca fake como Mailpit. Dependencias: 2A.6. Superficies: `infra/docker/compose.postgres.yml`, backend y evidencia de ejecución; no editar documentación Sprint 3. Hecho cuando Mailpit queda clasificado separadamente de fake y el contrato público real coincide con la especificación. Forecast: 0 líneas. <!-- sdd-owner: implementation -->

### 2A.8 — REFACTOR y cierre del slice

- [ ] Refactorizar solo después de TRIANGULATE: eliminar duplicación, revisar mapeos y excepciones, confirmar que el notifier sigue post-commit, que no se alteró la ruta histórica ni HU-004/HU-005/HU-006, y registrar rollback exacto para endpoints, wiring, settings, notifier, Compose y tests agregados sin borrar cuentas/sesiones. Medir authored additions + deletions del slice: 272 previstos + hasta 28 de reserva, máximo 300. Dependencias: 2A.7. Superficies: únicamente las superficies permitidas de 2A.2–2A.5. Hecho cuando el diff está dentro de límite y toda evidencia tiene comando, resultado y clasificación. Forecast: 0 líneas base; reserva restante según conteo. <!-- sdd-owner: implementation -->

**Distribución Slice 2A:** 90 + 57 + 50 + 53 + 14 + 8 = **272 líneas authored previstas**; **28 de reserva**; **máximo 300**. No se autoriza consumir la reserva sin registrar causa, archivo, nuevo total y condición de detención.

# Slice 2B — Flutter y evidencia condicional

**Presupuesto:** máximo 300 líneas authored. Depende del contrato estable de 2A, pero permanece como slice independiente y no encadenado.

### 2B.1 — Precheck duro y decisión de alcance antes de editar

- [ ] Antes de cualquier edición 2B, inspeccionar `panel/` para `package.json`, package manager, entrypoint, router, scripts y runner; inspeccionar `apps/cliente_mobile/pubspec.yaml`, `lib/main.dart`, `lib/app.dart`, servicio/repositorio/ViewModel/pantallas de auth, `web/index.html`, `web/manifest.json`, `android/app/src/main/AndroidManifest.xml` e `ios/Runner/Info.plist`; comprobar `flutter test`, `flutter analyze`, build/plataforma, emulador/dispositivo, cold start, resume y disponibilidad de deep link. Dependencias: Slice 2A cerrado y conteo real de 2A. Superficies: lectura únicamente de esos paths; no crear `panel/` scaffold. Hecho cuando se registra una matriz disponible/`N/A`/bloqueada para panel, Flutter, Flutter Web, Android, iOS, deep link y runners; ante ausencia de scaffold, el panel queda `N/A` y no recibe tareas de implementación. Si falta runner o plataforma necesaria, detener o reducir 2B explícitamente antes de editar. Forecast: 0 líneas. <!-- sdd-owner: implementation -->

### 2B.2 — Medición y puerta de presupuesto

- [ ] Medir el diff real de Slice 2A con additions + deletions authored y confirmar que el total proyectado de 2B no exceda 300 ni el agregado 600. Dependencias: 2B.1. Superficies: lectura de diff/estado; no modificar código, docs, gitlinks ni ramas. Hecho cuando se registra el número real, los archivos incluidos y la decisión `continuar 2B`, `2B parcial` o `detener`; no avanzar si 2A supera 300, si el total amenaza 600 o si seguridad/tests esenciales no caben. Forecast: 0 líneas. <!-- sdd-owner: implementation -->

### 2B.3 — RED: contrato Flutter y estados efímeros

- [ ] Si el precheck habilita Flutter, agregar primero tests rojos de servicio, repositorio, ViewModel, routing y widgets para request/resend/consume, éxito/error genérico, `422/410`, orientación posterior al registro, ruta pública durante restauración, consumo único, limpieza de query, no sesión y no escritura en `CredentialStorage`. Dependencias: 2B.2 y contrato 2A. Superficies permitidas: `apps/cliente_mobile/test/` existente o archivo nuevo dentro de ese directorio y los tests Flutter existentes relacionados; no editar `credential_storage.dart` ni panel. Hecho cuando los casos fallan por ausencia de integración y separan evidencia fake de runner Flutter. Forecast: hasta 70 líneas. <!-- sdd-owner: implementation -->

### 2B.4 — GREEN: integración mínima de Flutter

- [ ] Implementar solo la superficie Flutter verificable: métodos en `apps/cliente_mobile/lib/data/services/auth_api_service.dart`, delegación en `lib/data/repositories/auth_repository.dart`, estado/comandos en `lib/ui/features/auth/view_models/auth_view_model.dart`, orientación en `register_screen.dart`/`login_screen.dart`, vistas mínimas bajo `lib/ui/features/email_verification/` y rutas públicas en `lib/app.dart`. Mantener el token en memoria, consumirlo una sola vez, limpiar la URL y no pasarlo a `CredentialStorage`; no auto-login. Dependencias: 2B.3. Superficies exactas: esos paths Flutter; `AndroidManifest.xml`/`Info.plist` solo si build y prueba de plataforma fueron habilitados por 2B.1. Hecho cuando `go_router` conserva acceso público, el cliente usa los paths backend exactos y la implementación no persiste ni registra el token. Forecast: hasta 120 líneas. <!-- sdd-owner: implementation -->

### 2B.5 — GREEN condicional: deep link verificable, nunca productivo por inferencia

- [ ] Configurar y probar únicamente el scheme/plataforma realmente disponible, candidato local `roomforge://email-verification`; distinguir cold start y resume. No declarar Universal Links/App Links, dominio, certificados, fingerprints, Team ID, AASA o `assetlinks.json` sin evidencia. Si no hay build, app instalada, emulador/dispositivo o recepción comprobable, dejar deep link `N/A`/bloqueado y conservar fallback seguro. Dependencias: 2B.4. Superficies exactas: `AndroidManifest.xml` y/o `Info.plist` solo con precheck positivo, más tests/evidencia Flutter. Hecho cuando cada plataforma declarada tiene evidencia real o queda explícitamente no disponible. Forecast: hasta 35 líneas. <!-- sdd-owner: implementation -->

### 2B.6 — Panel web: N/A o integración solo si el precheck encuentra scaffold

- [ ] Mantener `panel/` sin implementación si faltan scaffold, entrypoint, router, package manager o runner: registrar `N/A` con causa y no crear archivos. Solo si 2B.1 encuentra todos esos elementos y 2B.2 confirma presupuesto, crear una ruta mínima de activación dentro de los archivos existentes, con token efímero, URL limpia, error genérico y acción a login; ejecutar únicamente scripts reales. Dependencias: 2B.1 y 2B.2. Superficies permitidas: `panel/` existente descubierto por el precheck; nunca scaffold nuevo ni Flutter Web presentado como panel React. Hecho cuando la clasificación distingue panel React/Vite de Flutter Web y la ausencia actual queda explícita. Forecast: 0 líneas si no hay scaffold; hasta 45 líneas si aparece uno verificable. <!-- sdd-owner: implementation -->

### 2B.7 — TRIANGULATE: Flutter, web, deep link y evidencia académica

- [ ] Ejecutar, si existen, `flutter test`, `flutter analyze`, build y escenarios de request exactos; comprobar orientación de registro, estados, no escritura en secure storage, ruta pública, consumo único y navegación a login. Separar evidencia `Flutter`, `Flutter deep link cold start`, `Flutter deep link resume`, `web/panel` y `Sprint 3`. Registrar `N/A`/bloqueo con causa cuando falte SDK, runner, Node, scaffold, dispositivo o emulador. Dependencias: 2B.4–2B.6. Superficies: runners y paths efectivamente implementados; no crear capturas, métricas ni resultados Sprint 3 no ejecutados. Hecho cuando ninguna presencia de archivo/configuración se presenta como PASS y el reporte conserva evidencia fake/backend/Mailpit separada. Forecast: 0 líneas. <!-- sdd-owner: implementation -->

### 2B.8 — REFACTOR y cierre del slice

- [ ] Refactorizar únicamente tras TRIANGULATE, revisar seguridad de URI/query/logs, mantener aislado el almacenamiento de sesión, medir additions + deletions authored y detenerse en 300. Registrar rollback de rutas, vistas, servicios y configuración Flutter/web agregados por HU-003; no tocar backend histórico, gitlinks ni otros dominios. Dependencias: 2B.7. Superficies: solo las autorizadas por 2B.3–2B.6. Hecho cuando cada superficie tiene resultado real o `N/A` justificado, el total agregado queda dentro de 600 y se conserva el gap del panel si corresponde. Forecast: hasta 30 líneas dentro del máximo; no se permite excederlo. <!-- sdd-owner: implementation -->

## Evidencia mínima exigida por superficie

| Superficie | Evidencia aceptable | Resultado si no está disponible |
| --- | --- | --- |
| Fake | Tests de contrato, DI, notifier, estados, no sesión y no filtración | Demuestra lógica aislada, nunca infraestructura |
| Backend | Pytest, Ruff, Pyright y requests/OpenAPI reales | `N/A` o bloqueo con causa |
| PostgreSQL/Alembic | `heads/current`, upgrade, constraints, locks y carrera | `N/A`; no sustituir con fake |
| Mailpit | Docker real, mensaje visible, enlace utilizable y revisión de secretos | `N/A` o fallo de entrega; no fake como PASS |
| Flutter | `flutter test`, `flutter analyze`, contrato, estados y secure storage | `N/A`/bloqueo por SDK o runner |
| Deep link | Build, app instalada, cold start y resume en plataforma concreta | `N/A`/bloqueo por plataforma |
| Panel | Scaffold, runner, ruta y prueba real | Actualmente `N/A`; no crear scaffold |
| Sprint 3 | Solo artefactos ejecutados y clasificados | Gap documental; no inventar capturas o métricas |

## Rollback, aislamiento y stop conditions

- Slice 2A se revierte retirando únicamente endpoints, DI, notifier, settings, Compose y tests agregados; no se borran cuentas, sesiones ni tokens automáticamente, y nunca se marca una cuenta como verificada durante rollback.
- Slice 2B se revierte retirando únicamente rutas, vistas, comandos, tests y configuración nativa de Flutter/web agregados por HU-003; no se alteran credenciales de sesión.
- No se hace downgrade de `0006`, backfill ni migración nueva como solución automática.
- Se detiene y se reporta decisión si: cualquier slice supera 300; el total amenaza 600; una prueba de seguridad esencial no cabe; se exige atomicidad distribuida; Mailpit requiere reestructuración o secretos; falta runner mínimo; panel requiere scaffold; deep link exige prometer una plataforma no comprobada; o la integración exige editar HU-004/HU-005/HU-006, el cambio archivado, gitlinks o configuración protegida.
- La siguiente fase recomendada es `apply`: las decisiones de producto están cerradas y las condiciones ambientales quedan explícitamente como tareas-gate, no como preguntas de producto. Apply debe iniciar por 2A. <!-- sdd-owner: implementation -->

## Criterio de preparación para apply

- [ ] Confirmar que todas las tareas anteriores permanecen sin marcar, que cada unidad tiene dependencias y superficies permitidas, que el presupuesto está expresado, que `panel/` no tiene tareas de creación de scaffold y que los stops están definidos. <!-- sdd-owner: implementation -->
