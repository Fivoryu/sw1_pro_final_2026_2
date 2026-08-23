# Spec — Registro de cliente con correo y contraseña (backend)

- **Cambio:** `registro-cliente`
- **Product Backlog:** PB-001 · **Historia:** HU-001 — Registro con correo (modo pruebas) · **Caso de uso:** CU-001
- **Slice:** backend (la pantalla de registro de la app cliente es slice posterior del mismo PB-001)
- **Estado:** especiﬁcado (propuesta aprobada 2026-08-23)
- **Dominio OpenSpec:** `identity` (spec completa de dominio nuevo; no existe spec canónica previa)

## Propósito

Definir el comportamiento verificable del slice backend que crea la cuenta global del cliente (`usuario_global`) mediante `POST /api/v1/auth/registro`, con validación de correo y contraseña, unicidad case-insensitive, hash Argon2id, persistencia preparada por migración Alembic y pruebas unitarias. Este slice habilita los ﬂujos posteriores del Sprint 1 (PB-002 y dependientes) sin adelantar login, veriﬁcación de correo ni UI móvil.

## Convenciones

- `DEBE` = MUST/SHALL (RFC 2119); `DEBERÍA` = SHOULD; `PUEDE` = MAY.
- El correo se acepta sin veriﬁcación real (modo pruebas, RF-001); la veriﬁcación real llega con RF-033 en Sprint 3 y reemplazará este modo antes de la demo ﬁnal.
- Códigos de estado HTTP: `201` creación, `422` error de validación, `409` conﬂicto de duplicado.
- Toda aﬁrmación trazable a fuentes del repositorio: ficha HU-001 (`docs/scrum/sprint-1/01-sprint-planning.md` §1.9), diseño lógico (`docs/scrum/sprint-1/02-proceso-por-hu.md` §2.1.2.2), trazabilidad (`docs/sprint-0/ids-trazabilidad.md`) y patrón S0-10 (`docs/scrum/sprint-0-requerimientos/10-patron-de-desarrollo.md`).

---

## REQ-01 — Endpoint `POST /api/v1/auth/registro`

### Qué

El sistema DEBE exponer el endpoint `POST /api/v1/auth/registro` que acepta un cuerpo JSON con `correo` (string con formato de correo) y `password` (string) y responde:

- `201 Created` con cuerpo `{ "id": uuid, "correo": string, "estado": "activo", "correo_verificado": false, "creado_en": timestamptz }`.
- `422 Unprocessable Entity` cuando el cuerpo no es válido (correo malformado o contraseña fuera de política); la cuenta NO se crea.
- `409 Conflict` con el mensaje exacto `Ya existe una cuenta con este correo` cuando el correo ya está registrado; no crea una segunda cuenta.

El endpoint DEBE responder sin exigir veriﬁcación de correo y sin incluir `hash_password` ni la contraseña en ninguna respuesta.

### Por qué

HU-001 requiere que el cliente pueda registrarse con correo (inventado en modo pruebas) y contraseña para probar la plataforma. El contrato API es la primera superﬁcie entregable del backend (backend-first) y la base sobre la que PB-002 (autenticación) construirá. Códigos y mensajes claros son parte de los criterios de aceptación cerrados de la ficha HU-001 (CA3: "mensaje claro").

### Criterios de aceptación verificables

1. Dado un request válido (`correo` con formato de correo, `password` de al menos 8 caracteres), cuando se envía a `POST /api/v1/auth/registro`, entonces responde `201` con `id` UUID, `correo`, `estado: "activo"`, `correo_verificado: false` y `creado_en` con sello de tiempo — sin campos de contraseña ni hash. (HU-001 CA1, CA2, CA4; §2.1.2.2)
2. Dado un request con `correo` sin formato válido (p. ej. `"no-es-correo"`), cuando se envía al endpoint, entonces responde `422` y no se crea ninguna cuenta. (Proposal CA5)
3. Dado un request con `password` de 7 caracteres o menos, cuando se envía al endpoint, entonces responde `422` y no se crea ninguna cuenta. (Proposal CA5)
4. Dado un correo ya registrado, cuando se repite el registro con el mismo correo, entonces responde `409` con el mensaje exacto `Ya existe una cuenta con este correo` y la cantidad de cuentas no cambia. (HU-001 CA3; Proposal CA3)
5. Dado un correo válido aunque inventado (p. ej. `prueba@ejemplo.inv`), cuando se registra, entonces el endpoint responde `201` sin solicitar veriﬁcación ni enviar enlace de activación. (RF-001; HU-001 CA1)

