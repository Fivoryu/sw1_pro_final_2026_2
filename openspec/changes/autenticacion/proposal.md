# Propuesta: Autenticación y sesión del cliente

- **Cambio:** `autenticacion`
- **Product Backlog:** PB-002
- **Historia:** HU-002 — Iniciar sesión y mantener sesión
- **Slice:** backend
- **Estado:** propuesta

## Problema y contexto

PB-001 deja disponible la cuenta global del cliente, pero todavía no existe el mecanismo que permita usarla de forma segura en los flujos posteriores. La app cliente necesita una sesión persistente para acceder al catálogo; sin login, renovación y cierre de sesión, el registro no habilita una continuidad de uso verificable.

La continuidad con PB-001 es deliberada: el nuevo slice reutiliza la cuenta `usuario_global`, la búsqueda por correo y la verificación Argon2id ya implementadas. Se propone entregar primero el contrato y la lógica backend, igual que en PB-001, para que la sesión pueda probarse sin depender de una pantalla cliente ni de un PostgreSQL disponible durante las pruebas unitarias.

La HU-002 es de prioridad Alta, está estimada en 8 PHU y define cuatro resultados observables: credenciales válidas emiten access y refresh; el refresh rota y puede revocarse; la sesión queda inválida tras 30 minutos de inactividad; y las credenciales inválidas producen un error genérico que no permite inferir si existe una cuenta.

## Usuarios y actores

- **Cliente global:** inicia sesión, mantiene actividad autenticada y cierra su sesión para acceder posteriormente al catálogo.
- **Backend de RoomForge:** valida credenciales, emite y renueva tokens, controla la inactividad y revoca sesiones.
- **Base de datos:** conserva la autoridad revocable de las sesiones mediante la tabla `sesion`.

## Objetivos

1. Permitir que un cliente registrado se autentique mediante correo y contraseña usando la verificación Argon2id reutilizada de PB-001.
2. Emitir un access token JWT de corta duración y un refresh token opaco asociado a una fila revocable de `sesion`.
3. Rotar atómicamente el refresh token, invalidar el anterior y rechazar tokens revocados, expirados o inactivos.
4. Mantener la sesión mediante una ventana deslizante server-side de 30 minutos, actualizando `ultima_actividad` ante actividad autenticada.
5. Exponer `GET /api/v1/auth/me` como ruta protegida mínima para demostrar el estado autenticado, sin adelantar la implementación del catálogo.
6. Cubrir CP-002 con pruebas TDD basadas en fakes y `dependency_overrides`, sin exigir PostgreSQL para el primer slice.

## Alcance

### Alcance incluido

- Migración Alembic `0002_crear_sesion.py`, siguiendo el patrón de `0001_crear_usuario_global.py` y con `down_revision="0001"`.
- Modelo `Sesion` con el esquema lógico previsto en S1-02 §2.1.2.2:
  - `id` UUID como clave primaria.
  - `usuario_global_id` como FK a `usuario_global.id`.
  - `refresh_token_hash` `CHAR(64)` único, almacenado como hash SHA-256 hexadecimal.
  - `expira_en` y `ultima_actividad` como `TIMESTAMPTZ`.
  - `revocado` booleano con valor predeterminado falso.
  - índice por `usuario_global_id` y `revocado`.
- Protocolo e implementación de `SessionRepository` para crear sesiones, buscar por hash, rotar/revocar, actualizar actividad y rechazar sesiones inválidas.
- Servicio de tokens en `app/core/`:
  - access JWT firmado con HS256, con al menos `sub`, `type`, `iat` y `exp`.
  - refresh opaco generado con `secrets.token_urlsafe`; nunca se persiste en texto claro.
  - hash SHA-256 del refresh para comparar con `refresh_token_hash`.
- Nuevos settings configurables para el secreto JWT, TTL del access, TTL del refresh y ventana de inactividad.
- Endpoints:
  - `POST /api/v1/auth/login`: devuelve access, refresh y expiración cuando las credenciales son válidas; responde 401 con el mismo error genérico para correo inexistente y contraseña incorrecta.
  - `POST /api/v1/auth/refresh`: valida la sesión, revoca el refresh recibido y emite un nuevo par de tokens.
  - `POST /api/v1/auth/logout`: revoca el refresh activo recibido.
  - `GET /api/v1/auth/me`: requiere un access válido y aplica el control de sesión/inactividad definido para este slice.
