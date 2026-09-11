# Diseño — HU-007: Invitación y aceptación de agentes

**Trazabilidad:** PB-007 · HU-007 · CU-007 · RF-004/RF-006 · CP-006  
**Superficies:** `backend/` y `panel/`  
**Estado:** diseño propuesto; no constituye evidencia de implementación ni de ejecución de CP-006.

## 1. Base confirmada y decisiones de alcance

El diseño parte de evidencia del repositorio actual:

- `backend/app/modules/tenant/models.py` ya contiene `Invitacion` (alta de tenant) y `TenantAdministrator`; este último tiene unicidad `(tenant_id, usuario_global_id)` y es la fuente actual del contexto administrativo.
- `TenantContextResolver` resuelve un único `TenantContext` desde el principal autenticado y la persistencia server-side.
- `UsuarioGlobal` normaliza el correo en los servicios de identidad y usa Argon2id mediante `PasswordHasherProtocol`.
- La cadena de Alembic observada comprende las revisiones `0001` a `0012`, con `0012_hu006_purge.py` como cabeza actual; HU-004–HU-006 tienen migraciones aditivas con downgrades protegidos por datos.
- El panel todavía construye `UserManagementService` sobre `InMemoryUserRepository`; `SessionService` ya ofrece la renovación transparente para solicitudes protegidas y `ApiClient.request` admite solicitudes públicas.

**Confirmado por propuesta/spec:** membresía inicial `pending`; contraseña definida por el agente solo para una cuenta nueva; TTL de siete días; correo `trim + lowercase`; token criptográficamente aleatorio con hash SHA-256 persistido; reutilización de `UsuarioGlobal` sin modificar sus credenciales; un pendiente por tenant/correo; sin `Plan.max_agents`; sin cambios de HU-006; sin activación/desactivación/revocación/reactivación de HU-008 ni RBAC de HU-009.

**Decisiones de diseño para concretar el contrato:** se separan las invitaciones de agente de la invitación de onboarding existente; el token de aceptación se transporta en el body y no en la URL HTTP; se añade una operación pública de inspección para saber si se necesita contraseña; la notificación ocurre después del commit y su resultado queda persistido. Estas decisiones evitan alterar la semántica histórica de HU-004 y reducen exposición del token en logs de acceso.

## 2. Arquitectura backend

El slice permanece dentro de `app.modules.tenant`, siguiendo el patrón router/schemas/service/repository/models:

1. `AgentInvitationRouter` expone las operaciones administrativas y públicas.
2. `AgentInvitationService` normaliza correo, aplica reglas, obtiene el reloj, genera/hashéa token, usa `TenantContext` y coordina la transacción.
3. `AgentInvitationRepository` encapsula `SELECT ... FOR UPDATE`, inserciones, cambios de estado y mapeo de `IntegrityError`.
4. Los modelos nuevos viven en `tenant.models`; `Invitacion` y `TenantAdministrator` no se reutilizan como membresía de agente.
5. `AgentInvitationNotifier` es un puerto inyectable. Un adaptador SMTP puede reutilizar la configuración y patrón de `identity.notifier`, pero usa asunto y URL de aceptación propios; el fake de pruebas captura el token únicamente en memoria.
6. El token puede reutilizar `SecureVerificationTokenGenerator` y `hash_verification_token` de `identity.verification`, sin llamar a `IdentityService.registrar`, porque ese servicio confirma por separado y puede emitir verificación de correo.

La dependencia administrativa debe obtener `MeResponse` con `get_current_user`, construir el `TenantRepository` existente y un `AgentInvitationRepository` sobre la misma `Session`, y resolver `TenantContextResolver.resolve_context(tenant_repository, principal.id)`. El servicio recibe el contexto ya resuelto y usa el repositorio de invitaciones para operar. No se acepta un `tenant_id` en body, query string o header: el schema usa `extra="forbid"` y la ruta aplica la misma comprobación de autoridad de `tenant.router`.

## 3. Entidades, estados e integridad

### `AgentInvitation`

Tabla propuesta: `agent_invitation`. Campos: `id`, `tenant_id`, `normalized_email`, `token_hash CHAR(64)`, `status`, `issued_at`, `expires_at`, `accepted_at`, `invalidated_at`, `replaced_by_id`, `created_by_administrator_id`, `delivery_status`, `delivery_error_code`. El token claro nunca es campo, log, respuesta ni evento.

