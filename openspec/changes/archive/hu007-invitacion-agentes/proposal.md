# Propuesta: Invitación y aceptación de agentes

- **Cambio:** `hu007-invitacion-agentes`
- **Product Backlog:** PB-007
- **Historia:** HU-007 — Invitar agentes y que acepten con enlace seguro
- **Caso de uso:** CU-007 — Invitación de agente y aceptación
- **Requisitos:** RF-004 y RF-006
- **Superficies:** Web + Backend
- **Estado:** propuesta

## Intención y contexto

RoomForge necesita que el administrador de una inmobiliaria incorpore agentes sin crear cuentas duplicadas, compartir contraseñas por correo ni permitir que una persona se autoasigne a un tenant. El panel contiene actualmente una gestión de usuarios local basada en memoria; no representa invitaciones reales, persistencia, membresías ni autorización multi-tenant.

Este cambio implementa el primer slice del flujo: un administrador autenticado genera una invitación segura y el destinatario la acepta mediante un enlace de un solo uso. La aceptación crea una membresía con estado `pending`; no activa el acceso del agente. La activación y desactivación pertenecen a HU-008.

La propuesta reutiliza la cuenta global `usuario_global`, el patrón de enlace de activación de HU-004 y la sesión JWT de HU-002. No modifica los artefactos existentes de HU-006.

## Actores y resultado de producto

- **Administrador del tenant:** invita a un agente desde el panel y consulta el estado de la invitación.
- **Agente invitado:** abre el enlace, define su contraseña cuando se crea una cuenta nueva y confirma la incorporación.
- **Backend:** valida autoridad, normaliza el correo, controla unicidad, protege el token y ejecuta la aceptación de forma atómica.
- **Tenant:** es el contexto de autorización derivado de la identidad autenticada del administrador, nunca de un identificador enviado por el cliente.

Después del cambio, el administrador podrá enviar una invitación trazable y el agente podrá aceptarla sin que el sistema duplique una cuenta global ni active prematuramente una membresía.

## Trazabilidad y dependencias

- **HU-007 / PB-007 / CU-007:** flujo principal de invitación y aceptación.
- **RF-004:** enlace seguro de invitación de un solo uso.
- **RF-006:** restricción de membresías; en este slice se prepara la integridad y se deja la activación para HU-008.
- **HU-002:** provee autenticación JWT, sesión server-side y `get_current_user`.
- **HU-004:** provee tenant aprovisionado, patrón de invitación/activación y decisión de TTL de siete días.
- **HU-005:** provee el contexto de administrador y la relación activa entre usuario, tenant y suscripción.
- **RNF-017 / BR-A3..BR-A7:** seguridad del enlace, incorporación administrada, reutilización de usuario global e integridad de membresías.

## Alcance incluido

### Backend

- Modelo persistente de invitación de agente y membresía de agente, o extensión controlada del modelo `Invitacion` existente, con estados explícitos:
  - Invitación: `pending`, `accepted`, `invalidated`, `expired`.
  - Membresía: `pending`, `active`, `inactive`, `revoked`.
- Migración Alembic con restricciones e índices que impidan duplicados pendientes y membresías duplicadas para el mismo usuario y tenant.
- Endpoint protegido para crear invitaciones, por ejemplo `POST /api/v1/tenant/agent-invitations`.
- Endpoint público para aceptar el enlace, por ejemplo `POST /api/v1/agent-invitations/{token}/accept`.
- Normalización del correo antes de buscar, comparar o persistir: trim y lowercase, consistente con `usuario_global`.
- Generación criptográficamente segura del token; persistencia exclusiva de su hash SHA-256. El token en claro solo se entrega al notificador y nunca se almacena ni se registra.
- TTL seleccionado de producto: **7 días** desde la emisión, para mantener consistencia con el flujo de activación de HU-004. La decisión queda seleccionada, no pendiente.
- Notificación con el enlace de invitación, reutilizando el seam de entrega existente cuando sea compatible. El fallo de entrega debe quedar observable sin convertir el token en recuperable desde la base de datos.
- Auditoría de emisión, reemplazo, aceptación, expiración, invalidación y resultado de las operaciones relevantes.
- Autorización del endpoint administrativo mediante JWT y `TenantContextResolver`: el backend obtiene `tenant_id` desde el principal autenticado y su membresía administrativa. El contrato no acepta `tenant_id` en body, query string ni headers para seleccionar autoridad.
- Pruebas de servicio, API, unicidad y concurrencia con el patrón de dobles existente; la aceptación debe probarse también contra PostgreSQL para confirmar índices parciales y locking.