- Pruebas TDD con fakes y `TestClient`, cubriendo los cinco pasos de CP-002 y la rotación del refresh:
  1. login válido emite access + refresh;
  2. credenciales inválidas no distinguen correo inexistente de contraseña incorrecta;
  3. actividad autenticada antes de 30 minutos mantiene la sesión y actualiza `ultima_actividad`;
  4. más de 30 minutos sin actividad invalida la sesión y exige autenticación;
  5. logout revoca el refresh y su reutilización es rechazada.
- Trazabilidad posterior en spec, tasks y documentación de Sprint 1 con los IDs PB-002, HU-002, RF-002, RNF-006, CP-002 y CU-002.

## Decisiones propuestas

### 1. Slice backend-first

Se mantiene el mismo orden de entrega de PB-001: primero persistencia, contrato API, servicios y pruebas. Esto permite validar la regla de negocio y la seguridad de la sesión antes de acoplar una UI. La app cliente podrá consumir el contrato cuando exista su slice de interfaz.

### 2. PyJWT y modelo de tokens

Se recomienda agregar **PyJWT 2.x** como dependencia mínima. `pyproject.toml` no contiene actualmente PyJWT, `python-jose`, `authlib` ni otra librería JWT. PyJWT resuelve específicamente la firma y validación del JWT sin introducir un framework adicional, tiene una API pequeña y mantiene alineación directa con RF-002 (`Argon2id + JWT/refresh`).

No se recomienda reemplazar ambos tokens por tokens opacos: contradice la mención explícita de JWT en RF-002 y elimina el beneficio del access token autocontenido. Tampoco se recomienda usar JWT para el refresh: el diseño lógico de `sesion` exige `refresh_token_hash CHAR(64) UNIQUE`, que representa un refresh opaco hasheado.

El modelo propuesto es, por tanto:

- **Access:** JWT HS256, corto, firmado con un secreto configurable y validado por `exp` y el tipo `access`. Contiene la identidad mínima necesaria (`sub`, `type`, `iat`, `exp`); el vínculo exacto con la sesión para aplicar revocación/inactividad se deberá conservar en la implementación del servicio y quedar cubierto por CP-002.
- **Refresh:** valor opaco aleatorio, almacenado únicamente como SHA-256 hexadecimal. Cada refresh aceptado se revoca y se reemplaza por uno nuevo dentro de una operación transaccional. El refresh anterior no puede reutilizarse.
- **Autoridad de sesión:** la tabla `sesion` es la autoridad para revocación, expiración absoluta e inactividad. No se agrega Redis ni una estrategia stateless alternativa en este cambio.

### 3. TTL y ventana de inactividad

Se proponen los siguientes valores configurables:

- **Access JWT: 15 minutos.** Es menor que el límite de inactividad de 30 minutos, reduce la ventana de exposición de una credencial de acceso y obliga a renovar mediante el refresh antes de prolongar la sesión. Sigue cumpliendo RF-002, que exige JWT/refresh y cierre por inactividad de 30 minutos.
- **Refresh: 7 días.** Permite continuidad de uso sin pedir credenciales en cada visita, pero limita la vida absoluta del artefacto de renovación. `expira_en` se persiste en `sesion` y se verifica server-side junto con `revocado`.
- **Inactividad: 30 minutos, server-side y sliding window.** La regla proviene de RNF-006 y RF-002. `ultima_actividad` se actualiza cuando una actividad autenticada válida —incluida la renovación válida— ocurre dentro de la ventana. Pasados 30 minutos sin actividad, la sesión se revoca o se trata como inválida y el cliente debe autenticarse otra vez. Se elige sliding y no fixed window porque la ficha CP-002 indica que la actividad debe quedar considerada para el control de inactividad y el diseño ya contiene `ultima_actividad`.

La configuración evita fijar estos valores en el código y permite ajustarlos sin cambiar el contrato. La semántica de si los 7 días corresponden a cada refresh rotado o a la familia completa de sesión queda señalada como confirmación de producto; la propuesta inicial es TTL absoluto por refresh emitido, sin revivir un refresh revocado.

### 4. Error genérico de login

Se propone el mensaje exacto **`Correo o contraseña inválidos`**, con HTTP 401 y el mismo cuerpo tanto para un correo inexistente como para una contraseña incorrecta. Así se evita revelar la existencia de una cuenta.

PB-001 ya establece el patrón de constantes de dominio (`DUPLICATE_EMAIL_MESSAGE = "Ya existe una cuenta con este correo"`). PB-002 debe agregar una constante paralela, por ejemplo `INVALID_CREDENTIALS_MESSAGE`, en lugar de duplicar el literal en el router. No se reutiliza el mensaje de duplicado porque su claridad deliberada es adecuada para registro, pero sería una filtración en login.