### Referencias

HU-001 (CA1–CA4) · RF-001 · CU-001 · PB-001 · BR-001 · §2.1.2.2 `usuario_global`

---

## REQ-02 — Normalización de correo a minúsculas y unicidad case-insensitive

### Qué

El servicio DEBE normalizar el correo a minúsculas (sin espacios en los extremos) antes de validar unicidad y antes de persistir. La tabla `usuario_global` DEBE respaldar la unicidad con una restricción `UNIQUE(correo)`; un intento de insertar un correo que ya existe (en cualquier combinación de mayúsculas/minúsculas) DEBE rechazarse con `409` y el mensaje de REQ-01, sin crear cuenta.

### Por qué

La decisión de negocio del 2026-08-23 (ronda de preguntas) cerró la normalización a minúsculas para que los duplicados no distingan mayúsculas de minúsculas, evitando cuentas múltiples para un mismo correo real. El diseño lógico §2.1.2.2 ya fija `correo VARCHAR(255) UNIQUE`.

### Criterios de aceptación verificables

1. Dado un registro con `Usuario@Example.com`, cuando se consulta el valor persistido, entonces el correo almacenado es `usuario@example.com` (minúsculas). (Proposal Regla 3)
2. Dado que existe la cuenta `usuario@example.com`, cuando se intenta registrar `Usuario@Example.com`, entonces responde `409` con `Ya existe una cuenta con este correo` y no se crea una segunda cuenta. (Proposal CA3)
3. Dado el mismo correo ingresado dos veces con distinta caja, cuando se normaliza, entonces el resultado es idéntico en ambos casos (normalización idempotente y aplicada en la capa de servicio, no solo en la base de datos). (Exploración: decisión de capa de servicio)

### Referencias

HU-001 (CA3) · RF-001 · BR-001 · §2.1.2.2 (UNIQUE(`correo`)) · Decisión 2026-08-23

---

## REQ-03 — Política de contraseña en modo pruebas

### Qué

El sistema DEBE exigir que `password` tenga al menos 8 caracteres. En modo pruebas, la contraseña NO DEBE exigir mayúscula, número, símbolo ni ninguna otra regla de complejidad. La contraseña DEBE conservarse exactamente como se envía para el hasheo (sin trunca-miento, transformación ni eliminación de caracteres).

### Por qué

La ficha HU-001 ﬁja como único requisito "contraseña de mínimo 8 caracteres"; la propuesta aprobada conﬁrma que no hay requisitos extra de complejidad en este modo, para no bloquear el recorrido de pruebas. La política podrá endurecerse en fases posteriores sin cambiar este contrato.

### Criterios de aceptación verificables

1. Dado un request con `password` de exactamente 8 caracteres (p. ej. `12345678`), cuando se registra, entonces responde `201`. (HU-001 CA1)
2. Dado un request con `password` de 7 caracteres o menos, cuando se registra, entonces responde `422` y no crea cuenta. (Proposal CA5)
3. Dado un request con `password` de 8 caracteres solo minúsculas (p. ej. `password`), cuando se registra en modo pruebas, entonces responde `201`; no se exige complejidad adicional. (Proposal Regla 4)
4. Dado un `password` con espacios internos o caracteres especiales válidos, cuando se hashea, entonces el hash se genera sobre el valor exacto recibido. (Proposal Regla 4)

### Referencias

HU-001 (CA1) · RF-001 · Proposal Reglas 4 y 7

---

## REQ-04 — Hash Argon2id; nunca en claro ni en respuestas

### Qué