### Panel Web

- Reemplazar el origen local de `UserManagementPage` por una superficie de invitación conectada al API.
- Formulario administrativo de correo, estados `pending`, `accepted`, `invalidated` y `expired`, reenvío/reinvitación y mensajes de conflicto.
- Ruta pública de aceptación con token, contraseña y confirmación para cuentas nuevas; el agente define la contraseña durante la aceptación.
- Estados de enlace expirado, reemplazado, ya utilizado, membresía existente y error de red, sin exponer el token ni detalles internos.
- No se incluye una pantalla de activación/desactivación ni administración de permisos.

## Reglas de negocio y decisiones seleccionadas

1. **Membresía pendiente:** aceptar una invitación crea la membresía en `pending`. No se crea una membresía `active`, no se otorga acceso operativo y no se asignan permisos en HU-007.
2. **Cuenta global existente:** el correo normalizado que ya tiene `usuario_global` reutiliza esa cuenta. La aceptación nunca reemplaza, restablece ni modifica sus credenciales existentes.
3. **Cuenta nueva:** si no existe `usuario_global`, el agente define la contraseña durante la aceptación; se almacena únicamente como hash Argon2id. La contraseña no se envía al administrador ni por correo.
4. **Un pendiente por tenant y correo:** como máximo existe una invitación/membresía pendiente para `(tenant_id, normalized_email)`. La restricción debe estar respaldada por la base de datos, no solo por una comprobación de aplicación.
5. **Reinvitación:** si existe una invitación pendiente para el mismo tenant y correo normalizado, se invalida atómicamente el enlace anterior y se emite un reemplazo. El enlace anterior queda rechazado incluso si aún no expiró.
6. **Membresía existente:** una membresía `active`, `inactive` o `revoked` del mismo usuario en el tenant no se duplica. La operación devuelve un conflicto o una respuesta de negocio equivalente y deriva la activación/reactivación a HU-008.
7. **Movilidad entre tenants:** reutilizar una cuenta global existente no implica duplicarla. La decisión sobre una membresía pendiente en otro tenant se mantiene separada; la regla de una sola membresía activa y cualquier reactivación pertenecen a HU-008.
8. **Single-use y expiración:** un token inválido, reemplazado, consumido o expirado se rechaza. La aceptación exitosa consume la invitación una sola vez.
9. **Aceptación atómica:** validación del token, creación o reutilización de la cuenta, creación de la membresía pendiente y consumo de la invitación ocurren en una única transacción. Dos aceptaciones concurrentes no pueden producir dos membresías ni dos cuentas.
10. **Sin `max_agents`:** HU-007 no consulta ni aplica `Plan.max_agents`. La política de cuota de agentes se difiere explícitamente a otra HU para no entrar en conflicto con HU-006/HU-005.
11. **Autoridad del tenant:** el cliente no puede elegir el tenant mediante un campo enviado. El contexto administrativo se deriva exclusivamente del JWT y de la persistencia server-side.

## Contrato y resultados de aceptación

### Creación administrativa

- **Éxito:** crea una invitación `pending`, devuelve una referencia no sensible y entrega el enlace al correo normalizado. El enlace tiene TTL de siete días.
- **Reinvitación pendiente:** invalida el enlace anterior y devuelve el reemplazo; solo el nuevo enlace puede aceptarse.
- **Membresía existente:** no crea registros duplicados y responde un conflicto de negocio para `active`, `inactive` o `revoked`.
- **Solicitud no autorizada:** responde 401/403 sin revelar información de otros tenants.
- **Correo inválido o contrato adicional:** responde 422 sin persistir una invitación.

### Aceptación

- **Usuario nuevo:** valida token y contraseña, crea `usuario_global`, crea membresía `pending`, consume la invitación y confirma la operación.
- **Usuario existente:** valida token, conserva exactamente sus credenciales, crea la membresía `pending` y consume la invitación.
- **Token no utilizable:** enlace inválido, reemplazado, expirado o ya consumido; se rechaza sin cambios persistidos.
- **Carrera concurrente:** una sola solicitud puede completar la aceptación; las demás reciben rechazo idempotente/conflicto y no dejan efectos parciales.
- **Postcondición:** no se inicia sesión automáticamente, no se activa la membresía y no se asignan permisos; esos resultados se reservan para las historias correspondientes.

