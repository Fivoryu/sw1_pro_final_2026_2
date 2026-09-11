# Exploración — HU-003: verificación de correo

## Identificación y trazabilidad

- **Cambio:** `hu003-verificacion-correo`
- **Producto:** RoomForge, SW1 2026-2, Grupo #12.
- **Historia:** **HU-003** — Como cliente, quiero verificar mi correo real con un enlace de activación.
- **Product Backlog:** **PB-003**, prioridad Must, complejidad M, Sprint 3.
- **Caso de uso:** **CU-003**, verificación de correo real con enlace de activación.
- **Requisito funcional:** **RF-033**, verificación con enlace de activación de un solo uso y reenvío acotado; reemplaza el modo de correo cualquiera en la demo final.
- **Regla de seguridad relacionada:** **RNF-017**, enlaces de activación de un solo uso y nunca contraseñas por correo.
- **Regla de negocio a confirmar:** la matriz vincula la identidad (incluido RF-033) con **BR-001..022**, pero el texto individual aplicable a activación no está desglosado en la evidencia disponible (**GAP-HU003-001**).
- **Sprint:** la planificación vigente ubica PB-003/HU-003/CU-003 en **SP-03** (**Sprint 3**).

## Método y fuentes verificadas

La exploración fue de solo lectura sobre el producto y las convenciones. Se consultaron:

- `README.md` y `AGENTS.md`: monorepo con backend, panel y apps como submódulos; la documentación de Ingeniería de Software se redacta en español y el código usa identificadores en inglés.
- `openspec/config.yaml` y `openspec/project-context.md`: almacén híbrido, flujo SDD, pruebas y herramientas declaradas, y restricciones de no modificar HU-004/HU-005/HU-006.
- `docs/sprint-0/ids-trazabilidad.md`: fuente de los IDs, RF-033, PB-003, HU-003, CU-003 y distribución de Sprint 3.
- `docs/scrum/sprint-0-requerimientos/04-requerimientos-iniciales.md`: RF-033 y RNF-017 en formato de requisitos. La ruta exacta fue validada mediante la búsqueda documental; el archivo equivalente de referencia contiene la fila citada.
- `backend/app/modules/identity/{models,schemas,repository,service,router}.py`, `backend/app/main.py`, `backend/app/core/config.py` y `backend/alembic/versions/0001_crear_usuario_global.py`/`0002_crear_sesion.py`.
- `backend/tests/test_registro.py` y `backend/tests/test_autenticacion.py`.
- `apps/cliente_mobile/lib/data/services/auth_api_service.dart`, `lib/domain/models/auth_models.dart` y `lib/ui/features/auth/views/register_screen.dart`.
- Superficie existente de HU-004: `backend/app/modules/tenant/{service,repository,router,ports}.py`, sus pruebas y la configuración de activación. Se trata como dependencia/conocimiento reutilizable, no como implementación de HU-003.

No se ejecutaron tests, migraciones, builds ni comandos que muten el repositorio.

## Hechos observados

### Backend y persistencia

1. El router de identidad publica `POST /api/v1/auth/registro`, `POST /api/v1/auth/login`, refresh, logout y `GET /api/v1/auth/me`.
2. `UsuarioGlobal` ya contiene `correo_verificado` (`Boolean`, obligatorio, default `false`), correo único, estado y fecha de creación. La migración `0001` crea esas columnas; no existe en las fuentes consultadas una tabla o migración específica de tokens de verificación para clientes.
3. `IdentityService.registrar` normaliza el correo, hashea la contraseña con el componente de seguridad y crea el usuario con `estado="activo"` y `correo_verificado=False`.
4. El login solo comprueba credenciales y `estado == "activo"`; no comprueba `correo_verificado`. Por tanto, actualmente el registro no dispara un envío de activación y una cuenta no verificada puede autenticarse si sus credenciales son válidas.
5. `Settings` ya expone `activation_ttl_days`, con default de 7 días. La evidencia de su uso está en la activación de onboarding de HU-004, no en la identidad de HU-003; no debe asumirse que resuelve el contrato de correo del cliente.
6. HU-004 ya tiene un patrón de activación separado: genera un token crudo efímero, persiste SHA-256, entrega mediante un puerto `ActivationNotifier` después de persistir y consume de forma condicional con respuesta genérica para token inválido/expirado/consumido. Ese patrón es una referencia técnica potencial, pero su entidad, actor, rutas y transacción pertenecen a onboarding y no deben reutilizarse sin revisar el aislamiento de dominios.