### 5. Inactividad, rotación y logout

El login crea una fila de sesión con `ultima_actividad` inicializada a la hora de emisión. Una ruta protegida actualiza esa marca si la sesión aún está dentro de la ventana. El refresh valida hash, estado, expiración e inactividad; luego revoca el registro anterior y emite el reemplazo. Logout revoca el refresh recibido y no devuelve información que permita confirmar si otro refresh pertenece a una cuenta.

El access JWT tiene una vida máxima de 15 minutos. La revocación exigida por HU-002 se garantiza para el refresh y su reutilización; la invalidación inmediata de un access ya emitido debe quedar explicitada en el diseño del vínculo entre JWT y `sesion`, porque un JWT autocontenido no puede revocarse por sí solo.

## Criterios de aceptación del slice

1. **Credenciales válidas:** una cuenta activa registrada con PB-001 recibe un access JWT y un refresh opaco; no se expone el hash del refresh.
2. **Refresh rotatorio y revocable:** un refresh válido produce un nuevo par, revoca el anterior y rechaza el uso posterior del anterior.
3. **Inactividad:** una sesión con actividad dentro de los 30 minutos puede continuar; una sesión sin actividad durante más de 30 minutos se rechaza y no puede renovarse.
4. **No enumeración:** correo inexistente y contraseña incorrecta responden con HTTP 401 y exactamente `Correo o contraseña inválidos`.
5. **Logout:** el refresh activo queda revocado y su reutilización responde como sesión inválida.
6. **Ruta protegida:** `/auth/me` devuelve la identidad de una sesión válida y rechaza credenciales ausentes, malformadas, expiradas o asociadas a una sesión inválida.

## Áreas afectadas e impacto

- **Identity:** reutiliza `UserRepository.buscar_por_correo`, `Argon2PasswordHasher.verify`, la normalización de correo y los patrones existentes de DI, servicios, schemas y manejo de errores.
- **Core/configuración:** incorpora firma/verificación JWT y settings de seguridad sin mover la responsabilidad al módulo de identidad de forma ad hoc.
- **Persistencia:** agrega la tabla `sesion`, su FK, índice, restricción única y migración dependiente de `usuario_global`.
- **API cliente:** habilita el contrato que consumirán las futuras pantallas; no cambia todavía la navegación ni el catálogo.
- **Pruebas:** extiende el patrón de fakes, `dependency_overrides` y `TestClient` de `tests/test_registro.py`; la integración real con PostgreSQL queda fuera del primer slice.
- **Operaciones y soporte:** habrá que documentar expiración, logout y reautenticación para evitar que un error 401 se interprete como pérdida de cuenta. La limpieza física programada de sesiones se difiere.

## Fuera de alcance

- Pantalla, navegación y almacenamiento de credenciales en la app cliente.
- TOTP administrativo, roles, permisos, membresías y aislamiento multi-tenant específico.
- Verificación real de correo, reenvío de enlaces y recuperación/reset de contraseña.
- Catálogo real y autorización de recursos del catálogo; `/auth/me` es solo una ruta protegida de demostración.
- Detección avanzada o respuesta de seguridad ante robo/reuso de un refresh rotado, más allá del rechazo genérico y el registro técnico que se acuerde.
- Job programado o purga masiva de sesiones inactivas; el slice usa limpieza o invalidación lazy donde corresponda.
- Redis, sesiones completamente stateless o cambio del modelo de autoridad en base de datos.
- Integración con PostgreSQL como requisito de las pruebas unitarias iniciales.

## Riesgos

- **Dependencia JWT no decidida:** implementar antes de confirmar la librería puede producir una API de tokens difícil de mantener. Mitigación: confirmar PyJWT antes de tasks y fijar versión compatible.
- **Revocación de access:** un access JWT autocontenido puede continuar siendo técnicamente válido hasta su `exp` después de logout. Mitigación propuesta: TTL de 15 minutos y definición explícita del vínculo con `sesion` en design; si se exige revocación inmediata, habrá costo de consulta server-side por request.
- **Escritura por request:** actualizar `ultima_actividad` en cada ruta protegida agrega un `UPDATE` por actividad. Para la escala del primer slice se acepta; optimizaciones por lotes se difieren porque podrían romper la semántica sliding.
- **Carrera de rotación:** dos refresh simultáneos pueden competir por el mismo token. Mitigación: operación transaccional, revocación única y rechazo del token anterior; la estrategia exacta de locking queda para design.
- **TTL ambiguo en documentación:** los documentos fijan inactividad, pero no `expira_en`. Mitigación: confirmar TTLs y documentar si los 7 días son por refresh o por familia.
- **Migraciones/entorno:** PostgreSQL real y la migración `0002` aún son deuda del Sprint 1. Mitigación: mantener tests con fakes y probar la migración en el entorno de integración cuando esté disponible.
- **Exposición de secretos:** un secreto JWT ausente o débil comprometería todos los access tokens. Mitigación: secret configurable fuera del código y validación de configuración; el mecanismo de provisión queda para la configuración operativa del proyecto.

