# Propuesta — Alta de inmobiliaria (HU-004)

- **Cambio:** `hu004-alta-inmobiliaria`
- **Product Backlog:** PB-004
- **Historia:** HU-004 — Alta de inmobiliaria
- **Caso de prueba:** CP-003
- **Prioridad:** Alta
- **Estimación de referencia:** 8 PHU
- **Idioma:** español profesional y neutral
- **Alcance técnico:** backend y contrato API consumible
- **Límite:** máximo 600 líneas modificadas
- **Estado de evidencia:** propuesta; no se han ejecutado pruebas ni se declara finalización de UI

## 1. Intención

Completar el slice backend-first de HU-004 para que una inmobiliaria pueda seleccionar un plan mensual aprobado, confirmar un checkout claramente simulado y ser aprovisionada únicamente cuando el backend reciba y verifique un evento firmado. El resultado debe exponer un contrato API consumible por el panel Web, sin implementar el panel visual en este cambio.

La propuesta separa deliberadamente dos momentos del negocio:

1. **Checkout simulado:** confirma la intención de contratación y hace observables el plan, el monto en BOB y la confirmación. No crea un tenant ni sus efectos asociados.
2. **Evento firmado:** constituye la frontera de confianza para el aprovisionamiento. Solo un evento auténtico, íntegro, correlacionado y procesado de forma idempotente puede crear el tenant y sus recursos iniciales.

El primer administrador recibirá un flujo mínimo de activación mediante un enlace o token de un solo uso, con expiración y almacenamiento hasheado. No se implementan todavía invitaciones completas de agentes, membresías generales ni RBAC de HU-007.

## 2. Problema y brecha actual

La implementación existente registra el módulo `tenant` y dispone de `POST /api/v1/tenant/alta`, pero el contrato actual mezcla la selección del plan, la confirmación y un supuesto `payload_firmado` en una misma operación. El servicio almacena el payload indicado, aunque la exploración no encontró un verificador de firma observable. En consecuencia, la ruta actual no demuestra que el aprovisionamiento esté protegido por una frontera de evento firmado.

También se identificaron estas brechas:

- La comprobación previa de un evento y su inserción tienen una carrera TOCTOU; la unicidad existente no define por sí sola la respuesta de un reintento concurrente ni el conflicto de una misma clave con otro payload.
- Los planes no tienen datos semilla reproducibles en la migración existente y el contrato de datos necesita una cuota explícita de agentes.
- La invitación actual conserva correo y hash de token, pero no formaliza una relación con `usuario_global` ni una membresía; solo puede definirse para HU-004 la relación mínima entre tenant, invitación pendiente y correo del primer administrador.
- No se encontraron pruebas específicas de tenant, checkout o idempotencia para CP-003. CP-003 permanece `not executed`.
- El código de HU-005 y HU-006 existe en la rama de referencia, pero no constituye alcance autorizado para este cambio.

## 3. Resultado de negocio esperado

Al finalizar el cambio:

- El consumidor Web podrá consultar/seleccionar un plan aprobado y mostrar su nombre, monto mensual en BOB, cuotas y confirmación del checkout simulado mediante un contrato estable.
- La confirmación no producirá un tenant prematuramente ni permitirá saltar la verificación del evento.
- Un evento firmado válido producirá un alta observable y atómica: tenant, suscripción inicial, registro del evento e invitación pendiente del primer administrador.
- Reprocesar el mismo evento, incluso concurrentemente, no creará un segundo tenant ni una segunda invitación/suscripción.
- El primer administrador podrá recibir un enlace/token de activación de un solo uso, expirable y no reversible, sin que se envíe o persista una contraseña.
- Las funciones visuales del panel Web podrán implementarse posteriormente contra el contrato, sin que esta fase prometa una pantalla terminada.

## 4. Alcance de la primera entrega

### 4.1 Checkout simulado