### Cliente móvil y superficies de interfaz

1. La app cliente ya integra registro, login, refresh, logout y consulta de sesión a través de `AuthApiService`; el contrato actual de registro espera una `RegistrationResult` con `correo_verificado`.
2. `RegisterScreen` registra la cuenta y navega directamente a `/login` cuando la API responde correctamente. No hay evidencia de una pantalla, deep link o flujo de activación de correo.
3. La búsqueda en `panel/` no encontró coincidencias de verificación de correo. El panel está documentado como estructura inicial, por lo que no es una superficie confirmada para esta HU.
4. No se encontró en las superficies consultadas un proveedor concreto SMTP/API, outbox de correo, plantilla, URL pública de activación o mecanismo de deep linking para el cliente.

### Calidad y convenciones

1. El proyecto declara modo TDD estricto y runner `.venv/Scripts/python.exe -m pytest backend/tests -q`, además de Ruff y Pyright.
2. Las pruebas actuales cubren registro, normalización, unicidad, hash y autenticación, incluyendo que el registro devuelve `correo_verificado: false`; no cubren generación, entrega, expiración o consumo de activación de cliente.
3. La documentación exige conservar IDs estables, separar evidencia de gaps y no inventar resultados.

## Inferencias razonables

- La implementación probablemente tendrá impacto primario en el backend de identidad y en `apps/cliente_mobile`; el panel no es necesario para el primer slice salvo que el equipo decida exponer una ruta web de activación.
- El diseño necesita una credencial aleatoria de un solo uso cuya representación persistida no permita recuperar el token original. La comparación/consumo debe ser atómica para evitar doble uso y debe ocultar si el token fue inexistente, expiró o ya fue consumido.
- Si la política de producto exige correo verificado para iniciar sesión, el comportamiento actual de login deberá cambiar y los tests existentes de registro/autenticación deberán actualizarse con una transición explícita. Esa política no está escrita de manera suficiente en RF-033 y es una decisión pendiente, no un hecho.
- El reenvío acotado requiere definir límites, invalidación de tokens anteriores, respuesta frente a correos inexistentes y control de abuso. RF-033 menciona reenvío, pero no fija esos parámetros.
- La entrega de correo debe desacoplarse del caso de uso y no dejar una cuenta parcialmente creada por un fallo del proveedor; el comportamiento exacto (outbox, entrega posterior al commit o modo demo) requiere decisión técnica y operativa.

## Superficies candidatas y dependencias

| Superficie | Estado actual | Posible responsabilidad HU-003 | Dependencias |
| --- | --- | --- | --- |
| `backend/app/modules/identity` | Implementado para registro/autenticación | Modelo/repo/servicio/router de activación; política de login; pruebas | `UsuarioGlobal`, reloj, configuración, persistencia SQLAlchemy/Alembic |
| `backend/app/core/config.py` | Configuración existente; TTL usado por HU-004 | URL pública, TTL/límites y configuración del proveedor, si se aprueban | Seguridad de secretos, entorno demo |
| `backend/alembic/versions` | Migraciones 0001/0002 de identidad/sesión y posteriores de HU-004 | Nueva migración aditiva para token/estado, si el diseño lo confirma | PostgreSQL, downgrade y compatibilidad con HU-004/005/006 |
| `backend/tests` | Tests de identidad y onboarding | RED/GREEN para ciclo válido, expirado, consumido, reenvío, concurrencia y regresión | Dobles de reloj/repositorio/notificador y eventualmente PostgreSQL |
| `apps/cliente_mobile` | Registro/login integrados | Estado y UX de “revisá tu correo”, activación por enlace/deep link y reenvío | Contrato HTTP, routing/deep links, plataforma Android |
| `panel` | Estructura inicial, sin coincidencias | No requerido por evidencia actual | Solo si se decide activación web |
| Proveedor/outbox de correo | No identificado | Entrega real, plantillas, observabilidad y reintentos | Investigación/decisión del equipo |

## Riesgos