Los códigos HTTP concretos y el esquema final de error se fijarán en spec/design manteniendo estas semánticas; no se debe filtrar si un token válido corresponde a otro tenant ni el estado sensible de una cuenta global.

## Áreas afectadas y superficies candidatas

- `backend/app/modules/identity/`: reutilización de `UsuarioGlobal`, normalización de correo y hash Argon2id; no cambiar credenciales al reutilizar una cuenta.
- `backend/app/modules/tenant/`: `TenantContextResolver`, modelos, repositorio, servicio, schemas y router de invitaciones/membresías.
- `backend/app/core/`: generación/hash de token y configuración del TTL, preferentemente reutilizando los patrones de `tokens.py`, `verification.py` y `activation_ttl_days` sin persistir secretos.
- `backend/alembic/versions/`: migración nueva dependiente de `usuario_global`, `tenant` y las estructuras de HU-004/HU-005.
- `backend/tests/`: pruebas de aceptación, duplicados, token, password, autorización por contexto y concurrencia.
- `panel/src/application/userManagementService.ts`: sustituir la mutación local por comandos de invitación cuando se implemente el slice.
- `panel/src/features/user-management/UserManagementPage.tsx`: evolucionar la demo local a gestión de invitaciones; no presentar la UI como activación ni RBAC.
- `panel/src/data/apiClient.ts`: agregar llamadas y códigos de error del contrato.

## Fuera de alcance y no objetivos

- **HU-006:** no se modifica el ciclo de suscripción, cuotas, purga, `SubscriptionGuard`, artefactos ni documentación de la historia.
- **HU-008:** no activar, desactivar, revocar ni reactivar membresías; tampoco resolver la regla operacional de una sola membresía activa.
- **HU-009:** no implementar RBAC, catálogo de permisos, asignaciones por tenant/inmueble ni autorización de capacidades del agente.
- No aplicar `Plan.max_agents` ni introducir una política de over-quota en este cambio.
- No crear la app móvil del agente ni modificar la app cliente.
- No implementar recuperación de contraseña, cambio de contraseña posterior, verificación de correo real de HU-003 ni notificaciones multicanal fuera del enlace de invitación.
- No autoasignar rol activo, permisos, inmuebles, propiedades ni acceso a publicaciones.
- No aceptar `tenant_id` del cliente ni crear una vía administrativa alternativa basada en ese valor.

## Riesgos y gaps

- **Modelo parcialmente adelantado:** el repositorio ya tiene `Invitacion` para HU-004, pero aún no tiene la membresía de agente completa. Gap: definir si se extiende esa tabla o se separan invitaciones de onboarding; la decisión debe preservar compatibilidad con HU-004.
- **Estado de correo existente:** una cuenta global existente puede estar sin verificar por el modo de pruebas de PB-001. Gap: confirmar con HU-003 si aceptar una invitación marca `correo_verificado` o si la verificación sigue siendo independiente; HU-007 no debe cambiarlo implícitamente.
- **Entrega de correo:** un fallo posterior al commit puede dejar una invitación válida no recibida. Mitigación: registrar el resultado, permitir reinvitación segura e indicar el mecanismo de reintento; no devolver ni guardar el token como recuperación.
- **Concurrencia y PostgreSQL:** los checks de aplicación no bastan para evitar carreras. Mitigación: índice parcial, locks `FOR UPDATE`, transacción única y pruebas reales de aceptación concurrente.
- **Compatibilidad de estados:** HU-004 usa actualmente estados de activación propios. Gap: acordar la transición y nomenclatura sin invalidar el primer administrador ni los enlaces ya emitidos.
- **Alcance de una cuenta en varios tenants:** se permite reutilizar `usuario_global`, pero la regla de membresía activa global y su movilidad se implementará en HU-008. Debe quedar cubierta por una restricción coherente en el diseño posterior.
- **Presupuesto de revisión:** la integración Web + Backend puede crecer por la migración y las pruebas de concurrencia. Si el diff previsto supera 400 líneas modificadas, se debe pausar y pedir una decisión de partición; no se asume una excepción.
- **GAP-073/GAP-087/GAP-092:** responsables, ejecución de CP-006 y migraciones restantes del Sprint 1 continúan pendientes según la documentación existente.