Estados permitidos: `pending -> accepted | invalidated | expired`. La expiración se materializa de forma perezosa al inspeccionar/aceptar una fila vencida. No se reabren estados terminales. `delivery_status` es independiente (`pending`, `delivered`, `failed`) para que un fallo de correo no haga recuperable el secreto.

Restricciones: FK a `tenant` y `tenant_administrator`, `UNIQUE(token_hash)`, `CHECK(status ...)`, `CHECK(expires_at > issued_at)` e índice único parcial `(tenant_id, normalized_email) WHERE status = 'pending'`. El índice normal `(tenant_id, normalized_email, issued_at)` soporta consulta histórica.

### `TenantAgentMembership`

Tabla propuesta: `tenant_agent_membership`. Campos: `id`, `tenant_id`, `usuario_global_id`, `invitation_id`, `status`, `created_at`. Estados permitidos: `pending`, `active`, `inactive`, `revoked`; HU-007 solo inserta `pending`. `UNIQUE(tenant_id, usuario_global_id)` impide duplicar una membresía histórica o pendiente; `UNIQUE(invitation_id)` vincula una aceptación a una sola membresía. No contiene rol ni permisos.

Una membresía `active`, `inactive`, `revoked` o `pending` existente produce conflicto/idempotencia de negocio: no se crea otra fila ni se cambia el estado. La transición operacional queda en HU-008; RBAC queda en HU-009. `TenantAdministrator` continúa representando únicamente la administración bootstrap y no se crea un administrador para el agente.

### Auditoría mínima

Tabla propuesta `agent_invitation_event`: `id`, `invitation_id`, `event_type`, `occurred_at`, `actor_administrator_id` nullable, `result_code` nullable. Eventos permitidos: emisión, reemplazo, aceptación, expiración, invalidación y fallo de entrega. No contiene token, contraseña ni payload sensible. Los eventos de una transacción se escriben junto con ella; el resultado de entrega se registra en una transacción posterior.

## 4. Concurrencia y flujo de datos

### Emisión/reinvitación administrativa

1. Validar schema y normalizar el correo antes de cualquier consulta.
2. Resolver el tenant exclusivamente desde `TenantContext` y verificar que la suscripción/contexto provienen del administrador actual; no consultar `Plan.max_agents`.
3. Dentro de una transacción, bloquear la fila `tenant` con `FOR UPDATE` para serializar emisiones del mismo tenant; consultar y bloquear el pendiente por `(tenant_id, normalized_email)`.
4. Si existe membresía del usuario global para ese tenant, devolver conflicto sin crear invitación. Si existe `pending`, cambiarla a `invalidated`, registrar reemplazo y crear una nueva fila `pending`; el índice parcial respalda la regla aunque falle un camino de aplicación.
5. Generar `secrets.token_urlsafe(32)`, calcular SHA-256, persistir únicamente el hash, emitir evento y hacer commit. El enlace se arma solo en memoria para el notifier.
6. Invocar `deliver(invitation_id, normalized_email, raw_token, expires_at)` después del commit. Actualizar `delivery_status` y el evento de resultado. Un fallo queda observable y permite reinvitar; nunca se devuelve el token como recuperación.

### Inspección y aceptación pública

El contrato de diseño usa `POST /api/v1/agent-invitations/inspect` con `{token}` y `POST /api/v1/agent-invitations/accept` con `{token, password?, password_confirmation?}`. Son decisiones de diseño, no contratos previamente implementados. La inspección responde solo `requires_password`, vencimiento y datos no sensibles; no expone existencia de usuarios a quien no posea un token válido.

La aceptación abre una única transacción y sigue este orden: localizar y bloquear la invitación por `token_hash`; si está vencida, marcar `expired`; rechazar cualquier estado no `pending` con un error genérico; tomar un advisory lock transaccional por `normalized_email` para carreras de creación global; bloquear el `UsuarioGlobal` si existe; crear la cuenta con Argon2id si no existe y validar contraseña de mínimo ocho caracteres; consultar/bloquear la membresía `(tenant_id, usuario_global_id)`; crear `pending`; cambiar invitación a `accepted`; registrar evento y commit. El advisory lock por correo evita dos cuentas nuevas para el mismo correo en tenants distintos; la unicidad global de correo es la segunda barrera.