- **R-HU003-01 — Seguridad del token (alto):** filtrar tokens en logs, respuestas o base de datos permitiría activar cuentas ajenas. Mitigar con token aleatorio, hash persistido, TTL, uso único y respuestas genéricas.
- **R-HU003-02 — Política de acceso no definida (alto):** permitir login antes de verificar contradice el objetivo de correo real; bloquearlo puede romper los contratos/test actuales. Requiere decisión explícita.
- **R-HU003-03 — Entrega externa (alto):** SMTP/API, credenciales, límites y fallos no están identificados. La demo necesita un mecanismo real o una estrategia de proveedor local documentada.
- **R-HU003-04 — Reenvío y abuso (medio/alto):** sin rate limit, cooldown y respuesta anti-enumeración puede usarse para spam o descubrir cuentas.
- **R-HU003-05 — Atomicidad/concurrencia (alto):** dos consumos simultáneos podrían activar dos veces o producir estados inconsistentes si no hay actualización condicional/bloqueo.
- **R-HU003-06 — Compatibilidad multi-HU (medio/alto):** compartir tablas, nombres o puertos con la activación de HU-004 puede acoplar dominios y afectar HU-005/HU-006. Debe conservarse la separación y probarse la regresión.
- **R-HU003-07 — Deep link (medio):** no hay ruta móvil confirmada para abrir el enlace y completar la activación.

## Preguntas de aceptación que bloquean el diseño

1. ¿La cuenta puede iniciar sesión mientras `correo_verificado` es `false`, o el login debe responder una condición específica hasta activar?
2. ¿Cuál es el contrato HTTP exacto para solicitar/re-enviar activación y consumir el enlace? ¿Se activa desde la app móvil, desde una página web o desde ambas?
3. ¿Qué TTL, cooldown, máximo de reenvíos por cuenta/IP y política de invalidación de tokens anteriores se desea para la demo? El valor de 7 días existe en configuración de HU-004, pero no está aprobado para HU-003.
4. ¿Qué proveedor real o servicio local se utilizará, y qué evidencia demostrará que el mensaje fue entregado sin guardar secretos en el repositorio?
5. ¿La activación debe crear una sesión/redirigir al login, o solo cambiar `correo_verificado` y devolver un resultado neutro?

## Alcance propuesto para la siguiente fase

### Incluido tentativamente

- Flujo backend de emisión, persistencia segura, expiración, consumo único y reenvío acotado para el usuario global de HU-003.
- Integración con un puerto de correo real o adaptador definido por decisión de producto, sin exponer secretos.
- Ajuste del contrato de autenticación únicamente si se decide exigir verificación para login.
- Flujo mínimo en la app cliente para informar el estado y abrir/consumir el enlace, si el equipo confirma esa superficie.
- Pruebas TDD y migración aditiva con regresión de identidad y aislamiento de HU-004/HU-005/HU-006.

### No incluido

- Activación de administradores/invitaciones de HU-004.
- Onboarding, trial, suscripción, roles, memberships, tenants o RBAC.
- Notificaciones generales multi-canal de PB-044; solo el envío necesario para la activación, si se aprueba.
- Panel web completo, recuperación de contraseña, cambio de correo, MFA y gestión general de perfiles.
- Cambios en `docs/diagramas/Diagrama1.eapx`, backend remoto, commits o push.

## Gaps y necesidad de investigación

- **GAP-HU003-001:** BR-001..022 no están desglosadas para activar esta historia.
- **GAP-HU003-002:** no existe contrato de endpoint, códigos HTTP ni formato de respuesta para activación/reenvío.
- **GAP-HU003-003:** proveedor, credenciales/configuración, plantilla y evidencia de entrega no están definidos.
- **GAP-HU003-004:** deep link/ruta de activación móvil no está definido.
- **GAP-HU003-005:** política de login con correo no verificado y comportamiento de cuentas existentes no están definidos.
- **GAP-HU003-006:** TTL y límites de reenvío de HU-003 no están aprobados.

**Investigación recomendada: sí, antes del diseño definitivo.** Debe ser breve y dirigida a (a) proveedor/local delivery compatible con la demo, (b) deep linking de Flutter/Android, y (c) decisiones de seguridad/anti-abuso y contrato HTTP. No se recomienda investigar tecnologías de negocio ajenas al flujo.

## Resultado de exploración

La base existente aporta identidad, `correo_verificado`, reloj/configuración y patrones de activación seguros en HU-004, pero **HU-003 no está implementada**: faltan persistencia específica, endpoints, entrega de correo, consumo para cliente, UX/deep link y criterios de aceptación cerrados. La siguiente fase debe convertir las preguntas y gaps anteriores en una propuesta aprobable, preservando la trazabilidad PB-003 → HU-003 → CU-003 → RF-033 → Sprint 3 y la independencia de HU-004.