El sistema DEBE almacenar la contraseña únicamente como hash Argon2id (con salt generado por la propia primitiva). El valor persistido DEBE ser distinto de la contraseña original y DEBE poder veriﬁcarse con el algoritmo de veriﬁcación de Argon2id. El sistema NO DEBE persistir, responder ni registrar la contraseña o el hash en texto claro; ninguna respuesta (éxito o error) DEBE contener `hash_password` ni la contraseña.

### Por qué

Es el criterio de aceptación CA4 de HU-001 ("la contraseña se almacena con Argon2id; nunca en claro") y la base de seguridad de identidad del proyecto (Argon2id también ﬁjado en RF-002/RNF-006 para autenticación; este slice entrega la parte de registro).

### Criterios de aceptación verificables

1. Dado un registro exitoso con `password` conocida, cuando se inspecciona la ﬁla persistida de `usuario_global`, entonces `hash_password` es distinto de la contraseña original y el algoritmo de veriﬁcación de Argon2id acepta `(password, hash)` como válido. (HU-001 CA4)
2. Dado cualquier respuesta del endpoint (201, 422 y 409), cuando se inspecciona el cuerpo, entonces no contiene la clave `hash_password` ni la contraseña. (Proposal CA4)
3. Dado un registro exitoso cuyo hash se inspecciona, cuando se compara con el hash de una contraseña distinta, entonces la veriﬁcación rechaza la contraseña incorrecta. (HU-001 CA4)
4. Dado el registro en modo de log de aplicación, cuando se emiten entradas del ﬂujo de registro, entonces no DEBE aparecer la contraseña ni el hash en el texto logueado. (Proposal Regla 7)

### Referencias

HU-001 (CA4) · RF-002 (Argon2id) · RNF-006 (baseline seguridad) · §2.1.2.2 (`hash_password`)

---

## REQ-05 — Persistencia de `usuario_global` y migración Alembic inicial

### Qué

El sistema DEBE persistir la cuenta en la tabla `usuario_global` con:

| Columna | Tipo | Restricción |
| --- | --- | --- |
| `id` | UUID | PK, default `gen_random_uuid()` |
| `correo` | VARCHAR(255) | NOT NULL, UNIQUE |
| `hash_password` | VARCHAR(255) | NOT NULL |
| `estado` | VARCHAR(20) | NOT NULL, default `activo` |
| `correo_verificado` | BOOLEAN | NOT NULL, default `false` |
| `creado_en` | TIMESTAMPTZ | NOT NULL, default `now()` |

El sistema DEBE incluir una migración Alembic inicial que cree únicamente esta tabla (cubre el GAP-092 de forma parcial: las demás tablas del Sprint 1 quedan fuera de este cambio). La tabla NO debe tener borrado físico activo en este slice (la desactivación es el mecanismo previsto, RNF-009). La tabla `sesion` NO se crea en este cambio (es de PB-002).

### Por qué

El diseño lógico §2.1.2.2 ﬁja la estructura y defaults (estado `activo`, `correo_verificado=false` que RF-033 exigirá en SP-03). El registro crea la cuenta global única sin membrecía ni tenant (BR-001), y la migración inicial entrega el esquema requerido sin adelantar tablas del slice.

### Criterios de aceptación verificables

1. Dado un entorno con Alembic, cuando se aplica la migración inicial (`upgrade head`), entonces existe la tabla `usuario_global` con las columnas y restricciones de la tabla anterior (incluido UNIQUE(`correo`) y defaults). (Proposal Criterios de éxito 2; §2.1.2.2)
2. Dado el script de migración, cuando se inspecciona su contenido, entonces crea únicamente `usuario_global` y no incluye `sesion` ni las demás tablas del Sprint 1. (Proposal Alcance; GAP-092)
3. Dado un registro exitoso, cuando se consulta la ﬁla creada, entonces `estado = 'activo'`, `correo_verificado = false` y `creado_en` tiene el sello de tiempo de creación. (HU-001 CA2; §2.1.2.2)
4. Dado un entorno descartable, cuando se ejecuta `downgrade base`, entonces la tabla `usuario_global` desaparece sin afectar otras tablas. (Proposal Rollback)
5. Dado el registro, cuando termina, entonces no se crea ninguna memb recía, tenant ni permiso asociado. (BR-001; Proposal Usuarios y actores)