Si falla cualquier paso, la transacción revierte cuenta, membresía, estado de invitación y evento. Una segunda aceptación del mismo token espera el lock y recibe `INVITATION_UNAVAILABLE`; no produce efectos parciales. Una carrera de reinvitación queda serializada por la fila tenant y el índice parcial. Los conflictos de unicidad se traducen a resultado de negocio después de rollback, sin ocultar una violación de integridad real.

Para un usuario existente se conserva exactamente `hash_password`, `estado`, `correo_verificado` y sesiones; la aceptación no inicia sesión. Para uno nuevo se crea `correo_verificado=false` y no se emite aquí un token de verificación: la política de HU-003 permanece independiente. Esto evita marcar implícitamente el correo y deja explícito el gap funcional descrito abajo.

## 5. Contrato HTTP y errores

Los nombres siguientes son **decisiones de diseño** para completar la spec; deben permanecer sujetos a pruebas de contrato antes de implementar:

- `GET /api/v1/tenant/agent-invitations`: lista del tenant resuelto, sin token; proyecta como `expired` un pendiente cuyo `expires_at` ya pasó y puede materializar ese cambio en la misma lectura transaccional.
- `POST /api/v1/tenant/agent-invitations`: body `{email}`; crea o reemplaza el pendiente. Devuelve `201` con `id`, correo normalizado para presentación, `status`, `expires_at` y `delivery_status`.
- `POST /api/v1/agent-invitations/inspect`: body `{token}`; devuelve `200` con `requires_password` y metadatos no sensibles.
- `POST /api/v1/agent-invitations/accept`: body con token y credenciales condicionales; devuelve `200` con `invitation_status: accepted`, `membership_status: pending`, `membership_id`; nunca tokens ni JWT.

Mapeo estable propuesto: `401 UNAUTHORIZED`; `403 TENANT_ADMIN_REQUIRED`; `400 CLIENT_AUTHORITY_FIELD_FORBIDDEN`; `422 REQUEST_SCHEMA_INVALID`/`INVALID_EMAIL`/`INVITATION_PASSWORD_REQUIRED`; `409 AGENT_MEMBERSHIP_EXISTS` o `AGENT_MEMBERSHIP_PENDING`; `410 INVITATION_UNAVAILABLE` para token inválido, expirado, invalidado, reemplazado o utilizado. La respuesta pública no distingue estados que permitan enumerar una invitación; la UI muestra mensajes no sensibles. Un fallo de notificación no revierte la invitación ya confirmada y se comunica mediante `delivery_status=failed`.

## 6. Integración del panel

Se conserva el `App` y el flujo de autenticación/suscripción; se reemplaza únicamente el seam local de usuarios:

- `App.tsx` deja de construir `InMemoryUserRepository` y crea `UserManagementService(api, session)`. Añade una rama mínima para la ruta pública de aceptación; no introduce RBAC, activación ni otra sesión.
- `application/userManagementService.ts` pasa a ser un adaptador de invitaciones: operaciones administrativas usan `SessionService.request`; inspección/aceptación públicas usan `ApiClient.request` sin sesión. Puede conservarse el nombre para minimizar el acoplamiento de la página existente.
- `data/apiClient.ts` añade métodos tipados para los cuatro contratos y códigos de error HU-007. El token se envía en body; no se concatena a paths ni se muestra en mensajes.
- `UserManagementPage.tsx` reemplaza alta/edición/desactivación local por correo, lista de estados `pending/accepted/invalidated/expired`, reinvitación mediante el mismo comando y estados de red/conflicto.
- Se añade `AgentInvitationAcceptancePage.tsx`; toma el token de un fragmento de URL (`#token=...`) en memoria, ejecuta `inspect`, solicita contraseña solo si corresponde y luego ejecuta `accept`. Nunca presenta aceptación como activación ni asigna permisos.
- Los archivos `domain/user.ts`, `UserRepository.ts`, `InMemoryUserRepository.ts` y fixtures locales se eliminan solo si la búsqueda final confirma que no tienen consumidores; no se modifica `SessionService`, `SubscriptionService` ni la pantalla de login.

## 7. Migración, despliegue y downgrade

