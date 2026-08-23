# Propuesta: Registro de cliente con correo y contraseña

- **Cambio:** `registro-cliente`
- **Product Backlog:** PB-001
- **Historia:** HU-001 — Registro con correo (modo pruebas)
- **Slice:** backend
- **Estado:** propuesta

## Problema y contexto

RoomForge necesita crear la cuenta global del cliente para habilitar los flujos posteriores del Sprint 1. En modo pruebas se debe poder registrar un correo inventado, sin bloquear el recorrido por un correo de verificación real. Hoy el repositorio no cuenta todavía con la base backend implementada para este flujo; por eso se propone entregar primero el contrato API, la persistencia y las pruebas. La pantalla de registro de la app cliente queda para un slice posterior del mismo PB-001.

La ausencia de verificación es deliberada para la demo y las pruebas. La verificación real se incorporará posteriormente mediante RF-033, en Sprint 3.

## Usuarios y actores

- **Cliente global:** persona que crea una cuenta única para probar y utilizar la plataforma.
- **Backend de RoomForge:** valida los datos, crea la cuenta global y devuelve el resultado del registro.

El registro no crea tenant, membresía ni permisos.

## Objetivo y resultados esperados

Entregar un slice backend FastAPI que permita registrar un cliente mediante un endpoint de registro, con persistencia PostgreSQL preparada por una migración Alembic inicial para `usuario_global` y pruebas unitarias con pytest.

Resultado esperado:

- Un correo válido y una contraseña de al menos 8 caracteres crean una cuenta activa.
- El correo se persiste normalizado a minúsculas y la unicidad no distingue mayúsculas de minúsculas.
- La cuenta queda con `correo_verificado = false` en modo pruebas.
- La contraseña se almacena únicamente como hash Argon2id.
- Un correo duplicado responde HTTP 409 con el mensaje: `Ya existe una cuenta con este correo`.
- La respuesta de creación no expone el hash de contraseña.

## Reglas de negocio y decisiones tomadas

1. **Registro en modo pruebas — RF-001:** se acepta un correo de formato válido, incluso inventado, sin exigir verificación de correo.
2. **Cuenta global única — BR-001:** el registro crea un único `usuario_global`; no crea una membresía ni un tenant.
3. **Normalización de correo:** antes de validar unicidad y persistir, el correo se convierte a minúsculas. Los duplicados son insensibles a mayúsculas y minúsculas.
4. **Contraseña en pruebas:** la única política de este slice es longitud mínima de 8 caracteres. No se exige mayúscula, número ni otro requisito de complejidad.
5. **Duplicados:** un correo ya registrado se rechaza con HTTP 409 y el mensaje claro `Ya existe una cuenta con este correo`.
6. **Estado inicial:** la cuenta se crea activa y sin confirmación de correo (`correo_verificado = false`).
7. **Seguridad:** la contraseña se hashea con Argon2id; nunca se persiste, responde o registra en texto claro.
8. **RNF-006:** TOTP y sesión inactiva de 30 minutos pertenecen a autenticación/PB-002; no se implementan aquí.
9. **RNF-009:** no se agrega borrado físico de cuentas; el ciclo de anonimización de transacciones se mantiene para el diseño posterior.
10. **RNF-017:** los enlaces de activación de un solo uso corresponden a la verificación real de RF-033 y a invitaciones posteriores. Este slice no envía contraseñas por correo ni implementa verificación.

Fuentes principales: ficha HU-001 de `docs/scrum/sprint-1/01-sprint-planning.md` §1.9; tabla `usuario_global` y estados de registro en `docs/scrum/sprint-1/02-proceso-por-hu.md` §2.1.2.2 y §2.1.3; `docs/sprint-0/ids-trazabilidad.md` (RF-001, BR-001, RNF-006, RNF-009 y RNF-017); y patrón S0-10 en `docs/scrum/sprint-0-requerimientos/10-patron-de-desarrollo.md`.

## Alcance incluido