### Referencias

HU-001 (CA2) · RF-001 · BR-001 · RNF-009 · §2.1.2.2 · GAP-092

---

## REQ-06 — Estructura de módulo `identity` según patrón S0-10

### Qué

El sistema DEBE organizar el slice como módulo de identidad dentro del monolito modular FastAPI (patrón S0-10) con separación de responsabilidades: `router.py` (endpoint HTTP), `schemas.py` (contratos request/response), `service.py` (normalización, validación de duplicado, hasheo y orquesta de persistencia), `repository.py` (acceso a `usuario_global`) y `models.py` (modelo SQLAlchemy). El router DEBE registrarse en la aplicación bajo el prefijo `/api/v1` y la conﬁguración (URL de base de datos, parámetros de hash y demás valores de entorno) DEBE leerse de `.env`/variables de entorno, nunca hardcodeada.

### Por qué

El patrón S0-10 establece el monolito modular por dominios y la conﬁguración por entorno como convención del proyecto; mantener la estructura desde el primer slice evita deuda y facilita que PB-002 (autenticación) reutilice el mismo módulo.

### Criterios de aceptación verificables

1. Dado el árbol del backend, cuando se inspecciona el módulo `identity`, entonces existen los archivos `router.py`, `schemas.py`, `service.py`, `repository.py` y `models.py`, cada uno con su responsabilidad (sin lógica de persistencia mezclada en `router.py`). (S0-10; Exploración estructura)
2. Dado el arranque de la aplicación, cuando se consulta la ruta, entonces `POST /api/v1/auth/registro` está disponible (el router está registrado bajo `/api/v1`). (REQ-01; S0-10)
3. Dado un entorno con valores de conﬁguración distintos (p. ej. URL de DB de pruebas), cuando se inicia la aplicación, entonces los valores provienen de la conﬁguración de entorno y no de constantes del código. (S0-10: conﬁguración solo por `.env`)
4. Dado el código del slice, cuando se busca la cadena de conexión o parámetros sensibles, entonces no aparecen hardcodeados en el código fuente. (S0-10)

### Referencias

S0-10 (arquitectura y convenciones) · Exploración (estructura de módulo) · REQ-01

---

## REQ-07 — Pruebas unitarias mínimas con pytest

### Qué

El sistema DEBE incluir pytest como dependencia de desarrollo (junto con el soporte de cliente HTTP de pruebas, p. ej. `httpx`/TestClient de FastAPI, agregados en el primer commit de código). DEBEN existir al menos 6 casos de prueba unitaria que cubran: (1) registro válido → 201 con campos esperados; (2) correo inválido → 422 y cuenta no creada; (3) contraseña corta → 422; (4) duplicado (incluida variante con mayúsculas) → 409 con el mensaje exacto; (5) hash persistido distinto del plaintext y veriﬁcable con Argon2id; (6) ninguna respuesta expone `hash_password`. Los 5 criterios de aceptación de la propuesta DEBEN tener cobertura de prueba reproducible. Las pruebas NO DEBEN depender de una instancia PostgreSQL real (usar dobles o base de pruebas en memoria) mientras el entorno Docker/Floci no esté disponible.

### Por qué

El criterio de éxito de la propuesta exige pruebas unitarias reproducibles y en verde para los cinco criterios de aceptación; el sprint exige CI verde y DoD con pruebas (S0-10, PB-049). pytest no está instalado aún — su incorporación es parte de este cambio (riesgo identiﬁcado en la propuesta y la exploración).

### Criterios de aceptación verificables