## Rollback

Deshabilitar temporalmente los endpoints de autenticación y renovación si el slice falla, preservando las cuentas creadas por PB-001. Revertir código, dependencia, settings y pruebas; en un entorno descartable ejecutar `downgrade` de Alembic para retirar `sesion`. Si la migración ya contiene sesiones, no eliminar datos de forma destructiva: conservar la tabla, revocar las sesiones activas y preparar una migración controlada antes de retirar el esquema.

El rollback no debe modificar ni borrar `usuario_global`, porque PB-002 depende de las cuentas de PB-001. Los clientes deberán reautenticarse una vez restablecido el servicio si se revocan las sesiones.

## Criterios de éxito

- Los criterios 1–6 de este documento cuentan con pruebas TDD reproducibles y pasan en el entorno configurado.
- CP-002 queda cubierto, incluyendo login válido, error no enumerativo, actividad sliding, expiración por inactividad, logout y rechazo del refresh reutilizado.
- La migración crea únicamente el esquema de `sesion` previsto, con FK, unicidad e índice documentados.
- Los refresh tokens no aparecen en persistencia ni logs como texto claro; las respuestas no exponen hashes ni contraseñas.
- El backend ofrece un contrato estable para que la UI de login y el catálogo puedan implementarse después, sin incorporar esas superficies al cambio.
- La rotación y revocación quedan verificadas con dobles de persistencia y la decisión de PyJWT/TTL/mensaje queda registrada antes de tasks.

## Decisiones para el usuario

La propuesta recomienda estas decisiones, pero requiere confirmación antes de cerrar la planificación técnica:

1. **Librería JWT:** ¿se aprueba PyJWT 2.x con access JWT HS256 y refresh opaco hasheado con SHA-256, en lugar de `python-jose`, `authlib` o tokens opacos para ambos?
2. **TTLs:** ¿se aprueban access de 15 minutos, refresh de 7 días e inactividad server-side sliding de 30 minutos? También debe confirmarse si los 7 días aplican a cada refresh rotado o a la familia completa de sesión.
3. **Mensaje genérico:** ¿se aprueba exactamente `Correo o contraseña inválidos` para el 401 de correo inexistente y contraseña incorrecta?

## Preguntas abiertas

- ¿La revocación de logout debe invalidar inmediatamente un access JWT ya emitido, o alcanza con revocar el refresh y limitar el access a 15 minutos? La decisión impacta el costo de consulta a `sesion` por request.
- ¿El reuso de un refresh rotado debe generar solo 401 y logging técnico, o debe revocar toda la familia de sesión? La detección avanzada queda fuera del primer slice.
- ¿La limpieza de sesiones inactivas se mantiene lazy durante login/refresh, o se requiere un job operativo en una entrega posterior?
- ¿Quién será responsable de implementación y pruebas? La ficha mantiene GAP-073.

## Fuentes y trazabilidad

- HU-002 y criterios de aceptación: `docs/scrum/sprint-1/01-sprint-planning.md`, líneas 111–120.
- CP-002 y semántica observable: `docs/scrum/sprint-1/02-proceso-por-hu.md`, §2.1.5.2.
- RF-002 y RNF-006: `docs/scrum/sprint-0-requerimientos/04-requerimientos-iniciales.md`.
- Modelo lógico de `sesion`, estados y secuencia: documentación de S1-02 §2.1.2.2–§2.1.3.
- PB-002, CU-002 y trazabilidad global: `docs/sprint-0/ids-trazabilidad.md` y `06-product-backlog-hu.md`.
- Estado técnico y brecha actual: artefacto de exploración `sdd/autenticacion/explore`.
- Patrón PB-001: `openspec/changes/registro-cliente/proposal.md` y `backend/app/modules/identity/repository.py`.