Crear `backend/alembic/versions/0013_hu007_agent_invitations.py`, dependiente de `0012` (`0012_hu006_purge.py`, cabeza actual), con las tres tablas, FKs, checks, índices y estado inicial. La migración se agrega al final de la cadena existente `0001`–`0012`; no renombrar, reordenar, backfillear ni cambiar estados de `invitacion`; las filas de onboarding y las relaciones de `tenant_administrator` siguen funcionando sin adaptación. La migración no consulta ni altera `plan`, `suscripcion` o datos de HU-006.

El despliegue es: aplicar la migración Alembic `0013` sobre la cabeza `0012`; configurar la URL SMTP/notificación; desplegar backend; desplegar panel. Si la entrega falla, se conserva la invitación y se permite reinvitar. Para rollback operativo se deshabilitan los comandos/rutas y se conservan cuentas, membresías, invitaciones y auditoría. El `downgrade` solo elimina las tablas HU-007 si están vacías; si existen datos, falla explícitamente con una excepción de seguridad. No se borran usuarios globales, tenants, `Invitacion` ni `TenantAdministrator`.

## 8. Pruebas TDD y verificación

Backend, en este orden: tests unitarios del normalizador, generador/hash y servicio; tests de repositorio fake para estados, reinvitación, credenciales y errores; tests API para autoridad derivada, rechazo de `tenant_id`, validación, respuestas y ausencia de secretos; pruebas PostgreSQL para migración, índice parcial, FKs, unicidad `(tenant,user)`, rollback y dos aceptaciones/reinvitaciones concurrentes. La suite autoritativa será `.venv/Scripts/python.exe -m pytest backend/tests -q`; después `ruff` y `pyright` según `AGENTS.md`.

Panel: Vitest para requests exactas (incluido que el token no aparece en URL), normalización de errores, servicio autenticado/público y página; pruebas de estados de carga, expiración, reemplazo, membresía existente, fallo de red y contraseña condicional. CP-006 queda preparado; no se declara ejecutado sin evidencia independiente.

## 9. Confirmado, gaps y riesgos restantes

**Confirmado:** separación de alcance HU-006/HU-008/HU-009; membresía pendiente; TTL siete días; reutilización global; no `max_agents`; normalización; token hash-only; aceptación atómica; reinvitación reemplazante.

**GAP-007-EMAIL:** no está decidido por HU-003 si una invitación válida verifica `correo_verificado`. Este diseño no lo modifica ni emite verificación; debe resolverse antes de prometer login posterior a HU-008.

**GAP-007-NOTIF:** el repositorio tiene notifier de verificación, no un outbox de invitaciones. El seam síncrono post-commit deja una invitación válida cuando SMTP falla; se requiere observabilidad y política de reintento operacional.

**GAP-007-CONTRACT:** las rutas, payloads y códigos de esta sección son decisiones de diseño y aún no evidencia de un contrato consumido por otra superficie. Deben fijarse mediante pruebas de contrato antes del apply.

Riesgos principales: locks advisory dependientes de PostgreSQL, migración con datos de HU-007 que impide downgrade, diferencias de navegador al usar fragmentos y crecimiento de pruebas de concurrencia. El plan mitiga los dos primeros mediante integración PostgreSQL y downgrade fail-closed; no se incorpora una política de cuota ni una excepción de tamaño.

## 10. Archivos candidatos y previsión de revisión

**Backend:** `app/modules/tenant/models.py`, `agent_invitation_repository.py`, `agent_invitation_service.py`, `agent_invitation_router.py`, `schemas.py`, `agent_invitation_notifications.py`, `main.py`, `alembic/versions/0013_hu007_agent_invitations.py`, `tests/test_hu007_agent_invitations.py` y un test PostgreSQL de concurrencia si el fixture existente no lo soporta.

**Panel:** `src/App.tsx`, `src/data/apiClient.ts`, `src/application/userManagementService.ts`, `src/features/user-management/UserManagementPage.tsx`, nuevo `src/features/agent-invitations/AgentInvitationAcceptancePage.tsx` y sus pruebas; eliminación condicionada de los artefactos locales sin consumidores.

Previsión: backend/migración 150–180 líneas; pruebas backend 110–130; panel/cliente 80–90; pruebas panel 40–60. Total estimado **380–400 líneas modificadas**, en el límite y sin asumir `size:exception`. Si el soporte real de concurrencia o el notifier supera ese límite, se debe pausar y pedir partición antes de implementar.