1. Dado el entorno con dependencias de desarrollo instaladas, cuando se ejecuta `pytest`, entonces los 6 casos mínimos corren y pasan en verde. (Proposal Criterios de éxito 1)
2. Dado el caso "registro válido", cuando se ejecuta la suite, entonces veriﬁca `201`, campos de respuesta presentes, correo normalizado a minúsculas, `estado` activo y `correo_verificado=false`. (HU-001 CA1/CA2; REQ-01/02/05)
3. Dado el caso "duplicado con mayúsculas", cuando se ejecuta la suite, entonces veriﬁca `409` con el mensaje exacto `Ya existe una cuenta con este correo`. (HU-001 CA3; REQ-01/02)
4. Dado el caso "hash", cuando se ejecuta la suite, entonces veriﬁca que el valor persistido difiere del plaintext y que `verify(password, hash)` de Argon2id es exitoso. (HU-001 CA4; REQ-04)
5. Dado el caso "respuesta sin hash", cuando se ejecuta la suite, entonces veriﬁca que ninguna respuesta contiene `hash_password`. (Proposal CA4; REQ-04)
6. Dado un entorno sin PostgreSQL (por ejemplo CI o máquina sin Docker), cuando se ejecuta la suite, entonces los tests corren sin requerir servicios externos. (Proposal Riesgos: entorno Docker/Floci pendiente)

### Referencias

HU-001 (CA1–CA4) · S0-10 (pruebas) · PB-049 (CI verde) · Proposal (Criterios de éxito, Riesgos)

---

## Matriz de trazabilidad

| REQ | Comportamiento veriﬁcable | HU-001 CA | RF / BR / RNF | Fuente documental |
| --- | --- | --- | --- | --- |
| REQ-01 | Endpoint POST /api/v1/auth/registro con 201/422/409 y mensaje de duplicado | CA1, CA2, CA3, CA4 | RF-001, BR-001 | 01-sprint-planning §1.9; ids-trazabilidad |
| REQ-02 | Normalización a minúsculas y unicidad case-insensitive | CA3 | RF-001, BR-001 | 02-proceso-por-hu §2.1.2.2; decisión 2026-08-23 |
| REQ-03 | Contraseña mínima de 8 caracteres, sin complejidad extra en pruebas | CA1 | RF-001 | 01-sprint-planning §1.9; proposal regla 4 |
| REQ-04 | Hash Argon2id; sin plaintext, sin hash en respuestas ni logs | CA4 | RF-002, RNF-006 | 01-sprint-planning §1.9; §2.1.2.2 |
| REQ-05 | Tabla `usuario_global` (UUID, UNIQUE correo, estados, timestamps) + migración Alembic | CA2 | RF-001, BR-001, RNF-009 | 02-proceso-por-hu §2.1.2.2; GAP-092 |
| REQ-06 | Módulo `identity` con router/schemas/service/repository/models; conﬁg por `.env` | — | S0-10 | 10-patron-de-desarrollo |
| REQ-07 | pytest + 6 casos unitarios mínimos, reproducibles sin PostgreSQL | CA1–CA4 | S0-10, PB-049 | proposal (criterios de éxito, riesgos) |

## Riesgos y gaps abiertos para la implementación

- **pytest no instalado (riesgo conocido):** el primer commit de código DEBE agregar `pytest` y el cliente HTTP de pruebas como dependencias de desarrollo; hasta entonces la suite no puede ejecutarse (REQ-07 asume su incorporación).
- **GAP-092:** la migración Alembic de este cambio cubre solo `usuario_global`; las 13 tablas restantes del Sprint 1 quedan pendientes por diseño.
- **Entorno Docker/Floci pendiente:** sin PostgreSQL local no hay prueba de integración real del 409 transaccional; queda mitigado por dobles de persistencia en tests unitarios (REQ-07 CA6).
- **GAP-073:** responsable de implementación y pruebas aún sin asignar.
- **Modo pruebas vs. ﬁnal:** aceptar correos inventados es deliberado (RF-001); RF-033 debe reemplazarlo en Sprint 3 — no debe tratarse como comportamiento deﬁnitivo.
- **Nota de formato OpenSpec:** la spec se entrega en la ruta plana `openspec/changes/registro-cliente/spec.md` (instrucción del orquestador) como spec completa de dominio nuevo; al archivar podrá sembrar `openspec/specs/identity/spec.md`.