Se definirá un contrato de checkout que reciba la selección de un plan activo y devuelva, como mínimo, una referencia de operación, el identificador y nombre del plan, el monto mensual en BOB y un estado de confirmación. El monto debe provenir del catálogo del servidor y utilizar una representación monetaria que no dependa de `float`.

El checkout deberá generar una referencia correlacionable con el evento posterior y conservar únicamente la intención mínima necesaria para validarlo. La forma exacta de persistir esa intención se resolverá en diseño sin introducir una integración de pagos real.

### 4.2 Frontera de evento firmado

Se definirá una operación backend independiente para recibir el evento del simulador. La verificación de autenticidad e integridad ocurrirá antes de modificar estado o persistir efectos de negocio. El evento deberá identificarse de manera única, corresponder a la intención/plan seleccionado y no confiar en un `tenant_id`, monto o cuota enviados por el cliente sin validación contra el catálogo y la correlación del checkout.

La ruta HTTP, headers, algoritmo, canonicalización y formato exacto de la firma permanecen como decisión técnica pendiente `GAP-004-API-001`; deberán cerrarse en spec/design antes de tasks. La separación conceptual entre checkout y evento firmado sí queda aprobada por esta propuesta.

### 4.3 Aprovisionamiento atómico

Después de una verificación válida, el caso de uso creará en una única transacción:

- `Tenant` de la inmobiliaria;
- suscripción inicial asociada al plan aprobado;
- registro del evento de facturación y su resultado;
- invitación pendiente del primer administrador.

La respuesta deberá exponer el identificador y estado necesarios para el consumidor API, sin devolver el token crudo, el payload sensible ni secretos.

### 4.4 Activación mínima del primer administrador

La invitación estará asociada al tenant y al correo normalizado del primer administrador, con estado pendiente, expiración, hash del token y marca de consumo o equivalente. El token crudo solo podrá entregarse al adaptador de notificación simulado/integrable y no se devolverá en respuestas ni se registrará en logs.

Este cambio no crea el sistema completo de membresías. Queda explícitamente fuera la decisión detallada sobre si la activación debe reutilizar o crear una cuenta `usuario_global`, cómo se materializa la membresía y qué rol persistente tendrá el usuario; se registra como `GAP-004-DOM-001` para HU-007 o una fase posterior. La relación mínima de HU-004 será suficiente para identificar al primer administrador pendiente y vincularlo al tenant sin habilitar RBAC general.

### 4.5 Catálogo de planes y contrato de cuotas

Los planes mensuales aprobados para el demo son:

| Plan | Monto mensual | Agentes | Almacenamiento | Inmuebles activos | Reconstrucciones/mes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Básico | 199 BOB | 5 | 50 GB | 5 | 10 |
| Profesional | 449 BOB | 15 | 200 GB | 20 | 40 |
| Empresarial | 899 BOB | 50 | 1.000 GB | 100 | 150 |

Todos comparten las funciones centrales; las diferencias de esta entrega son sus cuotas. El administrador no consume el cupo de agentes. El contrato de datos deberá incorporar explícitamente el nuevo campo de cuota de agentes, propuesto como `max_agents`, además de mantener las cuotas de almacenamiento, inmuebles y reconstrucciones. `GAP-061` queda cerrado por esta decisión de producto.

### 4.6 Contrato consumible y regresión

Se documentarán los esquemas de request/response y estados observables necesarios para que el panel Web consuma el checkout y el resultado del alta. Se mantendrá una frontera delgada router → service → repository, con reloj inyectable para expiraciones y seams de repositorio/notificación para pruebas.

La regresión se limitará a asegurar que el cambio no altere rutas ni lógica de HU-005 y HU-006. No se ampliarán esas historias.

## 5. Fuera de alcance y no objetivos