## Previsión de implementación y revisión

Se recomienda un único slice revisable de aproximadamente **300–380 líneas modificadas**, sin contar archivos generados:

- Backend, migración y contrato: 150–190 líneas.
- Pruebas de servicio/API/concurrencia: 90–120 líneas.
- Panel Web y cliente API: 60–70 líneas.

La previsión incluye solo HU-007 y mantiene el cambio dentro del presupuesto canónico de 400 líneas. Si la compatibilidad con HU-004 o la concurrencia exige más superficie, se debe reducir el slice o solicitar una partición antes de implementar.

## Rollback

Deshabilitar temporalmente la creación y aceptación de invitaciones, conservando las cuentas globales y membresías creadas. Revocar invitaciones `pending` emitidas por el cambio si existe riesgo de seguridad, sin borrar auditoría ni credenciales. Revertir código y panel; en un entorno descartable, aplicar `downgrade` solo si la migración no contiene datos. Si ya existen invitaciones o membresías, conservar el esquema y preparar una migración controlada; no eliminar `usuario_global`, tenants, historial ni autoría.

El rollback no debe activar ni desactivar membresías ni alterar la lógica de HU-006, HU-008 o HU-009.

## Criterios de éxito

1. Un administrador autenticado puede invitar desde el contexto de su tenant sin enviar `tenant_id`.
2. El correo se normaliza antes de validar unicidad y persistir.
3. La reinvitación reemplaza el enlace pendiente anterior y el enlace viejo no vuelve a funcionar.
4. El token se genera de forma segura, es de un solo uso, expira a los siete días y nunca se persiste en claro.
5. La aceptación de una cuenta nueva requiere que el agente defina su contraseña y la guarda como Argon2id; una cuenta existente conserva sus credenciales.
6. La aceptación crea exactamente una membresía `pending`, no activa al agente y no asigna permisos.
7. Una membresía `active`, `inactive` o `revoked` existente no se duplica y el caso se deriva a HU-008.
8. La aceptación es atómica y concurrente: no deja cuentas, invitaciones o membresías parciales ni duplicadas.
9. No se aplica `Plan.max_agents` en ninguna ruta de HU-007.
10. El panel comunica estados, expiración, reemplazo y conflictos sin mostrar secretos.
11. CP-006 queda preparado y ejecutable para Web + Backend; no se declara evidencia ejecutada por esta propuesta.

## Ronda de preguntas de propuesta

Las preguntas de negocio consideradas fueron quién necesita incorporar agentes, qué problema resuelve la invitación ahora, qué identidad y credenciales se reutilizan, qué política de duplicados evita cuentas/membresías repetidas, qué implica aceptar el enlace y qué debe permanecer en HU-008/HU-009. El encargo resolvió explícitamente esas decisiones: membresía `pending`, contraseña definida por el agente para cuentas nuevas, normalización de correo, reemplazo de invitaciones pendientes, TTL seleccionado de siete días, token hasheado y aceptación atómica, sin `max_agents` ni RBAC en este cambio. No se requiere una segunda ronda para cerrar la propuesta; permanecen únicamente los gaps técnicos y de producto identificados arriba.

## Fuentes y trazabilidad

- `docs/sprint-0/ids-trazabilidad.md`: PB-007, HU-007..HU-009, CU-007..CU-009, RF-004..RF-006 y RNF-017.
- `docs/scrum/sprint-0-requerimientos/04-requerimientos-iniciales.md`: requisitos, reglas iniciales y separación entre identidad, tenancy, suscripción y permisos.
- `docs/sprint-0/auditoria-br.md`: BR-A3..BR-A8, especialmente invitación administrativa, reutilización de `usuario_global`, membresía única y preservación histórica.
- `docs/scrum/sprint-1/02-proceso-por-hu.md`: modelo lógico de `usuario_global`, `invitacion`, membresía, estados de invitación/membresía y CP-006.
- `backend/app/modules/identity/`: autenticación JWT, `UsuarioGlobal`, Argon2id, normalización y tokens hasheados.
- `backend/app/modules/tenant/`: `TenantContextResolver`, `Invitacion`, onboarding HU-004, bootstrap HU-005 y configuración `activation_ttl_days=7`.
- `panel/src/features/user-management/` y `panel/src/application/userManagementService.ts`: demo local de gestión de usuarios que debe reemplazarse en el slice Web.