- Bootstrap del backend FastAPI siguiendo el patrón de monolito modular, con módulo de identidad.
- Endpoint de registro `POST /api/v1/auth/registro` con validación de correo y contraseña.
- Normalización a minúsculas, control de duplicados y respuestas 201, 409 y 422 según corresponda.
- Modelo y migración Alembic inicial de `usuario_global`, incluyendo UUID, correo único, hash, estado, `correo_verificado` y fecha de creación.
- Hash Argon2id y respuesta sin campos sensibles.
- Dependencias y pruebas unitarias con pytest; agregar pytest y el soporte HTTP de pruebas en el primer commit de código si aún no están instalados.

## Alcance excluido

- Pantalla y navegación de registro en la app cliente; queda como slice posterior de PB-001.
- Login, JWT, refresh, logout, sesiones y control de inactividad de 30 minutos (PB-002).
- Verificación real de correo, reenvío y enlaces de activación (RF-033, Sprint 3).
- TOTP administrativo (RNF-006).
- Tenants, membresías, permisos y onboarding.
- Tabla `sesion` y migraciones de las demás tablas del Sprint 1.
- Integración real contra PostgreSQL en Docker/Floci; queda pendiente del entorno de integración.

## Criterios de aceptación

Derivados de la ficha HU-001 y adaptados a la superficie backend:

1. **Registro válido:** dado un correo de formato válido, aunque sea inventado, y una contraseña de mínimo 8 caracteres, el endpoint crea la cuenta y responde exitosamente sin exigir verificación.
2. **Cuenta activa:** después de un registro exitoso, la cuenta queda en estado `activo` y `correo_verificado` es `false`.
3. **Correo duplicado:** al repetir el registro con el mismo correo, incluyendo una variante de mayúsculas, el endpoint no crea otra cuenta, responde HTTP 409 y muestra `Ya existe una cuenta con este correo`.
4. **Contraseña segura:** la persistencia contiene un hash Argon2id distinto de la contraseña original, y ninguna respuesta contiene `hash_password` ni la contraseña en claro.
5. **Validaciones:** un correo inválido o una contraseña menor de 8 caracteres se rechazan con error de validación y no crean una cuenta.

## Riesgos y gaps

- **pytest no instalado:** agregar pytest y `httpx`/soporte de cliente de pruebas al primer commit de código; mientras tanto, la ejecución de pruebas está bloqueada.
- **GAP-092 — migraciones:** las migraciones del Sprint 1 están pendientes; este cambio cubre únicamente la migración inicial de `usuario_global`.
- **Entorno Docker/Floci pendiente:** sin PostgreSQL local, la prueba de integración real y la validación transaccional del 409 quedan diferidas; se mitigan inicialmente con pruebas unitarias y dobles de persistencia.
- **GAP-073:** responsable de implementación y pruebas aún no asignado.
- **Riesgo de producto:** aceptar correos inventados es apropiado para pruebas, pero no debe confundirse con el comportamiento final; RF-033 debe reemplazar este modo antes de la demo final.

## Rollback

Revertir el código, dependencias y pruebas del slice. En entornos descartables, aplicar `downgrade` de Alembic para retirar la tabla `usuario_global`. Si la migración ya contiene datos, deshabilitar el endpoint y conservar la tabla hasta definir una migración controlada; no eliminar cuentas ni datos de forma destructiva.

## Criterios de éxito

- Los cinco criterios de aceptación tienen pruebas unitarias reproducibles y pasan en el entorno configurado.
- La migración inicial crea el esquema requerido para `usuario_global` sin incluir tablas fuera del slice.
- La API no expone contraseñas ni hashes y el duplicado devuelve el código y mensaje acordados.
- El backend queda listo para que PB-002 dependa de la cuenta global, sin adelantar login ni UI móvil.

## Ronda de preguntas de propuesta

Las preguntas de negocio consideradas fueron: qué habilita el registro ahora, quién lo usa en la demo, qué validaciones y política de contraseña aplican, cómo se trata un duplicado y qué debe quedar fuera del primer slice. Las decisiones recibidas el 2026-08-23 cierran esas definiciones: backend primero, correo normalizado a minúsculas, mínimo de 8 caracteres, duplicado con 409 y mensaje claro, sin verificación ni UI móvil en este cambio. No se requiere una segunda ronda.

## Preguntas abiertas restantes

**Ninguna** de producto para este slice. Permanecen los gaps operativos indicados arriba, especialmente GAP-073 y la disponibilidad del entorno Docker/Floci.