- Panel visual Web, navegación, copy, componentes React/TypeScript o prototipos de UI.
- Aplicación Flutter.
- Pagos reales, proveedor externo de checkout o facturación productiva.
- HU-005: trial y suscripción mensual.
- HU-006: cambio de plan, cancelación, aplicación de cuotas y purga.
- Invitaciones de agentes, aceptación de agentes, membresías completas y RBAC de HU-007.
- Verificación productiva de correo, proveedor de notificaciones real y recuperación de cuentas.
- S3/SQS, workers 3D, catálogo inmobiliario, publicaciones, auditoría completa y otras superficies no necesarias para HU-004.
- Reestructuración general del módulo tenant o corrección de funcionalidades existentes de HU-005/HU-006 que no sea necesaria para proteger HU-004.

## 6. Criterios de éxito HU-004 / CP-003

La entrega se considerará apta para verificación cuando la evidencia automatizada y de contrato demuestre:

| Criterio | Resultado observable |
| --- | --- |
| CA1 / CP-003.1 — Checkout | El consumidor selecciona un plan activo y recibe nombre, monto mensual en BOB, referencia y confirmación del checkout simulado; no se crea tenant por esta acción. |
| CA2 / CP-003.2 — Evento firmado | Un evento válido y firmado, asociado al checkout y al plan correcto, aprovisiona los recursos iniciales. Un evento ausente, inválido o alterado no aprovisiona ni deja efectos de negocio. |
| CA3 / CP-003.3 — Idempotencia | Repetir el mismo evento, de forma secuencial o concurrente, produce como máximo un tenant, una suscripción, una invitación y un registro lógico del evento. La misma clave con payload diferente se rechaza de forma explícita. |
| CA4 / CP-003.4 — Primer administrador | Se genera una activación pendiente de un solo uso, con expiración y hash persistido; el token no se expone ni se almacena en claro y no se acepta después de consumido o expirado. |
| Contrato de planes | Los tres planes y sus cuotas aprobadas son reproducibles; `max_agents` está disponible en el contrato y el administrador no reduce esa cuota. |
| Regresión y límites | No se modifica el comportamiento funcional de HU-005/HU-006 ni se incorpora UI visual en este cambio. |

CP-003 figura actualmente como `not executed`; estos son criterios de aceptación y evidencia esperada, no resultados ya obtenidos.

## 7. Áreas afectadas y límites de integración

### Backend y API

- `backend/app/modules/tenant/router.py`: separar las operaciones de checkout y evento, manteniendo el router delgado.
- `schemas.py`: contratos de selección, confirmación, evento firmado y respuestas sin secretos.
- `service.py`: reglas de negocio, verificación previa, correlación, aprovisionamiento y semántica de duplicados.
- `repository.py`: transacción, constraints y recuperación segura del resultado original en reintentos.
- `models.py` y migraciones Alembic: cuota de agentes, referencias de checkout/evento e invariantes persistentes mínimas.
- OpenAPI generado por FastAPI: superficie consumible por el panel Web.

### Datos y persistencia

El contrato del plan deberá representar como mínimo `plan_id`, nombre, monto BOB, `max_agents`, almacenamiento, inmuebles activos, reconstrucciones mensuales y estado activo. Las entidades tenant, suscripción, invitación y evento deberán conservar sus relaciones, unicidades y estados coherentes. El diseño debe revisar la representación de importes `Numeric(10,2)` frente a `Mapped[float]` y la consistencia entre modelos y migración.

### Identidad

El checkout y el receptor del evento son actores distintos. El router actual no exige autenticación; decidir si el simulador es público o autenticado queda como `GAP-004-AUTH-001`. Ningún `tenant_id` suministrado por el cliente será una autorización. Para HU-004 solo se define la invitación pendiente del primer administrador; identidad global, membresía y roles quedan diferidos.

### Panel Web

El panel Web es consumidor posterior. Esta fase solo debe dejar disponibles plan, monto, confirmación y estado de alta mediante API; no se implementa ni se afirma una experiencia visual completa (`GAP-004-UI-001`).

## 8. Invariantes de seguridad e idempotencia

1. La confirmación de checkout nunca aprovisiona por sí sola.
2. La firma se valida antes de cualquier cambio de estado o persistencia de efectos de negocio.
3. El evento debe ser auténtico, íntegro, correlacionado con el checkout y compatible con un plan activo; no se confían montos o cuotas arbitrarios del cliente.
4. No se reciben, generan ni envían contraseñas como parte del alta.
5. El token de activación se genera una sola vez para la entrega, se persiste únicamente como hash, expira y se consume una sola vez.
6. Tokens crudos, secretos de firma y payloads sensibles no aparecen en respuestas ni logs.
7. La unicidad del identificador del evento/idempotencia se refuerza en persistencia y dentro de la transacción; el patrón check-then-insert aislado no es suficiente.
8. El mismo evento repetido devuelve un resultado idempotente o el estado original, sin crear nuevos recursos. Una misma clave asociada a un payload distinto produce conflicto explícito.
9. Un fallo de cualquier inserción revierte el conjunto: no quedan tenant, suscripción, invitación o evento parcialmente creados.
10. La futura autorización multi-tenant no se anticipa usando identificadores enviados por el cliente.

## 9. Migración y datos semilla

La migración existente `0003_crear_tablas_tenant.py` crea las tablas principales, pero no carga planes. La implementación deberá:

- añadir el campo de cuota de agentes y cualquier referencia mínima que el diseño justifique;
- cargar o actualizar de forma reproducible los tres planes aprobados, con operación idempotente y sin duplicar catálogos;
- preservar compatibilidad con datos existentes y revisar nulabilidad, defaults, UUID, fechas y restricciones;
- validar la precisión del monto y la serialización JSON;
- incluir downgrade seguro, respetando el orden de claves foráneas y evitando eliminar datos de tenants ya aprovisionados;
- verificar la ejecución real de Alembic en el entorno disponible antes de declarar la migración operativa. El riesgo de PostgreSQL/migraciones reales queda relacionado con `GAP-092`.

No se agregan datos de planes de HU-005/HU-006 ni reglas de cuotas operativas más allá de exponer el catálogo aprobado para HU-004.

## 10. Riesgos y gaps explícitos

| ID | Riesgo o gap | Mitigación o decisión requerida |
| --- | --- | --- |
| `GAP-004-API-001` | No están definidos ruta, headers, algoritmo, canonicalización ni formato de firma. | Cerrar el contrato técnico en spec/design antes de tasks; probar firma válida, ausente, inválida y payload alterado. |
| `GAP-004-IDEM-001` | La implementación actual tiene carrera y no define el conflicto de payload ni la respuesta del duplicado. | Usar unicidad y transacción como autoridad; comparar representación/hash canónico y definir respuestas para repetición y conflicto. |
| `GAP-004-DOM-001` | No existe relación formal tenant–`usuario_global`/membresía para el administrador. | Limitar HU-004 a tenant + invitación pendiente + correo; dejar creación/reutilización de usuario y membresía como gap nombrado para HU-007. |
| `GAP-004-NOTIF-001` | No está definido el canal de entrega del enlace. | Implementar un adaptador simulado/inyectable y no filtrar el token por API; dejar correo productivo para una fase posterior. |
| `GAP-004-AUTH-001` | No está decidido si el checkout del simulador es público o autenticado. | Resolver el actor y la política de acceso en spec; no mezclar identidad del iniciador con el receptor del evento. |
| `GAP-004-UI-001` | No existe contrato visual o de navegación Web verificable. | Mantener la entrega backend/API; documentar solo el contrato consumible. |
| `GAP-092` | PostgreSQL y Alembic no están verificados en una ejecución real de esta exploración. | Ejecutar gates de migración durante verify y reportar cualquier limitación del entorno. |
| Presupuesto | El código existente de HU-005/HU-006 puede inducir refactor o alcance adicional. | Mantener una lista de archivos y tareas estrictamente HU-004; si el pronóstico supera 600 líneas, reducir o dividir antes de apply. |

## 11. Estrategia de pruebas y evidencia

Se aplicará TDD estricto. Primero se escribirán pruebas de contrato/API y de servicio usando `FakeTenantRepository`, `FakeClock`, dependencias sobreescritas y un adaptador de notificación controlado, siguiendo los seams de los cambios archivados. Después se implementará el mínimo código necesario.

La evidencia prevista incluye:

- prueba del checkout con plan, monto BOB, referencia y confirmación, verificando ausencia de aprovisionamiento;
- firma válida y casos de firma ausente, inválida o alterada;
- correlación de checkout, plan activo y datos del evento;
- atomicidad ante fallas de inserción;
- repetición secuencial y concurrente del evento;
- conflicto por misma clave con payload diferente;
- hash, expiración, consumo único y no exposición del token de activación;
- validación de plan inexistente/inactivo;
- regresión de rutas/lógica de HU-005 y HU-006;
- migración upgrade/downgrade en el entorno disponible y validación de esquema.

Los gates declarados por el proyecto son, desde la raíz:

```text
.venv/Scripts/python.exe -m pytest backend/tests -q
.venv/Scripts/python.exe -m ruff check backend/app backend/tests
.venv/Scripts/pyright.exe backend/app backend/tests
.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head
```

Estos comandos son estrategia de evidencia; no se ejecutaron durante la exploración ni esta propuesta afirma resultados.

## 12. Presupuesto y control de alcance

El cambio tiene un máximo de **600 líneas modificadas**. El presupuesto cubre únicamente contratos, lógica backend, modelos/migración, seed reproducible y pruebas de HU-004. No incluye UI ni refactor de HU-005/HU-006. Las tareas deberán agrupar cambios por el slice completo y revisar el pronóstico antes de implementar; una previsión superior al límite exige reducir alcance o una decisión explícita de entrega antes de continuar.

## 13. Rollback

El rollback operativo será conservador y no dependerá de borrar datos de onboarding:

1. Deshabilitar la recepción/procesamiento del evento firmado si se detecta un defecto, dejando de crear nuevos efectos.
2. Revertir la versión de aplicación a la versión anterior compatible y conservar los registros ya creados para trazabilidad.
3. No ejecutar un downgrade destructivo sobre una base con tenants, suscripciones, invitaciones o eventos nuevos; primero respaldar y verificar dependencias. En producción, una migración aditiva se revierte preferentemente mediante forward-fix.
4. En una base vacía o de prueba, ejecutar el downgrade solo después de validar el orden de FKs y la eliminación de seeds.
5. Al restablecer la versión corregida, reprocesar eventos válidos con la misma clave, confiando en la idempotencia para no duplicar recursos.

No se ha realizado ningún rollback; es el procedimiento previsto para la entrega.

## 14. Trazabilidad y fuentes

- `openspec/changes/hu004-alta-inmobiliaria/explore.md`: evidencia del módulo actual, CP-003, seams, límites, riesgos y gaps.
- `openspec/project-context.md`: stack, idioma, TDD estricto, comandos de calidad, arquitectura y restricciones.
- `openspec/config.yaml`: alcance HU-004, exclusión de HU-005/HU-006, modo híbrido y límite de 600 líneas.
- `docs/scrum/sprint-1/01-sprint-planning.md`: HU-004, prioridad, estimación y criterios de aceptación.
- `docs/scrum/sprint-1/02-proceso-por-hu.md`: CP-003 y su estado `not executed`.
- `docs/sprint-0/auditoria-br.md`: BR-B1, BR-B2, BR-B3 y reglas relacionadas.
- `backend/app/modules/tenant/` y `backend/alembic/versions/0003_crear_tablas_tenant.py`: contratos, persistencia y migración existentes.
- Observación Engram `sdd/hu004-alta-inmobiliaria/plan-pricing`: decisión aprobada de planes, cuotas y exclusión del administrador del cupo de agentes.

La siguiente fase debe convertir esta intención en especificaciones verificables y cerrar los gaps técnicos críticos, sin ampliar el alcance hacia HU-005, HU-006 ni la UI visual.
